import 'token_usage.dart';
import 'context_attachment.dart';

enum AgentRunKind { chat, inlineCompletion, editPrediction, backgroundTask }

enum AgentRunStatus {
  queued,
  running,
  streaming,
  waitingForApproval,
  succeeded,
  failed,
  cancelled,
}

enum AgentRunEventType {
  started,
  contextPrepared,
  providerRequest,
  streamChunk,
  toolCall,
  patchProposal,
  patchApply,
  commandRun,
  checkpoint,
  verification,
  tokenUsage,
  completed,
  failed,
  cancelled,
}

enum AgentTraceSpanKind {
  run,
  contextBuild,
  providerRequest,
  stream,
  toolCall,
  patchProposal,
  patchApply,
  commandRun,
  checkpoint,
  verification,
}

class AgentTraceSpan {
  final String id;
  final String? requestId;
  final AgentTraceSpanKind kind;
  final String name;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? detail;
  final Map<String, String> metadata;
  final bool failed;

  const AgentTraceSpan({
    required this.id,
    this.requestId,
    this.kind = AgentTraceSpanKind.run,
    required this.name,
    required this.startedAt,
    this.endedAt,
    this.detail,
    this.metadata = const {},
    this.failed = false,
  });

  AgentTraceSpan copyWith({
    DateTime? endedAt,
    String? detail,
    Map<String, String>? metadata,
    bool? failed,
  }) {
    return AgentTraceSpan(
      id: id,
      requestId: requestId,
      kind: kind,
      name: name,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      detail: detail ?? this.detail,
      metadata: metadata ?? this.metadata,
      failed: failed ?? this.failed,
    );
  }
}

class AgentRunEvent {
  final AgentRunEventType type;
  final DateTime timestamp;
  final String message;
  final String? requestId;
  final Map<String, String> metadata;

  const AgentRunEvent({
    required this.type,
    required this.timestamp,
    required this.message,
    this.requestId,
    this.metadata = const {},
  });
}

class AgentRun {
  final String id;
  final AgentRunKind kind;
  final AgentRunStatus status;
  final String model;
  final String? title;
  final String? inputPreview;
  final String? outputPreview;
  final String? retryPrompt;
  final List<ContextAttachment> retryAttachments;
  final int contextAttachmentCount;
  final DateTime startedAt;
  final DateTime? endedAt;
  final TokenUsage tokenUsage;
  final String? error;
  final bool cancelRequested;
  final List<AgentRunEvent> events;
  final List<AgentTraceSpan> spans;
  final List<String> changedFiles;
  final List<String> commandSummaries;
  final String? checkpointId;
  final String? agentTaskId;
  final String? parentRunId;
  final String? approvalId;
  final String? artifactId;
  final String? mascotAlias;
  final bool acceptsLegacyEvents;

  const AgentRun({
    required this.id,
    required this.kind,
    required this.status,
    required this.model,
    this.title,
    this.inputPreview,
    this.outputPreview,
    this.retryPrompt,
    this.retryAttachments = const [],
    this.contextAttachmentCount = 0,
    required this.startedAt,
    this.endedAt,
    this.tokenUsage = const TokenUsage(),
    this.error,
    this.cancelRequested = false,
    this.events = const [],
    this.spans = const [],
    this.changedFiles = const [],
    this.commandSummaries = const [],
    this.checkpointId,
    this.agentTaskId,
    this.parentRunId,
    this.approvalId,
    this.artifactId,
    this.mascotAlias,
    this.acceptsLegacyEvents = true,
  });

  AgentRun copyWith({
    AgentRunStatus? status,
    String? model,
    String? title,
    String? inputPreview,
    String? outputPreview,
    String? retryPrompt,
    List<ContextAttachment>? retryAttachments,
    int? contextAttachmentCount,
    DateTime? endedAt,
    TokenUsage? tokenUsage,
    Object? error = _sentinel,
    bool? cancelRequested,
    List<AgentRunEvent>? events,
    List<AgentTraceSpan>? spans,
    List<String>? changedFiles,
    List<String>? commandSummaries,
    Object? checkpointId = _sentinel,
    Object? agentTaskId = _sentinel,
    Object? parentRunId = _sentinel,
    Object? approvalId = _sentinel,
    Object? artifactId = _sentinel,
    Object? mascotAlias = _sentinel,
    bool? acceptsLegacyEvents,
  }) {
    return AgentRun(
      id: id,
      kind: kind,
      status: status ?? this.status,
      model: model ?? this.model,
      title: title ?? this.title,
      inputPreview: inputPreview ?? this.inputPreview,
      outputPreview: outputPreview ?? this.outputPreview,
      retryPrompt: retryPrompt ?? this.retryPrompt,
      retryAttachments: retryAttachments ?? this.retryAttachments,
      contextAttachmentCount:
          contextAttachmentCount ?? this.contextAttachmentCount,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      tokenUsage: tokenUsage ?? this.tokenUsage,
      error: identical(error, _sentinel) ? this.error : error as String?,
      cancelRequested: cancelRequested ?? this.cancelRequested,
      events: events ?? this.events,
      spans: spans ?? this.spans,
      changedFiles: changedFiles ?? this.changedFiles,
      commandSummaries: commandSummaries ?? this.commandSummaries,
      checkpointId: identical(checkpointId, _sentinel)
          ? this.checkpointId
          : checkpointId as String?,
      agentTaskId: identical(agentTaskId, _sentinel)
          ? this.agentTaskId
          : agentTaskId as String?,
      parentRunId: identical(parentRunId, _sentinel)
          ? this.parentRunId
          : parentRunId as String?,
      approvalId: identical(approvalId, _sentinel)
          ? this.approvalId
          : approvalId as String?,
      artifactId: identical(artifactId, _sentinel)
          ? this.artifactId
          : artifactId as String?,
      mascotAlias: identical(mascotAlias, _sentinel)
          ? this.mascotAlias
          : mascotAlias as String?,
      acceptsLegacyEvents: acceptsLegacyEvents ?? this.acceptsLegacyEvents,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind.name,
      'status': status.name,
      'model': model,
      'title': title,
      'inputPreview': inputPreview,
      'outputPreview': outputPreview,
      'retryPrompt': retryPrompt,
      'retryAttachments': retryAttachments
          .map((attachment) => attachment.toJson())
          .toList(),
      'contextAttachmentCount': contextAttachmentCount,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': endedAt?.toIso8601String(),
      'promptTokens': tokenUsage.promptTokens,
      'completionTokens': tokenUsage.completionTokens,
      'totalTokens': tokenUsage.totalTokens,
      'error': error,
      'cancelRequested': cancelRequested,
      'changedFiles': changedFiles,
      'commandSummaries': commandSummaries,
      'checkpointId': checkpointId,
      'agentTaskId': agentTaskId,
      'parentRunId': parentRunId,
      'approvalId': approvalId,
      'artifactId': artifactId,
      'mascotAlias': mascotAlias,
      'acceptsLegacyEvents': acceptsLegacyEvents,
      'events': events
          .map(
            (event) => {
              'type': event.type.name,
              'timestamp': event.timestamp.toIso8601String(),
              'message': event.message,
              'requestId': event.requestId,
              'metadata': event.metadata,
            },
          )
          .toList(),
      'spans': spans
          .map(
            (span) => {
              'id': span.id,
              'requestId': span.requestId,
              'kind': span.kind.name,
              'name': span.name,
              'startedAt': span.startedAt.toIso8601String(),
              'endedAt': span.endedAt?.toIso8601String(),
              'detail': span.detail,
              'metadata': span.metadata,
              'failed': span.failed,
            },
          )
          .toList(),
    };
  }

