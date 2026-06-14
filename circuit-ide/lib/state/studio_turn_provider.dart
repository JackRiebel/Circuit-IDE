import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/confirmation_request.dart';
import '../models/studio_thread.dart';
import '../models/studio_turn.dart';
import 'studio_thread_provider.dart';

const _uuid = Uuid();

class StudioTurnRef {
  final String requestId;
  final String threadId;
  final String turnId;

  const StudioTurnRef({
    required this.requestId,
    required this.threadId,
    required this.turnId,
  });
}

class StudioTurnState {
  final Map<String, StudioTurnRef> activeByRequestId;

  const StudioTurnState({this.activeByRequestId = const {}});

  StudioTurnRef? refForRequest(String requestId) {
    return activeByRequestId[requestId];
  }

  StudioTurnState copyWith({Map<String, StudioTurnRef>? activeByRequestId}) {
    return StudioTurnState(
      activeByRequestId: activeByRequestId ?? this.activeByRequestId,
    );
  }
}

class StudioTurnController extends Notifier<StudioTurnState> {
  @override
  StudioTurnState build() => const StudioTurnState();

  StudioTurn registerTurn({
    required String requestId,
    required String threadId,
    required String? taskId,
    required String userMessageId,
    required String prompt,
    required String model,
    required StudioContextSummary contextSummary,
  }) {
    final now = DateTime.now();
    final turnId = _uuid.v4();
    final turn = StudioTurn(
      id: turnId,
      threadId: threadId,
      requestId: requestId,
      taskId: taskId,
      userMessageId: userMessageId,
      prompt: prompt,
      model: model,
      contextSummary: contextSummary,
      status: StudioTurnStatus.buildingContext,
      createdAt: now,
      updatedAt: now,
      events: [
        StudioTurnEvent.userMessage(
          id: userMessageId,
          turnId: turnId,
          requestId: requestId,
          threadId: threadId,
          content: prompt,
          timestamp: now,
        ),
        StudioTurnEvent.context(
          turnId: turnId,
          requestId: requestId,
          threadId: threadId,
          summary: contextSummary,
          timestamp: now.add(const Duration(milliseconds: 1)),
        ),
      ],
    );
    state = state.copyWith(
      activeByRequestId: {
        ...state.activeByRequestId,
        requestId: StudioTurnRef(
          requestId: requestId,
          threadId: threadId,
          turnId: turnId,
        ),
      },
    );
    ref.read(studioThreadProvider.notifier).upsertTurn(threadId, turn);
    return turn;
  }

  void markProgress(
    String requestId, {
    required String title,
    required String detail,
    StudioTurnStatus? status,
    bool transcriptVisible = false,
  }) {
    final turnRef = state.refForRequest(requestId);
    if (turnRef == null) return;
    ref
        .read(studioThreadProvider.notifier)
        .upsertTurnEvent(
          turnRef.threadId,
          turnRef.turnId,
          StudioTurnEvent.progress(
            turnId: turnRef.turnId,
            requestId: requestId,
            threadId: turnRef.threadId,
            title: title,
            detail: detail,
            transcriptVisible: transcriptVisible,
          ),
        );
    if (status != null) {
      ref
          .read(studioThreadProvider.notifier)
          .updateTurn(turnRef.threadId, turnRef.turnId, status: status);
    }
  }

  void appendAssistantDelta(String requestId, String delta) {
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
    ref
        .read(studioThreadProvider.notifier)
        .updateTurn(
          turnRef.threadId,
          turnRef.turnId,
          status: StudioTurnStatus.streaming,
          assistantDraft: '${turn.assistantDraft}$delta',
        );
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
  }

  void upsertApproval(String requestId, ConfirmationRequest request) {
    final turnRef = state.refForRequest(requestId);
    if (turnRef == null) return;
    ref
        .read(studioThreadProvider.notifier)
        .upsertTurnEvent(
          turnRef.threadId,
          turnRef.turnId,
          StudioTurnEvent.approval(
            turnId: turnRef.turnId,
            requestId: requestId,
            threadId: turnRef.threadId,
            request: request,
          ),
        );
    ref
        .read(studioThreadProvider.notifier)
        .updateTurn(
          turnRef.threadId,
          turnRef.turnId,
          status: StudioTurnStatus.waitingForApproval,
        );
  }

  void resolveApproval(
    String requestId,
    String approvalId,
    ApprovalRequestState approvalState,
  ) {
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
    final event = turn.events
        .where((candidate) => candidate.approvalId == approvalId)
        .firstOrNull;
    if (event == null) return;
    ref
        .read(studioThreadProvider.notifier)
        .upsertTurnEvent(
          turnRef.threadId,
          turnRef.turnId,
          event.copyWith(approvalState: approvalState),
        );
  }

  void complete(String requestId, {required String content, String? summary}) {
    final turnRef = state.refForRequest(requestId);
    if (turnRef == null) return;
    final notifier = ref.read(studioThreadProvider.notifier);
    if (content.trim().isNotEmpty) {
      notifier.upsertTurnEvent(
        turnRef.threadId,
        turnRef.turnId,
        StudioTurnEvent.assistantMessage(
          turnId: turnRef.turnId,
          requestId: requestId,
          threadId: turnRef.threadId,
          content: content,
        ),
      );
    }
    if (summary != null && summary.trim().isNotEmpty) {
      notifier.upsertTurnEvent(
        turnRef.threadId,
        turnRef.turnId,
        StudioTurnEvent.completionSummary(
          turnId: turnRef.turnId,
          requestId: requestId,
          threadId: turnRef.threadId,
          title: summary == 'Ready for the next prompt.'
              ? 'Ready for next prompt'
              : 'Change summary',
          detail: summary,
        ),
      );
    }
    notifier.updateTurn(
      turnRef.threadId,
      turnRef.turnId,
      status: StudioTurnStatus.completed,
      assistantDraft: '',
      complete: true,
    );
    _archive(requestId);
  }

  void fail(String requestId, String message) {
    final turnRef = state.refForRequest(requestId);
    if (turnRef == null) return;
    final notifier = ref.read(studioThreadProvider.notifier);
    notifier.upsertTurnEvent(
      turnRef.threadId,
      turnRef.turnId,
      StudioTurnEvent.error(
        turnId: turnRef.turnId,
        requestId: requestId,
        threadId: turnRef.threadId,
        detail: message,
      ),
    );
    notifier.updateTurn(
      turnRef.threadId,
      turnRef.turnId,
      status: StudioTurnStatus.failed,
      lastError: message,
      complete: true,
      expirePendingApprovals: true,
    );
    _archive(requestId);
  }

  void cancel(String requestId, String message) {
    final turnRef = state.refForRequest(requestId);
    if (turnRef == null) return;
    final notifier = ref.read(studioThreadProvider.notifier);
    notifier.upsertTurnEvent(
      turnRef.threadId,
      turnRef.turnId,
      StudioTurnEvent.error(
        turnId: turnRef.turnId,
        requestId: requestId,
        threadId: turnRef.threadId,
        detail: message,
      ),
    );
    notifier.updateTurn(
      turnRef.threadId,
      turnRef.turnId,
      status: StudioTurnStatus.cancelled,
      complete: true,
      expirePendingApprovals: true,
    );
    _archive(requestId);
  }

  void _archive(String requestId) {
    final active = {...state.activeByRequestId}..remove(requestId);
    state = state.copyWith(activeByRequestId: active);
  }
}

final studioTurnProvider =
    NotifierProvider<StudioTurnController, StudioTurnState>(
      StudioTurnController.new,
    );
