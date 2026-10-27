import 'package:flutter/material.dart';

import '../baji_view_model.dart';
import '../formatters.dart';
import '../theme.dart';

class BajiCard extends StatelessWidget {
  const BajiCard({
    super.key,
    this.containerColor,
    this.contentColor,
    this.borderColor,
    this.padding = const EdgeInsets.all(18),
    this.radius = 20,
    this.onTap,
    required this.child,
  });

  final Color? containerColor;
  final Color? contentColor;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final container = containerColor ?? scheme.surface;
    final content = contentColor ?? scheme.onSurface;
    final border = borderColor ?? scheme.outlineVariant;
    final card = Container(
      decoration: BoxDecoration(
        color: container,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
      ),
      padding: padding,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: content),
        child: IconTheme.merge(
          data: IconThemeData(color: content),
          child: child,
        ),
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: card,
      ),
    );
  }
}

class FilledPill extends StatelessWidget {
  const FilledPill({
    super.key,
    required this.text,
    required this.onClick,
    this.enabled = true,
    this.containerColor,
    this.contentColor,
    this.disabledContainerColor,
    this.disabledContentColor,
    this.modifierWidth,
    this.fullWidth = false,
  });

  final String text;
  final VoidCallback onClick;
  final bool enabled;
  final Color? containerColor;
  final Color? contentColor;
  final Color? disabledContainerColor;
  final Color? disabledContentColor;
  final double? modifierWidth;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = enabled
        ? (containerColor ?? scheme.secondary)
        : (disabledContainerColor ?? scheme.surfaceContainerHighest);
    final foreground = enabled
        ? (contentColor ?? scheme.onSecondary)
        : (disabledContentColor ?? scheme.onSurfaceVariant.withValues(alpha: 0.55));
    final child = Material(
      color: background,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: enabled ? onClick : null,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: foreground),
          ),
        ),
      ),
    );
    if (fullWidth) return SizedBox(width: double.infinity, child: child);
    if (modifierWidth != null) return SizedBox(width: modifierWidth, child: child);
    return child;
  }
}

class OutlinePill extends StatelessWidget {
  const OutlinePill({
    super.key,
    required this.text,
    required this.onClick,
    this.enabled = true,
    this.contentColor,
    this.borderColor,
    this.fullWidth = false,
  });

  final String text;
  final VoidCallback onClick;
  final bool enabled;
  final Color? contentColor;
  final Color? borderColor;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = enabled
        ? (contentColor ?? scheme.onSurface)
        : scheme.onSurfaceVariant.withValues(alpha: 0.5);
    final border = (borderColor ?? scheme.outline)
        .withValues(alpha: enabled ? 1 : 0.35);
    final child = Material(
      color: Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: border)),
      child: InkWell(
        onTap: enabled ? onClick : null,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: foreground),
          ),
        ),
      ),
    );
    return fullWidth ? SizedBox(width: double.infinity, child: child) : child;
  }
}

class BinUploadButton extends StatelessWidget {
  const BinUploadButton({
    super.key,
    required this.loading,
    required this.loadingText,
    required this.progress,
    required this.enabled,
    required this.onClick,
  });

  final bool loading;
  final String loadingText;
  final double? progress;
  final bool enabled;
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = enabled ? scheme.tertiary : scheme.surfaceContainerHighest;
    final foreground = enabled ? scheme.onTertiary : scheme.onSurfaceVariant;
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: Material(
        color: background,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onClick : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    loading ? loadingText : '上传',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: foreground,
                        ),
                  ),
                ),
              ),
              if (loading)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 6,
                  child: LinearProgressIndicator(
                    value: progress?.clamp(0.0, 1.0),
                    backgroundColor: scheme.onSurfaceVariant.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineLarge),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class LabelValue extends StatelessWidget {
  const LabelValue({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: valueColor ?? scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.action,
  });

  final String title;
  final VoidCallback onBack;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 16, 2),
        child: Row(
          children: [
            TextButton(
              onPressed: onBack,
              child: Text('← 返回', style: Theme.of(context).textTheme.labelLarge),
            ),
            const SizedBox(width: 4),
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            const Spacer(),
            if (action != null) action!,
          ],
        ),
      ),
    );
  }
}

class OverlayHeader extends StatelessWidget {
  const OverlayHeader({super.key, required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onBack,
                child: Text('←', style: Theme.of(context).textTheme.headlineMedium),
              ),
            ),
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
      ),
    );
  }
}

