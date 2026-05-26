import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';

class CircuitIconButton extends ConsumerWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final Color? color;

  const CircuitIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.selected = false,
    this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final effectiveColor =
        color ?? (selected ? tokens.accent : tokens.textMuted);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? tokens.surfacePressed : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Icon(icon, size: 16, color: effectiveColor),
        ),
      ),
    );
  }
}

class CircuitActionMenu<T> extends ConsumerWidget {
  final IconData icon;
  final String tooltip;
  final List<PopupMenuEntry<T>> items;
  final PopupMenuItemSelected<T> onSelected;

  const CircuitActionMenu({
    super.key,
    this.icon = Icons.more_horiz,
    required this.tooltip,
    required this.items,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Tooltip(
      message: tooltip,
      child: PopupMenuButton<T>(
        tooltip: '',
        padding: EdgeInsets.zero,
        offset: const Offset(0, 30),
        color: tokens.surfacePopover,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.xl),
          side: BorderSide(color: tokens.outlineSoft),
        ),
        onSelected: onSelected,
        itemBuilder: (_) => items,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
            color: Colors.transparent,
          ),
          child: Icon(icon, size: 16, color: tokens.textMuted),
        ),
      ),
    );
  }
}

class CircuitSegmentedControl<T> extends ConsumerWidget {
  final T value;
  final List<CircuitSegment<T>> segments;
  final ValueChanged<T> onChanged;

  const CircuitSegmentedControl({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: tokens.surfaceInset,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: tokens.outlineSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: segments.map((segment) {
          final selected = segment.value == value;
          return InkWell(
            onTap: () => onChanged(segment.value),
            borderRadius: BorderRadius.circular(Radii.md),
            child: AnimatedContainer(
              duration: AnimationDurations.fast,
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: selected ? tokens.surfacePanel : Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Text(
                segment.label,
                style: TextStyle(
                  color: selected ? tokens.textPrimary : tokens.textMuted,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class CircuitSegment<T> {
  final T value;
  final String label;

  const CircuitSegment(this.value, this.label);
}

class CircuitStatusChip extends ConsumerWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  const CircuitStatusChip({
    super.key,
    required this.icon,
    required this.label,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final effectiveColor = color ?? tokens.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: effectiveColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: effectiveColor.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: effectiveColor),
            const SizedBox(width: Spacing.sm),
            Text(
              label,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CircuitPanelHeader extends ConsumerWidget {
  final IconData? icon;
  final String title;
  final Widget? trailing;

  const CircuitPanelHeader({
    super.key,
    this.icon,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      height: LayoutDimensions.tabBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      decoration: BoxDecoration(
        color: tokens.surfaceBase,
        border: Border(bottom: BorderSide(color: tokens.outlineSoft)),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: tokens.textMuted),
            const SizedBox(width: Spacing.sm),
          ],
          Text(
            title,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

class CircuitDisclosureRow extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> children;
  final bool initiallyExpanded;

  const CircuitDisclosureRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.children,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfacePanel,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: tokens.outlineSoft),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          childrenPadding: const EdgeInsets.fromLTRB(
            Spacing.md,
            0,
            Spacing.md,
            Spacing.md,
          ),
          leading: Icon(icon, color: tokens.textMuted, size: 16),
          title: Text(
            title,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: FontSizes.sm,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
                  ),
                ),
          children: children,
        ),
      ),
    );
  }
}
