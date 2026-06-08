import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/agent_workspace.dart';
import '../../models/command_run.dart';
import '../../models/studio_shell.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_view_models.dart';
import '../../state/chat_provider.dart';
import '../../state/command_run_provider.dart';
import '../../state/git_provider.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';

class StudioProgressPanel extends ConsumerWidget {
  final AgentTask? task;

  const StudioProgressPanel({super.key, this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final chat = ref.watch(chatProvider);
    final thread = ref.watch(studioThreadProvider).threadForTask(task?.id);
    final git = ref.watch(gitProvider).status;
    final patch = ref.watch(patchProposalProvider).active;
    final commands = ref.watch(commandRunProvider).values.toList();
    final runningCommand = commands
        .where((command) => command.status == CommandRunStatus.running)
        .firstOrNull;
    final displayState = thread == null
        ? TaskDisplayState.derive(
            task: task,
            isChatProcessing: chat.isProcessing,
            isChatStreaming: chat.isStreaming,
            hasAssistantResponse: false,
            hasPendingApproval: chat.pendingConfirmation != null,
            commands: commands,
            chatError: chat.error,
          )
        : TaskDisplayState.fromLifecycle(
            StudioTaskLifecycleState.fromThread(thread),
          );
    final rows = <StudioProgressRow>[
      StudioProgressRow(
        label: 'Task',
        value: displayState.label,
        accent: displayState.isActive || displayState.needsAttention,
      ),
      if (chat.pendingConfirmation != null)
        const StudioProgressRow(
          label: 'Approval',
          value: 'Required',
          accent: true,
        ),
      if (runningCommand != null)
        StudioProgressRow(
          label: 'Command',
          value: '${runningCommand.elapsed.inSeconds}s',
          accent: true,
        ),
      StudioProgressRow(
        label: 'Changes',
        value: patch == null ? 'No pending changes' : '+${patch.fileCount}',
        accent: patch != null,
      ),
      const StudioProgressRow(label: 'Local', value: 'Ready'),
      StudioProgressRow(
        label: 'Branch',
        value: git.branch.isEmpty ? 'main' : git.branch,
      ),
    ];

    return Container(
      width: 300,
      margin: const EdgeInsets.fromLTRB(0, 58, Spacing.lg, Spacing.lg),
      decoration: BoxDecoration(
        color: tokens.studioPanel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.studioDivider),
        boxShadow: Shadows.medium,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Progress',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.base,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: Spacing.xl),
            Divider(color: tokens.studioDivider, height: 1),
            const SizedBox(height: Spacing.lg),
            Text(
              'Environment',
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
            ),
            const SizedBox(height: Spacing.md),
            for (final row in rows) _ProgressRow(row: row),
            const SizedBox(height: Spacing.lg),
            Divider(color: tokens.studioDivider, height: 1),
            const SizedBox(height: Spacing.lg),
            Text(
              'Sources',
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
            ),
            const SizedBox(height: Spacing.md),
            _SourceRow(
              icon: Icons.travel_explore,
              label: _sourceLabel(thread, commands.isNotEmpty),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressRow extends ConsumerWidget {
  final StudioProgressRow row;

  const _ProgressRow({required this.row});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final color = row.enabled ? tokens.textSecondary : tokens.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
      child: Row(
        children: [
          Icon(_iconFor(row.label), color: color, size: 15),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              row.label,
              style: TextStyle(color: color, fontSize: FontSizes.sm),
            ),
          ),
          Text(
            row.value,
            style: TextStyle(
              color: row.accent ? tokens.success : tokens.textMuted,
              fontSize: FontSizes.sm,
              fontWeight: row.accent ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String label) {
    return switch (label) {
      'Task' => Icons.radio_button_checked,
      'Approval' => Icons.shield_outlined,
      'Command' => Icons.terminal_outlined,
      'Changes' => Icons.inventory_2_outlined,
      'Local' => Icons.computer_outlined,
      'Branch' => Icons.account_tree_outlined,
      _ => Icons.data_object_outlined,
    };
  }
}

String _sourceLabel(StudioThread? thread, bool hasCommands) {
  if (hasCommands) return 'Tool output';
  final summary = thread?.contextSummary;
  if (summary == null) return 'Project context';
  if (summary.rootPath == null) return 'No project context';
  return summary.projectLabel;
}

class _SourceRow extends ConsumerWidget {
  final IconData icon;
  final String label;

  const _SourceRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Row(
      children: [
        Icon(icon, color: tokens.textMuted, size: 15),
        const SizedBox(width: Spacing.md),
        Text(
          label,
          style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
        ),
      ],
    );
  }
}
