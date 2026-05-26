import 'token_usage.dart';

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
}

const _sentinel = Object();
