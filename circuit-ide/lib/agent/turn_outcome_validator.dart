import '../models/accepted_plan_context.dart';
import '../models/reviewed_edit.dart';
import '../models/studio_turn.dart';
import '../models/tool_call_info.dart';
import '../models/tool_result_envelope.dart';
import '../models/turn_intent.dart';
import 'tools/tool_registry.dart';

enum TurnOutcomeValidationStatus { valid, invalid, blockingQuestion }

class TurnOutcomeValidationResult {
  final TurnOutcomeValidationStatus status;
  final String? userMessage;
  final AcceptedPlanState acceptedPlanState;

  const TurnOutcomeValidationResult._({
    required this.status,
    this.userMessage,
    this.acceptedPlanState = AcceptedPlanState.none,
  });

  const TurnOutcomeValidationResult.valid({
    AcceptedPlanState acceptedPlanState = AcceptedPlanState.none,
  }) : this._(
         status: TurnOutcomeValidationStatus.valid,
         acceptedPlanState: acceptedPlanState,
       );

  const TurnOutcomeValidationResult.invalid(
    String userMessage, {
    AcceptedPlanState acceptedPlanState = AcceptedPlanState.failed,
  }) : this._(
         status: TurnOutcomeValidationStatus.invalid,
         userMessage: userMessage,
         acceptedPlanState: acceptedPlanState,
       );

  const TurnOutcomeValidationResult.blockingQuestion(
    String userMessage, {
    AcceptedPlanState acceptedPlanState =
        AcceptedPlanState.blockedForMissingContext,
  }) : this._(
         status: TurnOutcomeValidationStatus.blockingQuestion,
         userMessage: userMessage,
         acceptedPlanState: acceptedPlanState,
       );

  bool get canComplete =>
      status == TurnOutcomeValidationStatus.valid ||
      status == TurnOutcomeValidationStatus.blockingQuestion;
}

class TurnOutcomeValidator {
  const TurnOutcomeValidator();

