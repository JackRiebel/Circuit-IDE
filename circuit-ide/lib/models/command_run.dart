enum CommandRunStatus {
  queued,
  running,
  succeeded,
  failed,
  cancelled,
  timedOut,
  blocked,
}

enum CommandExitReason {
  completed,
  cancelled,
  timedOut,
  blocked,
  failed,
  interrupted,
}

enum CommandRunEventType {
  started,
  stdout,
  stderr,
  exited,
  cancelled,
  timedOut,
  blocked,
}

class CommandRunEvent {
  final CommandRunEventType type;
  final DateTime timestamp;
  final String text;
  final int? processId;
  final int? processGroupId;

  const CommandRunEvent({
    required this.type,
    required this.timestamp,
    required this.text,
    this.processId,
    this.processGroupId,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'timestamp': timestamp.toIso8601String(),
    'text': text,
    if (processId != null) 'processId': processId,
    if (processGroupId != null) 'processGroupId': processGroupId,
  };

  static CommandRunEvent? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    try {
      return CommandRunEvent(
        type: CommandRunEventType.values.firstWhere(
          (value) => value.name == json['type'],
          orElse: () => CommandRunEventType.exited,
        ),
        timestamp:
            DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        text: json['text'] as String? ?? '',
        processId: json['processId'] as int?,
        processGroupId: json['processGroupId'] as int?,
      );
    } catch (_) {
      return null;
    }
  }
}

class CommandRun {
  final String id;
  final String? requestId;
  final String? turnId;
  final String? taskId;
  final String command;
  final String workingDirectory;
  final int timeoutSeconds;
  final String environmentPolicy;
  final String? logPath;
  final int? processId;
  final int? processGroupId;
  final CommandRunStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? exitCode;
  final CommandExitReason? exitReason;
  final String stdout;
  final String stderr;
  final List<CommandRunEvent> events;

  const CommandRun({
    required this.id,
    this.requestId,
    this.turnId,
    this.taskId,
    required this.command,
    this.workingDirectory = '',
    this.timeoutSeconds = 120,
    this.environmentPolicy = 'sanitized-allowlist',
    this.logPath,
    this.processId,
    this.processGroupId,
    required this.status,
    required this.startedAt,
    this.endedAt,
    this.exitCode,
    this.exitReason,
    this.stdout = '',
    this.stderr = '',
    this.events = const [],
  });

  Duration get elapsed => (endedAt ?? DateTime.now()).difference(startedAt);

  String get combinedOutput {
    final buffer = StringBuffer();
    if (stdout.trim().isNotEmpty) buffer.writeln(stdout.trim());
    if (stderr.trim().isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('[stderr] ${stderr.trim()}');
    }
    if (exitCode != null && exitCode != 0) {
      buffer.writeln('\n[exit code: $exitCode]');
    }
    final text = buffer.toString().trim();
    return text.isEmpty ? '(no output)' : text;
  }

  CommandRun copyWith({
    String? requestId,
    String? turnId,
    String? taskId,
    String? workingDirectory,
    int? timeoutSeconds,
    String? environmentPolicy,
    String? logPath,
    int? processId,
    int? processGroupId,
    CommandRunStatus? status,
    DateTime? endedAt,
    int? exitCode,
    CommandExitReason? exitReason,
    String? stdout,
    String? stderr,
    List<CommandRunEvent>? events,
  }) {
    return CommandRun(
      id: id,
      requestId: requestId ?? this.requestId,
      turnId: turnId ?? this.turnId,
      taskId: taskId ?? this.taskId,
      command: command,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      environmentPolicy: environmentPolicy ?? this.environmentPolicy,
      logPath: logPath ?? this.logPath,
      processId: processId ?? this.processId,
      processGroupId: processGroupId ?? this.processGroupId,
      status: status ?? this.status,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      exitCode: exitCode ?? this.exitCode,
      exitReason: exitReason ?? this.exitReason,
      stdout: stdout ?? this.stdout,
      stderr: stderr ?? this.stderr,
      events: events ?? this.events,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (requestId != null) 'requestId': requestId,
    if (turnId != null) 'turnId': turnId,
    if (taskId != null) 'taskId': taskId,
    'command': command,
    'workingDirectory': workingDirectory,
    'timeoutSeconds': timeoutSeconds,
    'environmentPolicy': environmentPolicy,
    if (logPath != null) 'logPath': logPath,
    if (processId != null) 'processId': processId,
    if (processGroupId != null) 'processGroupId': processGroupId,
    'status': status.name,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'exitCode': exitCode,
    'exitReason': exitReason?.name,
    'stdout': stdout,
    'stderr': stderr,
    'events': events.map((event) => event.toJson()).toList(),
  };

  static CommandRun? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    try {
      return CommandRun(
        id: json['id'] as String? ?? '',
        requestId: json['requestId'] as String?,
        turnId: json['turnId'] as String?,
        taskId: json['taskId'] as String?,
        command: json['command'] as String? ?? '',
        workingDirectory: json['workingDirectory'] as String? ?? '',
        timeoutSeconds: json['timeoutSeconds'] as int? ?? 120,
        environmentPolicy:
            json['environmentPolicy'] as String? ?? 'sanitized-allowlist',
        logPath: json['logPath'] as String?,
        processId: json['processId'] as int?,
        processGroupId: json['processGroupId'] as int?,
        status: CommandRunStatus.values.firstWhere(
          (value) => value.name == json['status'],
          orElse: () => CommandRunStatus.failed,
        ),
        startedAt:
            DateTime.tryParse(json['startedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        endedAt: DateTime.tryParse(json['endedAt'] as String? ?? ''),
        exitCode: json['exitCode'] as int?,
        exitReason: (json['exitReason'] as String?) == null
            ? null
            : CommandExitReason.values.firstWhere(
                (value) => value.name == json['exitReason'],
                orElse: () => CommandExitReason.failed,
              ),
        stdout: json['stdout'] as String? ?? '',
        stderr: json['stderr'] as String? ?? '',
        events: (json['events'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(CommandRunEvent.fromJson)
            .nonNulls
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }
}
