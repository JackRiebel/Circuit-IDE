import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../core/constants/studio_layout_contract.dart';
import '../../models/agent_workspace.dart';
import '../../models/reviewed_edit.dart';
import '../../models/studio_source_artifact.dart';
import '../../models/studio_turn.dart';
import '../../models/turn_intent.dart';
import '../../models/generated_artifact.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_source_artifact_provider.dart';
import '../../state/studio_thread_provider.dart';
import 'studio_message_sender.dart';
import 'studio_plan_continuation.dart';
import 'studio_prompt_composer.dart';
import 'studio_right_drawer.dart';
import 'studio_task_artifact_cards.dart';
import 'studio_task_empty_state.dart';
import 'studio_task_plan_draft.dart';
import 'studio_task_plan_continuation_card.dart';
import 'studio_task_plan_summary.dart';
import 'studio_task_patch_summary.dart';
import 'studio_task_transcript_messages.dart';
import 'studio_task_transcript_chrome.dart';
import 'studio_task_transcript_index.dart';
import 'studio_task_transcript_status.dart';
import 'studio_task_workspace_card.dart';
import '../../services/studio_transcript_scroll_probe.dart';

export 'studio_task_patch_evidence.dart'
    show
        buildPatchVerificationPrompt,
        buildPlanImplementationPrompt,
        shouldOfferPatchVerification;

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

class _TaskTranscript extends ConsumerStatefulWidget {
  final AgentTask? task;

  const _TaskTranscript({required this.task});

  @override
  ConsumerState<_TaskTranscript> createState() => _TaskTranscriptState();
}

class _TaskTranscriptState extends ConsumerState<_TaskTranscript> {
  static const _tailFollowThreshold = 80.0;

