import 'package:flutter/material.dart';
import 'package:flutter_baji_demo/data/baji_repository.dart';
import 'package:flutter_baji_demo/ui/baji_app.dart';
import 'package:flutter_baji_demo/ui/baji_view_model.dart';
import 'package:flutter_baji_demo/ui/screens/home_screen.dart';
import 'package:flutter_baji_demo/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home scroll offset survives a secondary page', (tester) async {
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

    ScrollableState homeScrollable() => tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(HomeScreen),
                matching: find.byType(Scrollable),
              )
              .first,
        );

    await tester.drag(find.byType(ListView).first, const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(homeScrollable().position.pixels, greaterThan(0));

    final button = find.text('选择 GIF / 视频');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    final before = homeScrollable().position.pixels;

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('选择动图'), findsOneWidget);

    await tester.tap(find.text('←'));
    await tester.pumpAndSettle();

    expect(find.text('选择动图'), findsNothing);
    expect(homeScrollable().position.pixels, closeTo(before, 0.5));
  });
}
