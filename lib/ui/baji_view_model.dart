import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../ble/baji_ble_client.dart';
import '../ble/baji_scanner.dart';
import '../core/baji_log.dart';
import '../data/baji_repository.dart';
import '../data/device_state.dart';
import '../data/reconnect_state.dart';
import '../media/gif_sampler.dart';
import '../media/image_transforms.dart';
import '../media/media_files.dart';
import '../media/video_frames.dart';
import '../protocol/baji_protocol.dart';
import '../transfer/anim_bin_encoder.dart';
import '../transfer/baji_transfer_manager.dart';
import '../transfer/jpg_bin_encoder.dart';
import '../transfer/marquee_renderer.dart';
import '../transfer/transfer_models.dart';

class TransferUiState {
  const TransferUiState({
    this.running = false,
    this.kind,
    this.fileName = '',
    this.fileIndex = 0,
    this.fileCount = 0,
    this.sentBytes = 0,
    this.totalBytes = 0,
    this.speed = 0,
    this.message,
  });

  final bool running;
  final TransferKind? kind;
  final String fileName;
  final int fileIndex;
  final int fileCount;
  final int sentBytes;
  final int totalBytes;
  final int speed;
  final String? message;

  double get fraction =>
      totalBytes <= 0 ? 0 : (sentBytes / totalBytes).clamp(0.0, 1.0);

  TransferUiState copyWith({
    bool? running,
    TransferKind? kind,
    String? fileName,
    int? fileIndex,
    int? fileCount,
    int? sentBytes,
    int? totalBytes,
    int? speed,
    String? message,
    bool clearMessage = false,
  }) =>
      TransferUiState(
        running: running ?? this.running,
        kind: kind ?? this.kind,
        fileName: fileName ?? this.fileName,
        fileIndex: fileIndex ?? this.fileIndex,
        fileCount: fileCount ?? this.fileCount,
        sentBytes: sentBytes ?? this.sentBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        speed: speed ?? this.speed,
        message: clearMessage ? null : (message ?? this.message),
      );
}

class SettingsUiState {
  const SettingsUiState({
    this.bgLight = 50,
    this.breather = 0,
    this.devName = '',
  });

  final int bgLight;
  final int breather;
  final String devName;

  SettingsUiState copyWith({int? bgLight, int? breather, String? devName}) =>
      SettingsUiState(
        bgLight: bgLight ?? this.bgLight,
        breather: breather ?? this.breather,
        devName: devName ?? this.devName,
      );
}

class AlbumCropUiState {
  const AlbumCropUiState({
    this.image,
    this.fileName = '',
    this.index = 0,
    this.total = 0,
    this.targetSize = 368,
    this.loading = true,
    this.error,
  });

  final ui.Image? image;
  final String fileName;
  final int index;
  final int total;
  final int targetSize;
  final bool loading;
  final String? error;