  TurnOutcomeValidationResult validate({
    required TurnIntent intent,
    required AgentToolMode toolMode,
    required String content,
    required List<ToolCallInfo> toolCalls,
    required List<ToolResultEnvelope> toolResults,
    AcceptedPlanContext? acceptedPlan,
    String? taskPrompt,
  }) {
    final toolNames = {
      ...toolCalls.map((call) => call.name),
      ...toolResults.map((result) => result.toolName),
    };
    if (intent == TurnIntent.chat && toolNames.isNotEmpty) {
      return const TurnOutcomeValidationResult.invalid(
        'This conversational turn attempted to use tools. I stopped it before marking the response complete.',
      );
    }
    if (intent == TurnIntent.chat && content.trim().isEmpty) {
      return const TurnOutcomeValidationResult.invalid(
        'This conversational turn produced no response. Answer plainly without using tools or making project assumptions.',
        acceptedPlanState: AcceptedPlanState.none,
      );
    }
    if (intent == TurnIntent.chat &&
        _containsAppHandledApprovalRequest(content)) {
      return const TurnOutcomeValidationResult.invalid(
        'This conversational turn asked for approval text. Approval is only valid when CircuitCode has an active request-scoped approval or plan card.',
        acceptedPlanState: AcceptedPlanState.none,
      );
    }
    if (intent == TurnIntent.chat &&
        _containsPrematurePatchCompletionClaim(content)) {
      return const TurnOutcomeValidationResult.invalid(
        'This conversational turn claimed work was created, changed, tested, or completed without a scoped coding turn. It should answer conversationally instead.',
        acceptedPlanState: AcceptedPlanState.none,
      );
    }

    if ((intent == TurnIntent.ask || intent == TurnIntent.review) &&
        toolNames.any(_isMutationOrPatchTool)) {
      return const TurnOutcomeValidationResult.invalid(
        'This read-only turn attempted to propose or mutate changes. Switch to Plan or Code mode for implementation work.',
      );
    }
    if ((intent == TurnIntent.ask || intent == TurnIntent.review) &&
        content.trim().isEmpty) {
      return const TurnOutcomeValidationResult.invalid(
        'This read-only turn inspected context but did not produce an answer. Summarize the findings or ask one specific missing-context question.',
        acceptedPlanState: AcceptedPlanState.none,
      );
    }
    if ((intent == TurnIntent.ask || intent == TurnIntent.review) &&
        _containsReadOnlyMutationOrVerificationClaim(content)) {
      return const TurnOutcomeValidationResult.invalid(
        'This read-only turn claimed changes were made or verification ran. Ask/Review must report findings only; switch to Code or Verify for implementation or checks.',
        acceptedPlanState: AcceptedPlanState.none,
      );
    }
    if ((intent == TurnIntent.ask || intent == TurnIntent.review) &&
        _allReadOnlyToolResultsFailed(toolResults) &&
        _containsConfidentReadOnlyFinding(content)) {
      return const TurnOutcomeValidationResult.invalid(
        'This read-only turn could not inspect the requested context but still claimed a confident finding. Report the inspection failure or ask for the missing context instead.',
        acceptedPlanState: AcceptedPlanState.none,
      );
    }

    final question = _singleBlockingQuestion(content);
    if (_containsAppHandledApprovalRequest(content) &&
        !(acceptedPlan != null && _hasPatchProposalResult(toolResults))) {
      return const TurnOutcomeValidationResult.invalid(
        'This turn asked the user to type approval text. Circuit handles plan and patch approval through the review UI.',
      );
    }

    if (intent == TurnIntent.verify) {
      if (toolNames.any(_isPatchOrMutationToolExceptCommand)) {
        return const TurnOutcomeValidationResult.invalid(
          'Verify mode can inspect and request approved checks, but it cannot propose or mutate files.',
          acceptedPlanState: AcceptedPlanState.none,
        );
      }
      if (toolNames.contains('run_command')) {
        if (_containsMutationCompletionClaim(content)) {
          return const TurnOutcomeValidationResult.invalid(
            'Verify mode ran checks but claimed files or changes were made. Verification must report command results only; switch to Code or review/apply UI for implementation.',
            acceptedPlanState: AcceptedPlanState.none,
          );
        }
        if (_hasFailedCommandResult(toolResults) &&
            _containsVerificationSuccessClaim(content)) {
          return const TurnOutcomeValidationResult.invalid(
            'A verification command failed, but the response claimed success. Summarize the failed check and remaining issue instead.',
            acceptedPlanState: AcceptedPlanState.none,
          );
        }
        if (_containsVerificationSuccessClaim(content) &&
            !_verificationSuccessClaimMatchesCommand(content, toolCalls)) {
          return const TurnOutcomeValidationResult.invalid(
            'The response claimed verification success, but the approved command did not match that claim. Report the command that actually ran, or run the appropriate check in Verify mode.',
            acceptedPlanState: AcceptedPlanState.none,
          );
        }
        return const TurnOutcomeValidationResult.valid();
      }
      if (question != null) {
        return TurnOutcomeValidationResult.blockingQuestion(
          question,
          acceptedPlanState: AcceptedPlanState.none,
        );
      }
      return const TurnOutcomeValidationResult.invalid(
        'Verify mode must request an approved command or ask one specific missing-context question before claiming a result.',
        acceptedPlanState: AcceptedPlanState.none,
      );
    }

    if (intent == TurnIntent.plan) {
      if (toolNames.any(_isForbiddenInPlanMode)) {
        return const TurnOutcomeValidationResult.invalid(
          'Plan Mode can inspect and create a plan card, but it cannot run commands, write files, mutate git, or apply patches.',
          acceptedPlanState: AcceptedPlanState.none,
        );
      }
      if (_containsPrematurePatchCompletionClaim(content)) {
        return const TurnOutcomeValidationResult.invalid(
          'Plan Mode created planning output but also claimed changes were applied, verified, or completed. Implementation must happen only after the plan is accepted.',
          acceptedPlanState: AcceptedPlanState.none,
        );
      }
      final reviewablePlanCount = _reviewablePlanProposalCount(
        toolCalls,
        toolResults,
      );
      if (reviewablePlanCount == 1) {
        return const TurnOutcomeValidationResult.valid();
      }
      if (reviewablePlanCount > 1) {
        return const TurnOutcomeValidationResult.invalid(
          'Plan Mode must finish with exactly one reviewable plan card. Split separate plans into separate turns.',
          acceptedPlanState: AcceptedPlanState.none,
        );
      }
      final concretePatchCount = _concretePatchAttemptCount(
        toolCalls,
        toolResults,
      );
      if (concretePatchCount > 0) {
        return const TurnOutcomeValidationResult.invalid(
          'Plan Mode must create a plan-only review card. Concrete file edits belong in the implementation turn after the plan is accepted.',
          acceptedPlanState: AcceptedPlanState.none,
        );
      }
      if (question != null) {
        return TurnOutcomeValidationResult.blockingQuestion(
          question,
          acceptedPlanState: AcceptedPlanState.none,
        );
      }
      return const TurnOutcomeValidationResult.invalid(
        'Plan Mode must finish with one reviewable plan card or one specific blocking question.',
        acceptedPlanState: AcceptedPlanState.none,
      );
    }

    if (acceptedPlan != null) {
      if (_acceptedPlanHasNoTargets(acceptedPlan)) {
        if (question != null) {
          return TurnOutcomeValidationResult.blockingQuestion(question);
        }
        return const TurnOutcomeValidationResult.invalid(
          'The accepted plan does not name implementation target files. Revise the plan to include explicit workspace-relative planned files before implementing it.',
        );
      }
      if (_acceptedPlanHasUnsafeTargets(acceptedPlan)) {
        return const TurnOutcomeValidationResult.invalid(
          'The accepted plan contains unsafe file targets. Planned file paths must be workspace-relative and cannot be absolute paths, drive paths, UNC paths, or traversal paths.',
        );
      }
      if (toolNames.any(_isForbiddenInImplementationMode)) {
        return const TurnOutcomeValidationResult.invalid(
          'Accepted-plan implementation turns must propose reviewable patches only. Commands, direct writes, git mutation, and patch application are handled by separate review or verify actions.',
        );
      }
      final concretePatchCount = _concretePatchProposalCount(
        toolCalls,
        toolResults,
      );
      if (concretePatchCount == 1) {
        if (_containsPrematurePatchCompletionClaim(content)) {
          return const TurnOutcomeValidationResult.invalid(
            'Circuit proposed changes but also claimed they were already applied or verified. Review and apply the patch through CircuitCode instead.',
          );
        }
        if (!_concretePatchMatchesAcceptedPlanBatch(
          toolResults,
          acceptedPlan,
        )) {
          return const TurnOutcomeValidationResult.invalid(
            'The implementation patch does not match the accepted plan targets. Revise the patch to cover a valid planned batch, match each planned file intent, avoid unplanned files, or ask one specific missing-context question explaining why the plan cannot be implemented as written.',
          );
        }
        return const TurnOutcomeValidationResult.valid(
          acceptedPlanState: AcceptedPlanState.patchProposed,
        );
      }
      if (concretePatchCount > 1) {
        return const TurnOutcomeValidationResult.invalid(
          'Accepted-plan implementation turns must finish with exactly one concrete patch proposal. Split separate patch proposals into separate turns.',
        );
      }
      if (question != null) {
        if (_questionAsksForKnownAcceptedPlanTarget(question, acceptedPlan)) {
          return const TurnOutcomeValidationResult.invalid(
            'The accepted plan already names the implementation target files. Produce one concrete patch proposal for those targets, or ask one specific missing-context question about behavior inside the planned target.',
          );
        }
        if (_questionOmitsKnownAcceptedPlanTarget(question, acceptedPlan)) {
          return const TurnOutcomeValidationResult.invalid(
            'The accepted plan already names the target file. Ask one specific missing-context question that names the planned file, or produce one concrete patch proposal for that target.',
          );
        }
        return TurnOutcomeValidationResult.blockingQuestion(question);
      }
      return const TurnOutcomeValidationResult.invalid(
        'The accepted plan did not produce app-applyable file edits or one specific missing-context question.',
      );
    }

    if (intent == TurnIntent.code &&
        (toolMode == AgentToolMode.code || toolMode == AgentToolMode.fix)) {
      if (toolNames.any(_isForbiddenInImplementationMode)) {
        return const TurnOutcomeValidationResult.invalid(
          'Code mode must inspect and propose reviewable patches only. Commands, direct writes, git mutation, and patch application are handled by separate review or verify actions.',
          acceptedPlanState: AcceptedPlanState.none,
        );
      }
      final concretePatchCount = _concretePatchProposalCount(
        toolCalls,
        toolResults,
      );
      if (concretePatchCount == 1) {
        if (_containsPrematurePatchCompletionClaim(content)) {
          return const TurnOutcomeValidationResult.invalid(
            'Circuit proposed changes but also claimed they were already applied or verified. Review and apply the patch through CircuitCode instead.',
            acceptedPlanState: AcceptedPlanState.none,
          );
        }
        if (!_concretePatchAlignsWithTaskPrompt(toolResults, taskPrompt)) {
          return const TurnOutcomeValidationResult.invalid(
            'The proposed patch does not appear to match the user request. Revise the patch so its files, title, summary, and file intents clearly align with the requested task, or ask one specific missing-context question.',
            acceptedPlanState: AcceptedPlanState.none,
          );
        }
        return const TurnOutcomeValidationResult.valid();
      }
      if (concretePatchCount > 1) {
        return const TurnOutcomeValidationResult.invalid(
          'Code mode must finish with exactly one concrete patch proposal. Split separate patch proposals into separate turns.',
          acceptedPlanState: AcceptedPlanState.none,
        );
      }
      if (question != null) {
        return TurnOutcomeValidationResult.blockingQuestion(
          question,
          acceptedPlanState: AcceptedPlanState.none,
        );
      }
      return const TurnOutcomeValidationResult.invalid(
        'Code mode must finish with app-applyable file edits or one specific missing-context question.',
        acceptedPlanState: AcceptedPlanState.none,
      );
    }

    return const TurnOutcomeValidationResult.valid();
  }

