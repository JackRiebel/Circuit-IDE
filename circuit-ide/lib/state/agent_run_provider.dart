import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/utils/platform_utils.dart';
import '../enums/event_type.dart';
import '../models/agent_run.dart';
import '../models/context_attachment.dart';
import '../models/token_usage.dart';
import '../models/tool_call_info.dart';
import 'connection_provider.dart';

class AgentRunState {
  final Map<AgentRunKind, AgentRun> activeRuns;
  final List<AgentRun> recentRuns;

  const AgentRunState({this.activeRuns = const {}, this.recentRuns = const []});

  AgentRun? get activeChatRun => activeRuns[AgentRunKind.chat];
  AgentRun? get latestRun =>
      activeRuns.values.firstOrNull ?? recentRuns.firstOrNull;

  AgentRunState copyWith({
    Map<AgentRunKind, AgentRun>? activeRuns,
    List<AgentRun>? recentRuns,
  }) {
    return AgentRunState(
      activeRuns: activeRuns ?? this.activeRuns,
      recentRuns: recentRuns ?? this.recentRuns,
    );
  }
}

class AgentRunNotifier extends Notifier<AgentRunState> {
  static const _uuid = Uuid();
  bool _listening = false;

  @override
  AgentRunState build() {
    _listenToAgentEvents();
    _loadRecentRuns();
    return const AgentRunState();
  }

  String startRun({
    String? id,
    required AgentRunKind kind,
    required String model,
    String? message,
    String? title,
    String? inputPreview,
    String? retryPrompt,
    List<ContextAttachment> retryAttachments = const [],
    int contextAttachmentCount = 0,
    String? agentTaskId,
    String? parentRunId,
    String? approvalId,
    String? artifactId,
    String? mascotAlias,
  }) {
    final runId = id ?? _uuid.v4();
    final now = DateTime.now();
    final run = AgentRun(
      id: runId,
      kind: kind,
      status: AgentRunStatus.running,
      model: model,
      title: title,
      inputPreview: inputPreview,
      retryPrompt: retryPrompt,
      retryAttachments: retryAttachments,
      contextAttachmentCount: contextAttachmentCount,
      agentTaskId: agentTaskId,
      parentRunId: parentRunId,
      approvalId: approvalId,
      artifactId: artifactId,
      mascotAlias: mascotAlias,
      startedAt: now,
      events: [
        AgentRunEvent(
          type: AgentRunEventType.started,
          timestamp: now,
          message: message ?? '${_kindLabel(kind)} started',
          requestId: runId,
        ),
      ],
      spans: [
        AgentTraceSpan(
          id: _uuid.v4(),
          requestId: runId,
          kind: AgentTraceSpanKind.run,
          name: 'run',
          startedAt: now,
        ),
      ],
    );

    state = state.copyWith(activeRuns: {...state.activeRuns, kind: run});
    return runId;
  }

  void markStreaming(AgentRunKind kind) {
    _updateActive(
      kind,
      (run) => run.copyWith(status: AgentRunStatus.streaming),
    );
  }

  void addEvent(
    AgentRunKind kind,
    AgentRunEventType type,
    String message, {
    Map<String, String> metadata = const {},
  }) {
    _updateActive(kind, (run) {
      final event = AgentRunEvent(
        type: type,
        timestamp: DateTime.now(),
        message: message,
        requestId: run.id,
        metadata: metadata,
      );
      return run.copyWith(events: [...run.events, event].takeLast(40));
    });
  }

  void addSpan(
    AgentRunKind kind, {
    required AgentTraceSpanKind spanKind,
    required String name,
    String? detail,
    Map<String, String> metadata = const {},
    bool failed = false,
  }) {
    _updateActive(kind, (run) {
      final now = DateTime.now();
      final span = AgentTraceSpan(
        id: _uuid.v4(),
        requestId: run.id,
        kind: spanKind,
        name: name,
        startedAt: now,
        endedAt: now,
        detail: detail,
        metadata: metadata,
        failed: failed,
      );
      return run.copyWith(spans: [...run.spans, span].takeLast(40));
    });
  }

