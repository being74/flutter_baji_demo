import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ble/baji_ble_client.dart';
import '../baji_view_model.dart';
import '../widgets/baji_widgets.dart';

const List<String> _breatherOptions = ['无呼吸', '慢速', '中速', '快速'];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.viewModel,
    required this.onBack,
  });

  final BajiViewModel viewModel;
  final VoidCallback onBack;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _devNameController;

  BajiViewModel get viewModel => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _devNameController = TextEditingController(text: viewModel.settings.devName);
    viewModel.addListener(_syncDevName);
  }

  @override
  void dispose() {
    viewModel.removeListener(_syncDevName);
    _devNameController.dispose();
    super.dispose();
  }

  void _syncDevName() {
    final value = viewModel.settings.devName;
    if (_devNameController.text == value) return;
    _devNameController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final settings = viewModel.settings;
    final connected = viewModel.connection is BleConnected;

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          ScreenHeader(title: '设置', onBack: widget.onBack),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SettingGroup(
                    title: '显示',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '背光亮度：${settings.bgLight}%',
                          style: textTheme.titleMedium,
                        ),
                        Slider(
                          value: settings.bgLight.toDouble(),
                          min: 0,
                          max: 100,
                          divisions: 10,
                          onChanged: connected
                              ? (value) => viewModel.setBgLight(value.round())
                              : null,
                        ),
                        Text(
                          '步进 10，范围 0~100',
                          style: textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SettingGroup(
                    title: '设备',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('呼吸效果', style: textTheme.titleMedium),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (var index = 0;
                                  index < _breatherOptions.length;
                                  index++) ...[
                                if (index > 0) const SizedBox(width: 8),
                                FilterChip(
                                  selected: settings.breather == index,
                                  onSelected: connected
                                      ? (_) => viewModel.setBreather(index)
                                      : null,
                                  label: Text(_breatherOptions[index]),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text('设备名', style: textTheme.titleMedium),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _devNameController,
                          onChanged: viewModel.setDevName,
                          enabled: connected,
                          decoration: const InputDecoration(
                            hintText: '数字 + 英文',
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp('[A-Za-z0-9]'),
                            ),
                          ],
                          keyboardType: TextInputType.text,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SettingGroup(
                    title: '发送',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FilledPill(
                          text: '发送设置（0x0d）',
                          onClick: viewModel.sendSettings,
                          enabled: connected,
                          fullWidth: true,
                        ),
                        const SizedBox(height: 10),
                        OutlinePill(
                          text: '同步激活时间（0x08）',
                          onClick: viewModel.syncActivationTime,
                          enabled: connected,
                          fullWidth: true,
                        ),
                        if (!connected) ...[
                          const SizedBox(height: 8),
                          Text(
                            '连接设备后才能发送',
                            style: textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingGroup extends StatelessWidget {
  const _SettingGroup({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 6),
        BajiCard(
          child: SizedBox(width: double.infinity, child: child),
        ),
      ],
    );
  }
}
