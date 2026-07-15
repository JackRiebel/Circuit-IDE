import '../../models/command_run.dart';
import '../../models/reviewed_edit.dart';

const verificationRepairMarker = '[verification-repair-v1]';

bool hasVerificationRepairRequest(ProposedPatchSet patch) =>
    patch.revisionPrompt?.contains(verificationRepairMarker) ?? false;

String verificationRepairPrompt(ProposedPatchSet patch, CommandRun failed) {
  final output = verificationOutputPreviewForRun(failed);
  return [
    verificationRepairMarker,
    'The reviewed patch "${patch.title}" was applied, but the approved verification command failed.',
    'Inspect the current workspace and prepare one revised patch that addresses the failure. Do not apply files or run commands until each new action is explicitly approved.',
    'Failed command: ${failed.command}',
    if (failed.exitCode != null) 'Exit code: ${failed.exitCode}',
    if (output.isNotEmpty) 'Failure output:\n$output',
  ].join('\n\n');
}

String verificationSummaryForRuns(
  List<CommandRun> runs,
  List<String> requestedCommands,
) {
  if (runs.isEmpty) {
    return 'Verification did not run.\n\nNo command was started.';
  }
  final failed = runs
      .where((run) => run.status != CommandRunStatus.succeeded)
      .firstOrNull;
  final lines = <String>[
    failed == null ? 'Verification completed.' : 'Verification failed.',
    '',
    'Commands run:',
    for (final run in runs)
      '- `${run.command}` — ${verificationRunStatusLabel(run)}',
  ];
  if (failed != null) {
    final outputPreview = verificationOutputPreviewForRun(failed);
    if (outputPreview.isNotEmpty) {
      lines.addAll(['', 'Failure output:', outputPreview]);
    }
  }
  final remaining = requestedCommands.skip(runs.length).toList();
  if (remaining.isNotEmpty) {
    lines.addAll([
      '',
      'Skipped after first failure:',
      for (final command in remaining) '- `$command`',
    ]);
  }
  if (failed != null) {
    lines.addAll([
      '',
      'Next step: fix the failing command output above, then rerun verification.',
    ]);
  }
  return lines.join('\n');
}

String verificationOutputPreviewForRun(CommandRun run) {
  final output = run.combinedOutput.trim();
  if (output.isEmpty) return '';
  const maxPreview = 900;
  final preview = output.length <= maxPreview
      ? output
      : 'Output tail (${output.length} chars total):\n${output.substring(output.length - maxPreview)}';
  return preview
      .split('\n')
      .map((line) => line.trimRight())
      .where((line) => line.trim().isNotEmpty)
      .take(24)
      .join('\n');
}

String verificationRunStatusLabel(CommandRun run) {
  final exit = run.exitCode == null ? '' : ' (exit ${run.exitCode})';
  return switch (run.status) {
    CommandRunStatus.succeeded => 'passed$exit',
    CommandRunStatus.failed => 'failed$exit',
    CommandRunStatus.cancelled => 'cancelled',
    CommandRunStatus.timedOut => 'timed out',
    CommandRunStatus.blocked => 'blocked',
    CommandRunStatus.queued || CommandRunStatus.running => 'still running',
  };
}
