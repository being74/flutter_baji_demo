import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 解码并应用 EXIF 方向后的 RGBA 像素，用于 Flutter 侧裁剪预览。
class DecodedImage {
  const DecodedImage({
    required this.rgba,
    required this.width,
    required this.height,
  });

  final Uint8List rgba;
  final int width;
  final int height;
}

/// 相册裁剪、多图轮播与动图帧共用的图片解码/旋转/居中裁切。
abstract final class ImageTransforms {
  /// 按 [maxSource] 采样解码并应用 EXIF 方向。
  static Future<DecodedImage> loadOriented(
    Uint8List bytes, {
    int maxSource = 1024,
  }) =>
      Isolate.run(() => _decodeOriented(bytes, maxSource));

  /// 解码、居中裁成正方形并缩放到 [size]，输出 JPEG（质量 90）。
  static Future<Uint8List> loadSquareJpeg(
    Uint8List bytes, {
    int maxSource = 1024,
    int size = 368,
    int quality = 90,
  }) =>
      Isolate.run(() => _squareJpeg(bytes, maxSource, size, quality));

  /// 居中裁成正方形并缩放；返回新 Image，源图由调用方回收。
  static img.Image centerCrop(img.Image source, int size) {
    final side = source.width < source.height ? source.width : source.height;
    final left = (source.width - side) ~/ 2;
    final top = (source.height - side) ~/ 2;
    final cropped = img.copyCrop(source, x: left, y: top, width: side, height: side);
    if (side == size) return cropped;
    return img.copyResize(
      cropped,
      width: size,
      height: size,
      interpolation: img.Interpolation.average,
    );
  }

  static DecodedImage _decodeOriented(Uint8List bytes, int maxSource) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw StateError('无法解码图片');
    final baked = img.bakeOrientation(decoded);
    final resized = _limitSize(baked, maxSource);
    return DecodedImage(
      rgba: resized.getBytes(order: img.ChannelOrder.rgba),
      width: resized.width,
      height: resized.height,
    );
  }

  static Uint8List _squareJpeg(
    Uint8List bytes,
    int maxSource,
    int size,
    int quality,
  ) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw StateError('无法解码图片');
    final baked = img.bakeOrientation(decoded);
    final limited = _limitSize(baked, maxSource);
    final square = centerCrop(limited, size);
    return Uint8List.fromList(img.encodeJpg(square, quality: quality));
  }

  static img.Image _limitSize(img.Image image, int maxSource) {
    final longest = image.width > image.height ? image.width : image.height;
    if (longest <= maxSource) return image;
    final scale = maxSource / longest;
    return img.copyResize(
      image,
      width: (image.width * scale).round().clamp(1, maxSource),
      height: (image.height * scale).round().clamp(1, maxSource),
      interpolation: img.Interpolation.average,
    );
  }
}
