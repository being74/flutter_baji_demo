import 'dart:typed_data';

import 'package:flutter_baji_demo/media/gif_sampler.dart';
import 'package:flutter_baji_demo/media/image_transforms.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('loadSquareJpeg center crops and scales to 368', () async {
    final source = img.Image(width: 400, height: 200);
    img.fill(source, color: img.ColorRgb8(10, 20, 30));
    final jpeg = Uint8List.fromList(img.encodeJpg(source, quality: 90));

    final output = await ImageTransforms.loadSquareJpeg(jpeg, size: 368);
    final decoded = img.decodeJpg(output)!;

    expect(decoded.width, 368);
    expect(decoded.height, 368);
    expect(output.sublist(0, 2), [0xFF, 0xD8]);
    expect(output.sublist(output.length - 2), [0xFF, 0xD9]);
  });

  test('gif sampler caps duration and samples frames', () async {
    final first = img.Image(width: 120, height: 80)
      ..frameDuration = 100;
    img.fill(first, color: img.ColorRgb8(255, 0, 0));
    final second = img.Image(width: 120, height: 80)
      ..frameDuration = 100;
    img.fill(second, color: img.ColorRgb8(0, 255, 0));
    first.addFrame(second);

    final gif = Uint8List.fromList(img.encodeGif(first));
    final duration = await GifSampler.durationMs(gif);
    expect(duration, 200);

    final frames = await GifSampler.sampleFrames(gif, intervalMs: 100);
    expect(frames.length, 2);
    for (final frame in frames) {
      final decoded = img.decodeJpg(frame)!;
      expect(decoded.width, 368);
      expect(decoded.height, 368);
    }
  });
}
