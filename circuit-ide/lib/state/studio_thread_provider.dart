import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/utils/platform_utils.dart';
import '../enums/message_role.dart';
import '../models/accepted_plan_context.dart';
import '../models/agent_preflight.dart';
import '../models/agent_tool_permission.dart';
import '../models/context_pack.dart';
import '../models/provider_lifecycle_event.dart';
import '../models/reviewed_edit.dart';
import '../models/studio_source_artifact.dart';
import '../models/studio_thread.dart';
import '../models/studio_turn.dart';
import '../models/tool_result_envelope.dart';
import '../models/token_usage.dart';
import '../models/turn_intent.dart';
import '../services/summary_index_page_reader.dart';
import '../services/studio_thread_history_reader.dart';
import '../services/versioned_json_document.dart';
import '../services/worker_cancellation.dart';
import 'file_tree_provider.dart';
import 'studio_command_log_store.dart';
import 'work_item_provider.dart';

part 'studio_thread_store_load.dart';
part 'studio_thread_store_recovery.dart';
part 'studio_thread_store_persistence.dart';
part 'studio_thread_journal.dart';

const _uuid = Uuid();

class StudioThreadState {
  final List<StudioThread> threads;
  final String? selectedThreadId;
  final bool isLoading;
  final String? error;
  final String? recoveryMessage;

  const StudioThreadState({
    this.threads = const [],
    this.selectedThreadId,
    this.isLoading = false,
    this.error,
    this.recoveryMessage,
  });

  StudioThread? get selectedThread {
    if (selectedThreadId == null) return threads.firstOrNull;
    return threads.where((thread) => thread.id == selectedThreadId).firstOrNull;
  }

  StudioThread? threadForTask(String? taskId) {
    if (taskId == null) return null;
    return threads.where((thread) => thread.taskId == taskId).firstOrNull;
  }

  StudioThread? threadForTaskView(String? taskId) {
    if (taskId != null) return threadForTask(taskId);
    return selectedThread;
  }

  StudioThreadState copyWith({
    List<StudioThread>? threads,
    Object? selectedThreadId = _sentinel,
    bool? isLoading,
    Object? error = _sentinel,
    Object? recoveryMessage = _sentinel,
  }) {
    return StudioThreadState(
      threads: threads ?? this.threads,
      selectedThreadId: identical(selectedThreadId, _sentinel)
          ? this.selectedThreadId
          : selectedThreadId as String?,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _sentinel) ? this.error : error as String?,
      recoveryMessage: identical(recoveryMessage, _sentinel)
          ? this.recoveryMessage
          : recoveryMessage as String?,
    );
  }
}

class StudioStorageRepairResult {
  final int recoveredThreadCount;
  final String message;

  const StudioStorageRepairResult({
    required this.recoveredThreadCount,
    required this.message,
  });
}

class StudioThreadSummaryPage {
  final List<StudioThread> threads;
  final int totalCount;
  final int offset;

  const StudioThreadSummaryPage({
    required this.threads,
    required this.totalCount,
    required this.offset,
  });

  int get nextOffset => offset + threads.length;
  bool get hasMore => nextOffset < totalCount;
}

const _historySchemaKind = 'circuit.studio-thread-history';
const _summarySchemaKind = 'circuit.studio-thread-summaries';
const _schemaVersion = 3;
const _journalEnvelopeKind = 'circuit.studio-thread-journal-record';
const _journalCompactionByteThreshold = 1024 * 1024;
const _journalCompactionLineThreshold = 600;

// ADR-0002: thread history is durable state with restart recovery semantics.
class StudioThreadStore
    with
        StudioThreadStoreLoad,
        StudioThreadStoreRecovery,
        StudioThreadStorePersistence {
  @override
  final String baseDir;

  @override
  final StudioCommandLogStore commandLogStore;

  @override
  final Map<String, Set<String>> _journalLineCacheByPath = {};

  @override
  String? _lastRecoveryMessage;

  StudioThreadStore({String? baseDir, StudioCommandLogStore? commandLogStore})
    : baseDir = baseDir ?? p.join(PlatformUtils.configDir, 'studio_threads'),
      commandLogStore = commandLogStore ?? StudioCommandLogStore();

  @override
  List<StudioThread> _loadFromJournalRecordsForSnapshots(
    List<Map<String, dynamic>> records,
  ) => _loadFromJournalRecords(records);
}

