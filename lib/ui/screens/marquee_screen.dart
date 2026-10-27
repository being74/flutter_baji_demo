import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../ble/baji_ble_client.dart';
import '../../transfer/marquee_renderer.dart';
import '../../transfer/transfer_models.dart';
import '../baji_view_model.dart';
import '../intervals.dart';
import '../widgets/baji_widgets.dart';

const List<Color> _marqueeColors = [
  Color(0xFF111114),
  Color(0xFFF7F5EE),
  Color(0xFFFFD93D),
  Color(0xFFFF4D4D),
  Color(0xFFFF3D9E),
  Color(0xFF8B5CF6),
  Color(0xFF3B82F6),
  Color(0xFF38BDF8),
  Color(0xFF22D3EE),
  Color(0xFF34D399),
];

class MarqueeScreen extends StatefulWidget {
  const MarqueeScreen({
    super.key,
    required this.viewModel,
    required this.onBack,
  });

  final BajiViewModel viewModel;
  final VoidCallback onBack;

  @override
  State<MarqueeScreen> createState() => _MarqueeScreenState();
}

class _MarqueeScreenState extends State<MarqueeScreen> {
  static const int _defaultIntervalMs = 500;
  static const double _defaultSpeed =
      (AnimationLimits.maxIntervalMs - _defaultIntervalMs) /
          (AnimationLimits.maxIntervalMs - AnimationLimits.minIntervalMs);

  final TextEditingController _textController = TextEditingController();
  double _speed = _defaultSpeed;
  int _fontSize = MarqueeRenderer.defaultFontSize;
  int _textColorIndex = 2;
  int _backgroundColorIndex = 5;

  List<Uint8List> _previewFrames = const [];
  int _previewIndex = 0;
  Timer? _previewTimer;
  Timer? _previewDebounce;
  int _previewGeneration = 0;

