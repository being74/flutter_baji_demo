import 'package:flutter/material.dart';

import '../../ble/baji_ble_client.dart';
import '../../data/device_state.dart';
import '../baji_view_model.dart';
import '../formatters.dart';
import '../theme.dart';
import '../widgets/baji_widgets.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.viewModel,
    required this.onOpenLogs,
  });

  final BajiViewModel viewModel;
  final VoidCallback onOpenLogs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final connection = viewModel.connection;
    final connected = connection is BleConnected;
    final connectedState = connection is BleConnected ? connection : null;
    final device = viewModel.device;

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '我的',
                  style: textTheme.displayLarge?.copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  '设备与协议',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 10),
            BajiCard(
              containerColor: cobalt,
              contentColor: chalk,
              borderColor: cobalt,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          connected ? '已连接' : '未连接',
                          style: textTheme.labelLarge?.copyWith(
                            color: connected
                                ? butter
                                : chalk.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          connectedState != null
                              ? (device.devName ??
                                  connectedState.name ??
                                  'e-BADGE')
                              : '去首页连上它',
                          style: textTheme.headlineLarge?.copyWith(color: chalk),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          connectedState != null
                              ? '${connectedState.address} · MTU ${connectedState.mtu}'
                              : '连接后可读取设备信息',
                          style: textTheme.bodySmall
                              ?.copyWith(color: chalk.withValues(alpha: 0.62)),
                        ),
                      ],
                    ),
                  ),
                  StatusDot(
                    color: connected ? butter : chalk.withValues(alpha: 0.35),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle(title: '设备', subtitle: '连接后自动刷新'),
                  const SizedBox(height: 10),
                  _DeviceInfoCard(
                    device: device,
                    connected: connected,
                    queryingActivation: viewModel.queryingActivation,
                    onRefresh: viewModel.refresh,
                    onQueryActivation: viewModel.queryActivation,
                    onSyncActivationTime: viewModel.syncActivationTime,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle(
                    title: '身份核对',
                    subtitle: '收到 0x0e 身份码后自动回复',
                  ),
                  const SizedBox(height: 10),
                  BajiCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LabelValue(
                          label: '身份码',
                          value: device.identityCode ?? '—',
                        ),
                        _divider(scheme),
                        LabelValue(
                          label: '核对结果',
                          value: switch (device.identityVerified) {
                            true => '已确认',
                            false => '已拒绝',
                            null => '—',
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '如需拒绝，请在协议日志里确认身份码后重新连接。',
                          style: textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: BajiCard(
                onTap: onOpenLogs,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('协议日志', style: textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            '${viewModel.logs.length} 条收发记录',
                            style: textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '›',
                      style: textTheme.headlineMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(ColorScheme scheme) => Divider(
        height: 1,
        thickness: 1,
        color: scheme.outlineVariant.withValues(alpha: 0.6),
      );
}

class _DeviceInfoCard extends StatelessWidget {
  const _DeviceInfoCard({
    required this.device,
    required this.connected,
    required this.queryingActivation,
    required this.onRefresh,
    required this.onQueryActivation,
    required this.onSyncActivationTime,
  });

  final DeviceState device;
  final bool connected;
  final bool queryingActivation;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onQueryActivation;
  final Future<void> Function() onSyncActivationTime;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BajiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LabelValue(label: '激活状态', value: activationText(device.activated)),
          _divider(scheme),
          LabelValue(label: '固件版本', value: device.version ?? '—'),
          _divider(scheme),
          LabelValue(label: '设备名', value: device.devName ?? '—'),
          _divider(scheme),
          LabelValue(
            label: '空间',
            value: device.totalSpace == null
                ? '—'
                : '剩余 ${formatBytes(device.freeSpace == null ? null : device.freeSpace! * 1024)} / '
                    '共 ${formatBytes(device.totalSpace! * 1024)}',
          ),
          _divider(scheme),
          LabelValue(label: '分辨率', value: resolutionText(device)),
          _divider(scheme),
          LabelValue(label: '屏幕形状', value: shapeText(device.roundScreen)),
          _divider(scheme),
          LabelValue(label: '商家', value: device.brand?.toString() ?? '—'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinePill(
                text: '刷新',
                onClick: onRefresh,
                enabled: connected,
              ),
              OutlinePill(
                text: queryingActivation ? '查询中…' : '查询激活',
                onClick: onQueryActivation,
                enabled: connected && !queryingActivation,
              ),
              OutlinePill(
                text: '同步时间',
                onClick: onSyncActivationTime,
                enabled: connected,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider(ColorScheme scheme) => Divider(
        height: 1,
        thickness: 1,
        color: scheme.outlineVariant.withValues(alpha: 0.6),
      );
}

String activationText(bool? activated) => switch (activated) {
      true => '已激活',
      false => '未激活',
      null => '—',
    };

String shapeText(bool? round) => switch (round) {
      true => '圆屏',
      false => '方屏',
      null => '—',
    };

String resolutionText(DeviceState device) {
  final width = device.width;
  final height = device.height;
  if (width == null || height == null) return '—';
  return '$width × $height';
}
