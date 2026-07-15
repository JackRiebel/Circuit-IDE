import '../enums/message_role.dart';
import 'accepted_plan_context.dart';
import 'agent_tool_permission.dart';
import 'chat_message.dart';
import 'confirmation_request.dart';
import 'context_pack.dart';
import 'provider_lifecycle_event.dart';
import 'reviewed_edit.dart';
import 'studio_failure_taxonomy.dart';
import 'studio_thread.dart';
import 'tool_result_envelope.dart';
import 'turn_intent.dart';

enum TurnStep {
  preflight,
  contextBuild,
  researchPlan,
  sourceAcquisition,
  evidenceReview,
  providerRequest,
  streaming,
  toolDecision,
  approvalWait,
  toolExecution,
  commandRun,
  patchProposal,
  continuation,
  verification,
  finalSummary,
}

enum TurnStepStatus { queued, running, completed, failed, skipped }

class TurnStepRecord {
  final TurnStep step;
  final TurnStepStatus status;
  final String title;
  final String detail;
  final DateTime startedAt;
  final DateTime? completedAt;

  const TurnStepRecord({
    required this.step,
    required this.status,
    required this.title,
    this.detail = '',
    required this.startedAt,
    this.completedAt,
  });

  TurnStepRecord copyWith({
    TurnStepStatus? status,
    String? title,
    String? detail,
    DateTime? startedAt,
    Object? completedAt = _sentinel,
  }) {
    return TurnStepRecord(
      step: step,
      status: status ?? this.status,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      startedAt: startedAt ?? this.startedAt,
      completedAt: identical(completedAt, _sentinel)
          ? this.completedAt
          : completedAt as DateTime?,
    );
  }

  Map<String, dynamic> toJson() => {
    'step': step.name,
    'status': status.name,
    'title': title,
    'detail': detail,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };

  static TurnStepRecord? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    try {
      return TurnStepRecord(
        step: TurnStep.values.firstWhere(
          (candidate) => candidate.name == json['step'],
          orElse: () => TurnStep.providerRequest,
        ),
        status: TurnStepStatus.values.firstWhere(
          (candidate) => candidate.name == json['status'],
          orElse: () => TurnStepStatus.running,
        ),
        title: json['title'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        startedAt:
            DateTime.tryParse(json['startedAt'] as String? ?? '') ??
            DateTime.now(),
        completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
      );
    } catch (_) {
      return null;
    }
  }
}

enum StudioTurnStatus {
  queued,
  buildingContext,
  sent,
  waitingForModel,
  streaming,
  toolRunning,
  waitingForApproval,
  reviewingPatch,
  verifying,
  completed,
  failed,
  cancelled,
  interrupted,
}

/// The durable user-facing result of a terminal Studio turn. Provider prose is
/// supporting evidence; it is never the authority for what the product claims
/// happened.
enum StudioTurnOutcome {
  answered,
  createdArtifact,
  preparedChanges,
  appliedChanges,
  verified,
  blocked,
  failed,
  cancelled,
}

String studioTurnOutcomeTitle(StudioTurnOutcome outcome) => switch (outcome) {
  StudioTurnOutcome.answered => 'Answered',
  StudioTurnOutcome.createdArtifact => 'Created artifact',
  StudioTurnOutcome.preparedChanges => 'Prepared changes',
  StudioTurnOutcome.appliedChanges => 'Applied changes',
  StudioTurnOutcome.verified => 'Verified',
  StudioTurnOutcome.blocked => 'Blocked',
  StudioTurnOutcome.failed => 'Failed',
  StudioTurnOutcome.cancelled => 'Cancelled',
};

StudioTurnOutcome? inferStudioTurnOutcome(StudioTurn turn) {
  if (turn.finalOutcome != null) return turn.finalOutcome;
  return switch (turn.status) {
    StudioTurnStatus.failed =>
      _turnWasBlocked(turn)
          ? StudioTurnOutcome.blocked
          : StudioTurnOutcome.failed,
    StudioTurnStatus.cancelled => StudioTurnOutcome.cancelled,
    StudioTurnStatus.interrupted => StudioTurnOutcome.failed,
    StudioTurnStatus.completed => _completedTurnOutcome(turn),
    _ => null,
  };
}

StudioTurnOutcome _completedTurnOutcome(StudioTurn turn) {
  final deniedTool = turn.toolResults.any(
    (result) => result.status == ToolResultStatus.denied,
  );
  if (deniedTool) return StudioTurnOutcome.blocked;
  final failedVerification =
      turn.steps.any(
        (step) =>
            step.step == TurnStep.verification &&
            step.status == TurnStepStatus.failed,
      ) ||
      turn.toolResults.any(
        (result) =>
            result.toolName == 'run_command' &&
            (result.status == ToolResultStatus.error ||
                result.status == ToolResultStatus.cancelled),
      );
  if (failedVerification) return StudioTurnOutcome.failed;
  if (turn.intent == TurnIntent.verify ||
      turn.steps.any(
        (step) =>
            step.step == TurnStep.verification &&
            step.status == TurnStepStatus.completed,
      )) {
    return StudioTurnOutcome.verified;
  }
  if (turn.toolResults.any((result) => result.artifacts.isNotEmpty)) {
    return StudioTurnOutcome.createdArtifact;
  }
  // Completion summaries are provider-facing prose and may be absent, stale,
  // or overly broad. Durable outcome classification must use only typed turn
  // state that the runtime owns.
  final appliedPatch =
      turn.acceptedPlanState == AcceptedPlanState.implemented ||
      turn.planTargetProgress.any(
        (target) => target.state == PlanTargetProgressState.applied,
      );
  if (appliedPatch) return StudioTurnOutcome.appliedChanges;
  final preparedPatch =
      turn.intent == TurnIntent.plan ||
      turn.acceptedPlanState == AcceptedPlanState.patchProposed ||
      turn.toolResults.any(
        (result) =>
            result.toolName == 'propose_patch' ||
            result.toolName == 'create_patch',
      );
  return preparedPatch
      ? StudioTurnOutcome.preparedChanges
      : StudioTurnOutcome.answered;
}

