import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../media/image_codec.dart';
import '../baji_view_model.dart';

const double _cropRatio = 0.9;

/// 相册图片裁剪：固定 1:1 裁剪框，手势缩放/拖动，统一输出 368×368 像素。
class AlbumCropScreen extends StatefulWidget {
  const AlbumCropScreen({super.key, required this.viewModel});

  final BajiViewModel viewModel;

  @override
  State<AlbumCropScreen> createState() => _AlbumCropScreenState();
}

class _AlbumCropScreenState extends State<AlbumCropScreen> {
  Size _viewport = Size.zero;
  ui.Image? _image;
  double _zoom = 1;
  Offset? _offset;
  double _startZoom = 1;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;
  bool _busy = false;

  @override
  void dispose() {
    super.dispose();
  }

  void _syncImage(AlbumCropUiState state) {
    if (identical(_image, state.image)) return;
    _image = state.image;
    _zoom = 1;
    _offset = null;
  }

  double _cropSide() => math.min(_viewport.width, _viewport.height) * _cropRatio;

  Rect _cropRect() {
    final side = _cropSide();
    final left = (_viewport.width - side) / 2;
    final top = (_viewport.height - side) / 2;
    return Rect.fromLTWH(left, top, side, side);
  }

  double _baseScale() {
    final image = _image;
    if (image == null || _viewport.isEmpty) return 1;
    final side = _cropSide();
    return math.max(side / image.width, side / image.height);
  }

  Size _displaySize() {
    final image = _image;
    if (image == null) return Size.zero;
    final scale = _baseScale() * _zoom;
    return Size(image.width * scale, image.height * scale);
  }

  Offset _clampOffset(Offset proposed) {
    final image = _image;
    if (image == null || _viewport.isEmpty) return proposed;
    final crop = _cropRect();
    final size = _displaySize();
    final x = size.width <= crop.width
        ? crop.left + (crop.width - size.width) / 2
        : proposed.dx.clamp(crop.right - size.width, crop.left);
    final y = size.height <= crop.height
        ? crop.top + (crop.height - size.height) / 2
        : proposed.dy.clamp(crop.bottom - size.height, crop.top);
    return Offset(x, y);
  }

  Offset _initialOffset() {
    final size = _displaySize();
    return _clampOffset(
      Offset(
        (_viewport.width - size.width) / 2,
        (_viewport.height - size.height) / 2,
      ),
    );
  }

  Future<void> _confirm() async {
    final state = widget.viewModel.albumCrop;
    final image = _image;
    if (state == null || image == null || _viewport.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _cropToTargetSize(
        image,
        _viewport,
        _zoom,
        _offset ?? _initialOffset(),
        state.targetSize,
      );
      if (bytes != null) {
        await widget.viewModel.confirmAlbumCrop(bytes);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final state = widget.viewModel.albumCrop;
    if (state == null) return const Scaffold(body: SizedBox.shrink());
    _syncImage(state);

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    '裁剪相册图片 ${state.index + 1}/${state.total}',
                    style: textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : widget.viewModel.cancelAlbumCrop,
                    child: const Text('取消'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Center(
                  child: state.error != null && state.image == null
                      ? Text(
                          state.error!,
                          style: textTheme.bodyMedium
                              ?.copyWith(color: scheme.error),
                        )
                      : state.loading || state.image == null
                          ? const CircularProgressIndicator()
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final viewport = Size(
                                  constraints.maxWidth,
                                  constraints.maxHeight,
                                );
                                if (viewport != _viewport) {
                                  _viewport = viewport;
                                  _offset = null;
                                }
                                _offset ??= _initialOffset();
                                return GestureDetector(
                                  onScaleStart: (details) {
                                    _startZoom = _zoom;
                                    _startOffset = _offset!;
                                    _startFocal = details.localFocalPoint;
                                  },
                                  onScaleUpdate: (details) {
                                    final crop = _cropRect();
                                    final center = crop.center;
                                    final newZoom = (_startZoom * details.scale)
                                        .clamp(1.0, 4.0);
                                    final factor = newZoom / _startZoom;
                                    final proposed = center +
                                        (_startOffset - center) * factor +
                                        (details.localFocalPoint - _startFocal);
                                    setState(() {
                                      _zoom = newZoom;
                                      _offset = _clampOffset(proposed);
                                    });
                                  },
                                  child: CustomPaint(
                                    painter: _CropPainter(
                                      image: state.image!,
                                      zoom: _zoom,
                                      offset: _offset!,
                                      viewport: _viewport,
                                    ),
                                    size: Size.infinite,
                                  ),
                                );
                              },
                            ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '双指缩放、拖动调整位置；输出 '
                  '${state.targetSize}×${state.targetSize} 像素',
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: state.image != null &&
                          !state.loading &&
                          state.error == null &&
                          !_busy
                      ? _confirm
                      : null,
                  child: Text(
                    state.index + 1 < state.total ? '确认，裁剪下一张' : '确认并发送',
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

class _CropPainter extends CustomPainter {
  const _CropPainter({
    required this.image,
    required this.zoom,
    required this.offset,
    required this.viewport,
  });

  final ui.Image image;
  final double zoom;
  final Offset offset;
  final Size viewport;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    final side = math.min(size.width, size.height) * _cropRatio;
    final left = (size.width - side) / 2;
    final top = (size.height - side) / 2;
    final scale = math.max(side / image.width, side / image.height) * zoom;
    final destination = Rect.fromLTWH(
      offset.dx,
      offset.dy,
      image.width * scale,
      image.height * scale,
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      destination,
      Paint()..filterQuality = FilterQuality.high,
    );

    final mask = Paint()..color = Colors.black.withOpacity(0.55);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, top), mask);
    canvas.drawRect(
      Rect.fromLTWH(0, top + side, size.width, math.max(0, size.height - top - side)),
      mask,
    );
    canvas.drawRect(Rect.fromLTWH(0, top, left, side), mask);
    canvas.drawRect(
      Rect.fromLTWH(
        left + side,
        top,
        math.max(0, size.width - left - side),
        side,
      ),
      mask,
    );
    canvas.drawRect(
      Rect.fromLTWH(left, top, side, side),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _CropPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.zoom != zoom ||
      oldDelegate.offset != offset ||
      oldDelegate.viewport != viewport;
}

Future<Uint8List?> _cropToTargetSize(
  ui.Image image,
  Size viewport,
  double zoom,
  Offset offset,
  int targetSize,
) async {
  if (viewport.isEmpty) return null;
  final side = math.min(viewport.width, viewport.height) * _cropRatio;
  final left = (viewport.width - side) / 2;
  final top = (viewport.height - side) / 2;
  final scale = math.max(side / image.width, side / image.height) * zoom;
  if (scale <= 0) return null;

  final srcLeft =
      ((left - offset.dx) / scale).round().clamp(0, image.width - 1);
  final srcTop =
      ((top - offset.dy) / scale).round().clamp(0, image.height - 1);
  final srcSize = (side / scale).round().clamp(
        1,
        math.min(image.width - srcLeft, image.height - srcTop),
      );

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final out = targetSize < 1 ? 1 : targetSize;
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(
      srcLeft.toDouble(),
      srcTop.toDouble(),
      srcSize.toDouble(),
      srcSize.toDouble(),
    ),
    Rect.fromLTWH(0, 0, out.toDouble(), out.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(out, out);
  try {
    final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    return encodeRgbaJpeg(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      width: out,
      height: out,
      quality: 90,
    );
  } finally {
    rendered.dispose();
    picture.dispose();
  }
}
