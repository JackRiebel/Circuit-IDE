import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/agent_workspace.dart';
import '../../models/command_run.dart';
import '../../models/reviewed_edit.dart';
import '../../models/studio_shell.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_turn.dart';
import '../../models/studio_view_models.dart';
import '../../state/command_run_provider.dart';
import '../../state/git_provider.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';

class StudioProgressPanel extends ConsumerWidget {
  final AgentTask? task;

  const StudioProgressPanel({super.key, this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final thread = ref.watch(
      studioThreadProvider.select((state) => state.threadForTaskView(task?.id)),
    );
    final latestTurn = _latestTurn(thread);
    final branch = ref.watch(
      gitProvider.select((state) => state.status.branch),
    );
    final patch = ref.watch(
      patchProposalProvider.select((state) => _patchForTurn(state, latestTurn)),
    );
    final runningCommand = ref.watch(
      commandRunProvider.select(
        (state) => _runningCommandForTurn(state.values, latestTurn),
      ),
    );
    final hasPendingApproval =
        thread?.turns.any(
          (turn) => turn.events.any(
            (event) =>
                event.type == StudioTurnEventType.approvalRequest &&
                event.approvalState == ApprovalRequestState.pending,
          ),
        ) ??
        false;
    final displayState = TaskDisplayState.fromLifecycle(
      StudioTaskLifecycleState.fromThread(thread),
    );
    final shouldShowTaskState =
        displayState.isActive ||
        displayState.needsAttention ||
        hasPendingApproval ||
        runningCommand != null;
    final rows = <StudioProgressRow>[
      if (shouldShowTaskState)
        StudioProgressRow(
          label: 'Task',
          value: displayState.label,
          accent: true,
        ),
      if (hasPendingApproval)
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
        value: branch.isEmpty ? 'main' : branch,
      ),
    ];

    return Container(
      width: 292,
      margin: const EdgeInsets.fromLTRB(0, 56, 14, 18),
      decoration: BoxDecoration(
        color: tokens.studioPanel.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.38)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 10, 15, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _PanelSectionHeader(
              title: 'Environment',
              actionTooltip: 'Open context details',
              actionIcon: Icons.add,
              onAction: () =>
                  ref.read(studioRightDrawerProvider.notifier).openContext(),
            ),
            const SizedBox(height: 4),
            for (final row in rows) _ProgressRow(row: row),
            const SizedBox(height: 10),
            Divider(
              color: tokens.studioDivider.withValues(alpha: 0.32),
              height: 1,
            ),
            const SizedBox(height: 10),
            const _PanelSectionHeader(title: 'Sources'),
            const SizedBox(height: 6),
            _SourceDotGrid(
              activeCount: _sourceCount(thread, runningCommand != null),
            ),
          ],
        ),
      ),
    );
  }

  StudioTurn? _latestTurn(StudioThread? thread) {
    if (thread == null || thread.turns.isEmpty) return null;
    final turns = thread.turns.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return turns.first;
  }

  ProposedPatchSet? _patchForTurn(
    PatchProposalState patchState,
    StudioTurn? turn,
  ) {
    if (turn == null) return null;
    final active = patchState.active;
    if (active?.runId == turn.requestId) return active;
    final history =
        patchState.history
            .where((patch) => patch.runId == turn.requestId)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return history.firstOrNull;
  }

  CommandRun? _runningCommandForTurn(
    Iterable<CommandRun> commands,
    StudioTurn? turn,
  ) {
    if (turn == null) return null;
    return commands
        .where(
          (command) =>
              command.status == CommandRunStatus.running &&
              command.requestId == turn.requestId,
        )
        .firstOrNull;
  }
}

int _sourceCount(StudioThread? thread, bool hasCommands) {
  if (hasCommands) return 3;
  return (thread?.contextSummary?.includedItemCount ?? 0).clamp(1, 24).toInt();
}

class _ProgressRow extends ConsumerWidget {
  final StudioProgressRow row;

  const _ProgressRow({required this.row});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final color = row.enabled ? tokens.textSecondary : tokens.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            _iconFor(row.label),
            color: color.withValues(alpha: 0.9),
            size: 13,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              row.label,
              style: TextStyle(
                color: color,
                fontSize: FontSizes.sm,
                height: 1.1,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Flexible(
            child: Text(
              row.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: row.accent
                    ? tokens.success.withValues(alpha: 0.92)
                    : tokens.textMuted.withValues(alpha: 0.88),
                fontSize: FontSizes.sm,
                height: 1.1,
                fontWeight: row.accent ? FontWeight.w600 : FontWeight.w500,
              ),
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

class _PanelSectionHeader extends ConsumerWidget {
  final String title;
  final String? actionTooltip;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  const _PanelSectionHeader({
    required this.title,
    this.actionTooltip,
    this.actionIcon,
    this.onAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: tokens.textMuted.withValues(alpha: 0.86),
              fontSize: FontSizes.xs,
              height: 1.1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (actionIcon != null && onAction != null)
          Tooltip(
            message: actionTooltip ?? title,
            child: InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(Radii.sm),
              child: SizedBox(
                width: 22,
                height: 22,
                child: Icon(actionIcon, color: tokens.textMuted, size: 14),
              ),
            ),
          ),
      ],
    );
  }
}

class _SourceDotGrid extends ConsumerWidget {
  final int activeCount;

  const _SourceDotGrid({required this.activeCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final count = activeCount.clamp(1, 24).toInt();
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (var index = 0; index < 24; index++)
          Icon(
            Icons.language,
            size: 11,
            color: index < count
                ? tokens.textMuted.withValues(alpha: 0.76)
                : tokens.textMuted.withValues(alpha: 0.18),
          ),
      ],
    );
  }
}
