import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../ble/baji_ble_client.dart';
import '../../media/media_files.dart';
import '../../transfer/transfer_models.dart';
import '../baji_view_model.dart';
import '../intervals.dart';
import '../theme.dart';
import '../widgets/baji_widgets.dart';

class AnimationScreen extends StatefulWidget {
  const AnimationScreen({
    super.key,
    required this.viewModel,
    required this.onBack,
  });

  final BajiViewModel viewModel;
  final VoidCallback onBack;

  @override
  State<AnimationScreen> createState() => _AnimationScreenState();
}

class _AnimationScreenState extends State<AnimationScreen> {
  static const double _defaultSpeed =
      (AnimationLimits.maxIntervalMs - AnimationLimits.defaultIntervalMs) /
          (AnimationLimits.maxIntervalMs - AnimationLimits.minIntervalMs);

  double _speed = _defaultSpeed;

  BajiViewModel get viewModel => widget.viewModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) viewModel.clearTransferState();
    });
  }

  int get _intervalMs => animationIntervalFromSpeed(_speed);

  Future<void> _pickGif() async {
    try {
      final picked = await MediaFiles.pickGif();
      if (picked != null) await viewModel.selectAnimationSource(picked);
    } catch (error) {
      viewModel.showMessage('读取动图失败：$error');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picked = await MediaFiles.pickVideo();
      if (picked != null) await viewModel.selectAnimationSource(picked);
    } catch (error) {
      viewModel.showMessage('读取动图失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final connected = viewModel.connection is BleConnected;
    final transfer = viewModel.transfer;
    final animationTransfer = transfer.kind == TransferKind.ambience &&
            (transfer.running || transfer.message != null)
        ? transfer
        : null;
    final preparing = animationTransfer != null &&
        animationTransfer.running &&
        animationTransfer.totalBytes == 0;
    final busy = transfer.running;
    final source = viewModel.animationSource;

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          OverlayHeader(title: '动图', onBack: widget.onBack),
          TransferResultToast(transfer: animationTransfer),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  _PreviewCircle(source: source),
                  const SizedBox(height: 18),
                  ConnectionPill(connected: connected),
                  const SizedBox(height: 28),
                  const SectionTitle(title: '选择动图', subtitle: '限定 3 秒'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _MediaPickButton(
                          label: '视频',
                          icon: Icons.videocam_outlined,
                          enabled: !busy,
                          onClick: _pickVideo,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _MediaPickButton(
                          label: 'GIF',
                          icon: Icons.gif_box_outlined,
                          enabled: !busy,
                          onClick: _pickGif,
                        ),
                      ),
                    ],
                  ),
                  if (source != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${source.name} · '
                      '${source.kind == AnimationKind.gif ? 'GIF' : '视频'} · '
                      '${_formatDuration(source.durationMs)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (source.durationMs > AnimationLimits.maxDurationMs)
                      Text(
                        '仅取前 3 秒',
                        style: textTheme.bodySmall?.copyWith(color: scheme.error),
                      ),
                    Builder(
                      builder: (context) {
                        final effective = source.durationMs
                            .clamp(0, AnimationLimits.maxDurationMs)
                            .toInt();
                        final estimated = effective <= 0
                            ? 1
                            : (effective ~/ _intervalMs).clamp(
                                1,
                                AnimationLimits.maxFrames,
                              );
                        return Text(
                          '预计 $estimated 帧 · '
                          '${_formatDuration(estimated * _intervalMs)}',
                          style: textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 28),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('播放速度', style: textTheme.titleMedium),
                  ),
                  Row(
                    children: [
                      const PlayBadge(),
                      Expanded(
                        child: Slider(
                          value: _speed,
                          onChanged: busy
                              ? null
                              : (value) => setState(() => _speed = value),
                          activeColor: connectedGreen,
                          inactiveColor: scheme.surfaceContainerHighest,
                          thumbColor: scheme.surface,
                        ),
                      ),
                      Text(
                        '${_intervalMs}ms/帧',
                        style: textTheme.labelLarge
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  BinUploadButton(
                    loading: animationTransfer?.running == true,
                    loadingText: preparing
                        ? '生成中…'
                        : '上传中 '
                            '${((animationTransfer?.fraction ?? 0) * 100).round()}%',
                    progress: preparing ? null : animationTransfer?.fraction,
                    enabled: source != null && connected && !busy,
                    onClick: () => viewModel.startAnimationTransfer(_intervalMs),
                  ),
                  if (animationTransfer?.running == true)
                    TextButton(
                      onPressed: viewModel.cancelTransfer,
                      child: Text(
                        '取消上传',
                        style: textTheme.bodySmall,
                      ),
                    ),
                  if (!connected) ...[
                    const SizedBox(height: 8),
                    Text(
                      '请先连接设备',
                      style: textTheme.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ],
                  if (source == null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '请选择 GIF 或视频',
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    '上传可能耗时 1~3 分钟，请保持页面在前台。',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCircle extends StatelessWidget {
  const _PreviewCircle({required this.source});

  final AnimationSourceUi? source;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final current = source;
    return FractionallySizedBox(
      widthFactor: 0.72,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            shape: BoxShape.circle,
          ),
          foregroundDecoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: scheme.outlineVariant,
              width: 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: current == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'GIF / 视频',
                        style: textTheme.titleMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '选择后在此预览',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                )
              : current.kind == AnimationKind.gif
                  ? SizedBox.expand(
                      child: Image.file(
                        File(current.path),
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) =>
                            _previewError(textTheme, scheme),
                      ),
                    )
                  : SizedBox.expand(
                      child: _VideoPreview(
                        key: ValueKey(current.path),
                        source: current,
                        loopLimitMs: current.durationMs
                            .clamp(0, AnimationLimits.maxDurationMs)
                            .toInt(),
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _previewError(TextTheme textTheme, ColorScheme scheme) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '无法预览',
              style: textTheme.titleMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              '请尝试重新选择',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
}

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({super.key, required this.source, required this.loopLimitMs});

  final AnimationSourceUi source;
  final int loopLimitMs;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? _controller;
  Timer? _loopTimer;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final controller = VideoPlayerController.file(File(widget.source.path));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) return;
      setState(() {});
      _loopTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!controller.value.isInitialized) return;
        if (widget.loopLimitMs > 0 &&
            controller.value.position >
                Duration(milliseconds: widget.loopLimitMs)) {
          controller.seekTo(Duration.zero);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed) {
      final preview = widget.source.preview;
      if (preview != null) {
        return Image.memory(preview, fit: BoxFit.cover);
      }
      return const Center(child: Text('无法预览'));
    }
    if (controller == null || !controller.value.isInitialized) {
      final preview = widget.source.preview;
      return Stack(
        fit: StackFit.expand,
        children: [
          if (preview != null) Image.memory(preview, fit: BoxFit.cover),
          const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ],
      );
    }
    final size = controller.value.size;
    return ClipOval(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

class _MediaPickButton extends StatelessWidget {
  const _MediaPickButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onClick,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 68,
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: InkWell(
          onTap: enabled ? onClick : null,
          borderRadius: BorderRadius.circular(18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 26),
              const SizedBox(width: 8),
              Text(label, style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatDuration(int durationMs) => durationMs > 0
    ? '${(durationMs / 1000).toStringAsFixed(1)}s'
    : '时长未知';
