import 'package:circuit_ide/models/agent_run.dart';
import 'package:circuit_ide/models/token_usage.dart';
import 'package:circuit_ide/state/agent_run_provider.dart';
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
      message: 'map workspace',
      title: 'Map Workspace',
      inputPreview: 'map workspace',
    );
    notifier.finishRun(AgentRunKind.backgroundTask, error: 'Timed out');

    final failed = container.read(agentRunProvider).recentRuns.first;
    expect(failed.status, AgentRunStatus.failed);
    expect(failed.error, 'Timed out');
    expect(failed.title, 'Map Workspace');

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
}