bool _turnWasBlocked(StudioTurn turn) {
  return turn.toolResults.any(
    (result) => result.status == ToolResultStatus.denied,
  );
}

/// Canonical persisted lifecycle phases. Older transport-oriented status names
/// remain readable for backwards compatibility, but each maps to exactly one
/// phase so callers can reason about legal state transitions consistently.
enum StudioTurnPhase {
  created,
  retrieving,
  requesting,
  streaming,
  waitingApproval,
  runningTool,
  reviewingPatch,
  verifying,
  completed,
  failed,
  cancelled,
  interrupted,
}

class StudioTurnStateMachine {
  const StudioTurnStateMachine._();

  static StudioTurnPhase phaseFor(StudioTurnStatus status) => switch (status) {
    StudioTurnStatus.queued => StudioTurnPhase.created,
    StudioTurnStatus.buildingContext => StudioTurnPhase.retrieving,
    StudioTurnStatus.sent ||
    StudioTurnStatus.waitingForModel => StudioTurnPhase.requesting,
    StudioTurnStatus.streaming => StudioTurnPhase.streaming,
    StudioTurnStatus.toolRunning => StudioTurnPhase.runningTool,
    StudioTurnStatus.waitingForApproval => StudioTurnPhase.waitingApproval,
    StudioTurnStatus.reviewingPatch => StudioTurnPhase.reviewingPatch,
    StudioTurnStatus.verifying => StudioTurnPhase.verifying,
    StudioTurnStatus.completed => StudioTurnPhase.completed,
    StudioTurnStatus.failed => StudioTurnPhase.failed,
    StudioTurnStatus.cancelled => StudioTurnPhase.cancelled,
    StudioTurnStatus.interrupted => StudioTurnPhase.interrupted,
  };

  static bool isTerminal(StudioTurnStatus status) => switch (phaseFor(status)) {
    StudioTurnPhase.completed ||
    StudioTurnPhase.failed ||
    StudioTurnPhase.cancelled ||
    StudioTurnPhase.interrupted => true,
    _ => false,
  };

  static bool canTransition(StudioTurnStatus from, StudioTurnStatus to) {
    final current = phaseFor(from);
    final next = phaseFor(to);
    if (current == next) return true;
    if (isTerminal(from)) return false;
    if (next == StudioTurnPhase.failed ||
        next == StudioTurnPhase.cancelled ||
        next == StudioTurnPhase.interrupted) {
      return true;
    }
    return switch (current) {
      StudioTurnPhase.created =>
        next == StudioTurnPhase.retrieving ||
            next == StudioTurnPhase.requesting,
      StudioTurnPhase.retrieving =>
        next == StudioTurnPhase.requesting ||
            next == StudioTurnPhase.streaming ||
            next == StudioTurnPhase.runningTool ||
            next == StudioTurnPhase.waitingApproval ||
            next == StudioTurnPhase.reviewingPatch ||
            next == StudioTurnPhase.verifying ||
            next == StudioTurnPhase.completed,
      StudioTurnPhase.requesting =>
        next == StudioTurnPhase.streaming ||
            next == StudioTurnPhase.runningTool ||
            next == StudioTurnPhase.waitingApproval ||
            next == StudioTurnPhase.reviewingPatch ||
            next == StudioTurnPhase.verifying ||
            next == StudioTurnPhase.completed,
      StudioTurnPhase.streaming =>
        next == StudioTurnPhase.requesting ||
            next == StudioTurnPhase.runningTool ||
            next == StudioTurnPhase.waitingApproval ||
            next == StudioTurnPhase.reviewingPatch ||
            next == StudioTurnPhase.verifying ||
            next == StudioTurnPhase.completed,
      StudioTurnPhase.runningTool =>
        next == StudioTurnPhase.requesting ||
            next == StudioTurnPhase.streaming ||
            next == StudioTurnPhase.waitingApproval ||
            next == StudioTurnPhase.reviewingPatch ||
            next == StudioTurnPhase.verifying ||
            next == StudioTurnPhase.completed,
      StudioTurnPhase.waitingApproval =>
        next == StudioTurnPhase.requesting ||
            next == StudioTurnPhase.runningTool ||
            next == StudioTurnPhase.reviewingPatch ||
            next == StudioTurnPhase.verifying ||
            next == StudioTurnPhase.completed,
      StudioTurnPhase.reviewingPatch =>
        next == StudioTurnPhase.requesting ||
            next == StudioTurnPhase.runningTool ||
            next == StudioTurnPhase.waitingApproval ||
            next == StudioTurnPhase.verifying ||
            next == StudioTurnPhase.completed,
      StudioTurnPhase.verifying =>
        next == StudioTurnPhase.requesting ||
            next == StudioTurnPhase.runningTool ||
            next == StudioTurnPhase.waitingApproval ||
            next == StudioTurnPhase.reviewingPatch ||
            next == StudioTurnPhase.completed,
      StudioTurnPhase.completed ||
      StudioTurnPhase.failed ||
      StudioTurnPhase.cancelled ||
      StudioTurnPhase.interrupted => false,
    };
  }
}

