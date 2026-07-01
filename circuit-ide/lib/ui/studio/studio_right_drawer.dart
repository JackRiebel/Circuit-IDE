import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/constants/design_tokens.dart';
import '../../core/config/studio_feature_flags.dart';
import '../../models/agent_workspace.dart';
import '../../models/command_run.dart';
import '../../models/context_pack.dart';
import '../../models/generated_artifact.dart';
import '../../models/git_models.dart';
import '../../models/provider_lifecycle_event.dart';
import '../../models/reviewed_edit.dart';
import '../../models/studio_browser.dart';
import '../../models/studio_right_drawer.dart';
import '../../models/studio_shell.dart';
import '../../models/studio_source_artifact.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_turn.dart';
import '../../models/studio_view_models.dart';
import '../../state/command_run_provider.dart';
import '../../state/context_pack_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/git_provider.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/studio_browser_provider.dart';
import '../../state/studio_code_edit_provider.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_source_artifact_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';
import 'studio_chrome.dart';

class StudioRightDrawer extends ConsumerWidget {
  final AgentTask? task;

  const StudioRightDrawer({super.key, this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final drawer = ref.watch(studioRightDrawerProvider);
    final width = drawer.width;

    return AnimatedContainer(
      duration: AnimationDurations.panel,
      curve: AnimationCurves.smooth,
      width: width,
      margin: const EdgeInsets.fromLTRB(0, 48, 12, 16),
      decoration: BoxDecoration(
        color: tokens.studioDrawer.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: drawer.collapsed
          ? const _CollapsedDrawer()
          : Column(
              children: [
                _DrawerHeader(task: task),
                const _DrawerModeStrip(),
                Expanded(child: _DrawerBody(task: task)),
              ],
            ),
    );
  }
}

const _visibleDrawerModes = <StudioDrawerMode>[
  StudioDrawerMode.progress,
  StudioDrawerMode.artifacts,
  StudioDrawerMode.code,
  StudioDrawerMode.diff,
  StudioDrawerMode.files,
  StudioDrawerMode.terminal,
  StudioDrawerMode.context,
];

class _CollapsedDrawer extends ConsumerWidget {
  const _CollapsedDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        const SizedBox(height: 5),
        StudioChromeIconButton(
          tooltip: 'Expand right panel',
          onTap: () =>
              ref.read(studioRightDrawerProvider.notifier).toggleCollapsed(),
          icon: Icons.chevron_left,
          width: 30,
          height: 24,
          iconSize: 14,
        ),
        const SizedBox(height: 2),
        for (final mode in _visibleDrawerModes)
          _ModeIconButton(mode: mode, active: false, compact: true),
      ],
    );
  }
}

class _DrawerHeader extends ConsumerWidget {
  final AgentTask? task;

  const _DrawerHeader({this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final drawer = ref.watch(studioRightDrawerProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 9, 7, 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              _titleFor(drawer.mode),
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.sm,
                height: 1.2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (drawer.mode == StudioDrawerMode.progress) ...[
            StudioChromeIconButton(
              tooltip: drawer.expanded ? 'Shrink panel' : 'Expand panel',
              onTap: () =>
                  ref.read(studioRightDrawerProvider.notifier).toggleExpanded(),
              icon: drawer.expanded
                  ? Icons.close_fullscreen
                  : Icons.open_in_full_outlined,
            ),
            StudioChromeIconButton(
              tooltip: 'Collapse panel',
              onTap: () => ref
                  .read(studioRightDrawerProvider.notifier)
                  .toggleCollapsed(),
              icon: Icons.chevron_right,
            ),
          ],
          if (drawer.mode != StudioDrawerMode.progress) ...[
            _DrawerModeMenu(active: drawer.mode),
            StudioChromeIconButton(
              tooltip: drawer.expanded ? 'Shrink panel' : 'Expand panel',
              onTap: () =>
                  ref.read(studioRightDrawerProvider.notifier).toggleExpanded(),
              icon: drawer.expanded
                  ? Icons.close_fullscreen
                  : Icons.open_in_full_outlined,
            ),
            StudioChromeIconButton(
              tooltip: 'Collapse panel',
              onTap: () => ref
                  .read(studioRightDrawerProvider.notifier)
                  .toggleCollapsed(),
              icon: Icons.chevron_right,
            ),
          ],
        ],
      ),
    );
  }

  String _titleFor(StudioDrawerMode mode) {
    return switch (mode) {
      StudioDrawerMode.progress => 'Progress',
      StudioDrawerMode.browser => 'Preview',
      StudioDrawerMode.code => 'Code',
      StudioDrawerMode.diff => 'Diff',
      StudioDrawerMode.files => 'Files',
      StudioDrawerMode.artifacts => 'Artifacts',
      StudioDrawerMode.terminal => 'Terminal',
      StudioDrawerMode.sources => 'Sources',
      StudioDrawerMode.context => 'Context',
    };
  }
}

class _DrawerModeStrip extends ConsumerWidget {
  const _DrawerModeStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final drawer = ref.watch(studioRightDrawerProvider);
    return Container(
      height: 35,
      padding: const EdgeInsets.fromLTRB(11, 3, 11, 7),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: tokens.studioDivider.withValues(alpha: 0.24),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final mode in _visibleDrawerModes)
            _ModeIconButton(mode: mode, active: mode == drawer.mode),
        ],
      ),
    );
  }
}

class _DrawerModeMenu extends ConsumerWidget {
  final StudioDrawerMode active;

