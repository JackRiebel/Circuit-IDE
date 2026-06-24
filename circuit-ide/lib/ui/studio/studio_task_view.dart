import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/agent_workspace.dart';
import '../../models/accepted_plan_context.dart';
import '../../models/reviewed_edit.dart';
import '../../models/studio_right_drawer.dart';
import '../../models/studio_shell.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_turn.dart';
import '../../models/studio_view_models.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/agent_turn_runtime_provider.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';
import '../chat/chat_message_widget.dart';
import 'studio_message_sender.dart';
import 'studio_plan_prompts.dart' as studio_plan_prompts;
import 'studio_prompt_composer.dart';
import 'studio_right_drawer.dart';

enum _AssistantFeedback { helpful, needsWork }

class StudioTaskView extends ConsumerWidget {
  const StudioTaskView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studio = ref.watch(studioShellProvider);
    final workspace = ref.watch(agentWorkspaceProvider);
    final task = studio.selectedTaskId == null
        ? null
        : workspace.tasks
              .where((candidate) => candidate.id == studio.selectedTaskId)
              .firstOrNull;

    return Row(
      children: [
        Expanded(child: _TaskTranscript(task: task)),
        if (studio.rightProgressPanelVisible) StudioRightDrawer(task: task),
      ],
    );
  }
}

class _TaskTranscript extends ConsumerWidget {
  final AgentTask? task;

