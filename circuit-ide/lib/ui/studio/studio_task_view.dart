import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../models/agent_workspace.dart';
import '../../models/accepted_plan_context.dart';
import '../../models/reviewed_edit.dart';
import '../../models/studio_right_drawer.dart';
import '../../models/studio_shell.dart';
import '../../models/studio_source_artifact.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_turn.dart';
import '../../models/studio_view_models.dart';
import '../../models/turn_intent.dart';
import '../../models/generated_artifact.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/agent_turn_runtime_provider.dart';
import '../../state/artifact_launch_provider.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_source_artifact_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';
import '../chat/chat_message_widget.dart';
import 'studio_message_sender.dart';
import 'studio_plan_continuation.dart';
import 'studio_plan_prompts.dart' as studio_plan_prompts;
import 'studio_prompt_composer.dart';
import 'studio_right_drawer.dart';

enum _AssistantFeedback { helpful, needsWork }

class StudioTaskView extends ConsumerWidget {
  const StudioTaskView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shell = ref.watch(
      studioShellProvider.select(
        (state) => (
          selectedTaskId: state.selectedTaskId,
          rightProgressPanelVisible: state.rightProgressPanelVisible,
        ),
      ),
    );
    final workspace = ref.watch(agentWorkspaceProvider);
    final task = shell.selectedTaskId == null
        ? null
        : workspace.tasks
              .where((candidate) => candidate.id == shell.selectedTaskId)
              .firstOrNull;

    return Row(
      children: [
        Expanded(
          child: RepaintBoundary(child: _TaskTranscript(task: task)),
        ),
        if (shell.rightProgressPanelVisible)
          RepaintBoundary(child: StudioRightDrawer(task: task)),
      ],
    );
  }
}

class _TaskTranscript extends ConsumerWidget {
  final AgentTask? task;