  int _reviewablePlanProposalCount(
    List<ToolCallInfo> toolCalls,
    List<ToolResultEnvelope> toolResults,
  ) {
    return _proposalPayloads(toolCalls, toolResults)
        .where(
          (payload) =>
              _isReviewablePlanPayload(payload) &&
              !_isConcretePatchPayload(payload),
        )
        .length;
  }

  int _concretePatchProposalCount(
    List<ToolCallInfo> toolCalls,
    List<ToolResultEnvelope> toolResults,
  ) {
    return _proposalPayloads(
      toolCalls,
      toolResults,
    ).where(_isConcretePatchPayload).length;
  }

  int _concretePatchAttemptCount(
    List<ToolCallInfo> toolCalls,
    List<ToolResultEnvelope> toolResults,
  ) {
    return _proposalAttemptPayloads(
      toolCalls,
      toolResults,
    ).where(_isConcretePatchAttemptPayload).length;
  }

  bool _concretePatchMatchesAcceptedPlanBatch(
    List<ToolResultEnvelope> toolResults,
    AcceptedPlanContext acceptedPlan,
  ) {
    final plannedTargets = _acceptedPlanTargetSpecs(acceptedPlan);
    if (plannedTargets.isEmpty) return false;

    final concretePayloads = _proposalPayloads(
      const [],
      toolResults,
    ).where(_isConcretePatchPayload).toList(growable: false);
    if (concretePayloads.length != 1) return false;

    final files = concretePayloads.single['files'];
    if (files is! List) return false;
    final patchTargetSpecs = <String, _PlannedFileSpec>{};
    for (final file in files.whereType<Map<String, dynamic>>()) {
      final path = file['path'];
      final intent = file['intent'];
      if (path is! String || intent is! String) return false;
      if (_isUnsafePatchTarget(path)) return false;
      final normalizedPath = _normalizePatchTarget(path);
      if (normalizedPath.isEmpty) continue;
      patchTargetSpecs[normalizedPath] = _PlannedFileSpec(
        normalizedPath,
        intent.trim(),
        _operationFromValue(file['operation']),
      );
    }
    return _patchTargetsSatisfyAcceptedPlanBatch(
      plannedTargets,
      patchTargetSpecs,
    );
  }

  bool _patchTargetsSatisfyAcceptedPlanBatch(
    Map<String, _PlannedFileSpec> plannedTargets,
    Map<String, _PlannedFileSpec> patchTargets,
  ) {
    if (patchTargets.isEmpty) return false;
    for (final patchEntry in patchTargets.entries) {
      final matchingPlannedEntries = plannedTargets.entries
          .where(
            (plannedEntry) => _patchPathMatchesPlannedTarget(
              patchEntry.key,
              plannedEntry.value.path,
            ),
          )
          .toList(growable: false);
      if (matchingPlannedEntries.isEmpty) return false;
      final patchSpec = patchEntry.value;
      final satisfiesAnyPlannedTarget = matchingPlannedEntries.any(
        (plannedEntry) =>
            _patchSpecSatisfiesPlannedSpec(plannedEntry.value, patchSpec),
      );
      if (!satisfiesAnyPlannedTarget) {
        return false;
      }
    }
    return true;
  }

  bool _patchPathMatchesPlannedTarget(String patchPath, String plannedPath) {
    if (patchPath == plannedPath) return true;
    final normalizedPlanned = plannedPath.endsWith('/')
        ? plannedPath
        : '$plannedPath/';
    return plannedPath.endsWith('/') && patchPath.startsWith(normalizedPlanned);
  }

  bool _patchSpecSatisfiesPlannedSpec(
    _PlannedFileSpec plannedSpec,
    _PlannedFileSpec patchSpec,
  ) {
    if (plannedSpec.operation != null &&
        patchSpec.operation != plannedSpec.operation) {
      return false;
    }
    if (plannedSpec.operation == null &&
        patchSpec.operation == ProposedFileEditType.delete &&
        !_intentAllowsDelete(plannedSpec.intent)) {
      return false;
    }
    // Accepted-plan implementation should be strict about target boundaries and
    // operation safety, but not brittle about natural-language intent wording.
    // The review UI is the right place to judge whether the proposed change is
    // good enough; hard rejection here caused useful first-batch patches to be
    // surfaced as provider failures.
    return true;
  }

  Map<String, _PlannedFileSpec> _acceptedPlanTargetSpecs(
    AcceptedPlanContext acceptedPlan,
  ) {
    final targets = <String, _PlannedFileSpec>{};
    final structuredTargets = acceptedPlan.plannedTargets.isNotEmpty
        ? acceptedPlan.plannedTargets
        : [
            for (final file in acceptedPlan.plannedFiles)
              PlannedFileTarget.fromDisplayString(file),
          ];
    for (final target in structuredTargets) {
      final spec = _extractPlannedFileSpec(target);
      final normalizedPath = _normalizePatchTarget(spec.path);
      if (normalizedPath.isEmpty) continue;
      final inferredIntent = spec.intent.trim().isEmpty
          ? _inferAcceptedPlanIntent(acceptedPlan, normalizedPath)
          : spec.intent;
      targets[normalizedPath] = _PlannedFileSpec(
        normalizedPath,
        inferredIntent,
        spec.operation ?? _operationFromIntent(inferredIntent),
      );
    }
    return targets;
  }