class DotGridIcon extends StatelessWidget {
  const DotGridIcon({super.key, required this.color, this.size = 18});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _DotGridPainter(color),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.shortestSide / 3;
    final radius = cell * 0.2;
    final offset = cell * 0.5;
    final paint = Paint()..color = color;
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        canvas.drawCircle(
          Offset(cell * col + offset, cell * row + offset),
          radius,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class BajiBottomBar extends StatelessWidget {
  const BajiBottomBar({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
          SafeArea(
            top: false,
            child: SizedBox(
              height: 60,
              child: Row(
                children: [
                  _DockItem(
                    label: '首页',
                    icon: Icons.home,
                    outlineIcon: Icons.home_outlined,
                    selected: selected == 0,
                    onTap: () => onSelect(0),
                  ),
                  _DockItem(
                    label: '我的',
                    icon: Icons.person,
                    outlineIcon: Icons.person_outline,
                    selected: selected == 1,
                    onTap: () => onSelect(1),
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

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.label,
    required this.icon,
    required this.outlineIcon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData outlineIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? icon : outlineIcon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class ConnectionPill extends StatelessWidget {
  const ConnectionPill({super.key, required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = connected ? connectedGreen : scheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        shape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        connected ? '已链接' : '未连接',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
      ),
    );
  }
}

class PlayBadge extends StatelessWidget {
  const PlayBadge({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: connectedGreen, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: CustomPaint(
        size: Size(size * 0.36, size * 0.36),
        painter: _PlayPainter(),
      ),
    );
  }
}

class _PlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class TransferProgressCard extends StatelessWidget {
  const TransferProgressCard({
    super.key,
    required this.transfer,
    required this.onCancel,
  });

  final TransferUiState transfer;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final failed = transfer.message?.contains('失败') == true;
    final cancelled = transfer.message == '已取消';
    final statusText = transfer.running
        ? '${(transfer.fraction * 100).toInt()}%'
        : failed
            ? '失败'
            : cancelled
                ? '已取消'
                : '完成';
    final statusColor = failed
        ? vermilion
        : cancelled
            ? chalk.withValues(alpha: 0.7)
            : butter;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: BajiCard(
        containerColor: ink,
        contentColor: chalk,
        borderColor: ink,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  transfer.kind?.title ?? '传输',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: chalk),
                ),
                const Spacer(),
                Text(
                  statusText,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: statusColor),
                ),
              ],
            ),
            if (transfer.running) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: transfer.fraction,
                  minHeight: 4,
                  backgroundColor: chalk.withValues(alpha: 0.2),
                  valueColor: const AlwaysStoppedAnimation<Color>(butter),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${transfer.fileName}  ${transfer.fileIndex + 1}/${transfer.fileCount}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: chalk.withValues(alpha: 0.7)),
              ),
              Text(
                '${formatBytes(transfer.sentBytes)} / ${formatBytes(transfer.totalBytes)}'
                ' · ${formatBytes(transfer.speed)}/s',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: chalk.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 10),
              OutlinePill(
                text: '取消',
                onClick: onCancel,
                contentColor: chalk,
                borderColor: chalk.withValues(alpha: 0.5),
              ),
            ] else ...[
              const SizedBox(height: 6),
              Text(
                transfer.message ?? '',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: failed ? vermilion : chalk.withValues(alpha: 0.7),
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


/// 上传结果用 SnackBar 提示，避免页面底部再出现一块结果卡片。
/// 页面首次组合时已有的旧结果会被忽略。
class TransferResultToast extends StatefulWidget {
  const TransferResultToast({super.key, required this.transfer});

  final TransferUiState? transfer;

  @override
  State<TransferResultToast> createState() => _TransferResultToastState();
}

class _TransferResultToastState extends State<TransferResultToast> {
  String? _lastMessage;

  @override
  void initState() {
    super.initState();
    _lastMessage = _terminalMessage(widget.transfer);
  }

  @override
  void didUpdateWidget(covariant TransferResultToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.transfer == null || widget.transfer!.running) {
      _lastMessage = null;
      return;
    }
    final message = _terminalMessage(widget.transfer);
    if (message == null || message == _lastMessage) return;
    _lastMessage = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(message.toToastText())),
      );
    });
  }

  String? _terminalMessage(TransferUiState? state) {
    if (state == null || state.running) return null;
    return state.message;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

extension _ToastText on String {
  String toToastText() {
    if (this == '传输完成') return '上传成功';
    if (this == '已取消') return '已取消上传';
    if (startsWith('失败：')) return '上传$this';
    return this;
  }
}
