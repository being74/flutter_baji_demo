import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// 按固定帧间隔轮播 JPEG 帧，用于“动图”页的设备效果预览。
///
/// 帧序列与速度滑杆解耦：抽帧步长固定，[intervalMs] 只决定每帧停留时间。
class AnimationPreview extends StatefulWidget {
  const AnimationPreview({
    super.key,
    required this.frames,
    required this.intervalMs,
  });

  final List<Uint8List> frames;
  final int intervalMs;

  @override
  State<AnimationPreview> createState() => _AnimationPreviewState();
}

class _AnimationPreviewState extends State<AnimationPreview> {
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void didUpdateWidget(covariant AnimationPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.intervalMs != widget.intervalMs ||
        oldWidget.frames.length != widget.frames.length) {
      _restartTimer();
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    final count = widget.frames.length;
    if (count <= 1) return;
    _index %= count;
    _timer = Timer.periodic(Duration(milliseconds: widget.intervalMs), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % count);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frames = widget.frames;
    if (frames.isEmpty) {
      return const Center(child: Text('无法预览'));
    }
    return Image.memory(
      frames[_index % frames.length],
      fit: BoxFit.cover,
      gaplessPlayback: true,
    );
  }
}