  String _inferAcceptedPlanIntent(
    AcceptedPlanContext acceptedPlan,
    String normalizedPath,
  ) {
    final basename = normalizedPath.split('/').last;
    final pathPattern = RegExp(
      RegExp.escape(normalizedPath),
      caseSensitive: false,
    );
    final basenamePattern = RegExp(
      RegExp.escape(basename),
      caseSensitive: false,
    );
    final relevantLines = acceptedPlan.markdown
        .split(RegExp(r'\r?\n'))
        .where(
          (line) =>
              pathPattern.hasMatch(line) || basenamePattern.hasMatch(line),
        )
        .join(' ');
    final lineIntent = _meaningfulAcceptedPlanIntent(
      relevantLines,
      normalizedPath,
    );
    if (lineIntent.isNotEmpty) return lineIntent;

    final combined = [
      acceptedPlan.title,
      acceptedPlan.summary,
      acceptedPlan.markdown,
    ].join(' ');
    return _meaningfulAcceptedPlanIntent(combined, normalizedPath);
  }

  String _meaningfulAcceptedPlanIntent(String value, String normalizedPath) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final pathTokens = _pathIntentTokens(normalizedPath);
    final meaningfulTokens = _intentTokens(trimmed)
        .where(
          (token) =>
              !pathTokens.contains(token) &&
              !const {
                'accept',
                'accepted',
                'assumption',
                'behavior',
                'context',
                'detail',
                'implementation',
                'plan',
                'review',
                'step',
                'summary',
                'target',
                'verification',
                'work',
                'workspace',
              }.contains(token),
        )
        .toSet();
    if (meaningfulTokens.isEmpty) return '';
    return meaningfulTokens.join(' ');
  }

  Set<String> _pathIntentTokens(String path) {
    return path
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .split(RegExp(r'\s+'))
        .map((token) => token.trim())
        .map(_canonicalIntentToken)
        .where((token) => token.length > 2)
        .toSet();
  }

  bool _acceptedPlanHasUnsafeTargets(AcceptedPlanContext acceptedPlan) {
    final structuredTargets = acceptedPlan.plannedTargets.isNotEmpty
        ? acceptedPlan.plannedTargets
        : [
            for (final file in acceptedPlan.plannedFiles)
              PlannedFileTarget.fromDisplayString(file),
          ];
    return structuredTargets.any((target) => _isUnsafePatchTarget(target.path));
  }

  bool _acceptedPlanHasNoTargets(AcceptedPlanContext acceptedPlan) {
    return _acceptedPlanTargetSpecs(acceptedPlan).isEmpty;
  }

  _PlannedFileSpec _extractPlannedFileSpec(PlannedFileTarget plannedFile) {
    final trimmed = plannedFile.path.trim();
    if (trimmed.isEmpty) return const _PlannedFileSpec('', '');
    final intent = plannedFile.intent.trim();
    return _PlannedFileSpec(
      trimmed,
      intent,
      plannedFile.operation ?? _operationFromIntent(intent),
    );
  }

  ProposedFileEditType _operationFromValue(Object? value) {
    final operation = (value as String? ?? 'create').toLowerCase();
    return switch (operation) {
      'delete' => ProposedFileEditType.delete,
      'modify' || 'update' => ProposedFileEditType.modify,
      _ => ProposedFileEditType.create,
    };
  }

  bool _concretePatchAlignsWithTaskPrompt(
    List<ToolResultEnvelope> toolResults,
    String? taskPrompt,
  ) {
    final taskTokens = _taskPromptTokens(taskPrompt);
    if (taskTokens.isEmpty) return true;

    final concretePayloads = _proposalPayloads(
      const [],
      toolResults,
    ).where(_isConcretePatchPayload).toList(growable: false);
    if (concretePayloads.length != 1) return false;

    final payload = concretePayloads.single;
    final buffer = StringBuffer()
      ..write(' ')
      ..write(payload['title'] ?? '')
      ..write(' ')
      ..write(payload['summary'] ?? '');
    final files = payload['files'];
    if (files is List) {
      for (final file in files.whereType<Map<String, dynamic>>()) {
        buffer
          ..write(' ')
          ..write(file['path'] ?? '')
          ..write(' ')
          ..write(file['intent'] ?? '')
          ..write(' ')
          ..write(file['operation'] ?? '');
      }
    }

    final patchTokens = _intentTokens(buffer.toString());
    if (patchTokens.isEmpty) return false;
    final overlap = taskTokens.intersection(patchTokens).length;
    final requiredOverlap = taskTokens.length == 1 ? 1 : 2;
    return overlap >= requiredOverlap;
  }

  Set<String> _taskPromptTokens(String? taskPrompt) {
    if (taskPrompt == null || taskPrompt.trim().isEmpty) return const {};
    final tokens = _intentTokens(taskPrompt)
        .where(
          (token) => !const {
            'bug',
            'error',
            'fail',
            'failure',
            'issue',
            'problem',
            'request',
            'task',
            'test',
          }.contains(token),
        )
        .toSet();
    if (tokens.isEmpty) return const {};
    if (tokens.length <= 6) return tokens;
    final deweighted = tokens
        .where(
          (token) => !const {
            'please',
            'would',
            'could',
            'should',
            'make',
            'build',
            'using',
            'without',
            'before',
            'after',
            'then',
            'also',
            'just',
            'really',
            'thing',
            'stuff',
          }.contains(token),
        )
        .toSet();
    return deweighted.isEmpty ? tokens : deweighted;
  }

  bool _intentAllowsDelete(String plannedIntent) {
    return RegExp(
      r'\b(remove|delete|drop|deprecate|retire|discard|eliminate|clean up|cleanup|prune)\b',
      caseSensitive: false,
    ).hasMatch(plannedIntent);
  }

  ProposedFileEditType? _operationFromIntent(String plannedIntent) {
    final normalized = plannedIntent
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return null;
    if (_intentAllowsDelete(normalized)) return ProposedFileEditType.delete;
    if (RegExp(
      r'\b(create|add|new|scaffold|generate|introduce)\b',
    ).hasMatch(normalized)) {
      return ProposedFileEditType.create;
    }
    if (RegExp(
      r'\b(update|fix|change|modify|refactor|improve|adjust|rename|replace|repair)\b',
    ).hasMatch(normalized)) {
      return ProposedFileEditType.modify;
    }
    return null;
  }

  Set<String> _intentTokens(String value) {
    const stopWords = {
      'a',
      'an',
      'and',
      'for',
      'in',
      'of',
      'on',
      'the',
      'to',
      'with',
      'add',
      'adjust',
      'change',
      'cleanup',
      'correctly',
      'create',
      'delete',
      'discard',
      'drop',
      'eliminate',
      'file',
      'files',
      'fix',
      'generate',
      'improve',
      'introduce',
      'modify',
      'new',
      'patch',
      'properly',
      'refactor',
      'remove',
      'repair',
      'replace',
      'scaffold',
      'update',
    };
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .split(RegExp(r'\s+'))
        .map((token) => token.trim())
        .map(_canonicalIntentToken)
        .where((token) => token.length > 2 && !stopWords.contains(token))
        .toSet();
  }

  String _canonicalIntentToken(String token) {
    return switch (token) {
      'authentication' || 'authenticate' || 'authenticated' => 'auth',
      'authorization' || 'authorize' || 'authorized' => 'auth',
      'caching' || 'cached' || 'caches' => 'cache',
      'routing' || 'routed' || 'routes' => 'route',
      'redirects' || 'redirecting' || 'redirected' => 'redirect',
      'components' => 'component',
      'charts' => 'chart',
      'diagrams' => 'diagram',
      'tests' || 'tested' || 'testing' => 'test',
      'builds' || 'building' => 'build',
      _ when token.endsWith('ies') && token.length > 4 =>
        '${token.substring(0, token.length - 3)}y',
      _ when token.endsWith('ing') && token.length > 5 => token.substring(
        0,
        token.length - 3,
      ),
      _ when token.endsWith('ed') && token.length > 4 => token.substring(
        0,
        token.length - 2,
      ),
      _ when token.endsWith('s') && token.length > 4 => token.substring(
        0,
        token.length - 1,
      ),
      _ => token,
    };
  }

  bool _isMutationOrPatchTool(String name) {
    return {
      'propose_patch',
      'apply_patch_set',
      'write_file',
      'edit_file',
      'run_command',
      'git_branch',
      'git_commit',
      'github_create_repo',
      'github_create_issue',
      'github_close_issue',
    }.contains(name);
  }

  bool _isPatchOrMutationToolExceptCommand(String name) {
    return {
      'propose_patch',
      'apply_patch_set',
      'write_file',
      'edit_file',
      'git_branch',
      'git_commit',
      'github_create_repo',
      'github_create_issue',
      'github_close_issue',
    }.contains(name);
  }

  bool _isForbiddenInPlanMode(String name) {
    return {
      'apply_patch_set',
      'write_file',
      'edit_file',
      'run_command',
      'git_branch',
      'git_commit',
      'github_create_repo',
      'github_create_issue',
      'github_close_issue',
    }.contains(name);
  }

  bool _isForbiddenInImplementationMode(String name) {
    return {
      'apply_patch_set',
      'write_file',
      'edit_file',
      'run_command',
      'git_branch',
      'git_commit',
      'github_create_repo',
      'github_create_issue',
      'github_close_issue',
    }.contains(name);
  }

  bool _hasPatchProposalResult(List<ToolResultEnvelope> toolResults) {
    return toolResults.any(
      (result) =>
          result.toolName == 'propose_patch' &&
          result.status == ToolResultStatus.success,
    );
  }

  bool _hasFailedCommandResult(List<ToolResultEnvelope> toolResults) {
    return toolResults.any(
      (result) =>
          result.toolName == 'run_command' &&
          result.status != ToolResultStatus.success,
    );
  }

  bool _containsVerificationSuccessClaim(String content) {
    final normalized = content
        .toLowerCase()
        .replaceAll("'", ' ')
        .replaceAll('’', ' ')
        .replaceAll(RegExp(r'[`*_>#\[\]().,:;!]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return false;
    return RegExp(
          r'\b(tests?|checks?|build|lint|analy[sz]e|verification|command)\s+(pass|passed|passes|succeeded|succeeds|successful|clean)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(all|everything)\s+(pass|passed|passes|succeeded|succeeds|successful|good|green|clean)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(no|zero)\s+(failures?|errors?|issues?|problems?)\b',
        ).hasMatch(normalized) ||
        RegExp(r'\b(looks good|all good|green)\b').hasMatch(normalized);
  }

  bool _verificationSuccessClaimMatchesCommand(
    String content,
    List<ToolCallInfo> toolCalls,
  ) {
    final normalizedContent = content
        .toLowerCase()
        .replaceAll("'", ' ')
        .replaceAll('’', ' ')
        .replaceAll(RegExp(r'[`*_>#\[\]().,:;!]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final commands = toolCalls
        .where((call) => call.name == 'run_command')
        .map((call) => call.arguments['command'] as String? ?? '')
        .map(
          (command) =>
              command.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim(),
        )
        .where((command) => command.isNotEmpty)
        .toList(growable: false);
    if (commands.isEmpty) return false;

    final claimsTests = RegExp(r'\btests?\b').hasMatch(normalizedContent);
    final claimsBuild = RegExp(r'\bbuild\b').hasMatch(normalizedContent);
    final claimsLint = RegExp(
      r'\b(lint|analy[sz]e|analysis|format)\b',
    ).hasMatch(normalizedContent);
    final claimsGenericChecks = RegExp(
      r'\b(checks?|verification|command|all|everything|green)\b',
    ).hasMatch(normalizedContent);

    if (claimsTests && !commands.any(_isTestCommand)) return false;
    if (claimsBuild && !commands.any(_isBuildCommand)) return false;
    if (claimsLint && !commands.any(_isLintCommand)) return false;
    if (!claimsTests &&
        !claimsBuild &&
        !claimsLint &&
        claimsGenericChecks &&
        !commands.any(_isVerificationCommand)) {
      return false;
    }
    return true;
  }

  bool _isVerificationCommand(String command) {
    return _isTestCommand(command) ||
        _isBuildCommand(command) ||
        _isLintCommand(command) ||
        RegExp(r'\b(check|verify|validate)\b').hasMatch(command);
  }

  bool _isTestCommand(String command) {
    return RegExp(
      r'\b(test|tests|pytest|jest|vitest|mocha|rspec|phpunit)\b|\bgo test\b|\bcargo test\b|\bswift test\b|\bxcodebuild test\b',
    ).hasMatch(command);
  }

  bool _isBuildCommand(String command) {
    return RegExp(
      r'\b(build|assemble|compile|xcodebuild)\b|\bcargo build\b|\bgo build\b|\bswift build\b',
    ).hasMatch(command);
  }

  bool _isLintCommand(String command) {
    return RegExp(
      r'\b(lint|analy[sz]e|analysis|format|eslint|ruff|clippy)\b|\bdart format\b|\bflutter analyze\b',
    ).hasMatch(command);
  }

  bool _isConcretePatchPayload(Map<String, dynamic> args) {
    final title = args['title'];
    final summary = args['summary'];
    if (title is! String || title.trim().isEmpty) return false;
    if (summary is! String || summary.trim().isEmpty) return false;
    return _hasConcreteFileEdit(args);
  }

  bool _isConcretePatchAttemptPayload(Map<String, dynamic> args) {
    if (_isConcretePatchPayload(args)) return true;
    final files = args['files'];
    if (files is! List) return false;
    return files.whereType<Map<String, dynamic>>().any((file) {
      final path = file['path'];
      if (path is! String || path.trim().isEmpty) return false;
      final before = file['before'];
      final content = file['content'] ?? file['after'];
      return before is String || content is String;
    });
  }

  Iterable<Map<String, dynamic>> _proposalPayloads(
    List<ToolCallInfo> toolCalls,
    List<ToolResultEnvelope> toolResults,
  ) sync* {
    for (final result in toolResults.where(
      (result) =>
          result.toolName == 'propose_patch' &&
          result.status == ToolResultStatus.success &&
          result.data.isNotEmpty,
    )) {
      yield result.data;
    }
  }

  Iterable<Map<String, dynamic>> _proposalAttemptPayloads(
    List<ToolCallInfo> toolCalls,
    List<ToolResultEnvelope> toolResults,
  ) sync* {
    yield* _proposalPayloads(toolCalls, toolResults);
    for (final call in toolCalls.where(
      (call) => call.name == 'propose_patch',
    )) {
      if (call.arguments.isNotEmpty) yield call.arguments;
    }
  }

  bool _hasConcreteFileEdit(Map<String, dynamic> args) {
    final files = args['files'];
    if (files is! List) return false;
    final filePayloads = files.whereType<Map<String, dynamic>>().toList();
    if (filePayloads.isEmpty) return false;
    final paths = <String>{};
    for (final file in filePayloads) {
      final path = file['path'];
      if (path is! String) return false;
      if (_isUnsafePatchTarget(path)) return false;
      final normalizedPath = _normalizePatchTarget(path);
      if (normalizedPath.isEmpty || !paths.add(normalizedPath)) {
        return false;
      }
    }
    return filePayloads.every(_isConcreteFileEdit);
  }

  bool _isConcreteFileEdit(Map<String, dynamic> file) {
    final path = file['path'];
    if (path is! String || path.trim().isEmpty) return false;
    if (_isUnsafePatchTarget(path)) return false;
    final intent = file['intent'];
    if (intent is! String || intent.trim().isEmpty) return false;

    final operation = (file['operation'] as String? ?? 'create').toLowerCase();
    final before = file['before'];
    final content = file['content'] ?? file['after'];
    return switch (operation) {
      'create' =>
        content is String &&
            (content.trim().isNotEmpty || _intentAllowsEmptyContent(intent)),
      'modify' =>
        before is String &&
            content is String &&
            before != content &&
            (content.trim().isNotEmpty || _intentAllowsEmptyContent(intent)),
      'delete' => before is String,
      _ => false,
    };
  }

  bool _intentAllowsEmptyContent(String intent) {
    return RegExp(
      r'\b(empty|blank|placeholder|sentinel|gitkeep|keep directory|directory marker|truncate|clear)\b',
      caseSensitive: false,
    ).hasMatch(intent);
  }

  String _normalizePatchTarget(String path) {
    final raw = path.trim().replaceAll('\\', '/');
    if (raw.isEmpty) return '';
    final parts = <String>[];
    for (final part in raw.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty && parts.last != '..') {
          parts.removeLast();
        } else {
          parts.add(part);
        }
        continue;
      }
      parts.add(part);
    }
    final normalized = parts.join('/').toLowerCase();
    return raw.endsWith('/') && normalized.isNotEmpty
        ? '$normalized/'
        : normalized;
  }

  bool _isUnsafePatchTarget(String path) {
    final raw = path.trim();
    if (raw.isEmpty) return true;
    final sanitized = raw.replaceAll('\\', '/');
    if (_hasUnsafePathCharacters(sanitized)) return true;
    if (sanitized == '.' || sanitized == '..') return true;
    if (sanitized.startsWith('/') || sanitized.startsWith('//')) return true;
    if (RegExp(r'^[A-Za-z]:/').hasMatch(sanitized)) return true;
    if (_looksSecretPatchTarget(sanitized)) return true;
    return sanitized.split('/').any((part) => part == '..');
  }

  bool _hasUnsafePathCharacters(String sanitizedPath) {
    return sanitizedPath.codeUnits.any((unit) => unit < 32 || unit == 127);
  }

  bool _looksSecretPatchTarget(String sanitizedPath) {
    final normalized = sanitizedPath.toLowerCase();
    return normalized == '.env' ||
        normalized.startsWith('.env.') ||
        normalized.contains('/.env') ||
        normalized.contains('secret') ||
        normalized.contains('credentials') ||
        normalized == '.npmrc' ||
        normalized.endsWith('/.npmrc') ||
        normalized == '.netrc' ||
        normalized.endsWith('/.netrc') ||
        normalized == 'id_rsa' ||
        normalized.endsWith('/id_rsa') ||
        normalized == 'id_ed25519' ||
        normalized.endsWith('/id_ed25519') ||
        normalized == '.aws' ||
        normalized.startsWith('.aws/') ||
        normalized.contains('/.aws/');
  }

  bool _isReviewablePlanPayload(Map<String, dynamic> args) {
    final title = args['title'];
    final summary = args['summary'];
    if (title is! String || title.trim().isEmpty) return false;
    if (summary is! String || summary.trim().isEmpty) return false;

    final planMarkdown = args['plan_markdown'] ?? args['planMarkdown'];
    final planMarkdownText = planMarkdown is String ? planMarkdown.trim() : '';
    final hasPlanMarkdown = planMarkdownText.length >= 40;
    final hasAssumptions = _hasPlanAssumptions(args, planMarkdownText);
    final hasVerificationSteps = _hasPlanVerificationSteps(
      args,
      planMarkdownText,
    );
    final syntheticPlan = args['synthetic_plan'] == true;
    final hasPlannedFiles = _hasReviewablePlanFiles(args['files']);

    return hasPlanMarkdown &&
        (hasPlannedFiles || syntheticPlan) &&
        hasAssumptions &&
        hasVerificationSteps;
  }

  bool _hasReviewablePlanFiles(Object? files) {
    if (files is! List || files.isEmpty) return false;
    final filePayloads = files.whereType<Map<String, dynamic>>().toList();
    if (filePayloads.length != files.length || filePayloads.isEmpty) {
      return false;
    }
    final paths = <String>{};
    for (final file in filePayloads) {
      final path = file['path'];
      final intent = file['intent'];
      final operation = file['operation'];
      if (path is! String ||
          path.trim().isEmpty ||
          _isUnsafePatchTarget(path) ||
          intent is! String ||
          intent.trim().isEmpty ||
          !_isPlanOperationValue(operation)) {
        return false;
      }
      final normalizedPath = _normalizePatchTarget(path);
      if (normalizedPath.isEmpty || !paths.add(normalizedPath)) {
        return false;
      }
    }
    return true;
  }

  bool _isPlanOperationValue(Object? value) {
    if (value is! String) return false;
    return const {'create', 'modify', 'delete'}.contains(value.toLowerCase());
  }

  bool _hasPlanAssumptions(Map<String, dynamic> args, String planMarkdownText) {
    final assumptions = args['assumptions'];
    if (assumptions is List &&
        assumptions.any((item) => item is String && item.trim().isNotEmpty)) {
      return true;
    }
    return RegExp(
      r'(^|\n)\s{0,3}#{1,6}\s*assumptions?\b',
      caseSensitive: false,
    ).hasMatch(planMarkdownText);
  }

  bool _hasPlanVerificationSteps(
    Map<String, dynamic> args,
    String planMarkdownText,
  ) {
    final verification =
        args['verification_steps'] ?? args['verificationSteps'];
    if (verification is List &&
        verification.any((item) => item is String && item.trim().isNotEmpty)) {
      return true;
    }
    return RegExp(
      r'(^|\n)\s{0,3}#{1,6}\s*(verification|validation|test plan|checks?)\b',
      caseSensitive: false,
    ).hasMatch(planMarkdownText);
  }

  String? _singleBlockingQuestion(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;
    final questionCount = RegExp(r'\?').allMatches(trimmed).length;
    final looksQuestion = questionCount == 1 && trimmed.endsWith('?');
    if (!looksQuestion) return null;
    if (trimmed.length > 700) return null;
    if (!_isSpecificMissingContextQuestion(trimmed)) return null;
    return trimmed;
  }

  bool _containsAppHandledApprovalRequest(String content) {
    final normalized = content
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s?]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return false;
    if (_containsNegatedApprovalInstruction(normalized)) return false;
    return RegExp(
          r'\b(reply|type|say|send)\s+(approve|approval|approved)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(please\s+)?approve\s+(as described|this|the|these|that|it|plan|patch|changes|edits|implementation)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(approval|approve)\s+(is )?(needed|required)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(approve|approval|confirm if you want|say approve|reply approve)\b.*\b(apply|implement|make the changes|proceed|continue)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(do you want me to|would you like me to|should i|shall i)\b.*\b(apply|implement|make the changes|proceed|continue)\b',
        ).hasMatch(normalized);
  }

  bool _containsNegatedApprovalInstruction(String normalized) {
    return RegExp(
          r'\b(do not|don t|dont|never)\s+(ask|tell|prompt|instruct)\b.*\b(approve|approval|approved)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\bwithout\s+(asking|telling|prompting|instructing)\b.*\b(approve|approval|approved)\b',
        ).hasMatch(normalized);
  }

  bool _containsPrematurePatchCompletionClaim(String content) {
    final normalized = content
        .toLowerCase()
        .replaceAll("'", ' ')
        .replaceAll('’', ' ')
        .replaceAll(RegExp(r'[`*_>#\[\]().,:;!]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return false;

    return RegExp(
          r'\b(i|i ve|i have|we|we ve|we have|circuit)\s+(implemented|applied|made|changed|updated|created|deleted|removed|added|modified|scaffolded|generated|wrote|fixed|finished|completed)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(i|i ve|i have|we|we ve|we have|circuit)\s+(saved|exported|published|delivered|stored)\b.*\b(file|files|docs?|document|markdown|md|txt|report|chart|diagram|table|artifact|workspace|repo|repository)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(changes|patch|file|files|edits|updates)\s+(are|were|have been|has been)\s+(applied|implemented|written|updated|created|made|added|removed|modified|scaffolded|generated|completed|finished|fixed)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(diagram|chart|table|report|brief|summary|document|artifact)\s+(is|was|has been|have been)\s+(saved|exported|published|written|created|generated|stored)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(i|we|circuit)\s+(ran|verified|tested|checked)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\btests?\s+(pass|passed|are passing)\b',
        ).hasMatch(normalized) ||
        RegExp(r'^(done|completed|finished)\b').hasMatch(normalized);
  }

  bool _containsReadOnlyMutationOrVerificationClaim(String content) {
    final normalized = content
        .toLowerCase()
        .replaceAll("'", ' ')
        .replaceAll('’', ' ')
        .replaceAll(RegExp(r'[`*_>#\[\]().,:;!]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return false;

    return RegExp(
          r'\b(i|i ve|i have|we|we ve|we have|circuit)\s+(implemented|applied|made|changed|updated|created|deleted|removed|added|modified|scaffolded|generated|wrote|fixed|finished|completed)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(i|i ve|i have|we|we ve|we have|circuit)\s+(saved|exported|published|delivered|stored)\b.*\b(file|files|docs?|document|markdown|md|txt|report|chart|diagram|table|artifact|workspace|repo|repository)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(changes|patch|file|files|edits|updates)\s+(are|were|have been|has been)\s+(applied|implemented|written|updated|created|made|added|removed|modified|scaffolded|generated|completed|finished|fixed)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(diagram|chart|table|report|brief|summary|document|artifact)\s+(is|was|has been|have been)\s+(saved|exported|published|written|created|generated|stored)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(i|we|circuit)\s+(ran|verified|tested)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\btests?\s+(pass|passed|are passing)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(checks?|build|lint|analy[sz]e|verification|commands?)\s+(pass|passed|passes|succeeded|succeeds|successful|clean)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(all|everything)\s+(pass|passed|passes|succeeded|succeeds|successful|good|green|clean)\b',
        ).hasMatch(normalized);
  }

  bool _containsMutationCompletionClaim(String content) {
    final normalized = content
        .toLowerCase()
        .replaceAll("'", ' ')
        .replaceAll('’', ' ')
        .replaceAll(RegExp(r'[`*_>#\[\]().,:;!]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return false;

    return RegExp(
          r'\b(i|i ve|i have|we|we ve|we have|circuit)\s+(implemented|applied|made|changed|updated|created|deleted|removed|added|modified|scaffolded|generated|wrote|fixed)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(changes|patch|file|files|edits|updates)\s+(are|were|have been|has been)\s+(applied|implemented|written|updated|created|made|added|removed|modified|scaffolded|generated|completed|finished|fixed)\b',
        ).hasMatch(normalized);
  }

  bool _allReadOnlyToolResultsFailed(List<ToolResultEnvelope> toolResults) {
    final readOnlyResults = toolResults
        .where((result) => !_isMutationOrPatchTool(result.toolName))
        .toList();
    if (readOnlyResults.isEmpty) return false;
    return readOnlyResults.every(
      (result) => result.status != ToolResultStatus.success,
    );
  }

  bool _containsConfidentReadOnlyFinding(String content) {
    final normalized = content
        .toLowerCase()
        .replaceAll(RegExp(r'[`*_>#\[\]().,:;!]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return false;

    return RegExp(
          r'\b(i|we|circuit)\s+(found|confirmed|determined)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(no|zero)\s+(issues?|problems?|errors?|bugs?|risks?)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(looks good|all good|everything looks good|seems fine|looks fine|nothing looks wrong|nothing to fix|codebase is clean|project is healthy)\b',
        ).hasMatch(normalized);
  }

  bool _isSpecificMissingContextQuestion(String question) {
    final normalized = question
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s?]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (RegExp(
      r'\b(should i|would you like me to|do you want me to|can i|may i|shall i)\b.*\b(proceed|continue|start|begin|implement|apply|make the changes|go ahead)\b',
    ).hasMatch(normalized)) {
      return false;
    }
    if (RegExp(
      r'\b(approve|approval|confirm if you want|say approve|reply approve|go ahead)\b',
    ).hasMatch(normalized)) {
      return false;
    }

    final questionCore = _questionCore(normalized);
    if (_looksLikeMultiPartQuestion(questionCore)) return false;
    final asksForSpecifics = RegExp(
      r'^(which|what|where|who|when|how many|can you provide|could you provide|please provide|please share|tell me which|tell me what|confirm which|confirm what|confirm where)\b',
    ).hasMatch(questionCore);
    if (!asksForSpecifics) return false;

    return RegExp(
      r'\b(file|path|route|component|module|package|api|endpoint|schema|table|model|class|function|method|screen|page|view|branch|project|command|script|dependency|version|requirement|constraint|behavior|label|value|option|directory|folder|service|config|setting|environment|target|source|destination|customer|site|device|interface|vlan|subnet|network)\b',
    ).hasMatch(questionCore);
  }

  bool _questionAsksForKnownAcceptedPlanTarget(
    String question,
    AcceptedPlanContext acceptedPlan,
  ) {
    final plannedTargets = _acceptedPlanTargetSpecs(acceptedPlan);
    if (plannedTargets.isEmpty) return false;
    final normalized = question
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s?]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final core = _questionCore(normalized);
    final asksWhichTarget = RegExp(
      r'^(which|what|where|confirm which|confirm what|confirm where|tell me which|tell me what)\b.*\b(file|path|module|component|screen|page|view|directory|folder|target|source|destination)\b',
    ).hasMatch(core);
    if (!asksWhichTarget) return false;

    final mentionsKnownTarget = plannedTargets.keys.any((target) {
      final normalizedTarget = target
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final basename = target
          .split('/')
          .last
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return (normalizedTarget.isNotEmpty && core.contains(normalizedTarget)) ||
          (basename.isNotEmpty && core.contains(basename));
    });
    return !mentionsKnownTarget;
  }

  bool _questionOmitsKnownAcceptedPlanTarget(
    String question,
    AcceptedPlanContext acceptedPlan,
  ) {
    final plannedTargets = _acceptedPlanTargetSpecs(acceptedPlan);
    if (plannedTargets.isEmpty) return false;
    final normalized = question
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s?]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final core = _questionCore(normalized);
    if (core.isEmpty) return false;

    final mentionsKnownTarget = plannedTargets.keys.any((target) {
      final normalizedTarget = target
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final basename = target
          .split('/')
          .last
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return (normalizedTarget.isNotEmpty && core.contains(normalizedTarget)) ||
          (basename.isNotEmpty && core.contains(basename));
    });
    return !mentionsKnownTarget;
  }

  String _questionCore(String normalizedQuestion) {
    const preamblePatterns = [
      r'^i need one detail\s+',
      r'^i need one more detail\s+',
      r'^i need one missing detail\s+',
      r'^one detail\s+',
      r'^one question\s+',
      r'^quick question\s+',
      r'^before i can continue\s+',
      r'^before i can implement this\s+',
      r'^before i can make the patch\s+',
      r'^before i can propose the patch\s+',
    ];
    var core = normalizedQuestion;
    for (final pattern in preamblePatterns) {
      core = core.replaceFirst(RegExp(pattern), '');
    }
    return core.trim();
  }

  bool _looksLikeMultiPartQuestion(String questionCore) {
    final requestedFields = RegExp(
      r'\b(file|path|route|component|module|package|api|endpoint|schema|table|model|class|function|method|screen|page|view|branch|project|command|script|dependency|version|requirement|constraint|behavior|label|value|option|directory|folder|service|config|setting|environment|target|source|destination|customer|site|device|interface|vlan|subnet|network)\b',
    ).allMatches(questionCore).length;
    final conjunctions = RegExp(
      r'\b(and|or|also|plus|along with|as well as)\b',
    ).allMatches(questionCore).length;
    if (conjunctions >= 1 && requestedFields >= 2) return true;

    final punctuationSeparators = RegExp(
      r'[,;:]',
    ).allMatches(questionCore).length;
    if (punctuationSeparators >= 2) return true;

    if (requestedFields > 2) return true;

    return false;
  }
}

class _PlannedFileSpec {
  final String path;
  final String intent;
  final ProposedFileEditType? operation;

  const _PlannedFileSpec(this.path, this.intent, [this.operation]);
}
