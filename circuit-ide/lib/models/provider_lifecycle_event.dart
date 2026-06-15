enum ProviderLifecycleEventKind {
  requestSent,
  connected,
  firstByte,
  firstTextDelta,
  firstToolDelta,
  jsonFallback,
  completed,
  failed,
  cancelled,
}

class ProviderLifecycleEvent {
  final String requestId;
  final String? turnId;
  final ProviderLifecycleEventKind kind;
  final DateTime timestamp;
  final String model;
  final String? detail;
  final String? rawDiagnostic;

  const ProviderLifecycleEvent({
    required this.requestId,
    this.turnId,
    required this.kind,
    required this.timestamp,
    required this.model,
    this.detail,
    this.rawDiagnostic,
  });
}
