import 'package:circuit_ide/models/agent_run.dart';
import 'package:circuit_ide/models/run_diagnostics_summary.dart';
import 'package:circuit_ide/models/token_usage.dart';
import 'package:circuit_ide/enums/event_type.dart';
import 'package:circuit_ide/state/agent_run_provider.dart';
import 'package:circuit_ide/state/connection_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AgentRunController tracks active and completed runs', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(agentRunProvider.notifier);
    notifier.startRun(
      kind: AgentRunKind.chat,
      model: 'gpt-5-nano',
      message: 'hello',
      title: 'Chat',
      inputPreview: 'hello',
      retryPrompt: 'hello',
      contextAttachmentCount: 2,
    );
    notifier.markStreaming(AgentRunKind.chat);
    notifier.updateUsage(
      AgentRunKind.chat,
      const TokenUsage(promptTokens: 10, completionTokens: 5, totalTokens: 15),
    );

    expect(
      container.read(agentRunProvider).activeChatRun?.status,
      AgentRunStatus.streaming,
    );
    expect(
      container.read(agentRunProvider).activeChatRun?.tokenUsage.totalTokens,
      15,
    );
    expect(container.read(agentRunProvider).activeChatRun?.title, 'Chat');
    expect(
      container.read(agentRunProvider).activeChatRun?.contextAttachmentCount,
      2,
    );

    notifier.finishRun(AgentRunKind.chat, outputPreview: 'hi there');

    expect(container.read(agentRunProvider).activeChatRun, isNull);
    expect(
      container.read(agentRunProvider).recentRuns.first.status,
      AgentRunStatus.succeeded,
    );
    expect(
      container.read(agentRunProvider).recentRuns.first.outputPreview,
      'hi there',
    );
    expect(
      container.read(agentRunProvider).recentRuns.first.retryPrompt,
      'hello',
    );
  });

  test('AgentRunController keeps failure and cancellation metadata', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(agentRunProvider.notifier);
    notifier.startRun(
      kind: AgentRunKind.backgroundTask,
      model: 'gemini-3.1-flash-lite',
      message: 'index workspace',
      title: 'Index Workspace',
      inputPreview: 'index workspace',
    );
    notifier.finishRun(AgentRunKind.backgroundTask, error: 'Timed out');

    final failed = container.read(agentRunProvider).recentRuns.first;
    expect(failed.status, AgentRunStatus.failed);
    expect(failed.error, 'Timed out');
    expect(failed.title, 'Index Workspace');

    notifier.startRun(
      kind: AgentRunKind.chat,
      model: 'gpt-5-nano',
      message: 'hello',
      retryPrompt: 'hello',
    );
    notifier.requestCancel(AgentRunKind.chat);
    notifier.finishRun(AgentRunKind.chat, cancelled: true);

    final cancelled = container.read(agentRunProvider).recentRuns.first;
    expect(cancelled.status, AgentRunStatus.cancelled);
    expect(cancelled.cancelRequested, isTrue);
    expect(cancelled.retryPrompt, 'hello');
  });

  test('AgentRunController ignores stale request events', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(agentRunProvider.notifier);
    notifier.startRun(
      id: 'current-request',
      kind: AgentRunKind.chat,
      model: 'gpt-5-nano',
      message: 'hello',
    );

    final service = container.read(agentServiceProvider);
    service.events.emit(EventType.messageChunk, {
      'requestId': 'stale-request',
      'content': 'old',
    });

    expect(
      container.read(agentRunProvider).activeChatRun?.status,
      AgentRunStatus.running,
    );

    service.events.emit(EventType.messageChunk, {'content': 'missing id'});

    expect(
      container.read(agentRunProvider).activeChatRun?.status,
      AgentRunStatus.running,
      reason:
          'Legacy runtime events without a request id must not mutate Studio-owned runs.',
    );

    service.events.emit(EventType.messageChunk, {
      'requestId': 'current-request',
      'content': 'new',
    });

    expect(
      container.read(agentRunProvider).activeChatRun?.status,
      AgentRunStatus.streaming,
    );
  });

  test('RunDiagnosticsSummary includes request identity and events', () {
    final run = AgentRun(
      id: 'run-1',
      kind: AgentRunKind.chat,
      status: AgentRunStatus.failed,
      model: 'gpt-5-nano',
      startedAt: DateTime(2026, 5, 25),
      endedAt: DateTime(2026, 5, 25, 0, 0, 1),
      error: 'Timed out',
      events: [
        AgentRunEvent(
          type: AgentRunEventType.providerRequest,
          timestamp: DateTime(2026, 5, 25),
          message: 'Provider request started',
        ),
      ],
    );

    final summary = RunDiagnosticsSummary(run).serialize();

    expect(summary, contains('Request ID: run-1'));
    expect(summary, contains('Status: failed'));
    expect(summary, contains('Timed out'));
    expect(summary, contains('Provider request started'));
  });
}
