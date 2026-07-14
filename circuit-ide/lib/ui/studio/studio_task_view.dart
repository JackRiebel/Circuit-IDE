import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../core/constants/studio_layout_contract.dart';
import '../../models/agent_workspace.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import 'studio_message_sender.dart';
import 'studio_prompt_composer.dart';
import 'studio_right_drawer.dart';
import 'studio_task_empty_state.dart';
import 'studio_task_transcript_chrome.dart';
import 'studio_task_transcript_index.dart';
import 'studio_task_turn_renderer.dart';
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
                  builder: StudioTaskTurnRenderer.build,
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
}