  const _TaskTranscript({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threadState = ref.watch(studioThreadProvider);
    final thread = threadState.threadForTaskView(task?.id);
    final patchState = ref.watch(patchProposalProvider);
    final effectiveTaskId = task?.id ?? thread?.taskId;
    final patches = _visiblePatchesForTask(patchState, effectiveTaskId);
    final title = thread?.title ?? task?.goal ?? 'New Circuit task';
    final lifecycle = StudioTaskLifecycleState.fromThread(thread);
    final displayState = TaskDisplayState.fromLifecycle(lifecycle);
    final turns = thread?.turns ?? const <StudioTurn>[];
    final turnWidgets = _buildTurnWidgets(context, ref, turns, patches);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(72, 28, 72, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TranscriptStatusHeader(
                  label: _statusLabel(thread, displayState),
                  active: displayState.isActive,
                ),
                const SizedBox(height: Spacing.lg),
                if (turnWidgets.isEmpty)
                  _EmptyThreadState(title: title)
                else
                  ...turnWidgets,
                if ((thread?.isActive ?? false) &&
                    thread?.status == StudioThreadStatus.streaming)
                  _ChatTranscriptLine(
                    isUser: false,
                    text: (thread?.streamingContent ?? '').isEmpty
                        ? 'Circuit AI is responding...'
                        : thread!.streamingContent,
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 72, Spacing.md),
          child: StudioPromptComposer(
            compact: true,
            taskId: effectiveTaskId,
            hintText: 'Ask for follow-up changes',
            submitTooltip: 'Send follow-up',
            onSubmit: (text) => unawaited(
              sendStudioMessage(
                ref,
                text,
                taskId: effectiveTaskId,
                finishTask: effectiveTaskId != null,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _elapsed(DateTime start) {
    final delta = DateTime.now().difference(start);
    if (delta.inMinutes < 1) return '${delta.inSeconds}s';
    return '${delta.inMinutes}m ${delta.inSeconds.remainder(60)}s';
  }

  String _statusLabel(StudioThread? thread, TaskDisplayState displayState) {
    if (!displayState.isActive) {
      final workedFor = _workedDuration(thread);
      if (workedFor != null && displayState.kind == TaskDisplayKind.done) {
        return 'Worked for $workedFor';
      }
      return displayState.label;
    }
    final startedAt = _activeTurnStartedAt(thread);
    final elapsed = startedAt == null ? '' : ' for ${_elapsed(startedAt)}';
    return '${displayState.label}$elapsed';
  }

  String? _workedDuration(StudioThread? thread) {
    if (thread == null || thread.turns.isEmpty) return null;
    final completedTurns = thread.turns.where(
      (turn) =>
          turn.completedAt != null &&
          !turn.completedAt!.isBefore(turn.createdAt),
    );
    if (completedTurns.isEmpty) return null;
    final latest = completedTurns.reduce(
      (a, b) => a.completedAt!.isAfter(b.completedAt!) ? a : b,
    );
    return _formatDuration(latest.completedAt!.difference(latest.createdAt));
  }

  DateTime? _activeTurnStartedAt(StudioThread? thread) {
    if (thread == null || thread.turns.isEmpty) return null;
    final activeTurns = thread.turns.where(
      (turn) => switch (turn.status) {
        StudioTurnStatus.queued ||
        StudioTurnStatus.buildingContext ||
        StudioTurnStatus.sent ||
        StudioTurnStatus.waitingForModel ||
        StudioTurnStatus.streaming ||
        StudioTurnStatus.toolRunning ||
        StudioTurnStatus.waitingForApproval => true,
        StudioTurnStatus.completed ||
        StudioTurnStatus.failed ||
        StudioTurnStatus.cancelled => false,
      },
    );
    final candidates = activeTurns.isEmpty ? thread.turns : activeTurns;
    return candidates
        .reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b)
        .createdAt;
  }

  String _formatDuration(Duration delta) {
    if (delta.inHours > 0) {
      return '${delta.inHours}h ${delta.inMinutes.remainder(60)}m';
    }
    if (delta.inMinutes > 0) {
      return '${delta.inMinutes}m ${delta.inSeconds.remainder(60)}s';
    }
    return '${delta.inSeconds}s';
  }

  List<Widget> _buildTurnWidgets(
    BuildContext context,
    WidgetRef ref,
    List<StudioTurn> turns,
    List<ProposedPatchSet> patches,
  ) {
    final orderedTurns = turns.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final widgets = <Widget>[];
    for (var i = 0; i < orderedTurns.length; i++) {
      final turn = orderedTurns[i];
      final turnPatch = _patchForTurn(
        patches,
        turn,
        isLatestTurn: i == orderedTurns.length - 1,
      );
      var patchAdded = false;
      widgets.add(_ChatTranscriptLine(isUser: true, text: turn.prompt));
      final events = turn.events.toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      for (final event in events) {
        switch (event.type) {
          case StudioTurnEventType.userMessage:
            break;
          case StudioTurnEventType.context:
            // Routine context details stay in the progress drawer. Keeping them
            // out of chat prevents every request from becoming a stack of bars.
            break;
          case StudioTurnEventType.progress:
            if (turnPatch != null &&
                (event.title == 'Plan ready for review' ||
                    event.title == 'Patch ready')) {
              break;
            }
            break;
          case StudioTurnEventType.tool:
            break;
          case StudioTurnEventType.approvalRequest:
            widgets.add(_StudioTurnApprovalCard(event: event));
          case StudioTurnEventType.assistantMessage:
            if ((event.content ?? '').trim().isNotEmpty) {
              widgets.add(
                _ChatTranscriptLine(isUser: false, text: event.content!),
              );
              if (turnPatch != null && !patchAdded) {
                widgets.add(_PatchSummaryCard(patch: turnPatch));
                patchAdded = true;
              }
            }
          case StudioTurnEventType.error:
            widgets.add(
              _TranscriptEvent(
                icon: Icons.error_outline,
                title: event.title,
                detail: event.detail,
              ),
            );
          case StudioTurnEventType.completionSummary:
            if (_isGenericReadySummary(event)) break;
            widgets.add(
              _TranscriptEvent(
                icon: Icons.check_circle_outline,
                title: event.title,
                detail: event.detail,
              ),
            );
        }
      }
      final hasFinalAssistant = events.any(
        (event) => event.type == StudioTurnEventType.assistantMessage,
      );
      if (!hasFinalAssistant && turn.assistantDraft.trim().isNotEmpty) {
        widgets.add(
          _ChatTranscriptLine(isUser: false, text: turn.assistantDraft),
        );
      }
      if (turnPatch != null && !patchAdded) {
        widgets.add(_PatchSummaryCard(patch: turnPatch));
      }
    }
    return widgets;
  }

  bool _isGenericReadySummary(StudioTurnEvent event) {
    final title = event.title.trim().toLowerCase();
    final detail = event.detail.trim().toLowerCase();
    return title == 'ready for next prompt' &&
        (detail.isEmpty || detail == 'ready for the next prompt.');
  }

  ProposedPatchSet? _patchForTurn(
    List<ProposedPatchSet> patches,
    StudioTurn turn, {
    required bool isLatestTurn,
  }) {
    return patches
            .where((patch) => patch.runId == turn.requestId)
            .firstOrNull ??
        (isLatestTurn
            ? patches.where((patch) => patch.runId == null).firstOrNull
            : null);
  }

  List<ProposedPatchSet> _visiblePatchesForTask(
    PatchProposalState state,
    String? taskId,
  ) {
    final byId = <String, ProposedPatchSet>{};

    void addPatch(ProposedPatchSet? patch) {
      if (patch == null) return;
      if (patch.approvalStatus == PatchApprovalStatus.rejected) return;
      if (patch.agentTaskId != null && patch.agentTaskId != taskId) return;
      byId[patch.id] = patch;
    }

    addPatch(state.active);
    for (final patch in state.history) {
      addPatch(patch);
    }
    return byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }
}

class _TranscriptStatusHeader extends ConsumerWidget {
  final String label;
  final bool active;

  const _TranscriptStatusHeader({required this.label, required this.active});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final showChevron = label.startsWith('Worked for');
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: tokens.textMuted.withValues(alpha: active ? 0.9 : 0.74),
            fontSize: FontSizes.xs,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (showChevron) ...[
          const SizedBox(width: 3),
          Icon(
            Icons.chevron_right,
            size: 14,
            color: tokens.textMuted.withValues(alpha: 0.54),
          ),
        ],
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Container(
            height: 1,
            color: tokens.studioDivider.withValues(alpha: 0.72),
          ),
        ),
      ],
    );
  }
}

class _StudioTurnApprovalCard extends ConsumerWidget {
  final StudioTurnEvent event;