  BajiViewModel get viewModel => widget.viewModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) viewModel.clearTransferState();
    });
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _previewDebounce?.cancel();
    _textController.dispose();
    super.dispose();
  }

  int get _intervalMs => animationIntervalFromSpeed(_speed);

  void _schedulePreview() {
    _previewDebounce?.cancel();
    final generation = ++_previewGeneration;
    _previewDebounce = Timer(const Duration(milliseconds: 180), () {
      _renderPreview(generation);
    });
  }

  Future<void> _renderPreview(int generation) async {
    final content = _textController.text.trim();
    if (content.isEmpty) {
      if (!mounted || generation != _previewGeneration) return;
      setState(() {
        _previewFrames = const [];
        _previewIndex = 0;
      });
      _restartPreviewTimer();
      return;
    }
    try {
      final frames = await MarqueeRenderer.renderJpegFrames(
        MarqueeStyle(
          text: content,
          fontSize: _fontSize,
          textColor: _marqueeColors[_textColorIndex].toARGB32(),
          backgroundColor: _marqueeColors[_backgroundColorIndex].toARGB32(),
          mode: MarqueeMode.character,
        ),
      );
      if (!mounted || generation != _previewGeneration) return;
      setState(() {
        _previewFrames = frames;
        _previewIndex = 0;
      });
      _restartPreviewTimer();
    } catch (error) {
      viewModel.log.warn('跑马灯', '预览生成失败：$error');
    }
  }

  void _restartPreviewTimer() {
    _previewTimer?.cancel();
    if (_previewFrames.length <= 1) return;
    _previewTimer = Timer.periodic(Duration(milliseconds: _intervalMs), (_) {
      if (!mounted) return;
      setState(() {
        _previewIndex = (_previewIndex + 1) % _previewFrames.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final connected = viewModel.connection is BleConnected;
    final transfer = viewModel.transfer;
    final activeTransfer = transfer.kind == TransferKind.marquee &&
            (transfer.running || transfer.message != null)
        ? transfer
        : null;
    final preparing = activeTransfer != null &&
        activeTransfer.running &&
        activeTransfer.totalBytes == 0;
    final busy = transfer.running;
    final text = _textController.text.trim();
    final textColor = _marqueeColors[_textColorIndex];
    final backgroundColor = _marqueeColors[_backgroundColorIndex];
    final frameCount = MarqueeRenderer.characterFrames(text).length;

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          OverlayHeader(title: '跑马灯', onBack: widget.onBack),
          TransferResultToast(transfer: activeTransfer),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  FractionallySizedBox(
                    widthFactor: 0.7,
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: _MarqueeFramesPreview(
                        text: text,
                        frames: _previewFrames,
                        frameIndex: _previewIndex,
                        textColor: textColor,
                        backgroundColor: backgroundColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ConnectionPill(connected: connected),
                  const SizedBox(height: 26),
                  const FormLabel('文字'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _textController,
                    enabled: !busy,
                    maxLength: MarqueeRenderer.maxTextLength,
                    maxLines: 1,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText:
                          '请输入文字（不超过 ${MarqueeRenderer.maxTextLength} 个字）',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (_) {
                      setState(() {});
                      _schedulePreview();
                    },
                  ),
                  const SizedBox(height: 18),
                  const FormLabel('显示方式'),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      frameCount > 0
                          ? '逐字轮播 · 每个字一张 368×368 全屏图，共 $frameCount 帧'
                          : '逐字轮播 · 每个字一张 368×368 全屏图',
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.primary),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(child: FormLabel('字体大小')),
                      Text(
                        '${_fontSize}px',
                        style: textTheme.labelLarge
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  Slider(
                    value: _fontSize.toDouble(),
                    min: MarqueeRenderer.minFontSize.toDouble(),
                    max: MarqueeRenderer.maxFontSize.toDouble(),
                    divisions: MarqueeRenderer.maxFontSize -
                        MarqueeRenderer.minFontSize,
                    onChanged: busy
                        ? null
                        : (value) {
                            setState(() => _fontSize = value.round());
                            _schedulePreview();
                          },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(child: FormLabel('播放速度')),
                      Text(
                        '${_intervalMs}ms/帧',
                        style: textTheme.labelLarge
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const PlayBadge(),
                      Expanded(
                        child: Slider(
                          value: _speed,
                          onChanged: busy
                              ? null
                              : (value) {
                                  setState(() => _speed = value);
                                  _restartPreviewTimer();
                                },
                          activeColor: scheme.primary,
                          inactiveColor: scheme.surfaceContainerHighest,
                          thumbColor: scheme.surface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const FormLabel('字体颜色', alignStart: true),
                  const SizedBox(height: 8),
                  _ColorRow(
                    selectedIndex: _textColorIndex,
                    enabled: !busy,
                    onSelect: (index) {
                      setState(() => _textColorIndex = index);
                      _schedulePreview();
                    },
                  ),
                  const SizedBox(height: 20),
                  const FormLabel('背景选择', alignStart: true),
                  const SizedBox(height: 8),
                  _ColorRow(
                    selectedIndex: _backgroundColorIndex,
                    enabled: !busy,
                    onSelect: (index) {
                      setState(() => _backgroundColorIndex = index);
                      _schedulePreview();
                    },
                  ),
                  const SizedBox(height: 24),
                  BinUploadButton(
                    loading: activeTransfer?.running == true,
                    loadingText: preparing
                        ? '生成中…'
                        : '上传中 '
                            '${((activeTransfer?.fraction ?? 0) * 100).round()}%',
                    progress: preparing ? null : activeTransfer?.fraction,
                    enabled: connected && text.isNotEmpty && !busy,
                    onClick: () => viewModel.startMarqueeTransfer(
                      text: _textController.text,
                      fontSize: _fontSize,
                      textColor: textColor.toARGB32(),
                      backgroundColor: backgroundColor.toARGB32(),
                      mode: MarqueeMode.character,
                      intervalMs: _intervalMs,
                    ),
                  ),
                  if (activeTransfer?.running == true)
                    TextButton(
                      onPressed: viewModel.cancelTransfer,
                      child: Text('取消上传', style: textTheme.bodySmall),
                    ),
                  if (!connected) ...[
                    const SizedBox(height: 8),
                    Text(
                      '请先连接设备',
                      style: textTheme.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    '生成多张 JPG 帧并按动图指令发送，上传可能耗时 1~3 分钟。',
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

class FormLabel extends StatelessWidget {
  const FormLabel(this.text, {super.key, this.alignStart = false});

  final String text;
  final bool alignStart;

  @override
  Widget build(BuildContext context) {
    final label = Text(text, style: Theme.of(context).textTheme.titleMedium);
    return alignStart
        ? Align(alignment: Alignment.centerLeft, child: label)
        : label;
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.selectedIndex,
    required this.enabled,
    required this.onSelect,
  });

  final int selectedIndex;
  final bool enabled;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var index = 0; index < _marqueeColors.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: GestureDetector(
                onTap: enabled ? () => onSelect(index) : null,
                child: Container(
                  decoration: BoxDecoration(
                    color: _marqueeColors[index],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: index == selectedIndex
                          ? scheme.primary
                          : scheme.outlineVariant,
                      width: index == selectedIndex ? 2 : 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MarqueeFramesPreview extends StatelessWidget {
  const _MarqueeFramesPreview({
    required this.text,
    required this.frames,
    required this.frameIndex,
    required this.textColor,
    required this.backgroundColor,
  });

  final String text;
  final List<Uint8List> frames;
  final int frameIndex;
  final Color textColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasFrame = frames.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
      ),
      foregroundDecoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outlineVariant, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: text.isEmpty
          ? Center(
              child: Text(
                '输入文字后预览',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: textColor.withValues(alpha: 0.55),
                    ),
              ),
            )
          : !hasFrame
              ? Center(
                  child: Text(
                    '生成中…',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: textColor.withValues(alpha: 0.55),
                        ),
                  ),
                )
              : SizedBox.expand(
                  child: Image.memory(
                    frames[frameIndex.clamp(0, frames.length - 1)],
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    gaplessPlayback: true,
                  ),
                ),
    );
  }
}
