
import 'package:flutter/services.dart';

class VideoInfo {
  const VideoInfo({required this.durationMs, this.preview});

  final int durationMs;
  final Uint8List? preview;
}

/// 视频抽帧由 Android MediaMetadataRetriever / iOS AVAssetImageGenerator 完成，
/// 帧统一输出为 368×368 JPEG。
abstract final class VideoFrames {
  static const MethodChannel _channel = MethodChannel('baji/video');

  static Future<VideoInfo> load(String path, {int maxSize = 720}) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('load', {
      'path': path,
      'maxSize': maxSize,
    });
    if (result == null) throw StateError('读取视频信息失败');
    final duration = result['durationMs'];
    final preview = result['preview'];
    return VideoInfo(
      durationMs: duration is int ? duration : (duration as num?)?.toInt() ?? 0,
      preview: preview is Uint8List ? preview : null,
    );
  }

  static Future<List<Uint8List>> extract(
    String path, {
    int intervalMs = 100,
    int maxFrames = 30,
    int maxDurationMs = 3000,
    int size = 368,
  }) async {
    final result = await _channel.invokeListMethod<Uint8List>('extract', {
      'path': path,
      'intervalMs': intervalMs,
      'maxFrames': maxFrames,
      'maxDurationMs': maxDurationMs,
      'size': size,
    });
    return result ?? const [];
  }
}
