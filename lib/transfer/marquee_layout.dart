/// 跑马灯帧布局：把一行文字当作一条画布，固定用 [frameCount] 帧从右向左平移。
abstract final class MarqueeLayout {
  static const int size = 368;
  static const int frameCount = 30;

  static List<double> offsets(double textWidth) {
    if (textWidth <= 0) return const [];
    final totalDistance = size + textWidth;
    return List<double>.generate(
      frameCount,
      (index) => size - totalDistance * index / (frameCount - 1),
    );
  }
}
