import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../enums/event_type.dart';
import '../enums/tool_status.dart';
import '../models/command_run.dart';
import '../models/tool_call_info.dart';
import '../agent/tools/command_tools.dart';
import 'agent_turn_runtime_provider.dart';
import 'agent_workspace_provider.dart';
import 'studio_turn_provider.dart';
import 'work_item_provider.dart';
import '../services/event_bus.dart';

class CommandRunController extends Notifier<Map<String, CommandRun>> {
  final Map<String, String> _lastOutputById = {};
  final Map<String, _CommandRunEventBinding> _runtimeEventBindings = {};
  final Map<String, CommandTools> _directCommandTools = {};

  @override
  Map<String, CommandRun> build() {
    ref.onDispose(() {
      for (final binding in _runtimeEventBindings.values) {
        binding.dispose();
      }
      _runtimeEventBindings.clear();
      _directCommandTools.clear();
    });
    return const {};
  }

  void start({
    required String id,
    required String command,
    String? requestId,
    String? turnId,
    String? taskId,
  }) {
    final now = DateTime.now();
    final attachedTaskId = taskId ?? _taskIdForCommandRun();
    state = {
      ...state,
      id: CommandRun(
        id: id,
        requestId: requestId,
        turnId: turnId,
        taskId: attachedTaskId,
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
    if (attachedTaskId != null) {
      ref
          .read(agentWorkspaceProvider.notifier)
          .attachCommandRun(attachedTaskId, id, command);
    }
  }

  String? _taskIdForCommandRun() {
    final activeStudioSessions = ref
        .read(agentTurnRuntimeProvider)
        .activeSessions
        .values
        .toList(growable: false);
    if (activeStudioSessions.isNotEmpty) {
      return activeStudioSessions.length == 1
          ? activeStudioSessions.single.taskId
          : null;
    }
    return ref.read(agentWorkspaceProvider).selectedTask?.id;
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
    final completed = current.copyWith(
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
    );
    state = {...state, id: completed};
    final requestId = completed.requestId;
    if (requestId != null) {
      ref
          .read(studioTurnProvider.notifier)
          .recordCommandRunResult(
            requestId,
            commandRunId: id,
            command: completed.command,
            status: completed.status.name,
            output: completed.combinedOutput,
            exitCode: completed.exitCode,
          );
    }
  }

  Future<CommandRun> runVerificationCommand({
    required String id,
    required String command,
    required String workingDir,
    String? requestId,
    String? turnId,
    String? taskId,
    int timeout = 120,
  }) async {
    start(
      id: id,
      command: command,
      requestId: requestId,
      turnId: turnId,
      taskId: taskId,
    );
    ref.read(workItemProvider.notifier).recordCommandRun(id, command);
    final commandTools = CommandTools(workingDir: workingDir);
    _directCommandTools[id] = commandTools;

    void finishIfNeeded(CommandRunStatus status, {int? exitCode}) {
      final current = state[id];
      if (current == null || _isTerminal(current.status)) return;
      finish(id, status: status, exitCode: exitCode);
    }

    void handleEvent(CommandRunEvent event) {
      switch (event.type) {
        case CommandRunEventType.started:
          break;
        case CommandRunEventType.stdout:
        case CommandRunEventType.stderr:
          append(id, event.type, event.text);
          break;
        case CommandRunEventType.blocked:
          append(id, CommandRunEventType.stderr, event.text);
          finishIfNeeded(CommandRunStatus.blocked);
          break;
        case CommandRunEventType.timedOut:
          append(id, CommandRunEventType.stderr, event.text);
          finishIfNeeded(CommandRunStatus.timedOut);
          break;
        case CommandRunEventType.cancelled:
          finishIfNeeded(CommandRunStatus.cancelled);
          break;
        case CommandRunEventType.exited:
          final exitCode = _exitCodeFromEvent(event);
          finishIfNeeded(
            exitCode == 0
                ? CommandRunStatus.succeeded
                : CommandRunStatus.failed,
            exitCode: exitCode,
          );
          break;
      }
    }

    try {
      final output = await commandTools.runCommand(
        {'command': command, 'timeout': timeout},
        runId: id,
        onEvent: handleEvent,
      );
      final current = state[id];
      if (current != null && !_isTerminal(current.status)) {
        final exitCode = _exitCodeFromOutput(output);
        final status = _statusFromOutput(output, exitCode: exitCode);
        finishIfNeeded(status, exitCode: exitCode);
      }
    } finally {
      _directCommandTools.remove(id);
    }

    return state[id]!;
  }

  bool cancel(String id) {
    final killed = _directCommandTools.remove(id)?.cancel(id) ?? false;
    if (killed) {
      finish(id, status: CommandRunStatus.cancelled);
      return true;
    }
    final current = state[id];
    if (current != null &&
        (current.status == CommandRunStatus.running ||
            current.status == CommandRunStatus.queued)) {
      finish(id, status: CommandRunStatus.cancelled);
      return true;
    }
    return false;
  }

  void cancelRunningCommands() {
    for (final entry in state.entries) {
      if (entry.value.status == CommandRunStatus.running ||
          entry.value.status == CommandRunStatus.queued) {
        cancel(entry.key);
      }
    }
  }

  void attachRuntimeEvents(String requestId, EventBus events) {
    detachRuntimeEvents(requestId);
    final handlers = <EventType, EventHandler>{
      EventType.toolCallStarted: _handleToolEvent,
      EventType.toolCallCompleted: _handleToolEvent,
      EventType.toolCallError: _handleToolEvent,
    };
    for (final entry in handlers.entries) {
      events.on(entry.key, entry.value);
    }
    _runtimeEventBindings[requestId] = _CommandRunEventBinding(
      events: events,
      handlers: handlers,
    );
  }

  void detachRuntimeEvents(String requestId) {
    _runtimeEventBindings.remove(requestId)?.dispose();
  }

  void _handleToolEvent(Event event) {
    final toolCall = event.data['toolCall'] as ToolCallInfo?;
    if (toolCall == null || toolCall.name != 'run_command') return;
    final command = toolCall.arguments['command'] as String? ?? 'command';
    final id = toolCall.id;
    final requestId = event.data['requestId'] as String?;
    final session = requestId == null
        ? null
        : ref.read(agentTurnRuntimeProvider).sessionFor(requestId);
    final turnId = requestId == null
        ? null
        : ref.read(studioTurnProvider).refForRequest(requestId)?.turnId;
    if (!state.containsKey(id)) {
      start(
        id: id,
        command: command,
        requestId: requestId,
        turnId: turnId,
        taskId: session?.taskId,
      );
      ref.read(workItemProvider.notifier).recordCommandRun(id, command);
    }

    final result = toolCall.result ?? '';
    final previous = _lastOutputById[id] ?? '';
    if (result.length > previous.length) {
      final delta = result.substring(previous.length);
      append(
        id,
        toolCall.error == null
            ? CommandRunEventType.stdout
            : CommandRunEventType.stderr,
        delta,
      );
      _lastOutputById[id] = result;
    }

    switch (toolCall.status) {
      case ToolStatus.success:
        finish(id, status: CommandRunStatus.succeeded, exitCode: 0);
        break;
      case ToolStatus.error:
        finish(id, status: CommandRunStatus.failed);
        break;
      case ToolStatus.cancelled:
        finish(id, status: CommandRunStatus.cancelled);
        break;
      case ToolStatus.pending:
      case ToolStatus.running:
        break;
    }
  }
}

bool _isTerminal(CommandRunStatus status) {
  return switch (status) {
    CommandRunStatus.succeeded ||
    CommandRunStatus.failed ||
    CommandRunStatus.cancelled ||
    CommandRunStatus.timedOut ||
    CommandRunStatus.blocked => true,
    CommandRunStatus.queued || CommandRunStatus.running => false,
  };
}

int? _exitCodeFromEvent(CommandRunEvent event) {
  final match = RegExp(r'exit\s+(-?\d+)').firstMatch(event.text.trim());
  return int.tryParse(match?.group(1) ?? '');
}

int? _exitCodeFromOutput(String output) {
  final match = RegExp(r'\[exit code:\s*(-?\d+)\]').firstMatch(output);
  return int.tryParse(match?.group(1) ?? '');
}

CommandRunStatus _statusFromOutput(String output, {int? exitCode}) {
  final normalized = output.trim().toLowerCase();
  if (normalized.startsWith('error: command timed out')) {
    return CommandRunStatus.timedOut;
  }
  if (normalized.startsWith('error:') && normalized.contains('blocked')) {
    return CommandRunStatus.blocked;
  }
  if (exitCode != null && exitCode != 0) return CommandRunStatus.failed;
  if (normalized.startsWith('error:')) return CommandRunStatus.failed;
  return CommandRunStatus.succeeded;
}

class _CommandRunEventBinding {
  final EventBus events;
  final Map<EventType, EventHandler> handlers;

  const _CommandRunEventBinding({required this.events, required this.handlers});

  void dispose() {
    for (final entry in handlers.entries) {
      events.off(entry.key, entry.value);
    }
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
