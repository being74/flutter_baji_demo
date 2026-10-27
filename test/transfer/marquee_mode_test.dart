import 'package:flutter_baji_demo/transfer/marquee_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('character mode keeps every non whitespace character in order', () {
    expect(MarqueeRenderer.characterFrames('电影天堂'), ['电', '影', '天', '堂']);
    expect(MarqueeRenderer.characterFrames(' A B C '), ['A', 'B', 'C']);
  });

  test('whitespace only text has no character frames', () {
    expect(MarqueeRenderer.characterFrames('   '), isEmpty);
  });
}
