import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/reviewed_edit.dart';
import '../../state/theme_provider.dart';
import '../chat/chat_message_widget.dart';
import 'studio_chrome.dart';

class StudioPlanTargetChip extends ConsumerWidget {
  final PlannedFileTarget target;

  const StudioPlanTargetChip({super.key, required this.target});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final label = target.displayString.trim().isEmpty
        ? target.path
        : target.displayString;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.studioControl.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.38)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tokens.textSecondary,
          fontSize: FontSizes.xs,
          height: 1.1,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class StudioPlanMoreChip extends ConsumerWidget {
  final int count;

  const StudioPlanMoreChip({super.key, required this.count});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.studioControl.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        '+$count more',
        style: TextStyle(
          color: tokens.textMuted,
          fontSize: FontSizes.xs,
          height: 1.1,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class StudioPlanCardBody extends ConsumerWidget {
  final String markdown;
  final bool expanded;
  final double collapsedMaxHeight;

  const StudioPlanCardBody({
    super.key,
    required this.markdown,
    required this.expanded,
    this.collapsedMaxHeight = 318,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = expanded
        ? (screenHeight * 0.48).clamp(320.0, 520.0).toDouble()
        : collapsedMaxHeight;
    return SizedBox(
      height: maxHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              physics: expanded
                  ? const BouncingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              child: MarkdownWidget(
                data: markdown,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                config: buildChatMarkdownConfig(tokens),
              ),
            ),
          ),
          if (!expanded)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 96,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        tokens.studioCard.withValues(alpha: 0),
                        tokens.studioCard.withValues(alpha: 0.96),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class StudioPlanIconAction extends ConsumerWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;

  const StudioPlanIconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StudioChromeIconButton(
      icon: icon,
      tooltip: tooltip,
      onTap: onPressed,
      width: 28,
      height: 28,
      iconSize: 15,
      focusNode: focusNode,
    );
  }
}

class StudioPlanChoiceButton extends ConsumerWidget {
  final String? index;
  final IconData? icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  const StudioPlanChoiceButton({
    super.key,
    required this.index,
    this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final child = Material(
      color: enabled
          ? tokens.studioControl.withValues(alpha: 0.55)
          : tokens.studioControl.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: index == null ? Colors.transparent : tokens.textPrimary,
                borderRadius: BorderRadius.circular(999),
                border: index == null
                    ? Border.all(
                        color: tokens.studioDivider.withValues(alpha: 0.6),
                      )
                    : null,
              ),
              child: index == null
                  ? Icon(icon ?? StudioIcons.editOutlined, size: 12)
                  : Text(
                      index!,
                      style: TextStyle(
                        color: tokens.bgDark,
                        fontSize: FontSizes.xs,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: enabled ? tokens.textPrimary : tokens.textMuted,
                  fontSize: FontSizes.xs,
                  height: 1.25,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!enabled) {
      return Semantics(
        label: label,
        button: true,
        enabled: false,
        child: ExcludeSemantics(child: child),
      );
    }
    return StudioFocusableActionSurface(
      semanticLabel: label,
      borderRadius: BorderRadius.circular(8),
      onTap: onPressed,
      child: child,
    );
  }
}
