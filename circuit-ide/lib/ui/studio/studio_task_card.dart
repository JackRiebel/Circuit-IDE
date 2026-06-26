import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/agent_workspace.dart';
import '../../models/studio_shell.dart';
import '../../state/theme_provider.dart';

class StudioTaskCard extends ConsumerWidget {
  final AgentTask task;
  final String projectLabel;
  final VoidCallback onTap;

  const StudioTaskCard({
    super.key,
    required this.task,
    required this.projectLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final summary = StudioTaskSummary.fromTask(
      task,
      projectLabel: projectLabel,
    );
    final statusColor = _statusColor(tokens, task.status);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: Container(
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: tokens.studioCard,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: tokens.studioDivider),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Radii.lg),
                border: Border.all(color: statusColor.withValues(alpha: 0.24)),
              ),
              child: Text(
                summary.alias.characters.first,
                style: TextStyle(
                  color: statusColor,
                  fontSize: FontSizes.sm,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: Spacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.sm,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    '${summary.alias} · ${summary.projectLabel} · ${summary.detail}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Spacing.lg),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  summary.statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  '${summary.artifactCount} events',
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xxs,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(dynamic tokens, AgentTaskStatus status) {
    return switch (status) {
      AgentTaskStatus.completed => tokens.success,
      AgentTaskStatus.failed => tokens.error,
      AgentTaskStatus.cancelled => tokens.textMuted,
      AgentTaskStatus.waitingForApproval => tokens.warning,
      AgentTaskStatus.queued || AgentTaskStatus.running => tokens.accent,
    };
  }
}
