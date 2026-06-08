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
      if (run.checkpointId?.isNotEmpty == true)
        'Checkpoint: ${run.checkpointId}',
      if (run.changedFiles.isNotEmpty)
        'Changed files: ${run.changedFiles.join(", ")}',
      if (run.commandSummaries.isNotEmpty)
        'Commands: ${run.commandSummaries.map(_redact).join(" | ")}',
      if (run.tokenUsage.isNotEmpty)
        'Tokens: ${run.tokenUsage.formattedInputOutput}',
      if (run.inputPreview?.isNotEmpty == true)
        'Input: ${_redact(run.inputPreview!)}',
      if (run.outputPreview?.isNotEmpty == true)
        'Output: ${_redact(run.outputPreview!)}',
      if (run.error?.isNotEmpty == true) 'Error: ${_redact(run.error!)}',
      if (run.events.isNotEmpty) 'Events:',
      ...run.events
          .take(12)
          .map(
            (event) =>
                '- ${event.timestamp.toIso8601String()} '
                '${event.type.name}: ${_redact(event.message)}'
                '${event.metadata.isEmpty ? "" : " ${_redact(event.metadata.toString())}"}',
          ),
      if (run.spans.isNotEmpty) 'Spans:',
      ...run.spans
          .take(12)
          .map(
            (span) =>
                '- ${span.kind.name}: ${span.name}'
                '${span.detail == null ? "" : " ${_redact(span.detail!)}"}',
          ),
    ].join('\n');
  }

  String _redact(String value) {
    var redacted = value.replaceAllMapped(
      RegExp(
        r'''(api[_-]?key|token|secret|password|authorization)\s*[:=]\s*["']?[^,}\s"']+''',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=[redacted]',
    );
    redacted = redacted.replaceAll(
      RegExp(r'bearer\s+[a-z0-9._\-]+', caseSensitive: false),
      'Bearer [redacted]',
    );
    return redacted;
  }
}
