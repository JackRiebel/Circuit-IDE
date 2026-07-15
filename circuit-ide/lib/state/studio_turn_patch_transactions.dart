part of 'studio_turn_provider.dart';

mixin StudioTurnPatchTransactions on Notifier<StudioTurnState> {
  void recordStep(
    String requestId, {
    required TurnStep step,
    required TurnStepStatus status,
    required String title,
    String detail = '',
    bool allowArchived = false,
  });
  void setAcceptedPlanState(
    String requestId,
    AcceptedPlanState acceptedPlanState,
  ) {
    final turnRef = state.refForRequest(requestId);
    if (turnRef == null) return;
    ref
        .read(studioThreadProvider.notifier)
        .updateTurn(
          turnRef.threadId,
          turnRef.turnId,
          acceptedPlanState: acceptedPlanState,
        );
  }

  void startAcceptedPlanImplementation(
    String requestId,
    AcceptedPlanContext acceptedPlan,
  ) {
    final turnRef = state.refForRequest(requestId);
    if (turnRef == null) return;
    final thread = ref
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == turnRef.threadId)
        .firstOrNull;
    final turn = thread?.turns
        .where((candidate) => candidate.id == turnRef.turnId)
        .firstOrNull;
    if (turn == null) return;
    ref
        .read(studioThreadProvider.notifier)
        .updateTurn(
          turnRef.threadId,
          turnRef.turnId,
          acceptedPlanState: AcceptedPlanState.implementationStarted,
          acceptedPlanContext: turn.acceptedPlanContext ?? acceptedPlan,
          planTargetProgress: turn.planTargetProgress.isEmpty
              ? _planTargetProgressFor(acceptedPlan)
              : turn.planTargetProgress,
        );
  }

  void updatePlanTargetProgress(
    String requestId, {
    required String patchSetId,
    required Iterable<String> paths,
    required PlanTargetProgressState targetState,
    String? detail,
  }) {
    final turnRef = state.archivedRefForRequest(requestId);
    if (turnRef == null) return;
    final thread = ref
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == turnRef.threadId)
        .firstOrNull;
    final turn = thread?.turns
        .where((candidate) => candidate.id == turnRef.turnId)
        .firstOrNull;
    if (turn == null || turn.planTargetProgress.isEmpty) return;
    final normalizedPaths = {for (final path in paths) _normalizePlanPath(path)}
      ..remove('');
    if (normalizedPaths.isEmpty) return;
    final updatedTargets = [
      for (final target in turn.planTargetProgress)
        if (_planTargetMatchesAnyPath(target.path, normalizedPaths))
          target.copyWith(
            state: targetState,
            patchSetId: patchSetId,
            detail: detail,
          )
        else
          target,
    ];
    ref
        .read(studioThreadProvider.notifier)
        .updateTurn(
          turnRef.threadId,
          turnRef.turnId,
          planTargetProgress: updatedTargets,
        );
  }

  void recordPatchTransaction(
    String requestId, {
    required String patchSetId,
    required String title,
    required String detail,
    Iterable<String> paths = const [],
    PatchApplyStatus? applyStatus,
  }) {
    final turnRef = state.archivedRefForRequest(requestId);
    if (turnRef == null) return;
    final actionableDetail = applyStatus == PatchApplyStatus.conflict
        ? _patchConflictRecoveryDetail(detail)
        : detail;
    recordStep(
      requestId,
      step: TurnStep.patchProposal,
      status: switch (applyStatus) {
        PatchApplyStatus.applied => TurnStepStatus.completed,
        PatchApplyStatus.revisionRequested => TurnStepStatus.queued,
        PatchApplyStatus.conflict ||
        PatchApplyStatus.failed ||
        PatchApplyStatus.rejected => TurnStepStatus.failed,
        PatchApplyStatus.restored => TurnStepStatus.completed,
        null => TurnStepStatus.running,
      },
      title: title,
      detail: actionableDetail,
      allowArchived: true,
    );
    if (applyStatus == PatchApplyStatus.applied &&
        _patchTransactionRequestsVerification(actionableDetail)) {
      recordStep(
        requestId,
        step: TurnStep.verification,
        status: TurnStepStatus.queued,
        title: 'Verification ready',
        detail: _verificationStepDetail(actionableDetail),
        allowArchived: true,
      );
    }
    final thread = ref
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == turnRef.threadId)
        .firstOrNull;
    final turn = thread?.turns
        .where((candidate) => candidate.id == turnRef.turnId)
        .firstOrNull;
    final touchedPaths = paths.isNotEmpty
        ? paths.map(_normalizePlanPath).where((path) => path.isNotEmpty)
        : _pathsFromPatchTransactionDetail(detail);
    final isRevisionTransaction = _isPatchRevisionTransaction(
      title,
      applyStatus,
    );
    final progressState = isRevisionTransaction
        ? PlanTargetProgressState.proposed
        : switch (applyStatus) {
            PatchApplyStatus.applied => PlanTargetProgressState.applied,
            PatchApplyStatus.conflict => PlanTargetProgressState.conflict,
            PatchApplyStatus.failed => PlanTargetProgressState.blocked,
            PatchApplyStatus.rejected => PlanTargetProgressState.skipped,
            PatchApplyStatus.revisionRequested =>
              PlanTargetProgressState.proposed,
            PatchApplyStatus.restored => PlanTargetProgressState.proposed,
            null => null,
          };
    if (turn != null) {
      if (progressState != null && touchedPaths.isNotEmpty) {
        updatePlanTargetProgress(
          requestId,
          patchSetId: patchSetId,
          paths: touchedPaths,
          targetState: progressState,
          detail: title,
        );
        _propagateContinuationTargetProgress(
          threadId: turnRef.threadId,
          sourceTurnId: turnRef.turnId,
          continuationPlanId: turn.acceptedPlanContext?.patchSetId,
          patchSetId: patchSetId,
          paths: touchedPaths,
          targetState: progressState,
          detail: title,
        );
      }
    }
    final latestThread = ref
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == turnRef.threadId)
        .firstOrNull;
    final latestTurn = latestThread?.turns
        .where((candidate) => candidate.id == turnRef.turnId)
        .firstOrNull;
    if (applyStatus == PatchApplyStatus.applied) {
      final continuationDetail = _continuationStepDetail(latestTurn ?? turn);
      if (continuationDetail != null) {
        recordStep(
          requestId,
          step: TurnStep.continuation,
          status: TurnStepStatus.queued,
          title: 'Continue next batch',
          detail: continuationDetail,
          allowArchived: true,
        );
      }
    }
    final acceptedPlanState = _acceptedPlanStateForPatchApply(
      latestTurn ?? turn,
      applyStatus,
      title: title,
    );
    if (acceptedPlanState != null) {
      final notifier = ref.read(studioThreadProvider.notifier);
      if (acceptedPlanState == AcceptedPlanState.implemented) {
        notifier.updateTurn(
          turnRef.threadId,
          turnRef.turnId,
          acceptedPlanState: acceptedPlanState,
          status: StudioTurnStatus.completed,
          lastError: null,
          complete: true,
          finalOutcome: StudioTurnOutcome.appliedChanges,
        );
      } else {
        final shouldCompleteTurn =
            acceptedPlanState == AcceptedPlanState.patchProposed;
        if (shouldCompleteTurn) {
          notifier.updateTurn(
            turnRef.threadId,
            turnRef.turnId,
            acceptedPlanState: acceptedPlanState,
            status: StudioTurnStatus.completed,
            lastError: null,
            complete: true,
            finalOutcome: StudioTurnOutcome.preparedChanges,
          );
        } else {
          notifier.updateTurn(
            turnRef.threadId,
            turnRef.turnId,
            acceptedPlanState: acceptedPlanState,
          );
        }
      }
    }
    final transactionDetail = _patchTransactionDetailWithPlanProgress(
      latestTurn ?? turn,
      actionableDetail,
      applyStatus,
      touchedPaths: touchedPaths,
    );
    if (applyStatus == PatchApplyStatus.applied) {
      recordStep(
        requestId,
        step: TurnStep.finalSummary,
        status: TurnStepStatus.completed,
        title: 'Patch applied',
        detail: transactionDetail,
        allowArchived: true,
      );
    }
    ref
        .read(studioThreadProvider.notifier)
        .upsertTurnEvent(
          turnRef.threadId,
          turnRef.turnId,
          StudioTurnEvent.completionSummary(
            id: _patchTransactionEventId(
              turnId: turnRef.turnId,
              patchSetId: patchSetId,
              title: title,
              touchedPaths: touchedPaths,
              applyStatus: applyStatus,
            ),
            turnId: turnRef.turnId,
            requestId: requestId,
            threadId: turnRef.threadId,
            title: title,
            detail: transactionDetail,
            patchSetId: patchSetId,
          ),
        );
    if (applyStatus == PatchApplyStatus.applied) {
      ref
          .read(studioThreadProvider.notifier)
          .updateTurn(
            turnRef.threadId,
            turnRef.turnId,
            finalOutcome: StudioTurnOutcome.appliedChanges,
          );
    }
  }

  void recordCommandRunResult(
    String requestId, {
    required String commandRunId,
    required String command,
    required String status,
    String output = '',
    int? exitCode,
  }) {
    final activeTurnRef = state.refForRequest(requestId);
    final archivedTurnRef = state.archivedRefForRequest(requestId);
    final turnRef = activeTurnRef ?? archivedTurnRef;
    if (turnRef == null) return;
    final allowArchived = activeTurnRef == null;
    final statusLabel = status.trim().isEmpty ? 'completed' : status.trim();
    final normalizedStatus = statusLabel.toLowerCase();
    final succeeded =
        normalizedStatus == 'succeeded' ||
        normalizedStatus == 'success' ||
        normalizedStatus == 'completed';
    final title = succeeded ? 'Ran command' : 'Command $statusLabel';
    final trimmedOutput = output.trim();
    final commandLogPath = ref
        .read(studioCommandLogStoreProvider)
        .write(
          requestId: requestId,
          turnId: turnRef.turnId,
          commandRunId: commandRunId,
          command: command,
          status: statusLabel,
          output: output,
          exitCode: exitCode,
        );
    final detail = [
      command.trim().isEmpty ? 'Command completed.' : 'Command: $command',
      if (exitCode != null) 'Exit code: $exitCode',
      if (trimmedOutput.isNotEmpty)
        summarizeCommandOutput(trimmedOutput, commandLogPath),
    ].join('\n');
    final stepStatus = succeeded
        ? TurnStepStatus.completed
        : TurnStepStatus.failed;
    recordStep(
      requestId,
      step: TurnStep.commandRun,
      status: stepStatus,
      title: title,
      detail: detail,
      allowArchived: allowArchived,
    );
    recordStep(
      requestId,
      step: TurnStep.verification,
      status: stepStatus,
      title: title,
      detail: detail,
      allowArchived: allowArchived,
    );
    ref
        .read(studioThreadProvider.notifier)
        .upsertTurnEvent(
          turnRef.threadId,
          turnRef.turnId,
          StudioTurnEvent.completionSummary(
            id: 'command-run-${turnRef.turnId}-$commandRunId',
            turnId: turnRef.turnId,
            requestId: requestId,
            threadId: turnRef.threadId,
            title: title,
            detail: detail,
          ),
        );
    if (succeeded) {
      ref
          .read(studioThreadProvider.notifier)
          .updateTurn(
            turnRef.threadId,
            turnRef.turnId,
            finalOutcome: StudioTurnOutcome.verified,
          );
    }
  }

  String _patchConflictRecoveryDetail(String detail) {
    final normalized = detail.toLowerCase();
    if (normalized.contains('rebase') || normalized.contains('revise')) {
      return detail;
    }
    return [
      detail,
      'Ask Circuit to rebase the proposal against the current file contents before applying again.',
    ].where((line) => line.trim().isNotEmpty).join('\n');
  }

  String _patchTransactionEventId({
    required String turnId,
    required String patchSetId,
    required String title,
    required Iterable<String> touchedPaths,
    required PatchApplyStatus? applyStatus,
  }) {
    final statusPart = applyStatus?.name ?? _stableEventIdPart(title);
    if (applyStatus == PatchApplyStatus.conflict) {
      final pathPart = touchedPaths
          .map(_normalizePlanPath)
          .where((path) => path.isNotEmpty)
          .map(_stableEventIdPart)
          .join('-');
      if (pathPart.isNotEmpty) {
        return 'patch-transaction-$turnId-$statusPart-$pathPart';
      }
    }
    return 'patch-transaction-$turnId-$patchSetId-$statusPart';
  }

  String _patchTransactionDetailWithPlanProgress(
    StudioTurn? turn,
    String detail,
    PatchApplyStatus? applyStatus, {
    Iterable<String> touchedPaths = const [],
  }) {
    if (applyStatus != PatchApplyStatus.applied) {
      return detail;
    }
    final outcomeLines = _patchOutcomeContractLines(turn, detail, touchedPaths);
    if (outcomeLines.isEmpty) return detail;
    return [
      detail,
      '',
      ...outcomeLines,
    ].where((line) => line.trim().isNotEmpty).join('\n');
  }

  List<String> _patchOutcomeContractLines(
    StudioTurn? turn,
    String detail,
    Iterable<String> touchedPaths,
  ) {
    final lines = <String>[];
    final changedFiles = touchedPaths
        .map(_normalizePlanPath)
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (changedFiles.isNotEmpty) {
      lines.add('Changed files: ${changedFiles.join(', ')}');
    }

    final hasAcceptedPlan =
        turn != null &&
        turn.acceptedPlanState != AcceptedPlanState.none &&
        turn.planTargetProgress.isNotEmpty;
    final remaining = hasAcceptedPlan
        ? turn.planTargetProgress
              .where(
                (target) =>
                    target.state == PlanTargetProgressState.pending ||
                    target.state == PlanTargetProgressState.proposed ||
                    target.state == PlanTargetProgressState.conflict ||
                    target.state == PlanTargetProgressState.blocked,
              )
              .toList(growable: false)
        : const <PlanTargetProgress>[];

    if (hasAcceptedPlan) {
      if (remaining.isEmpty) {
        lines.add('Accepted plan progress: all planned targets are complete.');
        lines.add(
          'Remaining plan targets: none. All planned targets are complete.',
        );
      } else {
        lines.add(
          'Next batch: ${_remainingPlanTargetsSummary(remaining)} Use Continue next batch to keep implementing the accepted plan.',
        );
        lines.add(
          'Remaining plan targets: ${_remainingPlanTargetsSummary(remaining)}',
        );
      }
    }

    final verification = _suggestedChecksFromPatchDetail(detail);
    if (verification.isNotEmpty) {
      lines.add('Verification suggestions: ${verification.join(' · ')}');
    } else if (changedFiles.isNotEmpty) {
      lines.add(
        'Verification suggestions: review the changed files and run the relevant project checks.',
      );
    }

    if (remaining.isNotEmpty) {
      lines.add(
        'Next action: continue the next accepted-plan batch for the remaining targets.',
      );
    } else if (verification.isNotEmpty ||
        detail.toLowerCase().contains('verification was requested')) {
      lines.add('Next action: run verification for the applied changes.');
    } else if (changedFiles.isNotEmpty) {
      lines.add(
        'Next action: review the changed files or ask for follow-up changes.',
      );
    }

    return lines;
  }

  String _remainingPlanTargetsSummary(List<PlanTargetProgress> remaining) {
    final preview = remaining
        .take(4)
        .map(
          (target) => '${target.path} (${_planTargetStateLabel(target.state)})',
        )
        .join(', ');
    final hiddenCount = remaining.length > 4 ? remaining.length - 4 : 0;
    final previewText = [
      if (preview.isNotEmpty) preview,
      if (hiddenCount > 0) '+$hiddenCount more',
    ].join(hiddenCount > 0 && preview.isNotEmpty ? ', ' : '');
    return '${_acceptedPlanTargetsNeedWorkLabel(remaining.length)}${previewText.isEmpty ? '' : ' ($previewText)'}.';
  }

  String _planTargetStateLabel(PlanTargetProgressState state) {
    return switch (state) {
      PlanTargetProgressState.pending => 'pending',
      PlanTargetProgressState.proposed => 'proposed',
      PlanTargetProgressState.applied => 'applied',
      PlanTargetProgressState.conflict => 'conflict',
      PlanTargetProgressState.skipped => 'skipped',
      PlanTargetProgressState.blocked => 'blocked',
    };
  }

  List<String> _suggestedChecksFromPatchDetail(String detail) {
    final line = detail
        .split('\n')
        .map((candidate) => candidate.trim())
        .where(
          (candidate) =>
              candidate.toLowerCase().startsWith('suggested checks:') ||
              candidate.toLowerCase().startsWith('suggested verification:'),
        )
        .lastOrNull;
    if (line == null) return const [];
    final payload = line.substring(line.indexOf(':') + 1).trim();
    if (payload.isEmpty) return const [];
    return payload
        .split(RegExp(r'\s*(?:·|;)\s*'))
        .map((candidate) => candidate.trim())
        .where((candidate) => candidate.isNotEmpty)
        .take(4)
        .toList(growable: false);
  }

  String? _continuationStepDetail(StudioTurn? turn) {
    if (turn == null ||
        turn.acceptedPlanState == AcceptedPlanState.none ||
        turn.planTargetProgress.isEmpty) {
      return null;
    }
    final remaining = turn.planTargetProgress
        .where(
          (target) =>
              target.state == PlanTargetProgressState.pending ||
              target.state == PlanTargetProgressState.proposed ||
              target.state == PlanTargetProgressState.conflict ||
              target.state == PlanTargetProgressState.blocked,
        )
        .toList(growable: false);
    if (remaining.isEmpty) return null;
    final preview = remaining.take(4).map((target) => target.path).join(', ');
    final hiddenCount = remaining.length > 4 ? remaining.length - 4 : 0;
    final previewText = [
      if (preview.isNotEmpty) preview,
      if (hiddenCount > 0) '+$hiddenCount more',
    ].join(hiddenCount > 0 && preview.isNotEmpty ? ', ' : '');
    return [
      '${_acceptedPlanTargetsNeedWorkLabel(remaining.length)}.',
      if (previewText.isNotEmpty) 'Remaining: $previewText.',
      'Use Continue next batch to keep implementing the accepted plan.',
    ].join(' ');
  }

  String _acceptedPlanTargetsNeedWorkLabel(int count) {
    return '$count accepted-plan target${count == 1 ? '' : 's'} '
        '${count == 1 ? 'still needs' : 'still need'} work';
  }

  AcceptedPlanState? _acceptedPlanStateForPatchApply(
    StudioTurn? turn,
    PatchApplyStatus? applyStatus, {
    required String title,
  }) {
    final current = turn?.acceptedPlanState ?? AcceptedPlanState.none;
    if (current == AcceptedPlanState.none || applyStatus == null) return null;
    if (_isPatchRevisionTransaction(title, applyStatus)) {
      return AcceptedPlanState.patchProposed;
    }
    return switch (applyStatus) {
      PatchApplyStatus.applied =>
        _allAcceptedPlanTargetsTerminal(turn)
            ? AcceptedPlanState.implemented
            : AcceptedPlanState.patchProposed,
      PatchApplyStatus.conflict => AcceptedPlanState.patchProposed,
      PatchApplyStatus.failed => AcceptedPlanState.failed,
      PatchApplyStatus.rejected => AcceptedPlanState.blockedForMissingContext,
      PatchApplyStatus.revisionRequested => AcceptedPlanState.patchProposed,
      PatchApplyStatus.restored => AcceptedPlanState.patchProposed,
    };
  }

  void _propagateContinuationTargetProgress({
    required String threadId,
    required String sourceTurnId,
    required String? continuationPlanId,
    required String patchSetId,
    required Iterable<String> paths,
    required PlanTargetProgressState targetState,
    required String detail,
  }) {
    final originalPlanId = _sourcePlanIdForContinuation(continuationPlanId);
    if (originalPlanId == null) return;
    final normalizedPaths = paths
        .map(_normalizePlanPath)
        .where((path) => path.isNotEmpty)
        .toSet();
    if (normalizedPaths.isEmpty) return;
    final thread = ref
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == threadId)
        .firstOrNull;
    if (thread == null) return;
    for (final candidate in thread.turns) {
      if (candidate.id == sourceTurnId) continue;
      if (candidate.acceptedPlanContext?.patchSetId != originalPlanId) {
        continue;
      }
      if (candidate.planTargetProgress.isEmpty) continue;
      var changed = false;
      final updatedTargets = <PlanTargetProgress>[];
      for (final target in candidate.planTargetProgress) {
        if (_planTargetMatchesAnyPath(target.path, normalizedPaths)) {
          changed = true;
          updatedTargets.add(
            target.copyWith(
              state: targetState,
              patchSetId: patchSetId,
              detail: detail,
            ),
          );
        } else {
          updatedTargets.add(target);
        }
      }
      if (!changed) continue;
      final nextState = _allTargetsTerminal(updatedTargets)
          ? AcceptedPlanState.implemented
          : AcceptedPlanState.patchProposed;
      ref
          .read(studioThreadProvider.notifier)
          .updateTurn(
            threadId,
            candidate.id,
            acceptedPlanState: nextState,
            planTargetProgress: updatedTargets,
            status: StudioTurnStatus.completed,
            lastError: null,
            complete: true,
          );
    }
  }

  String? _sourcePlanIdForContinuation(String? planId) {
    if (planId == null) return null;
    const marker = ':next-batch';
    final index = planId.indexOf(marker);
    if (index <= 0) return null;
    return planId.substring(0, index);
  }

  bool _isPatchRevisionTransaction(
    String title,
    PatchApplyStatus? applyStatus,
  ) {
    if (applyStatus != PatchApplyStatus.rejected &&
        applyStatus != PatchApplyStatus.revisionRequested) {
      return false;
    }
    return title.trim().toLowerCase() == 'patch revision requested';
  }

  bool _allAcceptedPlanTargetsTerminal(StudioTurn? turn) {
    final targets = turn?.planTargetProgress ?? const <PlanTargetProgress>[];
    return _allTargetsTerminal(targets);
  }

  bool _allTargetsTerminal(List<PlanTargetProgress> targets) {
    if (targets.isEmpty) return true;
    return targets.every((target) {
      return switch (target.state) {
        PlanTargetProgressState.applied ||
        PlanTargetProgressState.skipped => true,
        PlanTargetProgressState.conflict ||
        PlanTargetProgressState.pending ||
        PlanTargetProgressState.proposed ||
        PlanTargetProgressState.blocked => false,
      };
    });
  }

  String _stableEventIdPart(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized.isEmpty ? 'event' : normalized;
  }

  List<PlanTargetProgress> _planTargetProgressFor(
    AcceptedPlanContext? acceptedPlanContext,
  ) {
    if (acceptedPlanContext == null) return const [];
    final targets = acceptedPlanContext.plannedTargets.isNotEmpty
        ? acceptedPlanContext.plannedTargets
        : [
            for (final file in acceptedPlanContext.plannedFiles)
              PlannedFileTarget.fromDisplayString(file),
          ];
    final seen = <String>{};
    return [
      for (final target in targets)
        if (target.path.trim().isNotEmpty &&
            seen.add(_normalizePlanPath(target.path)))
          PlanTargetProgress.fromTarget(target),
    ];
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
        .map(_normalizePlanPath)
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

  bool _patchTransactionRequestsVerification(String detail) {
    final normalized = detail.toLowerCase();
    return normalized.contains('suggested checks:') ||
        normalized.contains('recommended next step: run verification') ||
        normalized.contains('verification was requested');
  }

  String _verificationStepDetail(String detail) {
    final lines = detail
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where(
          (line) =>
              line.toLowerCase().startsWith('suggested checks:') ||
              line.toLowerCase().startsWith('recommended next step:') ||
              line.toLowerCase().startsWith('verification was requested'),
        )
        .toList(growable: false);
    return lines.isEmpty
        ? 'Patch was applied and is ready for verification.'
        : lines.join('\n');
  }

  String _normalizePlanPath(String value) {
    return value.trim().replaceAll('\\', '/').replaceAll(RegExp(r'^\./+'), '');
  }

  bool _planTargetMatchesAnyPath(String targetPath, Set<String> touchedPaths) {
    final normalizedTarget = _normalizePlanPath(
      targetPath,
    ).replaceAll(RegExp(r'/+$'), '');
    if (normalizedTarget.isEmpty) return false;
    for (final touched in touchedPaths) {
      final normalizedTouched = _normalizePlanPath(
        touched,
      ).replaceAll(RegExp(r'/+$'), '');
      if (normalizedTouched == normalizedTarget ||
          normalizedTouched.startsWith('$normalizedTarget/')) {
        return true;
      }
    }
    return false;
  }
}
