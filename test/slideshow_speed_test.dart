import 'package:flutter/material.dart';
import 'package:flutter_baji_demo/data/baji_repository.dart';
import 'package:flutter_baji_demo/ui/baji_view_model.dart';
import 'package:flutter_baji_demo/ui/screens/slideshow_screen.dart';
import 'package:flutter_baji_demo/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('slideshow slowest speed is one image per five seconds',
      (tester) async {
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
        home: Scaffold(body: SlideshowScreen(viewModel: viewModel, onBack: () {})),
      ),
    );
    await tester.pump();

    tester.widget<Slider>(find.byType(Slider)).onChanged!(0);
    await tester.pump();

    expect(find.text('每 5 秒 1 张'), findsOneWidget);
  });
}
