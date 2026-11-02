import 'package:flutter_baji_demo/transfer/marquee_layout.dart';
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

  test('frame count follows the selected mode', () {
    expect(MarqueeRenderer.frameCount('', MarqueeMode.character), 0);
    expect(MarqueeRenderer.frameCount('   ', MarqueeMode.scroll), 0);
    expect(MarqueeRenderer.frameCount('电影', MarqueeMode.character), 2);
    expect(
      MarqueeRenderer.frameCount('电影', MarqueeMode.scroll),
      MarqueeLayout.frameCount,
    );
  });
}
