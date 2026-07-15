part of 'studio_thread_provider.dart';

mixin StudioThreadStorePersistence {
  StudioCommandLogStore get commandLogStore;
  Map<String, Set<String>> get _journalLineCacheByPath;
  String historyPath(String? rootPath);
  String journalPath(String? rootPath);
  String summaryPath(String? rootPath);
  String summaryIndexPath(String? rootPath);
  Future<List<StudioThread>> load(String? rootPath);
  Future<void> _repairRecoveredHistory(
    String? rootPath,
    List<StudioThread> threads,
  );
  set _lastRecoveryMessage(String? value);
  String recoveryBackupPath(String? rootPath);
  String journalBackupPath(String? rootPath);
  VersionedJsonDocument _decodeHistoryDocument(String contents);
  Future<void> save(String? rootPath, List<StudioThread> threads) async {
    final file = File(historyPath(rootPath));
    // In large projects the controller retains metadata rows for unopened
    // threads. Merge only hydrated/new thread records into the on-disk detail
    // set so an update to one selected task can never truncate its neighbours.
    final sourceThreads = threads.any((thread) => !thread.detailLoaded)
        ? await _mergeHydratedThreads(rootPath, threads)
        : threads;
    final persistedThreads = sourceThreads.map(_threadForPersistence).toList();
    await _preserveCurrentHistory(file, rootPath);
    await writeVersionedJsonAtomically(file, _encodeHistory(persistedThreads));
    await _writeSummaries(rootPath, persistedThreads);
    await _writeJournal(rootPath, persistedThreads);
  }

  Future<List<StudioThread>> _mergeHydratedThreads(
    String? rootPath,
    List<StudioThread> threads,
  ) async {
    final existing = await load(rootPath);
    final byId = {for (final thread in existing) thread.id: thread};
    for (final thread in threads) {
      if (thread.detailLoaded || !byId.containsKey(thread.id)) {
        byId[thread.id] = thread;
      }
    }
    return byId.values.toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  }

  /// Restores recoverable data into a fresh primary snapshot. This is safe to
  /// call after the app has opened with an empty recovered history as well.
  Future<StudioStorageRepairResult> repair(String? rootPath) async {
    final threads = await load(rootPath);
    await _repairRecoveredHistory(rootPath, threads);
    final message = threads.isEmpty
        ? 'Started a clean thread-history store. Existing raw files were kept for export.'
        : 'Repaired thread history with ${threads.length} recovered ${threads.length == 1 ? 'thread' : 'threads'}.';
    _lastRecoveryMessage = message;
    return StudioStorageRepairResult(
      recoveredThreadCount: threads.length,
      message: message,
    );
  }

  /// Exports the local history and recovery sidecars exactly as they are.
  /// This is intentionally user-initiated because history can contain prompts
  /// and tool output that should not be included in a redacted support bundle.
  Future<void> exportRecoveryBundle(
    String? rootPath,
    String destinationPath,
  ) async {
    final files = <String, String>{};
    for (final path in [
      historyPath(rootPath),
      recoveryBackupPath(rootPath),
      journalPath(rootPath),
      journalBackupPath(rootPath),
    ]) {
      final file = File(path);
      if (!await file.exists()) continue;
      try {
        files[p.basename(path)] = await file.readAsString();
      } catch (_) {
        // Export every readable recovery source; a locked sidecar should not
        // prevent the user from collecting the remaining evidence.
      }
    }
    await writeVersionedJsonAtomically(
      File(destinationPath),
      const JsonEncoder.withIndent('  ').convert({
        'kind': 'circuit.studio-thread-recovery-export',
        'exportedAt': DateTime.now().toIso8601String(),
        'files': files,
      }),
    );
  }

  Future<void> _preserveCurrentHistory(File file, String? rootPath) async {
    if (!await file.exists()) return;
    try {
      final contents = await file.readAsString();
      _decodeHistoryDocument(contents);
      await writeVersionedJsonAtomically(
        File(recoveryBackupPath(rootPath)),
        contents,
      );
    } catch (_) {
      // Never replace the last known-good backup with a corrupt primary file.
    }
  }

  Future<void> _writeSummaries(
    String? rootPath,
    List<StudioThread> threads,
  ) async {
    final file = File(summaryPath(rootPath));
    final summaries = threads.map(_threadSummaryForPersistence).toList();
    await writeVersionedJsonAtomically(file, _encodeSummaries(summaries));
    await _writeSummaryIndex(rootPath, summaries);
  }

  Future<void> _writeSummaryIndex(
    String? rootPath,
    List<StudioThread> summaries,
  ) async {
    final lines = [
      jsonEncode({
        'kind': 'circuit.studio-thread-summary-index',
        'version': 1,
        'totalCount': summaries.length,
      }),
      for (final summary in summaries) jsonEncode(summary.toJson()),
    ];
    await writeVersionedJsonAtomically(
      File(summaryIndexPath(rootPath)),
      '${lines.join('\n')}\n',
    );
  }

  String _encodeHistory(List<StudioThread> threads) {
    return VersionedJsonDocument(
      kind: _historySchemaKind,
      schemaVersion: _schemaVersion,
      payload: threads.map((thread) => thread.toJson()).toList(),
    ).encode(pretty: true);
  }

  String _encodeSummaries(List<StudioThread> summaries) {
    return VersionedJsonDocument(
      kind: _summarySchemaKind,
      schemaVersion: _schemaVersion,
      payload: summaries.map((thread) => thread.toJson()).toList(),
    ).encode(pretty: true);
  }

  StudioThread _threadSummaryForPersistence(StudioThread thread) {
    final latestTurn = thread.turns.fold<StudioTurn?>(
      null,
      (latest, turn) =>
          latest == null || turn.createdAt.isAfter(latest.createdAt)
          ? turn
          : latest,
    );
    return thread.copyWith(
      messages: const <StudioThreadMessage>[],
      sourceArtifacts: const <StudioSourceArtifact>[],
      turns: latestTurn == null
          ? const <StudioTurn>[]
          : [_turnSummaryForPersistence(latestTurn)],
      streamingContent: '',
      updatedAt: thread.updatedAt,
    );
  }

  StudioTurn _turnSummaryForPersistence(StudioTurn turn) {
    return StudioTurn(
      id: turn.id,
      threadId: turn.threadId,
      requestId: turn.requestId,
      taskId: turn.taskId,
      userMessageId: turn.userMessageId,
      prompt: '',
      model: turn.model,
      intent: turn.intent,
      contextSummary: turn.contextSummary,
      status: turn.status,
      acceptedPlanState: turn.acceptedPlanState,
      createdAt: turn.createdAt,
      updatedAt: turn.updatedAt,
      completedAt: turn.completedAt,
      lastError: turn.lastError,
    );
  }

  StudioThread _threadForPersistence(StudioThread thread) {
    final persistedTurns = thread.turns
        .map(_turnForPersistence)
        .toList(growable: false);
    if (thread.messages.isEmpty && persistedTurns == thread.turns) {
      return thread;
    }
    return thread.copyWith(
      messages: thread.turns.isEmpty
          ? thread.messages
          : const <StudioThreadMessage>[],
      turns: persistedTurns,
      updatedAt: thread.updatedAt,
    );
  }

  StudioTurn _turnForPersistence(StudioTurn turn) {
    final toolResults = turn.toolResults
        .map(
          (result) => compactCommandToolResult(
            result: result,
            store: commandLogStore,
            requestId: turn.requestId,
            turnId: turn.id,
          ),
        )
        .toList(growable: false);
    final events = turn.events
        .map((event) => _turnEventForPersistence(turn, event))
        .toList(growable: false);
    final steps = turn.steps
        .map((step) => _turnStepForPersistence(turn, step))
        .toList(growable: false);
    return turn.copyWith(
      toolResults: toolResults,
      events: events,
      steps: steps,
      updatedAt: turn.updatedAt,
    );
  }

  StudioTurnEvent _turnEventForPersistence(
    StudioTurn turn,
    StudioTurnEvent event,
  ) {
    if (event.type != StudioTurnEventType.completionSummary ||
        !event.id.startsWith('command-run-') ||
        event.detail.length <= inlineCommandOutputLimit) {
      return event;
    }
    final commandRunId = _commandRunIdFromEvent(event.id, turn.id);
    final command = _commandFromCommandEventDetail(event.detail);
    final exitCode = _exitCodeFromCommandEventDetail(event.detail);
    final logPath = _commandLogPathFromDetail(event.detail);
    return event.copyWith(
      detail: _compactCommandEventDetail(
        detail: event.detail,
        command: command,
        turn: turn,
        commandRunId: commandRunId,
        status: _commandStatusFromEventTitle(event.title),
        exitCode: exitCode,
        logPath: logPath,
      ),
    );
  }

  TurnStepRecord _turnStepForPersistence(StudioTurn turn, TurnStepRecord step) {
    if (step.step != TurnStep.commandRun ||
        step.detail.length <= inlineCommandOutputLimit) {
      return step;
    }
    final command = _commandFromCommandEventDetail(step.detail);
    final exitCode = _exitCodeFromCommandEventDetail(step.detail);
    final logPath = _commandLogPathFromDetail(step.detail);
    return step.copyWith(
      detail: _compactCommandEventDetail(
        detail: step.detail,
        command: command,
        turn: turn,
        commandRunId: 'step-${step.step.name}',
        status: step.status.name,
        exitCode: exitCode,
        logPath: logPath,
      ),
    );
  }

  Future<void> _writeJournal(
    String? rootPath,
    List<StudioThread> threads,
  ) async {
    final file = File(journalPath(rootPath));
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    final lines = <String>[];
    void addRecord(Map<String, dynamic> record) {
      lines.add(_encodeJournalRecord(record));
    }

    for (final thread in threads) {
      addRecord({
        'kind': 'thread_snapshot',
        'threadId': thread.id,
        'threadTitle': thread.title,
        'status': thread.status.name,
        'phase': thread.phase.name,
        'turnCount': thread.turns.length,
        'updatedAt': thread.updatedAt.toIso8601String(),
        'capturedAt': DateTime.now().toIso8601String(),
        'thread': thread.toJson(),
      });
      for (final turn in thread.turns) {
        addRecord({
          'kind': 'turn',
          'threadId': thread.id,
          'threadTitle': thread.title,
          'turnId': turn.id,
          'requestId': turn.requestId,
          if (turn.taskId != null) 'taskId': turn.taskId,
          'intent': turn.intent.name,
          'status': turn.status.name,
          'model': turn.model,
          'acceptedPlanState': turn.acceptedPlanState.name,
          'createdAt': turn.createdAt.toIso8601String(),
          'updatedAt': turn.updatedAt.toIso8601String(),
          if (turn.completedAt != null)
            'completedAt': turn.completedAt!.toIso8601String(),
          if (turn.lastError != null) 'lastError': turn.lastError,
        });
        final contextRecord = _contextRetrievalJournalRecord(
          thread: thread,
          turn: turn,
        );
        if (contextRecord != null) {
          addRecord(contextRecord);
        }
        for (final step in turn.steps) {
          addRecord({
            'kind': 'turn_step',
            'threadId': thread.id,
            'threadTitle': thread.title,
            'turnId': turn.id,
            'requestId': turn.requestId,
            if (turn.taskId != null) 'taskId': turn.taskId,
            'intent': turn.intent.name,
            'step': step.toJson(),
          });
        }
        final acceptedPlanRecord = _acceptedPlanJournalRecord(
          thread: thread,
          turn: turn,
        );
        if (acceptedPlanRecord != null) {
          addRecord(acceptedPlanRecord);
        }
        for (final planTargetRecord in _planTargetJournalRecords(
          thread: thread,
          turn: turn,
        )) {
          addRecord(planTargetRecord);
        }
        final structuredCommandResultIds = turn.toolResults
            .where((result) => result.toolName == 'run_command')
            .map((result) => result.toolCallId)
            .toSet();
        final structuredCommandResultCommands = turn.toolResults
            .where((result) => result.toolName == 'run_command')
            .map((result) => result.data['command'])
            .whereType<String>()
            .map((command) => command.trim())
            .where((command) => command.isNotEmpty)
            .toSet();
        for (final event in turn.events) {
          addRecord({
            'kind': 'turn_event',
            'threadId': thread.id,
            'turnId': turn.id,
            'requestId': turn.requestId,
            'event': event.toJson(),
          });
          final approvalRecord = _approvalJournalRecord(
            thread: thread,
            turn: turn,
            event: event,
          );
          if (approvalRecord != null) {
            addRecord(approvalRecord);
          }
          final patchTransactionRecord = _patchTransactionJournalRecord(
            thread: thread,
            turn: turn,
            event: event,
          );
          if (patchTransactionRecord != null) {
            addRecord(patchTransactionRecord);
          }
          final commandRunRecord = _commandRunJournalRecordFromEvent(
            thread: thread,
            turn: turn,
            event: event,
            structuredCommandResultIds: structuredCommandResultIds,
            structuredCommandResultCommands: structuredCommandResultCommands,
          );
          if (commandRunRecord != null) {
            addRecord(commandRunRecord);
          }
        }
        for (final result in turn.toolResults) {
          final resultForStorage = compactCommandToolResult(
            result: result,
            store: commandLogStore,
            requestId: turn.requestId,
            turnId: turn.id,
          );
          addRecord({
            'kind': 'tool_result',
            'threadId': thread.id,
            'turnId': turn.id,
            'requestId': turn.requestId,
            'result': resultForStorage.toJson(),
          });
          final commandRunRecord = _commandRunJournalRecord(
            thread: thread,
            turn: turn,
            result: resultForStorage,
          );
          if (commandRunRecord != null) {
            addRecord(commandRunRecord);
          }
        }
        for (final diagnostic in turn.providerDiagnostics) {
          addRecord({
            'kind': 'provider_diagnostic',
            'threadId': thread.id,
            'turnId': turn.id,
            'requestId': turn.requestId,
            'diagnostic': diagnostic.toJson(),
          });
        }
      }
    }
    if (lines.isEmpty) return;
    final existing = await _existingJournalLines(file);
    final newLines = lines
        .where((line) => existing.add(line))
        .toList(growable: false);
    if (newLines.isEmpty) return;
    await file.writeAsString(
      '${newLines.join('\n')}\n',
      mode: FileMode.append,
      flush: true,
    );
    await _compactJournalIfNeeded(file, rootPath, threads);
  }

  String _encodeJournalRecord(Map<String, dynamic> record) {
    return jsonEncode({
      'envelopeKind': _journalEnvelopeKind,
      'payload': record,
      'checksum': VersionedJsonDocument.checksumFor(record),
    });
  }

  Future<void> _compactJournalIfNeeded(
    File file,
    String? rootPath,
    List<StudioThread> threads,
  ) async {
    final int size;
    final int lineCount;
    try {
      size = await file.length();
      lineCount = (await _readJournalLines(file)).length;
    } on FileSystemException {
      // An external workspace cleanup can remove a journal after its append
      // succeeded but before optional compaction begins. Its committed history
      // snapshot remains authoritative; do not surface a late background
      // compaction error or retain stale duplicate-line cache entries.
      _journalLineCacheByPath.remove(file.path);
      return;
    }
    if (size < _journalCompactionByteThreshold &&
        lineCount < _journalCompactionLineThreshold) {
      return;
    }
    try {
      await writeVersionedJsonAtomically(
        File(journalBackupPath(rootPath)),
        await file.readAsString(),
      );
      final compacted = threads
          .map(
            (thread) => _encodeJournalRecord({
              'kind': 'thread_snapshot',
              'threadId': thread.id,
              'threadTitle': thread.title,
              'status': thread.status.name,
              'phase': thread.phase.name,
              'turnCount': thread.turns.length,
              'updatedAt': thread.updatedAt.toIso8601String(),
              'capturedAt': DateTime.now().toIso8601String(),
              'thread': thread.toJson(),
            }),
          )
          .toList(growable: false);
      await writeVersionedJsonAtomically(file, '${compacted.join('\n')}\n');
      _journalLineCacheByPath[file.path] = compacted.toSet();
    } catch (_) {
      // Appending records remains safe if compaction cannot run. The next save
      // will retry without discarding the durable journal.
    }
  }

  Future<Set<String>> _existingJournalLines(File file) async {
    final cached = _journalLineCacheByPath[file.path];
    if (cached != null) return cached;
    if (!await file.exists()) {
      final empty = <String>{};
      _journalLineCacheByPath[file.path] = empty;
      return empty;
    }
    final lines = await _readJournalLines(file);
    final existing = lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toSet();
    _journalLineCacheByPath[file.path] = existing;
    return existing;
  }

  Future<List<String>> _readJournalLines(File file) async {
    try {
      return await file.readAsLines();
    } on FileSystemException {
      final bytes = await file.readAsBytes();
      return const LineSplitter().convert(
        utf8.decode(bytes, allowMalformed: true),
      );
    } on FormatException {
      final bytes = await file.readAsBytes();
      return const LineSplitter().convert(
        utf8.decode(bytes, allowMalformed: true),
      );
    }
  }

  Map<String, dynamic>? _contextRetrievalJournalRecord({
    required StudioThread thread,
    required StudioTurn turn,
  }) {
    final retrieval = turn.contextRetrieval;
    if (retrieval == null) return null;
    final included = retrieval.includedCandidates;
    final omitted = retrieval.omittedCandidates;
    return {
      'kind': 'context_retrieval',
      'threadId': thread.id,
      'threadTitle': thread.title,
      'turnId': turn.id,
      'requestId': turn.requestId,
      if (turn.taskId != null) 'taskId': turn.taskId,
      'intent': turn.intent.name,
      'budget': retrieval.budget.toJson(),
      'includedCount': included.length,
      'omittedCount': omitted.length,
      'warningCount': retrieval.warnings.length,
      'included': included.map(_contextCandidateJournalRecord).toList(),
      'omitted': omitted.map(_contextCandidateJournalRecord).toList(),
      if (retrieval.warnings.isNotEmpty)
        'warnings': retrieval.warnings
            .map((warning) => warning.toJson())
            .toList(),
      'updatedAt': turn.updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> _contextCandidateJournalRecord(
    ContextCandidate candidate,
  ) {
    return {
      'id': candidate.id,
      'title': candidate.title,
      if (candidate.path != null) 'path': candidate.path,
      'sourceKind': candidate.sourceKind.name,
      'score': candidate.score,
      'estimatedTokens': candidate.estimatedTokens,
      'reason': candidate.reason,
    };
  }

  Map<String, dynamic>? _acceptedPlanJournalRecord({
    required StudioThread thread,
    required StudioTurn turn,
  }) {
    final acceptedPlan = turn.acceptedPlanContext;
    if (acceptedPlan == null) return null;
    return {
      'kind': 'accepted_plan',
      'threadId': thread.id,
      'threadTitle': thread.title,
      'turnId': turn.id,
      'requestId': turn.requestId,
      if (turn.taskId != null) 'taskId': turn.taskId,
      'patchSetId': acceptedPlan.patchSetId,
      'title': acceptedPlan.title,
      'summary': acceptedPlan.summary,
      'markdown': acceptedPlan.markdown,
      'acceptedPlanState': turn.acceptedPlanState.name,
      'plannedFileCount': acceptedPlan.plannedFiles.length,
      'plannedTargetCount': acceptedPlan.plannedTargets.length,
      'verificationRequested': acceptedPlan.verificationRequested,
      if (acceptedPlan.plannedFiles.isNotEmpty)
        'plannedFiles': acceptedPlan.plannedFiles,
      if (acceptedPlan.plannedTargets.isNotEmpty)
        'plannedTargets': acceptedPlan.plannedTargets
            .map((target) => target.toJson())
            .toList(),
      'updatedAt': turn.updatedAt.toIso8601String(),
    };
  }

  Iterable<Map<String, dynamic>> _planTargetJournalRecords({
    required StudioThread thread,
    required StudioTurn turn,
  }) sync* {
    for (final target in turn.planTargetProgress) {
      yield {
        'kind': 'plan_target',
        'threadId': thread.id,
        'threadTitle': thread.title,
        'turnId': turn.id,
        'requestId': turn.requestId,
        if (turn.taskId != null) 'taskId': turn.taskId,
        'acceptedPlanState': turn.acceptedPlanState.name,
        'path': target.path,
        'intent': target.intent,
        if (target.operation != null) 'operation': target.operation!.name,
        'state': target.state.name,
        if (target.patchSetId != null) 'patchSetId': target.patchSetId,
        if (target.detail != null) 'detail': target.detail,
        'updatedAt': target.updatedAt.toIso8601String(),
      };
    }
  }

  Map<String, dynamic>? _approvalJournalRecord({
    required StudioThread thread,
    required StudioTurn turn,
    required StudioTurnEvent event,
  }) {
    if (event.type != StudioTurnEventType.approvalRequest) return null;
    return {
      'kind': 'approval',
      'threadId': thread.id,
      'threadTitle': thread.title,
      'turnId': turn.id,
      'requestId': turn.requestId,
      if (turn.taskId != null) 'taskId': turn.taskId,
      'approvalId': event.approvalId,
      'toolCallId': event.toolCallId,
      'toolName': event.toolName,
      'status': event.approvalState?.name,
      'preview': event.approvalPreview,
      if (event.approvalWarnings.isNotEmpty) 'warnings': event.approvalWarnings,
      if (event.approvalGrant != null) 'scope': event.approvalGrant!.name,
      if (event.approvalRisk != null) 'risk': event.approvalRisk!.name,
      if (event.approvalNormalizedAction != null)
        'normalizedAction': event.approvalNormalizedAction,
      if (event.approvalExpiresAt != null)
        'expiresAt': event.approvalExpiresAt!.toIso8601String(),
      if (event.filePath != null) 'path': event.filePath,
      'createdAt': event.timestamp.toIso8601String(),
    };
  }

  Map<String, dynamic>? _patchTransactionJournalRecord({
    required StudioThread thread,
    required StudioTurn turn,
    required StudioTurnEvent event,
  }) {
    if (event.type != StudioTurnEventType.completionSummary ||
        !event.id.startsWith('patch-transaction-')) {
      return null;
    }
    return {
      'kind': 'patch_transaction',
      'threadId': thread.id,
      'threadTitle': thread.title,
      'turnId': turn.id,
      'requestId': turn.requestId,
      if (turn.taskId != null) 'taskId': turn.taskId,
      'eventId': event.id,
      if (event.patchSetId != null) 'patchSetId': event.patchSetId,
      'title': event.title,
      'detail': event.detail,
      if (_patchTransactionStatus(event.title) != null)
        'status': _patchTransactionStatus(event.title),
      if (_pathsFromPatchTransactionDetail(event.detail).isNotEmpty)
        'paths': _pathsFromPatchTransactionDetail(event.detail),
      if (_checkpointIdFromPatchTransactionDetail(event.detail) != null)
        'checkpointId': _checkpointIdFromPatchTransactionDetail(event.detail),
      if (_remainingPlanTargetCount(event.detail) != null)
        'remainingPlanTargets': _remainingPlanTargetCount(event.detail),
      if (_hasContinueNextBatchGuidance(event.detail))
        'continueNextBatchAvailable': true,
      'createdAt': event.timestamp.toIso8601String(),
    };
  }

  String? _patchTransactionStatus(String title) {
    return switch (title.trim().toLowerCase()) {
      'applied changes' => 'applied',
      'restored checkpoint' => 'restored',
      'patch conflict' => 'conflict',
      'patch apply failed' => 'failed',
      'patch rejected' => 'rejected',
      'patch revision requested' => 'revisionRequested',
      _ => null,
    };
  }

  List<String> _pathsFromPatchTransactionDetail(String detail) {
    final paths = <String>[];
    final filesLine = RegExp(
      r'Here.s what changed:\s*([^\n]+)',
    ).firstMatch(detail);
    if (filesLine != null) {
      paths.addAll(
        filesLine
            .group(1)!
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty),
      );
    }
    final legacyFilesLine = RegExp(
      r'(?:^|\n)Files:\s*([^\n]+)',
      caseSensitive: false,
    ).firstMatch(detail);
    if (legacyFilesLine != null) {
      paths.addAll(
        legacyFilesLine
            .group(1)!
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty),
      );
    }
    final conflictPath = RegExp(
      r'(?:File changed since proposal|File already exists|File missing for modify|File missing for delete|Patch does not change file content|Patch target is a directory|Patch is missing expected prior content for|Patch is missing full target content for|Secret or environment file paths cannot be patched):\s*([^\n]+)',
    ).firstMatch(detail);
    if (conflictPath != null) {
      paths.add(conflictPath.group(1)!.trim());
    }
    final proseConflictPath = _pathFromPatchConflictProse(detail);
    if (proseConflictPath != null) {
      paths.add(proseConflictPath);
    }
    return paths
        .map(_normalizeJournalPath)
        .where((path) => path.isNotEmpty)
        .toList();
  }

  String? _pathFromPatchConflictProse(String detail) {
    final patterns = [
      RegExp(
        r'\bfor\s+([^\n]+?)(?:\. Ask\b|\. Revise\b| before\b| on line\b|$)',
        caseSensitive: false,
      ),
      RegExp(r'\bin\s+([^\n]+?)\s+on line\b', caseSensitive: false),
      RegExp(r'\bPatch leaves\s+([^\n]+?)\s+empty\b', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(detail);
      final path = _cleanExtractedPatchPath(match?.group(1));
      if (path != null) return path;
    }
    return null;
  }

  String? _cleanExtractedPatchPath(String? value) {
    final initial = value?.trim();
    if (initial == null || initial.isEmpty) return null;
    var path = initial
        .replaceAll(RegExp(r'''^[`"']+|[`"']+$'''), '')
        .replaceAll(RegExp(r'\s*\([^)]*\)$'), '')
        .trim();
    while (path.isNotEmpty && ',.;:'.contains(path[path.length - 1])) {
      path = path.substring(0, path.length - 1).trim();
    }
    if (path.isEmpty) return null;
    if (path.contains(' ') && !path.contains('/')) return null;
    return path;
  }

  String _normalizeJournalPath(String value) {
    return value.trim().replaceAll('\\', '/').replaceAll(RegExp(r'^\./+'), '');
  }

  String? _checkpointIdFromPatchTransactionDetail(String detail) {
    final match = RegExp(
      r'(?:Checkpoint|checkpoint):\s*([A-Za-z0-9._:-]+)',
    ).firstMatch(detail);
    return match?.group(1)?.trim();
  }

  int? _remainingPlanTargetCount(String detail) {
    final match = RegExp(
      r'Next batch:\s*(\d+)\s+accepted-plan target',
    ).firstMatch(detail);
    return int.tryParse(match?.group(1) ?? '');
  }

  bool _hasContinueNextBatchGuidance(String detail) {
    return detail.toLowerCase().contains('continue next batch');
  }

  Map<String, dynamic>? _commandRunJournalRecord({
    required StudioThread thread,
    required StudioTurn turn,
    required ToolResultEnvelope result,
  }) {
    if (result.toolName != 'run_command') return null;
    final command = result.data['command'] as String?;
    return {
      'kind': 'command_run',
      'threadId': thread.id,
      'threadTitle': thread.title,
      'turnId': turn.id,
      'requestId': turn.requestId,
      'toolCallId': result.toolCallId,
      if (turn.taskId != null) 'taskId': turn.taskId,
      'command': command,
      'status': result.status.name,
      'summary': result.summary,
      if (result.stdout != null) 'stdout': result.stdout,
      if (result.stderr != null) 'stderr': result.stderr,
      if (result.data['exitCode'] != null) 'exitCode': result.data['exitCode'],
      if (result.data['logPath'] != null) 'logPath': result.data['logPath'],
      if (result.diagnostic != null) 'diagnostic': result.diagnostic,
      'retryable': result.retryable,
      'createdAt': turn.updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic>? _commandRunJournalRecordFromEvent({
    required StudioThread thread,
    required StudioTurn turn,
    required StudioTurnEvent event,
    required Set<String> structuredCommandResultIds,
    required Set<String> structuredCommandResultCommands,
  }) {
    if (event.type != StudioTurnEventType.completionSummary) return null;
    final title = event.title.toLowerCase();
    if (title != 'ran command' && !title.startsWith('command ')) return null;
    final commandRunId = _commandRunIdFromEvent(event.id, turn.id);
    if (commandRunId != null &&
        structuredCommandResultIds.contains(commandRunId)) {
      return null;
    }
    final detail = event.detail;
    final command = _commandFromCommandEventDetail(detail);
    if (command != null && structuredCommandResultCommands.contains(command)) {
      return null;
    }
    final exitCode = _exitCodeFromCommandEventDetail(detail);
    final logPath = _commandLogPathFromDetail(detail);
    final compactDetail = _compactCommandEventDetail(
      detail: detail,
      command: command,
      turn: turn,
      commandRunId: commandRunId,
      status: _commandStatusFromEventTitle(event.title),
      exitCode: exitCode,
      logPath: logPath,
    );
    return {
      'kind': 'command_run',
      'threadId': thread.id,
      'threadTitle': thread.title,
      'turnId': turn.id,
      'requestId': turn.requestId,
      'toolCallId': ?commandRunId,
      if (turn.taskId != null) 'taskId': turn.taskId,
      'command': command,
      'status': _commandStatusFromEventTitle(event.title),
      'summary': event.title,
      'exitCode': ?exitCode,
      'logPath': ?logPath,
      if (compactDetail.trim().isNotEmpty) 'diagnostic': compactDetail,
      if (compactDetail.trim().isNotEmpty) 'stdout': compactDetail,
      'createdAt': event.timestamp.toIso8601String(),
    };
  }

  String _compactCommandEventDetail({
    required String detail,
    required String? command,
    required StudioTurn turn,
    required String? commandRunId,
    required String status,
    required int? exitCode,
    required String? logPath,
  }) {
    final trimmed = detail.trim();
    if (trimmed.length <= inlineCommandOutputLimit) return trimmed;
    if (logPath != null) return summarizeCommandOutput(trimmed, logPath);
    final writtenLogPath = commandLogStore.write(
      requestId: turn.requestId,
      turnId: turn.id,
      commandRunId: commandRunId ?? _commandLogIdPart(status),
      command: command ?? '',
      status: status,
      output: trimmed,
      exitCode: exitCode,
    );
    return summarizeCommandOutput(trimmed, writtenLogPath);
  }

  String _commandLogIdPart(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    return normalized.isEmpty ? 'command' : normalized;
  }

  String? _commandRunIdFromEvent(String eventId, String turnId) {
    final prefix = 'command-run-$turnId-';
    if (!eventId.startsWith(prefix)) return null;
    final id = eventId.substring(prefix.length).trim();
    return id.isEmpty ? null : id;
  }

  String? _commandFromCommandEventDetail(String detail) {
    final match = RegExp(r'(?:^|\n)Command:\s*([^\n]+)').firstMatch(detail);
    return match?.group(1)?.trim();
  }

  String? _commandLogPathFromDetail(String detail) {
    for (final line in detail.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.toLowerCase().startsWith('full log:')) {
        final path = trimmed.substring('full log:'.length).trim();
        return path.isEmpty ? null : path;
      }
    }
    return null;
  }

  int? _exitCodeFromCommandEventDetail(String detail) {
    final match = RegExp(r'(?:^|\n)Exit code:\s*(-?\d+)').firstMatch(detail);
    return int.tryParse(match?.group(1) ?? '');
  }

  String _commandStatusFromEventTitle(String title) {
    final normalized = title.trim().toLowerCase();
    if (normalized == 'ran command') return 'success';
    if (normalized.startsWith('command ')) {
      final status = normalized.substring('command '.length).trim();
      if (status.isNotEmpty) return status;
    }
    return normalized.isEmpty ? 'completed' : normalized;
  }
}
