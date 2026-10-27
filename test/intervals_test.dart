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
    expect(slideshowIntervalFromSpeed(0), 999);
    expect(slideshowIntervalFromSpeed(0.5), 600);
  });
}
