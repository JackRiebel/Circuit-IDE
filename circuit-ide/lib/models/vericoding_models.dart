import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum VericodeCheckType { dartAnalyze, flutterTest, customCommand, flutterFormat }

class VericodeCheck {
  final String id;
  final String name;
  final String command;
  final VericodeCheckType type;
  final bool enabled;
  final int order;
  final int timeoutSeconds;

  const VericodeCheck({
    required this.id,
    required this.name,
    required this.command,
    required this.type,
    this.enabled = true,
    this.order = 0,
    this.timeoutSeconds = 60,
  });

  VericodeCheck copyWith({
    String? name,
    String? command,
    VericodeCheckType? type,
    bool? enabled,
    int? order,
    int? timeoutSeconds,
  }) {
    return VericodeCheck(
      id: id,
      name: name ?? this.name,
      command: command ?? this.command,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
      order: order ?? this.order,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'command': command,
        'type': type.name,
        'enabled': enabled,
        'order': order,
        'timeoutSeconds': timeoutSeconds,
      };

  factory VericodeCheck.fromJson(Map<String, dynamic> json) => VericodeCheck(
        id: json['id'] as String,
        name: json['name'] as String,
        command: json['command'] as String,
        type: VericodeCheckType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => VericodeCheckType.customCommand,
        ),
        enabled: json['enabled'] as bool? ?? true,
        order: json['order'] as int? ?? 0,
        timeoutSeconds: json['timeoutSeconds'] as int? ?? 60,
      );
}

enum VericodeRunStatus {
  idle,
  runningChecks,
  analyzingFailures,
  fixing,
  rerunning,
  passed,
  failed,
}

class VericodeResult {
  final String checkId;
  final String checkName;
  final bool passed;
  final String output;
  final int exitCode;
  final Duration duration;

  const VericodeResult({
    required this.checkId,
    required this.checkName,
    required this.passed,
    required this.output,
    required this.exitCode,
    required this.duration,
  });
}

class VericodeFixAttempt {
  final int attemptNumber;
  final List<VericodeResult> results;
  final String? aiFixResponse;
  final DateTime timestamp;

  const VericodeFixAttempt({
    required this.attemptNumber,
    required this.results,
    this.aiFixResponse,
    required this.timestamp,
  });
}

class VericodeRun {
  final String id;
  final VericodeRunStatus status;
  final List<VericodeResult> currentResults;
  final List<VericodeFixAttempt> attempts;
  final int maxRetries;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String? triggerSource;

  VericodeRun({
    String? id,
    this.status = VericodeRunStatus.idle,
    this.currentResults = const [],
    this.attempts = const [],
    this.maxRetries = 3,
    DateTime? startedAt,
    this.completedAt,
    this.triggerSource,
  })  : id = id ?? _uuid.v4().substring(0, 8),
        startedAt = startedAt ?? DateTime.now();

  VericodeRun copyWith({
    VericodeRunStatus? status,
    List<VericodeResult>? currentResults,
    List<VericodeFixAttempt>? attempts,
    DateTime? completedAt,
  }) {
    return VericodeRun(
      id: id,
      status: status ?? this.status,
      currentResults: currentResults ?? this.currentResults,
      attempts: attempts ?? this.attempts,
      maxRetries: maxRetries,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
      triggerSource: triggerSource,
    );
  }
}

class VericodeConfig {
  final List<VericodeCheck> checks;
  final bool autoRunAfterEdit;
  final int maxRetries;
  final bool enabled;

  const VericodeConfig({
    this.checks = const [],
    this.autoRunAfterEdit = true,
    this.maxRetries = 3,
    this.enabled = true,
  });

  VericodeConfig copyWith({
    List<VericodeCheck>? checks,
    bool? autoRunAfterEdit,
    int? maxRetries,
    bool? enabled,
  }) {
    return VericodeConfig(
      checks: checks ?? this.checks,
      autoRunAfterEdit: autoRunAfterEdit ?? this.autoRunAfterEdit,
      maxRetries: maxRetries ?? this.maxRetries,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'checks': checks.map((c) => c.toJson()).toList(),
        'autoRunAfterEdit': autoRunAfterEdit,
        'maxRetries': maxRetries,
        'enabled': enabled,
      };

  factory VericodeConfig.fromJson(Map<String, dynamic> json) => VericodeConfig(
        checks: (json['checks'] as List<dynamic>?)
                ?.map((c) =>
                    VericodeCheck.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [],
        autoRunAfterEdit: json['autoRunAfterEdit'] as bool? ?? true,
        maxRetries: json['maxRetries'] as int? ?? 3,
        enabled: json['enabled'] as bool? ?? true,
      );
}
