import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/code_review_models.dart';
import '../../state/code_review_provider.dart';
import '../../state/theme_provider.dart';

class ReviewAnnotationWidget extends ConsumerStatefulWidget {
  final ReviewAnnotation annotation;

  const ReviewAnnotationWidget({super.key, required this.annotation});

  @override
  ConsumerState<ReviewAnnotationWidget> createState() =>
      _ReviewAnnotationWidgetState();
}

class _ReviewAnnotationWidgetState
    extends ConsumerState<ReviewAnnotationWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final annotation = widget.annotation;

    final (severityIcon, severityColor) = switch (annotation.severity) {
      ReviewSeverity.critical => (Icons.error, tokens.error),
      ReviewSeverity.warning => (Icons.warning_amber, tokens.warning),
      ReviewSeverity.suggestion => (Icons.lightbulb_outline, tokens.info),
      ReviewSeverity.nit => (Icons.info_outline, tokens.textMuted),
    };

    final lineRange = annotation.startLine == annotation.endLine
        ? 'L${annotation.startLine}'
        : 'L${annotation.startLine}-${annotation.endLine}';

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: AnimationDurations.fast,
        margin: const EdgeInsets.only(bottom: Spacing.xs),
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: _isHovered
              ? severityColor.withValues(alpha: 0.08)
              : severityColor.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
            color: severityColor.withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: severity icon + line range + actions
            Row(
              children: [
                Icon(severityIcon, size: 14, color: severityColor),
                const SizedBox(width: Spacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.border.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(Radii.xs),
                  ),
                  child: Text(
                    lineRange,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xxs,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Text(
                  annotation.severity.name.toUpperCase(),
                  style: TextStyle(
                    color: severityColor,
                    fontSize: FontSizes.xxs,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (annotation.isFixed)
                  Icon(
                    Icons.check_circle,
                    size: 14,
                    color: tokens.success,
                  )
                else ...[
                  if (annotation.suggestedFix != null)
                    _ActionButton(
                      label: 'Fix',
                      icon: Icons.auto_fix_high,
                      color: tokens.success,
                      isVisible: _isHovered,
                      onTap: () => ref
                          .read(codeReviewProvider.notifier)
                          .applyFix(annotation.id),
                    ),
                  const SizedBox(width: Spacing.xs),
                  _ActionButton(
                    label: 'Dismiss',
                    icon: Icons.close,
                    color: tokens.textMuted,
                    isVisible: _isHovered,
                    onTap: () => ref
                        .read(codeReviewProvider.notifier)
                        .dismissAnnotation(annotation.id),
                  ),
                ],
              ],
            ),
            const SizedBox(height: Spacing.sm),

            // Message
            Text(
              annotation.message,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: FontSizes.sm,
                height: 1.4,
              ),
            ),

            // Suggested fix preview
            if (annotation.suggestedFix != null && !annotation.isFixed) ...[
              const SizedBox(height: Spacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: tokens.editorBg,
                  borderRadius: BorderRadius.circular(Radii.xs),
                  border: Border.all(
                    color: tokens.border.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  annotation.suggestedFix!,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.xs,
                    fontFamily: 'JetBrains Mono',
                    height: 1.4,
                  ),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isVisible;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.isVisible,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: AnimationDurations.fast,
      opacity: isVisible ? 1.0 : 0.0,
      child: Tooltip(
        message: label,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 10, color: color),
                  const SizedBox(width: 2),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: FontSizes.xxs,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
