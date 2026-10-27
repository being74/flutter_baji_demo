import 'package:flutter/material.dart';
import 'package:flutter_baji_demo/data/baji_repository.dart';
import 'package:flutter_baji_demo/ui/baji_view_model.dart';
import 'package:flutter_baji_demo/ui/screens/animation_screen.dart';
import 'package:flutter_baji_demo/ui/screens/log_screen.dart';
import 'package:flutter_baji_demo/ui/screens/marquee_screen.dart';
import 'package:flutter_baji_demo/ui/screens/profile_screen.dart';
import 'package:flutter_baji_demo/ui/screens/settings_screen.dart';
import 'package:flutter_baji_demo/ui/screens/slideshow_screen.dart';
import 'package:flutter_baji_demo/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('all screens render without layout errors', (tester) async {
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

    final screens = <String, Widget>{
      'settings': SettingsScreen(viewModel: viewModel, onBack: () {}),
      'logs': LogScreen(viewModel: viewModel, onBack: () {}),
      'animation': AnimationScreen(viewModel: viewModel, onBack: () {}),
      'marquee': MarqueeScreen(viewModel: viewModel, onBack: () {}),
      'slideshow': SlideshowScreen(viewModel: viewModel, onBack: () {}),
      'profile': ProfileScreen(viewModel: viewModel, onOpenLogs: () {}),
    };

    for (final entry in screens.entries) {
      await tester.pumpWidget(
        MaterialApp(
          theme: bajiTheme(Brightness.light),
          home: Scaffold(body: entry.value),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: entry.key);
    }
  });
}
