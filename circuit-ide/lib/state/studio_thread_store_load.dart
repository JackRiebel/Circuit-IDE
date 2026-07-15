part of 'studio_thread_provider.dart';

mixin StudioThreadStoreLoad {
  String get baseDir;
  String? get _lastRecoveryMessage;
  set _lastRecoveryMessage(String? value);
  List<StudioThread> _loadFromJournalRecordsForSnapshots(
    List<Map<String, dynamic>> records,
  );
  String _encodeHistory(List<StudioThread> threads);
  String _encodeSummaries(List<StudioThread> summaries);
  StudioThread _threadForPersistence(StudioThread thread);
  Future<void> _writeSummaries(String? rootPath, List<StudioThread> threads);
  StudioThread _normalizeLoadedThread(StudioThread thread);
  StudioSendPhase _phaseForRecoveredStatus(StudioThreadStatus status);
  bool _isLoadedActiveThread(StudioThreadStatus status);
  Future<void> _writeSummaryIndex(
    String? rootPath,
    List<StudioThread> summaries,
  );

  String historyPath(String? rootPath) {
    return p.join(baseDir, '${WorkItemStore.projectKey(rootPath)}.json');
  }

  String journalPath(String? rootPath) {
    return p.join(
      baseDir,
      '${WorkItemStore.projectKey(rootPath)}.journal.jsonl',
    );
  }

  String summaryPath(String? rootPath) {
    return p.join(
      baseDir,
      '${WorkItemStore.projectKey(rootPath)}.summary.json',
    );
  }

  String summaryIndexPath(String? rootPath) {
    return p.join(
      baseDir,
      '${WorkItemStore.projectKey(rootPath)}.summary.index.jsonl',
    );
  }

  String? get lastRecoveryMessage => _lastRecoveryMessage;

  String recoveryBackupPath(String? rootPath) =>
      '${historyPath(rootPath)}.recovery.backup';

  String journalBackupPath(String? rootPath) =>
      '${journalPath(rootPath)}.recovery.backup';

  Future<List<StudioThread>> load(String? rootPath) async {
    _lastRecoveryMessage = null;
    final file = File(historyPath(rootPath));
    if (!await file.exists()) {
      final recovered = await _loadFromJournalSnapshots(rootPath);
      if (recovered.isNotEmpty) {
        _lastRecoveryMessage =
            'Thread history was rebuilt from its crash-recovery journal.';
        await _repairRecoveredHistory(rootPath, recovered);
      }
      return recovered;
    }
    try {
      final contents = await file.readAsString();
      final document = _decodeHistoryDocument(contents);
      final historyThreads = _threadsFromHistoryDocument(document);
      if (document.schemaVersion < _schemaVersion) {
        await migrateVersionedJsonFile(
          file: file,
          originalContents: contents,
          migratedContents: _encodeHistory(historyThreads),
          previousSchemaVersion: document.schemaVersion,
        );
      }
      final journalThreads = await _loadFromJournalSnapshots(rootPath);
      return _mergeLoadedThreads(historyThreads, journalThreads);
    } catch (error) {
      if (error is UnsupportedRuntimeSchemaVersion) rethrow;
      final recovered = await _loadFromJournalSnapshots(rootPath);
      if (recovered.isNotEmpty) {
        _lastRecoveryMessage =
            'Recovered thread history from the integrity-checked crash journal.';
        await _repairRecoveredHistory(rootPath, recovered);
        return recovered;
      }
      final backup = await _loadRecoveryBackup(rootPath);
      if (backup.isNotEmpty) {
        _lastRecoveryMessage =
            'Recovered thread history from its last known-good backup.';
        await _repairRecoveredHistory(rootPath, backup);
        return backup;
      }
      _lastRecoveryMessage =
          'Thread history could not be read. CircuitCode opened safely; use Settings to export recovery files or start a repaired history.';
      return const [];
    }
  }

  Future<StudioThread?> loadThread(
    String? rootPath,
    String threadId, {
    WorkerCancellationToken? cancellationToken,
  }) async {
    final file = File(historyPath(rootPath));
    if (await file.exists()) {
      try {
        final record = await const StudioThreadHistoryReader().readThread(
          path: file.path,
          expectedKind: _historySchemaKind,
          currentSchemaVersion: _schemaVersion,
          threadId: threadId,
          cancellationToken: cancellationToken,
        );
        if (record.legacyContents != null) {
          final document = _decodeHistoryDocument(record.legacyContents!);
          final historyThreads = _threadsFromHistoryDocument(document);
          await migrateVersionedJsonFile(
            file: file,
            originalContents: record.legacyContents!,
            migratedContents: _encodeHistory(historyThreads),
            previousSchemaVersion: document.schemaVersion,
          );
          return historyThreads
              .where((thread) => thread.id == threadId)
              .firstOrNull;
        }
        final threadJson = record.thread;
        if (threadJson != null) {
          final thread = StudioThread.fromJson(
            Map<String, dynamic>.from(threadJson),
          );
          return thread == null ? null : _normalizeLoadedThread(thread);
        }
      } on WorkerCancelledException {
        rethrow;
      } catch (_) {
        // History can be stale while the append-only journal has a newer
        // snapshot. The recovery path below retains that existing behavior.
      }
    }
    final threads = await load(rootPath);
    return threads.where((thread) => thread.id == threadId).firstOrNull;
  }

  VersionedJsonDocument _decodeHistoryDocument(String contents) {
    return VersionedJsonDocument.decode(
      jsonDecode(contents),
      expectedKind: _historySchemaKind,
      currentSchemaVersion: _schemaVersion,
    );
  }

  List<StudioThread> _threadsFromHistoryDocument(
    VersionedJsonDocument document,
  ) {
    final payload = document.payload;
    if (payload is! List<dynamic>) {
      throw const FormatException(
        'Studio thread history payload is not a list.',
      );
    }
    return payload
        .whereType<Map<String, dynamic>>()
        .map(StudioThread.fromJson)
        .nonNulls
        .map(_normalizeLoadedThread)
        .toList();
  }

  Future<List<StudioThread>> _loadRecoveryBackup(String? rootPath) async {
    final backup = File(recoveryBackupPath(rootPath));
    if (!await backup.exists()) return const [];
    try {
      return _threadsFromHistoryDocument(
        _decodeHistoryDocument(await backup.readAsString()),
      );
    } on UnsupportedRuntimeSchemaVersion {
      rethrow;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _repairRecoveredHistory(
    String? rootPath,
    List<StudioThread> threads,
  ) async {
    final file = File(historyPath(rootPath));
    if (await file.exists()) {
      try {
        await writeVersionedJsonAtomically(
          File(
            '${file.path}.corrupt-${DateTime.now().microsecondsSinceEpoch}.backup',
          ),
          await file.readAsString(),
        );
      } catch (_) {
        // A failed forensic copy must never prevent the usable recovery path.
      }
    }
    try {
      final persisted = threads.map(_threadForPersistence).toList();
      await writeVersionedJsonAtomically(file, _encodeHistory(persisted));
      await _writeSummaries(rootPath, persisted);
    } catch (_) {
      // Keep recovered data in memory even when the repaired snapshot cannot
      // be written (for example, a full disk or revoked folder permission).
    }
  }

  Future<List<StudioThread>> loadSummaries(String? rootPath) async {
    final summaryFile = File(summaryPath(rootPath));
    if (await summaryFile.exists()) {
      try {
        final contents = await summaryFile.readAsString();
        final document = VersionedJsonDocument.decode(
          jsonDecode(contents),
          expectedKind: _summarySchemaKind,
          currentSchemaVersion: _schemaVersion,
        );
        final payload = document.payload;
        if (payload is List<dynamic>) {
          final summaries = _summaryThreadsFromJson(payload);
          if (document.schemaVersion < _schemaVersion) {
            await migrateVersionedJsonFile(
              file: summaryFile,
              originalContents: contents,
              migratedContents: _encodeSummaries(summaries),
              previousSchemaVersion: document.schemaVersion,
            );
          }
          return summaries;
        }
      } on UnsupportedRuntimeSchemaVersion {
        rethrow;
      } catch (_) {
        // Fall through to the full history as a one-time recovery path.
      }
    }

    final historyFile = File(historyPath(rootPath));
    if (await historyFile.exists()) {
      try {
        final document = VersionedJsonDocument.decode(
          jsonDecode(await historyFile.readAsString()),
          expectedKind: _historySchemaKind,
          currentSchemaVersion: _schemaVersion,
        );
        final payload = document.payload;
        if (payload is List<dynamic>) {
          final summaries = _summaryThreadsFromJson(payload);
          unawaited(_writeSummaries(rootPath, summaries));
          return summaries;
        }
      } on UnsupportedRuntimeSchemaVersion {
        rethrow;
      } catch (_) {
        // Journal snapshots are the final recovery path.
      }
    }

    final journalSummaries = await _loadJournalThreadSummaries(rootPath);
    if (journalSummaries.isNotEmpty) {
      unawaited(_writeSummaries(rootPath, journalSummaries));
    }
    return journalSummaries;
  }

  /// Streams one metadata page from the compact summary index. Older installs
  /// fall back once to the JSON summary snapshot and write the index for later
  /// opens, keeping the migration transparent.
  Future<StudioThreadSummaryPage> loadSummaryPage(
    String? rootPath, {
    int offset = 0,
    int limit = 12,
    WorkerCancellationToken? cancellationToken,
  }) async {
    final safeOffset = offset < 0 ? 0 : offset;
    final safeLimit = limit.clamp(1, 100);
    final index = File(summaryIndexPath(rootPath));
    if (!await index.exists()) {
      final summaries = await loadSummaries(rootPath);
      if (summaries.isNotEmpty) {
        await _writeSummaryIndex(rootPath, summaries);
      }
      return StudioThreadSummaryPage(
        threads: summaries.skip(safeOffset).take(safeLimit).toList(),
        totalCount: summaries.length,
        offset: safeOffset,
      );
    }
    final indexPage = await const SummaryIndexPageReader().read(
      path: index.path,
      headerKind: 'circuit.studio-thread-summary-index',
      offset: safeOffset,
      limit: safeLimit,
      cancellationToken: cancellationToken,
    );
    final page = <StudioThread>[];
    for (final decoded in indexPage.records) {
      try {
        final summary = _threadSummaryFromJson(
          Map<String, dynamic>.from(decoded),
        );
        if (summary != null) page.add(summary);
      } catch (_) {
        // A malformed metadata row never blocks the remaining page.
      }
    }
    return StudioThreadSummaryPage(
      threads: page,
      totalCount: indexPage.totalCount,
      offset: safeOffset,
    );
  }

  List<StudioThread> _summaryThreadsFromJson(List<dynamic> json) {
    return json
        .whereType<Map<String, dynamic>>()
        .map(_threadSummaryFromJson)
        .nonNulls
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<List<StudioThread>> _loadJournalThreadSummaries(
    String? rootPath,
  ) async {
    final file = File(journalPath(rootPath));
    if (!await file.exists()) return const [];
    final snapshots = <String, StudioThread>{};
    final snapshotTimes = <String, DateTime>{};
    final records = await const StudioThreadJournalReader().read(
      path: file.path,
      envelopeKind: _journalEnvelopeKind,
    );
    for (final decoded in records) {
      if (decoded['kind'] != 'thread_snapshot') continue;
      final threadJson = decoded['thread'];
      if (threadJson is! Map) continue;
      final summary = _threadSummaryFromJson(
        Map<String, dynamic>.from(threadJson),
      );
      if (summary == null) continue;
      final capturedAt =
          DateTime.tryParse(decoded['capturedAt'] as String? ?? '') ??
          summary.updatedAt;
      final previous = snapshotTimes[summary.id];
      if (previous != null && previous.isAfter(capturedAt)) continue;
      snapshots[summary.id] = summary;
      snapshotTimes[summary.id] = capturedAt;
    }
    return snapshots.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  StudioThread? _threadSummaryFromJson(Map<String, dynamic> json) {
    try {
      final usage = json['tokenUsage'] as Map<String, dynamic>?;
      final contextSummary = StudioContextSummary.fromJson(
        json['contextSummary'] as Map<String, dynamic>?,
      );
      final latestTurn = _latestTurnSummary(
        (json['turns'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>(),
      );
      final rawStatus = StudioThreadStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => StudioThreadStatus.idle,
      );
      final lastError = json['lastError'] as String?;
      final status = _summaryStatusFor(
        rawStatus: rawStatus,
        latestTurn: latestTurn,
        lastError: lastError,
      );
      return StudioThread(
        id: json['id'] as String,
        taskId: json['taskId'] as String?,
        title: json['title'] as String? ?? 'Circuit task',
        status: status,
        phase: _phaseForRecoveredStatus(status),
        requestId: null,
        model: json['model'] as String?,
        contextSummary: contextSummary,
        turns: latestTurn == null ? const [] : [latestTurn],
        streamingContent: '',
        tokenUsage: TokenUsage(
          promptTokens: usage?['promptTokens'] as int? ?? 0,
          cachedInputTokens: usage?['cachedInputTokens'] as int? ?? 0,
          completionTokens: usage?['completionTokens'] as int? ?? 0,
          reasoningTokens: usage?['reasoningTokens'] as int? ?? 0,
          toolTokens: usage?['toolTokens'] as int? ?? 0,
          totalTokens: usage?['totalTokens'] as int? ?? 0,
        ),
        lastError: status == StudioThreadStatus.failed ? lastError : null,
        detailLoaded: false,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  StudioTurn? _latestTurnSummary(Iterable<Map<String, dynamic>> turnJson) {
    StudioTurn? latest;
    for (final json in turnJson) {
      final turn = _turnSummaryFromJson(json);
      if (turn == null) continue;
      if (latest == null || turn.createdAt.isAfter(latest.createdAt)) {
        latest = turn;
      }
    }
    return latest;
  }

  StudioTurn? _turnSummaryFromJson(Map<String, dynamic> json) {
    try {
      return StudioTurn(
        id: json['id'] as String,
        threadId: json['threadId'] as String,
        requestId: json['requestId'] as String? ?? '',
        taskId: json['taskId'] as String?,
        userMessageId: json['userMessageId'] as String? ?? '',
        prompt: '',
        model: json['model'] as String? ?? '',
        intent: TurnIntent.values.firstWhere(
          (value) => value.name == json['intent'],
          orElse: () => TurnIntent.code,
        ),
        contextSummary: StudioContextSummary.fromJson(
          json['contextSummary'] as Map<String, dynamic>?,
        ),
        status: StudioTurnStatus.values.firstWhere(
          (value) => value.name == json['status'],
          orElse: () => StudioTurnStatus.queued,
        ),
        acceptedPlanState: AcceptedPlanState.values.firstWhere(
          (value) => value.name == json['acceptedPlanState'],
          orElse: () => AcceptedPlanState.none,
        ),
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
        lastError: json['lastError'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  StudioThreadStatus _summaryStatusFor({
    required StudioThreadStatus rawStatus,
    required StudioTurn? latestTurn,
    required String? lastError,
  }) {
    if (!_isLoadedActiveThread(rawStatus)) return rawStatus;
    final turnStatus = switch (latestTurn?.status) {
      StudioTurnStatus.completed => StudioThreadStatus.done,
      StudioTurnStatus.failed => StudioThreadStatus.failed,
      StudioTurnStatus.cancelled => StudioThreadStatus.cancelled,
      StudioTurnStatus.waitingForApproval =>
        StudioThreadStatus.waitingForApproval,
      StudioTurnStatus.toolRunning => StudioThreadStatus.runningCommand,
      StudioTurnStatus.reviewingPatch => StudioThreadStatus.reviewingPatch,
      StudioTurnStatus.verifying => StudioThreadStatus.runningCommand,
      StudioTurnStatus.streaming => StudioThreadStatus.streaming,
      StudioTurnStatus.buildingContext => StudioThreadStatus.buildingContext,
      StudioTurnStatus.interrupted => StudioThreadStatus.failed,
      _ => null,
    };
    if (turnStatus != null) return turnStatus;
    if (lastError?.trim().isNotEmpty ?? false) return StudioThreadStatus.failed;
    return StudioThreadStatus.failed;
  }

  List<StudioThread> _mergeLoadedThreads(
    List<StudioThread> historyThreads,
    List<StudioThread> journalThreads,
  ) {
    if (journalThreads.isEmpty) return historyThreads;
    final byId = <String, StudioThread>{
      for (final thread in historyThreads) thread.id: thread,
    };
    for (final journalThread in journalThreads) {
      final historyThread = byId[journalThread.id];
      if (historyThread == null ||
          _journalThreadIsNewerOrRicher(journalThread, historyThread)) {
        byId[journalThread.id] = journalThread;
      }
    }
    return byId.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  bool _journalThreadIsNewerOrRicher(
    StudioThread journalThread,
    StudioThread historyThread,
  ) {
    if (journalThread.updatedAt.isAfter(historyThread.updatedAt)) return true;
    if (historyThread.updatedAt.isAfter(journalThread.updatedAt)) return false;
    if (journalThread.turns.length != historyThread.turns.length) {
      return journalThread.turns.length > historyThread.turns.length;
    }
    return _threadSignalCount(journalThread) >
        _threadSignalCount(historyThread);
  }

  int _threadSignalCount(StudioThread thread) {
    return thread.turns.fold<int>(
      thread.messages.length,
      (sum, turn) =>
          sum +
          turn.events.length +
          turn.steps.length +
          turn.toolResults.length +
          turn.providerDiagnostics.length +
          turn.planTargetProgress.length,
    );
  }

  Future<List<StudioThread>> _loadFromJournalSnapshots(String? rootPath) async {
    final file = File(journalPath(rootPath));
    if (!await file.exists()) return const [];
    final snapshots = <String, StudioThread>{};
    final snapshotTimes = <String, DateTime>{};
    final decodedRecords = await const StudioThreadJournalReader().read(
      path: file.path,
      envelopeKind: _journalEnvelopeKind,
    );
    for (final decoded in decodedRecords) {
      if (decoded['kind'] != 'thread_snapshot') continue;
      final threadJson = decoded['thread'];
      if (threadJson is! Map) continue;
      final thread = StudioThread.fromJson(
        Map<String, dynamic>.from(threadJson),
      );
      if (thread == null) continue;
      final capturedAt =
          DateTime.tryParse(decoded['capturedAt'] as String? ?? '') ??
          thread.updatedAt;
      final previous = snapshotTimes[thread.id];
      if (previous != null && previous.isAfter(capturedAt)) continue;
      snapshots[thread.id] = thread;
      snapshotTimes[thread.id] = capturedAt;
    }
    final restored = snapshots.values.map(_normalizeLoadedThread).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (restored.isNotEmpty) return restored;
    return _loadFromJournalRecordsForSnapshots(
      decodedRecords.map(Map<String, dynamic>.from).toList(growable: false),
    );
  }
}
