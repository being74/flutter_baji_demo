import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_baji_demo/data/baji_repository.dart';
import 'package:flutter_baji_demo/media/media_files.dart';
import 'package:flutter_baji_demo/ui/baji_view_model.dart';
import 'package:flutter_baji_demo/ui/widgets/animation_preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('source sampling uses a fixed step independent of playback speed',
      () async {
    final dir = await Directory.systemTemp.createTemp('baji_anim_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/source.gif');
    final gif = _threeFrameGif();
    await file.writeAsBytes(gif);

    final repository = BajiRepository();
    final viewModel = BajiViewModel(repository);
    addTearDown(() async {
      viewModel.dispose();
      await repository.close();
    });

    await viewModel.selectAnimationSource(
      PickedMedia(name: 'source.gif', path: file.path, bytes: gif),
    );

    final source = viewModel.animationSource;
    expect(source, isNotNull);
    expect(source!.kind, AnimationKind.gif);
    expect(source.durationMs, 300);
    expect(source.frames.length, 3, reason: '3×100ms 的源固定按 100ms 采样');
  });

  testWidgets('preview advances frames at the given interval', (tester) async {
    final frames = [
      _jpeg(img.ColorRgb8(255, 0, 0)),
      _jpeg(img.ColorRgb8(0, 255, 0)),
      _jpeg(img.ColorRgb8(0, 0, 255)),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimationPreview(frames: frames, intervalMs: 100),
        ),
      ),
    );

    Uint8List shownFrame() {
      final image = tester.widget<Image>(find.byType(Image));
      return (image.image as MemoryImage).bytes;
    }

    expect(shownFrame(), frames[0]);
    await tester.pump(const Duration(milliseconds: 100));
    expect(shownFrame(), frames[1]);
    await tester.pump(const Duration(milliseconds: 100));
    expect(shownFrame(), frames[2]);
    await tester.pump(const Duration(milliseconds: 100));
    expect(shownFrame(), frames[0], reason: '帧序列应循环播放');
  });

  testWidgets('changing interval changes playback speed', (tester) async {
    final frames = [
      _jpeg(img.ColorRgb8(255, 0, 0)),
      _jpeg(img.ColorRgb8(0, 255, 0)),
      _jpeg(img.ColorRgb8(0, 0, 255)),
    ];

    Widget preview(int intervalMs) => MaterialApp(
          home: Scaffold(
            body: AnimationPreview(frames: frames, intervalMs: intervalMs),
          ),
        );

    await tester.pumpWidget(preview(100));
    await tester.pump(const Duration(milliseconds: 100));
    final fastFrame = _shownFrame(tester);

    await tester.pumpWidget(preview(999));
    await tester.pump();
    final slowFirst = _shownFrame(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_shownFrame(tester), slowFirst, reason: '999ms/帧 时 100ms 内不应切帧');
    await tester.pump(const Duration(milliseconds: 899));
    expect(_shownFrame(tester), isNot(slowFirst));
    expect(_shownFrame(tester), isNot(fastFrame));
  });

  testWidgets('empty frames show an error placeholder', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AnimationPreview(frames: [], intervalMs: 100),
        ),
      ),
    );

    expect(find.text('无法预览'), findsOneWidget);
  });
}

Uint8List _shownFrame(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image));
  return (image.image as MemoryImage).bytes;
}

Uint8List _jpeg(img.ColorRgb8 color) {
  final image = img.Image(width: 8, height: 8);
  img.fill(image, color: color);
  return Uint8List.fromList(img.encodeJpg(image));
}

Uint8List _threeFrameGif() {
  img.Image? animation;
  for (final color in [
    img.ColorRgb8(255, 0, 0),
    img.ColorRgb8(0, 255, 0),
    img.ColorRgb8(0, 0, 255),
  ]) {
    final frame = img.Image(width: 120, height: 120)..frameDuration = 100;
    img.fill(frame, color: color);
    animation = animation == null ? frame : (animation..addFrame(frame));
  }
  return Uint8List.fromList(img.encodeGif(animation!));
}
