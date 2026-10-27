import 'dart:typed_data';

import '../protocol/baji_protocol.dart';

/// 需要传输的固件/图片类型。
enum TransferKind {
  ota(BajiCommands.ota, 'OTA 固件'),
  bootAnimation(BajiCommands.bootAnimation, '开机动画'),
  ambience(BajiCommands.ambience, '动态氛围'),

  /// 文字跑马灯：同样走 0x05 动图命令，仅用于区分进度与日志标题。
  marquee(BajiCommands.ambience, '跑马灯'),

  /// 多图轮播：每张图片一帧，仍走 0x05 动图命令。
  slideshow(BajiCommands.ambience, '多图轮播'),
  watchFace(BajiCommands.watchFace, '表盘样式'),
  album(BajiCommands.album, '相册');

  const TransferKind(this.type, this.title);

  final int type;
  final String title;

  /// 这些页面用上传按钮上方的进度卡展示结果，不再弹底部 snackbar。
  bool get showsInlineTransferStatus =>
      this == TransferKind.ambience ||
      this == TransferKind.marquee ||
      this == TransferKind.slideshow;
}

class TransferFile {
  const TransferFile({
    required this.name,
    required this.bytes,
    this.width,
    this.height,
    this.binWrapped = false,
  });

  final String name;
  final Uint8List bytes;
  final int? width;
  final int? height;

  /// true 表示 bytes 已是设备 IMB bin，相册传输时跳过 JPG→bin 封装。
  final bool binWrapped;

  TransferFile copyWith({Uint8List? bytes}) => TransferFile(
        name: name,
        bytes: bytes ?? this.bytes,
        width: width,
        height: height,
        binWrapped: binWrapped,
      );
}

class TransferOptions {
  const TransferOptions({
    this.watchFaceNames = const ['bg.bin', 'hour.bin', 'min.bin', 'sec.bin'],
    this.watchFaceInterval = const Duration(milliseconds: 1500),
    this.albumInterval = const Duration(seconds: 1),
  });

  /// 表盘槽位文件名，顺序为底图、时针、分针、秒针。
  final List<String> watchFaceNames;
  final Duration watchFaceInterval;
  final Duration albumInterval;
}

class TransferProgress {
  const TransferProgress({
    required this.kind,
    required this.fileIndex,
    required this.fileCount,
    required this.fileName,
    required this.sentBytes,
    required this.totalBytes,
    required this.bytesPerSecond,
  });

  final TransferKind kind;
  final int fileIndex;
  final int fileCount;
  final String fileName;
  final int sentBytes;
  final int totalBytes;
  final int bytesPerSecond;

  double get fraction =>
      totalBytes <= 0 ? 0 : (sentBytes / totalBytes).clamp(0.0, 1.0);
}

sealed class TransferResult {
  const TransferResult();
}

class TransferSuccess extends TransferResult {
  const TransferSuccess();
}

class TransferFailure extends TransferResult {
  const TransferFailure(this.message);

  final String message;
}
