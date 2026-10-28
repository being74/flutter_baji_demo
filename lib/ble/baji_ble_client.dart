import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus_ohos/flutter_blue_plus_ohos.dart';

import '../core/baji_log.dart';
import '../core/platform.dart';
import '../protocol/baji_protocol.dart';

sealed class BleConnectionState {
  const BleConnectionState();
}

class BleDisconnected extends BleConnectionState {
  const BleDisconnected();
}

class BleConnecting extends BleConnectionState {
  const BleConnecting();
}

class BleConnected extends BleConnectionState {
  const BleConnected({
    required this.name,
    required this.address,
    required this.mtu,
    required this.notifications,
    required this.canRead,
  });

  final String? name;
  final String address;
  final int mtu;
  final bool notifications;
  final bool canRead;
}

class BleFailed extends BleConnectionState {
  const BleFailed(this.message);

  final String message;
}

class DisconnectEvent {
  const DisconnectEvent({
    required this.address,
    required this.status,
    required this.localInitiated,
    required this.cause,
  });

  final String? address;
  final int status;
  final bool localInitiated;
  final String cause;
}

/// 单服务单特征值的 GATT 客户端。
///
/// - 写入统一使用 write without response，所有 GATT 操作串行化；
/// - 连接后先协商 MTU，再尝试打开 notify/indicate，失败时降级为主动 read；
/// - 设备上报的原始帧通过 [incoming] 抛出，由上层做协议解析。
class BajiBleClient {
  BajiBleClient();

  static const int _defaultMtu = 23;
  static const int _requestedMtu = 517;
  static const int _attHeaderSize = 3;

  static const Duration _connectTimeout = Duration(seconds: 20);
  static const Duration _notifyTimeout = Duration(seconds: 3);
  static const Duration _writeTimeout = Duration(seconds: 15);
  static const Duration _readTimeout = Duration(seconds: 3);
  static const Duration _writeChunkGap = Duration(milliseconds: 2);
  static const Duration _connectRetryDelay = Duration(milliseconds: 600);
  static const Duration _localDisconnectWindow = Duration(seconds: 5);
  static const int _maxConnectAttempts = 3;

  final ValueNotifier<BleConnectionState> state =
      ValueNotifier<BleConnectionState>(const BleDisconnected());
  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast(sync: true);
  final StreamController<DisconnectEvent> _disconnects =
      StreamController<DisconnectEvent>.broadcast(sync: true);

  Stream<Uint8List> get incoming => _incoming.stream;
  Stream<DisconnectEvent> get disconnects => _disconnects.stream;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _readChar;
  StreamSubscription<List<int>>? _valueSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  int _mtu = _defaultMtu;
  bool _notificationsEnabled = false;
  bool _supportsRead = false;
  bool _localDisconnect = false;
  DateTime? _lastLocalDisconnectAt;
  int _connectionGeneration = 0;

  Future<void> _opQueue = Future<void>.value();

  bool get isConnected => state.value is BleConnected;

  bool get canRead => _supportsRead;

  bool get usesNotifications => _notificationsEnabled;

  int get mtu => _platformMtu;

  int get _platformMtu => _mtu;

  // ------------------------------------------------------------------ connection

  Future<void> connect(String address) async {
    _localDisconnect = false;
    _lastLocalDisconnectAt = null;
    state.value = const BleConnecting();
    BajiLog.instance.info('BLE', '连接 $address');

    Object? lastError;
    for (var attempt = 1; attempt <= _maxConnectAttempts; attempt++) {
      try {
        await _connectOnce(address);
        return;
      } catch (error) {
        lastError = error;
        final retryable = error.toString().contains('133');
        if (attempt < _maxConnectAttempts && retryable) {
          BajiLog.instance.warn(
            'BLE',
            '连接失败（第 $attempt 次，status=133），'
            '${_connectRetryDelay.inMilliseconds}ms 后重试',
          );
          await _disconnectInternal('status=133 重试前清理');
          state.value = const BleConnecting();
          await Future<void>.delayed(_connectRetryDelay);
        } else {
          break;
        }
      }
    }

    final error = lastError ?? StateError('连接失败');
    BajiLog.instance.error('BLE', '连接失败：$error');
    await _disconnectInternal('连接失败清理');
    state.value = BleFailed(error.toString());
    throw error;
  }

