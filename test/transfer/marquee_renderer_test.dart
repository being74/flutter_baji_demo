import 'dart:typed_data';

import 'package:flutter_baji_demo/transfer/jpg_bin_encoder.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_baji_demo/transfer/marquee_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('character frames render as 368 square jpeg', () async {
    final frames = await MarqueeRenderer.renderJpegFrames(
      const MarqueeStyle(
        text: '电影',
        fontSize: 48,
        textColor: 0xFFFFD93D,
        backgroundColor: 0xFF8B5CF6,
        mode: MarqueeMode.character,
      ),
    );

    expect(frames.length, 2);
    for (final frame in frames) {
      expect(frame.sublist(0, 2), [0xFF, 0xD8]);
      expect(frame.sublist(frame.length - 2), [0xFF, 0xD9]);
      expect(JpgBinEncoder.jpegSize(Uint8List.fromList(frame)), (368, 368));
    }
  });

  test('scroll mode still renders all 30 frames', () async {
    final frames = await MarqueeRenderer.renderJpegFrames(
      const MarqueeStyle(
        text: 'Baji',
        fontSize: 48,
        textColor: 0xFFF7F5EE,
        backgroundColor: 0xFF111114,
      ),
    );
    expect(frames.length, 30);
    expect(JpgBinEncoder.jpegSize(Uint8List.fromList(frames.first)), (368, 368));
  });

  test('character painter lays out only the current glyph', () {
    const style = MarqueeStyle(
      text: '好汉歌',
      fontSize: 48,
      textColor: 0xFFFFD93D,
      backgroundColor: 0xFF8B5CF6,
      mode: MarqueeMode.character,
    );

    for (final character in ['好', '汉', '歌']) {
      final painter = MarqueeRenderer.buildCharacterPainter(style, character);
      expect(painter.text!.toPlainText(), character);
    }
  });


  test('character frame ink is centered in the 368 canvas', () async {
    final frames = await MarqueeRenderer.renderJpegFrames(
      const MarqueeStyle(
        text: 'H',
        fontSize: 48,
        textColor: 0xFFFFFFFF,
        backgroundColor: 0xFF000000,
        mode: MarqueeMode.character,
      ),
    );
    final decoded = img.decodeJpg(frames.single)!;
    var minX = decoded.width;
    var minY = decoded.height;
    var maxX = -1;
    var maxY = -1;
    for (var y = 0; y < decoded.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        final pixel = decoded.getPixel(x, y);
        final luminance =
            (pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114);
        if (luminance < 128) continue;
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
    expect(maxX, greaterThan(0));
    expect((minX + maxX) / 2, closeTo(184, 2));
    expect((minY + maxY) / 2, closeTo(184, 2));
  });
}

