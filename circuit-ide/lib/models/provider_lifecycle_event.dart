enum ProviderLifecycleEventKind {
  requestSent,
  toolExposure,
  authFailed,
  connected,
  firstByte,
  noFirstByte,
  firstTextDelta,
  firstToolDelta,
  nonSseJson,
  jsonFallback,
  toolOnly,
  noTextOrTool,
  unavailableTool,
  rateLimited,
  malformedChunk,
  malformedBytes,
  streamEndedWithoutDone,
  outcomeRepair,
  completed,
  failed,
  cancelled,
  timeout,
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

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'turnId': turnId,
    'kind': kind.name,
    'timestamp': timestamp.toIso8601String(),
    'model': model,
    'detail': detail,
    'rawDiagnostic': rawDiagnostic,
  };

  static ProviderLifecycleEvent? fromJson(Map<String, dynamic> json) {
    try {
      return ProviderLifecycleEvent(
        requestId: json['requestId'] as String? ?? '',
        turnId: json['turnId'] as String?,
        kind: ProviderLifecycleEventKind.values.firstWhere(
          (value) => value.name == json['kind'],
          orElse: () => ProviderLifecycleEventKind.failed,
        ),
        timestamp:
            DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
        model: json['model'] as String? ?? '',
        detail: json['detail'] as String?,
        rawDiagnostic: json['rawDiagnostic'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