  Future<void> _connectOnce(String address) async {
    final generation = ++_connectionGeneration;
    final device = BluetoothDevice.fromId(address);
    _device = device;

    await device.connect(
      timeout: _connectTimeout,
      mtu: null,
      autoConnect: false,
    );
    if (generation != _connectionGeneration) {
      throw StateError('连接已过期');
    }

    var services = device.servicesList;
    if (services.isEmpty) {
      services = await device.discoverServices(timeout: 10);
    }
    if (generation != _connectionGeneration) {
      throw StateError('连接已过期');
    }

    final (write, read) = _resolveCharacteristics(services);
    _writeChar = write;
    _readChar = read;

    _mtu = device.mtuNow;
    if (Platform.isAndroid || isOhos) {
      if (_mtu <= _defaultMtu) {
        try {
          _mtu = await device.requestMtu(_requestedMtu, timeout: 3);
        } catch (error) {
          BajiLog.instance.warn('BLE', 'requestMtu 失败：$error，保持 MTU=$_mtu');
        }
      }
    } else if (_mtu <= _defaultMtu) {
      // iOS 的 MTU 由系统异步协商，插件会轮询上报。
      try {
        _mtu = await device.mtu
            .firstWhere((value) => value > _defaultMtu)
            .timeout(const Duration(seconds: 1));
      } catch (_) {
        // 协商结果确认是 23 时按 20 字节 GATT 分片，保证不超长。
      }
    }
    final required = BajiConfig.maxDataPayload() + 6 + _attHeaderSize;
    if (_mtu < required) {
      BajiLog.instance.warn(
        'BLE',
        'MTU 协商结果 $_mtu 小于单帧所需 $required，大帧将被拆成多次 GATT 写入',
      );
    }

    await _subscribeIncoming(device);
    if (!device.isConnected || generation != _connectionGeneration) {
      throw StateError('连接已断开');
    }

    final name = _deviceName(device, address);
    final effectiveMtu = _platformMtu;
    state.value = BleConnected(
      name: name,
      address: address,
      mtu: effectiveMtu,
      notifications: _notificationsEnabled,
      canRead: _supportsRead,
    );
    BajiLog.instance.info(
      'BLE',
      '已连接 $address，MTU=$effectiveMtu，notify=$_notificationsEnabled，read=$_supportsRead',
    );
  }

  Future<void> _subscribeIncoming(BluetoothDevice device) async {
    final characteristic = _readChar!;
    final properties = characteristic.properties;
    _supportsRead = properties.read;
    _notificationsEnabled = false;

    if (!properties.notify && !properties.indicate) {
      BajiLog.instance.warn('BLE', '读特征值不支持 notify/indicate，降级为主动 read');
      return;
    }

    await _valueSubscription?.cancel();
    _valueSubscription = characteristic.onValueReceived.listen((value) {
      _emitIncoming(Uint8List.fromList(value));
    });

    try {
      await characteristic
          .setNotifyValue(true, timeout: _notifyTimeout.inSeconds)
          .timeout(_notifyTimeout);
      _notificationsEnabled = true;
    } catch (error) {
      _notificationsEnabled = false;
      BajiLog.instance.warn('BLE', '开启 notify 失败：$error，降级为主动 read');
    }

    await _connectionSubscription?.cancel();
    _connectionSubscription = device.connectionState.listen((value) {
      if (value == BluetoothConnectionState.disconnected) {
        _handleDisconnect(device);
      }
    });
  }

  Future<void> disconnect() async {
    _localDisconnect = true;
    _lastLocalDisconnectAt = DateTime.now();
    BajiLog.instance.info('BLE', 'App 主动调用 disconnect()');
    await _serialize(() async => _disconnectInternal('App 主动断开'));
    state.value = const BleDisconnected();
    BajiLog.instance.info('BLE', '已断开');
  }

