import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/confirmation_request.dart';
import '../models/accepted_plan_context.dart';
import '../models/agent_tool_permission.dart';
import '../models/context_pack.dart';
import '../models/provider_lifecycle_event.dart';
import '../models/reviewed_edit.dart';
import '../models/studio_thread.dart';
import '../models/studio_turn.dart';
import '../models/tool_result_envelope.dart';
import '../models/turn_intent.dart';
import 'studio_command_log_store.dart';
import 'studio_thread_provider.dart';

part 'studio_turn_streaming.dart';
part 'studio_turn_patch_transactions.dart';
part 'studio_turn_state.dart';

const _uuid = Uuid();

final studioCommandLogStoreProvider = Provider<StudioCommandLogStore>(
  (ref) => StudioCommandLogStore(),
);

class StudioTurnController extends Notifier<StudioTurnState>
    with StudioTurnStreaming, StudioTurnPatchTransactions {
  @override
  StudioTurnState build() {
    ref.onDispose(disposeAssistantDeltas);
    return const StudioTurnState();
  }

  StudioTurn registerTurn({
    required String requestId,
    required String threadId,
    required String? taskId,
    required String userMessageId,
    required String prompt,
    String? modelPrompt,
    String? taskTitle,
    required String model,
    required StudioContextSummary contextSummary,
    TurnIntent intent = TurnIntent.code,
    IntentRoutingDecision? intentRouting,
    AcceptedPlanState acceptedPlanState = AcceptedPlanState.none,
    AcceptedPlanContext? acceptedPlanContext,
    ContextRetrievalResult? contextRetrieval,
    bool userMessageTranscriptVisible = true,
    bool isResearch = false,
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
      modelPrompt: modelPrompt,
      taskTitle: taskTitle,
      model: model,
      intent: intent,
      intentRouting: intentRouting,
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
        if (isResearch)
          TurnStepRecord(
            step: TurnStep.researchPlan,
            status: TurnStepStatus.completed,
            title: 'Research plan ready',
            detail:
                'Find direct sources, assess coverage and freshness, then produce a cited evidence report.',
            startedAt: now.add(const Duration(milliseconds: 1)),
            completedAt: now.add(const Duration(milliseconds: 1)),
          ),
        if (isResearch)
          TurnStepRecord(
            step: TurnStep.sourceAcquisition,
            status: TurnStepStatus.queued,
            title: 'Source acquisition queued',
            detail: 'Waiting to search and fetch approved direct sources.',
            startedAt: now.add(const Duration(milliseconds: 2)),
          ),
        if (isResearch)
          TurnStepRecord(
            step: TurnStep.evidenceReview,
            status: TurnStepStatus.queued,
            title: 'Evidence review queued',
            detail:
                'Source coverage and citation gaps will be captured before the report is finalized.',
            startedAt: now.add(const Duration(milliseconds: 3)),
          ),
        TurnStepRecord(
          step: TurnStep.providerRequest,
          status: TurnStepStatus.queued,
          title: 'Provider queued',
          detail: model,
          startedAt: now.add(Duration(milliseconds: isResearch ? 4 : 1)),
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
        if (intentRouting != null)
          StudioTurnEvent.intentRouting(
            turnId: turnId,
            requestId: requestId,
            threadId: threadId,
            decision: intentRouting,
            timestamp: now.add(const Duration(milliseconds: 2)),
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

  @override
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
      StudioTurnStatus.reviewingPatch => TurnStep.patchProposal,
      StudioTurnStatus.verifying => TurnStep.verification,
      StudioTurnStatus.completed => TurnStep.finalSummary,
      StudioTurnStatus.failed ||
      StudioTurnStatus.cancelled ||
      StudioTurnStatus.interrupted => TurnStep.finalSummary,
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
    ApprovalRequestState approvalState, {
    ApprovalGrant? approvalGrant,
  }) {
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
          event.copyWith(
            approvalState: approvalState,
            approvalGrant: approvalGrant,
          ),
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
      detail: [
        event.approvalPreview ?? event.detail,
        if (approvalState == ApprovalRequestState.approved &&
            approvalGrant != null)
          'Scope: ${approvalGrant.name}.',
      ].join('\n'),
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
    final resultForStorage = compactCommandToolResult(
      result: result,
      store: ref.read(studioCommandLogStoreProvider),
      requestId: requestId,
      turnId: turnRef.turnId,
    );
    final results = [
      ...turn.toolResults.where(
        (candidate) => candidate.toolCallId != resultForStorage.toolCallId,
      ),
      resultForStorage,
    ];
    ref
        .read(studioThreadProvider.notifier)
        .updateTurn(turnRef.threadId, turnRef.turnId, toolResults: results);
    recordStep(
      requestId,
      step: TurnStep.toolExecution,
      status: switch (resultForStorage.status) {
        ToolResultStatus.success => TurnStepStatus.completed,
        ToolResultStatus.waitingForApproval => TurnStepStatus.running,
        ToolResultStatus.cancelled => TurnStepStatus.skipped,
        ToolResultStatus.error ||
        ToolResultStatus.denied => TurnStepStatus.failed,
      },
      title: '${resultForStorage.toolName} ${resultForStorage.status.name}',
      detail: resultForStorage.summary,
    );
  }

  void recordResearchToolResult(String requestId, ToolResultEnvelope result) {
    final turnRef = state.refForRequest(requestId);
    if (turnRef == null) return;
    final turn = _turnFor(turnRef.threadId, turnRef.turnId);
    if (turn == null ||
        !turn.steps.any((step) => step.step == TurnStep.researchPlan)) {
      return;
    }
    if (result.toolName == 'web_search') {
      recordStep(
        requestId,
        step: TurnStep.sourceAcquisition,
        status: TurnStepStatus.running,
        title: 'Source discovery running',
        detail:
            'Search candidates received; fetching direct sources under policy approval.',
      );
      markProgress(
        requestId,
        title: 'Researching sources',
        detail:
            'Search candidates received; selecting direct sources to fetch.',
      );
      return;
    }
    if (result.toolName != 'web_fetch') return;
    final fetched = turn.toolResults
        .where(
          (candidate) =>
              candidate.toolName == 'web_fetch' &&
              candidate.status == ToolResultStatus.success,
        )
        .length;
    recordStep(
      requestId,
      step: TurnStep.sourceAcquisition,
      status: TurnStepStatus.running,
      title: 'Direct sources acquired',
      detail:
          '$fetched direct ${fetched == 1 ? 'source' : 'sources'} fetched; checking evidence coverage.',
    );
    recordStep(
      requestId,
      step: TurnStep.evidenceReview,
      status: TurnStepStatus.running,
      title: 'Evidence review running',
      detail: 'Matching report statements to persisted direct sources.',
    );
    markProgress(
      requestId,
      title: 'Researching sources',
      detail:
          '$fetched direct ${fetched == 1 ? 'source' : 'sources'} fetched; reviewing coverage.',
    );
  }

  void completeResearch(
    String requestId, {
    required int directSourceCount,
    required int unsupportedClaimCount,
    required int freshnessGapCount,
  }) {
    final turnRef = state.refForRequest(requestId);
    if (turnRef == null) return;
    final turn = _turnFor(turnRef.threadId, turnRef.turnId);
    if (turn == null ||
        !turn.steps.any((step) => step.step == TurnStep.researchPlan)) {
      return;
    }
    recordStep(
      requestId,
      step: TurnStep.sourceAcquisition,
      status: TurnStepStatus.completed,
      title: 'Source acquisition complete',
      detail:
          '$directSourceCount direct ${directSourceCount == 1 ? 'source' : 'sources'} persisted for review.',
    );
    recordStep(
      requestId,
      step: TurnStep.evidenceReview,
      status: TurnStepStatus.completed,
      title: 'Evidence table ready',
      detail:
          '$unsupportedClaimCount unsupported ${unsupportedClaimCount == 1 ? 'statement' : 'statements'} · $freshnessGapCount freshness ${freshnessGapCount == 1 ? 'review' : 'reviews'}.',
    );
    markProgress(
      requestId,
      title: 'Research evidence ready',
      detail:
          'Saved a sourced evidence artifact with $directSourceCount direct ${directSourceCount == 1 ? 'source' : 'sources'}.',
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
    if (diagnostic.kind == ProviderLifecycleEventKind.outcomeRepair &&
        _isResearchRequest(requestId)) {
      recordStep(
        requestId,
        step: TurnStep.sourceAcquisition,
        status: TurnStepStatus.running,
        title: 'Independent-source retry',
        detail:
            'One bounded retry is acquiring any missing direct corroboration.',
        allowArchived: true,
      );
      markProgress(
        requestId,
        title: 'Retrying source acquisition',
        detail:
            'Checking one more approved source path before finalizing evidence.',
      );
      return;
    }
    switch (diagnostic.kind) {
      case ProviderLifecycleEventKind.requestSent:
      case ProviderLifecycleEventKind.reconnecting:
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

  bool _isResearchRequest(String requestId) {
    final turnRef = state.refForRequest(requestId);
    if (turnRef == null) return false;
    final turn = _turnFor(turnRef.threadId, turnRef.turnId);
    return turn?.steps.any((step) => step.step == TurnStep.researchPlan) ??
        false;
  }

  String _providerStepTitle(ProviderLifecycleEventKind kind) {
    return switch (kind) {
      ProviderLifecycleEventKind.requestSent => 'Provider request sent',
      ProviderLifecycleEventKind.toolExposure => 'Tools exposed',
      ProviderLifecycleEventKind.authFailed => 'Authentication failed',
      ProviderLifecycleEventKind.reconnecting => 'Refreshing authentication',
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

  void complete(
    String requestId, {
    required String content,
    String? summary,
    StudioTurnOutcome? finalOutcome,
    bool allowArchived = false,
  }) {
    _flushAssistantDelta(requestId);
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
    final completedTurn = _turnFor(turnRef.threadId, turnRef.turnId);
    notifier.updateTurn(
      turnRef.threadId,
      turnRef.turnId,
      status: StudioTurnStatus.completed,
      assistantDraft: '',
      complete: true,
      expirePendingApprovals: true,
      finalOutcome:
          finalOutcome ??
          (completedTurn == null
              ? StudioTurnOutcome.answered
              : inferStudioTurnOutcome(
                  completedTurn.copyWith(status: StudioTurnStatus.completed),
                )),
    );
    if (state.activeByRequestId.containsKey(requestId)) {
      _clearPendingAssistantDelta(requestId);
      _archive(requestId);
    }
  }

  void fail(
    String requestId,
    String message, {
    StudioTurnOutcome finalOutcome = StudioTurnOutcome.failed,
  }) {
    _flushAssistantDelta(requestId);
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
      finalOutcome: finalOutcome,
    );
    _clearPendingAssistantDelta(requestId);
    _archive(requestId);
  }

  void cancel(String requestId, String message) {
    _flushAssistantDelta(requestId);
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
      finalOutcome: StudioTurnOutcome.cancelled,
    );
    _clearPendingAssistantDelta(requestId);
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

  StudioTurn? _turnFor(String threadId, String turnId) {
    final thread = ref
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == threadId)
        .firstOrNull;
    return thread?.turns
        .where((candidate) => candidate.id == turnId)
        .firstOrNull;
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
