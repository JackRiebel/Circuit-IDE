import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/agent_workspace.dart';
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
import '../chat/chat_message_widget.dart';
import 'studio_chrome.dart';
import 'studio_message_sender.dart';
import 'studio_prompt_composer.dart';
import 'studio_right_drawer.dart';

class StudioTaskView extends ConsumerWidget {
  const StudioTaskView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studio = ref.watch(studioShellProvider);
    final workspace = ref.watch(agentWorkspaceProvider);
    final task = studio.selectedTaskId == null
        ? workspace.selectedTask
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
    final tokens = ref.watch(themeProvider);
    final threadState = ref.watch(studioThreadProvider);
    final thread =
        threadState.threadForTask(task?.id) ?? threadState.selectedThread;
    final patchState = ref.watch(patchProposalProvider);
    final patches = _visiblePatchesForTask(patchState, task?.id);
    final title = task?.goal ?? thread?.title ?? 'New Circuit task';
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
                Text(
                  _statusLabel(task, displayState),
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Divider(color: tokens.studioDivider.withValues(alpha: 0.82)),
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
            hintText: 'Ask for follow-up changes',
            submitTooltip: 'Send follow-up',
            onSubmit: (text) => unawaited(
              sendStudioMessage(
                ref,
                text,
                taskId: task?.id,
                finishTask: task != null,
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

  String _statusLabel(AgentTask? task, TaskDisplayState displayState) {
    final elapsed = task == null ? '' : ' for ${_elapsed(task.createdAt)}';
    return '${displayState.label}$elapsed';
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
            break;
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
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: tokens.studioPanel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isPending
                ? tokens.warning.withValues(alpha: 0.34)
                : tokens.studioDivider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isPending ? Icons.shield_outlined : Icons.task_alt_outlined,
                  color: isPending ? tokens.warning : tokens.textMuted,
                  size: 16,
                ),
                const SizedBox(width: Spacing.sm),
                Text(
                  statusLabel,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Text(
              event.toolName == null
                  ? 'Circuit wants approval for a protected action.'
                  : 'Circuit wants to use ${event.toolName!.replaceAll('_', ' ')}:',
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
            ),
            const SizedBox(height: Spacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: tokens.surfaceInset,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tokens.studioDivider),
              ),
              child: SelectableText(
                event.approvalPreview ?? event.detail,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.xs,
                  height: 1.45,
                  fontFamily: EditorDefaults.fallbackFontFamily,
                ),
              ),
            ),
            if (event.approvalWarnings.isNotEmpty) ...[
              const SizedBox(height: Spacing.md),
              for (final warning in event.approvalWarnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    warning,
                    style: TextStyle(
                      color: tokens.error,
                      fontSize: FontSizes.xs,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: Spacing.lg),
            Wrap(
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
                  label: const Text('Approve this task'),
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
      child: Container(
        constraints: const BoxConstraints(maxWidth: 660),
        margin: const EdgeInsets.only(bottom: Spacing.xl),
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: tokens.studioPanel.withValues(alpha: 0.52),
          borderRadius: BorderRadius.circular(Radii.xl),
          border: Border.all(color: tokens.studioDivider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != 'New Circuit task') ...[
              Text(
                title,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.sm,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Spacing.xs),
            ],
            Text(
              title == 'New Circuit task'
                  ? 'Start a new message below.'
                  : 'This thread has no saved turns yet. Start a follow-up below.',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.sm,
                height: 1.35,
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
    final delta = _patchDelta(patch);
    final title = isPlan
        ? isAcceptedPlan
              ? 'Plan accepted'
              : 'Plan ready'
        : patch.applyStatus == PatchApplyStatus.applied
        ? 'Edited ${patch.fileCount} files'
        : 'Prepared ${patch.fileCount} files';
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 706),
        margin: const EdgeInsets.only(bottom: Spacing.xl),
        decoration: BoxDecoration(
          color: tokens.studioActivityRow.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(Radii.xl),
          border: Border.all(color: tokens.studioDivider),
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
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.bgDark.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(Radii.lg),
                    ),
                    child: Icon(
                      isPlan
                          ? Icons.alt_route_outlined
                          : Icons.difference_outlined,
                      color: tokens.textMuted,
                      size: 18,
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
                            fontWeight: FontWeight.w700,
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
                  ] else
                    OutlinedButton(
                      onPressed: isPlan
                          ? () => setState(() => _expanded = true)
                          : () => _openPatchReview(ref),
                      child: Text(isPlan ? 'View plan' : 'Review'),
                    ),
                ],
              ),
            ),
            Divider(color: tokens.studioDivider, height: 1),
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
                      Text(
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
                      const SizedBox(height: Spacing.md),
                    ],
                    if ((patch.planMarkdown ?? '').trim().isNotEmpty)
                      _PlanMarkdownPreview(
                        markdown: patch.planMarkdown!,
                        expanded: _expanded,
                      ),
                    if ((patch.planMarkdown ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: Spacing.sm),
                      TextButton.icon(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        icon: Icon(
                          _expanded ? Icons.unfold_less : Icons.unfold_more,
                          size: 15,
                        ),
                        label: Text(
                          _expanded ? 'Collapse plan' : 'Expand plan',
                        ),
                      ),
                    ],
                    const SizedBox(height: Spacing.md),
                    Wrap(
                      spacing: Spacing.sm,
                      runSpacing: Spacing.sm,
                      children: [
                        if (!isAcceptedPlan)
                          FilledButton(
                            onPressed: () => _implementPlan(ref),
                            child: const Text('Implement this plan'),
                          ),
                        OutlinedButton(
                          onPressed: () => _revisePlan(ref),
                          child: const Text('Tell Circuit what to change'),
                        ),
                        TextButton(
                          onPressed: () => ref
                              .read(patchProposalProvider.notifier)
                              .rejectActive(),
                          child: const Text('Dismiss'),
                        ),
                      ],
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
    final shell = ref.read(studioShellProvider);
    final workspace = ref.read(agentWorkspaceProvider);
    final taskId = shell.selectedTaskId ?? workspace.selectedTask?.id;
    final shellNotifier = ref.read(studioShellProvider.notifier);
    ref.read(patchProposalProvider.notifier).markPlanAccepted(widget.patch.id);
    shellNotifier.setPlanModeEnabled(false);
    shellNotifier.setPromptMode(StudioPromptMode.code);
    final prompt = buildPlanImplementationPrompt(widget.patch);
    unawaited(
      sendStudioMessage(
        ref,
        prompt,
        taskId: taskId,
        finishTask: taskId != null,
      ),
    );
  }

  void _revisePlan(WidgetRef ref) {
    final shellNotifier = ref.read(studioShellProvider.notifier);
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

  void _rejectPatch(WidgetRef ref) {
    ref.read(patchProposalProvider.notifier).reject(widget.patch.id);
  }

  void _revisePatch(WidgetRef ref) {
    final shellNotifier = ref.read(studioShellProvider.notifier);
    shellNotifier.setPromptMode(StudioPromptMode.code);
    shellNotifier.setComposerText('Revise these proposed changes. Change: ');
  }
}

String? _patchStatusDetail(ProposedPatchSet patch) {
  return switch (patch.applyStatus) {
    PatchApplyStatus.applied =>
      'Applied successfully${patch.checkpointId == null ? '' : ' · checkpoint ${patch.checkpointId}'}.',
    PatchApplyStatus.conflict =>
      patch.conflictMessage ?? 'Patch has a conflict and was not applied.',
    PatchApplyStatus.failed =>
      patch.conflictMessage ?? 'Patch failed and was not applied.',
    PatchApplyStatus.rejected => 'Rejected.',
    null => null,
  };
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
        ? (screenHeight * 0.45).clamp(280.0, 460.0).toDouble()
        : 180.0;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.surfaceInset.withValues(alpha: 0.56),
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: tokens.studioDivider),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.md),
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

String buildPlanImplementationPrompt(ProposedPatchSet patch) {
  return [
    'Implement this approved plan.',
    'Use the plan below as the source of truth. Inspect files as needed, then propose or apply the appropriate code changes under the current review-first tool policy.',
    if ((patch.planMarkdown ?? '').trim().isNotEmpty)
      'Approved plan:\n${patch.planMarkdown!.trim()}',
    if (patch.plannedFiles.isNotEmpty)
      'Planned files:\n${patch.plannedFiles.map((file) => '- $file').join('\n')}',
  ].join('\n\n');
}

class _PatchFileRow extends ConsumerWidget {
  final ProposedPatchSet patch;
  final _PatchFileSummary file;

  const _PatchFileRow({required this.patch, required this.file});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return InkWell(
      onTap: () {
        if (file.hasDiff) {
          ref
              .read(studioRightDrawerProvider.notifier)
              .openPatchFile(patch.id, file.path);
        } else {
          ref.read(studioRightDrawerProvider.notifier).openFile(file.path);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                file.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.sm,
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
            Icon(Icons.expand_more, color: tokens.textMuted, size: 16),
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
    return StudioActivityRow(icon: icon, title: title, detail: detail);
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
        child: Container(
          constraints: const BoxConstraints(maxWidth: 660),
          margin: const EdgeInsets.only(bottom: Spacing.xl),
          child: MarkdownWidget(
            data: text,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            config: buildChatMarkdownConfig(tokens),
          ),
        ),
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
