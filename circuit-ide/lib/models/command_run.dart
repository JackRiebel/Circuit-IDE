enum CommandRunStatus {
  queued,
  running,
  succeeded,
  failed,
  cancelled,
  timedOut,
  blocked,
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

  const CommandRunEvent({
    required this.type,
    required this.timestamp,
    required this.text,
  });
}

class CommandRun {
  final String id;
  final String command;
  final CommandRunStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? exitCode;
  final String stdout;
  final String stderr;
  final List<CommandRunEvent> events;

  const CommandRun({
    required this.id,
    required this.command,
    required this.status,
    required this.startedAt,
    this.endedAt,
    this.exitCode,
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
    CommandRunStatus? status,
    DateTime? endedAt,
    int? exitCode,
    String? stdout,
    String? stderr,
    List<CommandRunEvent>? events,
  }) {
    return CommandRun(
      id: id,
      command: command,
      status: status ?? this.status,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      exitCode: exitCode ?? this.exitCode,
      stdout: stdout ?? this.stdout,
      stderr: stderr ?? this.stderr,
      events: events ?? this.events,
    );
  }
}
