import 'package:flutter_baji_demo/ui/intervals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('animation speed maps to encoder-safe interval', () {
    expect(animationIntervalFromSpeed(1), 100);
    expect(animationIntervalFromSpeed(0), 999);
    expect(animationIntervalFromSpeed(0.5), 550);
  });

  test('slideshow speed maps to 50ms steps', () {
    expect(slideshowIntervalFromSpeed(1), 200);
    expect(slideshowIntervalFromSpeed(0), 5000);
    expect(slideshowIntervalFromSpeed(0.5), 2600);
  });

  test('marquee scroll speed maps to 3-6 second cycles', () {
    expect(marqueeScrollIntervalFromSpeed(1), 100);
    expect(marqueeScrollIntervalFromSpeed(0), 200);
    expect(marqueeScrollIntervalFromSpeed(0.5), 150);
  });
}