  const _DrawerModeMenu({required this.active});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return PopupMenuButton<StudioDrawerMode>(
      tooltip: 'Open drawer view',
      color: tokens.studioPanel,
      elevation: 10,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.7)),
      ),
      onSelected: (mode) =>
          ref.read(studioRightDrawerProvider.notifier).openMode(mode),
      itemBuilder: (context) => [
        for (final mode in _visibleDrawerModes)
          PopupMenuItem<StudioDrawerMode>(
            height: 34,
            value: mode,
            child: Row(
              children: [
                Icon(
                  _drawerModeIcon(mode),
                  color: mode == active
                      ? tokens.textSecondary
                      : tokens.textMuted,
                  size: 13,
                ),
                const SizedBox(width: Spacing.md),
                Text(
                  _drawerModeLabel(mode),
                  style: TextStyle(
                    color: mode == active
                        ? tokens.textSecondary
                        : tokens.textMuted,
                    fontSize: FontSizes.xs,
                    fontWeight: mode == active
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: SizedBox(
        width: 26,
        height: 22,
        child: Icon(Icons.tune_outlined, color: tokens.textMuted, size: 13),
      ),
    );
  }
}

class _ModeIconButton extends ConsumerWidget {
  final StudioDrawerMode mode;
  final bool active;
  final bool compact;

  const _ModeIconButton({
    required this.mode,
    required this.active,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final color = active ? tokens.textSecondary : tokens.textMuted;
    return Tooltip(
      message: _drawerModeLabel(mode),
      child: InkWell(
        onTap: () =>
            ref.read(studioRightDrawerProvider.notifier).openMode(mode),
        borderRadius: BorderRadius.circular(7),
        child: Container(
          width: compact ? 34 : 28,
          height: compact ? 24 : 24,
          margin: EdgeInsets.only(right: compact ? 0 : 4),
          decoration: BoxDecoration(
            color: active
                ? tokens.studioControl.withValues(alpha: 0.42)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: active
                ? Border.all(
                    color: tokens.studioDivider.withValues(alpha: 0.32),
                  )
                : null,
          ),
          child: Icon(_drawerModeIcon(mode), color: color, size: 13),
        ),
      ),
    );
  }
}

IconData _drawerModeIcon(StudioDrawerMode mode) {
  return switch (mode) {
    StudioDrawerMode.progress => Icons.radio_button_checked,
    StudioDrawerMode.browser => Icons.language,
    StudioDrawerMode.code => Icons.code,
    StudioDrawerMode.diff => Icons.difference_outlined,
    StudioDrawerMode.files => Icons.folder_outlined,
    StudioDrawerMode.artifacts => Icons.file_present_outlined,
    StudioDrawerMode.terminal => Icons.terminal_outlined,
    StudioDrawerMode.sources => Icons.travel_explore,
    StudioDrawerMode.context => Icons.inventory_2_outlined,
  };
}

String _drawerModeLabel(StudioDrawerMode mode) {
  return switch (mode) {
    StudioDrawerMode.progress => 'Progress',
    StudioDrawerMode.browser => 'Browser preview',
    StudioDrawerMode.code => 'Code',
    StudioDrawerMode.diff => 'Diff',
    StudioDrawerMode.files => 'Files',
    StudioDrawerMode.artifacts => 'Artifacts',
    StudioDrawerMode.terminal => 'Terminal output',
    StudioDrawerMode.sources => 'Sources',
    StudioDrawerMode.context => 'Context details',
  };
}

class _DrawerBody extends ConsumerWidget {
  final AgentTask? task;

  const _DrawerBody({this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(studioRightDrawerProvider).mode;
    final safeMode =
        mode == StudioDrawerMode.browser &&
            !StudioFeatureFlags.advancedStudioSurfaces
        ? StudioDrawerMode.sources
        : mode;
    return switch (safeMode) {
      StudioDrawerMode.progress => _ProgressDrawer(task: task),
      StudioDrawerMode.browser => const _BrowserDrawer(),
      StudioDrawerMode.code => const _CodeDrawer(),
      StudioDrawerMode.diff => _DiffDrawer(task: task),
      StudioDrawerMode.files => const _FilesDrawer(),
      StudioDrawerMode.artifacts => _ArtifactsDrawer(task: task),
      StudioDrawerMode.terminal => _TerminalDrawer(task: task),
      StudioDrawerMode.sources => _SourcesDrawer(task: task),
      StudioDrawerMode.context => _ContextDrawer(task: task),
    };
  }
}

class _ProgressDrawer extends ConsumerWidget {
  final AgentTask? task;

  const _ProgressDrawer({this.task});

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
        const _DrawerSectionHeader(title: 'Environment'),
        const SizedBox(height: 7),
        for (final row in rows) _ProgressRow(row: row),
        const SizedBox(height: 10),
        Divider(color: tokens.studioDivider.withValues(alpha: 0.32), height: 1),
        const SizedBox(height: 10),
        const _DrawerSectionHeader(title: 'Latest event'),
        const SizedBox(height: 8),
        _MiniEvent(
          icon: Icons.history,
          title:
              actionableTitle ??
              eventTitle ??
              _diagnosticTitle(latestDiagnostic) ??
              latestActionableEvent?.title ??
              latestEvent?.title ??
              displayState.label,
          detail:
              actionableDetail ??
              eventDetail ??
              latestDiagnostic?.detail ??
              _diagnosticDetail(latestDiagnostic) ??
              latestActionableEvent?.detail ??
              latestEvent?.detail ??
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
    final events = turn.events.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return events.first;
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
        turn.status == StudioTurnStatus.cancelled) {
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

  const _DrawerSectionHeader({required this.title});

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
      ],
    );
  }
}

class _BrowserDrawer extends ConsumerStatefulWidget {
  const _BrowserDrawer();

  @override
  ConsumerState<_BrowserDrawer> createState() => _BrowserDrawerState();
}

class _BrowserDrawerState extends ConsumerState<_BrowserDrawer> {
  WebViewController? _controller;
  String? _loadedUrl;
  String? _scheduledLoadKey;
  int _loadedReloadNonce = 0;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final drawer = ref.watch(studioRightDrawerProvider);
    final session = ref.watch(studioBrowserProvider);
    final selected = _selectedArtifact(ref);
    final url = drawer.localUrl ?? selected?.localUrl ?? session.currentUrl;
    if (url != null && session.currentUrl != url) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ref.read(studioBrowserProvider).currentUrl == url) return;
        ref.read(studioBrowserProvider.notifier).open(url);
      });
    }
    final activeUrl = session.currentUrl ?? url;
    if (activeUrl != null &&
        (activeUrl != _loadedUrl ||
            session.reloadNonce != _loadedReloadNonce)) {
      final loadKey = '$activeUrl#${session.reloadNonce}';
      if (_scheduledLoadKey != loadKey) {
        _scheduledLoadKey = loadKey;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_loadedUrl == activeUrl &&
              _loadedReloadNonce == session.reloadNonce) {
            return;
          }
          _load(activeUrl, session.reloadNonce);
        });
      }
    }

    if (activeUrl == null) {
      return const _EmptyDrawerState(
        icon: Icons.language,
        title: 'No local preview yet',
        detail: 'Enter a URL or open a localhost source from the task.',
      );
    }

    return Column(
      children: [
        _BrowserToolbar(
          session: session,
          onBack: () {
            ref.read(studioBrowserProvider.notifier).goBack();
          },
          onForward: () {
            ref.read(studioBrowserProvider.notifier).goForward();
          },
          onNavigate: (value) {
            ref.read(studioBrowserProvider.notifier).open(value);
          },
          onReload: () {
            ref.read(studioBrowserProvider.notifier).reload();
          },
          onCopy: () => Clipboard.setData(ClipboardData(text: activeUrl)),
          onOpenExternal: () => launchUrl(Uri.parse(activeUrl)),
          onAllow: () => ref.read(studioBrowserProvider.notifier).allowSite(),
          onBlock: () => ref.read(studioBrowserProvider.notifier).blockSite(),
          onComment: () => _showCommentDialog(activeUrl),
        ),
        if (session.error != null)
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Text(
              session.error!,
              style: TextStyle(color: tokens.error, fontSize: FontSizes.sm),
            ),
          ),
        if (session.permission == BrowserSitePermission.blocked)
          const Expanded(
            child: _EmptyDrawerState(
              icon: Icons.block,
              title: 'Site blocked',
              detail: 'Allow this site from the browser toolbar to load it.',
            ),
          )
        else
          Expanded(
            child: _controller == null
                ? const Center(child: CircularProgressIndicator())
                : WebViewWidget(controller: _controller!),
          ),
      ],
    );
  }

  StudioSourceArtifact? _selectedArtifact(WidgetRef ref) {
    final drawer = ref.watch(studioRightDrawerProvider);
    return ref.watch(
      studioSourceArtifactByIdProvider(drawer.selectedArtifactId),
    );
  }

  void _load(String url, int reloadNonce) {
    _loadedUrl = url;
    _loadedReloadNonce = reloadNonce;
    ref.read(studioBrowserProvider.notifier).setError(null);
    ref.read(studioBrowserProvider.notifier).setProgress(0);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            ref.read(studioBrowserProvider.notifier).setProgress(progress);
          },
          onWebResourceError: (error) {
            ref
                .read(studioBrowserProvider.notifier)
                .setError(error.description);
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
    setState(() {});
  }

  Future<void> _showCommentDialog(String url) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) {
        final tokens = ref.read(themeProvider);
        return AlertDialog(
          backgroundColor: tokens.studioPanel,
          title: const Text('Comment on preview'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: 'Describe what Circuit should notice or change...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Add comment'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (note == null || note.trim().isEmpty) return;
    ref.read(studioBrowserProvider.notifier).addAnnotation(note);
  }
}

class _BrowserToolbar extends ConsumerWidget {
  final StudioBrowserSession session;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final ValueChanged<String> onNavigate;
  final VoidCallback onReload;
  final VoidCallback onCopy;
  final VoidCallback onOpenExternal;
  final VoidCallback onAllow;
  final VoidCallback onBlock;
  final VoidCallback onComment;

  const _BrowserToolbar({
    required this.session,
    required this.onBack,
    required this.onForward,
    required this.onNavigate,
    required this.onReload,
    required this.onCopy,
    required this.onOpenExternal,
    required this.onAllow,
    required this.onBlock,
    required this.onComment,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final url = session.currentUrl ?? session.addressDraft;
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.studioDivider)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              StudioChromeIconButton(
                tooltip: 'Back',
                onTap: session.canGoBack ? onBack : null,
                icon: Icons.chevron_left,
                iconSize: 14,
                width: 28,
                height: 24,
              ),
              StudioChromeIconButton(
                tooltip: 'Forward',
                onTap: session.canGoForward ? onForward : null,
                icon: Icons.chevron_right,
                iconSize: 14,
                width: 28,
                height: 24,
              ),
              Expanded(
                child: TextFormField(
                  initialValue: url,
                  onFieldSubmitted: onNavigate,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: Spacing.md,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      borderSide: BorderSide(color: tokens.studioDivider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      borderSide: BorderSide(color: tokens.studioDivider),
                    ),
                  ),
                ),
              ),
              StudioChromeIconButton(
                tooltip: 'Reload',
                onTap: onReload,
                icon: Icons.refresh,
                iconSize: 14,
                width: 28,
                height: 24,
              ),
              StudioChromeIconButton(
                tooltip: 'Copy URL',
                onTap: onCopy,
                icon: Icons.copy,
                iconSize: 14,
                width: 28,
                height: 24,
              ),
              StudioChromeIconButton(
                tooltip: 'Open external',
                onTap: onOpenExternal,
                icon: Icons.open_in_new,
                iconSize: 14,
                width: 28,
                height: 24,
              ),
              PopupMenuButton<BrowserSitePermission>(
                tooltip: 'Site permission',
                color: tokens.studioPanel,
                onSelected: (value) {
                  if (value == BrowserSitePermission.allowed) onAllow();
                  if (value == BrowserSitePermission.blocked) onBlock();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: BrowserSitePermission.allowed,
                    child: Text('Allow site'),
                  ),
                  PopupMenuItem(
                    value: BrowserSitePermission.blocked,
                    child: Text('Block site'),
                  ),
                ],
                child: Icon(
                  session.permission == BrowserSitePermission.blocked
                      ? Icons.block
                      : Icons.security_outlined,
                  size: 14,
                  color: tokens.textMuted,
                ),
              ),
              StudioChromeIconButton(
                tooltip: 'Add browser comment',
                onTap: onComment,
                icon: Icons.add_comment_outlined,
                iconSize: 14,
                width: 28,
                height: 24,
              ),
            ],
          ),
          if (session.loadingProgress > 0 && session.loadingProgress < 100)
            LinearProgressIndicator(value: session.loadingProgress / 100),
          if (session.annotations.isNotEmpty) ...[
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${session.annotations.length} preview comments attached',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CodeDrawer extends ConsumerWidget {
  const _CodeDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drawer = ref.watch(studioRightDrawerProvider);
    final selected = _selectedArtifact(ref);
    final rootPath = ref.watch(fileTreeProvider).rootPath;
    final path = drawer.filePath ?? selected?.filePath;
    if (path == null) {
      return const _EmptyDrawerState(
        icon: Icons.code,
        title: 'No file selected',
        detail: 'Open a file or source row to inspect code here.',
      );
    }
    final resolved = _resolvePath(rootPath, path);
    final editor = ref.watch(studioCodeEditProvider);
    if (editor.filePath != path && !editor.isLoading) {
      Future.microtask(
        () => ref.read(studioCodeEditProvider.notifier).open(path),
      );
    }
    if (editor.isLoading || editor.filePath != path) {
      return const Center(child: CircularProgressIndicator());
    }
    if (editor.error != null) {
      return _EmptyDrawerState(
        icon: Icons.error_outline,
        title: 'Could not open file',
        detail: editor.error!,
      );
    }
    return _CodePreviewView(title: path, resolvedPath: resolved, state: editor);
  }

  StudioSourceArtifact? _selectedArtifact(WidgetRef ref) {
    final drawer = ref.watch(studioRightDrawerProvider);
    return ref.watch(
      studioSourceArtifactByIdProvider(drawer.selectedArtifactId),
    );
  }
}

class _CodePreviewView extends ConsumerWidget {
  final String title;
  final String resolvedPath;
  final StudioCodeEditState state;