class StudioThreadController extends Notifier<StudioThreadState> {
  static const _persistDebounce = Duration(milliseconds: 950);
  static const _eagerThreadHistoryLimit = 48;
  static Duration? debugPersistDebounceOverride;

  final _store = StudioThreadStore();
  String? _loadedRootPath;
  Timer? _persistTimer;
  String? _pendingPersistRootPath;
  List<StudioThread>? _pendingPersistThreads;
  Future<void>? _persistInFlight;
  bool _persistAgain = false;
  final _hydrationCancellationByThread = <String, WorkerCancellationToken>{};

  @override
  StudioThreadState build() {
    Future.microtask(_load);
    ref.listen(fileTreeProvider, (previous, next) {
      if (previous?.rootPath != next.rootPath) {
        unawaited(_flushPendingPersist());
        _load();
      }
    });
    ref.onDispose(() {
      _cancelHydrations('Studio thread controller was disposed.');
      unawaited(flushPendingPersistence());
    });
    return const StudioThreadState(isLoading: true);
  }

  Future<void> _load() async {
    _cancelHydrations('Studio workspace changed while a thread was loading.');
    if (!ref.mounted) return;
    final targetRootPath = ref.read(fileTreeProvider).rootPath;
    if (targetRootPath == null) {
      final wasProjectScoped = _loadedRootPath != null;
      _loadedRootPath = null;
      state = wasProjectScoped
          ? const StudioThreadState()
          : state.copyWith(isLoading: false, error: null);
      return;
    }
    final rootChanged = targetRootPath != _loadedRootPath;
    state = rootChanged
        ? const StudioThreadState(isLoading: true)
        : state.copyWith(isLoading: true, error: null);
    try {
      final firstPage = await _store.loadSummaryPage(
        targetRootPath,
        limit: _eagerThreadHistoryLimit,
      );
      final threads = firstPage.totalCount > _eagerThreadHistoryLimit
          ? firstPage.threads
          : await _store.load(targetRootPath);
      if (!ref.mounted) return;
      if (ref.read(fileTreeProvider).rootPath != targetRootPath) return;
      _loadedRootPath = targetRootPath;
      final mergedThreads = _mergeLoadedThreads(
        loaded: threads,
        current: state.threads,
      );
      state = StudioThreadState(
        threads: mergedThreads,
        selectedThreadId:
            state.selectedThreadId ??
            (mergedThreads.isEmpty ? null : mergedThreads.first.id),
        recoveryMessage: _store.lastRecoveryMessage,
      );
      if (firstPage.totalCount > _eagerThreadHistoryLimit &&
          state.selectedThreadId != null) {
        unawaited(hydrateThread(state.selectedThreadId!));
      }
    } catch (error) {
      if (!ref.mounted) return;
      state = StudioThreadState(error: error.toString());
    }
  }

  Future<void> reload() => _load();

  Future<StudioThread?> hydrateThread(String threadId) async {
    final summary = _find(threadId);
    if (summary == null || summary.detailLoaded) return summary;
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (rootPath == null) return summary;
    _hydrationCancellationByThread[threadId]?.cancel(
      'A newer request is loading this Studio thread.',
    );
    final cancellationToken = WorkerCancellationToken();
    _hydrationCancellationByThread[threadId] = cancellationToken;
    StudioThread? full;
    try {
      full = await _store.loadThread(
        rootPath,
        threadId,
        cancellationToken: cancellationToken,
      );
    } on WorkerCancelledException {
      return summary;
    } finally {
      if (identical(
        _hydrationCancellationByThread[threadId],
        cancellationToken,
      )) {
        _hydrationCancellationByThread.remove(threadId);
      }
    }
    if (!ref.mounted || full == null) return summary;
    final threads = [
      full,
      ...state.threads.where((thread) => thread.id != threadId),
    ];
    state = state.copyWith(threads: threads, isLoading: false, error: null);
    return full;
  }

  void _cancelHydrations(String reason) {
    for (final token in _hydrationCancellationByThread.values) {
      token.cancel(reason);
    }
    _hydrationCancellationByThread.clear();
  }

  Future<StudioThread?> hydrateThreadForTask(String? taskId) {
    final thread = taskId == null
        ? state.selectedThread
        : state.threadForTask(taskId);
    if (thread == null) return Future.value(null);
    return hydrateThread(thread.id);
  }

