import '../transfer/marquee_layout.dart';
import 'baji_view_model.dart';

int animationIntervalFromSpeed(double speed) {
  final raw =
      AnimationLimits.maxIntervalMs -
      speed.clamp(0.0, 1.0) *
          (AnimationLimits.maxIntervalMs - AnimationLimits.minIntervalMs);
  return ((raw / 10).round() * 10).clamp(
    AnimationLimits.minIntervalMs,
    AnimationLimits.maxIntervalMs,
  );
}

/// 文字滚动按“整轮时长”调速：固定 30 帧走完一轮，
/// 最快 3 秒/轮（100ms/帧），最慢 6 秒/轮（200ms/帧）。
abstract final class MarqueeScrollLimits {
  static const int minCycleMs = 3000;
  static const int maxCycleMs = 6000;
  static const int defaultCycleMs = 4500;
}

int marqueeScrollIntervalFromSpeed(double speed) {
  final cycleMs =
      MarqueeScrollLimits.maxCycleMs -
      speed.clamp(0.0, 1.0) *
          (MarqueeScrollLimits.maxCycleMs - MarqueeScrollLimits.minCycleMs);
  return (cycleMs / MarqueeLayout.frameCount).round().clamp(
    AnimationLimits.minIntervalMs,
    AnimationLimits.maxIntervalMs,
  );
}

int slideshowIntervalFromSpeed(double speed) {
  final raw =
      SlideshowLimits.maxIntervalMs -
      speed.clamp(0.0, 1.0) *
          (SlideshowLimits.maxIntervalMs - SlideshowLimits.minIntervalMs);
  return ((raw / 50).round() * 50).clamp(
    SlideshowLimits.minIntervalMs,
    SlideshowLimits.maxIntervalMs,
  );
}
