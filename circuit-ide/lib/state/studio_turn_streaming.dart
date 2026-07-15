part of 'studio_turn_provider.dart';

mixin StudioTurnStreaming on Notifier<StudioTurnState> {
  static const _assistantDeltaFlushInterval = Duration(milliseconds: 120);

  final _pendingAssistantDeltas = <String, StringBuffer>{};
  final _assistantDeltaTimers = <String, Timer>{};
  final _lastAssistantDeltaFlushAt = <String, DateTime>{};

  void disposeAssistantDeltas() {
    for (final timer in _assistantDeltaTimers.values) {
      timer.cancel();
    }
    _assistantDeltaTimers.clear();
    _pendingAssistantDeltas.clear();
    _lastAssistantDeltaFlushAt.clear();
  }

  void recordStep(
    String requestId, {
    required TurnStep step,
    required TurnStepStatus status,
    required String title,
    String detail = '',
    bool allowArchived = false,
  });
  void appendAssistantDelta(String requestId, String delta) {
    if (delta.isEmpty) return;
    final turnRef = state.refForRequest(requestId);
    if (turnRef == null) return;
    (_pendingAssistantDeltas[requestId] ??= StringBuffer()).write(delta);
    final now = DateTime.now();
    final lastFlush = _lastAssistantDeltaFlushAt[requestId];
    if (lastFlush == null ||
        now.difference(lastFlush) >= _assistantDeltaFlushInterval) {
      _flushAssistantDelta(requestId);
      return;
    }
    _assistantDeltaTimers[requestId] ??= Timer(
      _assistantDeltaFlushInterval - now.difference(lastFlush),
      () => _flushAssistantDelta(requestId),
    );
  }

  void _flushAssistantDelta(String requestId) {
    _assistantDeltaTimers.remove(requestId)?.cancel();
    final buffer = _pendingAssistantDeltas.remove(requestId);
    final delta = buffer?.toString() ?? '';
    if (delta.isEmpty) return;
    final turnRef = state.refForRequest(requestId);
    if (turnRef == null) return;
    final thread = ref
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == turnRef.threadId)
        .firstOrNull;
    final turn = thread?.turns
        .where((candidate) => candidate.id == turnRef.turnId)
        .firstOrNull;
    if (turn == null) return;
    final shouldRecordStreamingStep = !_hasRunningOrCompletedStep(
      turn,
      TurnStep.streaming,
    );
    ref
        .read(studioThreadProvider.notifier)
        .updateTurn(
          turnRef.threadId,
          turnRef.turnId,
          status: StudioTurnStatus.streaming,
          assistantDraft: '${turn.assistantDraft}$delta',
        );
    if (shouldRecordStreamingStep) {
      recordStep(
        requestId,
        step: TurnStep.streaming,
        status: TurnStepStatus.running,
        title: 'Streaming response',
        detail: 'Circuit AI is returning assistant text.',
      );
    }
    _lastAssistantDeltaFlushAt[requestId] = DateTime.now();
  }

  bool _hasRunningOrCompletedStep(StudioTurn turn, TurnStep step) {
    return turn.steps.any(
      (candidate) =>
          candidate.step == step &&
          (candidate.status == TurnStepStatus.running ||
              candidate.status == TurnStepStatus.completed),
    );
  }

  void _clearPendingAssistantDelta(String requestId) {
    _assistantDeltaTimers.remove(requestId)?.cancel();
    _pendingAssistantDeltas.remove(requestId);
    _lastAssistantDeltaFlushAt.remove(requestId);
  }

  void replaceAssistantDraft(
    String requestId,
    String content, {
    bool allowArchived = false,
  }) {
    _clearPendingAssistantDelta(requestId);
    final turnRef = allowArchived
        ? state.archivedRefForRequest(requestId)
        : state.refForRequest(requestId);
    if (turnRef == null) return;
    final draft = content.trimRight();
    final thread = ref
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == turnRef.threadId)
        .firstOrNull;
    final turn = thread?.turns
        .where((candidate) => candidate.id == turnRef.turnId)
        .firstOrNull;
    final status = turn?.completedAt == null
        ? StudioTurnStatus.streaming
        : null;
    final shouldRecordStreamingStep =
        draft.isNotEmpty &&
        turn != null &&
        !_hasRunningOrCompletedStep(turn, TurnStep.streaming);
    ref
        .read(studioThreadProvider.notifier)
        .updateTurn(
          turnRef.threadId,
          turnRef.turnId,
          status: status,
          assistantDraft: draft,
        );
    if (shouldRecordStreamingStep) {
      recordStep(
        requestId,
        step: TurnStep.streaming,
        status: TurnStepStatus.running,
        title: 'Drafting plan',
        detail: 'Circuit AI is writing a reviewable plan.',
        allowArchived: allowArchived,
      );
    }
  }

  void upsertTool(
    String requestId, {
    required String toolCallId,
    required String toolName,
    required String title,
    required String detail,
    String? filePath,
    bool running = false,
  }) {
    final turnRef = state.refForRequest(requestId);
    if (turnRef == null) return;
    ref
        .read(studioThreadProvider.notifier)
        .upsertTurnEvent(
          turnRef.threadId,
          turnRef.turnId,
          StudioTurnEvent.tool(
            turnId: turnRef.turnId,
            requestId: requestId,
            threadId: turnRef.threadId,
            toolCallId: toolCallId,
            toolName: toolName,
            title: title,
            detail: detail,
            filePath: filePath,
          ),
        );
    ref
        .read(studioThreadProvider.notifier)
        .updateTurn(
          turnRef.threadId,
          turnRef.turnId,
          status: running ? StudioTurnStatus.toolRunning : null,
        );
    recordStep(
      requestId,
      step: TurnStep.toolExecution,
      status: running ? TurnStepStatus.running : TurnStepStatus.completed,
      title: running ? 'Tool running' : 'Tool completed',
      detail: '$toolName: $detail',
    );
  }
}
