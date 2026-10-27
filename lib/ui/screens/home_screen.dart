import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../ble/baji_ble_client.dart';
import '../../ble/baji_scanner.dart';
import '../../ble/ble_permissions.dart';
import '../../data/reconnect_state.dart';
import '../../media/media_files.dart';
import '../baji_view_model.dart';
import '../theme.dart';
import '../widgets/baji_widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.viewModel,
    this.scrollController,
    required this.onOpenSettings,
    required this.onOpenAnimation,
    required this.onOpenMarquee,
    required this.onOpenSlideshow,
  });

  final BajiViewModel viewModel;
  final ScrollController? scrollController;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAnimation;
  final VoidCallback onOpenMarquee;
  final VoidCallback onOpenSlideshow;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool? _permissionsGranted;
  bool _pairedExpanded = false;
  bool _showDevicePicker = false;
  bool _wasConnected = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    widget.viewModel.addListener(_onViewModelChanged);
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelChanged);
    super.dispose();
  }

  void _onViewModelChanged() {
    final connected = widget.viewModel.connection is BleConnected;
    if (connected && !_wasConnected) {
      _showDevicePicker = false;
    }
    _wasConnected = connected;
  }

  Future<void> _checkPermissions() async {
    final granted = await BlePermissions.granted();
    if (!mounted) return;
    setState(() => _permissionsGranted = granted);
    if (granted) {
      widget.viewModel.refreshBondedDevices();
    }
  }

  Future<void> _startScan() async {
    final granted = _permissionsGranted ?? await BlePermissions.granted();
    if (!mounted) return;
    if (!granted) {
      final result = await BlePermissions.request();
      if (!mounted) return;
      setState(() => _permissionsGranted = result);
      if (!result) return;
    }
    if (Platform.isAndroid && !await BlePermissions.isBluetoothEnabled()) {
      await BlePermissions.requestEnable();
      if (!await BlePermissions.isBluetoothEnabled()) {
        widget.viewModel.showMessage('请先在系统设置中打开蓝牙');
        return;
      }
    }
    widget.viewModel.refreshBondedDevices();
    widget.viewModel.toggleScan();
  }

  Future<void> _pickAlbum() async {
    final files = await MediaFiles.pickAlbumImages();
    if (files.isNotEmpty) {
      widget.viewModel.startAlbumTransfer(files);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final connection = vm.connection;
    final connected = connection is BleConnected;
    final canSend = connected && !vm.transfer.running;
    final scanned = vm.devices
        .where(
          (device) =>
              (device.name ?? '').isNotEmpty &&
              !vm.bondedDevices.any((bonded) => bonded.address == device.address),
        )
        .toList();

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ListView(
        controller: widget.scrollController,
        padding: EdgeInsets.zero,
        children: [
          _ConnectionHero(
            connection: connection,
            reconnect: vm.reconnect,
            scanning: vm.scanning,
            permissionsGranted: _permissionsGranted != false,
            onScan: _startScan,
            onDisconnect: vm.disconnect,
            onOpenSettings: widget.onOpenSettings,
          ),
          if (!connected || _showDevicePicker)
            _DevicePicker(
              scanning: vm.scanning,
              devices: scanned,
              bondedDevices: vm.bondedDevices,
              pairedExpanded: _pairedExpanded,
              showScanAction: connected,
              onTogglePaired: () => setState(() => _pairedExpanded = !_pairedExpanded),
              onScan: _startScan,
              onConnect: vm.connect,
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _showDevicePicker = true),
                    child: Text(
                      '更换设备',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: SectionTitle(
              title: '今天放什么',
              subtitle: connected
                  ? '选一样，扣上就出门。'
                  : '先连上它；跑马灯和动图可以先配置。',
            ),
          ),
          if (vm.transfer.running || vm.transfer.message != null)
            TransferProgressCard(
              transfer: vm.transfer,
              onCancel: vm.cancelTransfer,
            ),
          _AlbumCard(enabled: canSend, onPick: _pickAlbum),
          _AmbienceCard(enabled: !vm.transfer.running, onOpen: widget.onOpenAnimation),
          _SlideshowCard(enabled: !vm.transfer.running, onOpen: widget.onOpenSlideshow),
          _MarqueeCard(enabled: !vm.transfer.running, onOpen: widget.onOpenMarquee),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

class _ConnectionHero extends StatelessWidget {
  const _ConnectionHero({
    required this.connection,
    required this.reconnect,
    required this.scanning,
    required this.permissionsGranted,
    required this.onScan,
    required this.onDisconnect,
    required this.onOpenSettings,
  });

  final BleConnectionState connection;
  final ReconnectState reconnect;
  final bool scanning;
  final bool permissionsGranted;
  final Future<void> Function() onScan;
  final Future<void> Function() onDisconnect;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      color: cobalt,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('吧唧', style: textTheme.headlineMedium?.copyWith(color: chalk)),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      'baji',
                      style: textTheme.labelSmall?.copyWith(
                        color: chalk.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  const Spacer(),
                  InkResponse(
                    onTap: onOpenSettings,
                    radius: 24,
                    child: SizedBox(
                      width: 42,
                      height: 42,
                      child: Center(
                        child: DotGridIcon(color: chalk),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              switch (connection) {
                BleConnected() => _connected(context),
                BleConnecting() => _connecting(context),
                BleFailed() => _failed(context),
                BleDisconnected() => _disconnected(context),
              },
              if (reconnect.active) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    const StatusDot(color: butter),
                    const SizedBox(width: 8),
                    Text(
                      reconnect.watching
                          ? '重试 ${reconnect.total} 次未成功，继续等待设备广播…'
                          : '自动重连 第 ${reconnect.attempt}/${reconnect.total} 次',
                      style: textTheme.labelLarge?.copyWith(color: chalk),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _connected(BuildContext context) {
    final state = connection as BleConnected;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const StatusDot(color: butter),
            const SizedBox(width: 8),
            Text(
              '已连接',
              style: textTheme.labelLarge?.copyWith(color: butter),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          state.name ?? 'e-BADGE',
          style: textTheme.displayLarge?.copyWith(color: chalk),
        ),
        const SizedBox(height: 6),
        Text(
          '${state.address} · MTU ${state.mtu}',
          style: textTheme.bodySmall?.copyWith(color: chalk.withValues(alpha: 0.62)),
        ),
        const SizedBox(height: 22),
        OutlinePill(
          text: '断开连接',
          onClick: onDisconnect,
          contentColor: chalk,
          borderColor: chalk.withValues(alpha: 0.55),
        ),
      ],
    );
  }

  Widget _connecting(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('正在靠近…', style: textTheme.displayLarge?.copyWith(color: chalk)),
        const SizedBox(height: 8),
        Text(
          '正在建立 GATT 连接并协商 MTU',
          style: textTheme.bodyMedium?.copyWith(color: chalk.withValues(alpha: 0.78)),
        ),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            minHeight: 4,
            backgroundColor: chalk.withValues(alpha: 0.2),
            valueColor: const AlwaysStoppedAnimation<Color>(butter),
          ),
        ),
      ],
    );
  }

  Widget _failed(BuildContext context) {
    final state = connection as BleFailed;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('没连上。', style: textTheme.displayLarge?.copyWith(color: chalk)),
        const SizedBox(height: 8),
        Text(
          state.message,
          style: textTheme.bodyMedium?.copyWith(color: chalk.withValues(alpha: 0.78)),
        ),
        const SizedBox(height: 20),
        FilledPill(
          text: scanning ? '停止扫描' : '再试一次',
          onClick: onScan,
          containerColor: butter,
          contentColor: ink,
        ),
      ],
    );
  }

  Widget _disconnected(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('还没扣上。', style: textTheme.displayLarge?.copyWith(color: chalk)),
        const SizedBox(height: 8),
        Text(
          '打开蓝牙，靠近它，两秒内自己报到。',
          style: textTheme.bodyMedium?.copyWith(color: chalk.withValues(alpha: 0.78)),
        ),
        const SizedBox(height: 22),
        FilledPill(
          text: scanning ? '停止扫描' : '扫描设备',
          onClick: onScan,
          containerColor: butter,
          contentColor: ink,
        ),
        if (!permissionsGranted) ...[
          const SizedBox(height: 10),
          Text(
            '需要蓝牙权限才能扫描',
            style: textTheme.bodySmall?.copyWith(color: const Color(0xFFFFC9B8)),
          ),
        ],
      ],
    );
  }
}