  late final ScrollController _scrollController;
  final _scrollProbeOwner = Object();
  bool _followLatest = true;
  bool _followScheduled = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_trackScrollPosition);
    StudioTranscriptScrollProbe.register(
      owner: _scrollProbeOwner,
      prepare: _preparePackagedScrollProbe,
      driver: _drivePackagedScrollProbe,
    );
  }

  @override
  void didUpdateWidget(covariant _TaskTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task?.id != widget.task?.id) {
      _followLatest = true;
      _scheduleFollowLatest();
    }
  }

  @override
  void dispose() {
    StudioTranscriptScrollProbe.unregister(_scrollProbeOwner);
    _scrollController
      ..removeListener(_trackScrollPosition)
      ..dispose();
    super.dispose();
  }

  void _trackScrollPosition() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return;
    _followLatest =
        position.maxScrollExtent - position.pixels <= _tailFollowThreshold;
  }

  void _scheduleFollowLatest() {
    if (!_followLatest || _followScheduled) return;
    _followScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      if (!mounted || !_followLatest || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (!position.hasContentDimensions) return;
      position.jumpTo(position.maxScrollExtent);
    });
  }

  /// Drives the production transcript ListView only while the private
  /// packaged performance probe is active. The companion preparation hook
  /// starts at the tail; this method makes bounded animated steps toward
  /// history so the recorded frames represent a real no-stream transcript
  /// scroll rather than a synthetic widget tree.
  Future<bool> _preparePackagedScrollProbe() async {
    if (!mounted || !_scrollController.hasClients) return false;
    final position = _scrollController.position;
    if (!position.hasContentDimensions ||
        position.maxScrollExtent <= position.viewportDimension) {
      return false;
    }
    position.jumpTo(position.maxScrollExtent);
    return true;
  }

  Future<bool> _drivePackagedScrollProbe({required int stepCount}) async {
    if (!mounted || !_scrollController.hasClients || stepCount < 1) {
      return false;
    }
    final position = _scrollController.position;
    if (!position.hasContentDimensions ||
        position.maxScrollExtent <= position.viewportDimension) {
      return false;
    }
    final tail = position.maxScrollExtent;
    _followLatest = false;
    for (var step = 1; step <= stepCount; step++) {
      final fraction = 1 - (0.9 * step / stepCount);
      await _scrollController.animateTo(
        tail * fraction,
        duration: const Duration(milliseconds: 34),
        curve: Curves.linear,
      );
    }
    return mounted &&
        _scrollController.hasClients &&
        _scrollController.position.pixels < tail;
  }

  @override
  Widget build(BuildContext context) {
    final transcriptIndex = ref.watch(
      studioThreadProvider.select(
        (state) => StudioTaskTranscriptIndex.fromState(state, widget.task),
      ),
    );
    final visibleThreadId = transcriptIndex.threadId;
    ref.listen(studioThreadProvider, (previous, next) {
      final previousThread = previous?.threadForTaskView(
        transcriptIndex.effectiveTaskId,
      );
      final nextThread = next.threadForTaskView(
        transcriptIndex.effectiveTaskId,
      );
      if (previousThread?.id == visibleThreadId ||
          nextThread?.id == visibleThreadId) {
        _scheduleFollowLatest();
      }
    });
    _scheduleFollowLatest();
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            cacheExtent: StudioLayoutContract.transcriptCacheExtent,
            padding: const EdgeInsets.fromLTRB(
              StudioLayoutContract.transcriptHorizontalInset,
              24,
              StudioLayoutContract.transcriptHorizontalInset,
              18,
            ),
            itemCount: transcriptIndex.turnIds.isEmpty
                ? 2
                : transcriptIndex.turnIds.length + 1,
            itemBuilder: (context, itemIndex) {
              if (itemIndex == 0) {
                return StudioTaskTranscriptItemFrame(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      StudioTaskTranscriptStatusHeader(
                        label: transcriptIndex.statusLabel,
                        active: transcriptIndex.statusActive,
                      ),
                      if (widget.task != null) ...[
                        const SizedBox(height: Spacing.sm),
                        StudioTaskWorkspaceCard(task: widget.task!),
                      ],
                      for (final compaction in transcriptIndex.compactions) ...[
                        const SizedBox(height: Spacing.sm),
                        StudioConversationCompactionCard(
                          threadId: transcriptIndex.threadId,
                          compaction: compaction,
                        ),
                      ],
                      const SizedBox(height: Spacing.lg),
                    ],
                  ),
                );
              }
              if (transcriptIndex.turnIds.isEmpty) {
                return StudioTaskTranscriptItemFrame(
                  child: StudioTaskEmptyState(
                    title: transcriptIndex.title,
                    lastError: transcriptIndex.lastError,
                  ),
                );
              }
              final turnIndex = itemIndex - 1;
              return StudioTaskTranscriptItemFrame(
                child: StudioTurnTranscriptItem(
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
          padding: const EdgeInsets.fromLTRB(
            StudioLayoutContract.transcriptHorizontalInset,
            0,
            StudioLayoutContract.transcriptHorizontalInset,
            12,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: StudioLayoutContract.composerWidth,
              ),
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
                  onQueueResearch: _queueResearch,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _queueResearch(String text) {
    try {
      final task = ref
          .read(agentWorkspaceProvider.notifier)
          .startTask(
            goal: text,
            profile: AgentTaskProfile.research,
            backgroundExecutionRequested: true,
          );
      ref.read(studioShellProvider.notifier).openTask(task.id);
    } on StateError catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message.toString())));
    }
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
        StudioTaskChatTranscriptLine(
          isUser: true,
          text: visibleUserMessage.content ?? visibleUserMessage.detail,
        ),
      );
    } else if (_shouldRenderFallbackPrompt(turn, events)) {
      widgets.add(
        StudioTaskChatTranscriptLine(isUser: true, text: turn.displayPrompt),
      );
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
          widgets.add(StudioTurnApprovalCard(event: event));
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
              StudioTaskChatTranscriptLine(isUser: false, text: displayContent),
            );
          }
          if (generatedArtifacts.isNotEmpty && !artifactCardsAdded) {
            widgets.add(
              StudioGeneratedArtifactStack(artifacts: generatedArtifacts),
            );
            artifactCardsAdded = true;
          }
          if (turnPatch != null && !patchAdded) {
            widgets.add(_reviewArtifactCard(turnPatch));
            patchAdded = true;
          }
        case StudioTurnEventType.error:
          widgets.add(
            StudioTaskTranscriptEvent(
              icon: StudioIcons.errorOutline,
              title: event.title,
              detail: event.detail,
            ),
          );
        case StudioTurnEventType.completionSummary:
          if (_isGenericReadySummary(event)) break;
          widgets.add(
            StudioTaskTranscriptEvent(
              icon: StudioIcons.checkCircleOutline,
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
        widgets.add(StudioPlanDraftCard(markdown: turn.assistantDraft));
      } else if (draftContent.isNotEmpty) {
        widgets.add(
          StudioTaskChatTranscriptLine(
            isUser: false,
            text: draftContent,
            isStreaming: turn.status == StudioTurnStatus.streaming,
          ),
        );
      }
    }
    if (generatedArtifacts.isNotEmpty && !artifactCardsAdded) {
      widgets.add(StudioGeneratedArtifactStack(artifacts: generatedArtifacts));
    }
    if (turnPatch != null && !patchAdded) {
      widgets.add(_reviewArtifactCard(turnPatch));
    } else if (turnPatch == null) {
      final continuation = studioPlanContinuationForTurn(turn);
      if (continuation != null) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: StudioPlanContinuationCard(
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
    final recovery = turn.recoveryCheckpoint;
    if (turn.status == StudioTurnStatus.interrupted && recovery != null) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: StudioTaskRecoveryCard(turn: turn, taskId: taskId),
        ),
      );
    }
    final outcome = turn.finalOutcome;
    if (outcome != null) {
      widgets.add(
        StudioTaskTranscriptEvent(
          icon: switch (outcome) {
            StudioTurnOutcome.failed ||
            StudioTurnOutcome.blocked => StudioIcons.errorOutline,
            StudioTurnOutcome.cancelled => StudioIcons.cancelOutlined,
            _ => StudioIcons.taskAltOutlined,
          },
          title: studioTurnOutcomeTitle(outcome),
          detail: _finalOutcomeDetail(turn, outcome),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }

  Widget _reviewArtifactCard(ProposedPatchSet patch) {
    return patch.isPlanOnly
        ? StudioPlanSummaryCard(patch: patch)
        : StudioPatchSummaryCard(patch: patch);
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
    final prompt = turn.displayPrompt.trim();
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

String _finalOutcomeDetail(StudioTurn turn, StudioTurnOutcome outcome) {
  return switch (outcome) {
    StudioTurnOutcome.answered => 'Response recorded in this transcript.',
    StudioTurnOutcome.createdArtifact =>
      '${turn.toolResults.expand((result) => result.artifacts).length} artifact${turn.toolResults.expand((result) => result.artifacts).length == 1 ? '' : 's'} recorded. Review the artifact card above.',
    StudioTurnOutcome.preparedChanges =>
      'Changes are ready for review. Approve or revise the proposal above.',
    StudioTurnOutcome.appliedChanges =>
      turn.planTargetProgress.isEmpty
          ? 'Changes were applied. Review the patch or run verification next.'
          : '${turn.planTargetProgress.where((target) => target.state == PlanTargetProgressState.applied).length} planned target${turn.planTargetProgress.where((target) => target.state == PlanTargetProgressState.applied).length == 1 ? '' : 's'} applied. Review the patch or run verification next.',
    StudioTurnOutcome.verified =>
      'Verification completed. Review the command evidence above.',
    StudioTurnOutcome.blocked =>
      'A policy or approval blocked this task. Review the error and retry when ready.',
    StudioTurnOutcome.failed =>
      'The task stopped before completion. Review the error and retry when ready.',
    StudioTurnOutcome.cancelled =>
      'The request was cancelled. Start a new turn to retry.',
  };
}
