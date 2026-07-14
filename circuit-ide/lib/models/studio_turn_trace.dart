import 'studio_thread.dart';
import 'studio_turn.dart';
import 'tool_result_envelope.dart';

/// The complete, redacted lifecycle categories for one Studio request. A span
/// always records only identifiers, counts, statuses, and timestamps; it is
/// deliberately not a second transcript or workspace-content store.
enum StudioTraceSpanKind {
  workspaceBinding,
  context,
  provider,
  streaming,
  tool,
  approval,
  patch,
  command,
  artifact,
  verification,
  persistence,
  uiCompletion,
}

class StudioTraceSpan {
  final String id;
  final StudioTraceSpanKind kind;
  final String status;
  final DateTime startedAt;
  final DateTime? completedAt;
  final Map<String, Object?> attributes;

  const StudioTraceSpan({
    required this.id,
    required this.kind,
    required this.status,
    required this.startedAt,
    this.completedAt,
    this.attributes = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'status': status,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'completedAt': completedAt?.toUtc().toIso8601String(),
    'attributes': attributes,
  };
}

class StudioTurnTrace {
  final String requestId;
  final String threadId;
  final String turnId;
  final String intent;
  final String status;
  final String? outcome;
  final String? failureCategory;
  final List<StudioTraceSpan> spans;

  const StudioTurnTrace({
    required this.requestId,
    required this.threadId,
    required this.turnId,
    required this.intent,
    required this.status,
    this.outcome,
    this.failureCategory,
    required this.spans,
  });

  Map<String, dynamic> toJson() => {
    'schema': 'circuit.studio-turn-trace',
    'schemaVersion': 1,
    'requestId': requestId,
    'threadId': threadId,
    'turnId': turnId,
    'intent': intent,
    'status': status,
    'outcome': outcome,
    'failureCategory': failureCategory,
    'spans': spans.map((span) => span.toJson()).toList(growable: false),
  };
}

/// Builds a support-safe reconstruction directly from the durable Studio
/// lifecycle. This is intentionally an adapter: callers never hand it a
/// prompt, provider body, file name, command, path, URL, or event detail.
class StudioTurnTraceBuilder {
  const StudioTurnTraceBuilder._();

