part of 'studio_thread_provider.dart';

class _JournalThreadBuilder {
  final String threadId;
  String? title;
  final Map<String, _JournalTurnBuilder> turns = {};

  _JournalThreadBuilder({required this.threadId, String? title}) {
    mergeTitle(title);
  }

  void mergeTitle(String? value) {
    final next = value?.trim();
    if (next == null || next.isEmpty) return;
    if (_isInternalPrompt(next)) return;
    title ??= next;
  }

  _JournalTurnBuilder turnBuilder(String turnId) {
    return turns.putIfAbsent(
      turnId,
      () => _JournalTurnBuilder(threadId: threadId, turnId: turnId),
    );
  }

  StudioThread? build(StudioTurn Function(StudioTurn turn) normalizeTurn) {
    final rebuiltTurns =
        turns.values
            .map((builder) => builder.build())
            .whereType<StudioTurn>()
            .map(normalizeTurn)
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (rebuiltTurns.isEmpty) return null;
    final latestTurn = rebuiltTurns.reduce(
      (a, b) => a.updatedAt.isAfter(b.updatedAt) ? a : b,
    );
    final createdAt = rebuiltTurns.first.createdAt;
    final updatedAt = latestTurn.updatedAt;
    return StudioThread(
      id: threadId,
      title: title ?? _titleFromTurn(latestTurn),
      status: _threadStatusFromTurn(latestTurn),
      phase: _threadPhaseFromTurn(latestTurn),
      requestId: _activeTurnStatus(latestTurn.status)
          ? latestTurn.requestId
          : null,
      model: latestTurn.model.trim().isEmpty ? null : latestTurn.model,
      contextSummary: latestTurn.contextSummary,
      turns: rebuiltTurns,
      streamingContent: _activeTurnStatus(latestTurn.status)
          ? latestTurn.assistantDraft
          : '',
      lastError: latestTurn.lastError,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  String _titleFromTurn(StudioTurn turn) {
    final userEvent = turn.events
        .where(
          (event) =>
              event.type == StudioTurnEventType.userMessage &&
              event.transcriptVisible &&
              (event.content ?? event.detail).trim().isNotEmpty,
        )
        .firstOrNull;
    final titleSource =
        userEvent?.content ??
        _acceptedPlanTitle(turn) ??
        _outcomeTitle(turn) ??
        (turn.taskTitle.trim().isNotEmpty
            ? turn.taskTitle
            : (_isInternalPrompt(turn.displayPrompt)
                  ? null
                  : turn.displayPrompt));
    final title = (titleSource ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (title.isEmpty) return 'Recovered Studio thread';
    return title.length <= 80 ? title : '${title.substring(0, 77)}...';
  }

  String? _acceptedPlanTitle(StudioTurn turn) {
    final title = turn.acceptedPlanContext?.title.trim();
    if (title == null || title.isEmpty) return null;
    return title;
  }

  String? _outcomeTitle(StudioTurn turn) {
    final outcome = turn.finalOutcome;
    if (outcome != null) return studioTurnOutcomeTitle(outcome);
    final events = turn.events.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final latestEvent = events
        .where(
          (event) =>
              event.type == StudioTurnEventType.assistantMessage ||
              event.type == StudioTurnEventType.completionSummary ||
              event.type == StudioTurnEventType.error,
        )
        .firstOrNull;
    final value =
        (latestEvent?.content ??
                latestEvent?.detail ??
                latestEvent?.title ??
                '')
            .trim();
    if (value.isEmpty) return null;
    return value;
  }

  bool _isInternalPrompt(String prompt) {
    final lower = prompt.trim().toLowerCase();
    const internalPrefixes = [
      'implement this approved plan',
      'use the accepted plan context',
      'running verification',
      'run verification',
      'verify the applied patch',
    ];
    return internalPrefixes.any(lower.startsWith);
  }

  bool _activeTurnStatus(StudioTurnStatus status) {
    return switch (status) {
      StudioTurnStatus.queued ||
      StudioTurnStatus.buildingContext ||
      StudioTurnStatus.sent ||
      StudioTurnStatus.waitingForModel ||
      StudioTurnStatus.streaming ||
      StudioTurnStatus.toolRunning ||
      StudioTurnStatus.waitingForApproval ||
      StudioTurnStatus.verifying => true,
      StudioTurnStatus.reviewingPatch => false,
      StudioTurnStatus.completed ||
      StudioTurnStatus.failed ||
      StudioTurnStatus.cancelled ||
      StudioTurnStatus.interrupted => false,
    };
  }

  StudioThreadStatus _threadStatusFromTurn(StudioTurn turn) {
    return switch (turn.status) {
      StudioTurnStatus.queued ||
      StudioTurnStatus.buildingContext => StudioThreadStatus.buildingContext,
      StudioTurnStatus.sent ||
      StudioTurnStatus.waitingForModel ||
      StudioTurnStatus.streaming => StudioThreadStatus.streaming,
      StudioTurnStatus.toolRunning => StudioThreadStatus.runningCommand,
      StudioTurnStatus.waitingForApproval =>
        StudioThreadStatus.waitingForApproval,
      StudioTurnStatus.reviewingPatch => StudioThreadStatus.reviewingPatch,
      StudioTurnStatus.verifying => StudioThreadStatus.runningCommand,
      StudioTurnStatus.completed => StudioThreadStatus.done,
      StudioTurnStatus.failed => StudioThreadStatus.failed,
      StudioTurnStatus.cancelled => StudioThreadStatus.cancelled,
      StudioTurnStatus.interrupted => StudioThreadStatus.failed,
    };
  }

  StudioSendPhase _threadPhaseFromTurn(StudioTurn turn) {
    return switch (turn.status) {
      StudioTurnStatus.queued ||
      StudioTurnStatus.buildingContext => StudioSendPhase.buildingContext,
      StudioTurnStatus.sent ||
      StudioTurnStatus.waitingForModel => StudioSendPhase.sent,
      StudioTurnStatus.streaming => StudioSendPhase.streaming,
      StudioTurnStatus.toolRunning ||
      StudioTurnStatus.verifying => StudioSendPhase.runningCommand,
      StudioTurnStatus.waitingForApproval => StudioSendPhase.waitingForApproval,
      StudioTurnStatus.reviewingPatch => StudioSendPhase.waitingForApproval,
      StudioTurnStatus.completed => StudioSendPhase.completed,
      StudioTurnStatus.failed => StudioSendPhase.failed,
      StudioTurnStatus.cancelled => StudioSendPhase.cancelled,
      StudioTurnStatus.interrupted => StudioSendPhase.failed,
    };
  }
}

class _JournalTurnBuilder {
  final String threadId;
  final String turnId;
  String? requestId;
  String? taskId;
  String? intent;
  String? status;
  String? acceptedPlanStateName;
  String? model;
  String? lastError;
  DateTime? createdAt;
  DateTime? updatedAt;
  DateTime? completedAt;
  AcceptedPlanContext? acceptedPlanContext;
  ContextRetrievalResult? contextRetrieval;
  final Map<String, StudioTurnEvent> events = {};
  final Map<TurnStep, TurnStepRecord> steps = {};
  final Map<String, ToolResultEnvelope> toolResults = {};
  final List<ProviderLifecycleEvent> providerDiagnostics = [];
  final Map<String, PlanTargetProgress> planTargetProgress = {};

  _JournalTurnBuilder({required this.threadId, required this.turnId});

  void mergeTurnRecord(Map<String, dynamic> record) {
    requestId ??= record['requestId'] as String?;
    taskId ??= record['taskId'] as String?;
    intent ??= record['intent'] as String?;
    status ??= record['status'] as String?;
    acceptedPlanStateName ??= record['acceptedPlanState'] as String?;
    model ??= record['model'] as String?;
    lastError ??= record['lastError'] as String?;
    createdAt ??= DateTime.tryParse(record['createdAt'] as String? ?? '');
    updatedAt = _maxDate(
      updatedAt,
      DateTime.tryParse(record['updatedAt'] as String? ?? ''),
    );
    completedAt ??= DateTime.tryParse(record['completedAt'] as String? ?? '');
  }

  void mergeApprovalRecord(Map<String, dynamic> record) {
    requestId ??= record['requestId'] as String?;
    taskId ??= record['taskId'] as String?;
    final effectiveRequestId = requestId ?? record['requestId'] as String?;
    final approvalId = record['approvalId'] as String?;
    if (effectiveRequestId == null ||
        effectiveRequestId.trim().isEmpty ||
        approvalId == null ||
        approvalId.trim().isEmpty) {
      return;
    }
    final createdAt =
        DateTime.tryParse(record['createdAt'] as String? ?? '') ??
        DateTime.now();
    updatedAt = _maxDate(updatedAt, createdAt);
    final warnings =
        (record['warnings'] as List<dynamic>?)?.whereType<String>().toList() ??
        const <String>[];
    final statusName = record['status'] as String?;
    final scopeName = record['scope'] as String?;
    final riskName = record['risk'] as String?;
    final event = StudioTurnEvent(
      id: 'approval-$effectiveRequestId-$approvalId',
      turnId: turnId,
      requestId: effectiveRequestId,
      threadId: threadId,
      type: StudioTurnEventType.approvalRequest,
      title: 'Approval needed',
      detail: 'Review the tool request.',
      timestamp: createdAt,
      toolCallId: record['toolCallId'] as String?,
      toolName: record['toolName'] as String?,
      approvalId: approvalId,
      approvalState: ApprovalRequestState.values.firstWhere(
        (candidate) => candidate.name == statusName,
        orElse: () => ApprovalRequestState.pending,
      ),
      approvalPreview: record['preview'] as String?,
      approvalWarnings: warnings,
      approvalGrant: scopeName == null
          ? null
          : ApprovalGrant.values.firstWhere(
              (candidate) => candidate.name == scopeName,
              orElse: () => ApprovalGrant.once,
            ),
      approvalRisk: riskName == null
          ? null
          : ToolPermissionReason.values.firstWhere(
              (candidate) => candidate.name == riskName,
              orElse: () => ToolPermissionReason.unknownTool,
            ),
      approvalNormalizedAction: record['normalizedAction'] as String?,
      approvalExpiresAt: DateTime.tryParse(
        record['expiresAt'] as String? ?? '',
      ),
      filePath: record['path'] as String?,
    );
    events[event.id] = event;
  }

  void mergeAcceptedPlanRecord({
    required AcceptedPlanContext? acceptedPlanContext,
    required AcceptedPlanState acceptedPlanState,
    required DateTime? updatedAt,
  }) {
    this.acceptedPlanContext = acceptedPlanContext;
    acceptedPlanStateName = acceptedPlanState.name;
    final context = acceptedPlanContext;
    if (context == null) return;
    final targetUpdatedAt = updatedAt ?? DateTime.now();
    for (final target in context.plannedTargets) {
      final normalizedPath = _normalizeJournalPath(target.path);
      if (normalizedPath.isEmpty ||
          planTargetProgress.containsKey(normalizedPath)) {
        continue;
      }
      planTargetProgress[normalizedPath] = PlanTargetProgress(
        path: normalizedPath,
        intent: target.intent,
        operation: target.operation,
        updatedAt: targetUpdatedAt,
      );
    }
  }

  void mergePatchTransactionRecord(Map<String, dynamic> record) {
    requestId ??= record['requestId'] as String?;
    taskId ??= record['taskId'] as String?;
    final effectiveRequestId = requestId ?? record['requestId'] as String?;
    if (effectiveRequestId == null || effectiveRequestId.trim().isEmpty) {
      return;
    }
    final createdAt =
        DateTime.tryParse(record['createdAt'] as String? ?? '') ??
        DateTime.now();
    updatedAt = _maxDate(updatedAt, createdAt);
    final title = record['title'] as String? ?? 'Patch transaction';
    final detail = record['detail'] as String? ?? '';
    final patchSetId = record['patchSetId'] as String?;
    final eventId =
        record['eventId'] as String? ??
        'patch-transaction-$turnId-${patchSetId ?? _journalIdPart(title)}';
    events[eventId] = StudioTurnEvent.completionSummary(
      id: eventId,
      turnId: turnId,
      requestId: effectiveRequestId,
      threadId: threadId,
      title: title,
      detail: detail,
      patchSetId: patchSetId,
      timestamp: createdAt,
    );
    final status = _patchStepStatus(record['status'] as String?);
    steps.putIfAbsent(
      TurnStep.patchProposal,
      () => TurnStepRecord(
        step: TurnStep.patchProposal,
        status: status,
        title: title,
        detail: detail,
        startedAt: createdAt,
        completedAt: status == TurnStepStatus.running ? null : createdAt,
      ),
    );
    if (record['continueNextBatchAvailable'] == true) {
      final remaining = record['remainingPlanTargets'] as int?;
      final continuationDetail = remaining == null
          ? 'Use Continue next batch to keep implementing the accepted plan.'
          : '$remaining accepted-plan target${remaining == 1 ? '' : 's'} ${remaining == 1 ? 'still needs' : 'still need'} work. Use Continue next batch to keep implementing the accepted plan.';
      steps.putIfAbsent(
        TurnStep.continuation,
        () => TurnStepRecord(
          step: TurnStep.continuation,
          status: TurnStepStatus.queued,
          title: 'Continue next batch',
          detail: continuationDetail,
          startedAt: createdAt,
        ),
      );
    }
    _mergePatchTransactionPlanTargets(
      record: record,
      detail: detail,
      patchSetId: patchSetId,
      createdAt: createdAt,
    );
  }

  void _mergePatchTransactionPlanTargets({
    required Map<String, dynamic> record,
    required String detail,
    required String? patchSetId,
    required DateTime createdAt,
  }) {
    if (planTargetProgress.isEmpty) return;
    final targetState = switch (record['status'] as String?) {
      'applied' => PlanTargetProgressState.applied,
      'conflict' => PlanTargetProgressState.conflict,
      'failed' => PlanTargetProgressState.blocked,
      'rejected' => PlanTargetProgressState.skipped,
      'revisionRequested' => PlanTargetProgressState.proposed,
      'restored' => PlanTargetProgressState.proposed,
      _ => null,
    };
    if (targetState == null) return;
    final paths = _pathsFromPatchTransactionRecord(record, detail).toSet();
    if (paths.isEmpty) return;
    for (final entry in planTargetProgress.entries.toList()) {
      if (!_planTargetMatchesAnyPath(entry.key, paths)) continue;
      planTargetProgress[entry.key] = entry.value.copyWith(
        state: targetState,
        patchSetId: patchSetId,
        detail: detail,
        updatedAt: createdAt,
      );
    }
  }

  List<String> _pathsFromPatchTransactionRecord(
    Map<String, dynamic> record,
    String detail,
  ) {
    final explicitPaths = (record['paths'] as List<dynamic>?)
        ?.whereType<String>()
        .map(_normalizeJournalPath)
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (explicitPaths != null && explicitPaths.isNotEmpty) {
      return explicitPaths;
    }
    return _pathsFromPatchTransactionDetail(detail);
  }

  bool _planTargetMatchesAnyPath(String targetPath, Set<String> paths) {
    final target = _normalizeJournalPath(targetPath);
    if (target.isEmpty) return false;
    for (final path in paths) {
      if (path == target) return true;
      if (target.endsWith('/')) {
        if (path.startsWith(target)) return true;
      } else if (!target.contains('.') && path.startsWith('$target/')) {
        return true;
      }
    }
    return false;
  }

  void mergeCommandRunRecord(Map<String, dynamic> record) {
    requestId ??= record['requestId'] as String?;
    taskId ??= record['taskId'] as String?;
    final effectiveRequestId = requestId ?? record['requestId'] as String?;
    if (effectiveRequestId == null || effectiveRequestId.trim().isEmpty) {
      return;
    }
    final createdAt =
        DateTime.tryParse(record['createdAt'] as String? ?? '') ??
        DateTime.now();
    updatedAt = _maxDate(updatedAt, createdAt);
    final commandRunId = record['toolCallId'] as String?;
    final statusName = (record['status'] as String? ?? 'completed').trim();
    final succeeded = {
      'success',
      'succeeded',
      'completed',
    }.contains(statusName.toLowerCase());
    final title = succeeded ? 'Ran command' : 'Command $statusName';
    final stdout = (record['stdout'] as String?)?.trim();
    final stderr = (record['stderr'] as String?)?.trim();
    final diagnostic = (record['diagnostic'] as String?)?.trim();
    final logPath = (record['logPath'] as String?)?.trim();
    final detail = [
      if ((record['command'] as String?)?.trim().isNotEmpty == true)
        'Command: ${(record['command'] as String).trim()}',
      if (record['exitCode'] != null) 'Exit code: ${record['exitCode']}',
      if (stdout?.isNotEmpty == true) stdout!,
      if (stderr?.isNotEmpty == true && stderr != stdout) stderr!,
      if (diagnostic?.isNotEmpty == true &&
          diagnostic != stdout &&
          diagnostic != stderr)
        diagnostic!,
      if (logPath?.isNotEmpty == true) 'Full log: $logPath',
    ].join('\n');
    final eventId = commandRunId == null || commandRunId.trim().isEmpty
        ? 'command-run-$turnId-${_journalIdPart(statusName)}'
        : 'command-run-$turnId-$commandRunId';
    events[eventId] = StudioTurnEvent.completionSummary(
      id: eventId,
      turnId: turnId,
      requestId: effectiveRequestId,
      threadId: threadId,
      title: title,
      detail: detail,
      timestamp: createdAt,
    );
    final stepStatus = succeeded
        ? TurnStepStatus.completed
        : TurnStepStatus.failed;
    final step = TurnStepRecord(
      step: TurnStep.commandRun,
      status: stepStatus,
      title: title,
      detail: detail,
      startedAt: createdAt,
      completedAt: createdAt,
    );
    steps.putIfAbsent(TurnStep.commandRun, () => step);
    steps.putIfAbsent(
      TurnStep.verification,
      () => TurnStepRecord(
        step: TurnStep.verification,
        status: stepStatus,
        title: title,
        detail: detail,
        startedAt: createdAt,
        completedAt: createdAt,
      ),
    );
  }

  StudioTurn? build() {
    final sortedEvents = events.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final userEvent = sortedEvents
        .where((event) => event.type == StudioTurnEventType.userMessage)
        .firstOrNull;
    final visibleUserEvent = sortedEvents
        .where(
          (event) =>
              event.type == StudioTurnEventType.userMessage &&
              event.transcriptVisible &&
              (event.content ?? event.detail).trim().isNotEmpty,
        )
        .firstOrNull;
    final effectiveRequestId = requestId ?? userEvent?.requestId;
    if (effectiveRequestId == null || effectiveRequestId.trim().isEmpty) {
      return null;
    }
    final effectiveCreatedAt =
        createdAt ??
        (sortedEvents.isEmpty ? null : sortedEvents.first.timestamp) ??
        DateTime.now();
    final effectiveUpdatedAt =
        updatedAt ??
        (sortedEvents.isEmpty ? null : sortedEvents.last.timestamp) ??
        effectiveCreatedAt;
    final effectiveModel = model ?? _modelFromDiagnostics() ?? 'gpt-5-nano';
    final contextSummary = StudioContextSummary(
      projectLabel: 'Recovered journal',
      includedItemCount: contextRetrieval?.includedCandidates.length ?? 0,
      omittedCandidateCount: contextRetrieval?.omittedCandidates.length ?? 0,
      estimatedTokens: contextRetrieval?.budget.usedTokens ?? 0,
      warnings: const [
        'Recovered from lifecycle journal because the thread snapshot was unavailable.',
      ],
    );
    return StudioTurn(
      id: turnId,
      threadId: threadId,
      requestId: effectiveRequestId,
      taskId: taskId,
      userMessageId: userEvent?.id ?? 'message-$turnId',
      prompt: visibleUserEvent?.content ?? '',
      model: effectiveModel,
      intent: TurnIntent.values.firstWhere(
        (candidate) => candidate.name == intent,
        orElse: () => TurnIntent.code,
      ),
      contextSummary: contextSummary,
      status: StudioTurnStatus.values.firstWhere(
        (candidate) => candidate.name == status,
        orElse: () => StudioTurnStatus.completed,
      ),
      events: sortedEvents,
      steps: steps.values.toList()
        ..sort((a, b) => a.startedAt.compareTo(b.startedAt)),
      toolResults: toolResults.values.toList(),
      providerDiagnostics: providerDiagnostics
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp)),
      acceptedPlanState: AcceptedPlanState.values.firstWhere(
        (candidate) => candidate.name == acceptedPlanStateName,
        orElse: () => AcceptedPlanState.none,
      ),
      acceptedPlanContext: acceptedPlanContext,
      planTargetProgress: planTargetProgress.values.toList()
        ..sort((a, b) => a.path.compareTo(b.path)),
      contextRetrieval: contextRetrieval,
      createdAt: effectiveCreatedAt,
      updatedAt: effectiveUpdatedAt,
      completedAt: completedAt,
      lastError: lastError,
    );
  }

  String? _modelFromDiagnostics() {
    for (final diagnostic in providerDiagnostics.reversed) {
      if (diagnostic.model.trim().isNotEmpty) {
        return diagnostic.model;
      }
    }
    return null;
  }

  DateTime? _maxDate(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  TurnStepStatus _patchStepStatus(String? status) {
    return switch (status) {
      'applied' || 'restored' => TurnStepStatus.completed,
      'revisionRequested' => TurnStepStatus.queued,
      'conflict' || 'failed' || 'rejected' => TurnStepStatus.failed,
      _ => TurnStepStatus.running,
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

  String _journalIdPart(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }
}

const _sentinel = Object();
