import 'package:flutter_baji_demo/transfer/marquee_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty text has no frames', () {
    expect(MarqueeLayout.offsets(0), isEmpty);
  });

  test('short text still scrolls across all frames', () {
    final offsets = MarqueeLayout.offsets(120);
    expect(offsets.length, MarqueeLayout.frameCount);
    expect(offsets.first, MarqueeLayout.size.toDouble());
    expect(offsets.last, -120);
    for (var index = 1; index < offsets.length; index++) {
      expect(offsets[index], lessThan(offsets[index - 1]));
    }
  });

  test('overflowing text scrolls right to left across all frames', () {
    final offsets = MarqueeLayout.offsets(600);
    expect(offsets.length, MarqueeLayout.frameCount);
    expect(offsets.first, MarqueeLayout.size.toDouble());
    expect(offsets.last, -600);
  });

  test('frame count does not grow with text width', () {
    expect(MarqueeLayout.offsets(2000).length, MarqueeLayout.frameCount);
  });
}
