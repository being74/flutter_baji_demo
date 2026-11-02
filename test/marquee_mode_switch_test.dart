import 'package:flutter/material.dart';
import 'package:flutter_baji_demo/data/baji_repository.dart';
import 'package:flutter_baji_demo/ui/baji_view_model.dart';
import 'package:flutter_baji_demo/ui/screens/marquee_screen.dart';
import 'package:flutter_baji_demo/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'marquee screen defaults to single-image and switches to scroll',
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
          home: Scaffold(
            body: MarqueeScreen(viewModel: viewModel, onBack: () {}),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('单图轮播'), findsOneWidget);
      expect(find.text('文字滚动'), findsOneWidget);
      expect(find.text('单图轮播 · 每个字一张 368×368 全屏图'), findsOneWidget);
      expect(find.text('500ms/字'), findsOneWidget);
      expect(find.text('260px'), findsOneWidget);

      await tester.tap(find.text('文字滚动'));
      await tester.pump();

      expect(find.text('文字滚动 · 整句从右向左滚动'), findsOneWidget);
      expect(find.text('每轮 4.5 秒 · 150ms/帧'), findsOneWidget);
      expect(find.text('200px'), findsOneWidget);

      tester.widget<Slider>(find.byType(Slider).first).onChanged!(24);
      await tester.pump();
      expect(find.text('160px'), findsOneWidget);

      tester.widget<Slider>(find.byType(Slider).last).onChanged!(0);
      await tester.pump();
      expect(find.text('每轮 6 秒 · 200ms/帧'), findsOneWidget);

      await tester.tap(find.text('单图轮播'));
      await tester.pump();
      expect(find.text('500ms/字'), findsOneWidget);
      expect(find.text('260px'), findsOneWidget);

      await tester.tap(find.text('文字滚动'));
      await tester.pump();
      expect(find.text('每轮 6 秒 · 200ms/帧'), findsOneWidget);
      expect(find.text('160px'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '滚动文字');
      await tester.pump();
      expect(find.text('文字滚动 · 整句从右向左滚动，共 30 帧'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 220));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    },
  );
}
