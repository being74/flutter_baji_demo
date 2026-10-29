import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../ble/baji_ble_client.dart';
import '../../transfer/marquee_renderer.dart';
import '../../transfer/transfer_models.dart';
import '../baji_view_model.dart';
import '../intervals.dart';
import '../widgets/baji_widgets.dart';

/// 跑马灯配色：文字色与底色成对出现，避免选出看不清的组合。
class _MarqueePalette {
  const _MarqueePalette(this.name, this.background, this.foreground);

  final String name;
  final Color background;
  final Color foreground;
}

const List<_MarqueePalette> _darkMarqueePalettes = [
  _MarqueePalette('墨夜', Color(0xFF16171A), Color(0xFFF2EDE2)),
  _MarqueePalette('莓果', Color(0xFF5B1230), Color(0xFFFFD9E4)),
  _MarqueePalette('珊瑚', Color(0xFFCE3B2F), Color(0xFFFFF6EA)),
  _MarqueePalette('松林', Color(0xFF143C31), Color(0xFFB9E6C9)),
  _MarqueePalette('钴蓝', Color(0xFF2246E8), Color(0xFFF6D64A)),
];

const List<_MarqueePalette> _lightMarqueePalettes = [
  _MarqueePalette('暖纸', Color(0xFFF4EFE3), Color(0xFF1B1B1E)),
  _MarqueePalette('黄油', Color(0xFFF6D64A), Color(0xFF1B1B1E)),
  _MarqueePalette('薄荷', Color(0xFFCFE9DC), Color(0xFF10382A)),
  _MarqueePalette('雾蓝', Color(0xFFD6E4F2), Color(0xFF12283D)),
  _MarqueePalette('蜜桃', Color(0xFFF6DCCF), Color(0xFF46231A)),
];

const List<_MarqueePalette> _marqueePalettes = [
  ..._darkMarqueePalettes,
  ..._lightMarqueePalettes,
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
  int _paletteIndex = 0;

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
      final palette = _marqueePalettes[_paletteIndex];
      final frames = await MarqueeRenderer.renderJpegFrames(
        MarqueeStyle(
          text: content,
          fontSize: _fontSize,
          textColor: palette.foreground.toARGB32(),
          backgroundColor: palette.background.toARGB32(),
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
    final palette = _marqueePalettes[_paletteIndex];
    final textColor = palette.foreground;
    final backgroundColor = palette.background;
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
                  const SizedBox(height: 22),
                  const FormLabel('配色', alignStart: true),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '文字与底色已配好，选一组就行',
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '深色底',
                      style: textTheme.labelMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _PaletteRow(
                    palettes: _darkMarqueePalettes,
                    firstIndex: 0,
                    selectedIndex: _paletteIndex,
                    enabled: !busy,
                    onSelect: (index) {
                      setState(() => _paletteIndex = index);
                      _schedulePreview();
                    },
                  ),
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '浅色底',
                      style: textTheme.labelMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _PaletteRow(
                    palettes: _lightMarqueePalettes,
                    firstIndex: _darkMarqueePalettes.length,
                    selectedIndex: _paletteIndex,
                    enabled: !busy,
                    onSelect: (index) {
                      setState(() => _paletteIndex = index);
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

class _PaletteRow extends StatelessWidget {
  const _PaletteRow({
    required this.palettes,
    required this.firstIndex,
    required this.selectedIndex,
    required this.enabled,
    required this.onSelect,
  });

  final List<_MarqueePalette> palettes;
  final int firstIndex;
  final int selectedIndex;
  final bool enabled;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < palettes.length; index++) ...[
          if (index > 0) const SizedBox(width: 6),
          Expanded(
            child: _PaletteTile(
              palette: palettes[index],
              selected: firstIndex + index == selectedIndex,
              enabled: enabled,
              onTap: () => onSelect(firstIndex + index),
            ),
          ),
        ],
      ],
    );
  }
}

class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.palette,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final _MarqueePalette palette;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '${palette.name}配色',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? scheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: palette.background,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: selected
                          ? Colors.transparent
                          : scheme.outlineVariant,
                    ),
                  ),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Center(
                      child: ExcludeSemantics(
                        child: Text(
                          'Aa',
                          style: textTheme.titleLarge?.copyWith(
                            color: palette.foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                palette.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
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
