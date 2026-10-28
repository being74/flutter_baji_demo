import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../ble/baji_ble_client.dart';
import '../ble/baji_scanner.dart';
import '../core/baji_log.dart';
import '../core/platform.dart';
import '../protocol/baji_protocol.dart';
import '../protocol/command_codec.dart';
import '../protocol/device_message.dart';
import '../protocol/frame_assembler.dart';
import '../protocol/frame_codec.dart';
import '../transfer/baji_transfer_manager.dart';
import '../transfer/transfer_models.dart';
import 'device_state.dart';
import 'reconnect_state.dart';

class BajiValidationException implements Exception {
  const BajiValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 协议会话层：负责连接、握手、指令收发与设备状态汇总。
/// UI 只依赖这个类，不直接接触 GATT。
class BajiRepository {
  BajiRepository() {
    _transferManager = BajiTransferManager(
      sender: ({
        required type,
        required payload,
        required totalPackets,
        required packetIndex,
        required frameNumber,
        logLabel,
      }) =>
          _sendPayload(
        type,
        payload,
        poll: false,
        totalPackets: totalPackets,
        packetIndex: packetIndex,
        frameNumber: frameNumber,
        logLabel: logLabel,
      ),
    );
    _incomingSubscription = ble.incoming.listen(_handleRaw);
    _disconnectSubscription = ble.disconnects.listen(_handleDisconnect);
    ble.state.addListener(_onConnectionState);
  }

  final BajiBleClient ble = BajiBleClient();
  final BajiScanner scanner = BajiScanner();
  late final BajiTransferManager _transferManager;
  final FrameAssembler _assembler = FrameAssembler();

  final ValueNotifier<BleConnectionState> connection = ValueNotifier(const BleDisconnected());
  final ValueNotifier<ReconnectState> reconnect = ValueNotifier(const ReconnectState());
  final ValueNotifier<DeviceState> device = ValueNotifier(const DeviceState());

  StreamSubscription<Uint8List>? _incomingSubscription;
  StreamSubscription<DisconnectEvent>? _disconnectSubscription;

  String? _lastConnectAddress;
  String? _lastConnectName;
  bool _autoReconnectEnabled = false;
  int _reconnectGeneration = 0;
  Future<void>? _reconnectTask;
  Future<void>? _scanReconnectTask;
  StreamSubscription<List<BajiDevice>>? _watchScanSubscription;
  Completer<String?>? _watchScanCompleter;
  bool _closed = false;

  static const Duration _handshakeDelay = Duration(milliseconds: 200);
  static const Duration _responseDelay = Duration(milliseconds: 150);
  static const Set<int> _autoReconnectStatuses = {0, 8, 19, 22};
  static final RegExp _deviceNamePattern = RegExp(r'^[A-Za-z0-9]+$');

  bool get isConnected => ble.isConnected;

  bool get canRead => ble.canRead;

  Stream<List<BajiDevice>> scan() => scanner.scan();

  Future<List<BajiDevice>> bondedDevices() => scanner.bondedDevices();

  void _onConnectionState() {
    connection.value = ble.state.value;
    final state = ble.state.value;
    if (state is BleConnected) {
      BajiLog.instance.info(
        'BLE',
        '通道就绪：notify=${state.notifications} read=${state.canRead}',
      );
    }
  }

  Future<void> connect(String address) async {
    _reconnectGeneration++;
    _autoReconnectEnabled = false;
    _reconnectTask = null;
    _scanReconnectTask = null;
    _cancelWatchScan();
    reconnect.value = const ReconnectState();

    await ble.connect(address);
    _lastConnectAddress = address;
    final state = ble.state.value;
    _lastConnectName = state is BleConnected ? state.name : null;
    _autoReconnectEnabled = true;
    BajiLog.instance.info('会话', '连接成功，自动重连已开启：$address');
    await Future<void>.delayed(_handshakeDelay);
    await _handshake();
  }

  Future<void> disconnect() async {
    _autoReconnectEnabled = false;
    _reconnectGeneration++;
    _reconnectTask = null;
    _scanReconnectTask = null;
    _cancelWatchScan();
    reconnect.value = const ReconnectState();
    BajiLog.instance.info('会话', 'App 请求断开连接，已关闭自动重连');
    await ble.disconnect();
  }

  Future<void> close() async {
    _closed = true;
    _autoReconnectEnabled = false;
    _reconnectGeneration++;
    _reconnectTask = null;
    _scanReconnectTask = null;
    _cancelWatchScan();
    reconnect.value = const ReconnectState();
    await _incomingSubscription?.cancel();
    await _disconnectSubscription?.cancel();
    ble.state.removeListener(_onConnectionState);
    await ble.close();
  }

