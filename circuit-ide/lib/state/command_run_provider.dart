import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../enums/event_type.dart';
import '../enums/tool_status.dart';
import '../models/command_run.dart';
import '../models/tool_call_info.dart';
import 'agent_turn_runtime_provider.dart';
import 'agent_workspace_provider.dart';
import 'connection_provider.dart';
import 'work_item_provider.dart';
import '../services/event_bus.dart';

class CommandRunController extends Notifier<Map<String, CommandRun>> {
  final Map<String, String> _lastOutputById = {};
  bool _listening = false;

  @override
  Map<String, CommandRun> build() {
    _listenToAgentEvents();
    return const {};
  }

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
    final taskId = _taskIdForCommandRun();
    if (taskId != null) {
      ref
          .read(agentWorkspaceProvider.notifier)
          .attachCommandRun(taskId, id, command);
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

  void cancelRunningCommands() {
    ref.read(agentServiceProvider).cancelActiveCommands();
    for (final entry in state.entries) {
      if (entry.value.status == CommandRunStatus.running ||
          entry.value.status == CommandRunStatus.queued) {
        finish(entry.key, status: CommandRunStatus.cancelled);
      }
    }
  }

  void _listenToAgentEvents() {
    if (_listening) return;
    _listening = true;
    final events = ref.read(agentServiceProvider).events;
    events.on(EventType.toolCallStarted, _handleToolEvent);
    events.on(EventType.toolCallCompleted, _handleToolEvent);
    events.on(EventType.toolCallError, _handleToolEvent);
  }

  void _handleToolEvent(Event event) {
    final toolCall = event.data['toolCall'] as ToolCallInfo?;
    if (toolCall == null || toolCall.name != 'run_command') return;
    final command = toolCall.arguments['command'] as String? ?? 'command';
    final id = toolCall.id;
    if (!state.containsKey(id)) {
      start(id: id, command: command);
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