  static AgentRun? fromJson(Map<String, dynamic> json) {
    try {
      final kind = AgentRunKind.values.firstWhere(
        (value) => value.name == json['kind'],
      );
      final status = AgentRunStatus.values.firstWhere(
        (value) => value.name == json['status'],
      );
      final events = (json['events'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((event) {
            return AgentRunEvent(
              type: AgentRunEventType.values.firstWhere(
                (value) => value.name == event['type'],
                orElse: () => AgentRunEventType.started,
              ),
              timestamp:
                  DateTime.tryParse(event['timestamp'] as String? ?? '') ??
                  DateTime.now(),
              message: event['message'] as String? ?? '',
              requestId: event['requestId'] as String?,
              metadata:
                  (event['metadata'] as Map<String, dynamic>?)?.map(
                    (key, value) => MapEntry(key, value.toString()),
                  ) ??
                  const {},
            );
          })
          .toList();
      final spans = (json['spans'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((span) {
            return AgentTraceSpan(
              id: span['id'] as String? ?? '',
              requestId: span['requestId'] as String?,
              kind: AgentTraceSpanKind.values.firstWhere(
                (value) => value.name == span['kind'],
                orElse: () => AgentTraceSpanKind.run,
              ),
              name: span['name'] as String? ?? 'run',
              startedAt:
                  DateTime.tryParse(span['startedAt'] as String? ?? '') ??
                  DateTime.now(),
              endedAt: DateTime.tryParse(span['endedAt'] as String? ?? ''),
              detail: span['detail'] as String?,
              metadata:
                  (span['metadata'] as Map<String, dynamic>?)?.map(
                    (key, value) => MapEntry(key, value.toString()),
                  ) ??
                  const {},
              failed: span['failed'] as bool? ?? false,
            );
          })
          .toList();
      final retryAttachments =
          (json['retryAttachments'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(ContextAttachment.fromJson)
              .nonNulls
              .toList();
      return AgentRun(
        id: json['id'] as String,
        kind: kind,
        status: status,
        model: json['model'] as String? ?? 'gpt-5-nano',
        title: json['title'] as String?,
        inputPreview: json['inputPreview'] as String?,
        outputPreview: json['outputPreview'] as String?,
        retryPrompt: json['retryPrompt'] as String?,
        retryAttachments: retryAttachments,
        contextAttachmentCount: json['contextAttachmentCount'] as int? ?? 0,
        startedAt: DateTime.parse(json['startedAt'] as String),
        endedAt: DateTime.tryParse(json['endedAt'] as String? ?? ''),
        tokenUsage: TokenUsage(
          promptTokens: json['promptTokens'] as int? ?? 0,
          completionTokens: json['completionTokens'] as int? ?? 0,
          totalTokens: json['totalTokens'] as int? ?? 0,
        ),
        error: json['error'] as String?,
        cancelRequested: json['cancelRequested'] as bool? ?? false,
        events: events,
        spans: spans,
        changedFiles:
            (json['changedFiles'] as List<dynamic>?)?.cast<String>() ??
            const [],
        commandSummaries:
            (json['commandSummaries'] as List<dynamic>?)?.cast<String>() ??
            const [],
        checkpointId: json['checkpointId'] as String?,
        agentTaskId: json['agentTaskId'] as String?,
        parentRunId: json['parentRunId'] as String?,
        approvalId: json['approvalId'] as String?,
        artifactId: json['artifactId'] as String?,
        mascotAlias: json['mascotAlias'] as String?,
        acceptsLegacyEvents: json['acceptsLegacyEvents'] as bool? ?? true,
      );
    } catch (_) {
      return null;
    }
  }
}

const _sentinel = Object();