  Future<StudioStorageRepairResult?> repairStorage() async {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (rootPath == null) return null;
    final result = await _store.repair(rootPath);
    await _load();
    if (!ref.mounted) return result;
    state = state.copyWith(recoveryMessage: result.message, error: null);
    return result;
  }

  Future<void> exportRecoveryBundle(String destinationPath) async {
    await _store.exportRecoveryBundle(
      ref.read(fileTreeProvider).rootPath,
      destinationPath,
    );
  }

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
    if (threadId != null) unawaited(hydrateThread(threadId));
  }

  void selectTaskThread(String? taskId) {
    selectThread(state.threadForTask(taskId)?.id);
  }

  void archiveThread(String threadId) {
    final thread = _find(threadId);
    if (thread == null || thread.archived) return;
    if (!thread.detailLoaded) {
      unawaited(hydrateThread(threadId).then((_) => archiveThread(threadId)));
      return;
    }
    final updated = thread.copyWith(archived: true, archivedAt: DateTime.now());
    if (state.selectedThreadId == threadId) {
      String? nextVisibleThreadId;
      for (final candidate in state.threads) {
        if (candidate.id == threadId) continue;
        if (!candidate.archived) {
          nextVisibleThreadId = candidate.id;
          break;
        }
      }
      state = state.copyWith(selectedThreadId: nextVisibleThreadId);
    }
    _upsert(updated);
  }

  int archiveThreads(Iterable<String> threadIds) {
    final ids = threadIds.toSet();
    if (ids.isEmpty) return 0;
    var archivedCount = 0;
    final now = DateTime.now();
    final threads = [
      for (final thread in state.threads)
        if (ids.contains(thread.id) && !thread.archived)
          (() {
            archivedCount++;
            return thread.copyWith(archived: true, archivedAt: now);
          })()
        else
          thread,
    ];
    if (archivedCount == 0) return 0;
    final selectedThreadId = ids.contains(state.selectedThreadId)
        ? threads.where((thread) => !thread.archived).firstOrNull?.id
        : state.selectedThreadId;
    state = state.copyWith(
      threads: threads,
      selectedThreadId: selectedThreadId,
      isLoading: false,
      error: null,
    );
    _persist(threads);
    return archivedCount;
  }

  int restoreThreads(Iterable<String> threadIds) {
    final ids = threadIds.toSet();
    if (ids.isEmpty) return 0;
    var restoredCount = 0;
    final threads = [
      for (final thread in state.threads)
        if (ids.contains(thread.id) && thread.archived)
          (() {
            restoredCount++;
            return thread.copyWith(archived: false, archivedAt: null);
          })()
        else
          thread,
    ];
    if (restoredCount == 0) return 0;
    state = state.copyWith(threads: threads, isLoading: false, error: null);
    _persist(threads);
    return restoredCount;
  }

  bool restoreThread(String threadId) {
    final thread = _find(threadId);
    if (thread == null || !thread.archived) return false;
    if (!thread.detailLoaded) {
      unawaited(hydrateThread(threadId).then((_) => restoreThread(threadId)));
      return true;
    }
    _upsert(thread.copyWith(archived: false, archivedAt: null), select: true);
    return true;
  }

  bool renameThread(String threadId, String title) {
    final thread = _find(threadId);
    final trimmed = title.trim();
    if (thread == null || trimmed.isEmpty || trimmed.length > 160) return false;
    if (!thread.detailLoaded) {
      unawaited(
        hydrateThread(threadId).then((_) => renameThread(threadId, trimmed)),
      );
      return true;
    }
    _upsert(thread.copyWith(title: trimmed));
    return true;
  }

  bool setThreadPinned(String threadId, bool pinned) {
    final thread = _find(threadId);
    if (thread == null || thread.pinned == pinned) return false;
    if (!thread.detailLoaded) {
      unawaited(
        hydrateThread(threadId).then((_) => setThreadPinned(threadId, pinned)),
      );
      return true;
    }
    _upsert(thread.copyWith(pinned: pinned));
    return true;
  }

  /// Deletes a completed/archived task history only. Active work must be
  /// cancelled or archived first so the rail can never silently discard a
  /// running provider request or pending approval.
  bool deleteThread(String threadId) {
    final thread = _find(threadId);
    if (thread == null || thread.isActive || !thread.archived) return false;
    if (!thread.detailLoaded) {
      unawaited(hydrateThread(threadId).then((_) => deleteThread(threadId)));
      return true;
    }
    final threads = state.threads
        .where((candidate) => candidate.id != threadId)
        .toList(growable: false);
    final selectedThreadId = state.selectedThreadId == threadId
        ? threads.where((candidate) => !candidate.archived).firstOrNull?.id
        : state.selectedThreadId;
    state = state.copyWith(
      threads: threads,
      selectedThreadId: selectedThreadId,
      isLoading: false,
      error: null,
    );
    _persist(threads);
    return true;
  }

  String? firstVisibleThreadId() {
    for (final candidate in state.threads) {
      if (!candidate.archived) {
        return candidate.id;
      }
    }
    return null;
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

  void updateTokenUsage(String threadId, TokenUsage usage) {
    final thread = _find(threadId);
    if (thread == null) return;
    _upsert(thread.copyWith(lastRequestTokenUsage: usage), select: true);
  }

  void upsertSourceArtifact(String threadId, StudioSourceArtifact artifact) {
    final thread = _find(threadId);
    if (thread == null) return;
    final artifacts = [
      artifact,
      ...thread.sourceArtifacts.where(
        (candidate) => candidate.id != artifact.id,
      ),
    ];
    _upsert(thread.copyWith(sourceArtifacts: artifacts), select: false);
  }

  bool removeSourceArtifact(String threadId, String artifactId) {
    final thread = _find(threadId);
    if (thread == null) return false;
    final artifacts = thread.sourceArtifacts
        .where((candidate) => candidate.id != artifactId)
        .toList(growable: false);
    if (artifacts.length == thread.sourceArtifacts.length) return false;
    _upsert(thread.copyWith(sourceArtifacts: artifacts), select: false);
    return true;
  }

  bool upsertTurn(String threadId, StudioTurn turn, {bool select = false}) {
    final thread = _find(threadId);
    if (thread == null) return false;
    // Capture a durable recovery point for every active lifecycle write. The
    // checkpoint is intentionally descriptive only: restart recovery never
    // revives an old approval, process, or provider stream without a new user
    // action.
    final checkpointedTurn = StudioTurnStateMachine.isTerminal(turn.status)
        ? turn
        : turn.copyWith(
            recoveryCheckpoint: StudioTurnRecoveryCheckpoint.capture(turn),
          );
    final persistedTurn =
        StudioTurnStateMachine.isTerminal(checkpointedTurn.status) &&
            checkpointedTurn.finalOutcome == null
        ? checkpointedTurn.copyWith(
            finalOutcome: inferStudioTurnOutcome(checkpointedTurn),
          )
        : checkpointedTurn;
    final existing = thread.turns
        .where((candidate) => candidate.id == persistedTurn.id)
        .firstOrNull;
    if (existing != null &&
        !StudioTurnStateMachine.canTransition(
          existing.status,
          persistedTurn.status,
        )) {
      return false;
    }
    final turns = [
      persistedTurn,
      ...thread.turns.where((candidate) => candidate.id != persistedTurn.id),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final conversationCompactions = _conversationCompactionsFor(thread, turns);
    final updatedThread = switch (persistedTurn.status) {
      StudioTurnStatus.completed when persistedTurn.completedAt != null =>
        thread.copyWith(
          turns: turns,
          conversationCompactions: conversationCompactions,
          status: _completedThreadStatusForTurn(persistedTurn),
          phase: StudioSendPhase.completed,
          streamingContent: '',
          requestId: null,
          lastError: null,
        ),
      StudioTurnStatus.failed when persistedTurn.completedAt != null =>
        thread.copyWith(
          turns: turns,
          conversationCompactions: conversationCompactions,
          status: StudioThreadStatus.failed,
          phase: StudioSendPhase.failed,
          streamingContent: '',
          requestId: null,
          lastError: persistedTurn.lastError ?? thread.lastError,
        ),
      StudioTurnStatus.cancelled when persistedTurn.completedAt != null =>
        thread.copyWith(
          turns: turns,
          conversationCompactions: conversationCompactions,
          status: StudioThreadStatus.cancelled,
          phase: StudioSendPhase.cancelled,
          streamingContent: '',
          requestId: null,
          lastError: null,
        ),
      StudioTurnStatus.interrupted when persistedTurn.completedAt != null =>
        thread.copyWith(
          turns: turns,
          conversationCompactions: conversationCompactions,
          status: StudioThreadStatus.failed,
          phase: StudioSendPhase.failed,
          streamingContent: '',
          requestId: null,
          lastError:
              persistedTurn.lastError ?? 'Turn interrupted before completion.',
        ),
      _ => thread.copyWith(
        turns: turns,
        conversationCompactions: conversationCompactions,
      ),
    };
    _upsert(updatedThread, select: select);
    return true;
  }

  bool restoreConversationCompaction(String threadId, String compactionId) {
    final thread = _find(threadId);
    if (thread == null) return false;
    final compaction = thread.conversationCompactions
        .where((candidate) => candidate.id == compactionId)
        .firstOrNull;
    if (compaction == null || compaction.restored) return false;
    _upsert(
      thread.copyWith(
        conversationCompactions: [
          for (final candidate in thread.conversationCompactions)
            candidate.id == compactionId
                ? candidate.copyWith(restored: true)
                : candidate,
        ],
      ),
      select: true,
    );
    return true;
  }

  List<StudioConversationCompaction> _conversationCompactionsFor(
    StudioThread thread,
    List<StudioTurn> turns,
  ) {
    final existing = thread.conversationCompactions;
    final generated = buildStudioConversationCompaction(turns);
    final active = existing
        .where((compaction) => !compaction.restored)
        .firstOrNull;
    if (active != null) {
      if (generated == null ||
          _sameCompactionSources(
            active.sourceTurnIds,
            generated.sourceTurnIds,
          )) {
        return existing;
      }
      final expanded = StudioConversationCompaction(
        id: active.id,
        summary: generated.summary,
        sourceTurnIds: generated.sourceTurnIds,
        createdAt: generated.createdAt,
        sourceTokenEstimate: generated.sourceTokenEstimate,
      );
      return [
        for (final compaction in existing)
          compaction.id == active.id ? expanded : compaction,
      ];
    }
    // A user who restores the source turns explicitly chose the expanded
    // history. Do not silently create a second summary over the same thread.
    if (existing.isNotEmpty || generated == null) return existing;
    if (existing.any((compaction) => compaction.id == generated.id)) {
      return existing;
    }
    return [...existing, generated];
  }

  bool _sameCompactionSources(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
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

  void upsertTurnStep(String threadId, String turnId, TurnStepRecord step) {
    final thread = _find(threadId);
    if (thread == null) return;
    final turn = thread.turns
        .where((candidate) => candidate.id == turnId)
        .firstOrNull;
    if (turn == null) return;
    upsertTurn(threadId, turn.upsertStep(step));
  }

  bool updateTurn(
    String threadId,
    String turnId, {
    StudioTurnStatus? status,
    String? assistantDraft,
    List<TurnStepRecord>? steps,
    List<ToolResultEnvelope>? toolResults,
    List<ProviderLifecycleEvent>? providerDiagnostics,
    AcceptedPlanState? acceptedPlanState,
    Object? acceptedPlanContext = _sentinel,
    List<PlanTargetProgress>? planTargetProgress,
    Object? contextRetrieval = _sentinel,
    Object? lastError = _sentinel,
    Object? finalOutcome = _sentinel,
    bool complete = false,
    bool expirePendingApprovals = false,
  }) {
    final thread = _find(threadId);
    if (thread == null) return false;
    final turn = thread.turns
        .where((candidate) => candidate.id == turnId)
        .firstOrNull;
    if (turn == null) return false;
    if (status != null &&
        !StudioTurnStateMachine.canTransition(turn.status, status)) {
      return false;
    }
    final updated =
        (expirePendingApprovals ? turn.expirePendingApprovals() : turn)
            .copyWith(
              status: status,
              assistantDraft: assistantDraft,
              steps: steps,
              toolResults: toolResults,
              providerDiagnostics: providerDiagnostics,
              acceptedPlanState: acceptedPlanState,
              acceptedPlanContext: acceptedPlanContext,
              planTargetProgress: planTargetProgress,
              contextRetrieval: contextRetrieval,
              completedAt: complete ? DateTime.now() : _sentinel,
              lastError: lastError,
              finalOutcome: finalOutcome,
            );
    return upsertTurn(threadId, updated);
  }

  void complete(String threadId, {TokenUsage? tokenUsage}) {
    final thread = _find(threadId);
    if (thread == null) return;
    _upsert(
      thread.copyWith(
        status: StudioThreadStatus.done,
        phase: StudioSendPhase.completed,
        streamingContent: '',
        tokenUsage: tokenUsage == null
            ? thread.tokenUsage
            : thread.tokenUsage.plus(tokenUsage),
        lastRequestTokenUsage: tokenUsage ?? thread.lastRequestTokenUsage,
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

  void cancel(String threadId, {String? message}) {
    final thread = _find(threadId);
    if (thread == null) return;
    _upsert(
      thread.copyWith(
        status: StudioThreadStatus.cancelled,
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

  StudioThreadStatus _completedThreadStatusForTurn(StudioTurn turn) {
    final hasQueuedContinuation = turn.steps.any(
      (step) =>
          step.step == TurnStep.continuation &&
          step.status == TurnStepStatus.queued,
    );
    if (hasQueuedContinuation) return StudioThreadStatus.continuationReady;
    if (_turnHasRemainingAcceptedPlanTargets(turn)) {
      return StudioThreadStatus.continuationReady;
    }
    return StudioThreadStatus.done;
  }

  bool _turnHasRemainingAcceptedPlanTargets(StudioTurn turn) {
    if (turn.acceptedPlanContext == null || turn.planTargetProgress.isEmpty) {
      return false;
    }
    final hasStartedImplementation = turn.planTargetProgress.any(
      (target) =>
          target.state == PlanTargetProgressState.applied ||
          target.state == PlanTargetProgressState.proposed ||
          target.state == PlanTargetProgressState.conflict,
    );
    if (!hasStartedImplementation) return false;
    return turn.planTargetProgress.any(
      (target) =>
          target.state == PlanTargetProgressState.pending ||
          target.state == PlanTargetProgressState.conflict ||
          target.state == PlanTargetProgressState.blocked,
    );
  }

  StudioThread? _find(String threadId) {
    return state.threads.where((thread) => thread.id == threadId).firstOrNull;
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
    _pendingPersistRootPath = ref.read(fileTreeProvider).rootPath;
    _pendingPersistThreads = List<StudioThread>.unmodifiable(threads);
    _persistTimer?.cancel();
    final delay = debugPersistDebounceOverride ?? _persistDebounce;
    if (delay <= Duration.zero) {
      unawaited(_flushPendingPersist());
      return;
    }
    _persistTimer = Timer(delay, () {
      unawaited(_flushPendingPersist());
    });
  }

  /// Drains the debounced snapshot, summary, and journal writes for the
  /// current workspace. Tests and controlled host shutdowns can await this
  /// before disposing a temporary workspace, instead of racing an atomic
  /// journal compaction against directory cleanup.
  Future<void> flushPendingPersistence() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    while (true) {
      await _flushPendingPersist();
      if (_persistInFlight == null &&
          _pendingPersistThreads == null &&
          !_persistAgain) {
        return;
      }
      // A completion callback may enqueue one coalesced follow-up save.
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> _flushPendingPersist() {
    _persistTimer?.cancel();
    _persistTimer = null;
    final rootPath = _pendingPersistRootPath;
    final threads = _pendingPersistThreads;
    if (threads == null) return _persistInFlight ?? Future<void>.value();
    if (_persistInFlight != null) {
      _persistAgain = true;
      return _persistInFlight!;
    }
    _pendingPersistRootPath = null;
    _pendingPersistThreads = null;
    final future = _store.save(rootPath, threads).whenComplete(() {
      _persistInFlight = null;
      if (_persistAgain) {
        _persistAgain = false;
        unawaited(_flushPendingPersist());
      }
    });
    _persistInFlight = future;
    return future;
  }

  List<StudioThread> _mergeLoadedThreads({
    required List<StudioThread> loaded,
    required List<StudioThread> current,
  }) {
    if (current.isEmpty) return loaded;
    final currentIds = current.map((thread) => thread.id).toSet();
    final merged = [
      ...current,
      for (final thread in loaded)
        if (!currentIds.contains(thread.id)) thread,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return merged;
  }
}

final studioThreadProvider =
    NotifierProvider<StudioThreadController, StudioThreadState>(
      StudioThreadController.new,
    );
