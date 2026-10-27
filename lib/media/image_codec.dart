import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// Flutter 引擎没有 JPEG 编码器：先把 ui.Image 读成 RGBA，再交给 package:image。
Future<Uint8List> encodeUiImageJpeg(ui.Image image, {int quality = 90}) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) throw StateError('无法读取渲染结果');
  final rgba = img.Image.fromBytes(
    width: image.width,
    height: image.height,
    bytes: data.buffer,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodeJpg(rgba, quality: quality));
}

/// 把 RGBA 原始像素编码为 JPEG。
Uint8List encodeRgbaJpeg(
  Uint8List rgba, {
  required int width,
  required int height,
  int quality = 90,
}) {
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}
