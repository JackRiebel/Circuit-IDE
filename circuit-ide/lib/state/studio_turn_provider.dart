import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/confirmation_request.dart';
import '../models/accepted_plan_context.dart';
import '../models/context_pack.dart';
import '../models/provider_lifecycle_event.dart';
import '../models/reviewed_edit.dart';
import '../models/studio_thread.dart';
import '../models/studio_turn.dart';
import '../models/tool_result_envelope.dart';
import '../models/turn_intent.dart';
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
  final Map<String, StudioTurnRef> recentByRequestId;

  const StudioTurnState({
    this.activeByRequestId = const {},
    this.recentByRequestId = const {},
  });

  StudioTurnRef? refForRequest(String requestId) {
    return activeByRequestId[requestId];
  }

  StudioTurnRef? archivedRefForRequest(String requestId) {
    return activeByRequestId[requestId] ?? recentByRequestId[requestId];
  }

  StudioTurnState copyWith({
    Map<String, StudioTurnRef>? activeByRequestId,
    Map<String, StudioTurnRef>? recentByRequestId,
  }) {
    return StudioTurnState(
      activeByRequestId: activeByRequestId ?? this.activeByRequestId,
      recentByRequestId: recentByRequestId ?? this.recentByRequestId,
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
    TurnIntent intent = TurnIntent.code,
    AcceptedPlanState acceptedPlanState = AcceptedPlanState.none,
    AcceptedPlanContext? acceptedPlanContext,
    ContextRetrievalResult? contextRetrieval,
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
      intent: intent,
      contextSummary: contextSummary,
      acceptedPlanState: acceptedPlanState,
      acceptedPlanContext: acceptedPlanContext,
      contextRetrieval: contextRetrieval,
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
    final thread = ref
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == turnRef.threadId);
    final turn = thread.isEmpty
        ? null
        : thread.first.turns
              .where((candidate) => candidate.id == turnRef.turnId)
              .firstOrNull;
    final terminalTurn = turn?.completedAt != null;
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
    if (status != null && !terminalTurn) {
      ref
          .read(studioThreadProvider.notifier)
          .updateTurn(turnRef.threadId, turnRef.turnId, status: status);
    }
  }

  void markAcceptedPlanVerificationRequested(String requestId) {
    final turnRef = state.refForRequest(requestId);
    if (turnRef == null) return;
    ref
        .read(studioThreadProvider.notifier)
        .upsertTurnEvent(
          turnRef.threadId,
          turnRef.turnId,
          StudioTurnEvent(
            id: 'accepted-plan-verification-${turnRef.turnId}',
            turnId: turnRef.turnId,
            requestId: requestId,
            threadId: turnRef.threadId,
            type: StudioTurnEventType.progress,
            title: 'Accepted plan verification requested',
            detail:
                'The accepted plan asked for verification after app-side patch apply.',
            timestamp: DateTime.now(),
            transcriptVisible: false,
          ),
        );
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

  void addToolResult(String requestId, ToolResultEnvelope result) {
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
    final results = [
      ...turn.toolResults.where(
        (candidate) => candidate.toolCallId != result.toolCallId,
      ),
      result,
    ];
    ref
        .read(studioThreadProvider.notifier)
        .updateTurn(turnRef.threadId, turnRef.turnId, toolResults: results);
  }

  void addProviderDiagnostic(
    String requestId,
    ProviderLifecycleEvent diagnostic,
  ) {
    final turnRef = state.archivedRefForRequest(requestId);
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
    final diagnostics = [...turn.providerDiagnostics, diagnostic];
    ref
        .read(studioThreadProvider.notifier)
        .updateTurn(
          turnRef.threadId,
          turnRef.turnId,
          providerDiagnostics: diagnostics,
        );
  }

  void setAcceptedPlanState(
    String requestId,
    AcceptedPlanState acceptedPlanState,
  ) {
    final turnRef = state.refForRequest(requestId);
    if (turnRef == null) return;
    ref
        .read(studioThreadProvider.notifier)
        .updateTurn(
          turnRef.threadId,
          turnRef.turnId,
          acceptedPlanState: acceptedPlanState,
        );
  }

  void recordPatchTransaction(
    String requestId, {
    required String patchSetId,
    required String title,
    required String detail,
    PatchApplyStatus? applyStatus,
  }) {
    final turnRef = state.archivedRefForRequest(requestId);
    if (turnRef == null) return;
    final thread = ref
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == turnRef.threadId)
        .firstOrNull;
    final turn = thread?.turns
        .where((candidate) => candidate.id == turnRef.turnId)
        .firstOrNull;
    final acceptedPlanState = _acceptedPlanStateForPatchApply(
      turn?.acceptedPlanState ?? AcceptedPlanState.none,
      applyStatus,
    );
    if (acceptedPlanState != null) {
      ref
          .read(studioThreadProvider.notifier)
          .updateTurn(
            turnRef.threadId,
            turnRef.turnId,
            acceptedPlanState: acceptedPlanState,
          );
    }
    ref
        .read(studioThreadProvider.notifier)
        .upsertTurnEvent(
          turnRef.threadId,
          turnRef.turnId,
          StudioTurnEvent.completionSummary(
            id: 'patch-transaction-${turnRef.turnId}-$patchSetId-${DateTime.now().microsecondsSinceEpoch}',
            turnId: turnRef.turnId,
            requestId: requestId,
            threadId: turnRef.threadId,
            title: title,
            detail: detail,
          ),
        );
  }

  AcceptedPlanState? _acceptedPlanStateForPatchApply(
    AcceptedPlanState current,
    PatchApplyStatus? applyStatus,
  ) {
    if (current == AcceptedPlanState.none || applyStatus == null) return null;
    return switch (applyStatus) {
      PatchApplyStatus.applied => AcceptedPlanState.implemented,
      PatchApplyStatus.conflict ||
      PatchApplyStatus.failed => AcceptedPlanState.failed,
      PatchApplyStatus.rejected => AcceptedPlanState.blockedForMissingContext,
      PatchApplyStatus.restored => AcceptedPlanState.patchProposed,
    };
  }

  void complete(
    String requestId, {
    required String content,
    String? summary,
    bool allowArchived = false,
  }) {
    final turnRef = allowArchived
        ? state.archivedRefForRequest(requestId)
        : state.refForRequest(requestId);
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
          title: _completionSummaryTitle(summary),
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
      expirePendingApprovals: true,
    );
    if (state.activeByRequestId.containsKey(requestId)) {
      _archive(requestId);
    }
  }

  void fail(String requestId, String message) {
    final turnRef = state.refForRequest(requestId);
    if (turnRef == null) return;
    final notifier = ref.read(studioThreadProvider.notifier);
    final errorDetail = _failureDetail(requestId, message);
    notifier.upsertTurnEvent(
      turnRef.threadId,
      turnRef.turnId,
      StudioTurnEvent.error(
        turnId: turnRef.turnId,
        requestId: requestId,
        threadId: turnRef.threadId,
        detail: errorDetail,
      ),
    );
    notifier.updateTurn(
      turnRef.threadId,
      turnRef.turnId,
      status: StudioTurnStatus.failed,
      lastError: errorDetail,
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
    final archived = state.activeByRequestId[requestId];
    final active = {...state.activeByRequestId}..remove(requestId);
    final recent = {requestId: ?archived, ...state.recentByRequestId};
    state = state.copyWith(
      activeByRequestId: active,
      recentByRequestId: recent,
    );
  }

  String _completionSummaryTitle(String summary) {
    final normalized = summary.toLowerCase();
    if (summary == 'Ready for the next prompt.') {
      return 'Ready for next prompt';
    }
    if (normalized.contains('verification failed') ||
        normalized.contains('command failed')) {
      return 'Verification failed';
    }
    if (normalized.contains('verification command') ||
        normalized.contains('verification completed')) {
      return 'Verification summary';
    }
    if (normalized.contains('patch apply failed')) {
      return 'Patch apply failed';
    }
    if (normalized.contains('applied ') || normalized.contains('checkpoint:')) {
      return 'Applied changes';
    }
    if (normalized.contains('reviewable patch') ||
        normalized.contains('prepared')) {
      return 'Prepared changes';
    }
    if (normalized.contains('provider returned') ||
        normalized.contains('runtime repaired')) {
      return 'Provider summary';
    }
    return 'Turn summary';
  }

  String _failureDetail(String requestId, String message) {
    final turnRef = state.refForRequest(requestId);
    if (turnRef == null) return message;
    final thread = ref
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == turnRef.threadId)
        .firstOrNull;
    final turn = thread?.turns
        .where((candidate) => candidate.id == turnRef.turnId)
        .firstOrNull;
    final diagnostic = _preferredFailureDiagnostic(turn?.providerDiagnostics);
    if (diagnostic == null) return message;
    final title = _failureDiagnosticTitle(diagnostic.kind);
    final detail = diagnostic.detail?.trim();
    final prefix = detail == null || detail.isEmpty ? title : '$title: $detail';
    if (message.trim().isEmpty || message == detail || message == title) {
      return prefix;
    }
    if (message.contains(prefix) || prefix.contains(message)) return prefix;
    return '$prefix\n$message';
  }

  bool _isUserFacingFailureDiagnostic(ProviderLifecycleEvent event) {
    return switch (event.kind) {
      ProviderLifecycleEventKind.authFailed ||
      ProviderLifecycleEventKind.noFirstByte ||
      ProviderLifecycleEventKind.noTextOrTool ||
      ProviderLifecycleEventKind.unavailableTool ||
      ProviderLifecycleEventKind.rateLimited ||
      ProviderLifecycleEventKind.malformedChunk ||
      ProviderLifecycleEventKind.malformedBytes ||
      ProviderLifecycleEventKind.streamEndedWithoutDone ||
      ProviderLifecycleEventKind.failed ||
      ProviderLifecycleEventKind.timeout => true,
      _ => false,
    };
  }

  ProviderLifecycleEvent? _preferredFailureDiagnostic(
    List<ProviderLifecycleEvent>? diagnostics,
  ) {
    if (diagnostics == null || diagnostics.isEmpty) return null;
    final userFacing = diagnostics.reversed
        .where(_isUserFacingFailureDiagnostic)
        .toList(growable: false);
    if (userFacing.isEmpty) return null;
    return userFacing
            .where((event) => event.kind != ProviderLifecycleEventKind.failed)
            .firstOrNull ??
        userFacing.first;
  }

  String _failureDiagnosticTitle(ProviderLifecycleEventKind kind) {
    return switch (kind) {
      ProviderLifecycleEventKind.authFailed => 'Authentication failed',
      ProviderLifecycleEventKind.noFirstByte => 'No provider response bytes',
      ProviderLifecycleEventKind.noTextOrTool => 'No model output',
      ProviderLifecycleEventKind.unavailableTool =>
        'Unavailable tool requested',
      ProviderLifecycleEventKind.rateLimited => 'Rate limited',
      ProviderLifecycleEventKind.malformedChunk => 'Malformed stream chunk',
      ProviderLifecycleEventKind.malformedBytes => 'Malformed response bytes',
      ProviderLifecycleEventKind.streamEndedWithoutDone => 'Stream ended early',
      ProviderLifecycleEventKind.timeout => 'Provider timed out',
      ProviderLifecycleEventKind.failed => 'Provider failed',
      _ => 'Provider failed',
    };
  }
}

final studioTurnProvider =
    NotifierProvider<StudioTurnController, StudioTurnState>(
      StudioTurnController.new,
    );
