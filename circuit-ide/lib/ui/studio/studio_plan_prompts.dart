import '../../models/accepted_plan_context.dart';
import '../../models/reviewed_edit.dart';
import '../../agent/verification_command_filter.dart'
    as verification_command_filter;

String buildPlanImplementationPrompt(AcceptedPlanContext plan) {
  return [
    'Implement this approved plan.',
    'Use the accepted plan context attached to this request as the source of truth.',
    'Inspect files as needed, then either call `propose_patch` with concrete file edits or ask exactly one specific missing-context question.',
    if (plan.title.trim().isNotEmpty) 'Plan title: ${plan.title.trim()}',
    if (plan.summary.trim().isNotEmpty) 'Plan summary: ${plan.summary.trim()}',
    if (plan.plannedFiles.isNotEmpty)
      'Planned files:\n${plan.plannedFiles.map((file) => '- $file').join('\n')}',
    if (plan.verificationRequested)
      'Verification was explicitly requested. Preserve that request in the patch proposal and suggested checks; verification must run later in a separate approved Verify turn.',
  ].join('\n\n');
}

String buildPatchVerificationPrompt(ProposedPatchSet patch) {
  final commands = patch.verificationSuggestions
      .where((command) => command.trim().isNotEmpty)
      .where(isRunnableVerificationCommand)
      .toList(growable: false);
  final changedFiles = patch.changedFiles.isNotEmpty
      ? patch.changedFiles
      : patch.edits.map((edit) => edit.path).toList(growable: false);
  return [
    'Run these verification checks for the completed work.',
    'This is a Verify turn. Request approval before running shell commands.',
    if (changedFiles.isNotEmpty) ...[
      'Changed files:',
      for (final file in changedFiles) '- $file',
    ],
    if (commands.isNotEmpty) ...[
      'Suggested verification commands:',
      for (final command in commands) '- $command',
    ] else
      'No specific command was inferred. Inspect the project scripts and ask one specific verification question if no safe check is available.',
    'Summarize which checks ran, their exit status, and any remaining failures.',
  ].join('\n\n');
}

bool isRunnableVerificationCommand(String value) {
  return verification_command_filter.isRunnableVerificationCommand(value);
}