  const _TaskTranscript({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transcriptIndex = ref.watch(
      studioThreadProvider.select(
        (state) => _TaskTranscriptIndex.fromState(state, task),
      ),
    );
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(40, 24, 40, 18),
            itemCount: transcriptIndex.turnIds.isEmpty
                ? 2
                : transcriptIndex.turnIds.length + 1,
            itemBuilder: (context, itemIndex) {
              if (itemIndex == 0) {
                return _TranscriptItemFrame(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TranscriptStatusHeader(
                        label: transcriptIndex.statusLabel,
                        active: transcriptIndex.statusActive,
                      ),
                      const SizedBox(height: Spacing.lg),
                    ],
                  ),
                );
              }
              if (transcriptIndex.turnIds.isEmpty) {
                return _TranscriptItemFrame(
                  child: _EmptyThreadState(
                    title: transcriptIndex.title,
                    lastError: transcriptIndex.lastError,
                  ),
                );
              }
              final turnIndex = itemIndex - 1;
              return _TranscriptItemFrame(
                child: _TurnTranscriptItem(
                  turnId: transcriptIndex.turnIds[turnIndex],
                  taskId: transcriptIndex.effectiveTaskId,
                  isLatestTurn: turnIndex == transcriptIndex.turnIds.length - 1,
                  builder: _buildTurnWidget,
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 0, 40, 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 744),
              child: RepaintBoundary(
                child: StudioPromptComposer(
                  compact: true,
                  taskId: transcriptIndex.effectiveTaskId,
                  hintText: 'Ask for follow-up changes',
                  submitTooltip: 'Send follow-up',
                  onSubmit: (text) => unawaited(
                    sendStudioMessage(
                      ref,
                      text,
                      taskId: transcriptIndex.effectiveTaskId,
                      finishTask: transcriptIndex.effectiveTaskId != null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTurnWidget(
    BuildContext context,
    WidgetRef ref,
    StudioTurn turn,
    ProposedPatchSet? turnPatch, {
    required String? taskId,
  }) {
    final widgets = <Widget>[];
    var patchAdded = false;
    var artifactCardsAdded = false;
    final generatedArtifacts = ref.watch(
      studioSourceArtifactProvider.select(
        (state) => state.artifacts
            .where(
              (artifact) =>
                  artifact.kind == StudioSourceArtifactKind.generatedArtifact &&
                  artifact.requestId == turn.requestId,
            )
            .toList(growable: false),
      ),
    );
    final events = turn.events.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final visibleUserMessage = events
        .where(
          (event) =>
              event.type == StudioTurnEventType.userMessage &&
              event.transcriptVisible &&
              (event.content ?? event.detail).trim().isNotEmpty,
        )
        .firstOrNull;
    if (visibleUserMessage != null) {
      widgets.add(
        _ChatTranscriptLine(
          isUser: true,
          text: visibleUserMessage.content ?? visibleUserMessage.detail,
        ),
      );
    } else if (_shouldRenderFallbackPrompt(turn, events)) {
      widgets.add(_ChatTranscriptLine(isUser: true, text: turn.prompt));
    }
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
          final assistantContent = (event.content ?? '').trim();
          final duplicatePlanContent =
              turnPatch != null &&
              _isDuplicatePlanAssistantContent(assistantContent, turnPatch);
          final displayContent = _assistantContentForArtifacts(
            assistantContent,
            generatedArtifacts,
          );
          if (displayContent.isNotEmpty && !duplicatePlanContent) {
            widgets.add(
              _ChatTranscriptLine(isUser: false, text: displayContent),
            );
          }
          if (generatedArtifacts.isNotEmpty && !artifactCardsAdded) {
            widgets.add(_GeneratedArtifactStack(artifacts: generatedArtifacts));
            artifactCardsAdded = true;
          }
          if (turnPatch != null && !patchAdded) {
            widgets.add(_reviewArtifactCard(turnPatch));
            patchAdded = true;
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
      final draftContent = _assistantContentForArtifacts(
        turn.assistantDraft,
        generatedArtifacts,
      );
      if (turn.intent == TurnIntent.plan) {
        widgets.add(_PlanDraftCard(markdown: turn.assistantDraft));
      } else if (draftContent.isNotEmpty) {
        widgets.add(_ChatTranscriptLine(isUser: false, text: draftContent));
      }
    }
    if (generatedArtifacts.isNotEmpty && !artifactCardsAdded) {
      widgets.add(_GeneratedArtifactStack(artifacts: generatedArtifacts));
    }
    if (turnPatch != null && !patchAdded) {
      widgets.add(_reviewArtifactCard(turnPatch));
    } else if (turnPatch == null) {
      final continuation = studioPlanContinuationForTurn(turn);
      if (continuation != null) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: _PlanContinuationCard(
              continuation: continuation,
              onContinue: () => unawaited(
                implementAcceptedPlanFromStudio(
                  ref,
                  continuation.acceptedPlan,
                  taskId: taskId,
                  finishTask: taskId != null,
                  displayText: 'Continuing approved plan',
                ),
              ),
            ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }

  Widget _reviewArtifactCard(ProposedPatchSet patch) {
    return patch.isPlanOnly
        ? _PlanSummaryCard(patch: patch)
        : _PatchSummaryCard(patch: patch);
  }

  String _assistantContentForArtifacts(
    String content,
    List<StudioSourceArtifact> artifacts,
  ) {
    final trimmed = content.trim();
    if (trimmed.isEmpty || artifacts.isEmpty) return trimmed;
    if (!_shouldCollapseArtifactAssistantContent(trimmed)) return trimmed;
    final intro = _artifactResponseIntro(trimmed);
    final generatedArtifacts = artifacts
        .map(GeneratedArtifact.fromSourceArtifact)
        .nonNulls
        .toList(growable: false);
    final artifact = generatedArtifacts.isNotEmpty
        ? generatedArtifacts.first
        : null;
    final fileName = artifact?.fileName ?? artifacts.first.title;
    final summary = generatedArtifacts.length > 1
        ? 'Created ${generatedArtifacts.length} file artifacts.'
        : artifact?.summary ?? 'Created a file artifact.';
    return [
      if (intro.isNotEmpty) intro,
      '$summary See `$fileName` below.',
    ].join('\n\n');
  }

  bool _shouldCollapseArtifactAssistantContent(String content) {
    if (_containsLargeMarkdownTable(content)) return true;
    final lines = content.split('\n');
    final nonEmptyLines = lines.where((line) => line.trim().isNotEmpty).length;
    if (content.length >= 1800 && nonEmptyLines >= 16) return true;
    if (nonEmptyLines >= 34) return true;
    final headingCount = lines
        .where((line) => line.trimLeft().startsWith(RegExp(r'#{2,6}\s')))
        .length;
    final bulletCount = lines
        .where((line) => line.trimLeft().startsWith(RegExp(r'[-*]\s+')))
        .length;
    return content.length >= 1400 && headingCount >= 2 && bulletCount >= 6;
  }

  String _artifactResponseIntro(String content) {
    final introLines = <String>[];
    var nonEmptyLines = 0;
    for (final line in content.split('\n')) {
      final value = line.trim();
      if (value.contains('|') ||
          value.startsWith('```') ||
          value.startsWith(RegExp(r'#{2,6}\s')) ||
          value.startsWith(RegExp(r'[-*]\s+'))) {
        break;
      }
      introLines.add(line);
      if (value.isNotEmpty) nonEmptyLines++;
      if (nonEmptyLines >= 4 || introLines.join('\n').length >= 560) break;
    }
    final intro = introLines.join('\n').trim();
    if (intro.length <= 640) return intro;
    return '${intro.substring(0, 640).trimRight()}...';
  }

  bool _containsLargeMarkdownTable(String content) {
    var tableRows = 0;
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.contains('|') && trimmed.split('|').length >= 3) {
        tableRows++;
        if (tableRows >= 5) return true;
      } else if (tableRows > 0) {
        tableRows = 0;
      }
    }
    return false;
  }

  bool _isDuplicatePlanAssistantContent(
    String assistantContent,
    ProposedPatchSet patch,
  ) {
    if (!patch.isPlanOnly || assistantContent.length < 180) return false;
    final planMarkdown = (patch.planMarkdown ?? '').trim();
    if (planMarkdown.isEmpty) return false;
    final normalizedAssistant = _normalizePlanTextForComparison(
      assistantContent,
    );
    final normalizedPlan = _normalizePlanTextForComparison(planMarkdown);
    if (normalizedAssistant.isEmpty || normalizedPlan.isEmpty) return false;
    if (normalizedAssistant == normalizedPlan) return true;
    final assistantLooksLikePlan =
        RegExp(r'(^|\n)\s{0,4}([-*]|\d+[.)])\s+').hasMatch(assistantContent) ||
        RegExp(r'^\s*#{1,6}\s+', multiLine: true).hasMatch(assistantContent);
    return assistantLooksLikePlan &&
        normalizedAssistant.length > 220 &&
        normalizedPlan.contains(normalizedAssistant);
  }

  String _normalizePlanTextForComparison(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[`*_>#-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _isGenericReadySummary(StudioTurnEvent event) {
    final title = event.title.trim().toLowerCase();
    final detail = event.detail.trim().toLowerCase();
    return title == 'ready for next prompt' &&
        (detail.isEmpty || detail == 'ready for the next prompt.');
  }

  bool _shouldRenderFallbackPrompt(
    StudioTurn turn,
    List<StudioTurnEvent> events,
  ) {
    if (events.any((event) => event.type == StudioTurnEventType.userMessage)) {
      return false;
    }
    if (turn.acceptedPlanState != AcceptedPlanState.none ||
        turn.acceptedPlanContext != null) {
      return false;
    }
    final prompt = turn.prompt.trim();
    if (prompt.isEmpty) return false;
    final lower = prompt.toLowerCase();
    const internalPrefixes = [
      'implement this approved plan',
      'use the accepted plan context',
      'running verification',
      'run verification',
      'verify the applied patch',
    ];
    return !internalPrefixes.any(lower.startsWith);
  }
}

class _TaskTranscriptIndex {
  final String title;
  final String? effectiveTaskId;
  final String statusLabel;
  final bool statusActive;
  final String? lastError;
  final List<String> turnIds;

  const _TaskTranscriptIndex({
    required this.title,
    required this.effectiveTaskId,
    required this.statusLabel,
    required this.statusActive,
    required this.lastError,
    required this.turnIds,
  });

  factory _TaskTranscriptIndex.fromState(
    StudioThreadState state,
    AgentTask? task,
  ) {
    final thread = state.threadForTaskView(task?.id);
    final effectiveTaskId = task?.id ?? thread?.taskId;
    final lifecycle = StudioTaskLifecycleState.fromThread(thread);
    final displayState = TaskDisplayState.fromLifecycle(lifecycle);
    final orderedTurns = (thread?.turns ?? const <StudioTurn>[]).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return _TaskTranscriptIndex(
      title: thread?.title ?? task?.goal ?? 'New Circuit task',
      effectiveTaskId: effectiveTaskId,
      statusLabel: _statusLabel(thread, displayState),
      statusActive: displayState.isActive,
      lastError: thread?.lastError,
      turnIds: [for (final turn in orderedTurns) turn.id],
    );
  }

  static String _elapsed(DateTime start) {
    final delta = DateTime.now().difference(start);
    if (delta.inMinutes < 1) return '${delta.inSeconds}s';
    return '${delta.inMinutes}m ${delta.inSeconds.remainder(60)}s';
  }

  static String _statusLabel(
    StudioThread? thread,
    TaskDisplayState displayState,
  ) {
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

  static String? _workedDuration(StudioThread? thread) {
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

  static DateTime? _activeTurnStartedAt(StudioThread? thread) {
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

  static String _formatDuration(Duration delta) {
    if (delta.inHours > 0) {
      return '${delta.inHours}h ${delta.inMinutes.remainder(60)}m';
    }
    if (delta.inMinutes > 0) {
      return '${delta.inMinutes}m ${delta.inSeconds.remainder(60)}s';
    }
    return '${delta.inSeconds}s';
  }

  @override
  bool operator ==(Object other) {
    return other is _TaskTranscriptIndex &&
        title == other.title &&
        effectiveTaskId == other.effectiveTaskId &&
        statusLabel == other.statusLabel &&
        statusActive == other.statusActive &&
        listEquals(turnIds, other.turnIds);
  }

  @override
  int get hashCode => Object.hash(
    title,
    effectiveTaskId,
    statusLabel,
    statusActive,
    Object.hashAll(turnIds),
  );
}

typedef _TurnTranscriptBuilder =
    Widget Function(
      BuildContext context,
      WidgetRef ref,
      StudioTurn turn,
      ProposedPatchSet? turnPatch, {
      required String? taskId,
    });

class _TurnTranscriptItem extends ConsumerWidget {
  final String turnId;
  final String? taskId;
  final bool isLatestTurn;
  final _TurnTranscriptBuilder builder;

  const _TurnTranscriptItem({
    required this.turnId,
    required this.taskId,
    required this.isLatestTurn,
    required this.builder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final turn = ref.watch(
      studioThreadProvider.select(
        (state) => _turnById(state, turnId, taskId: taskId),
      ),
    );
    if (turn == null) return const SizedBox.shrink();
    final turnPatch = ref.watch(
      patchProposalProvider.select(
        (state) => _patchForTurn(
          _visiblePatchesForTask(state, taskId),
          turn,
          isLatestTurn: isLatestTurn,
        ),
      ),
    );
    return KeyedSubtree(
      key: ValueKey('studio-turn-${turn.id}'),
      child: builder(context, ref, turn, turnPatch, taskId: taskId),
    );
  }

  static StudioTurn? _turnById(
    StudioThreadState state,
    String turnId, {
    required String? taskId,
  }) {
    final thread = state.threadForTaskView(taskId);
    if (thread != null) {
      for (final turn in thread.turns) {
        if (turn.id == turnId) return turn;
      }
    }
    final selectedThread = state.selectedThread;
    if (selectedThread != null && selectedThread.id != thread?.id) {
      for (final turn in selectedThread.turns) {
        if (turn.id == turnId) return turn;
      }
    }
    return null;
  }

  static ProposedPatchSet? _patchForTurn(
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

  static List<ProposedPatchSet> _visiblePatchesForTask(
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

class _TranscriptItemFrame extends StatelessWidget {
  final Widget child;

  const _TranscriptItemFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 744),
        child: child,
      ),
    );
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
            fontWeight: FontWeight.w500,
          ),
        ),
        if (showChevron) ...[
          const SizedBox(width: 3),
          Icon(
            Icons.chevron_right,
            size: 13,
            color: tokens.textMuted.withValues(alpha: 0.54),
          ),
        ],
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Container(
            height: 1,
            color: tokens.studioDivider.withValues(alpha: 0.54),
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
        constraints: const BoxConstraints(maxWidth: 694),
        decoration: BoxDecoration(
          color: tokens.studioActivityRow.withValues(alpha: 0.46),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: isPending
                ? tokens.warning.withValues(alpha: 0.22)
                : tokens.studioDivider.withValues(alpha: 0.44),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 10, 10, 6),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.bgDark.withValues(alpha: 0.38),
                      borderRadius: BorderRadius.circular(7),
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
                        height: 1.15,
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
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              child: Text(
                event.toolName == null
                    ? 'Circuit wants approval for a protected action.'
                    : 'Circuit wants to use ${event.toolName!.replaceAll('_', ' ')}.',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                  height: 1.24,
                ),
              ),
            ),
            const SizedBox(height: 7),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: tokens.surfaceInset.withValues(alpha: 0.54),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: tokens.studioDivider.withValues(alpha: 0.46),
                  ),
                ),
                child: SelectableText(
                  event.approvalPreview ?? event.detail,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    height: 1.36,
                    fontFamily: EditorDefaults.studioMonospaceFontFamily,
                  ),
                ),
              ),
            ),
            if (event.approvalWarnings.isNotEmpty) ...[
              const SizedBox(height: Spacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
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
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: tokens.surfacePanel.withValues(alpha: 0.13),
                border: Border(
                  top: BorderSide(
                    color: tokens.studioDivider.withValues(alpha: 0.42),
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(13, 6, 10, 6),
              child: Wrap(
                alignment: WrapAlignment.end,
                runSpacing: Spacing.sm,
                spacing: Spacing.sm,
                children: [
                  TextButton(
                    style: _patchTextActionStyle(tokens),
                    onPressed: isPending && approvalId != null
                        ? () => ref
                              .read(agentTurnRuntimeProvider.notifier)
                              .rejectApproval(approvalId)
                        : null,
                    child: const Text('Reject'),
                  ),
                  OutlinedButton.icon(
                    style: _patchSecondaryActionStyle(tokens),
                    onPressed: isPending && approvalId != null
                        ? () => ref
                              .read(agentTurnRuntimeProvider.notifier)
                              .approveForTurn(approvalId)
                        : null,
                    icon: const Icon(Icons.task_alt_outlined, size: 14),
                    label: const Text('Approve for this turn'),
                  ),
                  FilledButton(
                    style: _patchPrimaryActionStyle(tokens),
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

class _GeneratedArtifactStack extends StatelessWidget {
  final List<StudioSourceArtifact> artifacts;

  const _GeneratedArtifactStack({required this.artifacts});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final artifact in artifacts) _GeneratedArtifactCard(artifact),
      ],
    );
  }
}

class _GeneratedArtifactCard extends ConsumerWidget {
  final StudioSourceArtifact sourceArtifact;

  const _GeneratedArtifactCard(this.sourceArtifact);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final artifact = GeneratedArtifact.fromSourceArtifact(sourceArtifact);
    final fileName = artifact?.fileName ?? sourceArtifact.title;
    final filePath = artifact?.filePath ?? sourceArtifact.filePath ?? '';
    final summary = artifact?.summary ?? sourceArtifact.subtitle;
    final typeLabel = artifact?.typeLabel ?? 'Artifact';
    final byteSize = artifact == null ? null : _formatArtifactSize(artifact);
    return Container(
      constraints: const BoxConstraints(maxWidth: 760),
      margin: const EdgeInsets.only(bottom: 22),
      decoration: BoxDecoration(
        color: tokens.studioCard.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.34)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 11),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.studioControl.withValues(alpha: 0.54),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _artifactIcon(artifact?.kind),
                    color: tokens.textSecondary,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: FontSizes.md,
                          height: 1.18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [typeLabel, ?byteSize].join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FontSizes.xs,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                _ArtifactCardAction(
                  label: 'Open',
                  onPressed: filePath.isEmpty
                      ? null
                      : () => _launchArtifactPath(context, ref, filePath),
                ),
                _ArtifactCardAction(
                  label: 'Reveal',
                  onPressed: filePath.isEmpty
                      ? null
                      : () => _launchArtifactPath(
                          context,
                          ref,
                          p.dirname(filePath),
                        ),
                ),
                _ArtifactCardAction(
                  label: 'Review',
                  onPressed: () => _reviewArtifact(
                    ref,
                    artifact: artifact,
                    sourceArtifact: sourceArtifact,
                    filePath: filePath,
                  ),
                ),
              ],
            ),
          ),
          if (summary.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 11),
              child: Text(
                summary,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.sm,
                  height: 1.32,
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: tokens.surfacePanel.withValues(alpha: 0.12),
              border: Border(
                top: BorderSide(
                  color: tokens.studioDivider.withValues(alpha: 0.32),
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(14, 7, 10, 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    filePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                      height: 1.2,
                      fontFamily: EditorDefaults.studioMonospaceFontFamily,
                    ),
                  ),
                ),
                TextButton(
                  style: _patchTextActionStyle(tokens),
                  onPressed: filePath.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: filePath));
                          _showArtifactSnack(context, 'Copied artifact path');
                        },
                  child: const Text('Copy path'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _artifactIcon(GeneratedArtifactKind? kind) {
    return switch (kind) {
      GeneratedArtifactKind.excel ||
      GeneratedArtifactKind.csv => Icons.table_chart_outlined,
      GeneratedArtifactKind.json => Icons.data_object_outlined,
      GeneratedArtifactKind.pdf => Icons.picture_as_pdf_outlined,
      GeneratedArtifactKind.powerPoint => Icons.slideshow_outlined,
      GeneratedArtifactKind.docx => Icons.article_outlined,
      GeneratedArtifactKind.diagram ||
      GeneratedArtifactKind.chart => Icons.account_tree_outlined,
      GeneratedArtifactKind.markdown ||
      GeneratedArtifactKind.report ||
      null => Icons.description_outlined,
    };
  }

  static String _formatArtifactSize(GeneratedArtifact artifact) {
    if (artifact.byteSize < 1024) return '${artifact.byteSize} B';
    final kb = artifact.byteSize / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }

  static void _reviewArtifact(
    WidgetRef ref, {
    required GeneratedArtifact? artifact,
    required StudioSourceArtifact sourceArtifact,
    required String filePath,
  }) {
    final drawer = ref.read(studioRightDrawerProvider.notifier);
    if (artifact != null &&
        filePath.trim().isNotEmpty &&
        _artifactOpensInCodeReview(artifact.kind)) {
      drawer.openFile(filePath);
      return;
    }
    drawer.openArtifact(sourceArtifact);
  }

  static bool _artifactOpensInCodeReview(GeneratedArtifactKind kind) {
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

  static Future<void> _launchArtifactPath(
    BuildContext context,
    WidgetRef ref,
    String filePath,
  ) async {
    final uri = Uri.file(filePath);
    final launcher = ref.read(artifactLaunchProvider);
    if (!await launcher(uri)) {
      if (!context.mounted) return;
      _showArtifactSnack(context, 'Could not open artifact');
    }
  }

  static void _showArtifactSnack(BuildContext context, String message) {
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

class _ArtifactCardAction extends ConsumerWidget {
  final String label;
  final VoidCallback? onPressed;

  const _ArtifactCardAction({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return TextButton(
      style: _patchTextActionStyle(tokens),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class _PlanDraftCard extends ConsumerStatefulWidget {
  final String markdown;

  const _PlanDraftCard({required this.markdown});

  @override
  ConsumerState<_PlanDraftCard> createState() => _PlanDraftCardState();
}

class _PlanDraftCardState extends ConsumerState<_PlanDraftCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final content = widget.markdown.trim().isEmpty
        ? '_Drafting plan..._'
        : widget.markdown.trim();
    final title = _draftPlanTitle(content);
    final body = _stripLeadingMarkdownHeading(content).trim();
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const Key('studio-plan-draft-card'),
        constraints: const BoxConstraints(maxWidth: 694),
        margin: const EdgeInsets.only(bottom: 22),
        decoration: BoxDecoration(
          color: tokens.studioCard.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: tokens.studioDivider.withValues(alpha: 0.28),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 14, 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Plan',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.sm,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: tokens.textMuted.withValues(alpha: 0.78),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'Drafting...',
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FontSizes.xs,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      _PlanIconAction(
                        icon: _expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        tooltip: _expanded
                            ? 'Collapse draft plan'
                            : 'Expand draft plan',
                        onPressed: () => setState(() => _expanded = !_expanded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                title,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.xxl,
                  height: 1.12,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _PlanCardBody(
                markdown: body.isEmpty ? content : body,
                expanded: _expanded,
                collapsedMaxHeight: 160,
              ),
            ),
            if (!_expanded)
              Transform.translate(
                offset: const Offset(0, -2),
                child: Center(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 26),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      backgroundColor: tokens.textPrimary,
                      foregroundColor: tokens.bgDark,
                      textStyle: const TextStyle(
                        fontSize: FontSizes.xs,
                        fontWeight: FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    onPressed: () => setState(() => _expanded = true),
                    child: const Text('Expand plan'),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: TextButton(
                    style: _patchTextActionStyle(tokens),
                    onPressed: () => setState(() => _expanded = false),
                    child: const Text('Collapse plan'),
                  ),
                ),
              ),
            Container(
              margin: const EdgeInsets.only(top: 14),
              decoration: BoxDecoration(
                color: tokens.surfacePanel.withValues(alpha: 0.28),
                border: Border(
                  top: BorderSide(
                    color: tokens.studioDivider.withValues(alpha: 0.42),
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: _DraftPlanActionFooter(tokens: tokens),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftPlanActionFooter extends StatelessWidget {
  final ThemeTokens tokens;

  const _DraftPlanActionFooter({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: tokens.textMuted.withValues(alpha: 0.76),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'Implement this plan?',
                style: TextStyle(
                  color: tokens.textPrimary.withValues(alpha: 0.82),
                  fontSize: FontSizes.sm,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              'Not ready yet',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xs,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        _PlanChoiceButton(
          index: '1',
          label: 'Yes, implement this plan',
          enabled: false,
          onPressed: () {},
        ),
        const SizedBox(height: 6),
        _PlanChoiceButton(
          index: null,
          icon: Icons.edit_outlined,
          label: 'No, and tell Circuit what to do differently',
          enabled: false,
          onPressed: () {},
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              style: _patchTextActionStyle(tokens),
              onPressed: null,
              child: const Text('Dismiss'),
            ),
            const SizedBox(width: Spacing.sm),
            FilledButton(
              style: _patchPrimaryActionStyle(tokens),
              onPressed: null,
              child: const Text('Submit'),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Actions unlock when Circuit finishes writing the plan.',
          textAlign: TextAlign.right,
          style: TextStyle(
            color: tokens.textMuted.withValues(alpha: 0.82),
            fontSize: FontSizes.xs,
            height: 1.2,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

String _draftPlanTitle(String markdown) {
  final match = RegExp(
    r'^\s*#{1,2}\s+(.+?)\s*$',
    multiLine: true,
  ).firstMatch(markdown);
  final title = match?.group(1)?.trim();
  return title == null || title.isEmpty ? 'Draft plan' : title;
}

String _stripLeadingMarkdownHeading(String markdown) {
  return markdown.replaceFirst(RegExp(r'^\s*#{1,2}\s+.+?(?:\r?\n)+'), '');
}

class _PlanSummaryCard extends ConsumerStatefulWidget {
  final ProposedPatchSet patch;

  const _PlanSummaryCard({required this.patch});

  @override
  ConsumerState<_PlanSummaryCard> createState() => _PlanSummaryCardState();
}

class _PlanSummaryCardState extends ConsumerState<_PlanSummaryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final patch = widget.patch;
    final targetProgress = ref
        .watch(
          studioThreadProvider.select(
            (state) =>
                _PlanProgressSnapshot.forPatch(state.selectedThread, patch),
          ),
        )
        .targets;
    final accepted = patch.approvalStatus == PatchApprovalStatus.approved;
    final markdown = (patch.planMarkdown ?? patch.comparisonSummary ?? '')
        .trim();
    final title = _planCardTitle(patch, markdown);
    final appliedTargetCount = targetProgress
        .where((target) => target.state == PlanTargetProgressState.applied)
        .length;
    final terminalTargetCount = targetProgress
        .where(
          (target) =>
              target.state == PlanTargetProgressState.applied ||
              target.state == PlanTargetProgressState.skipped,
        )
        .length;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 694),
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(
          color: tokens.studioCard.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: tokens.studioDivider.withValues(alpha: 0.28),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Plan',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.sm,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _PlanIconAction(
                    icon: Icons.content_copy_outlined,
                    tooltip: 'Copy plan',
                    onPressed: markdown.isEmpty
                        ? null
                        : () =>
                              Clipboard.setData(ClipboardData(text: markdown)),
                  ),
                  _PlanIconAction(
                    icon: Icons.thumb_up_alt_outlined,
                    tooltip: 'Useful',
                    onPressed: () {},
                  ),
                  _PlanIconAction(
                    icon: Icons.thumb_down_alt_outlined,
                    tooltip: 'Not useful',
                    onPressed: () {},
                  ),
                  _PlanIconAction(
                    icon: _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    tooltip: _expanded ? 'Collapse plan' : 'Expand plan',
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                title,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.xxl,
                  height: 1.12,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (targetProgress.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      terminalTargetCount == targetProgress.length
                          ? 'Plan progress: all ${targetProgress.length} targets complete'
                          : 'Plan progress: $appliedTargetCount/${targetProgress.length} targets applied',
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: FontSizes.xs,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final target in targetProgress.take(8))
                          _PlanContinuationTargetChip(target: target),
                        if (targetProgress.length > 8)
                          _PlanMoreChip(count: targetProgress.length - 8),
                      ],
                    ),
                  ],
                ),
              )
            else if (patch.effectivePlannedTargets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final target in patch.effectivePlannedTargets.take(8))
                      _PlanTargetChip(target: target),
                    if (patch.effectivePlannedTargets.length > 8)
                      _PlanMoreChip(
                        count: patch.effectivePlannedTargets.length - 8,
                      ),
                  ],
                ),
              ),
            if (markdown.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: _PlanCardBody(markdown: markdown, expanded: _expanded),
              ),
            if (!_expanded && markdown.isNotEmpty)
              Transform.translate(
                offset: const Offset(0, -2),
                child: Center(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 26),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      backgroundColor: tokens.textPrimary,
                      foregroundColor: tokens.bgDark,
                      textStyle: const TextStyle(
                        fontSize: FontSizes.xs,
                        fontWeight: FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    onPressed: () => setState(() => _expanded = true),
                    child: const Text('Expand plan'),
                  ),
                ),
              )
            else if (_expanded && markdown.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: TextButton(
                    style: _patchTextActionStyle(tokens),
                    onPressed: () => setState(() => _expanded = false),
                    child: const Text('Collapse plan'),
                  ),
                ),
              ),
            Container(
              margin: const EdgeInsets.only(top: 14),
              decoration: BoxDecoration(
                color: tokens.surfacePanel.withValues(alpha: 0.28),
                border: Border(
                  top: BorderSide(
                    color: tokens.studioDivider.withValues(alpha: 0.42),
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: accepted
                  ? Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          color: tokens.success.withValues(alpha: 0.92),
                          size: 16,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Plan accepted. Implementation started.',
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: FontSizes.sm,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          style: _patchTextActionStyle(tokens),
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                          child: Text(_expanded ? 'Hide plan' : 'View plan'),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Implement this plan?',
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: FontSizes.sm,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: Spacing.sm),
                        _PlanChoiceButton(
                          index: '1',
                          label: 'Yes, implement this plan',
                          enabled: true,
                          onPressed: () => _implementPlan(ref),
                        ),
                        const SizedBox(height: 6),
                        _PlanChoiceButton(
                          index: null,
                          icon: Icons.edit_outlined,
                          label: 'No, and tell Circuit what to do differently',
                          enabled: true,
                          onPressed: () => _revisePlan(ref),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              style: _patchTextActionStyle(tokens),
                              onPressed: () => ref
                                  .read(patchProposalProvider.notifier)
                                  .reject(widget.patch.id),
                              child: const Text('Dismiss'),
                            ),
                            const SizedBox(width: Spacing.sm),
                            FilledButton(
                              style: _patchPrimaryActionStyle(tokens),
                              onPressed: () => _implementPlan(ref),
                              child: const Text('Submit'),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
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
}

class _PlanTargetChip extends ConsumerWidget {
  final PlannedFileTarget target;

  const _PlanTargetChip({required this.target});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final label = target.displayString.trim().isEmpty
        ? target.path
        : target.displayString;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.studioControl.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.38)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tokens.textSecondary,
          fontSize: FontSizes.xs,
          height: 1.1,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _PlanMoreChip extends ConsumerWidget {
  final int count;

  const _PlanMoreChip({required this.count});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.studioControl.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        '+$count more',
        style: TextStyle(
          color: tokens.textMuted,
          fontSize: FontSizes.xs,
          height: 1.1,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

List<PlanTargetProgress> _planProgressForPatch(
  StudioThread? thread,
  ProposedPatchSet patch,
) {
  if (thread == null) return const [];
  final matchingTurns = thread.turns.where((turn) {
    final context = turn.acceptedPlanContext;
    return context?.patchSetId == patch.id &&
        turn.planTargetProgress.isNotEmpty;
  }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  if (matchingTurns.isEmpty) return const [];
  return matchingTurns.first.planTargetProgress;
}

class _PlanProgressSnapshot {
  final List<PlanTargetProgress> targets;
  final int _fingerprint;

  const _PlanProgressSnapshot(this.targets, this._fingerprint);

  factory _PlanProgressSnapshot.forPatch(
    StudioThread? thread,
    ProposedPatchSet patch,
  ) {
    final targets = _planProgressForPatch(thread, patch);
    return _PlanProgressSnapshot(targets, _planTargetFingerprint(targets));
  }

  @override
  bool operator ==(Object other) {
    return other is _PlanProgressSnapshot && _fingerprint == other._fingerprint;
  }

  @override
  int get hashCode => _fingerprint;
}

int _planTargetFingerprint(List<PlanTargetProgress> targets) {
  return Object.hashAll(
    targets.map(
      (target) =>
          Object.hash(target.path, target.intent, target.state, target.detail),
    ),
  );
}

class _PlanCardBody extends ConsumerWidget {
  final String markdown;
  final bool expanded;
  final double collapsedMaxHeight;

  const _PlanCardBody({
    required this.markdown,
    required this.expanded,
    this.collapsedMaxHeight = 318,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = expanded
        ? (screenHeight * 0.48).clamp(320.0, 520.0).toDouble()
        : collapsedMaxHeight;
    return SizedBox(
      height: expanded ? maxHeight : maxHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              physics: expanded
                  ? const BouncingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              child: MarkdownWidget(
                data: markdown,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                config: buildChatMarkdownConfig(tokens),
              ),
            ),
          ),
          if (!expanded)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 96,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        tokens.studioCard.withValues(alpha: 0),
                        tokens.studioCard.withValues(alpha: 0.96),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanIconAction extends ConsumerWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _PlanIconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 15,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        color: tokens.textMuted,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _PlanChoiceButton extends ConsumerWidget {
  final String? index;
  final IconData? icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  const _PlanChoiceButton({
    required this.index,
    this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Material(
      color: enabled
          ? tokens.studioControl.withValues(alpha: 0.55)
          : tokens.studioControl.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onPressed : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: index == null
                      ? Colors.transparent
                      : tokens.textPrimary,
                  borderRadius: BorderRadius.circular(999),
                  border: index == null
                      ? Border.all(
                          color: tokens.studioDivider.withValues(alpha: 0.6),
                        )
                      : null,
                ),
                child: index == null
                    ? Icon(icon ?? Icons.edit_outlined, size: 12)
                    : Text(
                        index!,
                        style: TextStyle(
                          color: tokens.bgDark,
                          fontSize: FontSizes.xs,
                          height: 1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: enabled ? tokens.textPrimary : tokens.textMuted,
                    fontSize: FontSizes.xs,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyThreadState extends ConsumerWidget {
  final String title;
  final String? lastError;

  const _EmptyThreadState({required this.title, this.lastError});

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
                    _emptyStateDetail,
                    style: TextStyle(
                      color: lastError?.trim().isNotEmpty == true
                          ? tokens.warning
                          : tokens.textMuted,
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

  String get _emptyStateDetail {
    final error = lastError?.trim();
    if (error != null && error.isNotEmpty) return error;
    return title == 'New Circuit task'
        ? 'Start a new message below.'
        : 'No saved turns yet. Start a follow-up below.';
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
        patch.approvalStatus != PatchApprovalStatus.revisionRequested &&
        patch.applyStatus != PatchApplyStatus.conflict &&
        patch.applyStatus != PatchApplyStatus.applied &&
        patch.applyStatus != PatchApplyStatus.rejected &&
        patch.applyStatus != PatchApplyStatus.revisionRequested;
    final canRestore =
        !isPlan &&
        patch.checkpointId != null &&
        patch.applyStatus == PatchApplyStatus.applied;
    final continuation = studioPlanContinuationForPatch(
      patch: patch,
      threads: ref.read(studioThreadProvider).threads,
    );
    final delta = _patchDelta(patch);
    final title = isPlan
        ? isAcceptedPlan
              ? 'Plan accepted'
              : 'Plan ready'
        : patch.applyStatus == PatchApplyStatus.applied
        ? 'Edited ${_formatFileCount(patch.fileCount)}'
        : patch.applyStatus == PatchApplyStatus.restored
        ? 'Restored ${_formatFileCount(patch.changedFiles.length)}'
        : patch.applyStatus == PatchApplyStatus.conflict
        ? 'Patch conflict'
        : patch.applyStatus == PatchApplyStatus.revisionRequested
        ? 'Revision requested'
        : 'Prepared ${_formatFileCount(patch.fileCount)}';
    final statusNote = _patchHeaderStatusNote(patch);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 694),
        margin: const EdgeInsets.only(bottom: 22),
        decoration: BoxDecoration(
          color: tokens.studioCard.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: tokens.studioDivider.withValues(alpha: 0.28),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tokens.surfaceInset.withValues(alpha: 0.66),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Icon(
                          isPlan
                              ? Icons.alt_route_outlined
                              : Icons.difference_outlined,
                          color: tokens.textMuted,
                          size: 13,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: FontSizes.sm,
                                height: 1.18,
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
                            if (statusNote != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                statusNote,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color:
                                      patch.applyStatus ==
                                          PatchApplyStatus.conflict
                                      ? tokens.warning
                                      : tokens.textMuted,
                                  fontSize: FontSizes.xs,
                                  height: 1.25,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: Spacing.sm,
                    runSpacing: 6,
                    children: [
                      if (canApply) ...[
                        TextButton(
                          style: _patchTextActionStyle(tokens),
                          onPressed: () => _rejectPatch(ref),
                          child: const Text('Reject'),
                        ),
                        OutlinedButton(
                          style: _patchSecondaryActionStyle(tokens),
                          onPressed: () =>
                              patch.applyStatus == PatchApplyStatus.conflict
                              ? _rebasePatch(ref)
                              : _revisePatch(ref),
                          child: Text(
                            patch.applyStatus == PatchApplyStatus.conflict
                                ? 'Ask Circuit to rebase'
                                : 'Ask for revision',
                          ),
                        ),
                        FilledButton(
                          style: _patchPrimaryActionStyle(tokens),
                          onPressed: () => _applyPatch(ref),
                          child: const Text('Apply changes'),
                        ),
                      ] else ...[
                        if (!isPlan &&
                            patch.applyStatus == PatchApplyStatus.conflict) ...[
                          OutlinedButton(
                            style: _patchSecondaryActionStyle(tokens),
                            onPressed: () => _viewConflictFile(ref),
                            child: const Text('View current file'),
                          ),
                          OutlinedButton(
                            style: _patchSecondaryActionStyle(tokens),
                            onPressed: () => _refreshPatch(ref),
                            child: const Text('Refresh patch'),
                          ),
                          OutlinedButton(
                            style: _patchSecondaryActionStyle(tokens),
                            onPressed: () => _rebasePatch(ref),
                            child: const Text('Ask Circuit to rebase'),
                          ),
                          TextButton(
                            style: _patchTextActionStyle(tokens),
                            onPressed: () => _dismissConflict(ref),
                            child: const Text('Dismiss conflict'),
                          ),
                        ],
                        if (canRestore)
                          OutlinedButton(
                            style: _patchSecondaryActionStyle(tokens),
                            onPressed: () => _restoreCheckpoint(ref),
                            child: const Text('Restore checkpoint'),
                          ),
                        _PatchCardButton(
                          onPressed: isPlan
                              ? () => setState(() => _expanded = true)
                              : () => _openPatchReview(ref),
                          label: isPlan ? 'View plan' : 'Review',
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Divider(
              color: tokens.studioDivider.withValues(alpha: 0.34),
              height: 1,
            ),
            for (final file in _patchFiles(patch))
              _PatchFileRow(patch: patch, file: file),
            if (!isPlan && _patchStatusDetail(patch) != null) ...[
              Divider(
                color: tokens.studioDivider.withValues(alpha: 0.34),
                height: 1,
              ),
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
              Divider(
                color: tokens.studioDivider.withValues(alpha: 0.34),
                height: 1,
              ),
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
            if (continuation != null) ...[
              Divider(
                color: tokens.studioDivider.withValues(alpha: 0.34),
                height: 1,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.md,
                  Spacing.lg,
                  Spacing.lg,
                ),
                child: _PlanContinuationCard(
                  continuation: continuation,
                  onContinue: () => _continueNextPlanBatch(ref, continuation),
                ),
              ),
            ],
            if (isPlan) ...[
              Divider(
                color: tokens.studioDivider.withValues(alpha: 0.34),
                height: 1,
              ),
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
                          style: _patchTextActionStyle(tokens),
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
                  7,
                  Spacing.lg,
                  7,
                ),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    TextButton(
                      style: _patchTextActionStyle(tokens),
                      onPressed: () => ref
                          .read(patchProposalProvider.notifier)
                          .reject(widget.patch.id),
                      child: const Text('Dismiss'),
                    ),
                    OutlinedButton(
                      style: _patchSecondaryActionStyle(tokens),
                      onPressed: () => _revisePlan(ref),
                      child: const Text('Tell Circuit what to change'),
                    ),
                    if (!isAcceptedPlan)
                      FilledButton(
                        style: _patchPrimaryActionStyle(tokens),
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

  void _continueNextPlanBatch(
    WidgetRef ref,
    StudioPlanContinuationSummary continuation,
  ) {
    unawaited(
      implementPlanFromStudio(
        ref,
        widget.patch,
        taskId: widget.patch.agentTaskId,
        finishTask: widget.patch.agentTaskId != null,
        acceptedPlanOverride: continuation.acceptedPlan,
        displayText: 'Continuing approved plan',
      ),
    );
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

  void _rebasePatch(WidgetRef ref) {
    final shellNotifier = ref.read(studioShellProvider.notifier);
    final conflict = widget.patch.conflictMessage?.trim();
    final prompt =
        'Refresh these proposed changes against the current files and preserve the accepted plan intent.'
        '${conflict == null || conflict.isEmpty ? '' : ' Resolve: $conflict'}';
    ref
        .read(patchProposalProvider.notifier)
        .requestRevision(
          PatchProposalRevisionRequest(
            patchSetId: widget.patch.id,
            prompt: prompt,
          ),
        );
    shellNotifier.setPromptMode(StudioPromptMode.code);
    shellNotifier.setComposerText(prompt);
  }

  void _refreshPatch(WidgetRef ref) {
    final shellNotifier = ref.read(studioShellProvider.notifier);
    final conflict = widget.patch.conflictMessage?.trim();
    final prompt =
        'Refresh this patch against the current file contents without expanding scope.'
        '${conflict == null || conflict.isEmpty ? '' : ' Resolve the current conflict: $conflict'}';
    ref
        .read(patchProposalProvider.notifier)
        .requestRevision(
          PatchProposalRevisionRequest(
            patchSetId: widget.patch.id,
            prompt: prompt,
          ),
        );
    shellNotifier.setPromptMode(StudioPromptMode.code);
    shellNotifier.setComposerText(prompt);
  }

  void _viewConflictFile(WidgetRef ref) {
    final path = _primaryConflictPath(widget.patch);
    if (path == null) return;
    ref.read(studioRightDrawerProvider.notifier).openFile(path);
  }

  void _dismissConflict(WidgetRef ref) {
    ref.read(patchProposalProvider.notifier).dismissConflict(widget.patch.id);
  }
}

class _PlanContinuationCard extends ConsumerWidget {
  final StudioPlanContinuationSummary continuation;
  final VoidCallback onContinue;

  const _PlanContinuationCard({
    required this.continuation,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final remainingTargets = continuation.remainingTargets.take(4).toList();
    final hiddenCount =
        continuation.remainingTargets.length - remainingTargets.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: tokens.surfacePanel.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.48)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Next batch available',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: FontSizes.xs,
              height: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            'Plan progress: ${continuation.appliedCount}/${continuation.totalCount} targets applied. ${continuation.summaryLabel}.',
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.xs,
              height: 1.35,
            ),
          ),
          if (remainingTargets.isNotEmpty) ...[
            const SizedBox(height: Spacing.xs),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final target in remainingTargets)
                  _PlanContinuationTargetChip(target: target),
                if (hiddenCount > 0) _PlanMoreChip(count: hiddenCount),
              ],
            ),
          ],
          const SizedBox(height: Spacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              style: _patchPrimaryActionStyle(tokens),
              onPressed: onContinue,
              child: const Text('Continue next batch'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanContinuationTargetChip extends ConsumerWidget {
  final PlanTargetProgress target;

  const _PlanContinuationTargetChip({required this.target});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final status = _planTargetStatusLabel(target.state);
    final statusColor = switch (target.state) {
      PlanTargetProgressState.conflict => tokens.warning,
      PlanTargetProgressState.blocked => tokens.error,
      PlanTargetProgressState.proposed => tokens.textSecondary,
      PlanTargetProgressState.pending => tokens.textMuted,
      PlanTargetProgressState.applied => tokens.success,
      PlanTargetProgressState.skipped => tokens.textMuted,
    };
    return Container(
      constraints: const BoxConstraints(maxWidth: 236),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.studioControl.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            status,
            style: TextStyle(
              color: statusColor,
              fontSize: FontSizes.xs,
              height: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              target.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                height: 1.1,
                fontFamily: EditorDefaults.studioMonospaceFontFamily,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _planTargetStatusLabel(PlanTargetProgressState state) {
  return switch (state) {
    PlanTargetProgressState.pending => 'Pending',
    PlanTargetProgressState.proposed => 'Proposed',
    PlanTargetProgressState.applied => 'Applied',
    PlanTargetProgressState.conflict => 'Conflict',
    PlanTargetProgressState.blocked => 'Blocked',
    PlanTargetProgressState.skipped => 'Skipped',
  };
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
        minimumSize: const Size(0, 24),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        visualDensity: VisualDensity.compact,
        foregroundColor: tokens.textSecondary,
        side: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.56)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: const TextStyle(
          fontSize: FontSizes.xs,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(label),
    );
  }
}

ButtonStyle _patchPrimaryActionStyle(ThemeTokens tokens) {
  return FilledButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
    visualDensity: VisualDensity.compact,
    textStyle: const TextStyle(
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w600,
      height: 1.0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
  );
}

ButtonStyle _patchSecondaryActionStyle(ThemeTokens tokens) {
  return OutlinedButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
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

ButtonStyle _patchTextActionStyle(ThemeTokens tokens) {
  return TextButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
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

String? _patchStatusDetail(ProposedPatchSet patch) {
  return switch (patch.applyStatus) {
    PatchApplyStatus.applied =>
      'Applied successfully${patch.checkpointId == null ? '' : ' · checkpoint ${patch.checkpointId}'}.',
    PatchApplyStatus.restored =>
      'Checkpoint restored${patch.changedFiles.isEmpty ? '' : ' · ${_formatFileCount(patch.changedFiles.length)} reverted'}.',
    PatchApplyStatus.conflict =>
      '${patch.conflictMessage ?? 'Patch has a conflict and was not applied.'} Ask Circuit to rebase the proposal or revise it before applying again.',
    PatchApplyStatus.failed =>
      patch.conflictMessage ?? 'Patch failed and was not applied.',
    PatchApplyStatus.rejected => 'Rejected.',
    PatchApplyStatus.revisionRequested =>
      'Revision requested. Circuit will use the current files and patch context to prepare an updated proposal.',
    null => null,
  };
}

String? _patchHeaderStatusNote(ProposedPatchSet patch) {
  return switch (patch.applyStatus) {
    PatchApplyStatus.conflict =>
      'Needs rebase before apply. Review the current file or ask Circuit to rebase.',
    PatchApplyStatus.revisionRequested =>
      'Revision requested. Circuit will prepare an updated proposal.',
    PatchApplyStatus.restored => 'Checkpoint restored.',
    PatchApplyStatus.failed => 'Apply failed. Review the message below.',
    PatchApplyStatus.rejected => 'Rejected.',
    PatchApplyStatus.applied || null => null,
  };
}

String? _primaryConflictPath(ProposedPatchSet patch) {
  final message = patch.conflictMessage?.trim();
  if (message != null && message.isNotEmpty) {
    final match = RegExp(r':\s*([^\n]+)').firstMatch(message);
    final parsed = match?.group(1)?.trim();
    if (parsed != null && parsed.isNotEmpty) return parsed;
  }
  return patch.edits.firstOrNull?.path;
}

String _formatFileCount(int count) => '$count ${count == 1 ? 'file' : 'files'}';

String _planCardTitle(ProposedPatchSet patch, String markdown) {
  final title = patch.title.trim();
  if (title.isNotEmpty && title.toLowerCase() != 'plan') return title;
  final heading = RegExp(
    r'^\s{0,3}#{1,3}\s+(.+?)\s*$',
    multiLine: true,
  ).firstMatch(markdown)?.group(1);
  if (heading != null && heading.trim().isNotEmpty) {
    return heading.trim();
  }
  return 'Implementation Plan';
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
    final verificationSnapshot = ref.watch(
      studioThreadProvider.select(
        (state) =>
            _PatchVerificationSnapshot.forPatch(state.selectedThread, patch),
      ),
    );
    final verificationStatus = verificationSnapshot.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary.isNotEmpty) ...[
          Text(
            'Change summary',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w600,
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
              fontWeight: FontWeight.w600,
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
                  fontFamily: EditorDefaults.studioMonospaceFontFamily,
                  height: 1.3,
                ),
              ),
            ),
          if (verificationStatus != null) ...[
            const SizedBox(height: Spacing.sm),
            _PatchVerificationStatusView(status: verificationStatus),
          ],
          if (shouldOfferPatchVerification(patch) &&
              !verificationSnapshot.inFlight) ...[
            const SizedBox(height: Spacing.sm),
            FilledButton(
              style: _patchPrimaryActionStyle(tokens),
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
    unawaited(
      verifyPatchFromStudio(
        ref,
        patch,
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

class _PatchVerificationStatusView extends ConsumerWidget {
  final _PatchVerificationStatus status;

  const _PatchVerificationStatusView({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final color = switch (status.kind) {
      _PatchVerificationStatusKind.running => tokens.textSecondary,
      _PatchVerificationStatusKind.waitingApproval => tokens.warning,
      _PatchVerificationStatusKind.passed => tokens.success,
      _PatchVerificationStatusKind.failed => tokens.error,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status.title,
            style: TextStyle(
              color: color,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (status.detail.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              status.detail,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _PatchVerificationStatusKind { running, waitingApproval, passed, failed }

class _PatchVerificationStatus {
  final _PatchVerificationStatusKind kind;
  final String title;
  final String detail;

  const _PatchVerificationStatus({
    required this.kind,
    required this.title,
    required this.detail,
  });
}

bool shouldOfferPatchVerification(ProposedPatchSet patch) {
  return patch.verificationRequested &&
      patch.applyStatus == PatchApplyStatus.applied &&
      (patch.verificationRequestId == null ||
          patch.verificationRequestId!.trim().isEmpty) &&
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

StudioTurn? _verificationTurnForPatch(
  StudioThread? thread,
  ProposedPatchSet patch,
) {
  final requestId = patch.verificationRequestId;
  if (requestId == null || requestId.trim().isEmpty || thread == null) {
    return null;
  }
  return thread.turns.where((turn) => turn.requestId == requestId).firstOrNull;
}

bool _verificationIsInFlight(StudioTurn? turn) {
  if (turn == null) return false;
  return switch (turn.status) {
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
  };
}

_PatchVerificationStatus? _verificationStatusForPatch(
  ProposedPatchSet patch,
  StudioTurn? turn,
) {
  final requestId = patch.verificationRequestId;
  if (requestId == null || requestId.trim().isEmpty) return null;
  if (turn == null) {
    return const _PatchVerificationStatus(
      kind: _PatchVerificationStatusKind.running,
      title: 'Verification started',
      detail: 'Circuit started a Verify turn for this patch.',
    );
  }
  final pendingApproval = turn.events.any(
    (event) =>
        event.type == StudioTurnEventType.approvalRequest &&
        event.approvalState == ApprovalRequestState.pending,
  );
  if (pendingApproval || turn.status == StudioTurnStatus.waitingForApproval) {
    return const _PatchVerificationStatus(
      kind: _PatchVerificationStatusKind.waitingApproval,
      title: 'Verification waiting for approval',
      detail: 'Review and approve the command before Circuit runs it.',
    );
  }
  if (_verificationIsInFlight(turn)) {
    return const _PatchVerificationStatus(
      kind: _PatchVerificationStatusKind.running,
      title: 'Verification running',
      detail: 'Circuit is running the approved verification turn.',
    );
  }
  final commandResults = turn.toolResults
      .where((result) => result.toolName == 'run_command')
      .toList(growable: false);
  final failedCommand = commandResults.where((result) {
    final status = result.status.name;
    return status == 'error' ||
        status == 'cancelled' ||
        status == 'denied' ||
        status == 'waitingForApproval';
  }).firstOrNull;
  if (turn.status == StudioTurnStatus.failed || failedCommand != null) {
    final detail = failedCommand?.summary.trim().isNotEmpty == true
        ? failedCommand!.summary
        : turn.lastError ?? _latestErrorDetail(turn) ?? 'Verification failed.';
    return _PatchVerificationStatus(
      kind: _PatchVerificationStatusKind.failed,
      title: 'Verification failed',
      detail: detail,
    );
  }
  if (turn.status == StudioTurnStatus.cancelled) {
    return const _PatchVerificationStatus(
      kind: _PatchVerificationStatusKind.failed,
      title: 'Verification cancelled',
      detail: 'The Verify turn was cancelled before completion.',
    );
  }
  final verificationStep = turn.steps
      .where((step) => step.step == TurnStep.verification)
      .lastOrNull;
  if (verificationStep?.status == TurnStepStatus.failed) {
    return _PatchVerificationStatus(
      kind: _PatchVerificationStatusKind.failed,
      title: 'Verification failed',
      detail: verificationStep?.detail ?? 'Verification failed.',
    );
  }
  final failedSummary = turn.events
      .where((event) => event.type == StudioTurnEventType.completionSummary)
      .where((event) {
        final text = '${event.title}\n${event.detail}'.toLowerCase();
        return text.contains('verification failed') ||
            text.contains('command failed') ||
            text.contains('command blocked') ||
            text.contains('timed out');
      })
      .lastOrNull;
  if (failedSummary != null) {
    return _PatchVerificationStatus(
      kind: _PatchVerificationStatusKind.failed,
      title: 'Verification failed',
      detail: failedSummary.detail,
    );
  }
  final successfulCommands = commandResults
      .where((result) => result.status.name == 'success')
      .toList(growable: false);
  if (turn.status == StudioTurnStatus.completed &&
      successfulCommands.isNotEmpty) {
    final detail = successfulCommands.length == 1
        ? successfulCommands.single.summary
        : '${successfulCommands.length} verification commands completed.';
    return _PatchVerificationStatus(
      kind: _PatchVerificationStatusKind.passed,
      title: 'Verification completed',
      detail: detail,
    );
  }
  if (turn.status == StudioTurnStatus.completed) {
    return _PatchVerificationStatus(
      kind: _PatchVerificationStatusKind.passed,
      title: 'Verification completed',
      detail:
          _latestCompletionDetail(turn) ??
          'The Verify turn completed without command output.',
    );
  }
  return null;
}

class _PatchVerificationSnapshot {
  final bool inFlight;
  final _PatchVerificationStatus? status;
  final int _fingerprint;

  const _PatchVerificationSnapshot({
    required this.inFlight,
    required this.status,
    required int fingerprint,
  }) : _fingerprint = fingerprint;

  factory _PatchVerificationSnapshot.forPatch(
    StudioThread? thread,
    ProposedPatchSet patch,
  ) {
    final turn = _verificationTurnForPatch(thread, patch);
    final status = _verificationStatusForPatch(patch, turn);
    return _PatchVerificationSnapshot(
      inFlight: _verificationIsInFlight(turn),
      status: status,
      fingerprint: Object.hash(
        patch.verificationRequestId,
        turn?.id,
        turn?.status,
        turn?.lastError,
        turn?.events.length,
        turn?.toolResults.length,
        status?.kind,
        status?.title,
        status?.detail,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _PatchVerificationSnapshot &&
        _fingerprint == other._fingerprint;
  }

  @override
  int get hashCode => _fingerprint;
}

String? _latestErrorDetail(StudioTurn turn) {
  return turn.events
      .where((event) => event.type == StudioTurnEventType.error)
      .lastOrNull
      ?.detail;
}

String? _latestCompletionDetail(StudioTurn turn) {
  return turn.events
      .where((event) => event.type == StudioTurnEventType.completionSummary)
      .lastOrNull
      ?.detail;
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
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        child: Row(
          children: [
            Icon(
              file.hasDiff
                  ? Icons.description_outlined
                  : Icons.article_outlined,
              color: tokens.textMuted,
              size: 11,
            ),
            const SizedBox(width: Spacing.sm),
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
            Icon(Icons.chevron_right, color: tokens.textMuted, size: 13),
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
        constraints: const BoxConstraints(maxWidth: 500),
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: tokens.studioBubble,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: FontSizes.md,
            height: 1.28,
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
      constraints: const BoxConstraints(maxWidth: 760),
      margin: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkdownWidget(
            data: widget.text,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            config: buildChatMarkdownConfig(widget.tokens),
          ),
          const SizedBox(height: 1),
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
        borderRadius: BorderRadius.circular(7),
        onTap: onPressed,
        child: AnimatedContainer(
          duration: AnimationDurations.fast,
          curve: AnimationCurves.smooth,
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? tokens.studioControl.withValues(alpha: 0.58)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            icon,
            size: 12,
            color: selected ? tokens.textSecondary : tokens.textMuted,
          ),
        ),
      ),
    );
  }
}
