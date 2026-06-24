import '../enums/message_role.dart';
import 'accepted_plan_context.dart';
import 'chat_message.dart';
import 'confirmation_request.dart';
import 'context_pack.dart';
import 'provider_lifecycle_event.dart';
import 'studio_thread.dart';
import 'tool_result_envelope.dart';
import 'turn_intent.dart';

enum TurnStep {
  preflight,
  contextBuild,
  providerRequest,
  streaming,
  toolDecision,
  approvalWait,
  toolExecution,
  patchProposal,
  verification,
  finalSummary,
}

enum TurnStepStatus { queued, running, completed, failed, skipped }

enum StudioTurnStatus {
  queued,
  buildingContext,
  sent,
  waitingForModel,
  streaming,
  toolRunning,
  waitingForApproval,
  completed,
  failed,
  cancelled,
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
  final String? sourceArtifactId;
  final String? filePath;
  final String? localUrl;
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
    this.sourceArtifactId,
    this.filePath,
    this.localUrl,
    this.transcriptVisible = true,
  });

  factory StudioTurnEvent.userMessage({
    required String id,
    required String turnId,
    required String requestId,
    required String threadId,
    required String content,
    required DateTime timestamp,
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
      timestamp: timestamp ?? DateTime.now(),
    );
  }

  StudioTurnEvent copyWith({
    String? title,
    String? detail,
    Object? content = _sentinel,
    DateTime? timestamp,
    Object? approvalState = _sentinel,
    Object? sourceArtifactId = _sentinel,
    Object? filePath = _sentinel,
    Object? localUrl = _sentinel,
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
      sourceArtifactId: identical(sourceArtifactId, _sentinel)
          ? this.sourceArtifactId
          : sourceArtifactId as String?,
      filePath: identical(filePath, _sentinel)
          ? this.filePath
          : filePath as String?,
      localUrl: identical(localUrl, _sentinel)
          ? this.localUrl
          : localUrl as String?,
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
      'sourceArtifactId': sourceArtifactId,
      'filePath': filePath,
      'localUrl': localUrl,
      'transcriptVisible': transcriptVisible,
    };
  }

  static StudioTurnEvent? fromJson(Map<String, dynamic> json) {
    try {
      final approvalStateName = json['approvalState'] as String?;
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
        sourceArtifactId: json['sourceArtifactId'] as String?,
        filePath: json['filePath'] as String?,
        localUrl: json['localUrl'] as String?,
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

class StudioTurn {
  final String id;
  final String threadId;
  final String requestId;
  final String? taskId;
  final String userMessageId;
  final String prompt;
  final String model;
  final TurnIntent intent;
  final StudioContextSummary contextSummary;
  final StudioTurnStatus status;
  final String assistantDraft;
  final List<StudioTurnEvent> events;
  final List<ToolResultEnvelope> toolResults;
  final List<ProviderLifecycleEvent> providerDiagnostics;
  final AcceptedPlanState acceptedPlanState;
  final AcceptedPlanContext? acceptedPlanContext;
  final ContextRetrievalResult? contextRetrieval;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final String? lastError;

  const StudioTurn({
    required this.id,
    required this.threadId,
    required this.requestId,
    this.taskId,
    required this.userMessageId,
    required this.prompt,
    required this.model,
    this.intent = TurnIntent.code,
    required this.contextSummary,
    this.status = StudioTurnStatus.queued,
    this.assistantDraft = '',
    this.events = const [],
    this.toolResults = const [],
    this.providerDiagnostics = const [],
    this.acceptedPlanState = AcceptedPlanState.none,
    this.acceptedPlanContext,
    this.contextRetrieval,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.lastError,
  });

  StudioTurn copyWith({
    StudioTurnStatus? status,
    String? assistantDraft,
    List<StudioTurnEvent>? events,
    List<ToolResultEnvelope>? toolResults,
    List<ProviderLifecycleEvent>? providerDiagnostics,
    AcceptedPlanState? acceptedPlanState,
    Object? acceptedPlanContext = _sentinel,
    Object? contextRetrieval = _sentinel,
    DateTime? updatedAt,
    Object? completedAt = _sentinel,
    Object? lastError = _sentinel,
  }) {
    return StudioTurn(
      id: id,
      threadId: threadId,
      requestId: requestId,
      taskId: taskId,
      userMessageId: userMessageId,
      prompt: prompt,
      model: model,
      intent: intent,
      contextSummary: contextSummary,
      status: status ?? this.status,
      assistantDraft: assistantDraft ?? this.assistantDraft,
      events: events ?? this.events,
      toolResults: toolResults ?? this.toolResults,
      providerDiagnostics: providerDiagnostics ?? this.providerDiagnostics,
      acceptedPlanState: acceptedPlanState ?? this.acceptedPlanState,
      acceptedPlanContext: identical(acceptedPlanContext, _sentinel)
          ? this.acceptedPlanContext
          : acceptedPlanContext as AcceptedPlanContext?,
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
    );
  }

  StudioTurn upsertEvent(StudioTurnEvent event) {
    final events = [
      ...this.events.where((candidate) => candidate.id != event.id),
      event,
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return copyWith(events: events, updatedAt: DateTime.now());
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
      'prompt': prompt,
      'model': model,
      'intent': intent.name,
      'contextSummary': contextSummary.toJson(),
      'status': status.name,
      'assistantDraft': assistantDraft,
      'events': events.map((event) => event.toJson()).toList(),
      'toolResults': toolResults.map((result) => result.toJson()).toList(),
      'providerDiagnostics': providerDiagnostics
          .map((event) => event.toJson())
          .toList(),
      'acceptedPlanState': acceptedPlanState.name,
      'acceptedPlanContext': acceptedPlanContext?.toJson(),
      'contextRetrieval': contextRetrieval?.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'lastError': lastError,
    };
  }

  static StudioTurn? fromJson(Map<String, dynamic> json) {
    try {
      return StudioTurn(
        id: json['id'] as String,
        threadId: json['threadId'] as String,
        requestId: json['requestId'] as String,
        taskId: json['taskId'] as String?,
        userMessageId: json['userMessageId'] as String,
        prompt: json['prompt'] as String? ?? '',
        model: json['model'] as String? ?? '',
        intent: TurnIntent.values.firstWhere(
          (value) => value.name == json['intent'],
          orElse: () => TurnIntent.code,
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
        acceptedPlanContext: AcceptedPlanContext.fromJson(
          json['acceptedPlanContext'] as Map<String, dynamic>?,
        ),
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
      );
    } catch (_) {
      return null;
    }
  }
}

const _sentinel = Object();