class _DevicePicker extends StatelessWidget {
  const _DevicePicker({
    required this.scanning,
    required this.devices,
    required this.bondedDevices,
    required this.pairedExpanded,
    required this.showScanAction,
    required this.onTogglePaired,
    required this.onScan,
    required this.onConnect,
  });

  final bool scanning;
  final List<BajiDevice> devices;
  final List<BajiDevice> bondedDevices;
  final bool pairedExpanded;
  final bool showScanAction;
  final VoidCallback onTogglePaired;
  final Future<void> Function() onScan;
  final Future<void> Function(String address) onConnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('附近设备', style: textTheme.titleLarge),
              const Spacer(),
              if (showScanAction)
                TextButton(
                  onPressed: onScan,
                  child: Text(scanning ? '停止扫描' : '扫描'),
                )
              else if (scanning)
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '扫描中…',
                      style: textTheme.labelMedium?.copyWith(color: scheme.primary),
                    ),
                  ],
                ),
            ],
          ),
          if (bondedDevices.isNotEmpty) ...[
            InkWell(
              onTap: onTogglePaired,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Text(
                      '已配对（${bondedDevices.length}）',
                      style: textTheme.labelMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const Spacer(),
                    Text(
                      pairedExpanded ? '收起' : '展开',
                      style: textTheme.labelMedium?.copyWith(color: scheme.primary),
                    ),
                  ],
                ),
              ),
            ),
            if (pairedExpanded)
              ...bondedDevices.map(
                (device) => _DeviceRow(
                  device: device,
                  paired: true,
                  onConnect: onConnect,
                ),
              ),
          ],
          if (devices.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Text(
                '扫描结果',
                style: textTheme.labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            ...devices.map(
              (device) => _DeviceRow(
                device: device,
                paired: false,
                onConnect: onConnect,
              ),
            ),
          ],
          if (bondedDevices.isEmpty && devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                scanning
                    ? '正在搜索 e-BADGE…'
                    : showScanAction
                        ? '没有发现设备。确认它已开机，再扫描。'
                        : '没有发现设备。确认它已开机，点上方按钮重试。',
                style: textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          Divider(color: scheme.outlineVariant, height: 1),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.paired,
    required this.onConnect,
  });

  final BajiDevice device;
  final bool paired;
  final Future<void> Function(String address) onConnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          StatusDot(
            color: device.hasTargetService
                ? cobalt
                : scheme.outline.withValues(alpha: 0.35),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name ?? '', style: textTheme.titleMedium),
                Text(
                  paired
                      ? '已配对 · ${device.address}'
                      : '${device.address} · RSSI ${device.rssi}',
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => onConnect(device.address),
            child: const Text('连接'),
          ),
        ],
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.enabled, required this.onPick});

  final bool enabled;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final container = dark ? scheme.secondaryContainer : butter;
    final content = dark ? scheme.onSecondaryContainer : ink;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: BajiCard(
        containerColor: container,
        contentColor: content,
        borderColor: dark ? scheme.outlineVariant : ink,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('相册', style: Theme.of(context).textTheme.headlineLarge),
                      const SizedBox(height: 4),
                      Text(
                        '最多 255 张，1 秒一张',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: content.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ),
                _AlbumMark(color: content),
              ],
            ),
            const SizedBox(height: 16),
            FilledPill(
              text: '选择图片',
              onClick: onPick,
              enabled: enabled,
              containerColor: ink,
              contentColor: butter,
              disabledContainerColor: content.withValues(alpha: 0.14),
              disabledContentColor: content.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmbienceCard extends StatelessWidget {
  const _AmbienceCard({required this.enabled, required this.onOpen});

  final bool enabled;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: BajiCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('动态氛围', style: Theme.of(context).textTheme.headlineLarge),
                      const SizedBox(height: 4),
                      Text(
                        'GIF 或视频，抽成 JPG 帧循环',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const _AmbienceMark(),
              ],
            ),
            const SizedBox(height: 16),
            OutlinePill(text: '选择 GIF / 视频', onClick: onOpen, enabled: enabled),
          ],
        ),
      ),
    );
  }
}

