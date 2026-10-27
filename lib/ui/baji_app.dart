import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'baji_view_model.dart';
import 'screens/album_crop_screen.dart';
import 'screens/animation_screen.dart';
import 'screens/home_screen.dart';
import 'screens/log_screen.dart';
import 'screens/marquee_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/slideshow_screen.dart';
import 'widgets/baji_widgets.dart';

enum _Overlay { none, settings, logs, animation, marquee, slideshow }

class BajiApp extends StatefulWidget {
  const BajiApp({super.key, required this.viewModel});

  final BajiViewModel viewModel;

  @override
  State<BajiApp> createState() => _BajiAppState();
}

class _BajiAppState extends State<BajiApp> {
  int _tab = 0;
  _Overlay _overlay = _Overlay.none;
  StreamSubscription<String>? _messageSubscription;
  final ScrollController _homeScrollController = ScrollController();
  double? _savedHomeOffset;
  bool _wasCrop = false;

  BajiViewModel get viewModel => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _wasCrop = viewModel.albumCrop != null;
    viewModel.addListener(_onViewModelChangedForScroll);
    _messageSubscription = viewModel.messages.listen((message) {
      // 等当前帧的 Scaffold 注册完成后再显示，避免相册裁剪页切换时
      // ScaffoldMessenger 找不到 descendant Scaffold。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      });
    });
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    viewModel.removeListener(_onViewModelChangedForScroll);
    _homeScrollController.dispose();
    super.dispose();
  }

  void _saveHomeOffset() {
    if (!_homeScrollController.hasClients) return;
    _savedHomeOffset = _homeScrollController.offset;
  }

  void _restoreHomeOffsetAfterFrame() {
    final offset = _savedHomeOffset;
    if (offset == null) return;
    _savedHomeOffset = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_homeScrollController.hasClients) return;
      final max = _homeScrollController.position.maxScrollExtent;
      _homeScrollController.jumpTo(offset.clamp(0.0, max));
    });
  }

  void _onViewModelChangedForScroll() {
    final showingCrop = viewModel.albumCrop != null;
    if (showingCrop && !_wasCrop) {
      _saveHomeOffset();
    } else if (!showingCrop && _wasCrop && _overlay == _Overlay.none) {
      _restoreHomeOffsetAfterFrame();
    }
    _wasCrop = showingCrop;
  }

  void _openOverlay(_Overlay overlay) {
    _saveHomeOffset();
    setState(() => _overlay = overlay);
  }

  void _closeOverlay() {
    if (_overlay == _Overlay.none) return;
    setState(() => _overlay = _Overlay.none);
    _restoreHomeOffsetAfterFrame();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        // albumCrop 必须在监听器内部读取：裁剪流程结束时它会变为 null，
        // 若在 build 外层捕获，页面会停留在已释放的裁剪页上。
        final crop = viewModel.albumCrop;
        final dark = Theme.of(context).brightness == Brightness.dark;
        final lightIcons =
            crop == null && _overlay == _Overlay.none && _tab == 0;
        final overlayStyle = SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: lightIcons || dark
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: lightIcons || dark
              ? Brightness.dark
              : Brightness.light,
          systemNavigationBarColor: Theme.of(context).colorScheme.surface,
          systemNavigationBarIconBrightness:
              dark ? Brightness.light : Brightness.dark,
        );

        final overlay = _buildOverlay();
        final showingSecondary = overlay != null || crop != null;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayStyle,
          child: Scaffold(
            resizeToAvoidBottomInset: true,
            body: PopScope(
              canPop: !showingSecondary,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                if (crop != null) {
                  viewModel.cancelAlbumCrop();
                  return;
                }
                if (overlay != null) _closeOverlay();
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 首页始终保留在树中；打开/关闭二级页面时通过
                  // ScrollController 恢复滚动位置，避免底栏高度变化截断。
                  _buildTabs(),
                  if (overlay != null) Positioned.fill(child: overlay),
                  if (crop != null)
                    Positioned.fill(child: AlbumCropScreen(viewModel: viewModel)),
                ],
              ),
            ),
            bottomNavigationBar: showingSecondary
                ? null
                : BajiBottomBar(
                    selected: _tab,
                    onSelect: (index) => setState(() => _tab = index),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildTabs() => IndexedStack(
        index: _tab,
        children: [
          HomeScreen(
            viewModel: viewModel,
            scrollController: _homeScrollController,
            onOpenSettings: () => _openOverlay(_Overlay.settings),
            onOpenAnimation: () => _openOverlay(_Overlay.animation),
            onOpenMarquee: () => _openOverlay(_Overlay.marquee),
            onOpenSlideshow: () => _openOverlay(_Overlay.slideshow),
          ),
          ProfileScreen(
            viewModel: viewModel,
            onOpenLogs: () => _openOverlay(_Overlay.logs),
          ),
        ],
      );

  Widget? _buildOverlay() => switch (_overlay) {
        _Overlay.none => null,
        _Overlay.settings => SettingsScreen(
            viewModel: viewModel,
            onBack: _closeOverlay,
          ),
        _Overlay.logs => LogScreen(
            viewModel: viewModel,
            onBack: _closeOverlay,
          ),
        _Overlay.animation => AnimationScreen(
            viewModel: viewModel,
            onBack: _closeOverlay,
          ),
        _Overlay.marquee => MarqueeScreen(
            viewModel: viewModel,
            onBack: _closeOverlay,
          ),
        _Overlay.slideshow => SlideshowScreen(
            viewModel: viewModel,
            onBack: _closeOverlay,
          ),
      };
}
