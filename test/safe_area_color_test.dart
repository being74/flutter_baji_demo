import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_baji_demo/data/baji_repository.dart';
import 'package:flutter_baji_demo/ui/baji_app.dart';
import 'package:flutter_baji_demo/ui/baji_view_model.dart';
import 'package:flutter_baji_demo/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

Color? _navigationBarColor(WidgetTester tester) => tester
    .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
    )
    .value
    .systemNavigationBarColor;

Future<BajiViewModel> _pumpApp(WidgetTester tester, ThemeData theme) async {
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
      theme: theme,
      home: BajiApp(viewModel: viewModel),
    ),
  );
  await tester.pumpAndSettle();
  return viewModel;
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'bottom system bar matches the page background ($brightness)',
      (tester) async {
        final theme = bajiTheme(brightness);
        await _pumpApp(tester, theme);

        // 首页底部是 surface 色的导航栏，系统导航栏跟随它。
        expect(_navigationBarColor(tester), theme.colorScheme.surface);

        final button = find.text('选择 GIF / 视频');
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();

        expect(find.text('选择动图'), findsOneWidget);
        // 动图页铺 scaffoldBackgroundColor，系统导航栏必须同色，
        // 否则底部会出现一条与页面不一致的白色安全区。
        expect(_navigationBarColor(tester), theme.scaffoldBackgroundColor);

        await tester.tap(find.text('←'));
        await tester.pumpAndSettle();
        expect(find.text('选择动图'), findsNothing);
        expect(_navigationBarColor(tester), theme.colorScheme.surface);
      },
    );
  }

  testWidgets('album crop keeps the surface bar matching its page', (
    tester,
  ) async {
    final theme = bajiTheme(Brightness.light);
    final viewModel = await _pumpApp(tester, theme);

    final source = img.Image(width: 64, height: 48);
    img.fill(source, color: img.ColorRgb8(40, 80, 160));
    final bytes = img.encodeJpg(source, quality: 90);
    viewModel.beginAlbumCrop([XFile.fromData(bytes, name: 'album.jpg')]);
    await tester.pump();

    expect(find.text('裁剪相册图片 1/1'), findsOneWidget);
    // 裁剪页的 Scaffold 底色是 surface，系统导航栏保持 surface。
    expect(_navigationBarColor(tester), theme.colorScheme.surface);
  });
}