  const _StudioTurnApprovalCard({required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final approvalId = event.approvalId;
    final isPending = event.approvalState == ApprovalRequestState.pending;
    final statusLabel = switch (event.approvalState) {
      ApprovalRequestState.approved => 'Approved',
      ApprovalRequestState.rejected => 'Rejected',
      ApprovalRequestState.expired => 'Expired',
      ApprovalRequestState.pending || null => 'Approval needed',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 660),
        decoration: BoxDecoration(
          color: tokens.studioActivityRow.withValues(alpha: 0.64),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isPending
                ? tokens.warning.withValues(alpha: 0.26)
                : tokens.studioDivider.withValues(alpha: 0.62),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.md,
                Spacing.lg,
                Spacing.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.bgDark.withValues(alpha: 0.54),
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    child: Icon(
                      isPending
                          ? Icons.shield_outlined
                          : Icons.task_alt_outlined,
                      color: isPending ? tokens.warning : tokens.textMuted,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.sm,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isPending)
                    Text(
                      'Review required',
                      style: TextStyle(
                        color: tokens.warning,
                        fontSize: FontSizes.xs,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Text(
                event.toolName == null
                    ? 'Circuit wants approval for a protected action.'
                    : 'Circuit wants to use ${event.toolName!.replaceAll('_', ' ')}.',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.sm,
                ),
                decoration: BoxDecoration(
                  color: tokens.surfaceInset.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(Radii.lg),
                  border: Border.all(
                    color: tokens.studioDivider.withValues(alpha: 0.68),
                  ),
                ),
                child: SelectableText(
                  event.approvalPreview ?? event.detail,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    height: 1.36,
                    fontFamily: EditorDefaults.fallbackFontFamily,
                  ),
                ),
              ),
            ),
            if (event.approvalWarnings.isNotEmpty) ...[
              const SizedBox(height: Spacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final warning in event.approvalWarnings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          warning,
                          style: TextStyle(
                            color: tokens.error,
                            fontSize: FontSizes.xs,
                            height: 1.25,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: Spacing.md),
            Container(
              decoration: BoxDecoration(
                color: tokens.surfacePanel.withValues(alpha: 0.2),
                border: Border(
                  top: BorderSide(
                    color: tokens.studioDivider.withValues(alpha: 0.66),
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.sm,
                Spacing.lg,
                Spacing.sm,
              ),
              child: Wrap(
                alignment: WrapAlignment.end,
                runSpacing: Spacing.sm,
                spacing: Spacing.sm,
                children: [
                  TextButton(
                    onPressed: isPending && approvalId != null
                        ? () => ref
                              .read(agentTurnRuntimeProvider.notifier)
                              .rejectApproval(approvalId)
                        : null,
                    child: const Text('Reject'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isPending && approvalId != null
                        ? () => ref
                              .read(agentTurnRuntimeProvider.notifier)
                              .approveForTurn(approvalId)
                        : null,
                    icon: const Icon(Icons.task_alt_outlined, size: 15),
                    label: const Text('Approve for this turn'),
                  ),
                  FilledButton(
                    onPressed: isPending && approvalId != null
                        ? () => ref
                              .read(agentTurnRuntimeProvider.notifier)
                              .approveOnce(approvalId)
                        : null,
                    child: const Text('Approve once'),
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

class _EmptyThreadState extends ConsumerWidget {
  final String title;

  const _EmptyThreadState({required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: Spacing.xl),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.forum_outlined,
                color: tokens.textMuted.withValues(alpha: 0.72),
                size: 14,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != 'New Circuit task') ...[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: FontSizes.xs,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    title == 'New Circuit task'
                        ? 'Start a new message below.'
                        : 'No saved turns yet. Start a follow-up below.',
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

class _PatchSummaryCard extends ConsumerStatefulWidget {
  final ProposedPatchSet patch;

  const _PatchSummaryCard({required this.patch});

  @override
  ConsumerState<_PatchSummaryCard> createState() => _PatchSummaryCardState();
}

class _PatchSummaryCardState extends ConsumerState<_PatchSummaryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final patch = widget.patch;
    final isPlan = patch.isPlanOnly;
    final isAcceptedPlan =
        isPlan && patch.approvalStatus == PatchApprovalStatus.approved;
    final canApply =
        !isPlan &&
        patch.edits.isNotEmpty &&
        patch.applyStatus != PatchApplyStatus.applied &&
        patch.applyStatus != PatchApplyStatus.rejected;
    final canRestore =
        !isPlan &&
        patch.checkpointId != null &&
        patch.applyStatus == PatchApplyStatus.applied;
    final delta = _patchDelta(patch);
    final title = isPlan
        ? isAcceptedPlan
              ? 'Plan accepted'
              : 'Plan ready'
        : patch.applyStatus == PatchApplyStatus.applied
        ? 'Edited ${patch.fileCount} files'
        : patch.applyStatus == PatchApplyStatus.restored
        ? 'Restored ${patch.changedFiles.length} files'
        : 'Prepared ${patch.fileCount} files';
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 706),
        margin: const EdgeInsets.only(bottom: Spacing.xl),
        decoration: BoxDecoration(
          color: tokens.studioActivityRow.withValues(alpha: 0.66),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: tokens.studioDivider.withValues(alpha: 0.58),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.md,
                Spacing.md,
                Spacing.md,
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.bgDark.withValues(alpha: 0.58),
                      borderRadius: BorderRadius.circular(Radii.lg),
                    ),
                    child: Icon(
                      isPlan
                          ? Icons.alt_route_outlined
                          : Icons.difference_outlined,
                      color: tokens.textMuted,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: FontSizes.sm,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (delta.additions > 0 || delta.deletions > 0) ...[
                          const SizedBox(height: 2),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '+${delta.additions}',
                                  style: TextStyle(color: tokens.success),
                                ),
                                const TextSpan(text: ' '),
                                TextSpan(
                                  text: '-${delta.deletions}',
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
                      ],
                    ),
                  ),
                  if (canApply) ...[
                    const SizedBox(width: Spacing.sm),
                    TextButton(
                      onPressed: () => _rejectPatch(ref),
                      child: const Text('Reject'),
                    ),
                    OutlinedButton(
                      onPressed: () => _revisePatch(ref),
                      child: const Text('Ask for revision'),
                    ),
                    FilledButton(
                      onPressed: () => _applyPatch(ref),
                      child: const Text('Apply changes'),
                    ),
                  ] else ...[
                    if (canRestore)
                      OutlinedButton(
                        onPressed: () => _restoreCheckpoint(ref),
                        child: const Text('Restore checkpoint'),
                      ),
                    const SizedBox(width: Spacing.sm),
                    _PatchCardButton(
                      onPressed: isPlan
                          ? () => setState(() => _expanded = true)
                          : () => _openPatchReview(ref),
                      label: isPlan ? 'View plan' : 'Review',
                    ),
                  ],
                ],
              ),
            ),
            Divider(
              color: tokens.studioDivider.withValues(alpha: 0.78),
              height: 1,
            ),
            for (final file in _patchFiles(patch))
              _PatchFileRow(patch: patch, file: file),
            if (!isPlan && _patchStatusDetail(patch) != null) ...[
              Divider(color: tokens.studioDivider, height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.md,
                  Spacing.lg,
                  Spacing.lg,
                ),
                child: Text(
                  _patchStatusDetail(patch)!,
                  style: TextStyle(
                    color: patch.applyStatus == PatchApplyStatus.conflict
                        ? tokens.warning
                        : tokens.textMuted,
                    fontSize: FontSizes.xs,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            if (!isPlan && _hasPatchTransactionEvidence(patch)) ...[
              Divider(color: tokens.studioDivider, height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.md,
                  Spacing.lg,
                  Spacing.lg,
                ),
                child: _PatchTransactionEvidence(patch: patch),
              ),
            ],
            if (isPlan) ...[
              Divider(color: tokens.studioDivider, height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.md,
                  Spacing.lg,
                  Spacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((patch.comparisonSummary ?? '').trim().isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(Spacing.md),
                        decoration: BoxDecoration(
                          color: tokens.surfacePanel.withValues(alpha: 0.34),
                          borderRadius: BorderRadius.circular(Radii.lg),
                          border: Border.all(
                            color: tokens.studioDivider.withValues(alpha: 0.62),
                          ),
                        ),
                        child: Text(
                          patch.comparisonSummary!.trim(),
                          maxLines: _expanded ? null : 3,
                          overflow: _expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: FontSizes.sm,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: Spacing.md),
                    ],
                    if ((patch.planMarkdown ?? '').trim().isNotEmpty) ...[
                      Row(
                        children: [
                          Text(
                            'Plan preview',
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: FontSizes.xs,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(width: Spacing.sm),
                          Expanded(
                            child: Container(
                              height: 1,
                              color: tokens.studioDivider.withValues(
                                alpha: 0.58,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Spacing.sm),
                      _PlanMarkdownPreview(
                        markdown: patch.planMarkdown!,
                        expanded: _expanded,
                      ),
                    ],
                    if ((patch.planMarkdown ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: Spacing.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: Spacing.sm,
                              vertical: 4,
                            ),
                          ),
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                          icon: Icon(
                            _expanded ? Icons.unfold_less : Icons.unfold_more,
                            size: 15,
                          ),
                          label: Text(
                            _expanded ? 'Collapse plan' : 'Expand plan',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: tokens.surfacePanel.withValues(alpha: 0.22),
                  border: Border(
                    top: BorderSide(
                      color: tokens.studioDivider.withValues(alpha: 0.68),
                    ),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.sm,
                  Spacing.lg,
                  Spacing.sm,
                ),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    TextButton(
                      onPressed: () => ref
                          .read(patchProposalProvider.notifier)
                          .reject(widget.patch.id),
                      child: const Text('Dismiss'),
                    ),
                    OutlinedButton(
                      onPressed: () => _revisePlan(ref),
                      child: const Text('Tell Circuit what to change'),
                    ),
                    if (!isAcceptedPlan)
                      FilledButton(
                        onPressed: () => _implementPlan(ref),
                        child: const Text('Implement this plan'),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _implementPlan(WidgetRef ref) {
    unawaited(
      implementPlanFromStudio(
        ref,
        widget.patch,
        taskId: widget.patch.agentTaskId,
        finishTask: widget.patch.agentTaskId != null,
      ),
    );
  }

  void _revisePlan(WidgetRef ref) {
    final shellNotifier = ref.read(studioShellProvider.notifier);
    ref
        .read(patchProposalProvider.notifier)
        .requestRevision(
          PatchProposalRevisionRequest(
            patchSetId: widget.patch.id,
            prompt: 'Revise this plan. Change: ',
          ),
        );
    shellNotifier.setPlanModeEnabled(true);
    shellNotifier.setComposerText('Revise this plan. Change: ');
  }

  void _openPatchReview(WidgetRef ref) {
    final firstEdit = widget.patch.edits.firstOrNull;
    if (firstEdit != null) {
      ref
          .read(studioRightDrawerProvider.notifier)
          .openPatchFile(widget.patch.id, firstEdit.path);
      return;
    }
    ref
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.diff);
  }

  Future<void> _applyPatch(WidgetRef ref) async {
    final result = await ref
        .read(patchProposalProvider.notifier)
        .apply(widget.patch.id);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          result.applied
              ? result.message ?? 'Applied ${result.changedFiles.length} files.'
              : result.conflictMessage ??
                    result.message ??
                    'Patch not applied.',
        ),
      ),
    );
  }

  Future<void> _restoreCheckpoint(WidgetRef ref) async {
    final checkpointId = widget.patch.checkpointId;
    if (checkpointId == null) return;
    final result = await ref
        .read(patchProposalProvider.notifier)
        .restoreCheckpoint(checkpointId);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          result.status == PatchApplyStatus.restored
              ? result.message ??
                    'Restored ${result.changedFiles.length} files.'
              : result.message ?? 'Checkpoint was not restored.',
        ),
      ),
    );
  }

  void _rejectPatch(WidgetRef ref) {
    ref.read(patchProposalProvider.notifier).reject(widget.patch.id);
  }

  void _revisePatch(WidgetRef ref) {
    final shellNotifier = ref.read(studioShellProvider.notifier);
    ref
        .read(patchProposalProvider.notifier)
        .requestRevision(
          PatchProposalRevisionRequest(
            patchSetId: widget.patch.id,
            prompt: 'Revise these proposed changes. Change: ',
          ),
        );
    shellNotifier.setPromptMode(StudioPromptMode.code);
    shellNotifier.setComposerText('Revise these proposed changes. Change: ');
  }
}

class _PatchCardButton extends ConsumerWidget {
  final VoidCallback? onPressed;
  final String label;

  const _PatchCardButton({required this.onPressed, required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        visualDensity: VisualDensity.compact,
        foregroundColor: tokens.textSecondary,
        side: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.72)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label),
    );
  }
}

String? _patchStatusDetail(ProposedPatchSet patch) {
  return switch (patch.applyStatus) {
    PatchApplyStatus.applied =>
      'Applied successfully${patch.checkpointId == null ? '' : ' · checkpoint ${patch.checkpointId}'}.',
    PatchApplyStatus.restored =>
      'Checkpoint restored${patch.changedFiles.isEmpty ? '' : ' · ${patch.changedFiles.length} files reverted'}.',
    PatchApplyStatus.conflict =>
      patch.conflictMessage ?? 'Patch has a conflict and was not applied.',
    PatchApplyStatus.failed =>
      patch.conflictMessage ?? 'Patch failed and was not applied.',
    PatchApplyStatus.rejected => 'Rejected.',
    null => null,
  };
}

bool _hasPatchTransactionEvidence(ProposedPatchSet patch) {
  return (patch.diffSummary ?? '').trim().isNotEmpty ||
      _runnableVerificationSuggestions(patch).isNotEmpty;
}

class _PatchTransactionEvidence extends ConsumerWidget {
  final ProposedPatchSet patch;

  const _PatchTransactionEvidence({required this.patch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final summary = (patch.diffSummary ?? '').trim();
    final verificationCommands = _runnableVerificationSuggestions(patch);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary.isNotEmpty) ...[
          Text(
            'Change summary',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            summary,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.xs,
              height: 1.35,
            ),
          ),
        ],
        if (verificationCommands.isNotEmpty) ...[
          if (summary.isNotEmpty) const SizedBox(height: Spacing.md),
          Text(
            patch.verificationRequested
                ? 'Verification requested'
                : 'Suggested checks',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (patch.verificationRequested) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              'Run these in a separate Verify turn after reviewing the applied patch.',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: Spacing.xs),
          for (final command in verificationCommands)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                command,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                  fontFamily: 'SF Mono',
                  height: 1.3,
                ),
              ),
            ),
          if (shouldOfferPatchVerification(patch)) ...[
            const SizedBox(height: Spacing.sm),
            FilledButton(
              onPressed: () => _runVerification(ref, patch),
              child: const Text('Run verification'),
            ),
          ],
        ],
      ],
    );
  }

  void _runVerification(WidgetRef ref, ProposedPatchSet patch) {
    final taskId =
        patch.agentTaskId ?? ref.read(studioShellProvider).selectedTaskId;
    final shellNotifier = ref.read(studioShellProvider.notifier);
    shellNotifier.setPlanModeEnabled(false);
    shellNotifier.setPromptMode(StudioPromptMode.ask);
    unawaited(
      sendStudioMessage(
        ref,
        buildPatchVerificationPrompt(patch),
        taskId: taskId,
        finishTask: taskId != null,
      ),
    );
  }
}

class _PlanMarkdownPreview extends ConsumerWidget {
  final String markdown;
  final bool expanded;

  const _PlanMarkdownPreview({required this.markdown, required this.expanded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = expanded
        ? (screenHeight * 0.42).clamp(260.0, 420.0).toDouble()
        : 132.0;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.surfaceInset.withValues(alpha: 0.46),
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(
            color: tokens.studioDivider.withValues(alpha: 0.68),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.sm,
            Spacing.md,
            Spacing.md,
          ),
          child: MarkdownWidget(
            data: markdown,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            config: buildChatMarkdownConfig(tokens),
          ),
        ),
      ),
    );
  }
}

bool shouldOfferPatchVerification(ProposedPatchSet patch) {
  return patch.verificationRequested &&
      patch.applyStatus == PatchApplyStatus.applied &&
      _runnableVerificationSuggestions(patch).isNotEmpty;
}

List<String> _runnableVerificationSuggestions(ProposedPatchSet patch) {
  return patch.verificationSuggestions
      .where(studio_plan_prompts.isRunnableVerificationCommand)
      .toSet()
      .take(5)
      .toList(growable: false);
}

String buildPlanImplementationPrompt(AcceptedPlanContext plan) {
  return studio_plan_prompts.buildPlanImplementationPrompt(plan);
}

String buildPatchVerificationPrompt(ProposedPatchSet patch) {
  return studio_plan_prompts.buildPatchVerificationPrompt(patch);
}

class _PatchFileRow extends ConsumerWidget {
  final ProposedPatchSet patch;
  final _PatchFileSummary file;

  const _PatchFileRow({required this.patch, required this.file});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return InkWell(
      borderRadius: BorderRadius.zero,
      onTap: () {
        if (file.hasDiff) {
          ref
              .read(studioRightDrawerProvider.notifier)
              .openPatchFile(patch.id, file.path);
        } else {
          ref.read(studioRightDrawerProvider.notifier).openFile(file.path);
        }
      },
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: Row(
          children: [
            Icon(
              file.hasDiff
                  ? Icons.description_outlined
                  : Icons.article_outlined,
              color: tokens.textMuted,
              size: 13,
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(
                file.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.xs,
                  height: 1.15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (file.additions > 0 || file.deletions > 0) ...[
              Text(
                '+${file.additions}',
                style: TextStyle(
                  color: tokens.success,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: Spacing.xs),
              Text(
                '-${file.deletions}',
                style: TextStyle(
                  color: tokens.error,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(width: Spacing.sm),
            Icon(Icons.chevron_right, color: tokens.textMuted, size: 15),
          ],
        ),
      ),
    );
  }
}

class _PatchFileSummary {
  final String path;
  final int additions;
  final int deletions;
  final bool hasDiff;

  const _PatchFileSummary({
    required this.path,
    this.additions = 0,
    this.deletions = 0,
    this.hasDiff = false,
  });
}

_PatchFileSummary _patchDelta(ProposedPatchSet patch) {
  final files = _patchFiles(patch);
  return _PatchFileSummary(
    path: '',
    additions: files.fold(0, (total, file) => total + file.additions),
    deletions: files.fold(0, (total, file) => total + file.deletions),
  );
}

List<_PatchFileSummary> _patchFiles(ProposedPatchSet patch) {
  if (patch.edits.isNotEmpty) {
    return [
      for (final edit in patch.edits)
        _PatchFileSummary(
          path: edit.path,
          additions: _lineDelta(edit).additions,
          deletions: _lineDelta(edit).deletions,
          hasDiff: true,
        ),
    ];
  }
  return [
    for (final file in patch.plannedFiles)
      _PatchFileSummary(path: file.split(' — ').first.trim()),
  ];
}

_PatchFileSummary _lineDelta(ProposedFileEdit edit) {
  if ((edit.unifiedDiff ?? '').trim().isNotEmpty) {
    var additions = 0;
    var deletions = 0;
    for (final line in edit.unifiedDiff!.split('\n')) {
      if (line.startsWith('+++') || line.startsWith('---')) continue;
      if (line.startsWith('+')) additions++;
      if (line.startsWith('-')) deletions++;
    }
    return _PatchFileSummary(
      path: edit.path,
      additions: additions,
      deletions: deletions,
    );
  }
  final before = edit.before?.split('\n').length ?? 0;
  final after = edit.after?.split('\n').length ?? 0;
  return _PatchFileSummary(
    path: edit.path,
    additions: after > before ? after - before : after,
    deletions: before > after ? before - after : 0,
  );
}

class _TranscriptEvent extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _TranscriptEvent({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: Spacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                icon,
                color: tokens.textMuted.withValues(alpha: 0.76),
                size: 13,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (detail.trim().isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textMuted.withValues(alpha: 0.82),
                        fontSize: FontSizes.xs,
                        height: 1.24,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatTranscriptLine extends ConsumerWidget {
  final bool isUser;
  final String text;

  const _ChatTranscriptLine({required this.isUser, required this.text});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    if (!isUser) {
      return Align(
        alignment: Alignment.centerLeft,
        child: _AssistantMessageBlock(text: text, tokens: tokens),
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.only(bottom: Spacing.lg),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: tokens.studioBubble,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: FontSizes.sm,
            height: 1.32,
          ),
        ),
      ),
    );
  }
}

class _AssistantMessageBlock extends StatefulWidget {
  final String text;
  final ThemeTokens tokens;

  const _AssistantMessageBlock({required this.text, required this.tokens});

  @override
  State<_AssistantMessageBlock> createState() => _AssistantMessageBlockState();
}

class _AssistantMessageBlockState extends State<_AssistantMessageBlock> {
  _AssistantFeedback? _feedback;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 660),
      margin: const EdgeInsets.only(bottom: Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkdownWidget(
            data: widget.text,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            config: buildChatMarkdownConfig(widget.tokens),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AssistantActionButton(
                tooltip: 'Copy response',
                icon: Icons.copy_outlined,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.text));
                  _showQuietSnack(context, 'Copied response');
                },
              ),
              _AssistantActionButton(
                tooltip: 'Mark helpful',
                icon: Icons.thumb_up_alt_outlined,
                selected: _feedback == _AssistantFeedback.helpful,
                onPressed: () =>
                    _setAssistantFeedback(context, _AssistantFeedback.helpful),
              ),
              _AssistantActionButton(
                tooltip: 'Mark needs work',
                icon: Icons.thumb_down_alt_outlined,
                selected: _feedback == _AssistantFeedback.needsWork,
                onPressed: () => _setAssistantFeedback(
                  context,
                  _AssistantFeedback.needsWork,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _setAssistantFeedback(BuildContext context, _AssistantFeedback next) {
    setState(() => _feedback = next);
    _showQuietSnack(
      context,
      next == _AssistantFeedback.helpful
          ? 'Marked helpful'
          : 'Marked needs work',
    );
  }

  void _showQuietSnack(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1100),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

class _AssistantActionButton extends ConsumerWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  const _AssistantActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: onPressed,
        child: AnimatedContainer(
          duration: AnimationDurations.fast,
          curve: AnimationCurves.smooth,
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? tokens.studioControl.withValues(alpha: 0.74)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Icon(
            icon,
            size: 13,
            color: selected ? tokens.textSecondary : tokens.textMuted,
          ),
        ),
      ),
    );
  }
}
