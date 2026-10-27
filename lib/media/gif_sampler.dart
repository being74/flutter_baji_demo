import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'image_transforms.dart';

/// GIF 时长与抽帧。抽帧规则与 Android Movie 版一致：
/// 源截取前 3 秒，默认 100ms 采样，最多 30 帧，中心裁切为 368×368 JPEG。
abstract final class GifSampler {
  static Future<int> durationMs(Uint8List bytes) =>
      Isolate.run(() => _durationMs(bytes));

  static Future<List<Uint8List>> sampleFrames(
    Uint8List bytes, {
    int intervalMs = 100,
    int maxFrames = 30,
    int maxDurationMs = 3000,
    int size = 368,
    int quality = 90,
  }) =>
      Isolate.run(
        () => _sampleFrames(
          bytes,
          intervalMs,
          maxFrames,
          maxDurationMs,
          size,
          quality,
        ),
      );

  static int _durationMs(Uint8List bytes) {
    final decoded = img.decodeGif(bytes);
    if (decoded == null) throw StateError('GIF 解码失败');
    return _totalDuration(decoded);
  }

  static List<Uint8List> _sampleFrames(
    Uint8List bytes,
    int intervalMs,
    int maxFrames,
    int maxDurationMs,
    int size,
    int quality,
  ) {
    final decoded = img.decodeGif(bytes);
    if (decoded == null) throw StateError('GIF 解码失败');
    if (decoded.width <= 0 || decoded.height <= 0) throw StateError('GIF 尺寸无效');

    final rawDuration = _totalDuration(decoded);
    final duration = rawDuration > 0
        ? (rawDuration < maxDurationMs ? rawDuration : maxDurationMs)
        : intervalMs;
    final count = duration <= 0
        ? 1
        : _min(maxFrames, _max(1, duration ~/ intervalMs));
    final frames = decoded.frames.isEmpty ? [decoded] : decoded.frames;

    final outputs = <Uint8List>[];
    for (var index = 0; index < count; index++) {
      final timeMs = index * intervalMs;
      final frame = _frameAt(frames, timeMs);
      final square = ImageTransforms.centerCrop(frame, size);
      final flattened = img.Image(
        width: square.width,
        height: square.height,
        numChannels: 3,
      );
      img.fill(flattened, color: img.ColorRgb8(0, 0, 0));
      img.compositeImage(flattened, square);
      outputs.add(Uint8List.fromList(img.encodeJpg(flattened, quality: quality)));
    }
    return outputs;
  }

  static int _totalDuration(img.Image gif) {
    final frames = gif.frames.isEmpty ? [gif] : gif.frames;
    var total = 0;
    for (final frame in frames) {
      total += frame.frameDuration;
    }
    return total;
  }

  static img.Image _frameAt(List<img.Image> frames, int timeMs) {
    if (timeMs <= 0) return frames.first;
    var elapsed = 0;
    for (final frame in frames) {
      elapsed += frame.frameDuration;
      if (timeMs < elapsed) return frame;
    }
    return frames.last;
  }

  static int _min(int left, int right) => left < right ? left : right;

  static int _max(int left, int right) => left > right ? left : right;
}