  void addRunArtifacts(
    AgentRunKind kind, {
    List<String> changedFiles = const [],
    List<String> commandSummaries = const [],
    String? checkpointId,
  }) {
    _updateActive(kind, (run) {
      return run.copyWith(
        changedFiles: {...run.changedFiles, ...changedFiles}.toList(),
        commandSummaries: [
          ...run.commandSummaries,
          ...commandSummaries,
        ].takeLast(20),
        checkpointId: checkpointId ?? run.checkpointId,
      );
    });
  }

  void updateUsage(AgentRunKind kind, TokenUsage usage) {
    _updateActive(kind, (run) => run.copyWith(tokenUsage: usage));
  }

  void requestCancel(AgentRunKind kind) {
    _updateActive(kind, (run) => run.copyWith(cancelRequested: true));
  }

  void finishRun(
    AgentRunKind kind, {
    String? error,
    bool cancelled = false,
    String? outputPreview,
  }) {
    final run = state.activeRuns[kind];
    if (run == null) return;

    final now = DateTime.now();
    final status = cancelled
        ? AgentRunStatus.cancelled
        : error == null
        ? AgentRunStatus.succeeded
        : AgentRunStatus.failed;
    final completedEvent = AgentRunEvent(
      type: cancelled
          ? AgentRunEventType.cancelled
          : error == null
          ? AgentRunEventType.completed
          : AgentRunEventType.failed,
      timestamp: now,
      message: cancelled
          ? '${_kindLabel(kind)} cancelled'
          : error ?? '${_kindLabel(kind)} completed',
    );

    final finished = run.copyWith(
      status: status,
      endedAt: now,
      error: error,
      outputPreview: outputPreview,
      spans: run.spans
          .map(
            (span) => span.endedAt == null
                ? span.copyWith(endedAt: now, failed: error != null)
                : span,
          )
          .toList(),
      events: [...run.events, completedEvent].takeLast(40),
    );

    final active = Map<AgentRunKind, AgentRun>.from(state.activeRuns)
      ..remove(kind);
    state = state.copyWith(
      activeRuns: active,
      recentRuns: [finished, ...state.recentRuns].take(20).toList(),
    );
    _saveRecentRuns();
  }

