import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/orchestration_provider.dart';
import '../../state/theme_provider.dart';

class OrchestrationWidget extends ConsumerWidget {
  const OrchestrationWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final orchState = ref.watch(orchestrationProvider);

    if (orchState.tasks.isEmpty) return const SizedBox.shrink();

    // Show only active + recently completed tasks
    final visible = orchState.tasks.where((t) {
      if (t.status == OrchestrationStatus.running) return true;
      if (t.completedAt != null &&
          DateTime.now().difference(t.completedAt!).inSeconds < 30) {
        return true;
      }
      return false;
    }).toList();

    if (visible.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.md,
      ),
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: tokens.bgLighter,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: tokens.accent.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree, size: 14, color: tokens.accent),
              const SizedBox(width: Spacing.md),
              Text(
                'Subagent Orchestration',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${orchState.activeTasks.length} active',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xxs,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          ...visible.map((task) => _OrchestrationTaskRow(task: task)),
        ],
      ),
    );
  }
}

class _OrchestrationTaskRow extends ConsumerStatefulWidget {
  final OrchestrationTask task;
  const _OrchestrationTaskRow({required this.task});

  @override
  ConsumerState<_OrchestrationTaskRow> createState() =>
      _OrchestrationTaskRowState();
}

class _OrchestrationTaskRowState extends ConsumerState<_OrchestrationTaskRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final task = widget.task;
    final isRunning = task.status == OrchestrationStatus.running;
    final isCompleted = task.status == OrchestrationStatus.completed;
    final isFailed = task.status == OrchestrationStatus.failed;

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(Radii.xs),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                // Status icon
                SizedBox(
                  width: 16,
                  height: 16,
                  child: isRunning
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: tokens.accent,
                          ),
                        )
                      : Icon(
                          isCompleted
                              ? Icons.check_circle
                              : Icons.error,
                          size: 14,
                          color: isCompleted
                              ? tokens.success
                              : tokens.error,
                        ),
                ),
                const SizedBox(width: Spacing.md),

                // Agent name
                Text(
                  task.name,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: Spacing.md),

                // Task description (truncated)
                Expanded(
                  child: Text(
                    task.task,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xxs,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),

                // Expand icon
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                  color: tokens.textMuted,
                ),
              ],
            ),
          ),

          // Expanded content
          if (_expanded) ...[
            const SizedBox(height: Spacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: tokens.bgMain,
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
              child: Text(
                isRunning
                    ? (task.streamingContent.isEmpty
                        ? 'Working...'
                        : task.streamingContent)
                    : isFailed
                        ? 'Error: ${task.error ?? "Unknown error"}'
                        : task.result ?? 'Completed',
                style: TextStyle(
                  color: isFailed ? tokens.error : tokens.textSecondary,
                  fontSize: FontSizes.xxs,
                  fontFamily: EditorDefaults.fontFamily,
                ),
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
