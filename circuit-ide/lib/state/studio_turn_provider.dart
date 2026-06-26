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
    bool userMessageTranscriptVisible = true,
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
      planTargetProgress: _planTargetProgressFor(acceptedPlanContext),
      contextRetrieval: contextRetrieval,
      status: StudioTurnStatus.buildingContext,
      createdAt: now,
      updatedAt: now,
      steps: [
        TurnStepRecord(
          step: TurnStep.contextBuild,
          status: TurnStepStatus.completed,
          title: 'Context built',
          detail: contextSummary.detail,
          startedAt: now,
          completedAt: now,
        ),
        TurnStepRecord(
          step: TurnStep.providerRequest,
          status: TurnStepStatus.queued,
          title: 'Provider queued',
          detail: model,
          startedAt: now.add(const Duration(milliseconds: 1)),
        ),
      ],
      events: [
        StudioTurnEvent.userMessage(
          id: userMessageId,
          turnId: turnId,
          requestId: requestId,
          threadId: threadId,
          content: prompt,
          timestamp: now,
          transcriptVisible: userMessageTranscriptVisible,
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

  void recordStep(
    String requestId, {
    required TurnStep step,
    required TurnStepStatus status,
    required String title,
    String detail = '',
    bool allowArchived = false,
  }) {
    final turnRef = allowArchived
        ? state.archivedRefForRequest(requestId)
        : state.refForRequest(requestId);
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
    final now = DateTime.now();
    final existing = turn.steps
        .where((candidate) => candidate.step == step)
        .firstOrNull;
    final startedAt = existing?.startedAt ?? now;
    final completedAt = _terminalStepStatus(status)
        ? (existing?.completedAt ?? now)
        : null;
    ref
        .read(studioThreadProvider.notifier)
        .upsertTurnStep(
          turnRef.threadId,
          turnRef.turnId,
          TurnStepRecord(
            step: step,
            status: status,
            title: title,
            detail: detail,
            startedAt: startedAt,
            completedAt: completedAt,
          ),
        );
  }

  bool _terminalStepStatus(TurnStepStatus status) {
    return switch (status) {
      TurnStepStatus.completed ||
      TurnStepStatus.failed ||
      TurnStepStatus.skipped => true,
      TurnStepStatus.queued || TurnStepStatus.running => false,
    };
  }

  TurnStep? _stepForTurnStatus(StudioTurnStatus status) {
    return switch (status) {
      StudioTurnStatus.buildingContext => TurnStep.contextBuild,
      StudioTurnStatus.sent ||
      StudioTurnStatus.waitingForModel => TurnStep.providerRequest,
      StudioTurnStatus.streaming => TurnStep.streaming,
      StudioTurnStatus.toolRunning => TurnStep.toolExecution,
      StudioTurnStatus.waitingForApproval => TurnStep.approvalWait,
      StudioTurnStatus.completed => TurnStep.finalSummary,
      StudioTurnStatus.failed ||
      StudioTurnStatus.cancelled => TurnStep.finalSummary,
      StudioTurnStatus.queued => null,
    };
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
      final step = _stepForTurnStatus(status);
      if (step != null) {
        recordStep(
          requestId,
          step: step,
          status: TurnStepStatus.running,
          title: title,
          detail: detail,
        );
      }
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
    recordStep(
      requestId,
      step: TurnStep.streaming,
      status: TurnStepStatus.running,
      title: 'Streaming response',
      detail: 'Circuit AI is returning assistant text.',
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
    recordStep(
      requestId,
      step: TurnStep.toolExecution,
      status: running ? TurnStepStatus.running : TurnStepStatus.completed,
      title: running ? 'Tool running' : 'Tool completed',
      detail: '$toolName: $detail',
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
    recordStep(
      requestId,
      step: TurnStep.approvalWait,
      status: TurnStepStatus.running,
      title: 'Waiting for approval',
      detail: request.preview,
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
    recordStep(
      requestId,
      step: TurnStep.approvalWait,
      status: switch (approvalState) {
        ApprovalRequestState.approved => TurnStepStatus.completed,
        ApprovalRequestState.rejected ||
        ApprovalRequestState.expired => TurnStepStatus.failed,
        ApprovalRequestState.pending => TurnStepStatus.running,
      },
      title: 'Approval ${approvalState.name}',
      detail: event.approvalPreview ?? event.detail,
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
    recordStep(
      requestId,
      step: TurnStep.toolExecution,
      status: switch (result.status) {
        ToolResultStatus.success => TurnStepStatus.completed,
        ToolResultStatus.waitingForApproval => TurnStepStatus.running,
        ToolResultStatus.cancelled => TurnStepStatus.skipped,
        ToolResultStatus.error ||
        ToolResultStatus.denied => TurnStepStatus.failed,
      },
      title: '${result.toolName} ${result.status.name}',
      detail: result.summary,
    );
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
    _recordProviderDiagnosticStep(requestId, diagnostic);
  }

  void _recordProviderDiagnosticStep(
    String requestId,
    ProviderLifecycleEvent diagnostic,
  ) {
    final detail = diagnostic.detail ?? diagnostic.kind.name;
    switch (diagnostic.kind) {
      case ProviderLifecycleEventKind.requestSent:
      case ProviderLifecycleEventKind.connected:
      case ProviderLifecycleEventKind.firstByte:
      case ProviderLifecycleEventKind.nonSseJson:
      case ProviderLifecycleEventKind.jsonFallback:
        recordStep(
          requestId,
          step: TurnStep.providerRequest,
          status: TurnStepStatus.running,
          title: _providerStepTitle(diagnostic.kind),
          detail: detail,
          allowArchived: true,
        );
      case ProviderLifecycleEventKind.firstTextDelta:
        recordStep(
          requestId,
          step: TurnStep.streaming,
          status: TurnStepStatus.running,
          title: 'First text received',
          detail: detail,
          allowArchived: true,
        );
      case ProviderLifecycleEventKind.firstToolDelta:
      case ProviderLifecycleEventKind.toolExposure:
      case ProviderLifecycleEventKind.toolOnly:
        recordStep(
          requestId,
          step: TurnStep.toolDecision,
          status: TurnStepStatus.running,
          title: _providerStepTitle(diagnostic.kind),
          detail: detail,
          allowArchived: true,
        );
      case ProviderLifecycleEventKind.outcomeRepair:
        recordStep(
          requestId,
          step: TurnStep.finalSummary,
          status: TurnStepStatus.running,
          title: 'Runtime repaired outcome',
          detail: detail,
          allowArchived: true,
        );
      case ProviderLifecycleEventKind.completed:
        recordStep(
          requestId,
          step: TurnStep.providerRequest,
          status: TurnStepStatus.completed,
          title: 'Provider completed',
          detail: detail,
          allowArchived: true,
        );
      case ProviderLifecycleEventKind.cancelled:
        recordStep(
          requestId,
          step: TurnStep.providerRequest,
          status: TurnStepStatus.skipped,
          title: 'Provider cancelled',
          detail: detail,
          allowArchived: true,
        );
      case ProviderLifecycleEventKind.authFailed:
      case ProviderLifecycleEventKind.noFirstByte:
      case ProviderLifecycleEventKind.noTextOrTool:
      case ProviderLifecycleEventKind.unavailableTool:
      case ProviderLifecycleEventKind.rateLimited:
      case ProviderLifecycleEventKind.malformedChunk:
      case ProviderLifecycleEventKind.malformedBytes:
      case ProviderLifecycleEventKind.streamEndedWithoutDone:
      case ProviderLifecycleEventKind.outcomeRejected:
      case ProviderLifecycleEventKind.failed:
      case ProviderLifecycleEventKind.timeout:
        recordStep(
          requestId,
          step: TurnStep.providerRequest,
          status: TurnStepStatus.failed,
          title: _providerStepTitle(diagnostic.kind),
          detail: detail,
          allowArchived: true,
        );
    }
  }

  String _providerStepTitle(ProviderLifecycleEventKind kind) {
    return switch (kind) {
      ProviderLifecycleEventKind.requestSent => 'Provider request sent',
      ProviderLifecycleEventKind.toolExposure => 'Tools exposed',
      ProviderLifecycleEventKind.authFailed => 'Authentication failed',
      ProviderLifecycleEventKind.connected => 'Provider connected',
      ProviderLifecycleEventKind.firstByte => 'First byte received',
      ProviderLifecycleEventKind.noFirstByte => 'No provider response bytes',
      ProviderLifecycleEventKind.firstTextDelta => 'First text received',
      ProviderLifecycleEventKind.firstToolDelta => 'First tool call received',
      ProviderLifecycleEventKind.nonSseJson => 'Non-streaming JSON response',
      ProviderLifecycleEventKind.jsonFallback => 'JSON fallback',
      ProviderLifecycleEventKind.toolOnly => 'Tool-only response',
      ProviderLifecycleEventKind.noTextOrTool => 'No model output',
      ProviderLifecycleEventKind.unavailableTool => 'Unavailable tool',
      ProviderLifecycleEventKind.rateLimited => 'Rate limited',
      ProviderLifecycleEventKind.malformedChunk => 'Malformed stream chunk',
      ProviderLifecycleEventKind.malformedBytes => 'Malformed response bytes',
      ProviderLifecycleEventKind.streamEndedWithoutDone => 'Stream ended early',
      ProviderLifecycleEventKind.outcomeRepair => 'Runtime repaired outcome',
      ProviderLifecycleEventKind.outcomeRejected => 'Invalid model outcome',
      ProviderLifecycleEventKind.completed => 'Provider completed',
      ProviderLifecycleEventKind.failed => 'Provider failed',
      ProviderLifecycleEventKind.cancelled => 'Provider cancelled',
      ProviderLifecycleEventKind.timeout => 'Provider timed out',
    };
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

  void startAcceptedPlanImplementation(
    String requestId,
    AcceptedPlanContext acceptedPlan,
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
    ref
        .read(studioThreadProvider.notifier)
        .updateTurn(
          turnRef.threadId,
          turnRef.turnId,
          acceptedPlanState: AcceptedPlanState.implementationStarted,
          acceptedPlanContext: turn.acceptedPlanContext ?? acceptedPlan,
          planTargetProgress: turn.planTargetProgress.isEmpty
              ? _planTargetProgressFor(acceptedPlan)
              : turn.planTargetProgress,
        );
  }

  void updatePlanTargetProgress(
    String requestId, {
    required String patchSetId,
    required Iterable<String> paths,
    required PlanTargetProgressState targetState,
    String? detail,
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
    if (turn == null || turn.planTargetProgress.isEmpty) return;
    final normalizedPaths = {for (final path in paths) _normalizePlanPath(path)}
      ..remove('');
    if (normalizedPaths.isEmpty) return;
    final updatedTargets = [
      for (final target in turn.planTargetProgress)
        if (_planTargetMatchesAnyPath(target.path, normalizedPaths))
          target.copyWith(
            state: targetState,
            patchSetId: patchSetId,
            detail: detail,
          )
        else
          target,
    ];
    ref
        .read(studioThreadProvider.notifier)
        .updateTurn(
          turnRef.threadId,
          turnRef.turnId,
          planTargetProgress: updatedTargets,
        );
  }

  void recordPatchTransaction(
    String requestId, {
    required String patchSetId,
    required String title,
    required String detail,
    Iterable<String> paths = const [],
    PatchApplyStatus? applyStatus,
  }) {
    final turnRef = state.archivedRefForRequest(requestId);
    if (turnRef == null) return;
    final actionableDetail = applyStatus == PatchApplyStatus.conflict
        ? _patchConflictRecoveryDetail(detail)
        : detail;
    recordStep(
      requestId,
      step: TurnStep.patchProposal,
      status: switch (applyStatus) {
        PatchApplyStatus.applied => TurnStepStatus.completed,
        PatchApplyStatus.revisionRequested => TurnStepStatus.queued,
        PatchApplyStatus.conflict ||
        PatchApplyStatus.failed ||
        PatchApplyStatus.rejected => TurnStepStatus.failed,
        PatchApplyStatus.restored => TurnStepStatus.completed,
        null => TurnStepStatus.running,
      },
      title: title,
      detail: actionableDetail,
      allowArchived: true,
    );
    if (applyStatus == PatchApplyStatus.applied &&
        _patchTransactionRequestsVerification(actionableDetail)) {
      recordStep(
        requestId,
        step: TurnStep.verification,
        status: TurnStepStatus.queued,
        title: 'Verification ready',
        detail: _verificationStepDetail(actionableDetail),
        allowArchived: true,
      );
    }
    final thread = ref
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == turnRef.threadId)
        .firstOrNull;
    final turn = thread?.turns
        .where((candidate) => candidate.id == turnRef.turnId)
        .firstOrNull;
    final touchedPaths = paths.isNotEmpty
        ? paths.map(_normalizePlanPath).where((path) => path.isNotEmpty)
        : _pathsFromPatchTransactionDetail(detail);
    final isRevisionTransaction = _isPatchRevisionTransaction(
      title,
      applyStatus,
    );
    final progressState = isRevisionTransaction
        ? PlanTargetProgressState.proposed
        : switch (applyStatus) {
            PatchApplyStatus.applied => PlanTargetProgressState.applied,
            PatchApplyStatus.conflict => PlanTargetProgressState.conflict,
            PatchApplyStatus.failed => PlanTargetProgressState.blocked,
            PatchApplyStatus.rejected => PlanTargetProgressState.skipped,
            PatchApplyStatus.revisionRequested =>
              PlanTargetProgressState.proposed,
            PatchApplyStatus.restored => PlanTargetProgressState.proposed,
            null => null,
          };
    if (turn != null) {
      if (progressState != null && touchedPaths.isNotEmpty) {
        updatePlanTargetProgress(
          requestId,
          patchSetId: patchSetId,
          paths: touchedPaths,
          targetState: progressState,
          detail: title,
        );
        _propagateContinuationTargetProgress(
          threadId: turnRef.threadId,
          sourceTurnId: turnRef.turnId,
          continuationPlanId: turn.acceptedPlanContext?.patchSetId,
          patchSetId: patchSetId,
          paths: touchedPaths,
          targetState: progressState,
          detail: title,
        );
      }
    }
    final latestThread = ref
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == turnRef.threadId)
        .firstOrNull;
    final latestTurn = latestThread?.turns
        .where((candidate) => candidate.id == turnRef.turnId)
        .firstOrNull;
    if (applyStatus == PatchApplyStatus.applied) {
      final continuationDetail = _continuationStepDetail(latestTurn ?? turn);
      if (continuationDetail != null) {
        recordStep(
          requestId,
          step: TurnStep.continuation,
          status: TurnStepStatus.queued,
          title: 'Continue next batch',
          detail: continuationDetail,
          allowArchived: true,
        );
      }
    }
    final acceptedPlanState = _acceptedPlanStateForPatchApply(
      latestTurn ?? turn,
      applyStatus,
      title: title,
    );
    if (acceptedPlanState != null) {
      final notifier = ref.read(studioThreadProvider.notifier);
      if (acceptedPlanState == AcceptedPlanState.implemented) {
        notifier.updateTurn(
          turnRef.threadId,
          turnRef.turnId,
          acceptedPlanState: acceptedPlanState,
          status: StudioTurnStatus.completed,
          lastError: null,
          complete: true,
        );
      } else {
        final shouldCompleteTurn =
            acceptedPlanState == AcceptedPlanState.patchProposed;
        if (shouldCompleteTurn) {
          notifier.updateTurn(
            turnRef.threadId,
            turnRef.turnId,
            acceptedPlanState: acceptedPlanState,
            status: StudioTurnStatus.completed,
            lastError: null,
            complete: true,
          );
        } else {
          notifier.updateTurn(
            turnRef.threadId,
            turnRef.turnId,
            acceptedPlanState: acceptedPlanState,
          );
        }
      }
    }
    final transactionDetail = _patchTransactionDetailWithPlanProgress(
      latestTurn ?? turn,
      actionableDetail,
      applyStatus,
    );
    ref
        .read(studioThreadProvider.notifier)
        .upsertTurnEvent(
          turnRef.threadId,
          turnRef.turnId,
          StudioTurnEvent.completionSummary(
            id: _patchTransactionEventId(
              turnId: turnRef.turnId,
              patchSetId: patchSetId,
              title: title,
              touchedPaths: touchedPaths,
              applyStatus: applyStatus,
            ),
            turnId: turnRef.turnId,
            requestId: requestId,
            threadId: turnRef.threadId,
            title: title,
            detail: transactionDetail,
            patchSetId: patchSetId,
          ),
        );
  }

  void recordCommandRunResult(
    String requestId, {
    required String commandRunId,
    required String command,
    required String status,
    String output = '',
    int? exitCode,
  }) {
    final activeTurnRef = state.refForRequest(requestId);
    final archivedTurnRef = state.archivedRefForRequest(requestId);
    final turnRef = activeTurnRef ?? archivedTurnRef;
    if (turnRef == null) return;
    final allowArchived = activeTurnRef == null;
    final statusLabel = status.trim().isEmpty ? 'completed' : status.trim();
    final normalizedStatus = statusLabel.toLowerCase();
    final succeeded =
        normalizedStatus == 'succeeded' ||
        normalizedStatus == 'success' ||
        normalizedStatus == 'completed';
    final title = succeeded ? 'Ran command' : 'Command $statusLabel';
    final detail = [
      command.trim().isEmpty ? 'Command completed.' : 'Command: $command',
      if (exitCode != null) 'Exit code: $exitCode',
      if (output.trim().isNotEmpty) _truncateCommandOutput(output.trim()),
    ].join('\n');
    final stepStatus = succeeded
        ? TurnStepStatus.completed
        : TurnStepStatus.failed;
    recordStep(
      requestId,
      step: TurnStep.commandRun,
      status: stepStatus,
      title: title,
      detail: detail,
      allowArchived: allowArchived,
    );
    recordStep(
      requestId,
      step: TurnStep.verification,
      status: stepStatus,
      title: title,
      detail: detail,
      allowArchived: allowArchived,
    );
    ref
        .read(studioThreadProvider.notifier)
        .upsertTurnEvent(
          turnRef.threadId,
          turnRef.turnId,
          StudioTurnEvent.completionSummary(
            id: 'command-run-${turnRef.turnId}-$commandRunId',
            turnId: turnRef.turnId,
            requestId: requestId,
            threadId: turnRef.threadId,
            title: title,
            detail: detail,
          ),
        );
  }

  String _truncateCommandOutput(String output) {
    if (output.length <= 1600) return output;
    return '${output.substring(0, 1200)}\n... (${output.length - 1400} chars omitted) ...\n${output.substring(output.length - 200)}';
  }

  String _patchConflictRecoveryDetail(String detail) {
    final normalized = detail.toLowerCase();
    if (normalized.contains('rebase') || normalized.contains('revise')) {
      return detail;
    }
    return [
      detail,
      'Ask Circuit to rebase the proposal against the current file contents before applying again.',
    ].where((line) => line.trim().isNotEmpty).join('\n');
  }

  String _patchTransactionEventId({
    required String turnId,
    required String patchSetId,
    required String title,
    required Iterable<String> touchedPaths,
    required PatchApplyStatus? applyStatus,
  }) {
    final statusPart = applyStatus?.name ?? _stableEventIdPart(title);
    if (applyStatus == PatchApplyStatus.conflict) {
      final pathPart = touchedPaths
          .map(_normalizePlanPath)
          .where((path) => path.isNotEmpty)
          .map(_stableEventIdPart)
          .join('-');
      if (pathPart.isNotEmpty) {
        return 'patch-transaction-$turnId-$statusPart-$pathPart';
      }
    }
    return 'patch-transaction-$turnId-$patchSetId-$statusPart';
  }

  String _patchTransactionDetailWithPlanProgress(
    StudioTurn? turn,
    String detail,
    PatchApplyStatus? applyStatus,
  ) {
    if (turn == null ||
        applyStatus != PatchApplyStatus.applied ||
        turn.acceptedPlanState == AcceptedPlanState.none ||
        turn.planTargetProgress.isEmpty) {
      return detail;
    }
    final remaining = turn.planTargetProgress
        .where(
          (target) =>
              target.state == PlanTargetProgressState.pending ||
              target.state == PlanTargetProgressState.proposed ||
              target.state == PlanTargetProgressState.conflict ||
              target.state == PlanTargetProgressState.blocked,
        )
        .toList(growable: false);
    if (remaining.isEmpty) {
      return [
        detail,
        'Accepted plan progress: all planned targets are complete.',
      ].where((line) => line.trim().isNotEmpty).join('\n');
    }
    final preview = remaining.take(4).map((target) => target.path).join(', ');
    final hiddenCount = remaining.length > 4 ? remaining.length - 4 : 0;
    final previewText = [
      if (preview.isNotEmpty) preview,
      if (hiddenCount > 0) '+$hiddenCount more',
    ].join(hiddenCount > 0 && preview.isNotEmpty ? ', ' : '');
    return [
      detail,
      'Next batch: ${_acceptedPlanTargetsNeedWorkLabel(remaining.length)}${previewText.isEmpty ? '' : ' ($previewText)'}. Use Continue next batch to keep implementing the accepted plan.',
    ].where((line) => line.trim().isNotEmpty).join('\n');
  }

  String? _continuationStepDetail(StudioTurn? turn) {
    if (turn == null ||
        turn.acceptedPlanState == AcceptedPlanState.none ||
        turn.planTargetProgress.isEmpty) {
      return null;
    }
    final remaining = turn.planTargetProgress
        .where(
          (target) =>
              target.state == PlanTargetProgressState.pending ||
              target.state == PlanTargetProgressState.proposed ||
              target.state == PlanTargetProgressState.conflict ||
              target.state == PlanTargetProgressState.blocked,
        )
        .toList(growable: false);
    if (remaining.isEmpty) return null;
    final preview = remaining.take(4).map((target) => target.path).join(', ');
    final hiddenCount = remaining.length > 4 ? remaining.length - 4 : 0;
    final previewText = [
      if (preview.isNotEmpty) preview,
      if (hiddenCount > 0) '+$hiddenCount more',
    ].join(hiddenCount > 0 && preview.isNotEmpty ? ', ' : '');
    return [
      '${_acceptedPlanTargetsNeedWorkLabel(remaining.length)}.',
      if (previewText.isNotEmpty) 'Remaining: $previewText.',
      'Use Continue next batch to keep implementing the accepted plan.',
    ].join(' ');
  }

  String _acceptedPlanTargetsNeedWorkLabel(int count) {
    return '$count accepted-plan target${count == 1 ? '' : 's'} '
        '${count == 1 ? 'still needs' : 'still need'} work';
  }

  AcceptedPlanState? _acceptedPlanStateForPatchApply(
    StudioTurn? turn,
    PatchApplyStatus? applyStatus, {
    required String title,
  }) {
    final current = turn?.acceptedPlanState ?? AcceptedPlanState.none;
    if (current == AcceptedPlanState.none || applyStatus == null) return null;
    if (_isPatchRevisionTransaction(title, applyStatus)) {
      return AcceptedPlanState.patchProposed;
    }
    return switch (applyStatus) {
      PatchApplyStatus.applied =>
        _allAcceptedPlanTargetsTerminal(turn)
            ? AcceptedPlanState.implemented
            : AcceptedPlanState.patchProposed,
      PatchApplyStatus.conflict => AcceptedPlanState.patchProposed,
      PatchApplyStatus.failed => AcceptedPlanState.failed,
      PatchApplyStatus.rejected => AcceptedPlanState.blockedForMissingContext,
      PatchApplyStatus.revisionRequested => AcceptedPlanState.patchProposed,
      PatchApplyStatus.restored => AcceptedPlanState.patchProposed,
    };
  }

  void _propagateContinuationTargetProgress({
    required String threadId,
    required String sourceTurnId,
    required String? continuationPlanId,
    required String patchSetId,
    required Iterable<String> paths,
    required PlanTargetProgressState targetState,
    required String detail,
  }) {
    final originalPlanId = _sourcePlanIdForContinuation(continuationPlanId);
    if (originalPlanId == null) return;
    final normalizedPaths = paths
        .map(_normalizePlanPath)
        .where((path) => path.isNotEmpty)
        .toSet();
    if (normalizedPaths.isEmpty) return;
    final thread = ref
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == threadId)
        .firstOrNull;
    if (thread == null) return;
    for (final candidate in thread.turns) {
      if (candidate.id == sourceTurnId) continue;
      if (candidate.acceptedPlanContext?.patchSetId != originalPlanId) {
        continue;
      }
      if (candidate.planTargetProgress.isEmpty) continue;
      var changed = false;
      final updatedTargets = <PlanTargetProgress>[];
      for (final target in candidate.planTargetProgress) {
        if (_planTargetMatchesAnyPath(target.path, normalizedPaths)) {
          changed = true;
          updatedTargets.add(
            target.copyWith(
              state: targetState,
              patchSetId: patchSetId,
              detail: detail,
            ),
          );
        } else {
          updatedTargets.add(target);
        }
      }
      if (!changed) continue;
      final nextState = _allTargetsTerminal(updatedTargets)
          ? AcceptedPlanState.implemented
          : AcceptedPlanState.patchProposed;
      ref
          .read(studioThreadProvider.notifier)
          .updateTurn(
            threadId,
            candidate.id,
            acceptedPlanState: nextState,
            planTargetProgress: updatedTargets,
            status: StudioTurnStatus.completed,
            lastError: null,
            complete: true,
          );
    }
  }

  String? _sourcePlanIdForContinuation(String? planId) {
    if (planId == null) return null;
    const marker = ':next-batch';
    final index = planId.indexOf(marker);
    if (index <= 0) return null;
    return planId.substring(0, index);
  }

  bool _isPatchRevisionTransaction(
    String title,
    PatchApplyStatus? applyStatus,
  ) {
    if (applyStatus != PatchApplyStatus.rejected &&
        applyStatus != PatchApplyStatus.revisionRequested) {
      return false;
    }
    return title.trim().toLowerCase() == 'patch revision requested';
  }

  bool _allAcceptedPlanTargetsTerminal(StudioTurn? turn) {
    final targets = turn?.planTargetProgress ?? const <PlanTargetProgress>[];
    return _allTargetsTerminal(targets);
  }

  bool _allTargetsTerminal(List<PlanTargetProgress> targets) {
    if (targets.isEmpty) return true;
    return targets.every((target) {
      return switch (target.state) {
        PlanTargetProgressState.applied ||
        PlanTargetProgressState.skipped => true,
        PlanTargetProgressState.conflict ||
        PlanTargetProgressState.pending ||
        PlanTargetProgressState.proposed ||
        PlanTargetProgressState.blocked => false,
      };
    });
  }

  String _stableEventIdPart(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized.isEmpty ? 'event' : normalized;
  }

  List<PlanTargetProgress> _planTargetProgressFor(
    AcceptedPlanContext? acceptedPlanContext,
  ) {
    if (acceptedPlanContext == null) return const [];
    final targets = acceptedPlanContext.plannedTargets.isNotEmpty
        ? acceptedPlanContext.plannedTargets
        : [
            for (final file in acceptedPlanContext.plannedFiles)
              PlannedFileTarget.fromDisplayString(file),
          ];
    final seen = <String>{};
    return [
      for (final target in targets)
        if (target.path.trim().isNotEmpty &&
            seen.add(_normalizePlanPath(target.path)))
          PlanTargetProgress.fromTarget(target),
    ];
  }

  List<String> _pathsFromPatchTransactionDetail(String detail) {
    final paths = <String>[];
    final filesLine = RegExp(
      r'Here.s what changed:\s*([^\n]+)',
    ).firstMatch(detail);
    if (filesLine != null) {
      paths.addAll(
        filesLine
            .group(1)!
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty),
      );
    }
    final conflictPath = RegExp(
      r'(?:File changed since proposal|File already exists|File missing for modify|File missing for delete|Patch does not change file content|Patch target is a directory|Patch is missing expected prior content for|Patch is missing full target content for|Secret or environment file paths cannot be patched):\s*([^\n]+)',
    ).firstMatch(detail);
    if (conflictPath != null) {
      paths.add(conflictPath.group(1)!.trim());
    }
    final proseConflictPath = _pathFromPatchConflictProse(detail);
    if (proseConflictPath != null) {
      paths.add(proseConflictPath);
    }
    return paths
        .map(_normalizePlanPath)
        .where((path) => path.isNotEmpty)
        .toList();
  }

  String? _pathFromPatchConflictProse(String detail) {
    final patterns = [
      RegExp(
        r'\bfor\s+([^\n]+?)(?:\. Ask\b|\. Revise\b| before\b| on line\b|$)',
        caseSensitive: false,
      ),
      RegExp(r'\bin\s+([^\n]+?)\s+on line\b', caseSensitive: false),
      RegExp(r'\bPatch leaves\s+([^\n]+?)\s+empty\b', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(detail);
      final path = _cleanExtractedPatchPath(match?.group(1));
      if (path != null) return path;
    }
    return null;
  }

  String? _cleanExtractedPatchPath(String? value) {
    final initial = value?.trim();
    if (initial == null || initial.isEmpty) return null;
    var path = initial
        .replaceAll(RegExp(r'''^[`"']+|[`"']+$'''), '')
        .replaceAll(RegExp(r'\s*\([^)]*\)$'), '')
        .trim();
    while (path.isNotEmpty && ',.;:'.contains(path[path.length - 1])) {
      path = path.substring(0, path.length - 1).trim();
    }
    if (path.isEmpty) return null;
    if (path.contains(' ') && !path.contains('/')) return null;
    return path;
  }

  bool _patchTransactionRequestsVerification(String detail) {
    final normalized = detail.toLowerCase();
    return normalized.contains('suggested checks:') ||
        normalized.contains('recommended next step: run verification') ||
        normalized.contains('verification was requested');
  }

  String _verificationStepDetail(String detail) {
    final lines = detail
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where(
          (line) =>
              line.toLowerCase().startsWith('suggested checks:') ||
              line.toLowerCase().startsWith('recommended next step:') ||
              line.toLowerCase().startsWith('verification was requested'),
        )
        .toList(growable: false);
    return lines.isEmpty
        ? 'Patch was applied and is ready for verification.'
        : lines.join('\n');
  }

  String _normalizePlanPath(String value) {
    return value.trim().replaceAll('\\', '/').replaceAll(RegExp(r'^\./+'), '');
  }

  bool _planTargetMatchesAnyPath(String targetPath, Set<String> touchedPaths) {
    final normalizedTarget = _normalizePlanPath(
      targetPath,
    ).replaceAll(RegExp(r'/+$'), '');
    if (normalizedTarget.isEmpty) return false;
    for (final touched in touchedPaths) {
      final normalizedTouched = _normalizePlanPath(
        touched,
      ).replaceAll(RegExp(r'/+$'), '');
      if (normalizedTouched == normalizedTarget ||
          normalizedTouched.startsWith('$normalizedTarget/')) {
        return true;
      }
    }
    return false;
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
    recordStep(
      requestId,
      step: TurnStep.finalSummary,
      status: TurnStepStatus.completed,
      title: 'Turn completed',
      detail: summary ?? content,
      allowArchived: allowArchived,
    );
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
    recordStep(
      requestId,
      step: TurnStep.finalSummary,
      status: TurnStepStatus.failed,
      title: 'Turn failed',
      detail: errorDetail,
    );
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
    recordStep(
      requestId,
      step: TurnStep.finalSummary,
      status: TurnStepStatus.skipped,
      title: 'Turn cancelled',
      detail: message,
    );
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
      ProviderLifecycleEventKind.outcomeRejected ||
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
      ProviderLifecycleEventKind.outcomeRejected => 'Invalid model outcome',
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
