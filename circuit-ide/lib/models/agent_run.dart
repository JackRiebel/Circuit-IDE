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
  tokenUsage,
  completed,
  failed,
  cancelled,
}

class AgentTraceSpan {
  final String id;
  final String name;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? detail;
  final bool failed;

  const AgentTraceSpan({
    required this.id,
    required this.name,
    required this.startedAt,
    this.endedAt,
    this.detail,
    this.failed = false,
  });

  AgentTraceSpan copyWith({DateTime? endedAt, String? detail, bool? failed}) {
    return AgentTraceSpan(
      id: id,
      name: name,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      detail: detail ?? this.detail,
      failed: failed ?? this.failed,
    );
  }
}

class AgentRunEvent {
  final AgentRunEventType type;
  final DateTime timestamp;
  final String message;

  const AgentRunEvent({
    required this.type,
    required this.timestamp,
    required this.message,
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
      'events': events
          .map(
            (event) => {
              'type': event.type.name,
              'timestamp': event.timestamp.toIso8601String(),
              'message': event.message,
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
      );
    } catch (_) {
      return null;
    }
  }
}

const _sentinel = Object();
