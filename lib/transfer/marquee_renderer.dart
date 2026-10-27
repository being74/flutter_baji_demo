import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../media/image_codec.dart';
import 'marquee_layout.dart';

/// 跑马灯的两种玩法。
enum MarqueeMode {
  /// 整句横向滚动；无论文字长短固定生成 30 帧。
  scroll,

  /// 每个字一张全屏大图，逐字轮播。
  character,
}

class MarqueeStyle {
  const MarqueeStyle({
    required this.text,
    required this.fontSize,
    required this.textColor,
    required this.backgroundColor,
    this.mode = MarqueeMode.scroll,
  });

  final String text;
  final int fontSize;
  final int textColor;
  final int backgroundColor;
  final MarqueeMode mode;
}

/// 把跑马灯文字画进 368×368 的静态帧；帧序列最终走动图 bin 容器。
abstract final class MarqueeRenderer {
  static const int maxTextLength = 10;
  static const int minFontSize = 24;
  static const int maxFontSize = 96;
  static const int defaultFontSize = 48;

  static const double _characterMinSize = 220;
  static const double _characterMaxSize = 340;

  static List<String> characterFrames(String text) =>
      text.split('').where((character) => character.trim().isNotEmpty).toList();

  static List<double> frameOffsets(MarqueeStyle style) {
    if (style.text.trim().isEmpty) return const [];
    return MarqueeLayout.offsets(measureText(style));
  }

  static double measureText(MarqueeStyle style) =>
      _buildPainter(style, style.fontSize.toDouble()).width;

  /// 逐字模式：一个字符铺满一帧；字号滑杆映射到 220–340px。
  static double characterFontSize(MarqueeStyle style) {
    final progress = (style.fontSize - minFontSize) / (maxFontSize - minFontSize);
    return _characterMinSize +
        progress.clamp(0.0, 1.0) * (_characterMaxSize - _characterMinSize);
  }

  /// 预览与导出共用：滚动模式的整句帧。
  static void paintFrame(Canvas canvas, MarqueeStyle style, double offsetX) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 368.0, 368.0),
      Paint()..color = Color(style.backgroundColor),
    );
    if (style.text.isEmpty) return;
    final painter = _buildPainter(style, style.fontSize.toDouble());
    _paintCentered(canvas, painter, offsetX);
  }

  /// 预览与导出共用：逐字模式的一帧。
  static void paintCharacterFrame(
    Canvas canvas,
    MarqueeStyle style,
    String character, {
    Offset inkCorrection = Offset.zero,
  }) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 368.0, 368.0),
      Paint()..color = Color(style.backgroundColor),
    );
    if (character.trim().isEmpty) return;
    final painter = buildCharacterPainter(style, character);
    canvas.save();
    canvas.translate(inkCorrection.dx, inkCorrection.dy);
    _paintCentered(canvas, painter, (MarqueeLayout.size - painter.width) / 2);
    canvas.restore();
  }

  /// 以字体 ascent/descent 的中点对齐画布中心，和原生 drawText 的
  /// baseline 计算保持一致；直接按 TextPainter 高度居中会因行高偏上。
  static void _paintCentered(Canvas canvas, TextPainter painter, double x) {
    final metrics = painter.computeLineMetrics();
    final double y;
    if (metrics.isEmpty) {
      y = (MarqueeLayout.size - painter.height) / 2;
    } else {
      final line = metrics.first;
      final baseline =
          MarqueeLayout.size / 2 + (line.ascent - line.descent) / 2;
      y = baseline - line.baseline;
    }
    painter.paint(canvas, Offset(x, y));
  }

  /// 逐字模式的单字排版器；单独暴露给测试校验只排入当前字符。
  static TextPainter buildCharacterPainter(
    MarqueeStyle style,
    String character,
  ) =>
      _buildPainter(
        style,
        characterFontSize(style),
        center: true,
        text: character,
      );

  /// 输出 368×368 JPEG（质量 90）帧列表，供动图 bin 封装。
  static Future<List<Uint8List>> renderJpegFrames(
    MarqueeStyle style, {
    int quality = 90,
  }) async {
    final outputs = <Uint8List>[];
    if (style.mode == MarqueeMode.character) {
      for (final character in characterFrames(style.text)) {
        final correction = await _characterInkCorrection(style, character);
        outputs.add(
          await _renderFrame(
            (canvas) => paintCharacterFrame(
              canvas,
              style,
              character,
              inkCorrection: correction,
            ),
            quality: quality,
          ),
        );
      }
      return outputs;
    }
    for (final offset in frameOffsets(style)) {
      outputs.add(
        await _renderFrame(
          (canvas) => paintFrame(canvas, style, offset),
          quality: quality,
        ),
      );
    }
    return outputs;
  }

  /// 渲染一次后测量文字墨迹包围盒，返回把它移到画布中心的修正量。
  static Future<Offset> _characterInkCorrection(
    MarqueeStyle style,
    String character,
  ) async {
    final image = await _drawFrame(
      (canvas) => paintCharacterFrame(canvas, style, character),
    );
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return Offset.zero;
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final width = image.width;
      final height = image.height;
      final background = style.backgroundColor;
      final bgR = (background >> 16) & 0xFF;
      final bgG = (background >> 8) & 0xFF;
      final bgB = background & 0xFF;
      var minX = width;
      var minY = height;
      var maxX = -1;
      var maxY = -1;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final index = (y * width + x) * 4;
          final diff = (bytes[index] - bgR).abs() +
              (bytes[index + 1] - bgG).abs() +
              (bytes[index + 2] - bgB).abs();
          if (diff < 24) continue;
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
      if (maxX < minX || maxY < minY) return Offset.zero;
      return Offset(
        width / 2 - (minX + maxX) / 2,
        height / 2 - (minY + maxY) / 2,
      );
    } finally {
      image.dispose();
    }
  }

  static Future<ui.Image> _drawFrame(void Function(Canvas canvas) draw) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, 368.0, 368.0),
    );
    draw(canvas);
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(MarqueeLayout.size, MarqueeLayout.size);
    } finally {
      picture.dispose();
    }
  }

  static Future<Uint8List> _renderFrame(
    void Function(Canvas canvas) draw, {
    required int quality,
  }) async {
    final image = await _drawFrame(draw);
    try {
      return await encodeUiImageJpeg(image, quality: quality);
    } finally {
      image.dispose();
    }
  }

  static TextPainter _buildPainter(
    MarqueeStyle style,
    double textSize, {
    bool center = false,
    String? text,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text ?? style.text,
        style: TextStyle(
          color: Color(style.textColor),
          fontSize: textSize,
          fontWeight: FontWeight.bold,
        ),
      ),
      textAlign: center ? TextAlign.center : TextAlign.left,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );
    painter.layout();
    return painter;
  }
}