  Future<void> close() async {
    _localDisconnect = true;
    _lastLocalDisconnectAt = DateTime.now();
    BajiLog.instance.info('BLE', 'App 关闭 BLE 客户端，释放 GATT');
    await _disconnectInternal('关闭客户端');
    await _incoming.close();
    await _disconnects.close();
  }

  void _handleDisconnect(BluetoothDevice device) {
    final local = _localDisconnect &&
        _lastLocalDisconnectAt != null &&
        DateTime.now().difference(_lastLocalDisconnectAt!) < _localDisconnectWindow;
    final reason = device.disconnectReason;
    final status = reason?.code ?? 0;
    final cause = _disconnectCause(status, local, reason?.description);
    final message = '链路断开：$cause（status=$status）';
    BajiLog.instance.warn('BLE', message);

    state.value = const BleDisconnected();
    _disconnects.add(
      DisconnectEvent(
        address: device.remoteId.str,
        status: status,
        localInitiated: local,
        cause: cause,
      ),
    );
    _clearConnection();
  }

  (BluetoothCharacteristic, BluetoothCharacteristic) _resolveCharacteristics(
    List<BluetoothService> services,
  ) {
    BajiLog.instance.info('BLE', '发现 ${services.length} 个服务');
    for (final service in services) {
      BajiLog.instance.info('BLE', 'service ${service.uuid.str128}');
      for (final characteristic in service.characteristics) {
        final properties = characteristic.properties;
        BajiLog.instance.info(
          'BLE',
          '  char ${characteristic.uuid.str128} '
              'read=${properties.read} write=${properties.write} '
              'writeNoResponse=${properties.writeWithoutResponse} '
              'notify=${properties.notify} indicate=${properties.indicate}',
        );
      }
    }

    final allCharacteristics = services.expand((service) => service.characteristics).toList();
    BluetoothService? service;
    for (final candidate in services) {
      if (candidate.uuid.str128 == BajiUuids.service) {
        service = candidate;
        break;
      }
      if (_shortId(candidate.uuid.str128) == 0x0150) {
        service = candidate;
        break;
      }
    }

    BluetoothCharacteristic? write = _characteristicByUuid(service, BajiUuids.write, allCharacteristics);
    BluetoothCharacteristic? read = _characteristicByUuid(service, BajiUuids.read, allCharacteristics);

    // 厂商自定义服务里特征值 UUID 与文档不一致时，仅在唯一候选时按属性回退。
    if (write == null || read == null) {
      final custom = services.where((service) {
        final short = _shortId(service.uuid.str128);
        return short == null || !BajiUuids.standardServiceIds.contains(short);
      });
      final customCharacteristics =
          custom.expand((service) => service.characteristics).toList();
      final writable = <Guid, BluetoothCharacteristic>{};
      final readable = <Guid, BluetoothCharacteristic>{};
      for (final characteristic in customCharacteristics) {
        final properties = characteristic.properties;
        if (properties.write || properties.writeWithoutResponse) {
          writable[characteristic.uuid] = characteristic;
        }
        if (properties.read || properties.notify || properties.indicate) {
          readable[characteristic.uuid] = characteristic;
        }
      }
      if (write == null && writable.length == 1) write = writable.values.first;
      if (read == null && readable.length == 1) read = readable.values.first;
      if (write != null || read != null) {
        BajiLog.instance.warn(
          'BLE',
          '未匹配到文档 UUID，按属性回退：'
              'write=${write?.uuid.str128} read=${read?.uuid.str128}',
        );
      }
    }

    if (write == null || read == null) {
      final dump = services.map((service) => service.uuid.str128).join('; ');
      throw StateError('未找到 0x0150/0x0151/0x0152。设备服务：$dump');
    }
    BajiLog.instance.info(
      'BLE',
      '使用 write=${write.uuid.str128} read=${read.uuid.str128}',
    );
    return (write, read);
  }

