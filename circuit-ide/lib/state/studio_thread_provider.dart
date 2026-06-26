import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/utils/platform_utils.dart';
import '../enums/message_role.dart';
import '../models/accepted_plan_context.dart';
import '../models/agent_preflight.dart';
import '../models/context_pack.dart';
import '../models/provider_lifecycle_event.dart';
import '../models/reviewed_edit.dart';
import '../models/studio_source_artifact.dart';
import '../models/studio_thread.dart';
import '../models/studio_turn.dart';
import '../models/tool_result_envelope.dart';
import '../models/token_usage.dart';
import '../models/turn_intent.dart';
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

  StudioThread? threadForTaskView(String? taskId) {
    if (taskId != null) return threadForTask(taskId);
    return selectedThread;
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

  String journalPath(String? rootPath) {
    return p.join(
      baseDir,
      '${WorkItemStore.projectKey(rootPath)}.journal.jsonl',
    );
  }

  Future<List<StudioThread>> load(String? rootPath) async {
    final file = File(historyPath(rootPath));
    if (!await file.exists()) return _loadFromJournalSnapshots(rootPath);
    try {
      final json = jsonDecode(await file.readAsString()) as List<dynamic>;
      return json
          .whereType<Map<String, dynamic>>()
          .map(StudioThread.fromJson)
          .nonNulls
          .map(_normalizeLoadedThread)
          .toList();
    } catch (_) {
      final recovered = await _loadFromJournalSnapshots(rootPath);
      if (recovered.isNotEmpty) return recovered;
      rethrow;
    }
  }

  Future<List<StudioThread>> _loadFromJournalSnapshots(String? rootPath) async {
    final file = File(journalPath(rootPath));
    if (!await file.exists()) return const [];
    final snapshots = <String, StudioThread>{};
    final snapshotTimes = <String, DateTime>{};
    final lines = await file.readAsLines();
    final decodedRecords = <Map<String, dynamic>>[];
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final decoded = _decodeJournalLine(line);
      if (decoded == null) continue;
      decodedRecords.add(decoded);
      if (decoded['kind'] != 'thread_snapshot') continue;
      final threadJson = decoded['thread'];
      if (threadJson is! Map<String, dynamic>) continue;
      final thread = StudioThread.fromJson(threadJson);
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
    return _loadFromJournalRecords(decodedRecords);
  }

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

  Map<String, dynamic>? _decodeJournalLine(String line) {
    try {
      final decoded = jsonDecode(line);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
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
    if (!_isLoadedActiveTurn(turn.status)) return turn;
    final recoverable = _recoverableInterruptedTurn(turn);
    if (recoverable != null) return recoverable;
    return turn.expirePendingApprovals().copyWith(
      status: StudioTurnStatus.failed,
      assistantDraft: '',
      completedAt: DateTime.now(),
      lastError: turn.lastError ?? 'Interrupted while CircuitCode was closed.',
      acceptedPlanState: _normalizeInterruptedAcceptedPlanState(
        turn.acceptedPlanState,
      ),
      planTargetProgress: _normalizeInterruptedPlanTargets(
        turn.planTargetProgress,
      ),
      steps: _normalizeInterruptedSteps(turn.steps),
    );
  }

  StudioTurn? _recoverableInterruptedTurn(StudioTurn turn) {
    final expired = turn.expirePendingApprovals();
    final hasActionablePatch = _turnHasActionablePatchReview(expired);
    final hasContinuation = _turnHasRemainingAcceptedPlanTargets(expired);
    if (!hasActionablePatch && !hasContinuation) return null;

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
      StudioTurnStatus.waitingForApproval => true,
      StudioTurnStatus.completed ||
      StudioTurnStatus.failed ||
      StudioTurnStatus.cancelled => false,
    };
  }

  Future<void> save(String? rootPath, List<StudioThread> threads) async {
    final file = File(historyPath(rootPath));
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    final persistedThreads = threads.map(_threadForPersistence).toList();
    await file.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(persistedThreads.map((thread) => thread.toJson()).toList()),
    );
    await _writeJournal(rootPath, persistedThreads);
  }

  StudioThread _threadForPersistence(StudioThread thread) {
    if (thread.turns.isEmpty || thread.messages.isEmpty) return thread;
    return thread.copyWith(
      messages: const <StudioThreadMessage>[],
      updatedAt: thread.updatedAt,
    );
  }

  Future<void> _writeJournal(
    String? rootPath,
    List<StudioThread> threads,
  ) async {
    final file = File(journalPath(rootPath));
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    final lines = <String>[];
    for (final thread in threads) {
      lines.add(
        jsonEncode({
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
      );
      for (final turn in thread.turns) {
        lines.add(
          jsonEncode({
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
          }),
        );
        final contextRecord = _contextRetrievalJournalRecord(
          thread: thread,
          turn: turn,
        );
        if (contextRecord != null) {
          lines.add(jsonEncode(contextRecord));
        }
        for (final step in turn.steps) {
          lines.add(
            jsonEncode({
              'kind': 'turn_step',
              'threadId': thread.id,
              'threadTitle': thread.title,
              'turnId': turn.id,
              'requestId': turn.requestId,
              if (turn.taskId != null) 'taskId': turn.taskId,
              'intent': turn.intent.name,
              'step': step.toJson(),
            }),
          );
        }
        final acceptedPlanRecord = _acceptedPlanJournalRecord(
          thread: thread,
          turn: turn,
        );
        if (acceptedPlanRecord != null) {
          lines.add(jsonEncode(acceptedPlanRecord));
        }
        for (final planTargetRecord in _planTargetJournalRecords(
          thread: thread,
          turn: turn,
        )) {
          lines.add(jsonEncode(planTargetRecord));
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
          lines.add(
            jsonEncode({
              'kind': 'turn_event',
              'threadId': thread.id,
              'turnId': turn.id,
              'requestId': turn.requestId,
              'event': event.toJson(),
            }),
          );
          final approvalRecord = _approvalJournalRecord(
            thread: thread,
            turn: turn,
            event: event,
          );
          if (approvalRecord != null) {
            lines.add(jsonEncode(approvalRecord));
          }
          final patchTransactionRecord = _patchTransactionJournalRecord(
            thread: thread,
            turn: turn,
            event: event,
          );
          if (patchTransactionRecord != null) {
            lines.add(jsonEncode(patchTransactionRecord));
          }
          final commandRunRecord = _commandRunJournalRecordFromEvent(
            thread: thread,
            turn: turn,
            event: event,
            structuredCommandResultIds: structuredCommandResultIds,
            structuredCommandResultCommands: structuredCommandResultCommands,
          );
          if (commandRunRecord != null) {
            lines.add(jsonEncode(commandRunRecord));
          }
        }
        for (final result in turn.toolResults) {
          lines.add(
            jsonEncode({
              'kind': 'tool_result',
              'threadId': thread.id,
              'turnId': turn.id,
              'requestId': turn.requestId,
              'result': result.toJson(),
            }),
          );
          final commandRunRecord = _commandRunJournalRecord(
            thread: thread,
            turn: turn,
            result: result,
          );
          if (commandRunRecord != null) {
            lines.add(jsonEncode(commandRunRecord));
          }
        }
        for (final diagnostic in turn.providerDiagnostics) {
          lines.add(
            jsonEncode({
              'kind': 'provider_diagnostic',
              'threadId': thread.id,
              'turnId': turn.id,
              'requestId': turn.requestId,
              'diagnostic': diagnostic.toJson(),
            }),
          );
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
  }

  Future<Set<String>> _existingJournalLines(File file) async {
    if (!await file.exists()) return <String>{};
    final lines = await file.readAsLines();
    return lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toSet();
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
      if (detail.trim().isNotEmpty) 'diagnostic': detail,
      if (detail.trim().isNotEmpty) 'stdout': detail,
      'createdAt': event.timestamp.toIso8601String(),
    };
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

class StudioThreadController extends Notifier<StudioThreadState> {
  final _store = StudioThreadStore();
  String? _loadedRootPath;

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
      final threads = await _store.load(targetRootPath);
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
      );
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
    ];
    _upsert(thread.copyWith(sourceArtifacts: artifacts), select: false);
  }

  void upsertTurn(String threadId, StudioTurn turn, {bool select = false}) {
    final thread = _find(threadId);
    if (thread == null) return;
    final turns = [
      turn,
      ...thread.turns.where((candidate) => candidate.id != turn.id),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final updatedThread = switch (turn.status) {
      StudioTurnStatus.completed when turn.completedAt != null =>
        thread.copyWith(
          turns: turns,
          status: _completedThreadStatusForTurn(turn),
          phase: StudioSendPhase.completed,
          streamingContent: '',
          requestId: null,
          lastError: null,
        ),
      StudioTurnStatus.failed when turn.completedAt != null => thread.copyWith(
        turns: turns,
        status: StudioThreadStatus.failed,
        phase: StudioSendPhase.failed,
        streamingContent: '',
        requestId: null,
        lastError: turn.lastError ?? thread.lastError,
      ),
      StudioTurnStatus.cancelled when turn.completedAt != null =>
        thread.copyWith(
          turns: turns,
          status: StudioThreadStatus.cancelled,
          phase: StudioSendPhase.cancelled,
          streamingContent: '',
          requestId: null,
          lastError: null,
        ),
      _ => thread.copyWith(turns: turns),
    };
    _upsert(updatedThread, select: select);
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

  void updateTurn(
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
              steps: steps,
              toolResults: toolResults,
              providerDiagnostics: providerDiagnostics,
              acceptedPlanState: acceptedPlanState,
              acceptedPlanContext: acceptedPlanContext,
              planTargetProgress: planTargetProgress,
              contextRetrieval: contextRetrieval,
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
    await _store.save(ref.read(fileTreeProvider).rootPath, threads);
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
        (_isInternalPrompt(turn.prompt) ? null : turn.prompt);
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
    final events = turn.events.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final outcome = events
        .where(
          (event) =>
              event.type == StudioTurnEventType.assistantMessage ||
              event.type == StudioTurnEventType.completionSummary ||
              event.type == StudioTurnEventType.error,
        )
        .firstOrNull;
    final value = (outcome?.content ?? outcome?.detail ?? outcome?.title ?? '')
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
      StudioTurnStatus.waitingForApproval => true,
      StudioTurnStatus.completed ||
      StudioTurnStatus.failed ||
      StudioTurnStatus.cancelled => false,
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
      StudioTurnStatus.completed => StudioThreadStatus.done,
      StudioTurnStatus.failed => StudioThreadStatus.failed,
      StudioTurnStatus.cancelled => StudioThreadStatus.cancelled,
    };
  }

  StudioSendPhase _threadPhaseFromTurn(StudioTurn turn) {
    return switch (turn.status) {
      StudioTurnStatus.queued ||
      StudioTurnStatus.buildingContext => StudioSendPhase.buildingContext,
      StudioTurnStatus.sent ||
      StudioTurnStatus.waitingForModel => StudioSendPhase.sent,
      StudioTurnStatus.streaming ||
      StudioTurnStatus.toolRunning => StudioSendPhase.streaming,
      StudioTurnStatus.waitingForApproval => StudioSendPhase.waitingForApproval,
      StudioTurnStatus.completed => StudioSendPhase.completed,
      StudioTurnStatus.failed => StudioSendPhase.failed,
      StudioTurnStatus.cancelled => StudioSendPhase.cancelled,
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
    final detail = [
      if ((record['command'] as String?)?.trim().isNotEmpty == true)
        'Command: ${(record['command'] as String).trim()}',
      if (record['exitCode'] != null) 'Exit code: ${record['exitCode']}',
      if ((record['stdout'] as String?)?.trim().isNotEmpty == true)
        (record['stdout'] as String).trim(),
      if ((record['stderr'] as String?)?.trim().isNotEmpty == true)
        (record['stderr'] as String).trim(),
      if ((record['diagnostic'] as String?)?.trim().isNotEmpty == true)
        (record['diagnostic'] as String).trim(),
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
