import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/spec_models.dart';
import '../../state/spec_provider.dart';
import '../../state/theme_provider.dart';

class SpecExecutionWidget extends ConsumerWidget {
  const SpecExecutionWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final spec = ref.watch(specProvider);

    if (spec == null || spec.steps.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress header
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.xl,
            vertical: Spacing.md,
          ),
          child: Row(
            children: [
              Text(
                'Steps',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.sm,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${spec.completedCount}/${spec.steps.length}',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                ),
              ),
              const SizedBox(width: Spacing.md),
              SizedBox(
                width: 80,
                child: LinearProgressIndicator(
                  value: spec.progress,
                  backgroundColor: tokens.border,
                  valueColor: AlwaysStoppedAnimation(tokens.accent),
                ),
              ),
            ],
          ),
        ),

        // Step list
        ...spec.steps.map((step) => _StepRow(step: step)),
      ],
    );
  }
}

class _StepRow extends ConsumerStatefulWidget {
  final SpecStep step;
  const _StepRow({required this.step});

  @override
  ConsumerState<_StepRow> createState() => _StepRowState();
}

class _StepRowState extends ConsumerState<_StepRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final step = widget.step;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Spacing.xl, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(Radii.xs),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
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
                        : step.error != null
                        ? Icon(Icons.error, size: 16, color: tokens.error)
                        : Icon(
                            Icons.circle_outlined,
                            size: 16,
                            color: tokens.textMuted,
                          ),
                  ),
                  const SizedBox(width: Spacing.md),
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
                  // Action buttons
                  if (step.error != null && !step.isRunning) ...[
                    _SmallButton(
                      label: 'Retry',
                      color: tokens.accent,
                      onTap: () =>
                          ref.read(specProvider.notifier).retryStep(step.id),
                    ),
                    const SizedBox(width: Spacing.sm),
                    _SmallButton(
                      label: 'Skip',
                      color: tokens.textMuted,
                      onTap: () =>
                          ref.read(specProvider.notifier).skipStep(step.id),
                    ),
                  ],
                  if (!step.isCompleted &&
                      !step.isRunning &&
                      step.error == null)
                    InkWell(
                      onTap: () =>
                          ref.read(specProvider.notifier).removeStep(step.id),
                      child: Icon(
                        Icons.remove_circle_outline,
                        size: 14,
                        color: tokens.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Expanded result/error
          if (_expanded && (step.result != null || step.error != null))
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(left: 28, bottom: Spacing.md),
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: tokens.bgMain,
                borderRadius: BorderRadius.circular(Radii.xs),
                border: Border.all(
                  color: step.error != null
                      ? tokens.error.withValues(alpha: 0.3)
                      : tokens.border,
                ),
              ),
              child: Text(
                step.error ?? step.result ?? '',
                style: TextStyle(
                  color: step.error != null
                      ? tokens.error
                      : tokens.textSecondary,
                  fontSize: FontSizes.xxs,
                  fontFamily: EditorDefaults.fontFamily,
                ),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SmallButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.xs),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.xs),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: FontSizes.xxs),
        ),
      ),
    );
  }
}
