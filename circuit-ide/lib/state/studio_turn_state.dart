part of 'studio_turn_provider.dart';

/// Stable request-to-turn references retained while a turn is active or
/// shortly after it completes for late lifecycle events.
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

/// Request-indexed turn ownership for the Studio turn controller.
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
