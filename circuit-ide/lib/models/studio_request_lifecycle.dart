import 'studio_thread.dart';

enum StudioRequestLifecycleEventKind {
  requestStarted,
  waitingForModel,
  streaming,
  toolRunning,
  approvalNeeded,
  completed,
  failed,
  cancelled,
}

class StudioRequestLifecycleEntry {
  final String requestId;
  final String threadId;
  final String? taskId;
  final String model;
  final StudioContextSummary contextSummary;
  final DateTime startedAt;
  final DateTime lastEventAt;
  final StudioRequestLifecycleEventKind lastEventKind;
  final String? lastEventDetail;

  const StudioRequestLifecycleEntry({
    required this.requestId,
    required this.threadId,
    this.taskId,
    required this.model,
    required this.contextSummary,
    required this.startedAt,
    required this.lastEventAt,
    required this.lastEventKind,
    this.lastEventDetail,
  });

  StudioRequestLifecycleEntry copyWith({
    DateTime? lastEventAt,
    StudioRequestLifecycleEventKind? lastEventKind,
    Object? lastEventDetail = _sentinel,
  }) {
    return StudioRequestLifecycleEntry(
      requestId: requestId,
      threadId: threadId,
      taskId: taskId,
      model: model,
      contextSummary: contextSummary,
      startedAt: startedAt,
      lastEventAt: lastEventAt ?? this.lastEventAt,
      lastEventKind: lastEventKind ?? this.lastEventKind,
      lastEventDetail: identical(lastEventDetail, _sentinel)
          ? this.lastEventDetail
          : lastEventDetail as String?,
    );
  }
}

class StudioRequestLifecycleState {
  final Map<String, StudioRequestLifecycleEntry> activeRequests;
  final Map<String, StudioRequestLifecycleEntry> recentRequests;

  const StudioRequestLifecycleState({
    this.activeRequests = const {},
    this.recentRequests = const {},
  });

  StudioRequestLifecycleEntry? active(String requestId) =>
      activeRequests[requestId];

  StudioRequestLifecycleEntry? find(String requestId) =>
      activeRequests[requestId] ?? recentRequests[requestId];

  StudioRequestLifecycleState copyWith({
    Map<String, StudioRequestLifecycleEntry>? activeRequests,
    Map<String, StudioRequestLifecycleEntry>? recentRequests,
  }) {
    return StudioRequestLifecycleState(
      activeRequests: activeRequests ?? this.activeRequests,
      recentRequests: recentRequests ?? this.recentRequests,
    );
  }
}

const _sentinel = Object();
