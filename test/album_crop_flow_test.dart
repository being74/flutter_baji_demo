import 'package:flutter/material.dart';
import 'package:flutter_baji_demo/data/baji_repository.dart';
import 'package:flutter_baji_demo/ui/baji_app.dart';
import 'package:flutter_baji_demo/ui/baji_view_model.dart';
import 'package:flutter_baji_demo/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

void main() {
  testWidgets('album crop opens immediately and restores main shell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repository = BajiRepository();
    final viewModel = BajiViewModel(repository);
    addTearDown(() async {
      viewModel.dispose();
      await repository.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: bajiTheme(Brightness.light),
        home: BajiApp(viewModel: viewModel),
      ),
    );
    await tester.pumpAndSettle();

    final source = img.Image(width: 64, height: 48);
    img.fill(source, color: img.ColorRgb8(40, 80, 160));
    final bytes = img.encodeJpg(source, quality: 90);
    final file = XFile.fromData(bytes, name: 'album.jpg');

    viewModel.beginAlbumCrop([file]);
    await tester.pump();

    expect(find.text('裁剪相册图片 1/1'), findsOneWidget);
    expect(find.text('确认并发送'), findsOneWidget);

    // A message while the crop screen owns the only Scaffold must not assert.
    viewModel.showMessage('测试提示');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('测试提示'), findsOneWidget);

    // Closing the crop screen must restore the main Scaffold immediately.
    viewModel.cancelAlbumCrop();
    await tester.pump();
    expect(find.text('裁剪相册图片 1/1'), findsNothing);
    expect(find.text('吧唧'), findsOneWidget);

    viewModel.showMessage('已回到首页');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
