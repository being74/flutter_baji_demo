import 'package:flutter/material.dart';

import 'data/baji_repository.dart';
import 'ui/baji_app.dart';
import 'ui/baji_view_model.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = BajiRepository();
  final viewModel = BajiViewModel(repository);
  runApp(
    MaterialApp(
      title: 'BajiDemo',
      debugShowCheckedModeBanner: false,
      theme: bajiTheme(Brightness.light),
      darkTheme: bajiTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: BajiApp(viewModel: viewModel),
    ),
  );
}
