import 'package:flutter/material.dart';

/// Compact icon button matching the IDE style
class IDEIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color? color;
  final Color? hoverColor;
  final bool isActive;

  const IDEIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 20,
    this.color,
    this.hoverColor,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = isActive
        ? theme.colorScheme.primary
        : color ?? theme.colorScheme.onSurface.withValues(alpha: 0.7);

    Widget button = SizedBox(
      width: size + 8,
      height: size + 8,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          hoverColor:
              hoverColor ?? theme.colorScheme.onSurface.withValues(alpha: 0.08),
          child: Center(
            child: Icon(
              icon,
              size: size,
              color: onPressed == null
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
                  : effectiveColor,
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(
        message: tooltip!,
        waitDuration: const Duration(milliseconds: 600),
        child: button,
      );
    }

    return button;
  }
}