  BluetoothCharacteristic? _characteristicByUuid(
    BluetoothService? service,
    String uuid,
    List<BluetoothCharacteristic> all,
  ) {
    final target = _shortId(uuid);
    if (service != null) {
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid.str128 == uuid) return characteristic;
      }
      if (target != null) {
        for (final characteristic in service.characteristics) {
          if (_shortId(characteristic.uuid.str128) == target) return characteristic;
        }
      }
    }
    for (final characteristic in all) {
      if (characteristic.uuid.str128 == uuid) return characteristic;
    }
    if (target != null) {
      for (final characteristic in all) {
        if (_shortId(characteristic.uuid.str128) == target) return characteristic;
      }
    }
    return null;
  }

  // ------------------------------------------------------------------ io

  /// 写入一个完整协议帧；若帧长超过 (MTU-3)，在 GATT 层再切分。
  Future<void> writeFrame(Uint8List frame) => _serialize(
        () => _writeFrameLocked(frame).timeout(_writeTimeout),
      );

  Future<void> _writeFrameLocked(Uint8List frame) async {
    if (state.value is! BleConnected) throw StateError('未连接');
    final characteristic = _writeChar;
    if (characteristic == null) throw StateError('写特征值不可用');

    final maxChunk = (_platformMtu - _attHeaderSize).clamp(20, 512);
    if (frame.length > maxChunk) {
      final times = (frame.length + maxChunk - 1) ~/ maxChunk;
      BajiLog.instance.warn('BLE', '帧 ${frame.length}B 超过 GATT 单包 $maxChunk，分 $times 次写入');
    }
    var offset = 0;
    while (offset < frame.length) {
      final end = offset + maxChunk < frame.length ? offset + maxChunk : frame.length;
      final chunk = Uint8List.sublistView(frame, offset, end);
      await characteristic.write(chunk, withoutResponse: true);
      offset = end;
      await Future<void>.delayed(_writeChunkGap);
    }
  }

  /// 主动读取设备消息；仅当读特征值支持 READ 时可用。
  Future<Uint8List?> read() async {
    if (!_supportsRead) return null;
    return _serialize(() async {
      final characteristic = _readChar;
      if (characteristic == null || state.value is! BleConnected) return null;
      try {
        final value = await characteristic
            .read(timeout: _readTimeout.inSeconds)
            .timeout(_readTimeout);
        return Uint8List.fromList(value);
      } catch (error) {
        BajiLog.instance.warn('BLE', '读特征值失败：$error');
        return null;
      }
    });
  }

  // ------------------------------------------------------------------ internals

  Future<T> _serialize<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _opQueue = _opQueue.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _disconnectInternal(String reason) async {
    BajiLog.instance.info('BLE', '释放 GATT：$reason');
    _connectionGeneration++;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await _valueSubscription?.cancel();
    _valueSubscription = null;
    final device = _device;
    _device = null;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
    _clearConnection();
  }

  void _clearConnection() {
    _writeChar = null;
    _readChar = null;
    _mtu = _defaultMtu;
    _notificationsEnabled = false;
    _supportsRead = false;
  }

  void _emitIncoming(Uint8List value) {
    if (value.isEmpty) return;
    BajiLog.instance.info('BLE', '设备->App ${value.length}B: ${toHex(value)}');
    _incoming.add(value);
  }

  String _deviceName(BluetoothDevice device, String address) {
    final platformName = device.platformName.trim();
    if (platformName.isNotEmpty) return platformName;
    final advertised = device.advName.trim();
    if (advertised.isNotEmpty) return advertised;
    return address;
  }

  String _disconnectCause(int status, bool local, String? nativeDescription) {
    if (local) return 'App 侧刚发起断开（本机主动）';
    if (nativeDescription != null && nativeDescription.isNotEmpty) {
      return nativeDescription;
    }
    return switch (status) {
      0 => '对端正常断开',
      8 => '链路超时（设备断电/休眠/离开范围）',
      19 => '外设主动断开（PEER_USER）',
      20 => '本机协议栈主动断开（LOCAL_HOST）',
      22 => 'LMP 响应超时',
      34 => '连接建立失败',
      133 => 'GATT 错误',
      _ => '未知原因',
    };
  }

  static int? _shortId(String uuid) {
    if (uuid.length != 36) return null;
    const suffix = '-0000-1000-8000-00805f9b34fb';
    if (!uuid.startsWith('0000') || !uuid.endsWith(suffix)) return null;
    return int.tryParse(uuid.substring(4, 8), radix: 16);
  }
}
