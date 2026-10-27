import 'package:flutter/material.dart';
import 'package:flutter_baji_demo/data/baji_repository.dart';
import 'package:flutter_baji_demo/ui/baji_app.dart';
import 'package:flutter_baji_demo/ui/baji_view_model.dart';
import 'package:flutter_baji_demo/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home and profile render without a device', (tester) async {
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

    expect(find.text('吧唧'), findsOneWidget);
    expect(find.text('还没扣上。'), findsOneWidget);
    expect(find.text('相册'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('跑马灯'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('动态氛围'), findsOneWidget);
    expect(find.text('多图轮播'), findsOneWidget);
    expect(find.text('跑马灯'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('设备与协议'), findsOneWidget);
    expect(find.text('激活状态'), findsOneWidget);
  });
}