enum StudioTurnEventType {
  userMessage,
  context,
  assistantMessage,
  progress,
  tool,
  approvalRequest,
  error,
  completionSummary,
}

enum ApprovalScope { once, turn }

enum ApprovalRequestState { pending, approved, rejected, expired }

enum AcceptedPlanState {
  none,
  accepted,
  implementationStarted,
  patchProposed,
  blockedForMissingContext,
  implemented,
  failed,
}

enum PlanTargetProgressState {
  pending,
  proposed,
  applied,
  conflict,
  skipped,
  blocked,
}

class PlanTargetProgress {
  final String path;
  final String intent;
  final ProposedFileEditType? operation;
  final PlanTargetProgressState state;
  final String? patchSetId;
  final String? detail;
  final DateTime updatedAt;

  const PlanTargetProgress({
    required this.path,
    required this.intent,
    this.operation,
    this.state = PlanTargetProgressState.pending,
    this.patchSetId,
    this.detail,
    required this.updatedAt,
  });

  factory PlanTargetProgress.fromTarget(PlannedFileTarget target) {
    return PlanTargetProgress(
      path: target.path,
      intent: target.intent,
      operation: target.operation,
      updatedAt: DateTime.now(),
    );
  }

  PlanTargetProgress copyWith({
    PlanTargetProgressState? state,
    Object? patchSetId = _sentinel,
    Object? detail = _sentinel,
    DateTime? updatedAt,
  }) {
    return PlanTargetProgress(
      path: path,
      intent: intent,
      operation: operation,
      state: state ?? this.state,
      patchSetId: identical(patchSetId, _sentinel)
          ? this.patchSetId
          : patchSetId as String?,
      detail: identical(detail, _sentinel) ? this.detail : detail as String?,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'intent': intent,
    'operation': operation?.name,
    'state': state.name,
    'patchSetId': patchSetId,
    'detail': detail,
    'updatedAt': updatedAt.toIso8601String(),
  };

  static PlanTargetProgress? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    try {
      final operationName = json['operation'] as String?;
      final stateName = json['state'] as String?;
      return PlanTargetProgress(
        path: json['path'] as String? ?? '',
        intent: json['intent'] as String? ?? '',
        operation: operationName == null
            ? null
            : ProposedFileEditType.values.firstWhere(
                (candidate) => candidate.name == operationName,
                orElse: () => ProposedFileEditType.modify,
              ),
        state: PlanTargetProgressState.values.firstWhere(
          (candidate) => candidate.name == stateName,
          orElse: () => PlanTargetProgressState.pending,
        ),
        patchSetId: json['patchSetId'] as String?,
        detail: json['detail'] as String?,
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}

class StudioTurnEvent {
  final String id;
  final String turnId;
  final String requestId;
  final String threadId;
  final StudioTurnEventType type;
  final String title;
  final String detail;
  final String? content;
  final DateTime timestamp;
  final String? relatedMessageId;
  final String? toolCallId;
  final String? toolName;
  final String? approvalId;
  final ApprovalRequestState? approvalState;
  final String? approvalPreview;
  final List<String> approvalWarnings;
  final ApprovalGrant? approvalGrant;
  final ToolPermissionReason? approvalRisk;
  final String? approvalNormalizedAction;
  final DateTime? approvalExpiresAt;
  final String? sourceArtifactId;
  final String? filePath;
  final String? localUrl;
  final String? patchSetId;
  final bool transcriptVisible;

  const StudioTurnEvent({
    required this.id,
    required this.turnId,
    required this.requestId,
    required this.threadId,
    required this.type,
    required this.title,
    required this.detail,
    this.content,
    required this.timestamp,
    this.relatedMessageId,
    this.toolCallId,
    this.toolName,
    this.approvalId,
    this.approvalState,
    this.approvalPreview,
    this.approvalWarnings = const [],
    this.approvalGrant,
    this.approvalRisk,
    this.approvalNormalizedAction,
    this.approvalExpiresAt,
    this.sourceArtifactId,
    this.filePath,
    this.localUrl,
    this.patchSetId,
    this.transcriptVisible = true,
  });

  factory StudioTurnEvent.userMessage({
    required String id,
    required String turnId,
    required String requestId,
    required String threadId,
    required String content,
    required DateTime timestamp,
    bool transcriptVisible = true,
  }) {
    return StudioTurnEvent(
      id: id,
      turnId: turnId,
      requestId: requestId,
      threadId: threadId,
      type: StudioTurnEventType.userMessage,
      title: 'User message',
      detail: content,
      content: content,
      timestamp: timestamp,
      transcriptVisible: transcriptVisible,
    );
  }

  factory StudioTurnEvent.context({
    required String turnId,
    required String requestId,
    required String threadId,
    required StudioContextSummary summary,
    DateTime? timestamp,
  }) {
    return StudioTurnEvent(
      id: 'context-$turnId',
      turnId: turnId,
      requestId: requestId,
      threadId: threadId,
      type: StudioTurnEventType.context,
      title: summary.title,
      detail: summary.detail,
      timestamp: timestamp ?? DateTime.now(),
      transcriptVisible: false,
    );
  }

  factory StudioTurnEvent.intentRouting({
    required String turnId,
    required String requestId,
    required String threadId,
    required IntentRoutingDecision decision,
    DateTime? timestamp,
  }) {
    return StudioTurnEvent(
      id: 'intent-routing-$turnId',
      turnId: turnId,
      requestId: requestId,
      threadId: threadId,
      type: StudioTurnEventType.progress,
      title: 'Intent routing',
      detail:
          '${decision.intent.name} · ${decision.confidenceLabel} · ${decision.source.name}: ${decision.reason}',
      timestamp: timestamp ?? DateTime.now(),
      transcriptVisible: false,
    );
  }

  factory StudioTurnEvent.progress({
    required String turnId,
    required String requestId,
    required String threadId,
    required String title,
    required String detail,
    bool transcriptVisible = false,
    DateTime? timestamp,
  }) {
    return StudioTurnEvent(
      id: 'progress-$turnId',
      turnId: turnId,
      requestId: requestId,
      threadId: threadId,
      type: StudioTurnEventType.progress,
      title: title,
      detail: detail,
      timestamp: timestamp ?? DateTime.now(),
      transcriptVisible: transcriptVisible,
    );
  }

  factory StudioTurnEvent.tool({
    required String turnId,
    required String requestId,
    required String threadId,
    required String toolCallId,
    required String toolName,
    required String title,
    required String detail,
    String? filePath,
    DateTime? timestamp,
  }) {
    return StudioTurnEvent(
      id: 'tool-$requestId-$toolCallId',
      turnId: turnId,
      requestId: requestId,
      threadId: threadId,
      type: StudioTurnEventType.tool,
      title: title,
      detail: detail,
      timestamp: timestamp ?? DateTime.now(),
      toolCallId: toolCallId,
      toolName: toolName,
      filePath: filePath,
      transcriptVisible: false,
    );
  }

  factory StudioTurnEvent.approval({
    required String turnId,
    required String requestId,
    required String threadId,
    required ConfirmationRequest request,
    ApprovalRequestState state = ApprovalRequestState.pending,
    DateTime? timestamp,
  }) {
    return StudioTurnEvent(
      id: 'approval-$requestId-${request.id}',
      turnId: turnId,
      requestId: requestId,
      threadId: threadId,
      type: StudioTurnEventType.approvalRequest,
      title: 'Approval needed',
      detail: 'Review the tool request.',
      timestamp: timestamp ?? request.timestamp,
      toolCallId: request.toolCall.id,
      toolName: request.toolCall.name,
      approvalId: request.id,
      approvalState: state,
      approvalPreview: request.preview,
      approvalWarnings: request.warnings,
      approvalGrant: request.grantedScope,
      approvalRisk: request.risk,
      approvalNormalizedAction: request.normalizedAction,
      approvalExpiresAt: request.expiresAt,
      filePath: _pathForTool(request.toolCall.arguments),
    );
  }

  factory StudioTurnEvent.assistantMessage({
    required String turnId,
    required String requestId,
    required String threadId,
    required String content,
    DateTime? timestamp,
  }) {
    return StudioTurnEvent(
      id: 'assistant-$turnId',
      turnId: turnId,
      requestId: requestId,
      threadId: threadId,
      type: StudioTurnEventType.assistantMessage,
      title: 'Assistant response',
      detail: content,
      content: content,
      timestamp: timestamp ?? DateTime.now(),
    );
  }

  factory StudioTurnEvent.error({
    required String turnId,
    required String requestId,
    required String threadId,
    required String detail,
    DateTime? timestamp,
  }) {
    return StudioTurnEvent(
      id: 'error-$turnId',
      turnId: turnId,
      requestId: requestId,
      threadId: threadId,
      type: StudioTurnEventType.error,
      title: 'Circuit AI needs attention',
      detail: detail,
      timestamp: timestamp ?? DateTime.now(),
    );
  }

  factory StudioTurnEvent.completionSummary({
    String? id,
    required String turnId,
    required String requestId,
    required String threadId,
    required String title,
    required String detail,
    String? patchSetId,
    DateTime? timestamp,
  }) {
    return StudioTurnEvent(
      id: id ?? 'completion-$turnId',
      turnId: turnId,
      requestId: requestId,
      threadId: threadId,
      type: StudioTurnEventType.completionSummary,
      title: title,
      detail: detail,
      patchSetId: patchSetId,
      timestamp: timestamp ?? DateTime.now(),
    );
  }

  StudioTurnEvent copyWith({
    String? title,
    String? detail,
    Object? content = _sentinel,
    DateTime? timestamp,
    Object? approvalState = _sentinel,
    Object? approvalGrant = _sentinel,
    Object? approvalRisk = _sentinel,
    Object? approvalNormalizedAction = _sentinel,
    Object? approvalExpiresAt = _sentinel,
    Object? sourceArtifactId = _sentinel,
    Object? filePath = _sentinel,
    Object? localUrl = _sentinel,
    Object? patchSetId = _sentinel,
    bool? transcriptVisible,
  }) {
    return StudioTurnEvent(
      id: id,
      turnId: turnId,
      requestId: requestId,
      threadId: threadId,
      type: type,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      content: identical(content, _sentinel)
          ? this.content
          : content as String?,
      timestamp: timestamp ?? this.timestamp,
      relatedMessageId: relatedMessageId,
      toolCallId: toolCallId,
      toolName: toolName,
      approvalId: approvalId,
      approvalState: identical(approvalState, _sentinel)
          ? this.approvalState
          : approvalState as ApprovalRequestState?,
      approvalPreview: approvalPreview,
      approvalWarnings: approvalWarnings,
      approvalGrant: identical(approvalGrant, _sentinel)
          ? this.approvalGrant
          : approvalGrant as ApprovalGrant?,
      approvalRisk: identical(approvalRisk, _sentinel)
          ? this.approvalRisk
          : approvalRisk as ToolPermissionReason?,
      approvalNormalizedAction: identical(approvalNormalizedAction, _sentinel)
          ? this.approvalNormalizedAction
          : approvalNormalizedAction as String?,
      approvalExpiresAt: identical(approvalExpiresAt, _sentinel)
          ? this.approvalExpiresAt
          : approvalExpiresAt as DateTime?,
      sourceArtifactId: identical(sourceArtifactId, _sentinel)
          ? this.sourceArtifactId
          : sourceArtifactId as String?,
      filePath: identical(filePath, _sentinel)
          ? this.filePath
          : filePath as String?,
      localUrl: identical(localUrl, _sentinel)
          ? this.localUrl
          : localUrl as String?,
      patchSetId: identical(patchSetId, _sentinel)
          ? this.patchSetId
          : patchSetId as String?,
      transcriptVisible: transcriptVisible ?? this.transcriptVisible,
    );
  }

  ChatMessage toUserChatMessage() {
    return ChatMessage(
      id: id,
      role: MessageRole.user,
      content: content ?? detail,
      timestamp: timestamp,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'turnId': turnId,
      'requestId': requestId,
      'threadId': threadId,
      'type': type.name,
      'title': title,
      'detail': detail,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'relatedMessageId': relatedMessageId,
      'toolCallId': toolCallId,
      'toolName': toolName,
      'approvalId': approvalId,
      'approvalState': approvalState?.name,
      'approvalPreview': approvalPreview,
      'approvalWarnings': approvalWarnings,
      'approvalGrant': approvalGrant?.name,
      'approvalRisk': approvalRisk?.name,
      'approvalNormalizedAction': approvalNormalizedAction,
      'approvalExpiresAt': approvalExpiresAt?.toIso8601String(),
      'sourceArtifactId': sourceArtifactId,
      'filePath': filePath,
      'localUrl': localUrl,
      'patchSetId': patchSetId,
      'transcriptVisible': transcriptVisible,
    };
  }

  static StudioTurnEvent? fromJson(Map<String, dynamic> json) {
    try {
      final approvalStateName = json['approvalState'] as String?;
      final approvalGrantName = json['approvalGrant'] as String?;
      final approvalRiskName = json['approvalRisk'] as String?;
      return StudioTurnEvent(
        id: json['id'] as String,
        turnId: json['turnId'] as String,
        requestId: json['requestId'] as String,
        threadId: json['threadId'] as String,
        type: StudioTurnEventType.values.firstWhere(
          (value) => value.name == json['type'],
          orElse: () => StudioTurnEventType.progress,
        ),
        title: json['title'] as String? ?? 'Activity',
        detail: json['detail'] as String? ?? '',
        content: json['content'] as String?,
        timestamp:
            DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
        relatedMessageId: json['relatedMessageId'] as String?,
        toolCallId: json['toolCallId'] as String?,
        toolName: json['toolName'] as String?,
        approvalId: json['approvalId'] as String?,
        approvalState: approvalStateName == null
            ? null
            : ApprovalRequestState.values.firstWhere(
                (value) => value.name == approvalStateName,
                orElse: () => ApprovalRequestState.pending,
              ),
        approvalPreview: json['approvalPreview'] as String?,
        approvalWarnings:
            (json['approvalWarnings'] as List<dynamic>?)?.cast<String>() ??
            const [],
        approvalGrant: approvalGrantName == null
            ? null
            : ApprovalGrant.values.firstWhere(
                (value) => value.name == approvalGrantName,
                orElse: () => ApprovalGrant.once,
              ),
        approvalRisk: approvalRiskName == null
            ? null
            : ToolPermissionReason.values.firstWhere(
                (value) => value.name == approvalRiskName,
                orElse: () => ToolPermissionReason.unknownTool,
              ),
        approvalNormalizedAction: json['approvalNormalizedAction'] as String?,
        approvalExpiresAt: DateTime.tryParse(
          json['approvalExpiresAt'] as String? ?? '',
        ),
        sourceArtifactId: json['sourceArtifactId'] as String?,
        filePath: json['filePath'] as String?,
        localUrl: json['localUrl'] as String?,
        patchSetId: json['patchSetId'] as String?,
        transcriptVisible:
            json['transcriptVisible'] as bool? ??
            _defaultTranscriptVisibleFor(
              StudioTurnEventType.values.firstWhere(
                (value) => value.name == json['type'],
                orElse: () => StudioTurnEventType.progress,
              ),
            ),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _pathForTool(Map<String, dynamic> arguments) {
    final value =
        arguments['path'] ?? arguments['file'] ?? arguments['directory'];
    return value is String && value.trim().isNotEmpty ? value : null;
  }
}

// ADR-0001: StudioTurn is the durable source of Studio lifecycle truth.
bool _defaultTranscriptVisibleFor(StudioTurnEventType type) {
  return switch (type) {
    StudioTurnEventType.context ||
    StudioTurnEventType.progress ||
    StudioTurnEventType.tool => false,
    StudioTurnEventType.userMessage ||
    StudioTurnEventType.assistantMessage ||
    StudioTurnEventType.approvalRequest ||
    StudioTurnEventType.error ||
    StudioTurnEventType.completionSummary => true,
  };
}

/// Safe recovery information captured whenever an active turn is persisted.
///
/// Provider streams, command processes, and approval grants are request-local,
/// so a checkpoint never resumes any of them automatically after restart. It
/// gives the restored UI the exact phase and the safest next user action.
enum StudioTurnRecoveryAction {
  retryTurn,
  reviewPatch,
  continuePlan,
  rerunVerification,
}

class StudioTurnRecoveryCheckpoint {
  final StudioTurnPhase phase;
  final DateTime capturedAt;
  final int streamedCharacters;
  final int completedToolCount;
  final String? providerCursor;
  final String? pendingApprovalId;
  final String? pendingToolCallId;
  final String? pendingToolName;
  final String? commandRunId;
  final String? patchSetId;
  final StudioTurnRecoveryAction action;

  const StudioTurnRecoveryCheckpoint({
    required this.phase,
    required this.capturedAt,
    required this.streamedCharacters,
    required this.completedToolCount,
    this.providerCursor,
    this.pendingApprovalId,
    this.pendingToolCallId,
    this.pendingToolName,
    this.commandRunId,
    this.patchSetId,
    required this.action,
  });

  String get actionLabel => switch (action) {
    StudioTurnRecoveryAction.retryTurn => 'Retry task',
    StudioTurnRecoveryAction.reviewPatch => 'Review patch',
    StudioTurnRecoveryAction.continuePlan => 'Continue plan',
    StudioTurnRecoveryAction.rerunVerification => 'Rerun verification',
  };

  factory StudioTurnRecoveryCheckpoint.capture(
    StudioTurn turn, {
    DateTime? capturedAt,
  }) {
    final pendingApproval = turn.events.reversed
        .where(
          (event) =>
              event.type == StudioTurnEventType.approvalRequest &&
              event.approvalState == ApprovalRequestState.pending,
        )
        .firstOrNull;
    final pendingTool = turn.events.reversed
        .where((event) => event.type == StudioTurnEventType.tool)
        .firstOrNull;
    final commandResult = turn.toolResults.reversed
        .where((result) => result.toolName == 'run_command')
        .firstOrNull;
    final patchSetId =
        turn.acceptedPlanContext?.patchSetId ??
        turn.events.reversed
            .map((event) => event.patchSetId)
            .whereType<String>()
            .firstOrNull;
    final hasPendingPlanTargets = turn.planTargetProgress.any(
      (target) =>
          target.state == PlanTargetProgressState.pending ||
          target.state == PlanTargetProgressState.proposed ||
          target.state == PlanTargetProgressState.blocked,
    );
    final action = switch (turn.status) {
      StudioTurnStatus.reviewingPatch => StudioTurnRecoveryAction.reviewPatch,
      StudioTurnStatus.verifying => StudioTurnRecoveryAction.rerunVerification,
      _
          when turn.intent == TurnIntent.verify ||
              commandResult?.status == ToolResultStatus.waitingForApproval =>
        StudioTurnRecoveryAction.rerunVerification,
      _
          when turn.acceptedPlanState == AcceptedPlanState.patchProposed ||
              patchSetId != null =>
        StudioTurnRecoveryAction.reviewPatch,
      _ when hasPendingPlanTargets => StudioTurnRecoveryAction.continuePlan,
      _ => StudioTurnRecoveryAction.retryTurn,
    };
    return StudioTurnRecoveryCheckpoint(
      phase: turn.phase,
      capturedAt: capturedAt ?? DateTime.now(),
      streamedCharacters: turn.assistantDraft.length,
      completedToolCount: turn.toolResults
          .where((result) => result.status == ToolResultStatus.success)
          .length,
      // The current provider protocol advertises no resumable cursor. Keep
      // this nullable field for a negotiated cursor in a future protocol.
      providerCursor: null,
      pendingApprovalId: pendingApproval?.approvalId,
      pendingToolCallId: pendingApproval?.toolCallId ?? pendingTool?.toolCallId,
      pendingToolName: pendingApproval?.toolName ?? pendingTool?.toolName,
      commandRunId: commandResult?.toolCallId,
      patchSetId: patchSetId,
      action: action,
    );
  }

  Map<String, dynamic> toJson() => {
    'phase': phase.name,
    'capturedAt': capturedAt.toIso8601String(),
    'streamedCharacters': streamedCharacters,
    'completedToolCount': completedToolCount,
    'providerCursor': providerCursor,
    'pendingApprovalId': pendingApprovalId,
    'pendingToolCallId': pendingToolCallId,
    'pendingToolName': pendingToolName,
    'commandRunId': commandRunId,
    'patchSetId': patchSetId,
    'action': action.name,
  };

  static StudioTurnRecoveryCheckpoint? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final phaseName = json['phase'] as String?;
    final actionName = json['action'] as String?;
    if (phaseName == null || actionName == null) return null;
    try {
      return StudioTurnRecoveryCheckpoint(
        phase: StudioTurnPhase.values.firstWhere(
          (value) => value.name == phaseName,
        ),
        capturedAt:
            DateTime.tryParse(json['capturedAt'] as String? ?? '') ??
            DateTime.now(),
        streamedCharacters: json['streamedCharacters'] as int? ?? 0,
        completedToolCount: json['completedToolCount'] as int? ?? 0,
        providerCursor: json['providerCursor'] as String?,
        pendingApprovalId: json['pendingApprovalId'] as String?,
        pendingToolCallId: json['pendingToolCallId'] as String?,
        pendingToolName: json['pendingToolName'] as String?,
        commandRunId: json['commandRunId'] as String?,
        patchSetId: json['patchSetId'] as String?,
        action: StudioTurnRecoveryAction.values.firstWhere(
          (value) => value.name == actionName,
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

class StudioTurn {
  final String id;
  final String threadId;
  final String requestId;
  final String? taskId;
  final String userMessageId;

  /// User-visible prompt. This is the only prompt surface UI/history may use.
  final String displayPrompt;

  /// Runtime-only prompt sent to the provider. It can include orchestration
  /// contracts and must never be rendered as a user message, task title, or
  /// search/export/notification payload.
  final String modelPrompt;

  /// User-facing title chosen at turn creation, independent of either prompt.
  final String taskTitle;
  final String model;
  final TurnIntent intent;
  final IntentRoutingDecision? intentRouting;
  final StudioTurnRecoveryCheckpoint? recoveryCheckpoint;
  final StudioContextSummary contextSummary;
  final StudioTurnStatus status;
  final String assistantDraft;
  final List<StudioTurnEvent> events;
  final List<TurnStepRecord> steps;
  final List<ToolResultEnvelope> toolResults;
  final List<ProviderLifecycleEvent> providerDiagnostics;
  final AcceptedPlanState acceptedPlanState;
  final AcceptedPlanContext? acceptedPlanContext;
  final List<PlanTargetProgress> planTargetProgress;
  final ContextRetrievalResult? contextRetrieval;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final String? lastError;
  final StudioFailureCategory? failureCategory;
  final StudioTurnOutcome? finalOutcome;

  StudioTurnPhase get phase => StudioTurnStateMachine.phaseFor(status);

  const StudioTurn({
    required this.id,
    required this.threadId,
    required this.requestId,
    this.taskId,
    required this.userMessageId,
    required String prompt,
    String? modelPrompt,
    String? taskTitle,
    required this.model,
    this.intent = TurnIntent.code,
    this.intentRouting,
    this.recoveryCheckpoint,
    required this.contextSummary,
    this.status = StudioTurnStatus.queued,
    this.assistantDraft = '',
    this.events = const [],
    this.steps = const [],
    this.toolResults = const [],
    this.providerDiagnostics = const [],
    this.acceptedPlanState = AcceptedPlanState.none,
    this.acceptedPlanContext,
    this.planTargetProgress = const [],
    this.contextRetrieval,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.lastError,
    this.failureCategory,
    this.finalOutcome,
  }) : displayPrompt = prompt,
       modelPrompt = modelPrompt ?? prompt,
       taskTitle = taskTitle ?? prompt;

  @Deprecated('Use displayPrompt for user-visible turn text.')
  String get prompt => displayPrompt;

  StudioTurn copyWith({
    StudioTurnStatus? status,
    String? assistantDraft,
    List<StudioTurnEvent>? events,
    List<TurnStepRecord>? steps,
    List<ToolResultEnvelope>? toolResults,
    List<ProviderLifecycleEvent>? providerDiagnostics,
    Object? intentRouting = _sentinel,
    Object? recoveryCheckpoint = _sentinel,
    AcceptedPlanState? acceptedPlanState,
    Object? acceptedPlanContext = _sentinel,
    List<PlanTargetProgress>? planTargetProgress,
    Object? contextRetrieval = _sentinel,
    DateTime? updatedAt,
    Object? completedAt = _sentinel,
    Object? lastError = _sentinel,
    Object? failureCategory = _sentinel,
    Object? finalOutcome = _sentinel,
  }) {
    return StudioTurn(
      id: id,
      threadId: threadId,
      requestId: requestId,
      taskId: taskId,
      userMessageId: userMessageId,
      prompt: displayPrompt,
      modelPrompt: modelPrompt,
      taskTitle: taskTitle,
      model: model,
      intent: intent,
      intentRouting: identical(intentRouting, _sentinel)
          ? this.intentRouting
          : intentRouting as IntentRoutingDecision?,
      recoveryCheckpoint: identical(recoveryCheckpoint, _sentinel)
          ? this.recoveryCheckpoint
          : recoveryCheckpoint as StudioTurnRecoveryCheckpoint?,
      contextSummary: contextSummary,
      status: status ?? this.status,
      assistantDraft: assistantDraft ?? this.assistantDraft,
      events: events ?? this.events,
      steps: steps ?? this.steps,
      toolResults: toolResults ?? this.toolResults,
      providerDiagnostics: providerDiagnostics ?? this.providerDiagnostics,
      acceptedPlanState: acceptedPlanState ?? this.acceptedPlanState,
      acceptedPlanContext: identical(acceptedPlanContext, _sentinel)
          ? this.acceptedPlanContext
          : acceptedPlanContext as AcceptedPlanContext?,
      planTargetProgress: planTargetProgress ?? this.planTargetProgress,
      contextRetrieval: identical(contextRetrieval, _sentinel)
          ? this.contextRetrieval
          : contextRetrieval as ContextRetrievalResult?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      completedAt: identical(completedAt, _sentinel)
          ? this.completedAt
          : completedAt as DateTime?,
      lastError: identical(lastError, _sentinel)
          ? this.lastError
          : lastError as String?,
      failureCategory: identical(failureCategory, _sentinel)
          ? this.failureCategory
          : failureCategory as StudioFailureCategory?,
      finalOutcome: identical(finalOutcome, _sentinel)
          ? this.finalOutcome
          : finalOutcome as StudioTurnOutcome?,
    );
  }

  StudioFailureCategory? get effectiveFailureCategory =>
      failureCategory ??
      StudioFailureTaxonomy.classify(statusName: status.name, error: lastError);

  StudioTurn upsertEvent(StudioTurnEvent event) {
    final events = [
      ...this.events.where((candidate) => candidate.id != event.id),
      event,
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return copyWith(events: events, updatedAt: DateTime.now());
  }

  StudioTurn upsertStep(TurnStepRecord step) {
    final steps = [
      ...this.steps.where((candidate) => candidate.step != step.step),
      step,
    ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return copyWith(steps: steps, updatedAt: DateTime.now());
  }

  StudioTurn expirePendingApprovals() {
    return copyWith(
      events: [
        for (final event in events)
          if (event.type == StudioTurnEventType.approvalRequest &&
              event.approvalState == ApprovalRequestState.pending)
            event.copyWith(approvalState: ApprovalRequestState.expired)
          else
            event,
      ],
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'threadId': threadId,
      'requestId': requestId,
      'taskId': taskId,
      'userMessageId': userMessageId,
      // Keep `prompt` for schema-1 compatibility; readers prefer the explicit
      // display/model/title fields added in schema 2.
      'prompt': displayPrompt,
      'displayPrompt': displayPrompt,
      'modelPrompt': modelPrompt,
      'taskTitle': taskTitle,
      'model': model,
      'intent': intent.name,
      'intentRouting': intentRouting?.toJson(),
      'recoveryCheckpoint': recoveryCheckpoint?.toJson(),
      'contextSummary': contextSummary.toJson(),
      'status': status.name,
      'assistantDraft': assistantDraft,
      'events': events.map((event) => event.toJson()).toList(),
      'steps': steps.map((step) => step.toJson()).toList(),
      'toolResults': toolResults.map((result) => result.toJson()).toList(),
      'providerDiagnostics': providerDiagnostics
          .map((event) => event.toJson())
          .toList(),
      'acceptedPlanState': acceptedPlanState.name,
      'acceptedPlanContext': acceptedPlanContext?.toJson(),
      'planTargetProgress': planTargetProgress
          .map((target) => target.toJson())
          .toList(),
      'contextRetrieval': contextRetrieval?.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'lastError': lastError,
      'failureCategory': effectiveFailureCategory?.name,
      'finalOutcome': finalOutcome?.name,
    };
  }

  static StudioTurn? fromJson(Map<String, dynamic> json) {
    try {
      final acceptedPlanContext = AcceptedPlanContext.fromJson(
        json['acceptedPlanContext'] as Map<String, dynamic>?,
      );
      final planTargetProgress =
          (json['planTargetProgress'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(PlanTargetProgress.fromJson)
              .nonNulls
              .toList();
      return StudioTurn(
        id: json['id'] as String,
        threadId: json['threadId'] as String,
        requestId: json['requestId'] as String,
        taskId: json['taskId'] as String?,
        userMessageId: json['userMessageId'] as String,
        prompt:
            json['displayPrompt'] as String? ?? json['prompt'] as String? ?? '',
        modelPrompt: json['modelPrompt'] as String?,
        taskTitle: json['taskTitle'] as String?,
        model: json['model'] as String? ?? '',
        intent: TurnIntent.values.firstWhere(
          (value) => value.name == json['intent'],
          orElse: () => TurnIntent.code,
        ),
        intentRouting: IntentRoutingDecision.fromJson(
          json['intentRouting'] as Map<String, dynamic>?,
        ),
        recoveryCheckpoint: StudioTurnRecoveryCheckpoint.fromJson(
          json['recoveryCheckpoint'] as Map<String, dynamic>?,
        ),
        contextSummary: StudioContextSummary.fromJson(
          json['contextSummary'] as Map<String, dynamic>?,
        ),
        status: StudioTurnStatus.values.firstWhere(
          (value) => value.name == json['status'],
          orElse: () => StudioTurnStatus.queued,
        ),
        assistantDraft: json['assistantDraft'] as String? ?? '',
        events: (json['events'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(StudioTurnEvent.fromJson)
            .nonNulls
            .toList(),
        steps: (json['steps'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(TurnStepRecord.fromJson)
            .nonNulls
            .toList(),
        toolResults: (json['toolResults'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ToolResultEnvelope.fromJson)
            .toList(),
        providerDiagnostics:
            (json['providerDiagnostics'] as List<dynamic>? ?? [])
                .whereType<Map<String, dynamic>>()
                .map(ProviderLifecycleEvent.fromJson)
                .nonNulls
                .toList(),
        acceptedPlanState: AcceptedPlanState.values.firstWhere(
          (value) => value.name == json['acceptedPlanState'],
          orElse: () => AcceptedPlanState.none,
        ),
        acceptedPlanContext: acceptedPlanContext,
        planTargetProgress: planTargetProgress.isNotEmpty
            ? planTargetProgress
            : _planTargetProgressFromContext(acceptedPlanContext),
        contextRetrieval: ContextRetrievalResult.fromJson(
          json['contextRetrieval'] as Map<String, dynamic>?,
        ),
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
        lastError: json['lastError'] as String?,
        failureCategory: StudioFailureCategory.values
            .where((value) => value.name == json['failureCategory'])
            .firstOrNull,
        finalOutcome: StudioTurnOutcome.values
            .where((value) => value.name == json['finalOutcome'])
            .firstOrNull,
      );
    } catch (_) {
      return null;
    }
  }
}

const _sentinel = Object();

List<PlanTargetProgress> _planTargetProgressFromContext(
  AcceptedPlanContext? context,
) {
  if (context == null) return const [];
  final targets = context.plannedTargets.isNotEmpty
      ? context.plannedTargets
      : [
          for (final file in context.plannedFiles)
            PlannedFileTarget.fromDisplayString(file),
        ];
  final seen = <String>{};
  return [
    for (final target in targets)
      if (target.path.trim().isNotEmpty &&
          seen.add(target.path.trim().replaceAll('\\', '/')))
        PlanTargetProgress.fromTarget(target),
  ];
}
