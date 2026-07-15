part of 'studio_thread_provider.dart';

mixin StudioThreadStoreRecovery {
  String journalPath(String? rootPath);
  List<StudioThread> _loadFromJournalRecords(
    List<Map<String, dynamic>> records,
  ) {
    final builders = <String, _JournalThreadBuilder>{};
    _JournalThreadBuilder builderFor(String threadId, String? title) {
      return builders.putIfAbsent(
        threadId,
        () => _JournalThreadBuilder(threadId: threadId, title: title),
      )..mergeTitle(title);
    }

    _JournalTurnBuilder? turnBuilderFor(Map<String, dynamic> record) {
      final threadId = record['threadId'] as String?;
      final turnId = record['turnId'] as String?;
      if (threadId == null ||
          threadId.trim().isEmpty ||
          turnId == null ||
          turnId.trim().isEmpty) {
        return null;
      }
      return builderFor(
        threadId,
        record['threadTitle'] as String?,
      ).turnBuilder(turnId);
    }

    for (final record in records) {
      switch (record['kind']) {
        case 'turn':
          final builder = turnBuilderFor(record);
          if (builder == null) continue;
          builder.mergeTurnRecord(record);
          break;
        case 'turn_event':
          final builder = turnBuilderFor(record);
          final eventJson = record['event'];
          if (builder == null || eventJson is! Map<String, dynamic>) continue;
          final event = StudioTurnEvent.fromJson(eventJson);
          if (event != null) builder.events[event.id] = event;
          break;
        case 'approval':
          final builder = turnBuilderFor(record);
          if (builder == null) continue;
          builder.mergeApprovalRecord(record);
          break;
        case 'turn_step':
          final builder = turnBuilderFor(record);
          final stepJson = record['step'];
          if (builder == null || stepJson is! Map<String, dynamic>) continue;
          final step = TurnStepRecord.fromJson(stepJson);
          if (step != null) builder.steps[step.step] = step;
          break;
        case 'tool_result':
          final builder = turnBuilderFor(record);
          final resultJson = record['result'];
          if (builder == null || resultJson is! Map<String, dynamic>) continue;
          final result = ToolResultEnvelope.fromJson(resultJson);
          builder.toolResults[result.toolCallId] = result;
          break;
        case 'patch_transaction':
          final builder = turnBuilderFor(record);
          if (builder == null) continue;
          builder.mergePatchTransactionRecord(record);
          break;
        case 'command_run':
          final builder = turnBuilderFor(record);
          if (builder == null) continue;
          builder.mergeCommandRunRecord(record);
          break;
        case 'provider_diagnostic':
          final builder = turnBuilderFor(record);
          final diagnosticJson = record['diagnostic'];
          if (builder == null || diagnosticJson is! Map<String, dynamic>) {
            continue;
          }
          final diagnostic = ProviderLifecycleEvent.fromJson(diagnosticJson);
          if (diagnostic != null) {
            builder.providerDiagnostics.add(diagnostic);
          }
          break;
        case 'accepted_plan':
          final builder = turnBuilderFor(record);
          if (builder == null) continue;
          builder.mergeAcceptedPlanRecord(
            acceptedPlanContext: _acceptedPlanFromJournalRecord(record),
            acceptedPlanState: _acceptedPlanStateFromName(
              record['acceptedPlanState'] as String?,
            ),
            updatedAt: DateTime.tryParse(record['updatedAt'] as String? ?? ''),
          );
          break;
        case 'plan_target':
          final builder = turnBuilderFor(record);
          if (builder == null) continue;
          final target = _planTargetFromJournalRecord(record);
          if (target != null) builder.planTargetProgress[target.path] = target;
          break;
        case 'context_retrieval':
          final builder = turnBuilderFor(record);
          if (builder == null) continue;
          builder.contextRetrieval = _contextRetrievalFromJournalRecord(record);
          break;
      }
    }

    final restored =
        builders.values
            .map((builder) => builder.build(_normalizeLoadedTurn))
            .whereType<StudioThread>()
            .map(_normalizeLoadedThread)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return restored;
  }

  AcceptedPlanContext? _acceptedPlanFromJournalRecord(
    Map<String, dynamic> record,
  ) {
    final patchSetId = record['patchSetId'] as String? ?? '';
    if (patchSetId.trim().isEmpty) return null;
    final plannedFiles =
        (record['plannedFiles'] as List<dynamic>?)?.cast<String>() ??
        const <String>[];
    final plannedTargets = (record['plannedTargets'] as List<dynamic>?)
        ?.whereType<Map<String, dynamic>>()
        .map(PlannedFileTarget.fromJson)
        .whereType<PlannedFileTarget>()
        .where((target) => target.path.trim().isNotEmpty)
        .toList(growable: false);
    return AcceptedPlanContext(
      patchSetId: patchSetId,
      title: record['title'] as String? ?? 'Accepted plan',
      summary: record['summary'] as String? ?? '',
      markdown:
          record['markdown'] as String? ?? record['summary'] as String? ?? '',
      plannedFiles: plannedFiles,
      plannedTargets:
          plannedTargets ??
          [
            for (final file in plannedFiles)
              PlannedFileTarget.fromDisplayString(file),
          ],
      verificationRequested: record['verificationRequested'] as bool? ?? false,
    );
  }

  AcceptedPlanState _acceptedPlanStateFromName(String? name) {
    return AcceptedPlanState.values.firstWhere(
      (candidate) => candidate.name == name,
      orElse: () => AcceptedPlanState.none,
    );
  }

  PlanTargetProgress? _planTargetFromJournalRecord(
    Map<String, dynamic> record,
  ) {
    final path = record['path'] as String? ?? '';
    if (path.trim().isEmpty) return null;
    final operationName = record['operation'] as String?;
    final stateName = record['state'] as String?;
    return PlanTargetProgress(
      path: path,
      intent: record['intent'] as String? ?? '',
      operation: operationName == null
          ? null
          : ProposedFileEditType.values.firstWhere(
              (candidate) => candidate.name == operationName,
              orElse: () => ProposedFileEditType.modify,
            ),
      state: PlanTargetProgressState.values.firstWhere(
        (candidate) => candidate.name == stateName,
        orElse: () => PlanTargetProgressState.pending,
      ),
      patchSetId: record['patchSetId'] as String?,
      detail: record['detail'] as String?,
      updatedAt:
          DateTime.tryParse(record['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  ContextRetrievalResult? _contextRetrievalFromJournalRecord(
    Map<String, dynamic> record,
  ) {
    final budgetJson = record['budget'];
    if (budgetJson is! Map<String, dynamic>) return null;
    final included = _contextCandidatesFromJournal(
      record['included'],
      included: true,
    );
    final omitted = _contextCandidatesFromJournal(
      record['omitted'],
      included: false,
    );
    final warnings =
        (record['warnings'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(ContextPackWarning.fromJson)
            .toList(growable: false) ??
        const <ContextPackWarning>[];
    return ContextRetrievalResult(
      rankedCandidates: [...included, ...omitted]
        ..sort((a, b) => b.score.compareTo(a.score)),
      budget: ContextBudgetReport.fromJson(budgetJson),
      warnings: warnings,
    );
  }

  List<ContextCandidate> _contextCandidatesFromJournal(
    Object? raw, {
    required bool included,
  }) {
    return (raw as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (record) => ContextCandidate(
            id: record['id'] as String? ?? '',
            title: record['title'] as String? ?? '',
            path: record['path'] as String?,
            sourceKind: ContextPackSourceKind.values.firstWhere(
              (candidate) => candidate.name == record['sourceKind'],
              orElse: () => ContextPackSourceKind.projectProfile,
            ),
            score: record['score'] as int? ?? 0,
            estimatedTokens: record['estimatedTokens'] as int? ?? 0,
            included: included,
            reason: record['reason'] as String? ?? '',
          ),
        )
        .toList(growable: false);
  }

  StudioThread _normalizeLoadedThread(StudioThread thread) {
    final normalizedTurns =
        (thread.turns.isEmpty && thread.messages.isNotEmpty
                ? _turnsFromLegacyMessages(thread)
                : thread.turns)
            .map(_normalizeLoadedTurn)
            .toList();
    var normalized = thread.copyWith(
      messages: normalizedTurns.isNotEmpty
          ? const <StudioThreadMessage>[]
          : thread.messages,
      turns: normalizedTurns,
      updatedAt: thread.updatedAt,
    );
    final latestTurn = normalizedTurns.fold<StudioTurn?>(
      null,
      (latest, turn) =>
          latest == null || turn.createdAt.isAfter(latest.createdAt)
          ? turn
          : latest,
    );
    final recoveredStatus = switch (latestTurn?.status) {
      StudioTurnStatus.completed => _completedThreadStatusForTurns(
        normalizedTurns,
        latestTurn!,
      ),
      StudioTurnStatus.failed => StudioThreadStatus.failed,
      StudioTurnStatus.cancelled => StudioThreadStatus.cancelled,
      StudioTurnStatus.interrupted => StudioThreadStatus.failed,
      _ => null,
    };
    if (recoveredStatus != null) {
      return normalized.copyWith(
        status: recoveredStatus,
        phase: _phaseForRecoveredStatus(recoveredStatus),
        requestId: null,
        streamingContent: '',
        lastError: recoveredStatus == StudioThreadStatus.failed
            ? (latestTurn?.lastError ?? normalized.lastError)
            : null,
        updatedAt: normalized.updatedAt,
      );
    }

    if (!_isLoadedActiveThread(normalized.status)) {
      return _normalizeInactiveLoadedThread(normalized);
    }

    const message = 'Interrupted while CircuitCode was closed.';
    return normalized.copyWith(
      status: StudioThreadStatus.failed,
      phase: StudioSendPhase.failed,
      requestId: null,
      streamingContent: '',
      lastError: normalized.lastError ?? message,
      updatedAt: normalized.updatedAt,
    );
  }

  List<StudioTurn> _turnsFromLegacyMessages(StudioThread thread) {
    final messages =
        thread.messages
            .where((message) => message.content.trim().isNotEmpty)
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final turns = <StudioTurn>[];
    var index = 0;
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (message.role != MessageRole.user) continue;
      final assistantMessages = <StudioThreadMessage>[];
      var cursor = i + 1;
      while (cursor < messages.length &&
          messages[cursor].role != MessageRole.user) {
        if (messages[cursor].role == MessageRole.assistant &&
            messages[cursor].content.trim().isNotEmpty) {
          assistantMessages.add(messages[cursor]);
        }
        cursor++;
      }
      final assistantContent = assistantMessages
          .map((assistant) => assistant.content.trim())
          .where((content) => content.isNotEmpty)
          .join('\n\n');
      final requestId = 'legacy-request-${thread.id}-${index + 1}';
      final turnId = 'legacy-turn-${thread.id}-${index + 1}';
      final createdAt = message.timestamp;
      final completedAt = assistantMessages.isEmpty
          ? null
          : assistantMessages.last.timestamp;
      turns.add(
        StudioTurn(
          id: turnId,
          threadId: thread.id,
          requestId: requestId,
          userMessageId: message.id,
          prompt: message.content,
          model: thread.model ?? 'gpt-5-nano',
          contextSummary:
              thread.contextSummary ??
              const StudioContextSummary(projectLabel: 'Migrated history'),
          status: assistantContent.isEmpty
              ? StudioTurnStatus.failed
              : StudioTurnStatus.completed,
          events: [
            StudioTurnEvent.userMessage(
              id: 'legacy-user-${message.id}',
              turnId: turnId,
              requestId: requestId,
              threadId: thread.id,
              content: message.content,
              timestamp: createdAt,
            ),
            if (assistantContent.isNotEmpty)
              StudioTurnEvent.assistantMessage(
                turnId: turnId,
                requestId: requestId,
                threadId: thread.id,
                content: assistantContent,
                timestamp: completedAt,
              )
            else
              StudioTurnEvent.error(
                turnId: turnId,
                requestId: requestId,
                threadId: thread.id,
                detail: 'This saved message did not have an assistant reply.',
                timestamp: createdAt,
              ),
          ],
          createdAt: createdAt,
          updatedAt: completedAt ?? createdAt,
          completedAt: completedAt,
          lastError: assistantContent.isEmpty
              ? 'This saved message did not have an assistant reply.'
              : null,
        ),
      );
      index++;
      i = cursor - 1;
    }
    return turns;
  }

  StudioSendPhase _phaseForRecoveredStatus(StudioThreadStatus status) {
    return switch (status) {
      StudioThreadStatus.done ||
      StudioThreadStatus.continuationReady ||
      StudioThreadStatus.reviewingPatch => StudioSendPhase.completed,
      StudioThreadStatus.cancelled => StudioSendPhase.cancelled,
      StudioThreadStatus.failed => StudioSendPhase.failed,
      _ => StudioSendPhase.idle,
    };
  }

  StudioThreadStatus _completedThreadStatusForTurn(StudioTurn turn) {
    final hasQueuedContinuation = turn.steps.any(
      (step) =>
          step.step == TurnStep.continuation &&
          step.status == TurnStepStatus.queued,
    );
    if (_turnHasAcceptedPlanConflict(turn)) {
      return StudioThreadStatus.reviewingPatch;
    }
    if (hasQueuedContinuation) return StudioThreadStatus.continuationReady;
    if (_turnHasRemainingAcceptedPlanTargets(turn)) {
      return StudioThreadStatus.continuationReady;
    }
    if (_turnHasLegacyAcceptedPlanContinuation(turn)) {
      return StudioThreadStatus.continuationReady;
    }
    if (_turnHasActionablePatchReview(turn)) {
      return StudioThreadStatus.reviewingPatch;
    }
    return StudioThreadStatus.done;
  }

  StudioThreadStatus _completedThreadStatusForTurns(
    List<StudioTurn> turns,
    StudioTurn latestTurn,
  ) {
    if (turns.any(
      (turn) =>
          turn.status == StudioTurnStatus.completed &&
          _turnHasAcceptedPlanConflict(turn),
    )) {
      return StudioThreadStatus.reviewingPatch;
    }
    if (turns.any(
      (turn) =>
          turn.status == StudioTurnStatus.completed &&
          (_turnHasRemainingAcceptedPlanTargets(turn) ||
              _turnHasLegacyAcceptedPlanContinuation(turn) ||
              turn.steps.any(
                (step) =>
                    step.step == TurnStep.continuation &&
                    step.status == TurnStepStatus.queued,
              )),
    )) {
      return StudioThreadStatus.continuationReady;
    }
    if (turns.any(
      (turn) =>
          turn.status == StudioTurnStatus.completed &&
          _turnHasActionablePatchReview(turn),
    )) {
      return StudioThreadStatus.reviewingPatch;
    }
    return _completedThreadStatusForTurn(latestTurn);
  }

  bool _turnHasAcceptedPlanConflict(StudioTurn turn) {
    if (turn.acceptedPlanContext == null) return false;
    if (turn.planTargetProgress.any(
      (target) => target.state == PlanTargetProgressState.conflict,
    )) {
      return true;
    }
    return turn.events.any((event) {
      if (event.type != StudioTurnEventType.completionSummary) return false;
      return event.title.toLowerCase().contains('patch conflict');
    });
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

  bool _turnHasLegacyAcceptedPlanContinuation(StudioTurn turn) {
    if (turn.acceptedPlanContext == null ||
        turn.acceptedPlanState != AcceptedPlanState.patchProposed) {
      return false;
    }
    if (turn.toolResults.any((result) => result.changedFiles.isNotEmpty)) {
      return true;
    }
    return turn.events.any((event) {
      if (event.type != StudioTurnEventType.completionSummary) return false;
      return event.title.toLowerCase() == 'applied changes' &&
          event.detail.toLowerCase().contains('applied ');
    });
  }

  bool _turnHasActionablePatchReview(StudioTurn turn) {
    if (turn.intent == TurnIntent.plan) return false;
    final hasAppliedPatchSummary = turn.events.any((event) {
      if (event.type != StudioTurnEventType.completionSummary) return false;
      return event.title.toLowerCase() == 'applied changes';
    });
    if (turn.acceptedPlanState == AcceptedPlanState.patchProposed &&
        !hasAppliedPatchSummary) {
      return true;
    }
    return turn.events.any((event) {
      if (event.type != StudioTurnEventType.completionSummary) return false;
      final title = event.title.toLowerCase();
      if (title == 'applied changes') return false;
      if (hasAppliedPatchSummary &&
          (title.contains('prepared changes') ||
              title.contains('patch ready'))) {
        return false;
      }
      return title.contains('prepared changes') ||
          title.contains('patch conflict') ||
          title.contains('patch revision requested');
    });
  }

  StudioThread _normalizeInactiveLoadedThread(StudioThread thread) {
    if (thread.requestId == null &&
        thread.streamingContent.isEmpty &&
        !(_isActionableTerminalStatus(thread.status) &&
            thread.lastError != null)) {
      return thread;
    }
    return thread.copyWith(
      requestId: null,
      streamingContent: '',
      lastError: _isActionableTerminalStatus(thread.status)
          ? null
          : thread.lastError,
      updatedAt: thread.updatedAt,
    );
  }

  bool _isActionableTerminalStatus(StudioThreadStatus status) {
    return status == StudioThreadStatus.done ||
        status == StudioThreadStatus.continuationReady ||
        status == StudioThreadStatus.reviewingPatch;
  }

  StudioTurn _normalizeLoadedTurn(StudioTurn turn) {
    final normalized = !_isLoadedActiveTurn(turn.status)
        ? turn
        : _recoverableInterruptedTurn(turn) ??
              turn.expirePendingApprovals().copyWith(
                status: StudioTurnStatus.interrupted,
                assistantDraft: '',
                completedAt: DateTime.now(),
                lastError:
                    turn.lastError ??
                    'Interrupted while CircuitCode was closed.',
                acceptedPlanState: _normalizeInterruptedAcceptedPlanState(
                  turn.acceptedPlanState,
                ),
                planTargetProgress: _normalizeInterruptedPlanTargets(
                  turn.planTargetProgress,
                ),
                steps: _normalizeInterruptedSteps(turn.steps),
              );
    return normalized.finalOutcome == null
        ? normalized.copyWith(finalOutcome: inferStudioTurnOutcome(normalized))
        : normalized;
  }

  StudioTurn? _recoverableInterruptedTurn(StudioTurn turn) {
    final expired = turn.expirePendingApprovals();
    final hasActionablePatch = _turnHasActionablePatchReview(expired);
    final hasContinuation = _turnHasRemainingAcceptedPlanTargets(expired);
    final hasConflict = _turnHasAcceptedPlanConflict(expired);
    if (!hasActionablePatch && !hasContinuation && !hasConflict) return null;

    return expired.copyWith(
      status: StudioTurnStatus.completed,
      assistantDraft: '',
      completedAt: expired.completedAt ?? DateTime.now(),
      lastError: null,
      acceptedPlanState: expired.acceptedPlanState == AcceptedPlanState.none
          ? AcceptedPlanState.none
          : AcceptedPlanState.patchProposed,
      steps: _normalizeInterruptedReviewSteps(expired.steps),
    );
  }

  List<TurnStepRecord> _normalizeInterruptedReviewSteps(
    List<TurnStepRecord> steps,
  ) {
    final now = DateTime.now();
    return [
      for (final step in steps)
        switch (step.status) {
          TurnStepStatus.queued || TurnStepStatus.running => step.copyWith(
            status: TurnStepStatus.completed,
            completedAt: step.completedAt ?? now,
            detail: step.detail.trim().isEmpty
                ? 'Recovered reviewable output after CircuitCode reopened.'
                : '${step.detail}\nRecovered reviewable output after CircuitCode reopened.',
          ),
          TurnStepStatus.completed ||
          TurnStepStatus.failed ||
          TurnStepStatus.skipped => step,
        },
    ];
  }

  AcceptedPlanState _normalizeInterruptedAcceptedPlanState(
    AcceptedPlanState state,
  ) {
    return switch (state) {
      AcceptedPlanState.none => AcceptedPlanState.none,
      AcceptedPlanState.implemented => AcceptedPlanState.implemented,
      _ => AcceptedPlanState.failed,
    };
  }

  List<PlanTargetProgress> _normalizeInterruptedPlanTargets(
    List<PlanTargetProgress> targets,
  ) {
    return [
      for (final target in targets)
        switch (target.state) {
          PlanTargetProgressState.applied ||
          PlanTargetProgressState.conflict ||
          PlanTargetProgressState.skipped => target,
          _ => target.copyWith(
            state: PlanTargetProgressState.blocked,
            detail: 'Interrupted while CircuitCode was closed.',
          ),
        },
    ];
  }

  List<TurnStepRecord> _normalizeInterruptedSteps(List<TurnStepRecord> steps) {
    final now = DateTime.now();
    final normalized = [
      for (final step in steps)
        switch (step.status) {
          TurnStepStatus.queued || TurnStepStatus.running => step.copyWith(
            status: TurnStepStatus.failed,
            completedAt: step.completedAt ?? now,
            detail: step.detail.trim().isEmpty
                ? 'Interrupted while CircuitCode was closed.'
                : '${step.detail}\nInterrupted while CircuitCode was closed.',
          ),
          TurnStepStatus.completed ||
          TurnStepStatus.failed ||
          TurnStepStatus.skipped => step,
        },
    ];
    if (!normalized.any((step) => step.step == TurnStep.finalSummary)) {
      normalized.add(
        TurnStepRecord(
          step: TurnStep.finalSummary,
          status: TurnStepStatus.failed,
          title: 'Turn interrupted',
          detail: 'Interrupted while CircuitCode was closed.',
          startedAt: now,
          completedAt: now,
        ),
      );
    }
    return normalized;
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
      StudioThreadStatus.continuationReady ||
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
      StudioTurnStatus.waitingForApproval ||
      StudioTurnStatus.verifying => true,
      StudioTurnStatus.reviewingPatch => false,
      StudioTurnStatus.completed ||
      StudioTurnStatus.failed ||
      StudioTurnStatus.cancelled ||
      StudioTurnStatus.interrupted => false,
    };
  }
}
