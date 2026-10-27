import 'package:flutter/material.dart';

import '../../core/baji_log.dart';
import '../baji_view_model.dart';
import '../widgets/baji_widgets.dart';

class LogScreen extends StatelessWidget {
  const LogScreen({
    super.key,
    required this.viewModel,
    required this.onBack,
  });

  final BajiViewModel viewModel;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final entries = viewModel.logs.reversed.toList();

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          ScreenHeader(
            title: '协议日志',
            onBack: onBack,
            action: TextButton(
              onPressed: viewModel.log.clear,
              child: Text('清空', style: textTheme.labelLarge),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              itemCount: entries.isEmpty ? 1 : entries.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                thickness: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
              itemBuilder: (context, index) {
                if (entries.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      '还没有收发记录。连接设备后，协议帧会出现在这里。',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  );
                }
                final entry = entries[index];
                final color = _levelColor(scheme, entry.level);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            BajiLog.formatTime(entry.timestamp),
                            style: textTheme.labelSmall?.copyWith(color: scheme.outline),
                          ),
                          Text(
                            '  ${entry.tag}',
                            style: textTheme.labelSmall?.copyWith(color: color),
                          ),
                        ],
                      ),
                      Text(
                        entry.message,
                        style: textTheme.bodySmall?.copyWith(color: color),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _levelColor(ColorScheme scheme, BajiLogLevel level) => switch (level) {
        BajiLogLevel.debug => scheme.outline,
        BajiLogLevel.info => scheme.onSurface,
        BajiLogLevel.warn => scheme.tertiary,
        BajiLogLevel.error => scheme.error,
      };
}
