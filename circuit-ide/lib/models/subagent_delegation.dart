import 'tool_result_envelope.dart';

/// The only context a delegated Studio subagent may receive. This is kept
/// separate from [ChatMessage] on purpose: callers must deliberately select
/// a bounded context excerpt instead of accidentally forwarding a thread.
class SubagentDelegationRequest {
  static const maxTaskCharacters = 2400;
  static const maxContextCharacters = 8000;
  static const maxToolCount = 6;

  /// These operations are safe to grant to a child without changing the
  /// workspace. The child never inherits the parent's general tool access.
  static const readOnlyTools = <String>{
    'read_file',
    'list_files',
    'search_files',
    'git_status',
    'git_diff',
    'git_log',
  };

  /// A child can produce a patch proposal only after this explicit grant. The
  /// proposal remains data for the parent; application stays in the normal
  /// Studio reviewed-patch flow.
  static const reviewedProposalTool = 'propose_patch';

  final String task;
  final String context;
  final Set<String> toolGrant;
  final bool allowReviewedPatchProposal;

  const SubagentDelegationRequest({
    required this.task,
    this.context = '',
    this.toolGrant = const {},
    this.allowReviewedPatchProposal = false,
  });

  factory SubagentDelegationRequest.fromToolArguments(
    Map<String, dynamic> arguments,
  ) {
    return SubagentDelegationRequest(
      task: arguments['task'] as String? ?? '',
      context: arguments['context'] as String? ?? '',
      toolGrant: (arguments['tool_grant'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toSet(),
      allowReviewedPatchProposal:
          arguments['allow_reviewed_patch_proposal'] as bool? ?? false,
    );
  }

  List<String> validate() {
    final errors = <String>[];
    if (task.trim().isEmpty) {
      errors.add('A bounded subagent task is required.');
    }
    if (task.length > maxTaskCharacters) {
      errors.add('Subagent task exceeds $maxTaskCharacters characters.');
    }
    if (context.length > maxContextCharacters) {
      errors.add('Subagent context exceeds $maxContextCharacters characters.');
    }
    if (toolGrant.length > maxToolCount) {
      errors.add('A subagent may receive at most $maxToolCount tools.');
    }
    final allowed = {
      ...readOnlyTools,
      if (allowReviewedPatchProposal) reviewedProposalTool,
    };
    final disallowed = toolGrant.difference(allowed);
    if (disallowed.isNotEmpty) {
      errors.add(
        'Subagent tool grant is not allowed: ${disallowed.join(', ')}. '
        'Only bounded read tools${allowReviewedPatchProposal ? ' and propose_patch' : ''} may be granted.',
      );
    }
    if (!allowReviewedPatchProposal &&
        toolGrant.contains(reviewedProposalTool)) {
      errors.add(
        'Patch proposals require allow_reviewed_patch_proposal: true.',
      );
    }
    if (allowReviewedPatchProposal &&
        !toolGrant.contains(reviewedProposalTool)) {
      errors.add(
        'A reviewed patch proposal requires propose_patch in tool_grant.',
      );
    }
    return errors;
  }

  Map<String, dynamic> toJson() => {
    'task': task,
    'context': context,
    'toolGrant': toolGrant.toList(growable: false),
    'allowReviewedPatchProposal': allowReviewedPatchProposal,
  };
}

class SubagentEvidence {
  final String source;
  final String summary;

  const SubagentEvidence({required this.source, required this.summary});

  factory SubagentEvidence.fromToolResult(ToolResultEnvelope result) =>
      SubagentEvidence(source: result.toolName, summary: result.summary);

  Map<String, dynamic> toJson() => {'source': source, 'summary': summary};
}

/// The single compact report returned to the parent. Provider streaming and
/// child tool chatter are intentionally not exposed to the main transcript.
class SubagentDelegationResult {
  final String summary;
  final List<SubagentEvidence> evidence;
  final List<String> artifacts;
  final List<String> unresolved;

  const SubagentDelegationResult({
    required this.summary,
    this.evidence = const [],
    this.artifacts = const [],
    this.unresolved = const [],
  });

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'evidence': evidence.map((item) => item.toJson()).toList(),
    'artifacts': artifacts,
    'unresolved': unresolved,
  };

  String toPromptBlock() => [
    'Delegated subagent report',
    'Summary:\n${summary.trim().isEmpty ? 'No final summary was returned.' : summary.trim()}',
    'Evidence:',
    if (evidence.isEmpty)
      '- No tool evidence returned.'
    else
      ...evidence.map((item) => '- ${item.source}: ${item.summary}'),
    'Artifacts:',
    if (artifacts.isEmpty) '- None.' else ...artifacts.map((item) => '- $item'),
    'Unresolved:',
    if (unresolved.isEmpty)
      '- None reported.'
    else
      ...unresolved.map((item) => '- $item'),
  ].join('\n');
}
