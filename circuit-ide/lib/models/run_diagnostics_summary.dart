import 'agent_run.dart';

class RunDiagnosticsSummary {
  final AgentRun run;

  const RunDiagnosticsSummary(this.run);

  String serialize() {
    final endedAt = run.endedAt;
    final elapsed = endedAt == null
        ? DateTime.now().difference(run.startedAt)
        : endedAt.difference(run.startedAt);

    return [
      'CircuitCode run diagnostics',
      'Request ID: ${run.id}',
      'Kind: ${run.kind.name}',
      'Status: ${run.status.name}',
      'Model: ${run.model}',
      'Elapsed: ${elapsed.inMilliseconds}ms',
      'Context attachments: ${run.contextAttachmentCount}',
      if (run.tokenUsage.isNotEmpty)
        'Tokens: ${run.tokenUsage.formattedInputOutput}',
      if (run.inputPreview?.isNotEmpty == true) 'Input: ${run.inputPreview}',
      if (run.outputPreview?.isNotEmpty == true) 'Output: ${run.outputPreview}',
      if (run.error?.isNotEmpty == true) 'Error: ${run.error}',
      if (run.events.isNotEmpty) 'Events:',
      ...run.events
          .take(12)
          .map(
            (event) =>
                '- ${event.timestamp.toIso8601String()} '
                '${event.type.name}: ${event.message}',
          ),
    ].join('\n');
  }
}
