import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';
import 'studio_plan_continuation.dart';
import 'studio_task_plan_primitives.dart';
import 'studio_task_plan_progress_chip.dart';

class StudioPlanContinuationCard extends ConsumerWidget {
  final StudioPlanContinuationSummary continuation;
  final VoidCallback onContinue;

  const StudioPlanContinuationCard({
    super.key,
    required this.continuation,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final remainingTargets = continuation.remainingTargets.take(4).toList();
    final hiddenCount =
        continuation.remainingTargets.length - remainingTargets.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: tokens.surfacePanel.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.48)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Next batch available',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: FontSizes.xs,
              height: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            'Plan progress: ${continuation.appliedCount}/${continuation.totalCount} targets applied. ${continuation.summaryLabel}.',
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.xs,
              height: 1.35,
            ),
          ),
          if (remainingTargets.isNotEmpty) ...[
            const SizedBox(height: Spacing.xs),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final target in remainingTargets)
                  StudioPlanProgressTargetChip(target: target),
                if (hiddenCount > 0) StudioPlanMoreChip(count: hiddenCount),
              ],
            ),
          ],
          const SizedBox(height: Spacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              style: _planContinuationPrimaryActionStyle(tokens),
              onPressed: onContinue,
              child: const Text('Continue next batch'),
            ),
          ),
        ],
      ),
    );
  }
}

ButtonStyle _planContinuationPrimaryActionStyle(ThemeTokens tokens) {
  return FilledButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
    visualDensity: VisualDensity.compact,
    textStyle: const TextStyle(
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w600,
      height: 1.0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
  );
}
