enum AgentRequestLane { chat, inlineCompletion, editPrediction, backgroundTask }

enum AgentRequestStatus {
  idle,
  queued,
  running,
  streaming,
  cancelling,
  done,
  failed,
}

class AgentRequestState {
  final AgentRequestLane lane;
  final AgentRequestStatus status;
  final String? requestId;
  final String? model;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? error;
  final bool cancelRequested;

  const AgentRequestState({
    required this.lane,
    this.status = AgentRequestStatus.idle,
    this.requestId,
    this.model,
    this.startedAt,
    this.endedAt,
    this.error,
    this.cancelRequested = false,
  });

  AgentRequestState copyWith({
    AgentRequestStatus? status,
    String? requestId,
    String? model,
    DateTime? startedAt,
    DateTime? endedAt,
    Object? error = _sentinel,
    bool? cancelRequested,
  }) {
    return AgentRequestState(
      lane: lane,
      status: status ?? this.status,
      requestId: requestId ?? this.requestId,
      model: model ?? this.model,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      error: identical(error, _sentinel) ? this.error : error as String?,
      cancelRequested: cancelRequested ?? this.cancelRequested,
    );
  }
}

class AgentRequestHandle {
  final AgentRequestLane lane;
  final String requestId;
  final void Function() _cancel;
  bool _cancelRequested = false;

  AgentRequestHandle({
    required this.lane,
    required this.requestId,
    required void Function() cancel,
  }) : _cancel = cancel;

  bool get cancelRequested => _cancelRequested;

  void cancel() {
    if (_cancelRequested) return;
    _cancelRequested = true;
    _cancel();
  }
}

const _sentinel = Object();