  AlbumCropUiState copyWith({
    ui.Image? image,
    String? fileName,
    int? index,
    int? total,
    int? targetSize,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      AlbumCropUiState(
        image: image ?? this.image,
        fileName: fileName ?? this.fileName,
        index: index ?? this.index,
        total: total ?? this.total,
        targetSize: targetSize ?? this.targetSize,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

enum AnimationKind { gif, video }

class AnimationSourceUi {
  const AnimationSourceUi({
    required this.path,
    required this.name,
    required this.kind,
    required this.durationMs,
    this.preview,
  });

  final String path;
  final String name;
  final AnimationKind kind;
  final int durationMs;
  final Uint8List? preview;
}

/// “动图”页的采样约束：源最长 3 秒，最多 30 帧。
abstract final class AnimationLimits {
  static const int maxFrames = 30;
  static const int maxDurationMs = 3000;
  static const int minIntervalMs = 100;
  static const int maxIntervalMs = 999;
  static const int defaultIntervalMs = 100;
}

/// “多图轮播”：每张图一帧，最多 30 张。
abstract final class SlideshowLimits {
  static const int maxImages = 30;
  static const int minIntervalMs = 200;
  static const int maxIntervalMs = 999;
  static const int defaultIntervalMs = 500;
}

class BajiViewModel extends ChangeNotifier {
  BajiViewModel(this.repository) {
    repository.connection.addListener(_onConnectionChanged);
    repository.reconnect.addListener(notifyListeners);
    repository.device.addListener(_onDeviceChanged);
    BajiLog.instance.addListener(_onLogsChanged);
  }

  final BajiRepository repository;

  final BajiLog log = BajiLog.instance;

  BleConnectionState _connection = const BleDisconnected();
  ReconnectState get reconnect => repository.reconnect.value;
  DeviceState get device => repository.device.value;
  BleConnectionState get connection => _connection;

  bool _scanning = false;
  bool get scanning => _scanning;

  List<BajiDevice> _devices = const [];
  List<BajiDevice> get devices => _devices;

  List<BajiDevice> _bondedDevices = const [];
  List<BajiDevice> get bondedDevices => _bondedDevices;

  TransferUiState _transfer = const TransferUiState();
  TransferUiState get transfer => _transfer;

  AlbumCropUiState? _albumCrop;
  AlbumCropUiState? get albumCrop => _albumCrop;

  AnimationSourceUi? _animationSource;
  AnimationSourceUi? get animationSource => _animationSource;

  SettingsUiState _settings = const SettingsUiState();
  SettingsUiState get settings => _settings;

  bool _queryingActivation = false;
  bool get queryingActivation => _queryingActivation;

  List<BajiLogEntry> get logs => log.entries;

  void showMessage(String message) => _messages.add(message);

  final StreamController<String> _messages = StreamController<String>.broadcast();
  Stream<String> get messages => _messages.stream;

  StreamSubscription<List<BajiDevice>>? _scanSubscription;
  int _connectToken = 0;
  int _transferToken = 0;
  bool _devNameEdited = false;
  String? _devNameSourceAddress;
  bool _wasConnected = false;

  List<XFile> _albumFiles = [];
  final List<TransferFile> _albumCroppedFiles = [];
  int _albumCropIndex = 0;
  int _lastProgressNotifyMs = 0;

  final Map<String, Future<Uint8List>> _previewCache = {};

  static const int _maxFileBytes = MediaFiles.maxFileBytes;
  static const int _maxCropSource = 1024;
  static const int albumCropSize = 368;
  static const int _previewMaxSize = 720;
  static final RegExp _asciiAlphanumeric = RegExp(r'^[A-Za-z0-9]$');

  void _onConnectionChanged() {
    final state = repository.connection.value;
    final connected = state is BleConnected;
    if (_wasConnected && !connected) {
      _devices = const [];
    }
    if (state is BleConnected && state.address != _devNameSourceAddress) {
      _devNameSourceAddress = state.address;
      _devNameEdited = false;
    }
    _wasConnected = connected;
    _connection = state;
    notifyListeners();
  }

  void _onDeviceChanged() {
    final name = repository.device.value.devName;
    if (!_devNameEdited && name != null && name.trim().isNotEmpty) {
      if (_settings.devName != name) {
        _settings = _settings.copyWith(devName: name);
        notifyListeners();
      }
    }
  }

  void _onLogsChanged() => notifyListeners();

  // ------------------------------------------------------------------ scan

  void toggleScan() {
    if (_scanning) {
      _scanSubscription?.cancel();
      _scanSubscription = null;
      _scanning = false;
      notifyListeners();
      return;
    }
    refreshBondedDevices();
    _scanning = true;
    notifyListeners();
    _scanSubscription = repository.scan().listen(
      (devices) {
        _devices = devices;
        notifyListeners();
      },
      onError: (Object error) {
        _messages.add('扫描失败：$error');
        _scanning = false;
        notifyListeners();
      },
      onDone: () {
        _scanning = false;
        notifyListeners();
      },
    );
  }

  Future<void> refreshBondedDevices() async {
    _bondedDevices = await repository.bondedDevices();
    notifyListeners();
  }

  Future<void> connect(String address) async {
    final token = ++_connectToken;
    try {
      await repository.connect(address);
    } catch (error) {
      if (token == _connectToken) {
        _messages.add('连接失败：$error');
      }
    }
  }

  Future<void> disconnect() async {
    _connectToken++;
    _scanSubscription?.cancel();
    _scanSubscription = null;
    _scanning = false;
    _devices = const [];
    try {
      await repository.disconnect();
    } catch (error) {
      _messages.add('断开失败：$error');
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    try {
      await repository.refresh();
    } catch (error) {
      _messages.add('刷新失败：$error');
    }
  }

  Future<void> queryActivation() async {
    if (_queryingActivation) return;
    _queryingActivation = true;
    BajiLog.instance.info(
      '会话',
      '点击查询激活状态：发送 0x01，当前显示=${device.activated}',
    );
    notifyListeners();
    try {
      await repository.queryActivation();
      // 设备通过 notify 异步回复 0x01，留一点时间让状态刷新。
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      BajiLog.instance.info(
        '会话',
        '激活查询等待结束：当前显示=${device.activated}；'
            '若仍为空/未变化，请查看协议日志中的 ← type=0x01',
      );
    } catch (error) {
      _messages.add('激活查询失败：$error');
    } finally {
      _queryingActivation = false;
      notifyListeners();
    }
  }

  Future<void> syncActivationTime() async {
    try {
      await repository.syncActivationTime();
      _messages.add('激活时间已同步');
    } catch (error) {
      _messages.add('同步失败：$error');
    }
  }

  Future<void> replyIdentity(bool valid) async {
    try {
      await repository.replyIdentity(valid);
    } catch (error) {
      _messages.add('身份核对回复失败：$error');
    }
  }

  // ------------------------------------------------------------------ settings

  void setBgLight(int value) {
    _settings = _settings.copyWith(bgLight: (value ~/ 10 * 10).clamp(0, 100));
    notifyListeners();
  }

  void setBreather(int value) {
    _settings = _settings.copyWith(breather: value.clamp(0, 3));
    notifyListeners();
  }

  void setDevName(String value) {
    _devNameEdited = true;
    final filtered = value.split('').where(_asciiAlphanumeric.hasMatch).join();
    _settings = _settings.copyWith(devName: filtered);
    notifyListeners();
  }

  Future<void> sendSettings() async {
    final current = _settings;
    if (current.devName.trim().isEmpty) {
      _messages.add('请先填写设备名（数字+英文）');
      return;
    }
    try {
      await repository.updateSettings(
        current.bgLight,
        current.breather,
        current.devName,
      );
      _messages.add('设置已发送');
    } catch (error) {
      _messages.add('设置发送失败：$error');
    }
  }

  // ------------------------------------------------------------------ transfer

  void startAlbumTransfer(List<XFile> files) {
    if (files.isEmpty) return;
    beginAlbumCrop(files);
  }

  /// 用户在“动图”页选中 GIF/视频后，后台解析名称、时长与首帧预览。
  Future<void> selectAnimationSource(PickedMedia picked) async {
    if (_transfer.running) return;
    try {
      final isGif = MediaFiles.isGif(picked.name);
      final isVideo = MediaFiles.isVideo(picked.name);
      if (!isGif && !isVideo) throw StateError('请选择 GIF 或视频');
      if (isGif) {
        final bytes = picked.bytes ??
            await _readFileBytes(picked.path, picked.name);
        final duration = await GifSampler.durationMs(bytes);
        _animationSource = AnimationSourceUi(
          path: picked.path,
          name: picked.name,
          kind: AnimationKind.gif,
          durationMs: duration,
        );
      } else {
        final info = await VideoFrames.load(picked.path, maxSize: _previewMaxSize);
        _animationSource = AnimationSourceUi(
          path: picked.path,
          name: picked.name,
          kind: AnimationKind.video,
          durationMs: info.durationMs,
          preview: info.preview,
        );
      }
      _transfer = const TransferUiState();
      notifyListeners();
    } catch (error) {
      _messages.add('读取动图失败：$error');
    }
  }

  /// 上传当前选中的动图；intervalMs 来自“播放速度”滑杆。
  Future<void> startAnimationTransfer(int intervalMs) async {
    final source = _animationSource;
    if (source == null) {
      _messages.add('请先选择 GIF 或视频');
      return;
    }
    final token = ++_transferToken;
    _transfer = const TransferUiState(
      running: true,
      kind: TransferKind.ambience,
      message: '正在提取 JPG 帧…',
    );
    notifyListeners();
    try {
      final safeInterval = intervalMs.clamp(
        AnimationLimits.minIntervalMs,
        AnimationLimits.maxIntervalMs,
      );
      final List<Uint8List> frames;
      if (source.kind == AnimationKind.gif) {
        final bytes = await _readFileBytes(source.path, source.name);
        frames = await GifSampler.sampleFrames(
          bytes,
          intervalMs: safeInterval,
          maxFrames: AnimationLimits.maxFrames,
          maxDurationMs: AnimationLimits.maxDurationMs,
          size: albumCropSize,
        );
      } else {
        frames = await VideoFrames.extract(
          source.path,
          intervalMs: safeInterval,
          maxFrames: AnimationLimits.maxFrames,
          maxDurationMs: AnimationLimits.maxDurationMs,
          size: albumCropSize,
        );
      }
      if (token != _transferToken) return;
      if (frames.isEmpty) throw StateError('没有生成可用帧');
      final bytes = AnimBinEncoder.encode(
        frames: frames,
        width: albumCropSize,
        height: albumCropSize,
        intervalMs: safeInterval,
      );
      BajiLog.instance.info(
        '氛围',
        '${source.name}：${source.kind == AnimationKind.gif ? 'GIF' : '视频'}，'
            '${frames.length} 帧/${safeInterval}ms，bin ${bytes.length}B，'
            'header=${toHex(bytes, maxBytes: 16)}',
      );
      await launchTransfer(
        TransferKind.ambience,
        [
          TransferFile(
            name: source.name,
            bytes: bytes,
            width: albumCropSize,
            height: albumCropSize,
            binWrapped: true,
          ),
        ],
        token: token,
      );
    } catch (error) {
      if (token != _transferToken) return;
      _transfer = TransferUiState(
        kind: TransferKind.ambience,
        message: '提取失败：$error',
      );
      notifyListeners();
    }
  }

  /// 把输入的跑马灯文字渲染成一组静态 JPG 帧，按动图 bin 封装后用 0x05 发送。
  Future<void> startMarqueeTransfer({
    required String text,
    required int fontSize,
    required int textColor,
    required int backgroundColor,
    required MarqueeMode mode,
    required int intervalMs,
  }) async {
    final content = text.trim();
    if (content.isEmpty) {
      _messages.add('请输入跑马灯文字');
      return;
    }
    if (content.length > MarqueeRenderer.maxTextLength) {
      _messages.add('跑马灯文字不超过 ${MarqueeRenderer.maxTextLength} 个字');
      return;
    }
    final safeInterval = intervalMs.clamp(
      AnimationLimits.minIntervalMs,
      AnimationLimits.maxIntervalMs,
    );
    final token = ++_transferToken;
    _transfer = const TransferUiState(
      running: true,
      kind: TransferKind.marquee,
      message: '正在生成跑马灯帧…',
    );
    notifyListeners();
    try {
      final style = MarqueeStyle(
        text: content,
        fontSize: fontSize.clamp(
          MarqueeRenderer.minFontSize,
          MarqueeRenderer.maxFontSize,
        ),
        textColor: textColor,
        backgroundColor: backgroundColor,
        mode: mode,
      );
      final frames = await MarqueeRenderer.renderJpegFrames(style);
      if (token != _transferToken) return;
      if (frames.isEmpty) throw StateError('没有生成可用帧');
      final bin = AnimBinEncoder.encode(
        frames: frames,
        width: albumCropSize,
        height: albumCropSize,
        intervalMs: safeInterval,
      );
      final name = 'marquee_${DateTime.now().millisecondsSinceEpoch}.bin';
      BajiLog.instance.info(
        '跑马灯',
        '$name：${frames.length} 帧/${safeInterval}ms，bin ${bin.length}B',
      );
      await launchTransfer(
        TransferKind.marquee,
        [
          TransferFile(
            name: name,
            bytes: bin,
            width: albumCropSize,
            height: albumCropSize,
            binWrapped: true,
          ),
        ],
        token: token,
      );
    } catch (error) {
      if (token != _transferToken) return;
      _transfer = TransferUiState(
        kind: TransferKind.marquee,
        message: '跑马灯生成失败：$error',
      );
      notifyListeners();
    }
  }

  /// 多图轮播：每张图片居中裁成 368×368 作为一帧，按动图 bin 封装后用 0x05 发送。
  Future<void> startSlideshowTransfer(List<XFile> images, int intervalMs) async {
    if (images.isEmpty) {
      _messages.add('请先选择图片');
      return;
    }
    if (images.length > SlideshowLimits.maxImages) {
      _messages.add('最多选择 ${SlideshowLimits.maxImages} 张图片');
      return;
    }
    final safeInterval = intervalMs.clamp(
      SlideshowLimits.minIntervalMs,
      SlideshowLimits.maxIntervalMs,
    );
    final token = ++_transferToken;
    _transfer = const TransferUiState(
      running: true,
      kind: TransferKind.slideshow,
      message: '正在生成轮播帧…',
    );
    notifyListeners();
    try {
      final frames = <Uint8List>[];
      for (final image in images) {
        final bytes = await MediaFiles.readBytes(image);
        final jpeg = await ImageTransforms.loadSquareJpeg(
          bytes,
          maxSource: _maxCropSource,
          size: albumCropSize,
        );
        frames.add(jpeg);
        if (token != _transferToken) return;
      }
      final bin = AnimBinEncoder.encode(
        frames: frames,
        width: albumCropSize,
        height: albumCropSize,
        intervalMs: safeInterval,
      );
      final name = 'slideshow_${DateTime.now().millisecondsSinceEpoch}.bin';
      BajiLog.instance.info(
        '轮播',
        '$name：${frames.length} 帧/${safeInterval}ms，bin ${bin.length}B',
      );
      await launchTransfer(
        TransferKind.slideshow,
        [
          TransferFile(
            name: name,
            bytes: bin,
            width: albumCropSize,
            height: albumCropSize,
            binWrapped: true,
          ),
        ],
        token: token,
      );
    } catch (error) {
      if (token != _transferToken) return;
      _transfer = TransferUiState(
        kind: TransferKind.slideshow,
        message: '轮播生成失败：$error',
      );
      notifyListeners();
    }
  }

  /// 清空上一次传输结果；正在传输时不打断。
  void clearTransferState() {
    if (!_transfer.running) {
      _transfer = const TransferUiState();
      notifyListeners();
    }
  }

  Future<void> launchTransfer(
    TransferKind kind,
    List<TransferFile> files, {
    required int token,
  }) async {
    if (files.isEmpty) {
      _transfer = TransferUiState(kind: kind, message: '没有可发送的文件');
      notifyListeners();
      return;
    }
    final total = files.fold<int>(0, (sum, file) => sum + file.bytes.length);
    _transfer = TransferUiState(
      running: true,
      kind: kind,
      fileCount: files.length,
      totalBytes: total,
    );
    _lastProgressNotifyMs = 0;
    notifyListeners();

    try {
      final result = await repository.transfer(
        kind: kind,
        files: files,
        options: const TransferOptions(),
        isCancelled: () => token != _transferToken,
        onProgress: (progress) {
          if (token != _transferToken) return;
          _transfer = _transfer.copyWith(
            fileName: progress.fileName,
            fileIndex: progress.fileIndex,
            sentBytes: progress.sentBytes,
            totalBytes: progress.totalBytes,
            speed: progress.bytesPerSecond,
          );
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - _lastProgressNotifyMs >= 100 ||
              progress.sentBytes >= progress.totalBytes) {
            _lastProgressNotifyMs = now;
            notifyListeners();
          }
        },
      );
      if (token != _transferToken) return;
      switch (result) {
        case TransferSuccess():
          _transfer = _transfer.copyWith(running: false, message: '传输完成');
          if (!kind.showsInlineTransferStatus) {
            _messages.add('${kind.title} 传输完成');
          }
          break;
        case TransferFailure():
          _transfer = _transfer.copyWith(
            running: false,
            message: '失败：${result.message}',
          );
          if (!kind.showsInlineTransferStatus) {
            _messages.add('${kind.title} 传输失败：${result.message}');
          }
          break;
      }
    } on TransferCancelled {
      // cancelTransfer 已经写入“已取消”。
    } catch (error) {
      if (token != _transferToken) return;
      _transfer = _transfer.copyWith(
        running: false,
        message: '失败：$error',
      );
      if (!kind.showsInlineTransferStatus) {
        _messages.add('${kind.title} 传输失败：$error');
      }
    }
    notifyListeners();
  }

  void cancelTransfer() {
    _transferToken++;
    _transfer = _transfer.copyWith(running: false, message: '已取消');
    notifyListeners();
  }

  // ------------------------------------------------------------------ album crop

  void beginAlbumCrop(List<XFile> files) {
    _transferToken++;
    _disposeAlbumImage();
    _albumFiles = files;
    _albumCroppedFiles.clear();
    _albumCropIndex = 0;
    _loadAlbumCrop(0);
  }

  Future<void> _loadAlbumCrop(int index) async {
    _albumCropIndex = index;
    _albumCrop = AlbumCropUiState(
      index: index,
      total: _albumFiles.length,
      targetSize: albumCropSize,
    );
    notifyListeners();
    try {
      final file = _albumFiles[index];
      final bytes = await MediaFiles.readBytes(file);
      final decoded = await ImageTransforms.loadOriented(
        bytes,
        maxSource: _maxCropSource,
      );
      if (_albumCropIndex != index || _albumCrop == null) return;
      final image = await _rgbaToUiImage(decoded);
      if (_albumCropIndex != index || _albumCrop == null) {
        image.dispose();
        return;
      }
      _albumCrop = _albumCrop!.copyWith(
        image: image,
        fileName: file.name,
        loading: false,
        clearError: true,
      );
    } catch (error) {
      _albumCrop = _albumCrop?.copyWith(
        loading: false,
        error: '图片加载失败：$error',
      );
    }
    notifyListeners();
  }

  Future<void> confirmAlbumCrop(Uint8List bytes) async {
    final state = _albumCrop;
    if (state == null || bytes.isEmpty) return;
    final size = JpgBinEncoder.jpegSize(bytes);
    BajiLog.instance.info(
      '裁剪',
      '${state.fileName} -> ${size?.$1 ?? 0}x${size?.$2 ?? 0}，${bytes.length}B，'
          'head=${toHex(bytes, maxBytes: 4)}，'
          'tail=${toHex(_tail(bytes, 2))}',
    );
    try {
      final dir = await getTemporaryDirectory();
      final file = p.join(dir.path, 'album_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await _writeFile(file, bytes);
      BajiLog.instance.info('裁剪', '已保存 $file');
    } catch (error) {
      BajiLog.instance.warn('裁剪', '保存失败：$error');
    }
    _albumCroppedFiles.add(
      TransferFile(
        name: state.fileName,
        bytes: bytes,
        width: size?.$1 ?? 0,
        height: size?.$2 ?? 0,
      ),
    );
    if (_albumCropIndex + 1 < _albumFiles.length) {
      _disposeAlbumImage();
      await _loadAlbumCrop(_albumCropIndex + 1);
    } else {
      final files = List<TransferFile>.from(_albumCroppedFiles);
      _albumCroppedFiles.clear();
      _albumFiles = [];
      _disposeAlbumImage();
      _albumCrop = null;
      notifyListeners();
      final token = ++_transferToken;
      _transfer = TransferUiState(
        running: true,
        kind: TransferKind.album,
        fileCount: files.length,
        totalBytes: files.fold<int>(0, (sum, file) => sum + file.bytes.length),
      );
      notifyListeners();
      await launchTransfer(TransferKind.album, files, token: token);
    }
  }

  void cancelAlbumCrop() {
    _disposeAlbumImage();
    _albumCrop = null;
    _albumFiles = [];
    _albumCroppedFiles.clear();
    _albumCropIndex = 0;
    notifyListeners();
  }

  void _disposeAlbumImage() {
    _albumCrop?.image?.dispose();
  }

  Future<ui.Image> _rgbaToUiImage(DecodedImage decoded) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      decoded.rgba,
      decoded.width,
      decoded.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  // ------------------------------------------------------------------ previews

  /// 多图轮播预览/缩略图：按路径缓存 368 或 96 的方形 JPEG。
  Future<Uint8List> slideshowPreview(XFile file, {int size = 368, int maxSource = 1024}) {
    final key = '${file.path}|$size|$maxSource';
    return _previewCache.putIfAbsent(key, () async {
      final bytes = await MediaFiles.readBytes(file);
      return ImageTransforms.loadSquareJpeg(
        bytes,
        maxSource: maxSource,
        size: size,
      );
    });
  }

  Future<Uint8List> _readFileBytes(String path, String name) async {
    final bytes = await _readBytesFromPath(path);
    if (bytes.isEmpty) throw StateError('无法读取 $name');
    if (bytes.length > _maxFileBytes) {
      throw StateError('$name 超过 ${_maxFileBytes ~/ 1024 ~/ 1024}MB 限制');
    }
    return bytes;
  }

  Future<Uint8List> _readBytesFromPath(String path) async {
    final file = XFile(path);
    return file.readAsBytes();
  }

  Future<void> _writeFile(String path, Uint8List bytes) =>
      File(path).writeAsBytes(bytes, flush: true);

  static Uint8List _tail(Uint8List bytes, int count) {
    final start = bytes.length > count ? bytes.length - count : 0;
    return Uint8List.sublistView(bytes, start);
  }

  @override
  void dispose() {
    repository.connection.removeListener(_onConnectionChanged);
    repository.reconnect.removeListener(notifyListeners);
    repository.device.removeListener(_onDeviceChanged);
    BajiLog.instance.removeListener(_onLogsChanged);
    _scanSubscription?.cancel();
    _messages.close();
    _disposeAlbumImage();
    super.dispose();
  }
}
