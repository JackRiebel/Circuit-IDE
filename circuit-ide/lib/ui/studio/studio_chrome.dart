import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';

class StudioChromeIconButton extends ConsumerWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  final double width;
  final double height;

  const StudioChromeIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.active = false,
    this.width = 30,
    this.height = 26,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? tokens.studioControl.withValues(alpha: 0.68)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.md),
            border: active
                ? Border.all(
                    color: tokens.studioDivider.withValues(alpha: 0.54),
                  )
                : null,
          ),
          child: Icon(
            icon,
            color: active ? tokens.textSecondary : tokens.textMuted,
            size: 15,
          ),
        ),
      ),
    );
  }
}

class StudioMiniChip extends ConsumerWidget {
  final String label;
  final bool attention;

  const StudioMiniChip({
    super.key,
    required this.label,
    this.attention = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: attention
            ? tokens.warning.withValues(alpha: 0.13)
            : tokens.studioControl.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: attention ? tokens.warning : tokens.textMuted,
          fontSize: FontSizes.xxs,
          height: 1.15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class StudioTonalButton extends ConsumerWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  const StudioTonalButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        decoration: BoxDecoration(
          color: tokens.studioControl,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(
            color: tokens.studioDivider.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: tokens.textMuted, size: 14),
              const SizedBox(width: Spacing.sm),
            ],
            Text(
              label,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StudioActivityRow extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;
  final bool elevated;

  const StudioActivityRow({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.onTap,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 706),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: elevated
                ? tokens.studioActivityRow.withValues(alpha: 0.62)
                : tokens.studioActivityRow.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: tokens.studioDivider.withValues(alpha: 0.48),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: tokens.textMuted, size: 13),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: FontSizes.xs,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (detail.trim().isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FontSizes.xs,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, color: tokens.textMuted, size: 15),
            ],
          ),
        ),
      ),
    );
  }
}

class StudioRailRow extends ConsumerStatefulWidget {
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final bool project;
  final Widget? trailing;
  final Widget? hoverTrailing;
  final double leftIndent;

  const StudioRailRow({
    super.key,
    this.icon,
    required this.label,
    this.onTap,
    this.selected = false,
    this.project = false,
    this.trailing,
    this.hoverTrailing,
    this.leftIndent = 0,
  });

  @override
  ConsumerState<StudioRailRow> createState() => _StudioRailRowState();
}

class _StudioRailRowState extends ConsumerState<StudioRailRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final showHoverTrailing =
        widget.hoverTrailing != null &&
        (_hovered || _focused || widget.selected);
    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.sm + widget.leftIndent,
        right: Spacing.sm,
        bottom: 1,
      ),
      child: FocusableActionDetector(
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(Radii.md),
          child: Container(
            height: widget.project ? 29 : 28,
            padding: EdgeInsets.symmetric(horizontal: widget.project ? 9 : 8),
            decoration: BoxDecoration(
              color: widget.selected
                  ? (widget.project
                        ? tokens.studioRailSelected.withValues(alpha: 0.78)
                        : tokens.studioTaskSelected.withValues(alpha: 0.78))
                  : _hovered || _focused
                  ? tokens.studioHover.withValues(alpha: 0.48)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Row(
              children: [
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    color: widget.selected
                        ? tokens.textPrimary
                        : tokens.textMuted,
                    size: widget.project ? 15 : 14,
                  ),
                  const SizedBox(width: 7),
                ],
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.selected
                          ? tokens.textPrimary
                          : tokens.textSecondary,
                      fontSize: FontSizes.sm,
                      height: 1.15,
                      fontWeight: widget.selected
                          ? FontWeight.w600
                          : widget.project
                          ? FontWeight.w500
                          : FontWeight.w400,
                    ),
                  ),
                ),
                if (widget.trailing != null) ...[
                  const SizedBox(width: Spacing.sm),
                  widget.trailing!,
                ],
                if (showHoverTrailing) ...[
                  const SizedBox(width: Spacing.xs),
                  widget.hoverTrailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
