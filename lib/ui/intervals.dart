import 'baji_view_model.dart';

int animationIntervalFromSpeed(double speed) {
  final raw = AnimationLimits.maxIntervalMs -
      speed.clamp(0.0, 1.0) *
          (AnimationLimits.maxIntervalMs - AnimationLimits.minIntervalMs);
  return ((raw / 10).round() * 10).clamp(
    AnimationLimits.minIntervalMs,
    AnimationLimits.maxIntervalMs,
  );
}

int slideshowIntervalFromSpeed(double speed) {
  final raw = SlideshowLimits.maxIntervalMs -
      speed.clamp(0.0, 1.0) *
          (SlideshowLimits.maxIntervalMs - SlideshowLimits.minIntervalMs);
  return ((raw / 50).round() * 50).clamp(
    SlideshowLimits.minIntervalMs,
    SlideshowLimits.maxIntervalMs,
  );
}