  void _handleDisconnect(DisconnectEvent event) {
    BajiLog.instance.info(
      '会话',
      '断开事件：${event.cause}（status=${event.status}，local=${event.localInitiated}）',
    );
    // iOS/ohos 的断开码不沿用 Android HCI 语义，断开即尝试重连。
    final eligibleStatus =
        Platform.isIOS || isOhos || _autoReconnectStatuses.contains(event.status);
    if (BajiConfig.autoReconnect &&
        _autoReconnectEnabled &&
        !ble.isConnected &&
        !event.localInitiated &&
        eligibleStatus) {
      _scheduleReconnect(event.address ?? _lastConnectAddress);
    }
  }

  void _scheduleReconnect(String? address) {
    if (address == null || _closed) return;
    if (_reconnectTask != null || _scanReconnectTask != null) return;
    final delays = BajiConfig.autoReconnectDelays;
    if (delays.isEmpty) return;

    final generation = ++_reconnectGeneration;
    _reconnectTask = _runReconnect(address, delays, generation).whenComplete(() {
      _reconnectTask = null;
    });
  }

  Future<void> _runReconnect(
    String address,
    List<Duration> delays,
    int generation,
  ) async {
    for (var index = 0; index < delays.length; index++) {
      if (!_autoReconnectEnabled || generation != _reconnectGeneration) return;
      reconnect.value = ReconnectState(attempt: index + 1, total: delays.length);
      await Future<void>.delayed(delays[index]);
      if (!_autoReconnectEnabled || generation != _reconnectGeneration) return;

      BajiLog.instance.info('会话', '自动重连 ${index + 1}/${delays.length}：$address');
      try {
        await ble.connect(address);
        if (!_autoReconnectEnabled || generation != _reconnectGeneration) return;
        await _handshake();
        _lastConnectAddress = address;
        final state = ble.state.value;
        if (state is BleConnected) _lastConnectName = state.name;
        reconnect.value = const ReconnectState();
        BajiLog.instance.info('会话', '自动重连成功');
        return;
      } catch (error) {
        BajiLog.instance.warn('会话', '自动重连失败：$error');
      }
    }

    if (_autoReconnectEnabled &&
        generation == _reconnectGeneration &&
        BajiConfig.autoReconnectScan) {
      await _watchForDevice(address, generation);
    } else {
      _autoReconnectEnabled = false;
      reconnect.value = const ReconnectState();
      BajiLog.instance.warn('会话', '自动重连次数用尽，已停止');
    }
  }

  /// 盲重连只适合设备快速恢复；设备退出 BLE 后通常不再广播，
  /// 这里改为扫描等待目标地址/名称重新出现，发现广播后再连接。
  Future<void> _watchForDevice(String address, int generation) async {
    if (_scanReconnectTask != null) return;
    _scanReconnectTask = _watchForDeviceInternal(address, generation)
        .whenComplete(() => _scanReconnectTask = null);
    await _scanReconnectTask;
  }

  void _cancelWatchScan() {
    _watchScanSubscription?.cancel();
    _watchScanSubscription = null;
    final completer = _watchScanCompleter;
    _watchScanCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    }
  }

