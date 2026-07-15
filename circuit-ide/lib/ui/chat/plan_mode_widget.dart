import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/plan_mode_provider.dart';
import '../../state/theme_provider.dart';

class PlanModeWidget extends ConsumerWidget {
  const PlanModeWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final planState = ref.watch(planModeProvider);

    if (!planState.isActive) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(Spacing.lg),
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: tokens.bgLighter,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.checklist, size: 16, color: tokens.accent),
              const SizedBox(width: 8),
              Text(
                'Plan Mode',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.sm,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Progress
              Text(
                '${planState.completedCount}/${planState.steps.length}',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: LinearProgressIndicator(
                  value: planState.progress,
                  backgroundColor: tokens.border,
                  valueColor: AlwaysStoppedAnimation(tokens.accent),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => ref.read(planModeProvider.notifier).deactivate(),
                child: Icon(Icons.close, size: 14, color: tokens.textMuted),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),

          // Steps
          ...planState.steps.map((step) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: step.isCompleted
                        ? Icon(
                            Icons.check_circle,
                            size: 16,
                            color: tokens.success,
                          )
                        : step.isRunning
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: tokens.accent,
                            ),
                          )
                        : Icon(
                            Icons.circle_outlined,
                            size: 16,
                            color: tokens.textMuted,
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      step.description,
                      style: TextStyle(
                        color: step.isCompleted
                            ? tokens.textMuted
                            : tokens.textPrimary,
                        fontSize: FontSizes.sm,
                        decoration: step.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  if (!step.isCompleted && !step.isRunning)
                    InkWell(
                      onTap: () => ref
                          .read(planModeProvider.notifier)
                          .removeStep(step.id),
                      child: Icon(
                        Icons.remove_circle_outline,
                        size: 14,
                        color: tokens.textMuted,
                      ),
                    ),
                ],
              ),
            );
          }),

          const SizedBox(height: Spacing.md),
          if (!planState.isExecuting)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  ref.read(planModeProvider.notifier).setExecuting(true);
                  // Start executing steps...
                },
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('Execute Plan'),
              ),
            ),
        ],
      ),
    );
  }
}
