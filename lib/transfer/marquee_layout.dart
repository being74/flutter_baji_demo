/// 跑马灯帧布局：把一行文字想象成一条画布，固定用 [frameCount] 帧从右向左平移。
///
/// 首帧文字完全在右侧屏外，末帧完全在左侧屏外；无论文字长短都会滚动，
/// 设备循环播放即为跑马灯。
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
