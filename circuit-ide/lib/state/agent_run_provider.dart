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
      startedAt: now,
      events: [
        AgentRunEvent(
          type: AgentRunEventType.started,
          timestamp: now,
          message: message ?? '${_kindLabel(kind)} started',
        ),
      ],
      spans: [AgentTraceSpan(id: _uuid.v4(), name: 'run', startedAt: now)],
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

  void addEvent(AgentRunKind kind, AgentRunEventType type, String message) {
    _updateActive(kind, (run) {
      final event = AgentRunEvent(
        type: type,
        timestamp: DateTime.now(),
        message: message,
      );
      return run.copyWith(events: [...run.events, event].takeLast(40));
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
        addEvent(AgentRunKind.chat, AgentRunEventType.toolCall, tool.name);
      }
    });
    service.events.on(EventType.tokensUpdated, (event) {
      if (!_eventBelongsToActiveChat(event.data)) return;
      final usage = event.data['lastUsage'] as TokenUsage?;
      if (usage != null) updateUsage(AgentRunKind.chat, usage);
    });
  }

  bool _eventBelongsToActiveChat(Map<String, dynamic> data) {
    final requestId = data['requestId'] as String?;
    final active = state.activeChatRun;
    if (requestId == null || active == null) return active != null;
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