  const _CodePreviewView({
    required this.title,
    required this.resolvedPath,
    required this.state,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.surfaceInset.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: tokens.studioDivider.withValues(alpha: 0.68),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.sm,
                Spacing.sm,
                Spacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: resolvedPath,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: FontSizes.xs,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.studioControl.withValues(alpha: 0.44),
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Text(
                      'Read only',
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: FontSizes.xs,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.xs),
                  StudioChromeIconButton(
                    tooltip: 'Copy',
                    onTap: () =>
                        Clipboard.setData(ClipboardData(text: state.draft)),
                    icon: Icons.copy,
                    width: 26,
                    height: 24,
                    iconSize: 14,
                  ),
                ],
              ),
            ),
            Divider(
              color: tokens.studioDivider.withValues(alpha: 0.72),
              height: 1,
            ),
            Expanded(
              child: RepaintBoundary(
                child: _VirtualizedTextDocumentBody(
                  text: state.draft,
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.md,
                    Spacing.sm,
                    Spacing.md,
                    Spacing.lg,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VirtualizedTextDocumentBody extends ConsumerStatefulWidget {
  final String text;
  final EdgeInsets padding;

  const _VirtualizedTextDocumentBody({
    required this.text,
    required this.padding,
  });

  @override
  ConsumerState<_VirtualizedTextDocumentBody> createState() =>
      _VirtualizedTextDocumentBodyState();
}

class _VirtualizedTextDocumentBodyState
    extends ConsumerState<_VirtualizedTextDocumentBody> {
  late List<String> _lines;
  late int _maxLineLength;

  @override
  void initState() {
    super.initState();
    _prepareLines();
  }

  @override
  void didUpdateWidget(covariant _VirtualizedTextDocumentBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _prepareLines();
    }
  }

  void _prepareLines() {
    final text = widget.text.isEmpty ? '(empty)' : widget.text;
    _lines = text.split('\n');
    _maxLineLength = 0;
    for (final line in _lines) {
      if (line.length > _maxLineLength) _maxLineLength = line.length;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final lineNumberWidth = (_lines.length + 1).toString().length * 7.0 + 28;
    return LayoutBuilder(
      builder: (context, constraints) {
        final estimatedTextWidth =
            (_maxLineLength * 7.1) + lineNumberWidth + 48;
        final contentWidth = estimatedTextWidth
            .clamp(constraints.maxWidth, 2200.0)
            .toDouble();
        return Scrollbar(
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth,
              child: ListView.builder(
                key: const ValueKey('studio-virtualized-text-lines'),
                padding: widget.padding,
                itemCount: _lines.length,
                itemBuilder: (context, index) {
                  final line = _lines[index];
                  return _VirtualizedTextLine(
                    lineNumber: index + 1,
                    lineNumberWidth: lineNumberWidth,
                    line: line,
                    tokens: tokens,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VirtualizedTextLine extends StatelessWidget {
  final int lineNumber;
  final double lineNumberWidth;
  final String line;
  final ThemeTokens tokens;

  const _VirtualizedTextLine({
    required this.lineNumber,
    required this.lineNumberWidth,
    required this.line,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final color = _lineColor(line, tokens);
    return SizedBox(
      height: 19,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: lineNumberWidth,
            child: Text(
              '$lineNumber',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: tokens.textMuted.withValues(alpha: 0.56),
                fontSize: FontSizes.xs,
                height: 1.42,
                fontFamily: EditorDefaults.studioMonospaceFontFamily,
              ),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              line.isEmpty ? ' ' : line,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: color,
                fontSize: FontSizes.xs,
                height: 1.42,
                fontFamily: EditorDefaults.studioMonospaceFontFamily,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _lineColor(String line, ThemeTokens tokens) {
    if (line.startsWith('+') && !line.startsWith('+++')) {
      return tokens.success.withValues(alpha: 0.92);
    }
    if (line.startsWith('-') && !line.startsWith('---')) {
      return tokens.error.withValues(alpha: 0.92);
    }
    if (line.startsWith('@@')) {
      return tokens.accent.withValues(alpha: 0.9);
    }
    if (line.startsWith('diff ') ||
        line.startsWith('index ') ||
        line.startsWith('+++') ||
        line.startsWith('---')) {
      return tokens.textMuted;
    }
    return tokens.textSecondary;
  }
}

class _DiffDrawer extends ConsumerStatefulWidget {
  final AgentTask? task;

  const _DiffDrawer({this.task});

  @override
  ConsumerState<_DiffDrawer> createState() => _DiffDrawerState();
}

class _DiffDrawerState extends ConsumerState<_DiffDrawer> {
  String? _selectedPath;
  bool _selectedStaged = false;

  @override
  Widget build(BuildContext context) {
    final drawer = ref.watch(studioRightDrawerProvider);
    final patchState = ref.watch(patchProposalProvider);
    final thread = ref
        .watch(studioThreadProvider)
        .threadForTaskView(widget.task?.id);
    final patch = _patchForDrawer(
      patchState,
      drawer.diffId,
      thread: thread,
      taskId: widget.task?.id,
      selectedPath: drawer.patchFilePath,
    );
    if (patch == null) {
      if ((drawer.diffId ?? '').trim().isNotEmpty) {
        return _MissingPatchReviewDrawer(
          patchSetId: drawer.diffId!,
          selectedPath: drawer.patchFilePath,
        );
      }
      return _GitReviewDrawer(
        selectedPath: _selectedPath,
        selectedStaged: _selectedStaged,
        onSelect: (path, staged) {
          setState(() {
            _selectedPath = path;
            _selectedStaged = staged;
          });
        },
      );
    }
    final selectedPath = drawer.patchFilePath;
    return _PatchDiffReviewDrawer(
      patch: patch,
      selectedPath: selectedPath,
      diffText: _diffPreview(patch, selectedPath),
    );
  }

  String _diffPreview(ProposedPatchSet patch, String? selectedPath) {
    final edits = selectedPath == null
        ? patch.edits
        : patch.edits.where((edit) => edit.path == selectedPath).toList();
    if (edits.isEmpty) {
      if (patch.isPlanOnly) {
        return patch.planMarkdown ??
            patch.comparisonSummary ??
            'This plan does not include a file diff yet.';
      }
      return selectedPath == null
          ? 'No diff available yet.'
          : 'No diff available for $selectedPath.';
    }
    return edits
        .map((edit) {
          return [
            '--- ${edit.path}',
            '+++ ${edit.path}',
            if (edit.unifiedDiff?.isNotEmpty == true)
              edit.unifiedDiff!
            else
              _fallbackUnifiedDiff(edit),
          ].join('\n');
        })
        .join('\n\n');
  }
}

String _fallbackUnifiedDiff(ProposedFileEdit edit) {
  final before = edit.before ?? '';
  final after = edit.after ?? '';
  final beforeLines = _splitDiffLines(before);
  final afterLines = _splitDiffLines(after);
  return switch (edit.type) {
    ProposedFileEditType.create => [
      '@@ -0,0 +1,${afterLines.length} @@',
      for (final line in afterLines) '+$line',
    ].join('\n'),
    ProposedFileEditType.delete => [
      '@@ -1,${beforeLines.length} +0,0 @@',
      for (final line in beforeLines) '-$line',
    ].join('\n'),
    ProposedFileEditType.modify => _lineDiff(beforeLines, afterLines),
  };
}

List<String> _splitDiffLines(String value) {
  if (value.isEmpty) return const [];
  final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) {
    return lines.sublist(0, lines.length - 1);
  }
  return lines;
}

String _lineDiff(List<String> before, List<String> after) {
  final rows = _diffRows(before, after);
  final result = <String>['@@ -1,${before.length} +1,${after.length} @@'];
  for (final row in rows) {
    switch (row.type) {
      case _DiffRowType.unchanged:
        result.add(' ${row.value}');
        break;
      case _DiffRowType.removed:
        result.add('-${row.value}');
        break;
      case _DiffRowType.added:
        result.add('+${row.value}');
        break;
    }
  }
  return result.join('\n');
}

List<_DiffRow> _diffRows(List<String> before, List<String> after) {
  final lcs = List.generate(
    before.length + 1,
    (_) => List<int>.filled(after.length + 1, 0),
  );
  for (var i = before.length - 1; i >= 0; i--) {
    for (var j = after.length - 1; j >= 0; j--) {
      lcs[i][j] = before[i] == after[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }

  final rows = <_DiffRow>[];
  var i = 0;
  var j = 0;
  while (i < before.length && j < after.length) {
    if (before[i] == after[j]) {
      rows.add(_DiffRow(_DiffRowType.unchanged, before[i]));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      rows.add(_DiffRow(_DiffRowType.removed, before[i]));
      i++;
    } else {
      rows.add(_DiffRow(_DiffRowType.added, after[j]));
      j++;
    }
  }
  while (i < before.length) {
    rows.add(_DiffRow(_DiffRowType.removed, before[i]));
    i++;
  }
  while (j < after.length) {
    rows.add(_DiffRow(_DiffRowType.added, after[j]));
    j++;
  }
  return rows;
}

enum _DiffRowType { unchanged, removed, added }

class _DiffRow {
  final _DiffRowType type;
  final String value;

  const _DiffRow(this.type, this.value);
}

class _MissingPatchReviewDrawer extends ConsumerWidget {
  final String patchSetId;
  final String? selectedPath;

  const _MissingPatchReviewDrawer({
    required this.patchSetId,
    required this.selectedPath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Center(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: tokens.surfaceInset.withValues(alpha: 0.54),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: tokens.studioDivider.withValues(alpha: 0.62),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.difference_outlined,
                    size: 17,
                    color: tokens.textMuted,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      'Patch review unavailable',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.sm,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                selectedPath == null || selectedPath!.trim().isEmpty
                    ? 'Circuit could not find the selected patch review. It may have been dismissed, restored from older history, or not loaded for this thread yet.'
                    : 'Circuit could not find the selected patch review for $selectedPath. It may have been dismissed, restored from older history, or not loaded for this thread yet.',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.xs,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              SelectableText(
                'Patch id: $patchSetId',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                  height: 1.3,
                  fontFamily: EditorDefaults.studioMonospaceFontFamily,
                ),
              ),
              const SizedBox(height: Spacing.md),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  OutlinedButton(
                    style: _drawerSecondaryActionStyle(tokens),
                    onPressed: () => ref
                        .read(studioRightDrawerProvider.notifier)
                        .openRepositoryDiff(),
                    child: const Text('Show repo changes'),
                  ),
                  OutlinedButton(
                    style: _drawerSecondaryActionStyle(tokens),
                    onPressed:
                        selectedPath == null || selectedPath!.trim().isEmpty
                        ? null
                        : () => ref
                              .read(studioRightDrawerProvider.notifier)
                              .openFile(selectedPath!),
                    child: const Text('Open current file'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatchDiffReviewDrawer extends ConsumerWidget {
  final ProposedPatchSet patch;
  final String? selectedPath;
  final String diffText;

  const _PatchDiffReviewDrawer({
    required this.patch,
    required this.selectedPath,
    required this.diffText,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final edits = patch.edits;
    final effectiveSelectedPath = selectedPath ?? edits.firstOrNull?.path;
    final selectedEdit = effectiveSelectedPath == null
        ? null
        : edits.where((edit) => edit.path == effectiveSelectedPath).firstOrNull;
    final stats = _patchReviewStats(patch);
    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.surfaceInset.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: tokens.studioDivider.withValues(alpha: 0.68),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.sm,
                Spacing.sm,
                Spacing.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: tokens.bgDark.withValues(alpha: 0.48),
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    child: Icon(
                      patch.isPlanOnly
                          ? Icons.alt_route_outlined
                          : Icons.difference_outlined,
                      color: tokens.textMuted,
                      size: 13,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patch.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: FontSizes.xs,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: _formatFileCount(patch.fileCount)),
                              if (stats.additions > 0 || stats.deletions > 0)
                                TextSpan(
                                  text:
                                      '  +${stats.additions} -${stats.deletions}',
                                ),
                              if (patch.applyStatus != null)
                                TextSpan(text: '  ${patch.applyStatus!.name}'),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: FontSizes.xs,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (effectiveSelectedPath != null) ...[
                    StudioChromeIconButton(
                      tooltip: 'Open current file',
                      onTap: () => ref
                          .read(studioRightDrawerProvider.notifier)
                          .openFile(effectiveSelectedPath),
                      icon: Icons.open_in_new,
                      width: 26,
                      height: 24,
                      iconSize: 14,
                    ),
                    const SizedBox(width: Spacing.xs),
                  ],
                  StudioChromeIconButton(
                    tooltip: 'Copy diff',
                    onTap: () =>
                        Clipboard.setData(ClipboardData(text: diffText)),
                    icon: Icons.copy,
                    width: 26,
                    height: 24,
                    iconSize: 14,
                  ),
                ],
              ),
            ),
            Divider(
              color: tokens.studioDivider.withValues(alpha: 0.72),
              height: 1,
            ),
            _PatchReviewActionBar(patch: patch),
            Divider(
              color: tokens.studioDivider.withValues(alpha: 0.72),
              height: 1,
            ),
            if (edits.length > 1)
              SizedBox(
                height: 104,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                  itemCount: edits.length,
                  separatorBuilder: (_, _) => Divider(
                    color: tokens.studioDivider.withValues(alpha: 0.42),
                    height: 1,
                  ),
                  itemBuilder: (context, index) {
                    final edit = edits[index];
                    return _PatchDiffFileRow(
                      edit: edit,
                      selected: edit.path == effectiveSelectedPath,
                      onTap: () => ref
                          .read(studioRightDrawerProvider.notifier)
                          .openPatchFile(patch.id, edit.path),
                    );
                  },
                ),
              ),
            if (edits.length > 1)
              Divider(
                color: tokens.studioDivider.withValues(alpha: 0.72),
                height: 1,
              ),
            if (selectedEdit != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  Spacing.xs,
                  Spacing.md,
                  0,
                ),
                child: _PatchDiffSelectedFileHeader(edit: selectedEdit),
              ),
            Expanded(
              child: RepaintBoundary(
                child: _VirtualizedTextDocumentBody(
                  text: diffText,
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.md,
                    Spacing.sm,
                    Spacing.md,
                    Spacing.lg,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatchReviewActionBar extends ConsumerWidget {
  final ProposedPatchSet patch;

  const _PatchReviewActionBar({required this.patch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    if (patch.isPlanOnly) {
      return _PatchReviewActionStrip(
        children: [
          Text(
            'Plan review',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }
    final canApply =
        patch.edits.isNotEmpty &&
        patch.approvalStatus != PatchApprovalStatus.revisionRequested &&
        patch.applyStatus != PatchApplyStatus.conflict &&
        patch.applyStatus != PatchApplyStatus.applied &&
        patch.applyStatus != PatchApplyStatus.rejected &&
        patch.applyStatus != PatchApplyStatus.revisionRequested;
    final canRestore =
        patch.checkpointId != null &&
        patch.applyStatus == PatchApplyStatus.applied;
    if (canApply) {
      return _PatchReviewActionStrip(
        children: [
          TextButton(
            style: _drawerTextActionStyle(tokens),
            onPressed: () =>
                ref.read(patchProposalProvider.notifier).reject(patch.id),
            child: const Text('Reject'),
          ),
          OutlinedButton(
            style: _drawerSecondaryActionStyle(tokens),
            onPressed: () => _requestRevision(ref),
            child: const Text('Ask for revision'),
          ),
          FilledButton(
            style: _drawerPrimaryActionStyle(tokens),
            onPressed: () => _applyPatch(context, ref),
            child: const Text('Apply changes'),
          ),
        ],
      );
    }
    if (patch.applyStatus == PatchApplyStatus.conflict) {
      return _PatchReviewActionStrip(
        children: [
          OutlinedButton(
            style: _drawerSecondaryActionStyle(tokens),
            onPressed: () => _openConflictFile(ref),
            child: const Text('View current file'),
          ),
          OutlinedButton(
            style: _drawerSecondaryActionStyle(tokens),
            onPressed: () => _requestRefresh(ref),
            child: const Text('Refresh patch'),
          ),
          OutlinedButton(
            style: _drawerSecondaryActionStyle(tokens),
            onPressed: () => _requestRebase(ref),
            child: const Text('Ask Circuit to rebase'),
          ),
          TextButton(
            style: _drawerTextActionStyle(tokens),
            onPressed: () => ref
                .read(patchProposalProvider.notifier)
                .dismissConflict(patch.id),
            child: const Text('Dismiss conflict'),
          ),
        ],
      );
    }
    if (canRestore) {
      return _PatchReviewActionStrip(
        children: [
          Text(
            'Applied',
            style: TextStyle(
              color: tokens.success,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w700,
            ),
          ),
          OutlinedButton(
            style: _drawerSecondaryActionStyle(tokens),
            onPressed: () => _restoreCheckpoint(context, ref),
            child: const Text('Restore checkpoint'),
          ),
        ],
      );
    }
    final label = switch (patch.applyStatus) {
      PatchApplyStatus.restored => 'Checkpoint restored',
      PatchApplyStatus.rejected => 'Rejected',
      PatchApplyStatus.revisionRequested => 'Revision requested',
      PatchApplyStatus.failed => 'Apply failed',
      PatchApplyStatus.applied => 'Applied',
      PatchApplyStatus.conflict => 'Conflict',
      null => 'Review',
    };
    return _PatchReviewActionStrip(
      children: [
        Text(
          label,
          style: TextStyle(
            color: patch.applyStatus == PatchApplyStatus.failed
                ? tokens.error
                : tokens.textMuted,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Future<void> _applyPatch(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(patchProposalProvider.notifier)
        .apply(patch.id);
    if (!context.mounted) return;
    _showPatchSnack(
      context,
      result.applied
          ? result.message ?? 'Applied ${result.changedFiles.length} files.'
          : result.conflictMessage ?? result.message ?? 'Patch not applied.',
    );
  }

  Future<void> _restoreCheckpoint(BuildContext context, WidgetRef ref) async {
    final checkpointId = patch.checkpointId;
    if (checkpointId == null) return;
    final result = await ref
        .read(patchProposalProvider.notifier)
        .restoreCheckpoint(checkpointId);
    if (!context.mounted) return;
    _showPatchSnack(
      context,
      result.status == PatchApplyStatus.restored
          ? result.message ?? 'Checkpoint restored.'
          : result.message ?? 'Checkpoint was not restored.',
    );
  }

  void _requestRevision(WidgetRef ref) {
    const prompt = 'Revise these proposed changes. Change: ';
    ref
        .read(patchProposalProvider.notifier)
        .requestRevision(
          PatchProposalRevisionRequest(patchSetId: patch.id, prompt: prompt),
        );
    ref.read(studioShellProvider.notifier)
      ..setPromptMode(StudioPromptMode.code)
      ..setComposerText(prompt);
  }

  void _requestRebase(WidgetRef ref) {
    final conflict = patch.conflictMessage?.trim();
    final prompt =
        'Refresh these proposed changes against the current files and preserve the accepted plan intent.'
        '${conflict == null || conflict.isEmpty ? '' : ' Resolve: $conflict'}';
    ref
        .read(patchProposalProvider.notifier)
        .requestRevision(
          PatchProposalRevisionRequest(patchSetId: patch.id, prompt: prompt),
        );
    ref.read(studioShellProvider.notifier)
      ..setPromptMode(StudioPromptMode.code)
      ..setComposerText(prompt);
  }

  void _requestRefresh(WidgetRef ref) {
    final conflict = patch.conflictMessage?.trim();
    final prompt =
        'Refresh this patch against the current file contents without expanding scope.'
        '${conflict == null || conflict.isEmpty ? '' : ' Resolve the current conflict: $conflict'}';
    ref
        .read(patchProposalProvider.notifier)
        .requestRevision(
          PatchProposalRevisionRequest(patchSetId: patch.id, prompt: prompt),
        );
    ref.read(studioShellProvider.notifier)
      ..setPromptMode(StudioPromptMode.code)
      ..setComposerText(prompt);
  }

  void _openConflictFile(WidgetRef ref) {
    final path = _primaryConflictPath(patch);
    if (path == null) return;
    ref.read(studioRightDrawerProvider.notifier).openFile(path);
  }
}

class _PatchReviewActionStrip extends ConsumerWidget {
  final List<Widget> children;

  const _PatchReviewActionStrip({required this.children});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      color: tokens.surfacePanel.withValues(alpha: 0.24),
      padding: const EdgeInsets.fromLTRB(Spacing.sm, 7, Spacing.sm, 7),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: Spacing.xs,
        runSpacing: Spacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}

class _PatchDiffFileRow extends ConsumerWidget {
  final ProposedFileEdit edit;
  final bool selected;
  final VoidCallback onTap;

  const _PatchDiffFileRow({
    required this.edit,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final stats = _editReviewStats(edit);
    return Material(
      color: selected
          ? tokens.studioRailSelected.withValues(alpha: 0.45)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: 7,
          ),
          child: Row(
            children: [
              Icon(
                _patchEditIcon(edit.type),
                size: 13,
                color: selected ? tokens.textPrimary : tokens.textMuted,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  edit.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? tokens.textPrimary : tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ),
              if (stats.additions > 0 || stats.deletions > 0)
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '+${stats.additions}',
                        style: TextStyle(color: tokens.success),
                      ),
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: '-${stats.deletions}',
                        style: TextStyle(color: tokens.error),
                      ),
                    ],
                  ),
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatchDiffSelectedFileHeader extends ConsumerWidget {
  final ProposedFileEdit edit;

  const _PatchDiffSelectedFileHeader({required this.edit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Row(
      children: [
        Icon(_patchEditIcon(edit.type), size: 13, color: tokens.textMuted),
        const SizedBox(width: Spacing.xs),
        Expanded(
          child: Text(
            edit.path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.xs,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: tokens.studioControl.withValues(alpha: 0.44),
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Text(
            edit.type.name,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xs,
              height: 1.1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _PatchReviewStats {
  final int additions;
  final int deletions;

  const _PatchReviewStats({required this.additions, required this.deletions});
}

_PatchReviewStats _patchReviewStats(ProposedPatchSet patch) {
  var additions = 0;
  var deletions = 0;
  for (final edit in patch.edits) {
    final stats = _editReviewStats(edit);
    additions += stats.additions;
    deletions += stats.deletions;
  }
  return _PatchReviewStats(additions: additions, deletions: deletions);
}

_PatchReviewStats _editReviewStats(ProposedFileEdit edit) {
  var additions = 0;
  var deletions = 0;
  final diff = edit.unifiedDiff;
  if (diff != null && diff.trim().isNotEmpty) {
    for (final line in diff.split('\n')) {
      if (line.startsWith('+++') || line.startsWith('---')) continue;
      if (line.startsWith('+')) additions++;
      if (line.startsWith('-')) deletions++;
    }
    return _PatchReviewStats(additions: additions, deletions: deletions);
  }
  final before = edit.before;
  final after = edit.after;
  if (before != null && after != null) {
    for (final row in _diffRows(
      _splitDiffLines(before),
      _splitDiffLines(after),
    )) {
      switch (row.type) {
        case _DiffRowType.added:
          additions++;
          break;
        case _DiffRowType.removed:
          deletions++;
          break;
        case _DiffRowType.unchanged:
          break;
      }
    }
  } else if (after != null) {
    additions = _splitDiffLines(after).length;
  } else if (before != null) {
    deletions = _splitDiffLines(before).length;
  }
  return _PatchReviewStats(additions: additions, deletions: deletions);
}

IconData _patchEditIcon(ProposedFileEditType type) {
  return switch (type) {
    ProposedFileEditType.create => Icons.note_add_outlined,
    ProposedFileEditType.modify => Icons.description_outlined,
    ProposedFileEditType.delete => Icons.delete_outline,
  };
}

String _formatFileCount(int count) => '$count ${count == 1 ? 'file' : 'files'}';

String? _primaryConflictPath(ProposedPatchSet patch) {
  final message = patch.conflictMessage?.trim();
  if (message != null && message.isNotEmpty) {
    final match = RegExp(r':\s*([^\n]+)').firstMatch(message);
    final parsed = match?.group(1)?.trim();
    if (parsed != null && parsed.isNotEmpty) return parsed;
  }
  return patch.edits.firstOrNull?.path;
}

void _showPatchSnack(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}

ButtonStyle _drawerPrimaryActionStyle(ThemeTokens tokens) {
  return FilledButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
    visualDensity: VisualDensity.compact,
    textStyle: const TextStyle(
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w600,
      height: 1.0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
  );
}

ButtonStyle _drawerSecondaryActionStyle(ThemeTokens tokens) {
  return OutlinedButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
    visualDensity: VisualDensity.compact,
    foregroundColor: tokens.textSecondary,
    side: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.58)),
    textStyle: const TextStyle(
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w600,
      height: 1.0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
  );
}

ButtonStyle _drawerTextActionStyle(ThemeTokens tokens) {
  return TextButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 0),
    visualDensity: VisualDensity.compact,
    foregroundColor: tokens.textSecondary,
    textStyle: const TextStyle(
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w600,
      height: 1.0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
  );
}

ProposedPatchSet? _patchForDrawer(
  PatchProposalState patchState,
  String? requestedPatchId, {
  StudioThread? thread,
  String? taskId,
  String? selectedPath,
}) {
  final requestedId = requestedPatchId?.trim();
  if (requestedId != null && requestedId.isNotEmpty) {
    if (patchState.active?.id == requestedId) return patchState.active;
    for (final patch in patchState.history) {
      if (patch.id == requestedId) return patch;
    }
  }
  final threadPatch = _latestPatchForThread(
    patchState,
    thread: thread,
    taskId: taskId,
    selectedPath: selectedPath,
  );
  return threadPatch ?? patchState.active;
}

ProposedPatchSet? _latestPatchForThread(
  PatchProposalState patchState, {
  required StudioThread? thread,
  required String? taskId,
  required String? selectedPath,
}) {
  if (thread == null && (taskId == null || taskId.trim().isEmpty)) {
    return null;
  }
  final candidates = <ProposedPatchSet>[];
  void addPatch(ProposedPatchSet? patch) {
    if (patch == null) return;
    if (!_patchBelongsToThread(patch, thread: thread, taskId: taskId)) return;
    candidates.add(patch);
  }

  addPatch(patchState.active);
  for (final patch in patchState.history) {
    addPatch(patch);
  }
  if (candidates.isEmpty) return null;

  candidates.sort((a, b) {
    final priorityCompare =
        _drawerPatchPriority(
          b,
          patchState: patchState,
          selectedPath: selectedPath,
        ).compareTo(
          _drawerPatchPriority(
            a,
            patchState: patchState,
            selectedPath: selectedPath,
          ),
        );
    if (priorityCompare != 0) return priorityCompare;
    return b.createdAt.compareTo(a.createdAt);
  });
  return candidates.first;
}

bool _patchBelongsToThread(
  ProposedPatchSet patch, {
  required StudioThread? thread,
  required String? taskId,
}) {
  final normalizedTaskId = taskId?.trim();
  if (normalizedTaskId != null &&
      normalizedTaskId.isNotEmpty &&
      patch.agentTaskId == normalizedTaskId) {
    return true;
  }
  if (thread == null) return false;
  if (thread.taskId != null &&
      thread.taskId!.trim().isNotEmpty &&
      patch.agentTaskId == thread.taskId) {
    return true;
  }
  final runId = patch.runId?.trim();
  if (runId != null && runId.isNotEmpty) {
    final requestIds = thread.turns.map((turn) => turn.requestId).toSet();
    if (requestIds.contains(runId)) return true;
  }
  final patchIds = <String>{
    for (final turn in thread.turns)
      if (turn.acceptedPlanContext?.patchSetId.trim().isNotEmpty == true)
        turn.acceptedPlanContext!.patchSetId,
    for (final turn in thread.turns)
      for (final event in turn.events)
        if (event.patchSetId?.trim().isNotEmpty == true) event.patchSetId!,
  };
  return patchIds.contains(patch.id);
}

int _drawerPatchPriority(
  ProposedPatchSet patch, {
  required PatchProposalState patchState,
  required String? selectedPath,
}) {
  var priority = 0;
  final requestedPath = selectedPath?.trim();
  if (requestedPath != null &&
      requestedPath.isNotEmpty &&
      patch.edits.any((edit) => edit.path == requestedPath)) {
    priority += 100;
  }
  if (patchState.active?.id == patch.id) priority += 80;
  priority += switch (patch.applyStatus) {
    PatchApplyStatus.conflict => 70,
    PatchApplyStatus.revisionRequested => 65,
    null => 60,
    PatchApplyStatus.applied => 55,
    PatchApplyStatus.failed => 45,
    PatchApplyStatus.restored => 35,
    PatchApplyStatus.rejected => 10,
  };
  if (!patch.isPlanOnly && patch.edits.isNotEmpty) priority += 8;
  return priority;
}

class _GitReviewDrawer extends ConsumerWidget {
  final String? selectedPath;
  final bool selectedStaged;
  final void Function(String path, bool staged) onSelect;

  const _GitReviewDrawer({
    required this.selectedPath,
    required this.selectedStaged,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final git = ref.watch(gitProvider).status;
    final changes = <_ReviewChange>[
      for (final change in git.staged)
        _ReviewChange(change: change, staged: true),
      for (final change in git.unstaged)
        _ReviewChange(change: change, staged: false),
      for (final change in git.untracked)
        _ReviewChange(change: change, staged: false),
    ];
    if (changes.isEmpty) {
      return const _EmptyDrawerState(
        icon: Icons.difference_outlined,
        title: 'No changes',
        detail: 'Repo changes and AI patch reviews appear here.',
      );
    }
    final selected =
        changes
            .where((change) => change.change.path == selectedPath)
            .firstOrNull ??
        changes.first;
    final staged = selectedPath == null ? selected.staged : selectedStaged;
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Repository changes',
                style: TextStyle(
                  color: ref.watch(themeProvider).textSecondary,
                  fontSize: FontSizes.sm,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => ref.read(gitProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        for (final change in changes)
          _GitChangeRow(
            change: change,
            selected: change.change.path == selected.change.path,
            onTap: () => onSelect(change.change.path, change.staged),
          ),
        const SizedBox(height: Spacing.lg),
        _GitReviewNotice(path: selected.change.path),
        const SizedBox(height: Spacing.md),
        FutureBuilder<String>(
          future: ref
              .read(gitProvider.notifier)
              .getDiff(path: selected.change.path, staged: staged),
          builder: (context, snapshot) {
            return _TextDocumentView(
              title: selected.change.path,
              text: snapshot.data ?? 'Loading diff...',
              embedded: true,
            );
          },
        ),
      ],
    );
  }
}

class _ReviewChange {
  final GitFileChange change;
  final bool staged;

  const _ReviewChange({required this.change, required this.staged});
}

class _GitChangeRow extends ConsumerWidget {
  final _ReviewChange change;
  final bool selected;
  final VoidCallback onTap;

  const _GitChangeRow({
    required this.change,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SourceListRow(
      icon: change.staged ? Icons.check_box : Icons.check_box_outline_blank,
      title: change.change.path,
      subtitle:
          '${change.change.type.label}${change.staged ? ' · staged' : ''}',
      selected: selected,
      onTap: onTap,
    );
  }
}

class _GitReviewNotice extends ConsumerWidget {
  final String path;

  const _GitReviewNotice({required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: tokens.studioHover.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.studioDivider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: Spacing.md),
          Flexible(
            child: Text(
              'Review only',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilesDrawer extends ConsumerWidget {
  const _FilesDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fileTree = ref.watch(fileTreeProvider);
    if (fileTree.rootPath == null) {
      return const _EmptyDrawerState(
        icon: Icons.folder_outlined,
        title: 'No project selected',
        detail: 'Choose a project to see files here.',
      );
    }
    final nodes = fileTree.nodes.take(80).toList();
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        for (final node in nodes)
          _SourceListRow(
            icon: node.isDirectory
                ? Icons.folder_outlined
                : Icons.description_outlined,
            title: node.name,
            subtitle: node.path,
            onTap: node.isDirectory
                ? null
                : () => ref
                      .read(studioRightDrawerProvider.notifier)
                      .openFile(node.path),
          ),
      ],
    );
  }
}

class _TerminalDrawer extends ConsumerWidget {
  final AgentTask? task;

  const _TerminalDrawer({this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drawer = ref.watch(studioRightDrawerProvider);
    final tokens = ref.watch(themeProvider);
    final thread = ref.watch(studioThreadProvider).threadForTaskView(task?.id);
    final commands = _commandRunsForThread(
      liveCommands: ref.watch(commandRunProvider).values,
      thread: thread,
      taskId: task?.id,
    )..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final selected = commands
        .where((command) => command.id == drawer.commandRunId)
        .firstOrNull;
    final command = selected ?? commands.firstOrNull;
    if (commands.isEmpty) {
      return const _EmptyDrawerState(
        icon: Icons.terminal_outlined,
        title: 'No command logs',
        detail:
            'Approved verification commands and tool-run output will appear here. Studio does not expose an interactive terminal in the core agent loop.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        Text(
          'Command logs',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        for (final candidate in commands.take(12))
          _SourceListRow(
            icon: Icons.terminal_outlined,
            title: candidate.command,
            subtitle: candidate.status.name,
            selected: candidate.id == command?.id,
            onTap: () => ref
                .read(studioRightDrawerProvider.notifier)
                .openCommand(candidate.id),
          ),
        if (command != null) ...[
          const SizedBox(height: Spacing.md),
          _TextDocumentView(
            title: command.command,
            text: command.combinedOutput.isEmpty
                ? 'No output captured yet.'
                : command.combinedOutput,
            embedded: true,
          ),
        ],
      ],
    );
  }
}

bool _commandBelongsToThread(
  CommandRun command,
  StudioThread? thread,
  String? taskId,
) {
  if (thread == null && taskId == null) return false;
  if (taskId != null && command.taskId == taskId) return true;
  if (thread == null) return false;
  if (command.taskId != null && command.taskId == thread.taskId) return true;
  final turnIds = thread.turns.map((turn) => turn.id).toSet();
  final requestIds = thread.turns.map((turn) => turn.requestId).toSet();
  return command.turnId != null && turnIds.contains(command.turnId) ||
      command.requestId != null && requestIds.contains(command.requestId);
}

List<CommandRun> _commandRunsForThread({
  required Iterable<CommandRun> liveCommands,
  required StudioThread? thread,
  required String? taskId,
}) {
  final commands = <String, CommandRun>{};
  for (final command in liveCommands) {
    if (!_commandBelongsToThread(command, thread, taskId)) continue;
    commands[command.id] = command;
  }
  if (thread != null) {
    for (final command in _persistedCommandRunsForThread(thread)) {
      commands.putIfAbsent(command.id, () => command);
    }
  }
  return commands.values.toList();
}

Iterable<CommandRun> _persistedCommandRunsForThread(StudioThread thread) sync* {
  for (final turn in thread.turns) {
    for (final event in turn.events) {
      if (event.type != StudioTurnEventType.completionSummary) continue;
      if (!event.id.startsWith('command-run-')) continue;
      final command = _commandRunFromTurnEvent(thread, turn, event);
      if (command != null) yield command;
    }
  }
}

CommandRun? _commandRunFromTurnEvent(
  StudioThread thread,
  StudioTurn turn,
  StudioTurnEvent event,
) {
  final detail = event.detail.trim();
  final command = _commandLineFromDetail(detail);
  if (command == null) return null;
  final status = _commandRunStatusFromTitle(event.title);
  final commandRunId = _commandRunIdFromEvent(turn, event);
  return CommandRun(
    id: commandRunId,
    requestId: event.requestId,
    turnId: turn.id,
    taskId: thread.taskId,
    command: command,
    status: status,
    startedAt: event.timestamp,
    endedAt: event.timestamp,
    exitCode: _exitCodeFromDetail(detail),
    stdout: _commandOutputFromDetail(detail),
    events: [
      CommandRunEvent(
        type: CommandRunEventType.started,
        timestamp: event.timestamp,
        text: command,
      ),
      CommandRunEvent(
        type: status == CommandRunStatus.cancelled
            ? CommandRunEventType.cancelled
            : status == CommandRunStatus.timedOut
            ? CommandRunEventType.timedOut
            : CommandRunEventType.exited,
        timestamp: event.timestamp,
        text: event.title,
      ),
    ],
  );
}

String _commandRunIdFromEvent(StudioTurn turn, StudioTurnEvent event) {
  final prefix = 'command-run-${turn.id}-';
  if (event.id.startsWith(prefix) && event.id.length > prefix.length) {
    return event.id.substring(prefix.length);
  }
  return event.id;
}

String? _commandLineFromDetail(String detail) {
  for (final line in detail.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.toLowerCase().startsWith('command:')) {
      final command = trimmed.substring('command:'.length).trim();
      return command.isEmpty ? null : command;
    }
  }
  return null;
}

int? _exitCodeFromDetail(String detail) {
  final match = RegExp(
    r'^Exit code:\s*(-?\d+)$',
    multiLine: true,
  ).firstMatch(detail);
  if (match == null) return null;
  return int.tryParse(match.group(1) ?? '');
}

String _commandOutputFromDetail(String detail) {
  final lines = detail.split('\n');
  final output = lines
      .where((line) {
        final trimmed = line.trimLeft().toLowerCase();
        return !trimmed.startsWith('command:') &&
            !trimmed.startsWith('exit code:');
      })
      .join('\n')
      .trim();
  return output;
}

CommandRunStatus _commandRunStatusFromTitle(String title) {
  final normalized = title.toLowerCase();
  if (normalized.contains('cancel')) return CommandRunStatus.cancelled;
  if (normalized.contains('timeout') || normalized.contains('timed out')) {
    return CommandRunStatus.timedOut;
  }
  if (normalized.contains('blocked')) return CommandRunStatus.blocked;
  if (normalized.contains('failed') || normalized.contains('error')) {
    return CommandRunStatus.failed;
  }
  return CommandRunStatus.succeeded;
}

class _ArtifactsDrawer extends ConsumerWidget {
  final AgentTask? task;

  const _ArtifactsDrawer({this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threadId = ref.watch(
      studioThreadProvider.select(
        (state) => state.threadForTaskView(task?.id)?.id,
      ),
    );
    final artifactView = ref.watch(
      studioSourceArtifactsForThreadProvider(threadId),
    );
    final drawer = ref.watch(studioRightDrawerProvider);
    final artifacts = artifactView.artifacts
        .where(
          (artifact) =>
              artifact.kind == StudioSourceArtifactKind.generatedArtifact,
        )
        .map(GeneratedArtifact.fromSourceArtifact)
        .nonNulls
        .toList(growable: false);
    if (artifacts.isEmpty) {
      return const _EmptyDrawerState(
        icon: Icons.file_present_outlined,
        title: 'No artifacts yet',
        detail:
            'Generated files, spreadsheets, reports, diagrams, and charts appear here.',
      );
    }
    StudioSourceArtifact? sourceFor(GeneratedArtifact artifact) {
      return artifactView.artifacts
          .where((candidate) => candidate.id == 'generated-${artifact.id}')
          .firstOrNull;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      children: [
        for (final artifact in artifacts)
          Builder(
            builder: (context) {
              final source = sourceFor(artifact);
              final selected = source?.id == drawer.selectedArtifactId;
              return _ArtifactDrawerCard(
                artifact: artifact,
                selected: selected,
                onTap: source == null
                    ? null
                    : () {
                        ref
                            .read(studioRightDrawerProvider.notifier)
                            .openArtifact(source);
                      },
                onReview: () {
                  if (artifact.filePath.trim().isEmpty) return;
                  if (_artifactOpensInCodeReview(artifact.kind)) {
                    ref
                        .read(studioRightDrawerProvider.notifier)
                        .openFile(artifact.filePath);
                    return;
                  }
                  if (source != null) {
                    ref
                        .read(studioRightDrawerProvider.notifier)
                        .openArtifact(source);
                  }
                },
              );
            },
          ),
      ],
    );
  }
}

class _ArtifactDrawerCard extends ConsumerWidget {
  final GeneratedArtifact artifact;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback onReview;

  const _ArtifactDrawerCard({
    required this.artifact,
    required this.selected,
    required this.onTap,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.studioCard.withValues(alpha: 0.76),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? tokens.accent.withValues(alpha: 0.38)
                : tokens.studioDivider.withValues(alpha: 0.3),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 10, 9, 8),
                child: Row(
                  children: [
                    Icon(
                      _artifactDrawerIcon(artifact.kind),
                      color: tokens.textMuted,
                      size: 16,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            artifact.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: FontSizes.sm,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _artifactMeta(artifact),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: FontSizes.xxs,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _artifactWorkbenchHint(artifact.kind),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textMuted.withValues(alpha: 0.82),
                              fontSize: FontSizes.xxs,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (artifact.summary.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 0, 11, 9),
                child: Text(
                  artifact.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
                    height: 1.25,
                  ),
                ),
              ),
            _ArtifactDrawerPreview(artifact: artifact),
            if (selected) _ArtifactDrawerDetailGrid(artifact: artifact),
            _ArtifactDrawerActions(artifact: artifact, onReview: onReview),
          ],
        ),
      ),
    );
  }

  IconData _artifactDrawerIcon(GeneratedArtifactKind kind) {
    return switch (kind) {
      GeneratedArtifactKind.excel ||
      GeneratedArtifactKind.csv => Icons.table_chart_outlined,
      GeneratedArtifactKind.json => Icons.data_object_outlined,
      GeneratedArtifactKind.diagram ||
      GeneratedArtifactKind.chart => Icons.account_tree_outlined,
      GeneratedArtifactKind.pdf => Icons.picture_as_pdf_outlined,
      GeneratedArtifactKind.powerPoint => Icons.slideshow_outlined,
      GeneratedArtifactKind.docx => Icons.article_outlined,
      GeneratedArtifactKind.markdown ||
      GeneratedArtifactKind.report => Icons.description_outlined,
    };
  }

  String _artifactMeta(GeneratedArtifact artifact) {
    final parts = <String>[artifact.typeLabel];
    if (artifact.sheetCount > 1) {
      parts.add(switch (artifact.kind) {
        GeneratedArtifactKind.powerPoint => '${artifact.sheetCount} slides',
        GeneratedArtifactKind.docx => '${artifact.sheetCount} sections',
        GeneratedArtifactKind.pdf => '${artifact.sheetCount} pages',
        GeneratedArtifactKind.chart => '${artifact.sheetCount} charts',
        _ => '${artifact.sheetCount} sheets',
      });
    }
    if (artifact.byteSize > 0) parts.add(_formatBytes(artifact.byteSize));
    parts.add(artifact.statusLabel);
    return parts.join(' • ');
  }
}

String _artifactWorkbenchHint(GeneratedArtifactKind kind) {
  return switch (kind) {
    GeneratedArtifactKind.excel =>
      'Workbook artifact for sizing, inventories, and matrices',
    GeneratedArtifactKind.csv => 'Dataset artifact for clean tabular exchange',
    GeneratedArtifactKind.powerPoint =>
      'Presentation artifact for customer-ready decks',
    GeneratedArtifactKind.docx =>
      'Document artifact for reports, briefs, and handoffs',
    GeneratedArtifactKind.pdf => 'Final handoff artifact for fixed review',
    GeneratedArtifactKind.diagram =>
      'Diagram artifact for topology and architecture visuals',
    GeneratedArtifactKind.chart =>
      'Visual artifact for comparison and trend analysis',
    GeneratedArtifactKind.json => 'Structured data artifact for integrations',
    GeneratedArtifactKind.markdown =>
      'Markdown artifact for editable planning and notes',
    GeneratedArtifactKind.report =>
      'Report artifact for structured customer deliverables',
  };
}

bool _artifactOpensInCodeReview(GeneratedArtifactKind kind) {
  return switch (kind) {
    GeneratedArtifactKind.csv ||
    GeneratedArtifactKind.markdown ||
    GeneratedArtifactKind.json ||
    GeneratedArtifactKind.diagram ||
    GeneratedArtifactKind.chart ||
    GeneratedArtifactKind.report => true,
    GeneratedArtifactKind.excel ||
    GeneratedArtifactKind.pdf ||
    GeneratedArtifactKind.powerPoint ||
    GeneratedArtifactKind.docx => false,
  };
}

class _ArtifactDrawerDetailGrid extends ConsumerWidget {
  final GeneratedArtifact artifact;

  const _ArtifactDrawerDetailGrid({required this.artifact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final extension = p.extension(artifact.fileName).replaceFirst('.', '');
    final folder = artifact.filePath.trim().isEmpty
        ? ''
        : p.dirname(artifact.filePath);
    final rows = <(String, String)>[
      ('Type', artifact.typeLabel),
      ('Status', artifact.statusLabel),
      ('Created', _compactDate(artifact.createdAt)),
      if (extension.isNotEmpty) ('Format', extension.toUpperCase()),
      if (artifact.sheetCount > 0)
        (_countLabel(artifact.kind), '${artifact.sheetCount}'),
      if (artifact.requestId != null && artifact.requestId!.trim().isNotEmpty)
        ('Request', artifact.requestId!),
      if (folder.trim().isNotEmpty) ('Folder', folder),
      if (artifact.filePath.trim().isNotEmpty) ('Path', artifact.filePath),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surfacePanel.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 62,
                    child: Text(
                      row.$1,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: FontSizes.xxs,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.$2,
                      maxLines: row.$1 == 'Path' || row.$1 == 'Folder' ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: FontSizes.xxs,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _countLabel(GeneratedArtifactKind kind) {
    return switch (kind) {
      GeneratedArtifactKind.powerPoint => 'Slides',
      GeneratedArtifactKind.docx => 'Sections',
      GeneratedArtifactKind.pdf => 'Pages',
      GeneratedArtifactKind.chart => 'Charts',
      GeneratedArtifactKind.excel => 'Sheets',
      _ => 'Items',
    };
  }

  String _compactDate(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.month}/${local.day}/${local.year} $hour:$minute $suffix';
  }
}

class _ArtifactDrawerPreview extends ConsumerWidget {
  final GeneratedArtifact artifact;

  const _ArtifactDrawerPreview({required this.artifact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    if (artifact.previewRows.isNotEmpty) {
      return _ArtifactStructuredPreview(artifact: artifact);
    }
    if (_isBinaryPreviewOnly(artifact.kind)) {
      return _BinaryArtifactPreview(artifact: artifact);
    }
    if (artifact.filePath.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<String>(
      future: _readArtifactPreview(artifact.filePath),
      builder: (context, snapshot) {
        final text = snapshot.data?.trim() ?? '';
        if (text.isEmpty) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: tokens.surfacePanel.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: tokens.studioDivider.withValues(alpha: 0.22),
            ),
          ),
          child: Text(
            text,
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.xs,
              height: 1.25,
              fontFamily: artifact.kind == GeneratedArtifactKind.json
                  ? EditorDefaults.studioMonospaceFontFamily
                  : null,
            ),
          ),
        );
      },
    );
  }

  bool _isBinaryPreviewOnly(GeneratedArtifactKind kind) {
    return switch (kind) {
      GeneratedArtifactKind.excel ||
      GeneratedArtifactKind.powerPoint ||
      GeneratedArtifactKind.docx ||
      GeneratedArtifactKind.pdf => true,
      _ => false,
    };
  }

  static Future<String> _readArtifactPreview(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return '';
    final bytes = await file
        .openRead(0, 4096)
        .fold<List<int>>(
          <int>[],
          (previous, element) => previous..addAll(element),
        );
    return String.fromCharCodes(
      bytes,
      0,
      bytes.length,
    ).replaceAll('\u0000', '').trim();
  }
}

class _ArtifactStructuredPreview extends ConsumerWidget {
  final GeneratedArtifact artifact;

  const _ArtifactStructuredPreview({required this.artifact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(
        color: tokens.surfacePanel.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
            child: Row(
              children: [
                Icon(
                  _previewIcon(artifact.kind),
                  color: tokens.textMuted,
                  size: 13,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _previewTitle(artifact),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: FontSizes.xxs,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (artifact.sheetCount > 0)
                  Text(
                    _previewCount(artifact),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xxs,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          _ArtifactTablePreview(rows: artifact.previewRows, embedded: true),
        ],
      ),
    );
  }

  IconData _previewIcon(GeneratedArtifactKind kind) {
    return switch (kind) {
      GeneratedArtifactKind.excel ||
      GeneratedArtifactKind.csv => Icons.table_chart_outlined,
      GeneratedArtifactKind.powerPoint => Icons.view_carousel_outlined,
      GeneratedArtifactKind.docx ||
      GeneratedArtifactKind.pdf ||
      GeneratedArtifactKind.markdown ||
      GeneratedArtifactKind.report => Icons.article_outlined,
      GeneratedArtifactKind.diagram ||
      GeneratedArtifactKind.chart => Icons.account_tree_outlined,
      GeneratedArtifactKind.json => Icons.data_object_outlined,
    };
  }

  String _previewTitle(GeneratedArtifact artifact) {
    return switch (artifact.kind) {
      GeneratedArtifactKind.excel => 'Workbook preview',
      GeneratedArtifactKind.csv => 'Dataset preview',
      GeneratedArtifactKind.powerPoint => 'Slide outline',
      GeneratedArtifactKind.docx => 'Report outline',
      GeneratedArtifactKind.pdf => 'PDF outline',
      GeneratedArtifactKind.diagram => 'Diagram structure',
      GeneratedArtifactKind.chart => 'Chart summary',
      GeneratedArtifactKind.json => 'Structured data preview',
      GeneratedArtifactKind.markdown ||
      GeneratedArtifactKind.report => 'Document preview',
    };
  }

  String _previewCount(GeneratedArtifact artifact) {
    return switch (artifact.kind) {
      GeneratedArtifactKind.powerPoint => '${artifact.sheetCount} slides',
      GeneratedArtifactKind.docx => '${artifact.sheetCount} sections',
      GeneratedArtifactKind.pdf => '${artifact.sheetCount} pages',
      GeneratedArtifactKind.chart => '${artifact.sheetCount} charts',
      GeneratedArtifactKind.excel => '${artifact.sheetCount} sheets',
      _ => '${artifact.sheetCount} items',
    };
  }
}

class _BinaryArtifactPreview extends ConsumerWidget {
  final GeneratedArtifact artifact;

  const _BinaryArtifactPreview({required this.artifact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final detail = switch (artifact.kind) {
      GeneratedArtifactKind.powerPoint =>
        artifact.sheetCount > 0
            ? '${artifact.sheetCount} slide deck'
            : 'PowerPoint deck',
      GeneratedArtifactKind.excel =>
        artifact.sheetCount > 0
            ? '${artifact.sheetCount} sheet workbook'
            : 'Excel workbook',
      GeneratedArtifactKind.docx => 'Word document',
      GeneratedArtifactKind.pdf =>
        artifact.sheetCount > 0
            ? '${artifact.sheetCount} page PDF document'
            : 'PDF document',
      _ => artifact.typeLabel,
    };
    final extension = p.extension(artifact.fileName).replaceFirst('.', '');
    final parts = <String>[
      if (extension.isNotEmpty) extension.toUpperCase(),
      if (artifact.byteSize > 0) _formatBytes(artifact.byteSize),
      if (artifact.sheetCount > 0) _binaryCountLabel(artifact),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: tokens.surfacePanel.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            artifact.kind == GeneratedArtifactKind.powerPoint
                ? Icons.slideshow_outlined
                : Icons.insert_drive_file_outlined,
            color: tokens.textMuted,
            size: 15,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$detail ready',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Open to inspect the full document in its native app.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xxs,
                    height: 1.2,
                  ),
                ),
                if (parts.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      for (final part in parts)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.studioControl.withValues(alpha: 0.32),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: tokens.studioDivider.withValues(
                                alpha: 0.18,
                              ),
                            ),
                          ),
                          child: Text(
                            part,
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: FontSizes.xxs,
                              height: 1,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _binaryCountLabel(GeneratedArtifact artifact) {
    return switch (artifact.kind) {
      GeneratedArtifactKind.powerPoint => '${artifact.sheetCount} slides',
      GeneratedArtifactKind.excel => '${artifact.sheetCount} sheets',
      GeneratedArtifactKind.pdf => '${artifact.sheetCount} pages',
      GeneratedArtifactKind.docx => '${artifact.sheetCount} sections',
      _ => '${artifact.sheetCount} items',
    };
  }
}

class _ArtifactTablePreview extends ConsumerWidget {
  final List<List<String>> rows;
  final bool embedded;

  const _ArtifactTablePreview({required this.rows, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final visibleRows = rows.take(6).toList(growable: false);
    final columnCount = visibleRows.fold<int>(
      0,
      (max, row) => row.length > max ? row.length : max,
    );
    final table = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder(
          horizontalInside: BorderSide(
            color: tokens.studioDivider.withValues(alpha: 0.16),
          ),
        ),
        children: [
          for (var rowIndex = 0; rowIndex < visibleRows.length; rowIndex++)
            TableRow(
              decoration: BoxDecoration(
                color: rowIndex == 0
                    ? tokens.studioControl.withValues(alpha: 0.36)
                    : Colors.transparent,
              ),
              children: [
                for (
                  var columnIndex = 0;
                  columnIndex < columnCount;
                  columnIndex++
                )
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Text(
                      columnIndex < visibleRows[rowIndex].length
                          ? visibleRows[rowIndex][columnIndex]
                          : '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: rowIndex == 0
                            ? tokens.textPrimary
                            : tokens.textSecondary,
                        fontSize: FontSizes.xxs,
                        height: 1.18,
                        fontWeight: rowIndex == 0
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
    if (embedded) return table;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(
        color: tokens.surfacePanel.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: table,
    );
  }
}

class _ArtifactDrawerActions extends ConsumerWidget {
  final GeneratedArtifact artifact;
  final VoidCallback onReview;

  const _ArtifactDrawerActions({
    required this.artifact,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final exportTargets = ref
        .read(studioSourceArtifactProvider.notifier)
        .supportedExportTargets(artifact);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.22)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton(
            style: _compactDrawerActionStyle(tokens),
            onPressed: artifact.filePath.isEmpty
                ? null
                : () => launchUrl(Uri.file(artifact.filePath)),
            child: const Text('Open'),
          ),
          TextButton(
            style: _compactDrawerActionStyle(tokens),
            onPressed: artifact.filePath.isEmpty
                ? null
                : () => launchUrl(Uri.file(p.dirname(artifact.filePath))),
            child: const Text('Reveal'),
          ),
          TextButton(
            style: _compactDrawerActionStyle(tokens),
            onPressed: onReview,
            child: const Text('Review'),
          ),
          if (exportTargets.isNotEmpty)
            PopupMenuButton<GeneratedArtifactKind>(
              tooltip: 'Export as',
              color: tokens.studioPanel,
              elevation: 10,
              position: PopupMenuPosition.under,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: tokens.studioDivider.withValues(alpha: 0.6),
                ),
              ),
              onSelected: (kind) async {
                await ref
                    .read(studioSourceArtifactProvider.notifier)
                    .exportGeneratedArtifact(artifact, kind);
              },
              itemBuilder: (context) => [
                for (final kind in exportTargets)
                  PopupMenuItem<GeneratedArtifactKind>(
                    value: kind,
                    height: 32,
                    child: Text(
                      _exportLabel(kind),
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: FontSizes.xs,
                        height: 1.1,
                      ),
                    ),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Text(
                  'Export',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xxs,
                    height: 1,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          StudioChromeIconButton(
            tooltip: 'Copy path',
            onTap: artifact.filePath.isEmpty
                ? null
                : () =>
                      Clipboard.setData(ClipboardData(text: artifact.filePath)),
            icon: Icons.copy,
            width: 26,
            height: 22,
            iconSize: 13,
          ),
        ],
      ),
    );
  }
}

String _exportLabel(GeneratedArtifactKind kind) {
  return switch (kind) {
    GeneratedArtifactKind.excel => 'Excel workbook',
    GeneratedArtifactKind.csv => 'CSV',
    GeneratedArtifactKind.markdown => 'Markdown',
    GeneratedArtifactKind.json => 'JSON',
    GeneratedArtifactKind.pdf => 'PDF report',
    GeneratedArtifactKind.powerPoint => 'PowerPoint deck',
    GeneratedArtifactKind.docx => 'Word report',
    GeneratedArtifactKind.diagram => 'Diagram',
    GeneratedArtifactKind.chart => 'Chart',
    GeneratedArtifactKind.report => 'Report',
  };
}

ButtonStyle _compactDrawerActionStyle(ThemeTokens tokens) {
  return TextButton.styleFrom(
    foregroundColor: tokens.textSecondary,
    disabledForegroundColor: tokens.textMuted.withValues(alpha: 0.38),
    textStyle: const TextStyle(fontSize: FontSizes.xxs, height: 1),
    visualDensity: VisualDensity.compact,
    minimumSize: const Size(0, 24),
    padding: const EdgeInsets.symmetric(horizontal: 7),
  );
}

String _formatBytes(int value) {
  if (value < 1024) return '$value B';
  final kb = value / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
}

class _SourcesDrawer extends ConsumerWidget {
  final AgentTask? task;

  const _SourcesDrawer({this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threadId = ref.watch(
      studioThreadProvider.select(
        (state) => state.threadForTaskView(task?.id)?.id,
      ),
    );
    final artifactView = ref.watch(
      studioSourceArtifactsForThreadProvider(threadId),
    );
    if (artifactView.isEmpty) {
      return const _EmptyDrawerState(
        icon: Icons.travel_explore,
        title: 'No sources yet',
        detail:
            'Context, local previews, files, diffs, and commands appear here.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        for (final artifact in artifactView.artifacts)
          _SourceListRow(
            icon: _sourceIcon(artifact.kind),
            title: artifact.title,
            subtitle: artifact.subtitle,
            onTap: () => ref
                .read(studioRightDrawerProvider.notifier)
                .openArtifact(artifact),
          ),
      ],
    );
  }

  IconData _sourceIcon(StudioSourceArtifactKind kind) {
    return switch (kind) {
      StudioSourceArtifactKind.localUrl ||
      StudioSourceArtifactKind.webSource ||
      StudioSourceArtifactKind.browserComment => Icons.language,
      StudioSourceArtifactKind.file => Icons.description_outlined,
      StudioSourceArtifactKind.generatedArtifact => Icons.file_present_outlined,
      StudioSourceArtifactKind.diff ||
      StudioSourceArtifactKind.gitChange ||
      StudioSourceArtifactKind.gitHunk ||
      StudioSourceArtifactKind.reviewComment ||
      StudioSourceArtifactKind.patch => Icons.difference_outlined,
      StudioSourceArtifactKind.command ||
      StudioSourceArtifactKind.terminalLog ||
      StudioSourceArtifactKind.terminalSession => Icons.terminal_outlined,
      StudioSourceArtifactKind.topology => Icons.account_tree_outlined,
      StudioSourceArtifactKind.sizing => Icons.straighten_outlined,
      StudioSourceArtifactKind.lifecycle => Icons.event_available_outlined,
      StudioSourceArtifactKind.chart => Icons.insert_chart_outlined,
      StudioSourceArtifactKind.businessUseCase => Icons.query_stats_outlined,
      StudioSourceArtifactKind.evidence => Icons.verified_outlined,
      StudioSourceArtifactKind.toolResult => Icons.dataset_linked_outlined,
    };
  }
}

class _ContextDrawer extends ConsumerWidget {
  final AgentTask? task;

  const _ContextDrawer({this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final thread = ref.watch(studioThreadProvider).threadForTaskView(task?.id);
    final pack = task == null || thread != null
        ? ref.watch(contextPackProvider)
        : null;
    final persistedRetrieval = thread?.latestContextRetrieval;
    final retrieval = pack?.retrievalResult ?? persistedRetrieval;
    final canPersistContextPreference =
        ref.watch(fileTreeProvider).rootPath != null;
    ref.watch(contextPreferenceRevisionProvider);
    if (pack == null && retrieval == null) {
      return const _EmptyDrawerState(
        icon: Icons.inventory_2_outlined,
        title: 'No context yet',
        detail:
            'Context details appear here after Circuit builds a task context.',
      );
    }

    final removedIds = pack?.removedItemIds.toSet() ?? const <String>{};
    final included =
        retrieval?.includedCandidates
            .where((candidate) => !removedIds.contains(candidate.id))
            .toList() ??
        const [];
    final omitted = retrieval?.omittedCandidates ?? const [];
    final visibleIds =
        pack?.visibleItems.map((item) => item.id).toSet() ?? const <String>{};
    final visibleItems = pack?.visibleItems ?? const <ContextPackItem>[];
    final removedItems =
        pack?.allItems
            .where((item) => removedIds.contains(item.id))
            .toList(growable: false) ??
        const <ContextPackItem>[];
    final includeNextPaths = canPersistContextPreference
        ? ref
              .read(contextPackProvider.notifier)
              .includeNextTimePathsForCurrentRoot()
        : const <String>{};

    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        Text(
          'Context budget',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        if (pack != null)
          _ContextBudgetCard(pack: pack)
        else
          _ContextBudgetSnapshot(retrieval: retrieval!),
        if (retrieval?.warnings.isNotEmpty == true) ...[
          const SizedBox(height: Spacing.md),
          for (final warning in retrieval!.warnings)
            _ContextWarning(message: warning.message),
        ],
        const SizedBox(height: Spacing.lg),
        _ContextSectionTitle(
          title: 'Included',
          count: included.isEmpty ? visibleItems.length : included.length,
        ),
        const SizedBox(height: Spacing.sm),
        if (included.isEmpty)
          for (final item in visibleItems)
            _ContextItemRow(
              title: item.title,
              subtitle: _contextSubtitle(
                path: item.source,
                reason: item.sourceKind.name,
                tokens: item.estimatedTokens,
              ),
              score: null,
              removable: item.removable,
              onRemove: item.removable && pack != null
                  ? () => ref
                        .read(contextPackProvider.notifier)
                        .removeItem(item.id)
                  : null,
            )
        else
          for (final candidate in included)
            _ContextItemRow(
              title: candidate.title,
              subtitle: _contextSubtitle(
                path: candidate.path,
                reason: candidate.reason,
                tokens: candidate.estimatedTokens,
              ),
              score: candidate.score,
              removable: visibleIds.contains(candidate.id),
              onRemove: visibleIds.contains(candidate.id)
                  ? () => ref
                        .read(contextPackProvider.notifier)
                        .removeItem(candidate.id)
                  : null,
              actionLabel:
                  candidate.path != null &&
                      includeNextPaths.contains(candidate.path)
                  ? 'Remove next'
                  : null,
              onAction:
                  candidate.path != null &&
                      includeNextPaths.contains(candidate.path)
                  ? () => ref
                        .read(contextPackProvider.notifier)
                        .removeIncludeNextTime(candidate.path!)
                  : null,
            ),
        if (removedItems.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          _ContextSectionTitle(
            title: 'Removed from next send',
            count: removedItems.length,
          ),
          const SizedBox(height: Spacing.sm),
          for (final item in removedItems)
            _ContextItemRow(
              title: item.title,
              subtitle: _contextSubtitle(
                path: item.source,
                reason: 'Removed before send',
                tokens: item.estimatedTokens,
              ),
              score: null,
              removable: false,
              muted: true,
              actionLabel: 'Restore',
              onAction: pack == null
                  ? null
                  : () => ref
                        .read(contextPackProvider.notifier)
                        .restoreItem(item.id),
            ),
        ],
        if (omitted.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          _ContextSectionTitle(title: 'Omitted', count: omitted.length),
          const SizedBox(height: Spacing.sm),
          for (final candidate in omitted)
            _ContextItemRow(
              title: candidate.title,
              subtitle: _contextSubtitle(
                path: candidate.path,
                reason: candidate.reason,
                tokens: candidate.estimatedTokens,
              ),
              score: candidate.score,
              removable: false,
              muted: true,
              actionLabel:
                  candidate.path != null &&
                      canPersistContextPreference &&
                      includeNextPaths.contains(candidate.path)
                  ? 'Remove next'
                  : candidate.path != null && canPersistContextPreference
                  ? 'Include next'
                  : null,
              onAction: candidate.path != null && canPersistContextPreference
                  ? includeNextPaths.contains(candidate.path)
                        ? () => ref
                              .read(contextPackProvider.notifier)
                              .removeIncludeNextTime(candidate.path!)
                        : () => ref
                              .read(contextPackProvider.notifier)
                              .includeNextTime(candidate.path!)
                  : null,
            ),
        ],
      ],
    );
  }

  String _contextSubtitle({
    required String? path,
    required String reason,
    required int tokens,
  }) {
    return [
      if (path != null && path.trim().isNotEmpty) path,
      reason,
      '~$tokens tokens',
    ].join(' · ');
  }
}

class _ContextBudgetCard extends ConsumerWidget {
  final ContextPack pack;

  const _ContextBudgetCard({required this.pack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final budget = pack.retrievalResult?.budget;
    final used = pack.estimatedTokens;
    final available = budget?.availableForContext;
    final label = available == null
        ? '~$used tokens'
        : '~$used / ~$available context tokens';
    final percent = available == null || available == 0
        ? 0.0
        : (used / available).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: tokens.studioPanel.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.studioDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.sm,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: percent,
              backgroundColor: tokens.surfaceInset,
              color: percent > 0.92 ? tokens.warning : tokens.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextBudgetSnapshot extends ConsumerWidget {
  final ContextRetrievalResult retrieval;

  const _ContextBudgetSnapshot({required this.retrieval});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final budget = retrieval.budget;
    final label =
        '~${budget.usedTokens} / ~${budget.availableForContext} context tokens';
    final percent = budget.availableForContext == 0
        ? 0.0
        : (budget.usedTokens / budget.availableForContext).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: tokens.studioPanel.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.studioDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label · saved with turn',
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.sm,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: percent,
              backgroundColor: tokens.surfaceInset,
              color: percent > 0.92 ? tokens.warning : tokens.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextSectionTitle extends ConsumerWidget {
  final String title;
  final int count;

  const _ContextSectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          '$count',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ContextWarning extends ConsumerWidget {
  final String message;

  const _ContextWarning({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: tokens.warning),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: tokens.warning, fontSize: FontSizes.xs),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextItemRow extends ConsumerWidget {
  final String title;
  final String subtitle;
  final int? score;
  final bool removable;
  final bool muted;
  final VoidCallback? onRemove;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _ContextItemRow({
    required this.title,
    required this.subtitle,
    required this.score,
    required this.removable,
    this.muted = false,
    this.onRemove,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final color = muted ? tokens.textMuted : tokens.textSecondary;
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.fromLTRB(8, 7, 6, 7),
      decoration: BoxDecoration(
        color: tokens.studioHover.withValues(alpha: muted ? 0.16 : 0.28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.42)),
      ),
      child: Row(
        children: [
          Icon(
            muted ? Icons.remove_circle_outline : Icons.check_circle_outline,
            color: muted ? tokens.textMuted : tokens.success,
            size: 14,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          if (score != null)
            Padding(
              padding: const EdgeInsets.only(left: Spacing.sm),
              child: Text(
                '$score',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (removable)
            StudioChromeIconButton(
              tooltip: 'Remove from next send',
              onTap: onRemove,
              icon: Icons.close,
              width: 22,
              height: 22,
              iconSize: 14,
            ),
          if (actionLabel != null && onAction != null)
            Padding(
              padding: const EdgeInsets.only(left: Spacing.sm),
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: tokens.textSecondary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: 0,
                  ),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                  textStyle: const TextStyle(
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(actionLabel!),
              ),
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
          Text(
            row.value,
            style: TextStyle(
              color: row.accent
                  ? tokens.success.withValues(alpha: 0.92)
                  : tokens.textMuted.withValues(alpha: 0.88),
              fontSize: FontSizes.sm,
              height: 1.1,
              fontWeight: row.accent ? FontWeight.w600 : FontWeight.w500,
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

class _SourceListRow extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool selected;

  const _SourceListRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: selected
                ? tokens.studioControl.withValues(alpha: 0.62)
                : tokens.studioActivityRow.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: tokens.studioDivider.withValues(
                alpha: selected ? 0.72 : 0.42,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, color: tokens.textMuted, size: 13),
              ),
              const SizedBox(width: Spacing.sm),
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
                        fontSize: FontSizes.xs,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: FontSizes.xs,
                        height: 1.22,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextDocumentView extends ConsumerWidget {
  final String title;
  final String text;
  final bool embedded;

  const _TextDocumentView({
    required this.title,
    required this.text,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final view = Container(
      decoration: BoxDecoration(
        color: tokens.surfaceInset.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.68)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.sm,
              Spacing.sm,
              Spacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: tokens.bgDark.withValues(alpha: 0.48),
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Icon(
                    Icons.difference_outlined,
                    color: tokens.textMuted,
                    size: 13,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: FontSizes.xs,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.studioControl.withValues(alpha: 0.44),
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Text(
                    'Read only',
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.xs),
                StudioChromeIconButton(
                  tooltip: 'Copy',
                  onTap: () => Clipboard.setData(ClipboardData(text: text)),
                  icon: Icons.copy,
                  width: 26,
                  height: 24,
                  iconSize: 14,
                ),
              ],
            ),
          ),
          Divider(
            color: tokens.studioDivider.withValues(alpha: 0.72),
            height: 1,
          ),
          Expanded(
            child: RepaintBoundary(
              child: _VirtualizedTextDocumentBody(
                text: text,
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  Spacing.md,
                  Spacing.md,
                  Spacing.lg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (embedded) return SizedBox(height: 280, child: view);
    return Padding(padding: const EdgeInsets.all(Spacing.md), child: view);
  }
}

class _EmptyDrawerState extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _EmptyDrawerState({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                icon,
                color: tokens.textMuted.withValues(alpha: 0.72),
                size: 14,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: FontSizes.xs,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                      height: 1.28,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _resolvePath(String? rootPath, String path) {
  if (p.isAbsolute(path)) return path;
  if (rootPath == null) return path;
  return p.normalize(p.join(rootPath, path));
}
