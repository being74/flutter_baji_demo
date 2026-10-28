import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../ble/baji_ble_client.dart';
import '../../media/media_files.dart';
import '../../transfer/transfer_models.dart';
import '../baji_view_model.dart';
import '../intervals.dart';
import '../widgets/baji_widgets.dart';

class SlideshowScreen extends StatefulWidget {
  const SlideshowScreen({
    super.key,
    required this.viewModel,
    required this.onBack,
  });

  final BajiViewModel viewModel;
  final VoidCallback onBack;

  @override
  State<SlideshowScreen> createState() => _SlideshowScreenState();
}

class _SlideshowScreenState extends State<SlideshowScreen> {
  static const double _defaultSpeed =
      (SlideshowLimits.maxIntervalMs - SlideshowLimits.defaultIntervalMs) /
          (SlideshowLimits.maxIntervalMs - SlideshowLimits.minIntervalMs);

  final List<XFile> _slides = [];
  double _speed = _defaultSpeed;
  String? _pickerMessage;
  int _previewIndex = 0;
  Timer? _previewTimer;

  BajiViewModel get viewModel => widget.viewModel;

  int get _intervalMs => slideshowIntervalFromSpeed(_speed);

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
    super.dispose();
  }

  void _restartPreviewTimer() {
    _previewTimer?.cancel();
    if (_slides.length <= 1) return;
    _previewTimer = Timer.periodic(Duration(milliseconds: _intervalMs), (_) {
      if (!mounted) return;
      setState(() => _previewIndex = (_previewIndex + 1) % _slides.length);
    });
  }

  void _addImages(List<XFile> picked) {
    if (picked.isEmpty) return;
    final remaining = SlideshowLimits.maxImages - _slides.length;
    if (remaining <= 0) {
      setState(() => _pickerMessage = '最多选择 ${SlideshowLimits.maxImages} 张图片');
      return;
    }
    final existing = _slides.map((file) => file.path).toSet();
    final unique = <XFile>[];
    for (final file in picked) {
      if (existing.add(file.path)) unique.add(file);
    }
    final accepted = unique.take(remaining).toList();
    setState(() {
      _pickerMessage = unique.length > remaining
          ? '最多 ${SlideshowLimits.maxImages} 张，'
              '已忽略多余的 ${unique.length - remaining} 张'
          : null;
      _slides.addAll(accepted);
      _previewIndex = 0;
    });
    _restartPreviewTimer();
  }

  Future<void> _pickGallery() async {
    final files = await MediaFiles.pickAlbumImages();
    _addImages(files);
  }

  Future<void> _takePhoto() async {
    try {
      final file = await MediaFiles.pickCameraImage();
      if (file != null) _addImages([file]);
    } catch (error) {
      setState(() => _pickerMessage = '没有可用的相机应用');
    }
  }

  void _remove(XFile file) {
    setState(() {
      _slides.removeWhere((item) => item.path == file.path);
      _previewIndex = 0;
    });
    _restartPreviewTimer();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final connected = viewModel.connection is BleConnected;
    final transfer = viewModel.transfer;
    final activeTransfer = transfer.kind == TransferKind.slideshow &&
            (transfer.running || transfer.message != null)
        ? transfer
        : null;
    final preparing = activeTransfer != null &&
        activeTransfer.running &&
        activeTransfer.totalBytes == 0;
    final busy = transfer.running;
    final current = _slides.isEmpty
        ? null
        : _slides[_previewIndex.clamp(0, _slides.length - 1).toInt()];

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          OverlayHeader(title: '多图轮播', onBack: widget.onBack),
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
                                child: Text(
                                  _slides.isEmpty ? '选择图片后预览' : '加载中…',
                                  style: textTheme.bodyMedium
                                      ?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              )
                            : FutureBuilder<Uint8List>(
                                future: viewModel.slideshowPreview(
                                  current,
                                  size: 368,
                                  maxSource: 1024,
                                ),
                                builder: (context, snapshot) {
                                  final bytes = snapshot.data;
                                  if (bytes == null) {
                                    return Center(
                                      child: Text(
                                        '加载中…',
                                        style: textTheme.bodyMedium?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    );
                                  }
                                  return SizedBox.expand(
                                    child: Image.memory(
                                      bytes,
                                      fit: BoxFit.cover,
                                      alignment: Alignment.center,
                                      gaplessPlayback: true,
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ConnectionPill(connected: connected),
                  const SizedBox(height: 26),
                  const _FormLabel('选择图片', alignStart: true),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _SlidePickButton(
                          label: '拍照',
                          icon: Icons.photo_camera_outlined,
                          enabled: !busy,
                          onClick: _takePhoto,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SlidePickButton(
                          label: '相册',
                          icon: Icons.image_outlined,
                          enabled: !busy,
                          onClick: _pickGallery,
                        ),
                      ),
                    ],
                  ),
                  if (_pickerMessage != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _pickerMessage!,
                        style: textTheme.bodySmall
                            ?.copyWith(color: scheme.error),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (_slides.isEmpty)
                    Container(
                      height: 88,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '尚未选择图片',
                        style: textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    )
                  else ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var index = 0; index < _slides.length; index++) ...[
                            if (index > 0) const SizedBox(width: 8),
                            _SlideThumb(
                              file: _slides[index],
                              preview: viewModel.slideshowPreview(
                                _slides[index],
                                size: 96,
                                maxSource: 256,
                              ),
                              onRemove: () => _remove(_slides[index]),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_slides.length}/${SlideshowLimits.maxImages} 张',
                        style: textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(child: _FormLabel('播放速度', alignStart: true)),
                      Text(
                        '~${(1000 / _intervalMs).round()} 张/秒 · '
                        '${_intervalMs}ms/张',
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
                  const SizedBox(height: 24),
                  BinUploadButton(
                    loading: activeTransfer?.running == true,
                    loadingText: preparing
                        ? '生成中…'
                        : '上传中 '
                            '${((activeTransfer?.fraction ?? 0) * 100).round()}%',
                    progress: preparing ? null : activeTransfer?.fraction,
                    enabled: connected && _slides.isNotEmpty && !busy,
                    onClick: () => viewModel.startSlideshowTransfer(
                      List<XFile>.from(_slides),
                      _intervalMs,
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
                    '传图可能耗时 10~60 秒，请勿退出页面。',
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

class _FormLabel extends StatelessWidget {
  const _FormLabel(this.text, {this.alignStart = false});

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

class _SlidePickButton extends StatelessWidget {
  const _SlidePickButton({
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
      height: 64,
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
              Icon(icon, size: 24),
              const SizedBox(width: 8),
              Text(label, style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlideThumb extends StatelessWidget {
  const _SlideThumb({
    required this.file,
    required this.preview,
    required this.onRemove,
  });

  final XFile file;
  final Future<Uint8List> preview;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 68,
      height: 68,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<Uint8List>(
                future: preview,
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (bytes == null) return const SizedBox.shrink();
                  return Image.memory(bytes, fit: BoxFit.cover);
                },
              ),
              Positioned(
                top: 3,
                right: 3,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '×',
                      style: TextStyle(color: Colors.white, fontSize: 14, height: 1),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
