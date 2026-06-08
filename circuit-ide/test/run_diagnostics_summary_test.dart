import 'package:circuit_ide/models/agent_run.dart';
import 'package:circuit_ide/models/run_diagnostics_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RunDiagnosticsSummary includes artifacts and redacts secrets', () {
    final run = AgentRun(
      id: 'run-1',
      kind: AgentRunKind.chat,
      status: AgentRunStatus.failed,
      model: 'gpt-5-nano',
      inputPreview: 'token=abc123',
      startedAt: DateTime(2026),
      error: 'api_key: secret-value',
      changedFiles: const ['lib/main.dart'],
      commandSummaries: const ['curl -H "Authorization: Bearer abc"'],
      checkpointId: 'checkpoint-1',
      events: [
        AgentRunEvent(
          type: AgentRunEventType.commandRun,
          timestamp: DateTime(2026),
          message: 'secret=abc123',
        ),
      ],
      spans: [
        AgentTraceSpan(
          id: 'span-1',
          requestId: 'run-1',
          kind: AgentTraceSpanKind.commandRun,
          name: 'run_command',
          startedAt: DateTime(2026),
          detail: 'password=hunter2',
        ),
      ],
    );

    final summary = RunDiagnosticsSummary(run).serialize();

    expect(summary, contains('Checkpoint: checkpoint-1'));
    expect(summary, contains('Changed files: lib/main.dart'));
    expect(summary, contains('Commands: curl -H "Authorization=[redacted]'));
    expect(summary, isNot(contains('secret-value')));
    expect(summary, isNot(contains('hunter2')));
  });
}
