import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../enums/event_type.dart';
import '../enums/tool_status.dart';
import '../agent/security/agent_tool_permission_policy.dart';
import '../models/command_run.dart';
import '../models/agent_tool_permission.dart';
import '../models/tool_call_info.dart';
import '../models/turn_intent.dart';
import '../agent/tools/command_tools.dart';
import 'agent_turn_runtime_provider.dart';
import 'agent_workspace_provider.dart';
import 'studio_turn_provider.dart';
import 'work_item_provider.dart';
import '../services/event_bus.dart';
import '../services/versioned_json_document.dart';
import '../core/utils/platform_utils.dart';
import 'file_tree_provider.dart';

class CommandRunStore {
  static const _kind = 'circuit.command-run-history';
  static const _schemaVersion = 1;

  final String baseDir;

  CommandRunStore({String? baseDir})
    : baseDir = baseDir ?? p.join(PlatformUtils.configDir, 'command_runs');

  String historyPath(String? rootPath) =>
      p.join(baseDir, '${WorkItemStore.projectKey(rootPath)}.json');

  String logPath(String? rootPath, String runId) =>
      p.join(baseDir, WorkItemStore.projectKey(rootPath), 'logs', '$runId.log');

  Future<List<CommandRun>> load(String? rootPath) async {
    final file = File(historyPath(rootPath));
    if (!await file.exists()) return const [];
    final document = VersionedJsonDocument.decode(
      jsonDecode(await file.readAsString()),
      expectedKind: _kind,
      currentSchemaVersion: _schemaVersion,
    );
    final payload = document.payload;
    if (payload is! List) {
      throw const FormatException('Command history is invalid.');
    }
    return payload
        .whereType<Map<String, dynamic>>()
        .map(CommandRun.fromJson)
        .nonNulls
        .toList(growable: false);
  }

  Future<void> save(String? rootPath, Iterable<CommandRun> runs) =>
      writeVersionedJsonAtomically(
        File(historyPath(rootPath)),
        VersionedJsonDocument(
          kind: _kind,
          schemaVersion: _schemaVersion,
          payload: runs.map((run) => run.toJson()).toList(growable: false),
        ).encode(pretty: true),
      );

  Future<void> appendLog(String path, String text) async {
    final file = File(path);
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsString(text, mode: FileMode.append, flush: true);
  }
}

final commandRunStoreProvider = Provider<CommandRunStore>(
  (ref) => CommandRunStore(),
);

class CommandRunController extends Notifier<Map<String, CommandRun>> {
  final Map<String, String> _lastOutputById = {};
  final Map<String, _CommandRunEventBinding> _runtimeEventBindings = {};
  final Map<String, CommandTools> _directCommandTools = {};

  @override
  Map<String, CommandRun> build() {
    Future.microtask(_loadForWorkspace);
    ref.listen(fileTreeProvider, (previous, next) {
      if (previous?.rootPath != next.rootPath) {
        state = const {};
        Future.microtask(_loadForWorkspace);
      }
    });
    ref.onDispose(() {
      for (final binding in _runtimeEventBindings.values) {
        binding.dispose();
      }
      _runtimeEventBindings.clear();
      _directCommandTools.clear();
    });
    return const {};
  }

  Future<void> _loadForWorkspace() async {
    if (!ref.mounted || state.isNotEmpty) return;
    final rootPath = ref.read(fileTreeProvider).rootPath;
    try {
      final store = ref.read(commandRunStoreProvider);
      final loaded = await store.load(rootPath);
      if (!ref.mounted || ref.read(fileTreeProvider).rootPath != rootPath) {
        return;
      }
      final now = DateTime.now();
      final recovered = [
        for (final run in loaded)
          if (run.status == CommandRunStatus.running ||
              run.status == CommandRunStatus.queued)
            run.copyWith(
              status: CommandRunStatus.failed,
              endedAt: now,
              exitReason: CommandExitReason.interrupted,
              events: [
                ...run.events,
                CommandRunEvent(
                  type: CommandRunEventType.exited,
                  timestamp: now,
                  text: 'interrupted after app restart',
                ),
              ].takeLast(80),
            )
          else
            run,
      ];
      state = {for (final run in recovered) run.id: run};
      if (recovered.length == loaded.length &&
          recovered.any(
            (run) => run.exitReason == CommandExitReason.interrupted,
          )) {
        await store.save(rootPath, recovered);
      }
    } catch (_) {
      // A malformed command history must not block Studio; the log files stay
      // untouched for manual support recovery.
    }
  }

  void _persist() {
    if (!ref.mounted) return;
    final rootPath = ref.read(fileTreeProvider).rootPath;
    unawaited(ref.read(commandRunStoreProvider).save(rootPath, state.values));
  }