class _SlideshowCard extends StatelessWidget {
  const _SlideshowCard({required this.enabled, required this.onOpen});

  final bool enabled;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: BajiCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('多图轮播', style: Theme.of(context).textTheme.headlineLarge),
                      const SizedBox(height: 4),
                      Text(
                        '多张图片，按节奏轮播',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const _SlideshowMark(),
              ],
            ),
            const SizedBox(height: 16),
            OutlinePill(text: '选择图片', onClick: onOpen, enabled: enabled),
          ],
        ),
      ),
    );
  }
}

class _MarqueeCard extends StatelessWidget {
  const _MarqueeCard({required this.enabled, required this.onOpen});

  final bool enabled;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final container = dark ? scheme.primaryContainer : cobalt;
    final content = dark ? scheme.onPrimaryContainer : chalk;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: BajiCard(
        containerColor: container,
        contentColor: content,
        borderColor: container,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('跑马灯', style: Theme.of(context).textTheme.headlineLarge),
                      const SizedBox(height: 4),
                      Text(
                        '输入文字，选颜色，生成动图',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: content.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ),
                _MarqueeMark(color: content),
              ],
            ),
            const SizedBox(height: 16),
            FilledPill(
              text: '打开跑马灯',
              onClick: onOpen,
              enabled: enabled,
              containerColor: butter,
              contentColor: ink,
              disabledContainerColor: content.withValues(alpha: 0.16),
              disabledContentColor: content.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumMark extends StatelessWidget {
  const _AlbumMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 11, height: 11, color: color),
            const SizedBox(width: 3),
            Container(width: 11, height: 11, color: vermilion),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Container(width: 11, height: 11, color: cobalt),
            const SizedBox(width: 3),
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ],
        ),
      ],
    );
  }
}

class _AmbienceMark extends StatelessWidget {
  const _AmbienceMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 38,
      child: Stack(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: vermilion.withValues(alpha: 0.85),
              shape: BoxShape.circle,
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: cobalt.withValues(alpha: 0.75),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideshowMark extends StatelessWidget {
  const _SlideshowMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: cobalt.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 3),
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: butter,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        const SizedBox(width: 3),
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: cobalt.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}

class _MarqueeMark extends StatelessWidget {
  const _MarqueeMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 40, height: 4, color: butter),
          const SizedBox(height: 5),
          Container(
            width: 28,
            height: 4,
            color: color.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 5),
          Container(width: 35, height: 4, color: butter),
        ],
      ),
    );
  }
}