  Future<void> _watchForDeviceInternal(String address, int generation) async {
    reconnect.value = ReconnectState(
      attempt: reconnect.value.total,
      total: reconnect.value.total,
      watching: true,
    );
    BajiLog.instance.info(
      '会话',
      '进入广播监听：等待 $address 重新出现'
          '（最长 ${BajiConfig.autoReconnectScanTimeout.inSeconds}s）',
    );

    final deadline = DateTime.now().add(BajiConfig.autoReconnectScanTimeout);
    while (_autoReconnectEnabled && generation == _reconnectGeneration) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;

      String? targetAddress;
      final completer = Completer<String?>();
      _watchScanCompleter = completer;
      final subscription = scanner.scan().timeout(remaining).listen(
        (devices) {
          if (!_autoReconnectEnabled || generation != _reconnectGeneration) {
            if (!completer.isCompleted) completer.complete(null);
            return;
          }
          for (final candidate in devices) {
            if (candidate.address == address ||
                (_lastConnectName != null &&
                    candidate.name == _lastConnectName)) {
              if (!completer.isCompleted) completer.complete(candidate.address);
              return;
            }
          }
        },
        onError: (Object error) {
          if (!completer.isCompleted) completer.complete(null);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(null);
        },
      );
      _watchScanSubscription = subscription;
      targetAddress = await completer.future;
      await subscription.cancel();
      if (identical(_watchScanSubscription, subscription)) {
        _watchScanSubscription = null;
      }
      if (identical(_watchScanCompleter, completer)) {
        _watchScanCompleter = null;
      }
      if (!_autoReconnectEnabled || generation != _reconnectGeneration) return;
      if (targetAddress == null) break;

      BajiLog.instance.info('会话', '发现目标广播 $targetAddress，尝试重连');
      try {
        await ble.connect(targetAddress);
        if (!_autoReconnectEnabled || generation != _reconnectGeneration) return;
        await _handshake();
        _lastConnectAddress = targetAddress;
        final state = ble.state.value;
        if (state is BleConnected) _lastConnectName = state.name;
        reconnect.value = const ReconnectState();
        BajiLog.instance.info('会话', '广播触发重连成功');
        return;
      } catch (error) {
        BajiLog.instance.warn('会话', '广播触发重连失败：$error');
      }
    }
    _autoReconnectEnabled = false;
    reconnect.value = const ReconnectState();
    BajiLog.instance.warn('会话', '广播监听结束，停止自动重连');
  }

  // ------------------------------------------------------------------ commands

  Future<void> queryActivation() =>
      _sendPayload(BajiCommands.activation, CommandCodec.activationQuery());

  Future<void> queryVersion() =>
      _sendPayload(BajiCommands.version, CommandCodec.versionQuery());

  /// 设备信息没有查询指令，只能等待上报或主动 read。
  Future<void> pollDeviceMessage() async {
    if (!ble.canRead) return;
    final raw = await ble.read();
    if (raw == null) return;
    BajiLog.instance.info('协议', '主动 read 返回 ${raw.length}B: ${toHex(raw)}');
    _handleRaw(raw);
  }

  Future<void> refresh() async {
    await queryActivation();
    await queryVersion();
    await pollDeviceMessage();
  }

  Future<void> replyIdentity(bool valid) async {
    await _sendPayload(BajiCommands.identity, CommandCodec.identityReply(valid));
    device.value = device.value.copyWith(identityVerified: valid);
  }

  Future<void> syncActivationTime([DateTime? time]) => _sendPayload(
        BajiCommands.activationTime,
        CommandCodec.updateActivationTime(time),
      );

  Future<void> updateSettings(int bgLight, int breather, String devName) async {
    if (bgLight < 0 || bgLight > 100 || bgLight % 10 != 0) {
      throw const BajiValidationException('亮度必须是 0~100 且步进 10');
    }
    if (breather < 0 || breather > 3) {
      throw const BajiValidationException('呼吸档位必须是 0~3');
    }
    if (!_deviceNamePattern.hasMatch(devName)) {
      throw const BajiValidationException('设备名只能包含数字和英文');
    }
    await _sendPayload(
      BajiCommands.deviceSettings,
      CommandCodec.setDeviceSettings(bgLight, breather, devName),
    );
  }

  Future<TransferResult> transfer({
    required TransferKind kind,
    required List<TransferFile> files,
    TransferOptions options = const TransferOptions(),
    void Function(TransferProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) =>
      _transferManager.transfer(
        kind: kind,
        files: files,
        options: options,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );

  // ------------------------------------------------------------------ internals

  Future<void> _sendPayload(
    int type,
    Uint8List payload, {
    bool poll = true,
    int totalPackets = 0,
    int packetIndex = 0,
    int frameNumber = 1,
    String? logLabel,
  }) async {
    final frame = FrameCodec.encode(
      head: FrameCodec.headToDevice,
      type: type,
      totalPackets: totalPackets,
      packetIndex: packetIndex,
      payload: payload,
      format: BajiConfig.frameFormat,
    );
    await ble.writeFrame(frame);

    final totalForLog = totalPackets == 0 ? 1 : totalPackets;
    final typeText = type.toRadixString(16).padLeft(2, '0').toUpperCase();
    if (logLabel != null) {
      BajiLog.instance.transfer(
        '协议',
        'App->设备 $logLabel type=0x$typeText frame=$frameNumber/$totalForLog '
            'total=$totalPackets index=$packetIndex len=${payload.length} '
            'frameSize=${frame.length}B: ${toHex(frame)}',
      );
    } else if (poll) {
      BajiLog.instance.info(
        '协议',
        'App->设备 type=0x$typeText frame=$frameNumber/$totalForLog '
            'total=$totalPackets index=$packetIndex len=${payload.length} '
            'frameSize=${frame.length}B: ${toHex(frame)}',
      );
    } else if (BajiConfig.logFileFrames) {
      BajiLog.instance.transferTrace(
        '帧',
        '第 $frameNumber/$totalForLog 帧 type=0x$typeText total=$totalPackets '
            'index=$packetIndex len=${payload.length} frameSize=${frame.length}B: '
            '${toHex(frame)}',
      );
    }
    if (poll && !ble.usesNotifications && ble.canRead) {
      await Future<void>.delayed(_responseDelay);
      final raw = await ble.read();
      if (raw != null) _handleRaw(raw);
    }
  }

  void _handleRaw(Uint8List raw) {
    final frame = FrameCodec.decode(raw);
    if (frame == null) {
      var sum = 0;
      for (final byte in raw) {
        sum = (sum + byte) & 0xFF;
      }
      final head = raw.length >= 8 ? Uint8List.sublistView(raw, 0, 8) : raw;
      final tailStart = raw.length > 8 ? raw.length - 8 : 0;
      final tail = raw.length > tailStart ? Uint8List.sublistView(raw, tailStart) : raw;
      BajiLog.instance.warn(
        '协议',
        '无效帧 size=${raw.length} sum=0x${sum.toRadixString(16)} '
            'head=${toHex(head)} tail=${toHex(tail)}',
      );
      return;
    }
    if (!frame.checksumValid) {
      BajiLog.instance.warn(
        '协议',
        '帧无校验或校验不匹配，按数据域解析 type=0x'
            '${frame.type.toRadixString(16).padLeft(2, '0').toUpperCase()}',
      );
    }
    BajiLog.instance.info(
      '协议',
      '← type=0x${frame.type.toRadixString(16).padLeft(2, '0').toUpperCase()} '
          'total=${frame.totalPackets} index=${frame.packetIndex} '
          'len=${frame.payload.length} '
          'data=${_preview(frame.payload)}',
    );
    final payload = _assembler.offer(frame);
    if (payload == null) return;
    final message = CommandCodec.parse(payload);
    if (message == null) {
      BajiLog.instance.info(
        '协议',
        '未识别 type=0x${frame.type.toRadixString(16).padLeft(2, '0').toUpperCase()} '
            '非 JSON 数据：${_preview(payload)} | hex=${toHex(payload)}',
      );
      return;
    }
    BajiLog.instance.info('协议', '← ${_describe(message)}');
    _apply(message);
  }

  void _apply(DeviceMessage message) {
    switch (message) {
      case ActivationMessage():
        BajiLog.instance.info(
          '协议',
          '激活状态更新：${message.activated ? '已激活(state=1)' : '未激活(state=0)'}',
        );
        device.value = device.value.copyWith(activated: message.activated);
      case VersionMessage():
        device.value = device.value.copyWith(version: message.version);
      case DeviceInfoMessage():
        final current = device.value;
        device.value = DeviceState(
          activated: current.activated,
          version: current.version,
          totalSpace: message.totalSpace ?? current.totalSpace,
          freeSpace: message.freeSpace ?? current.freeSpace,
          devName: message.devName ?? current.devName,
          width: message.width ?? current.width,
          height: message.height ?? current.height,
          roundScreen: message.roundScreen ?? current.roundScreen,
          brand: message.brand ?? current.brand,
          identityCode: current.identityCode,
          identityVerified: current.identityVerified,
        );
      case IdentityCheckMessage():
        device.value = device.value.copyWith(identityCode: message.code);
        BajiLog.instance.info('协议', '设备身份码：${message.code}，自动回复确认');
        unawaited(
          replyIdentity(true).catchError((Object error) {
            BajiLog.instance.warn('协议', '身份核对回复失败：$error');
          }),
        );
      case IdentityResultMessage():
        device.value = device.value.copyWith(identityVerified: message.valid);
      case UnknownMessage():
        BajiLog.instance.info('协议', '未识别消息 type=${message.type}: ${message.raw}');
    }
  }

  Future<void> _handshake() async {
    BajiLog.instance.info('会话', '开始会话握手');
    try {
      await queryActivation();
    } catch (error) {
      BajiLog.instance.warn('会话', '激活查询失败：$error');
    }
    try {
      await queryVersion();
    } catch (error) {
      BajiLog.instance.warn('会话', '版本查询失败：$error');
    }
    try {
      await pollDeviceMessage();
    } catch (error) {
      BajiLog.instance.warn('会话', '读取设备信息失败：$error');
    }
  }

  static String _preview(Uint8List payload) {
    final text = String.fromCharCodes(payload.take(300));
    return text;
  }

  static String _describe(DeviceMessage message) => switch (message) {
        ActivationMessage() => 'Activation(activated: ${message.activated})',
        VersionMessage() => 'Version(version: ${message.version})',
        DeviceInfoMessage() =>
          'DeviceInfo(totalSpace: ${message.totalSpace}, freeSpace: ${message.freeSpace}, '
              'devName: ${message.devName}, width: ${message.width}, height: ${message.height}, '
              'roundScreen: ${message.roundScreen}, brand: ${message.brand})',
        IdentityCheckMessage() => 'IdentityCheck(code: ${message.code})',
        IdentityResultMessage() => 'IdentityResult(valid: ${message.valid})',
        UnknownMessage() => 'Unknown(type: ${message.type}, raw: ${message.raw})',
      };
}
