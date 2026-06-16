import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/utils/platform_utils.dart';
import '../enums/message_role.dart';
import '../models/agent_preflight.dart';
import '../models/chat_message.dart';
import '../models/studio_source_artifact.dart';
import '../models/studio_thread.dart';
import '../models/studio_turn.dart';
import '../models/token_usage.dart';
import 'file_tree_provider.dart';
import 'work_item_provider.dart';

const _uuid = Uuid();

class StudioThreadState {
  final List<StudioThread> threads;
  final String? selectedThreadId;
  final bool isLoading;
  final String? error;

  const StudioThreadState({
    this.threads = const [],
    this.selectedThreadId,
    this.isLoading = false,
    this.error,
  });

  StudioThread? get selectedThread {
    if (selectedThreadId == null) return threads.firstOrNull;
    return threads.where((thread) => thread.id == selectedThreadId).firstOrNull;
  }

  StudioThread? threadForTask(String? taskId) {
    if (taskId == null) return null;
    return threads.where((thread) => thread.taskId == taskId).firstOrNull;
  }

  StudioThreadState copyWith({
    List<StudioThread>? threads,
    Object? selectedThreadId = _sentinel,
    bool? isLoading,
    Object? error = _sentinel,
  }) {
    return StudioThreadState(
      threads: threads ?? this.threads,
      selectedThreadId: identical(selectedThreadId, _sentinel)
          ? this.selectedThreadId
          : selectedThreadId as String?,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

class StudioThreadStore {
  final String baseDir;

  StudioThreadStore({String? baseDir})
    : baseDir = baseDir ?? p.join(PlatformUtils.configDir, 'studio_threads');

  String historyPath(String? rootPath) {
    return p.join(baseDir, '${WorkItemStore.projectKey(rootPath)}.json');
  }

  Future<List<StudioThread>> load(String? rootPath) async {
    final file = File(historyPath(rootPath));
    if (!await file.exists()) return const [];
    final json = jsonDecode(await file.readAsString()) as List<dynamic>;
    return json
        .whereType<Map<String, dynamic>>()
        .map(StudioThread.fromJson)
        .nonNulls
        .map(_normalizeLoadedThread)
        .toList();
  }

  StudioThread _normalizeLoadedThread(StudioThread thread) {
    final normalizedTurns = thread.turns.map(_normalizeLoadedTurn).toList();
    var normalized = thread.copyWith(turns: normalizedTurns);
    if (!_isLoadedActiveThread(normalized.status)) return normalized;

    final latestTurn = normalizedTurns.fold<StudioTurn?>(
      null,
      (latest, turn) =>
          latest == null || turn.createdAt.isAfter(latest.createdAt)
          ? turn
          : latest,
    );
    final recoveredStatus = switch (latestTurn?.status) {
      StudioTurnStatus.completed => StudioThreadStatus.done,
      StudioTurnStatus.failed => StudioThreadStatus.failed,
      StudioTurnStatus.cancelled => StudioThreadStatus.cancelled,
      _ => null,
    };
    if (recoveredStatus != null) {
      return normalized.copyWith(
        status: recoveredStatus,
        phase: recoveredStatus == StudioThreadStatus.done
            ? StudioSendPhase.completed
            : StudioSendPhase.failed,
        requestId: null,
        streamingContent: '',
        lastError: recoveredStatus == StudioThreadStatus.failed
            ? (latestTurn?.lastError ?? normalized.lastError)
            : null,
      );
    }

    final hasAssistantMessage = normalized.messages.any(
      (message) =>
          message.role == MessageRole.assistant &&
          message.content.trim().isNotEmpty,
    );
    if (hasAssistantMessage) {
      return normalized.copyWith(
        status: StudioThreadStatus.done,
        phase: StudioSendPhase.completed,
        requestId: null,
        streamingContent: '',
        lastError: null,
      );
    }
    const message = 'Interrupted while CircuitCode was closed.';
    return normalized.copyWith(
      status: StudioThreadStatus.failed,
      phase: StudioSendPhase.failed,
      requestId: null,
      streamingContent: '',
      lastError: normalized.lastError ?? message,
    );
  }

  StudioTurn _normalizeLoadedTurn(StudioTurn turn) {
    if (!_isLoadedActiveTurn(turn.status)) return turn;
    return turn.expirePendingApprovals().copyWith(
      status: StudioTurnStatus.failed,
      assistantDraft: '',
      completedAt: DateTime.now(),
      lastError: turn.lastError ?? 'Interrupted while CircuitCode was closed.',
    );
  }

  bool _isLoadedActiveThread(StudioThreadStatus status) {
    return switch (status) {
      StudioThreadStatus.preflighting ||
      StudioThreadStatus.buildingContext ||
      StudioThreadStatus.streaming ||
      StudioThreadStatus.waitingForApproval ||
      StudioThreadStatus.runningCommand => true,
      StudioThreadStatus.idle ||
      StudioThreadStatus.reviewingPatch ||
      StudioThreadStatus.done ||
      StudioThreadStatus.failed ||
      StudioThreadStatus.cancelled => false,
    };
  }

  bool _isLoadedActiveTurn(StudioTurnStatus status) {
    return switch (status) {
      StudioTurnStatus.queued ||
      StudioTurnStatus.buildingContext ||
      StudioTurnStatus.sent ||
      StudioTurnStatus.waitingForModel ||
      StudioTurnStatus.streaming ||
      StudioTurnStatus.toolRunning ||
      StudioTurnStatus.waitingForApproval => true,
      StudioTurnStatus.completed ||
      StudioTurnStatus.failed ||
      StudioTurnStatus.cancelled => false,
    };
  }

  Future<void> save(String? rootPath, List<StudioThread> threads) async {
    final file = File(historyPath(rootPath));
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(threads.map((thread) => thread.toJson()).toList()),
    );
  }
}

class StudioThreadController extends Notifier<StudioThreadState> {
  final _store = StudioThreadStore();

  @override
  StudioThreadState build() {
    Future.microtask(_load);
    ref.listen(fileTreeProvider, (previous, next) {
      if (previous?.rootPath != next.rootPath) _load();
    });
    return const StudioThreadState(isLoading: true);
  }

  Future<void> _load() async {
    if (!ref.mounted) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final threads = await _store.load(ref.read(fileTreeProvider).rootPath);
      if (!ref.mounted) return;
      state = StudioThreadState(threads: threads);
    } catch (error) {
      if (!ref.mounted) return;
      state = StudioThreadState(error: error.toString());
    }
  }

  Future<void> reload() => _load();

  StudioThread createBlankThread({String title = 'New thread', String? model}) {
    final now = DateTime.now();
    final thread = StudioThread(
      id: _uuid.v4().substring(0, 8),
      title: title,
      model: model,
      createdAt: now,
      updatedAt: now,
    );
    _upsert(thread, select: true);
    return thread;
  }

  StudioThread ensureThread({
    String? taskId,
    required String title,
    String? model,
  }) {
    final existing = taskId == null
        ? (state.selectedThreadId == null ? null : state.selectedThread)
        : state.threadForTask(taskId);
    if (existing != null) {
      final updated = existing.copyWith(
        title: title,
        model: model ?? existing.model,
      );
      _upsert(updated, select: true);
      return updated;
    }
    final now = DateTime.now();
    final thread = StudioThread(
      id: _uuid.v4().substring(0, 8),
      taskId: taskId,
      title: title,
      model: model,
      createdAt: now,
      updatedAt: now,
    );
    _upsert(thread, select: true);
    return thread;
  }

  void selectThread(String? threadId) {
    state = state.copyWith(selectedThreadId: threadId);
  }

  void selectTaskThread(String? taskId) {
    selectThread(state.threadForTask(taskId)?.id);
  }

  void markPhase(
    String threadId, {
    required StudioThreadStatus status,
    required StudioSendPhase phase,
    String? requestId,
    String? model,
    StudioContextSummary? contextSummary,
    String? streamingContent,
    Object? lastError = _sentinel,
  }) {
    final thread = _find(threadId);
    if (thread == null) return;
    _upsert(
      thread.copyWith(
        status: status,
        phase: phase,
        requestId: requestId,
        model: model,
        contextSummary: contextSummary,
        streamingContent: streamingContent,
        lastError: lastError,
      ),
      select: true,
    );
  }

  String? appendUserMessage(String threadId, String content) {
    return _appendMessage(threadId, MessageRole.user, content);
  }

  String? appendAssistantMessage(String threadId, String content) {
    return _appendMessage(threadId, MessageRole.assistant, content);
  }

  void appendChatMessages(String threadId, Iterable<ChatMessage> messages) {
    final thread = _find(threadId);
    if (thread == null) return;
    final existingIds = thread.messages.map((message) => message.id).toSet();
    final studioMessages = [
      ...thread.messages,
      for (final message in messages)
        if (!existingIds.contains(message.id) &&
            (message.role == MessageRole.user ||
                message.role == MessageRole.assistant))
          StudioThreadMessage(
            id: message.id,
            role: message.role,
            content: message.content,
            timestamp: message.timestamp,
          ),
    ];
    _upsert(thread.copyWith(messages: studioMessages), select: true);
  }

  void updateTokenUsage(String threadId, TokenUsage usage) {
    final thread = _find(threadId);
    if (thread == null) return;
    _upsert(thread.copyWith(tokenUsage: usage), select: true);
  }

  void upsertSourceArtifact(String threadId, StudioSourceArtifact artifact) {
    final thread = _find(threadId);
    if (thread == null) return;
    final artifacts = [
      artifact,
      ...thread.sourceArtifacts.where(
        (candidate) => candidate.id != artifact.id,
      ),
    ].take(120).toList();
    _upsert(thread.copyWith(sourceArtifacts: artifacts), select: false);
  }

  void upsertTurn(String threadId, StudioTurn turn, {bool select = false}) {
    final thread = _find(threadId);
    if (thread == null) return;
    final turns = [
      turn,
      ...thread.turns.where((candidate) => candidate.id != turn.id),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _upsert(thread.copyWith(turns: turns), select: select);
  }

  void upsertTurnEvent(String threadId, String turnId, StudioTurnEvent event) {
    final thread = _find(threadId);
    if (thread == null) return;
    final turn = thread.turns
        .where((candidate) => candidate.id == turnId)
        .firstOrNull;
    if (turn == null) return;
    upsertTurn(threadId, turn.upsertEvent(event));
  }

  void updateTurn(
    String threadId,
    String turnId, {
    StudioTurnStatus? status,
    String? assistantDraft,
    Object? lastError = _sentinel,
    bool complete = false,
    bool expirePendingApprovals = false,
  }) {
    final thread = _find(threadId);
    if (thread == null) return;
    final turn = thread.turns
        .where((candidate) => candidate.id == turnId)
        .firstOrNull;
    if (turn == null) return;
    final updated =
        (expirePendingApprovals ? turn.expirePendingApprovals() : turn)
            .copyWith(
              status: status,
              assistantDraft: assistantDraft,
              completedAt: complete ? DateTime.now() : _sentinel,
              lastError: lastError,
            );
    upsertTurn(threadId, updated);
  }

  void complete(String threadId, {TokenUsage? tokenUsage}) {
    final thread = _find(threadId);
    if (thread == null) return;
    _upsert(
      thread.copyWith(
        status: StudioThreadStatus.done,
        phase: StudioSendPhase.completed,
        streamingContent: '',
        tokenUsage: tokenUsage ?? thread.tokenUsage,
        lastError: null,
      ),
      select: true,
    );
  }

  void block(
    String threadId,
    String message, {
    AgentPreflightResult? preflight,
  }) {
    final thread = _find(threadId);
    if (thread == null) return;
    _upsert(
      thread.copyWith(
        status: StudioThreadStatus.failed,
        phase: StudioSendPhase.blocked,
        streamingContent: '',
        lastError: message,
      ),
      select: true,
    );
  }

  void fail(String threadId, String message) {
    final thread = _find(threadId);
    if (thread == null) return;
    _upsert(
      thread.copyWith(
        status: StudioThreadStatus.failed,
        phase: StudioSendPhase.failed,
        streamingContent: '',
        lastError: message,
      ),
      select: true,
    );
  }

  void waitForApproval(String threadId) {
    final thread = _find(threadId);
    if (thread == null) return;
    _upsert(
      thread.copyWith(
        status: StudioThreadStatus.waitingForApproval,
        phase: StudioSendPhase.waitingForApproval,
        streamingContent: '',
      ),
      select: true,
    );
  }

  void setReviewingPatch(String threadId) {
    final thread = _find(threadId);
    if (thread == null) return;
    _upsert(
      thread.copyWith(
        status: StudioThreadStatus.reviewingPatch,
        phase: StudioSendPhase.completed,
        streamingContent: '',
      ),
      select: true,
    );
  }

  StudioThread? _find(String threadId) {
    return state.threads.where((thread) => thread.id == threadId).firstOrNull;
  }

  String? _appendMessage(String threadId, MessageRole role, String content) {
    final thread = _find(threadId);
    if (thread == null || content.trim().isEmpty) return null;
    final message = StudioThreadMessage(
      id: _uuid.v4(),
      role: role,
      content: content.trim(),
      timestamp: DateTime.now(),
    );
    _upsert(
      thread.copyWith(messages: [...thread.messages, message]),
      select: true,
    );
    return message.id;
  }

  void _upsert(StudioThread thread, {bool select = false}) {
    final threads = [
      thread,
      ...state.threads.where((candidate) => candidate.id != thread.id),
    ];
    state = state.copyWith(
      threads: threads,
      selectedThreadId: select ? thread.id : state.selectedThreadId,
      isLoading: false,
      error: null,
    );
    _persist(threads);
  }

  Future<void> _persist(List<StudioThread> threads) async {
    await _store.save(ref.read(fileTreeProvider).rootPath, threads);
  }
}

final studioThreadProvider =
    NotifierProvider<StudioThreadController, StudioThreadState>(
      StudioThreadController.new,
    );

const _sentinel = Object();