  static StudioTurnTrace build({
    required StudioThread thread,
    required StudioTurn turn,
  }) {
    final finishedAt = turn.completedAt ?? turn.updatedAt;
    final stepsByKind = <TurnStep, TurnStepRecord>{
      for (final step in turn.steps) step.step: step,
    };
    final artifacts = {
      ...thread.sourceArtifacts
          .where((artifact) => artifact.requestId == turn.requestId)
          .map((artifact) => artifact.id),
      for (final result in turn.toolResults) ...result.artifacts,
    }.where((id) => id.trim().isNotEmpty).toList(growable: false);
    final patchSetIds = {
      for (final target in turn.planTargetProgress)
        if (target.patchSetId?.trim().isNotEmpty == true) target.patchSetId!,
      for (final event in turn.events)
        if (event.patchSetId?.trim().isNotEmpty == true) event.patchSetId!,
    }.toList(growable: false);
    final commandResults = turn.toolResults
        .where((result) => result.toolName == 'run_command')
        .toList(growable: false);
    final approvalEvents = turn.events
        .where((event) => event.type == StudioTurnEventType.approvalRequest)
        .toList(growable: false);

    StudioTraceSpan stepSpan(
      StudioTraceSpanKind kind,
      TurnStep step, {
      Map<String, Object?> attributes = const {},
    }) {
      final record = stepsByKind[step];
      return StudioTraceSpan(
        id: '${turn.requestId}-${kind.name}',
        kind: kind,
        status: record?.status.name ?? 'not_applicable',
        startedAt: record?.startedAt ?? turn.createdAt,
        completedAt:
            record?.completedAt ??
            (record == null ? turn.createdAt : finishedAt),
        attributes: attributes,
      );
    }

    final context = turn.contextRetrieval;
    final outcome = inferStudioTurnOutcome(turn);
    final spans = <StudioTraceSpan>[
      StudioTraceSpan(
        id: '${turn.requestId}-${StudioTraceSpanKind.workspaceBinding.name}',
        kind: StudioTraceSpanKind.workspaceBinding,
        status: turn.contextSummary.rootPath == null ? 'no_project' : 'bound',
        startedAt: turn.createdAt,
        completedAt:
            stepsByKind[TurnStep.preflight]?.completedAt ?? turn.createdAt,
        attributes: {
          'hasProjectContext': turn.contextSummary.rootPath != null,
          'includesGit': turn.contextSummary.includesGit,
          'includesTerminal': turn.contextSummary.includesTerminal,
        },
      ),
      stepSpan(
        StudioTraceSpanKind.context,
        TurnStep.contextBuild,
        attributes: {
          'includedItemCount': turn.contextSummary.includedItemCount,
          'omittedCandidateCount': turn.contextSummary.omittedCandidateCount,
          'estimatedTokens': turn.contextSummary.estimatedTokens,
          'retrievalIncludedCount': context?.includedCandidates.length ?? 0,
          'retrievalOmittedCount': context?.omittedCandidates.length ?? 0,
        },
      ),
      stepSpan(
        StudioTraceSpanKind.provider,
        TurnStep.providerRequest,
        attributes: {
          'model': turn.model,
          'diagnosticKinds': turn.providerDiagnostics
              .map((event) => event.kind.name)
              .toSet()
              .toList(growable: false),
        },
      ),
      stepSpan(
        StudioTraceSpanKind.streaming,
        TurnStep.streaming,
        attributes: {
          'receivedProviderDelta': turn.providerDiagnostics.any(
            (event) => event.kind.name.startsWith('first'),
          ),
        },
      ),
      stepSpan(
        StudioTraceSpanKind.tool,
        TurnStep.toolExecution,
        attributes: {
          'toolCallIds': turn.toolResults
              .map((result) => result.toolCallId)
              .where((id) => id.trim().isNotEmpty)
              .toList(growable: false),
          'toolNames': turn.toolResults
              .map((result) => result.toolName)
              .where((name) => name.trim().isNotEmpty)
              .toSet()
              .toList(growable: false),
          'statusCounts': _statusCounts(turn.toolResults),
        },
      ),
      stepSpan(
        StudioTraceSpanKind.approval,
        TurnStep.approvalWait,
        attributes: {
          'approvalIds': approvalEvents
              .map((event) => event.approvalId)
              .whereType<String>()
              .toList(growable: false),
          'states': approvalEvents
              .map((event) => event.approvalState?.name ?? 'unknown')
              .toList(growable: false),
          'risks': approvalEvents
              .map((event) => event.approvalRisk?.name ?? 'unknown')
              .toSet()
              .toList(growable: false),
        },
      ),
      stepSpan(
        StudioTraceSpanKind.patch,
        TurnStep.patchProposal,
        attributes: {
          'patchSetIds': patchSetIds,
          'targetStateCounts': _targetStateCounts(turn),
        },
      ),
      stepSpan(
        StudioTraceSpanKind.command,
        TurnStep.commandRun,
        attributes: {
          'commandRunIds': commandResults
              .map((result) => result.toolCallId)
              .where((id) => id.trim().isNotEmpty)
              .toList(growable: false),
          'statusCounts': _statusCounts(commandResults),
        },
      ),
      StudioTraceSpan(
        id: '${turn.requestId}-${StudioTraceSpanKind.artifact.name}',
        kind: StudioTraceSpanKind.artifact,
        status: artifacts.isEmpty ? 'not_applicable' : 'recorded',
        startedAt: turn.createdAt,
        completedAt: finishedAt,
        attributes: {'artifactIds': artifacts},
      ),
      stepSpan(
        StudioTraceSpanKind.verification,
        TurnStep.verification,
        attributes: {'intent': turn.intent.name},
      ),
      StudioTraceSpan(
        id: '${turn.requestId}-${StudioTraceSpanKind.persistence.name}',
        kind: StudioTraceSpanKind.persistence,
        status: 'persisted',
        startedAt: turn.createdAt,
        completedAt: turn.updatedAt,
        attributes: {'turnStatus': turn.status.name},
      ),
      StudioTraceSpan(
        id: '${turn.requestId}-${StudioTraceSpanKind.uiCompletion.name}',
        kind: StudioTraceSpanKind.uiCompletion,
        status: outcome?.name ?? 'in_progress',
        startedAt: turn.createdAt,
        completedAt: finishedAt,
        attributes: {'threadStatus': thread.status.name},
      ),
    ];
    return StudioTurnTrace(
      requestId: turn.requestId,
      threadId: thread.id,
      turnId: turn.id,
      intent: turn.intent.name,
      status: turn.status.name,
      outcome: outcome?.name,
      failureCategory: turn.effectiveFailureCategory?.name,
      spans: spans,
    );
  }

  static Map<String, int> _statusCounts(Iterable<ToolResultEnvelope> results) {
    final counts = <String, int>{};
    for (final result in results) {
      final status = result.status.name;
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return counts;
  }

  static Map<String, int> _targetStateCounts(StudioTurn turn) {
    final counts = <String, int>{};
    for (final target in turn.planTargetProgress) {
      final state = target.state.name;
      counts[state] = (counts[state] ?? 0) + 1;
    }
    return counts;
  }
}
