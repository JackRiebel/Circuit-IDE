import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/command_run.dart';

class CommandRunController extends Notifier<Map<String, CommandRun>> {
  @override
  Map<String, CommandRun> build() => const {};

  void start({required String id, required String command}) {
    final now = DateTime.now();
    state = {
      ...state,
      id: CommandRun(
        id: id,
        command: command,
        status: CommandRunStatus.running,
        startedAt: now,
        events: [
          CommandRunEvent(
            type: CommandRunEventType.started,
            timestamp: now,
            text: command,
          ),
        ],
      ),
    };
  }

  void append(String id, CommandRunEventType type, String text) {
    final current = state[id];
    if (current == null) return;
    final event = CommandRunEvent(
      type: type,
      timestamp: DateTime.now(),
      text: text,
    );
    state = {
      ...state,
      id: current.copyWith(
        stdout: type == CommandRunEventType.stdout
            ? current.stdout + text
            : current.stdout,
        stderr: type == CommandRunEventType.stderr
            ? current.stderr + text
            : current.stderr,
        events: [...current.events, event].takeLast(80),
      ),
    };
  }

  void finish(String id, {required CommandRunStatus status, int? exitCode}) {
    final current = state[id];
    if (current == null) return;
    state = {
      ...state,
      id: current.copyWith(
        status: status,
        endedAt: DateTime.now(),
        exitCode: exitCode,
        events: [
          ...current.events,
          CommandRunEvent(
            type: switch (status) {
              CommandRunStatus.cancelled => CommandRunEventType.cancelled,
              CommandRunStatus.timedOut => CommandRunEventType.timedOut,
              CommandRunStatus.blocked => CommandRunEventType.blocked,
              _ => CommandRunEventType.exited,
            },
            timestamp: DateTime.now(),
            text: exitCode == null ? status.name : 'exit $exitCode',
          ),
        ].takeLast(80),
      ),
    };
  }
}

extension _TakeLast<T> on List<T> {
  List<T> takeLast(int count) {
    if (length <= count) return this;
    return sublist(length - count);
  }
}

final commandRunProvider =
    NotifierProvider<CommandRunController, Map<String, CommandRun>>(
      CommandRunController.new,
    );
