import 'agent_run.dart';
import 'project_profile.dart';
import 'reviewed_edit.dart';

class WorkItemHandoffSummary {
  final String goal;
  final String status;
  final List<String> context;
  final List<ProposedPatchSet> patchSets;
  final List<String> changedFiles;
  final List<String> commandsRun;
  final List<VerificationResultSummary> verificationResults;
  final AgentRun? run;
  final List<String> errors;
  final List<String> nextSteps;

  const WorkItemHandoffSummary({
    required this.goal,
    required this.status,
    this.context = const [],
    this.patchSets = const [],
    this.changedFiles = const [],
    this.commandsRun = const [],
    this.verificationResults = const [],
    this.run,
    this.errors = const [],
    this.nextSteps = const [],
  });

  String serialize() {
    return [
      'CircuitCode work item handoff',
      'Goal: $goal',
      'Status: $status',
      if (context.isNotEmpty) 'Context: ${context.join(', ')}',
      if (changedFiles.isNotEmpty) 'Changed files: ${changedFiles.join(', ')}',
      if (patchSets.isNotEmpty)
        'Patch sets: ${patchSets.map((patch) => patch.title).join(', ')}',
      if (commandsRun.isNotEmpty) 'Commands: ${commandsRun.join(' | ')}',
      if (verificationResults.isNotEmpty) 'Verification:',
      ...verificationResults.map(
        (result) =>
            '- ${result.command}: ${result.statusLabel} (${result.duration.inSeconds}s)',
      ),
      if (run != null) 'Run: ${run!.id} · ${run!.status.name} · ${run!.model}',
      if (run?.tokenUsage.isNotEmpty == true)
        'Tokens: ${run!.tokenUsage.formattedInputOutput}',
      if (errors.isNotEmpty) 'Errors:',
      ...errors.map((error) => '- $error'),
      if (nextSteps.isNotEmpty) 'Next steps:',
      ...nextSteps.map((step) => '- $step'),
    ].join('\n');
  }
}