  void _listenToAgentEvents() {
    if (_listening) return;
    _listening = true;
    final service = ref.read(agentServiceProvider);

    service.events.on(EventType.messageStarted, (event) {
      if (!_eventBelongsToActiveChat(event.data)) return;
      addEvent(
        AgentRunKind.chat,
        AgentRunEventType.providerRequest,
        'Provider request started',
      );
      addSpan(
        AgentRunKind.chat,
        spanKind: AgentTraceSpanKind.providerRequest,
        name: 'Provider request',
      );
    });
    service.events.on(EventType.messageChunk, (event) {
      if (!_eventBelongsToActiveChat(event.data)) return;
      final content = event.data['content'] as String? ?? '';
      markStreaming(AgentRunKind.chat);
      if (content.isNotEmpty) {
        addEvent(
          AgentRunKind.chat,
          AgentRunEventType.streamChunk,
          'Streaming response',
        );
      }
    });
    service.events.on(EventType.toolCallStarted, (event) {
      if (!_eventBelongsToActiveChat(event.data)) return;
      final tool = event.data['toolCall'] as ToolCallInfo?;
      if (tool != null) {
        final command = tool.name == 'run_command'
            ? tool.arguments['command'] as String?
            : null;
        addEvent(
          AgentRunKind.chat,
          command == null
              ? AgentRunEventType.toolCall
              : AgentRunEventType.commandRun,
          command == null ? tool.name : 'Command: $command',
          metadata: {
            'tool': tool.name,
            if (command != null) ...{'command': command},
          },
        );
        addSpan(
          AgentRunKind.chat,
          spanKind: command == null
              ? AgentTraceSpanKind.toolCall
              : AgentTraceSpanKind.commandRun,
          name: tool.name,
          detail: command,
        );
        if (command != null) {
          addRunArtifacts(AgentRunKind.chat, commandSummaries: [command]);
        }
      }
    });
    service.events.on(EventType.checkpointCreated, (event) {
      final checkpoint = event.data['checkpoint'];
      final checkpointId = _readProperty(checkpoint, 'id');
      addEvent(
        AgentRunKind.chat,
        AgentRunEventType.checkpoint,
        'Checkpoint created',
        metadata: {
          if (checkpointId != null) ...{'checkpointId': checkpointId},
        },
      );
      addSpan(
        AgentRunKind.chat,
        spanKind: AgentTraceSpanKind.checkpoint,
        name: 'Checkpoint created',
        detail: checkpointId,
      );
      addRunArtifacts(AgentRunKind.chat, checkpointId: checkpointId);
    });
    service.events.on(EventType.vericodeTriggered, (event) {
      final files =
          (event.data['editedFiles'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const <String>[];
      addEvent(
        AgentRunKind.chat,
        AgentRunEventType.verification,
        files.isEmpty ? 'Verification triggered' : 'Verification triggered',
        metadata: {if (files.isNotEmpty) 'files': files.join(', ')},
      );
      addRunArtifacts(AgentRunKind.chat, changedFiles: files);
    });
    service.events.on(EventType.tokensUpdated, (event) {
      if (!_eventBelongsToActiveChat(event.data)) return;
      final usage = event.data['lastUsage'] as TokenUsage?;
      if (usage != null) updateUsage(AgentRunKind.chat, usage);
    });
  }

  String? _readProperty(dynamic value, String property) {
    try {
      final dynamic object = value;
      return switch (property) {
        'id' => object.id as String?,
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  bool _eventBelongsToActiveChat(Map<String, dynamic> data) {
    final requestId = data['requestId'] as String?;
    final active = state.activeChatRun;
    if (requestId == null || active == null) return false;
    return active.id == requestId;
  }

  void _updateActive(AgentRunKind kind, AgentRun Function(AgentRun) update) {
    final run = state.activeRuns[kind];
    if (run == null) return;
    state = state.copyWith(
      activeRuns: {...state.activeRuns, kind: update(run)},
    );
  }

  static String _kindLabel(AgentRunKind kind) {
    return switch (kind) {
      AgentRunKind.chat => 'Chat',
      AgentRunKind.inlineCompletion => 'Inline completion',
      AgentRunKind.editPrediction => 'Edit prediction',
      AgentRunKind.backgroundTask => 'Background task',
    };
  }

  Future<void> _loadRecentRuns() async {
    try {
      final file = File(_historyPath);
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString()) as List<dynamic>;
      final runs = json
          .whereType<Map<String, dynamic>>()
          .map(AgentRun.fromJson)
          .nonNulls
          .take(20)
          .toList();
      if (!ref.mounted) return;
      state = state.copyWith(recentRuns: runs);
    } catch (_) {}
  }

  Future<void> _saveRecentRuns() async {
    try {
      final dir = Directory(PlatformUtils.configDir);
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File(_historyPath);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(
          state.recentRuns.take(20).map((run) => run.toJson()).toList(),
        ),
      );
    } catch (_) {}
  }

  static String get _historyPath =>
      p.join(PlatformUtils.configDir, 'agent_runs.json');
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

extension _TakeLast<T> on List<T> {
  List<T> takeLast(int count) {
    if (length <= count) return this;
    return sublist(length - count);
  }
}

final agentRunProvider = NotifierProvider<AgentRunNotifier, AgentRunState>(
  AgentRunNotifier.new,
);