  void start({
    required String id,
    required String command,
    String? requestId,
    String? turnId,
    String? taskId,
    String workingDirectory = '',
    int timeoutSeconds = 120,
    String? providedLogPath,
  }) {
    final now = DateTime.now();
    final attachedTaskId = taskId ?? _taskIdForCommandRun();
    final logPath =
        providedLogPath ??
        ref
            .read(commandRunStoreProvider)
            .logPath(ref.read(fileTreeProvider).rootPath, id);
    state = {
      ...state,
      id: CommandRun(
        id: id,
        requestId: requestId,
        turnId: turnId,
        taskId: attachedTaskId,
        command: command,
        workingDirectory: workingDirectory,
        timeoutSeconds: timeoutSeconds,
        logPath: logPath,
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
    unawaited(
      ref
          .read(commandRunStoreProvider)
          .appendLog(logPath, '[$now] started: $command\n'),
    );
    _persist();
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

  void append(
    String id,
    CommandRunEventType type,
    String text, {
    int? processId,
  }) {
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
        processId: processId ?? current.processId,
        events: [...current.events, event].takeLast(80),
      ),
    };
    final path = state[id]?.logPath;
    if (path != null) {
      unawaited(
        ref
            .read(commandRunStoreProvider)
            .appendLog(
              path,
              '[${event.timestamp.toIso8601String()}] ${type.name}: $text',
            ),
      );
    }
    _persist();
  }

  void _setProcessMetadata(String id, int? processId, int? processGroupId) {
    if (processId == null && processGroupId == null) return;
    final current = state[id];
    if (current == null ||
        (current.processId == processId &&
            current.processGroupId == processGroupId)) {
      return;
    }
    state = {
      ...state,
      id: current.copyWith(
        processId: processId,
        processGroupId: processGroupId,
      ),
    };
    _persist();
  }

  void finish(String id, {required CommandRunStatus status, int? exitCode}) {
    final current = state[id];
    if (current == null) return;
    final completed = current.copyWith(
      status: status,
      endedAt: DateTime.now(),
      exitCode: exitCode,
      exitReason: _exitReasonForStatus(status),
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
    final path = completed.logPath;
    if (path != null) {
      unawaited(
        ref
            .read(commandRunStoreProvider)
            .appendLog(
              path,
              '[${completed.endedAt?.toIso8601String() ?? ''}] ${completed.exitReason?.name ?? status.name}\n',
            ),
      );
    }
    _persist();
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
    bool userApproved = false,
  }) async {
    start(
      id: id,
      command: command,
      requestId: requestId,
      turnId: turnId,
      taskId: taskId,
      workingDirectory: workingDir,
      timeoutSeconds: timeout,
    );
    ref.read(workItemProvider.notifier).recordCommandRun(id, command);

    // This route is only invoked after an explicit verification action in the
    // UI. Reify that action as a grant scoped to this exact command; callers
    // that do not carry that approval remain blocked at the policy boundary.
    final toolCall = ToolCallInfo(
      id: id,
      name: 'run_command',
      arguments: {'command': command, 'timeout': timeout},
    );
    final basePolicy = AgentToolPermissionPolicy(
      workingDir: workingDir,
      request: const ToolPermissionRequest(
        intent: TurnIntent.verify,
        phase: ToolPermissionPhase.verify,
      ),
    );
    final decision = AgentToolPermissionPolicy(
      workingDir: workingDir,
      request: ToolPermissionRequest(
        intent: TurnIntent.verify,
        phase: ToolPermissionPhase.verify,
        approvalGrant: userApproved ? ApprovalGrant.turn : ApprovalGrant.none,
        approvalGrantKey: userApproved
            ? basePolicy.approvalGrantKeyFor(toolCall)
            : null,
      ),
    ).evaluate(toolCall);
    if (!decision.allowed) {
      append(id, CommandRunEventType.stderr, decision.message);
      finish(id, status: CommandRunStatus.blocked);
      return state[id]!;
    }

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
          _setProcessMetadata(id, event.processId, event.processGroupId);
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

CommandExitReason _exitReasonForStatus(CommandRunStatus status) {
  return switch (status) {
    CommandRunStatus.succeeded => CommandExitReason.completed,
    CommandRunStatus.cancelled => CommandExitReason.cancelled,
    CommandRunStatus.timedOut => CommandExitReason.timedOut,
    CommandRunStatus.blocked => CommandExitReason.blocked,
    CommandRunStatus.failed => CommandExitReason.failed,
    CommandRunStatus.queued ||
    CommandRunStatus.running => CommandExitReason.interrupted,
  };
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
  // A launched command reaches this fallback only if it did not deliver its
  // terminal process event. Never promote an output-only result to success:
  // a missing exit status is inconclusive, particularly at the broker
  // boundary where a launcher can report diagnostics without a child result.
  if (exitCode == null) return CommandRunStatus.failed;
  if (exitCode != 0) return CommandRunStatus.failed;
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
