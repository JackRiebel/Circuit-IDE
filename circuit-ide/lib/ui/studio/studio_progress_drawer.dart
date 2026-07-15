import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/agent_workspace.dart';
import '../../models/command_run.dart';
import '../../models/provider_lifecycle_event.dart';
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
import 'studio_chrome.dart';

/// Projects the active task's durable progress, actions, and provider state.
class StudioProgressDrawer extends ConsumerWidget {
  final AgentTask? task;

  const StudioProgressDrawer({super.key, this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final thread = ref.watch(
      studioThreadProvider.select((state) => state.threadForTaskView(task?.id)),
    );
    final latestTurn = _latestTurn(thread);
    final latestEvent = _latestEvent(latestTurn);
    final latestActionableEvent = _latestActionableEvent(latestTurn);
    final queuedContinuation = _queuedContinuationStep(latestTurn);
    final latestDiagnostic = _latestDiagnostic(latestTurn);
    final outcomeRepairCount = _diagnosticCount(
      latestTurn,
      ProviderLifecycleEventKind.outcomeRepair,
    );
    final hasPendingApproval = _hasPendingApproval(latestTurn);
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
    final displayState = TaskDisplayState.fromLifecycle(
      StudioTaskLifecycleState.fromThread(thread),
    );
    final actionableTitle = _actionableTitle(
      patch: patch,
      hasPendingApproval: hasPendingApproval,
      runningCommand: runningCommand,
      queuedContinuation: queuedContinuation,
    );
    final actionableDetail = _actionableDetail(
      patch: patch,
      hasPendingApproval: hasPendingApproval,
      runningCommand: runningCommand,
      queuedContinuation: queuedContinuation,
    );
    final actionableEventIsGenericError =
        latestActionableEvent?.type == StudioTurnEventType.error &&
        latestDiagnostic != null;
    final eventTitle = actionableEventIsGenericError
        ? null
        : latestActionableEvent?.title;
    final eventDetail = actionableEventIsGenericError
        ? null
        : latestActionableEvent?.detail;
    // A running turn can retain a generic provider diagnostic (for example,
    // the bounded research-outcome repair) while publishing a newer, specific
    // progress event. Prefer that visible progress so the drawer describes
    // what Studio is doing now; a generic error still retains its diagnostic
    // as the root cause rather than being masked by an event title.
    final statusTitle = actionableEventIsGenericError
        ? _diagnosticTitle(latestDiagnostic)
        : latestEvent?.title ?? _diagnosticTitle(latestDiagnostic);
    final statusDetail = actionableEventIsGenericError
        ? (latestDiagnostic.detail ?? _diagnosticDetail(latestDiagnostic))
        : (latestEvent?.detail ??
              latestDiagnostic?.detail ??
              _diagnosticDetail(latestDiagnostic));
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
          accent: displayState.isActive || displayState.needsAttention,
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
      if (outcomeRepairCount > 0)
        StudioProgressRow(
          label: 'Repair',
          value: outcomeRepairCount == 1
              ? '1 model retry'
              : '$outcomeRepairCount model retries',
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(15, 7, 15, 14),
      children: [
        _DrawerSectionHeader(
          title: 'Environment',
          actionTooltip: 'Context details',
          actionIcon: StudioIcons.add,
          onAction: () =>
              ref.read(studioRightDrawerProvider.notifier).openContext(),
        ),
        const SizedBox(height: 7),
        for (final row in rows) _ProgressRow(row: row),
        const SizedBox(height: 10),
        Divider(color: tokens.studioDivider.withValues(alpha: 0.32), height: 1),
        const SizedBox(height: 10),
        const _DrawerSectionHeader(title: 'Latest event'),
        const SizedBox(height: 8),
        _MiniEvent(
          icon: StudioIcons.history,
          title:
              actionableTitle ??
              eventTitle ??
              statusTitle ??
              displayState.label,
          detail:
              actionableDetail ??
              eventDetail ??
              statusDetail ??
              thread?.contextSummary?.detail ??
              'Studio is ready.',
        ),
      ],
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

  StudioTurnEvent? _latestEvent(StudioTurn? turn) {
    if (turn == null || turn.events.isEmpty) return null;
    final events = turn.events.where(_isProgressDrawableEvent).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return events.firstOrNull;
  }

  bool _isProgressDrawableEvent(StudioTurnEvent event) {
    return switch (event.type) {
      StudioTurnEventType.userMessage ||
      StudioTurnEventType.assistantMessage ||
      StudioTurnEventType.context => false,
      StudioTurnEventType.progress ||
      StudioTurnEventType.tool ||
      StudioTurnEventType.approvalRequest ||
      StudioTurnEventType.error ||
      StudioTurnEventType.completionSummary => true,
    };
  }

  StudioTurnEvent? _latestActionableEvent(StudioTurn? turn) {
    if (turn == null || turn.events.isEmpty) return null;
    final events =
        turn.events.where((event) => _isActionableLatestEvent(event)).toList()
          ..sort((a, b) {
            final priorityCompare = _actionableEventPriority(
              b,
            ).compareTo(_actionableEventPriority(a));
            if (priorityCompare != 0) return priorityCompare;
            return b.timestamp.compareTo(a.timestamp);
          });
    return events.firstOrNull;
  }

  TurnStepRecord? _queuedContinuationStep(StudioTurn? turn) {
    if (turn == null || turn.steps.isEmpty) return null;
    final steps =
        turn.steps
            .where(
              (step) =>
                  step.step == TurnStep.continuation &&
                  step.status == TurnStepStatus.queued,
            )
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return steps.firstOrNull;
  }

  int _actionableEventPriority(StudioTurnEvent event) {
    if (event.type == StudioTurnEventType.approvalRequest &&
        event.approvalState == ApprovalRequestState.pending) {
      return 100;
    }
    if (event.type == StudioTurnEventType.completionSummary) {
      final title = event.title.toLowerCase();
      if (title.contains('patch conflict')) return 90;
      if (title.contains('patch revision requested')) return 85;
      if (title.contains('continue next batch')) return 84;
      if (title.contains('prepared') || title.contains('applied changes')) {
        return 80;
      }
      if (title.contains('verification') || title.contains('command')) {
        return 70;
      }
      return 60;
    }
    if (event.type == StudioTurnEventType.error) return 10;
    return 0;
  }

  bool _isActionableLatestEvent(StudioTurnEvent event) {
    return switch (event.type) {
      StudioTurnEventType.approvalRequest =>
        event.approvalState == ApprovalRequestState.pending,
      StudioTurnEventType.completionSummary ||
      StudioTurnEventType.error => true,
      StudioTurnEventType.userMessage ||
      StudioTurnEventType.context ||
      StudioTurnEventType.assistantMessage ||
      StudioTurnEventType.progress ||
      StudioTurnEventType.tool => false,
    };
  }

  ProviderLifecycleEvent? _latestDiagnostic(StudioTurn? turn) {
    if (turn == null || turn.providerDiagnostics.isEmpty) return null;
    final diagnostics = turn.providerDiagnostics.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (turn.status == StudioTurnStatus.failed ||
        turn.status == StudioTurnStatus.cancelled ||
        turn.status == StudioTurnStatus.interrupted) {
      return diagnostics.where(_isRootCauseDiagnostic).firstOrNull ??
          diagnostics.first;
    }
    return diagnostics.first;
  }

  bool _isRootCauseDiagnostic(ProviderLifecycleEvent diagnostic) {
    return switch (diagnostic.kind) {
      ProviderLifecycleEventKind.authFailed ||
      ProviderLifecycleEventKind.noFirstByte ||
      ProviderLifecycleEventKind.noTextOrTool ||
      ProviderLifecycleEventKind.unavailableTool ||
      ProviderLifecycleEventKind.rateLimited ||
      ProviderLifecycleEventKind.malformedChunk ||
      ProviderLifecycleEventKind.malformedBytes ||
      ProviderLifecycleEventKind.streamEndedWithoutDone ||
      ProviderLifecycleEventKind.outcomeRejected ||
      ProviderLifecycleEventKind.timeout ||
      ProviderLifecycleEventKind.cancelled => true,
      _ => false,
    };
  }

  String? _actionableTitle({
    required ProposedPatchSet? patch,
    required bool hasPendingApproval,
    required CommandRun? runningCommand,
    required TurnStepRecord? queuedContinuation,
  }) {
    if (hasPendingApproval) return 'Approval needed';
    if (patch?.applyStatus == PatchApplyStatus.conflict) {
      return 'Patch conflict';
    }
    if (patch?.applyStatus == PatchApplyStatus.revisionRequested) {
      return 'Patch revision requested';
    }
    if (queuedContinuation != null) return queuedContinuation.title;
    if (patch?.applyStatus == PatchApplyStatus.applied) {
      return 'Applied changes';
    }
    if (patch != null && patch.applyStatus != PatchApplyStatus.applied) {
      return patch.isPlanOnly ? 'Plan ready' : 'Prepared changes';
    }
    if (runningCommand != null) return 'Command running';
    return null;
  }

  String? _actionableDetail({
    required ProposedPatchSet? patch,
    required bool hasPendingApproval,
    required CommandRun? runningCommand,
    required TurnStepRecord? queuedContinuation,
  }) {
    if (hasPendingApproval) {
      return 'Review the pending approval in the transcript.';
    }
    if (patch?.applyStatus == PatchApplyStatus.conflict) {
      return patch?.conflictMessage ??
          'Resolve the patch conflict or ask Circuit to revise it.';
    }
    if (patch?.applyStatus == PatchApplyStatus.revisionRequested) {
      return patch?.revisionPrompt ??
          'Circuit will use the current files and patch context to prepare an updated proposal.';
    }
    if (queuedContinuation != null) return queuedContinuation.detail;
    if (patch?.applyStatus == PatchApplyStatus.applied) {
      final changedCount = patch?.changedFiles.length ?? 0;
      if (changedCount > 0) {
        return 'Applied $changedCount ${changedCount == 1 ? 'file' : 'files'}.';
      }
      final fileCount = patch?.fileCount ?? 0;
      if (fileCount > 0) {
        return 'Applied $fileCount ${fileCount == 1 ? 'file' : 'files'}.';
      }
      return 'Patch applied successfully.';
    }
    if (patch != null && patch.applyStatus != PatchApplyStatus.applied) {
      return patch.isPlanOnly
          ? 'Review the plan card before implementation.'
          : 'Review, revise, or apply the prepared changes.';
    }
    if (runningCommand != null) {
      return runningCommand.command;
    }
    return null;
  }

  int _diagnosticCount(StudioTurn? turn, ProviderLifecycleEventKind kind) {
    if (turn == null) return 0;
    return turn.providerDiagnostics
        .where((diagnostic) => diagnostic.kind == kind)
        .length;
  }

  String? _diagnosticTitle(ProviderLifecycleEvent? diagnostic) {
    if (diagnostic == null) return null;
    return switch (diagnostic.kind) {
      ProviderLifecycleEventKind.requestSent => 'Request sent',
      ProviderLifecycleEventKind.toolExposure => 'Tools exposed',
      ProviderLifecycleEventKind.authFailed => 'Authentication failed',
      ProviderLifecycleEventKind.reconnecting => 'Refreshing authentication',
      ProviderLifecycleEventKind.connected => 'Provider connected',
      ProviderLifecycleEventKind.firstByte => 'Response started',
      ProviderLifecycleEventKind.noFirstByte => 'No provider response bytes',
      ProviderLifecycleEventKind.firstTextDelta => 'Writing response',
      ProviderLifecycleEventKind.firstToolDelta => 'Tool call started',
      ProviderLifecycleEventKind.nonSseJson => 'Non-streaming response',
      ProviderLifecycleEventKind.jsonFallback => 'JSON fallback',
      ProviderLifecycleEventKind.toolOnly => 'Tool-only response',
      ProviderLifecycleEventKind.noTextOrTool => 'No model output',
      ProviderLifecycleEventKind.unavailableTool => 'Unavailable tool',
      ProviderLifecycleEventKind.rateLimited => 'Rate limited',
      ProviderLifecycleEventKind.malformedChunk => 'Malformed stream chunk',
      ProviderLifecycleEventKind.malformedBytes => 'Malformed response bytes',
      ProviderLifecycleEventKind.streamEndedWithoutDone => 'Stream ended early',
      ProviderLifecycleEventKind.outcomeRepair => 'Repairing response',
      ProviderLifecycleEventKind.outcomeRejected => 'Invalid model outcome',
      ProviderLifecycleEventKind.completed => 'Provider completed',
      ProviderLifecycleEventKind.failed => 'Provider failed',
      ProviderLifecycleEventKind.cancelled => 'Provider cancelled',
      ProviderLifecycleEventKind.timeout => 'Provider timed out',
    };
  }

  String? _diagnosticDetail(ProviderLifecycleEvent? diagnostic) {
    if (diagnostic == null) return null;
    return switch (diagnostic.kind) {
      ProviderLifecycleEventKind.outcomeRepair =>
        'Circuit rejected a vague draft and requested one structured repair.',
      ProviderLifecycleEventKind.toolOnly =>
        'Circuit returned tool calls without assistant text.',
      ProviderLifecycleEventKind.noTextOrTool =>
        'Circuit returned neither assistant text nor tool calls.',
      ProviderLifecycleEventKind.noFirstByte =>
        'Circuit did not return response bytes before the request ended.',
      ProviderLifecycleEventKind.nonSseJson ||
      ProviderLifecycleEventKind.jsonFallback =>
        'Circuit returned a non-streaming JSON response.',
      ProviderLifecycleEventKind.malformedChunk =>
        'Circuit returned a malformed stream chunk.',
      ProviderLifecycleEventKind.malformedBytes =>
        'Circuit returned response bytes that were not valid UTF-8.',
      ProviderLifecycleEventKind.streamEndedWithoutDone =>
        'Circuit closed the SSE stream without the normal completion marker.',
      ProviderLifecycleEventKind.unavailableTool =>
        'Circuit requested a tool that is hidden for this mode or phase.',
      ProviderLifecycleEventKind.rateLimited =>
        'Circuit API is rate limited. Wait for the retry window or try again later.',
      ProviderLifecycleEventKind.authFailed =>
        'Circuit credentials or token refresh failed.',
      ProviderLifecycleEventKind.reconnecting =>
        'Circuit refreshed authentication and is retrying this request once.',
      ProviderLifecycleEventKind.timeout =>
        'Circuit did not finish before the timeout.',
      ProviderLifecycleEventKind.cancelled => 'The request was cancelled.',
      ProviderLifecycleEventKind.failed => 'The provider reported a failure.',
      _ => null,
    };
  }

  bool _hasPendingApproval(StudioTurn? turn) {
    return turn?.events.any(
          (event) =>
              event.type == StudioTurnEventType.approvalRequest &&
              event.approvalState == ApprovalRequestState.pending,
        ) ??
        false;
  }
}

class _DrawerSectionHeader extends ConsumerWidget {
  final String title;
  final String? actionTooltip;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  const _DrawerSectionHeader({
    required this.title,
    this.actionTooltip,
    this.actionIcon,
    this.onAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
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
          ),
          if (actionIcon != null && onAction != null)
            StudioChromeIconButton(
              tooltip: actionTooltip ?? title,
              icon: actionIcon!,
              onTap: onAction!,
              width: StudioChromeIconButton.minimumTargetSize,
              height: StudioChromeIconButton.minimumTargetSize,
              iconSize: 14,
            ),
        ],
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
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
      'Task' => StudioIcons.radioButtonChecked,
      'Approval' => StudioIcons.shieldOutlined,
      'Command' => StudioIcons.terminalOutlined,
      'Changes' => StudioIcons.inventory2Outlined,
      'Local' => StudioIcons.computerOutlined,
      'Branch' => StudioIcons.accountTreeOutlined,
      _ => StudioIcons.dataObjectOutlined,
    };
  }
}

class _MiniEvent extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _MiniEvent({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: tokens.studioActivityRow.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.34)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tokens.textMuted.withValues(alpha: 0.9), size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.sm,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
                if (detail.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                      height: 1.22,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
