import 'package:circuit_ide/enums/event_type.dart';
import 'package:circuit_ide/models/accepted_plan_context.dart';
import 'package:circuit_ide/models/confirmation_request.dart';
import 'package:circuit_ide/models/agent_workspace.dart';
import 'package:circuit_ide/models/agent_request.dart';
import 'package:circuit_ide/models/agent_run.dart';
import 'package:circuit_ide/models/provider_lifecycle_event.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/models/studio_request_lifecycle.dart';
import 'package:circuit_ide/models/studio_shell.dart';
import 'package:circuit_ide/models/studio_source_artifact.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/models/token_usage.dart';
import 'package:circuit_ide/models/tool_call_info.dart';
import 'package:circuit_ide/models/tool_result_envelope.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:circuit_ide/services/event_bus.dart';
import 'package:circuit_ide/state/patch_proposal_provider.dart';
import 'package:circuit_ide/state/agent_workspace_provider.dart';
import 'package:circuit_ide/state/agent_request_provider.dart';
import 'package:circuit_ide/state/agent_run_provider.dart';
import 'package:circuit_ide/state/studio_request_lifecycle_provider.dart';
import 'package:circuit_ide/state/studio_shell_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/state/studio_turn_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _lifecycleContainer() {
  return ProviderContainer();
}

final _runtimeEventsByContainer = Expando<Map<String, EventBus>>(
  'studio-lifecycle-test-events',
);

EventBus _runtimeEventsFor(ProviderContainer container, String requestId) {
  final eventsByRequest = _runtimeEventsByContainer[container] ??=
      <String, EventBus>{};
  return eventsByRequest.putIfAbsent(requestId, () {
    final events = EventBus();
    container
        .read(studioRequestLifecycleProvider.notifier)
        .attachRuntimeEvents(requestId, events);
    return events;
  });
}

void _emitRuntimeEvent(
  ProviderContainer container,
  String requestId,
  EventType type,
  Map<String, dynamic> data,
) {
  final eventData = {...data, 'requestId': requestId};
  _runtimeEventsFor(container, requestId).emit(type, eventData);
}

void main() {
  test('unattached runtime events are ignored by Studio lifecycle', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final thread = container
        .read(studioThreadProvider.notifier)
        .ensureThread(title: 'Review app', model: 'gpt-5-nano');
    const summary = StudioContextSummary(
      rootPath: '/tmp/project',
      projectLabel: 'project',
      includedItemCount: 2,
      estimatedTokens: 200,
    );
    _registerTurn(container, 'req-global-ignored', thread.id, summary: summary);
    container
        .read(studioRequestLifecycleProvider.notifier)
        .registerRequest(
          requestId: 'req-global-ignored',
          threadId: thread.id,
          model: 'gpt-5-nano',
          contextSummary: summary,
        );

    final unattachedEvents = EventBus();
    unattachedEvents.emit(EventType.messageChunk, {
      'requestId': 'req-global-ignored',
      'content': 'legacy chunk',
    });

    final updated = container.read(studioThreadProvider).selectedThread!;
    expect(updated.status, StudioThreadStatus.preflighting);
    expect(updated.streamingContent, isEmpty);
    expect(updated.turns.single.assistantDraft, isEmpty);
  });

  test('legacy agent run events are ignored by Studio lifecycle', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final thread = container
        .read(studioThreadProvider.notifier)
        .ensureThread(title: 'Review app', model: 'gpt-5-nano');
    const summary = StudioContextSummary(
      rootPath: '/tmp/project',
      projectLabel: 'project',
      includedItemCount: 2,
      estimatedTokens: 200,
    );
    _registerTurn(
      container,
      'req-legacy-agent-run-ignored',
      thread.id,
      summary: summary,
    );
    container
        .read(studioRequestLifecycleProvider.notifier)
        .registerRequest(
          requestId: 'req-legacy-agent-run-ignored',
          threadId: thread.id,
          model: 'gpt-5-nano',
          contextSummary: summary,
        );

    _emitRuntimeEvent(
      container,
      'req-legacy-agent-run-ignored',
      EventType.agentRunEvent,
      {'event': 'provider_lifecycle', 'kind': 'first_text_delta'},
    );

    final updated = container.read(studioThreadProvider).selectedThread!;
    expect(updated.status, StudioThreadStatus.preflighting);
    expect(updated.phase, StudioSendPhase.preflighting);
    expect(updated.turns.single.status, StudioTurnStatus.waitingForModel);
    expect(updated.turns.single.assistantDraft, isEmpty);
    expect(
      container
          .read(studioRequestLifecycleProvider)
          .active('req-legacy-agent-run-ignored')
          ?.lastEventKind,
      StudioRequestLifecycleEventKind.requestStarted,
    );
  });

  test('streaming chunks update the registered Studio turn live', () async {
    final container = _lifecycleContainer();
    addTearDown(container.dispose);

    final thread = container
        .read(studioThreadProvider.notifier)
        .ensureThread(title: 'Review app', model: 'gpt-5-nano');
    const summary = StudioContextSummary(
      rootPath: '/tmp/project',
      projectLabel: 'project',
      includedItemCount: 2,
      estimatedTokens: 200,
    );
    _registerTurn(container, 'req-stream', thread.id, summary: summary);
    container
        .read(studioRequestLifecycleProvider.notifier)
        .registerRequest(
          requestId: 'req-stream',
          threadId: thread.id,
          model: 'gpt-5-nano',
          contextSummary: summary,
        );

    _emitRuntimeEvent(container, 'req-stream', EventType.messageChunk, {
      'requestId': 'req-stream',
      'content': 'Hello',
    });
    _emitRuntimeEvent(container, 'req-stream', EventType.messageChunk, {
      'requestId': 'req-stream',
      'content': ' world',
    });
    await Future<void>.delayed(const Duration(milliseconds: 120));

    final updated = container.read(studioThreadProvider).selectedThread!;
    expect(updated.status, StudioThreadStatus.streaming);
    expect(updated.phase, StudioSendPhase.streaming);
    expect(updated.streamingContent, isEmpty);
    expect(updated.turns.single.assistantDraft, 'Hello world');
  });

  test(
    'message completion records assistant content on the turn and marks thread done',
    () async {
      final container = _lifecycleContainer();
      addTearDown(container.dispose);
      await _waitForThreadStore(container);

      final thread = container
          .read(studioThreadProvider.notifier)
          .ensureThread(title: 'Say hi', model: 'gpt-5-nano');
      const summary = StudioContextSummary(projectLabel: 'No project selected');
      _registerTurn(container, 'req-done', thread.id, summary: summary);
      container
          .read(studioRequestLifecycleProvider.notifier)
          .registerRequest(
            requestId: 'req-done',
            threadId: thread.id,
            model: 'gpt-5-nano',
            contextSummary: summary,
          );

      _emitRuntimeEvent(container, 'req-done', EventType.messageCompleted, {
        'requestId': 'req-done',
        'content': 'Hi! How can I help?',
        'toolCalls': const [],
        'lastUsage': const TokenUsage(
          promptTokens: 50,
          cachedInputTokens: 20,
          completionTokens: 10,
          reasoningTokens: 4,
          toolTokens: 2,
          totalTokens: 60,
        ),
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updated = container
          .read(studioThreadProvider)
          .threads
          .firstWhere((candidate) => candidate.id == thread.id);
      expect(updated.status, StudioThreadStatus.done);
      expect(updated.phase, StudioSendPhase.completed);
      expect(updated.streamingContent, isEmpty);
      expect(updated.tokenUsage.totalTokens, 0);
      expect(updated.lastRequestTokenUsage.promptTokens, 50);
      expect(updated.lastRequestTokenUsage.cachedInputTokens, 20);
      expect(updated.lastRequestTokenUsage.completionTokens, 10);
      expect(updated.lastRequestTokenUsage.reasoningTokens, 4);
      expect(updated.lastRequestTokenUsage.toolTokens, 2);
      expect(updated.lastRequestTokenUsage.totalTokens, 60);
      expect(updated.messages, isEmpty);
      final turn = updated.turns.single;
      expect(turn.status, StudioTurnStatus.completed);
      expect(
        turn.events
            .where(
              (event) => event.type == StudioTurnEventType.assistantMessage,
            )
            .single
            .content,
        'Hi! How can I help?',
      );
      expect(
        container
            .read(studioRequestLifecycleProvider)
            .find('req-done')
            ?.lastEventKind,
        StudioRequestLifecycleEventKind.completed,
      );
    },
  );

  test(
    'research lifecycle persists evidence and visible source-review phases',
    () async {
      final container = _lifecycleContainer();
      addTearDown(container.dispose);
      await _waitForThreadStore(container);

      final thread = container
          .read(studioThreadProvider.notifier)
          .ensureThread(title: 'Research rollout', model: 'gpt-5-nano');
      const summary = StudioContextSummary(projectLabel: 'No project selected');
      _registerTurn(
        container,
        'req-research',
        thread.id,
        summary: summary,
        modelPrompt: 'Research Mode is enabled.\nResearch question: rollout',
        isResearch: true,
      );
      container
          .read(studioRequestLifecycleProvider.notifier)
          .registerRequest(
            requestId: 'req-research',
            threadId: thread.id,
            model: 'gpt-5-nano',
            contextSummary: summary,
            intent: TurnIntent.ask,
          );

      _emitRuntimeEvent(
        container,
        'req-research',
        EventType.toolResultRecorded,
        {
          'result': const ToolResultEnvelope(
            toolCallId: 'search-1',
            toolName: 'web_search',
            status: ToolResultStatus.success,
            summary: 'Found candidates.',
          ),
        },
      );
      _emitRuntimeEvent(
        container,
        'req-research',
        EventType.toolResultRecorded,
        {
          'result': const ToolResultEnvelope(
            toolCallId: 'fetch-1',
            toolName: 'web_fetch',
            status: ToolResultStatus.success,
            summary: 'Fetched official rollout record.',
            data: {
              'rawResult': '''
# Official rollout record
Published: 2026-07-12
Source: https://agency.gov/rollout?tracking=private
Checked: 2026-07-13
''',
            },
          ),
        },
      );
      _emitRuntimeEvent(container, 'req-research', EventType.messageCompleted, {
        'content': '''
The rollout is active. https://agency.gov/rollout?tracking=private

## Evidence table
| Claim | Sources | Evidence status |
| --- | --- | --- |
| The rollout is active. | https://agency.gov/rollout | Direct source attached |

## Sources
- https://agency.gov/rollout — Checked: 2026-07-13
''',
        'toolCalls': const [],
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updated = container
          .read(studioThreadProvider)
          .threads
          .firstWhere((candidate) => candidate.id == thread.id);
      final turn = updated.turns.single;
      expect(
        turn.steps
            .singleWhere((step) => step.step == TurnStep.sourceAcquisition)
            .status,
        TurnStepStatus.completed,
      );
      expect(
        turn.steps
            .singleWhere((step) => step.step == TurnStep.evidenceReview)
            .status,
        TurnStepStatus.completed,
      );
      final evidence = updated.sourceArtifacts.singleWhere(
        (artifact) => artifact.id == 'research-evidence-${turn.id}',
      );
      expect(evidence.kind, StudioSourceArtifactKind.evidence);
      expect(evidence.value, contains('## Evidence table'));
      expect(evidence.value, isNot(contains('tracking=private')));
      final assistant = turn.events.singleWhere(
        (event) => event.type == StudioTurnEventType.assistantMessage,
      );
      expect(assistant.content, contains('The rollout is active.'));
      expect(assistant.content, contains('Research evidence report saved'));
      expect(assistant.content, isNot(contains('## Evidence table')));
    },
  );

  test('research outcome repair is shown as a bounded source retry', () {
    final container = _lifecycleContainer();
    addTearDown(container.dispose);

    final thread = container
        .read(studioThreadProvider.notifier)
        .ensureThread(title: 'Research retry', model: 'gpt-5-nano');
    const summary = StudioContextSummary(projectLabel: 'project');
    _registerTurn(
      container,
      'req-research-retry',
      thread.id,
      summary: summary,
      modelPrompt: 'Research Mode is enabled.\nResearch question: rollout',
      isResearch: true,
    );
    container
        .read(studioRequestLifecycleProvider.notifier)
        .registerRequest(
          requestId: 'req-research-retry',
          threadId: thread.id,
          model: 'gpt-5-nano',
          contextSummary: summary,
          intent: TurnIntent.ask,
        );

    _emitRuntimeEvent(
      container,
      'req-research-retry',
      EventType.providerLifecycle,
      {
        'event': ProviderLifecycleEvent(
          requestId: 'req-research-retry',
          kind: ProviderLifecycleEventKind.outcomeRepair,
          timestamp: DateTime.utc(2026, 7, 13),
          model: 'gpt-5-nano',
          detail: 'One structured research repair is acquiring corroboration.',
        ),
      },
    );

    final turn = container
        .read(studioThreadProvider)
        .selectedThread!
        .turns
        .single;
    final sourceAcquisition = turn.steps.singleWhere(
      (step) => step.step == TurnStep.sourceAcquisition,
    );
    expect(sourceAcquisition.status, TurnStepStatus.running);
    expect(sourceAcquisition.title, 'Independent-source retry');
    expect(
      turn.events
          .where((event) => event.type == StudioTurnEventType.progress)
          .singleWhere((event) => event.title == 'Retrying source acquisition')
          .detail,
      'Checking one more approved source path before finalizing evidence.',
    );
  });

  test(
    'explicit completeRequest does not mutate contradictory legacy request state',
    () async {
      final container = _lifecycleContainer();
      addTearDown(container.dispose);
      await _waitForThreadStore(container);

      final thread = container
          .read(studioThreadProvider.notifier)
          .ensureThread(title: 'Direct complete', model: 'gpt-5-nano');
      const summary = StudioContextSummary(projectLabel: 'project');
      _registerTurn(
        container,
        'req-direct-complete',
        thread.id,
        summary: summary,
      );
      container
          .read(studioRequestLifecycleProvider.notifier)
          .registerRequest(
            requestId: 'req-direct-complete',
            threadId: thread.id,
            model: 'gpt-5-nano',
            contextSummary: summary,
          );
      container
          .read(agentRequestProvider.notifier)
          .start(
            lane: AgentRequestLane.chat,
            requestId: 'req-direct-complete',
            model: 'gpt-5-nano',
          );
      container
          .read(agentRunProvider.notifier)
          .startRun(
            id: 'req-direct-complete',
            kind: AgentRunKind.chat,
            model: 'gpt-5-nano',
            message: 'Lifecycle direct complete',
          );

      container
          .read(studioRequestLifecycleProvider.notifier)
          .completeRequest(
            'req-direct-complete',
            message: 'Runtime completed.',
          );

      final updated = container
          .read(studioThreadProvider)
          .threads
          .firstWhere((candidate) => candidate.id == thread.id);
      expect(updated.status, StudioThreadStatus.done);
      expect(updated.phase, StudioSendPhase.completed);
      expect(updated.turns.single.status, StudioTurnStatus.completed);
      expect(
        container
            .read(studioRequestLifecycleProvider)
            .find('req-direct-complete')
            ?.lastEventKind,
        StudioRequestLifecycleEventKind.completed,
      );
      expect(
        container.read(agentRequestProvider)[AgentRequestLane.chat]?.status,
        AgentRequestStatus.running,
      );
      expect(
        container.read(agentRunProvider).activeRuns[AgentRunKind.chat]?.status,
        AgentRunStatus.running,
      );
    },
  );

  test(
    'explicit completeRequest completes associated workspace task',
    () async {
      final container = _lifecycleContainer();
      addTearDown(container.dispose);
      await _waitForThreadStore(container);
      await _waitForWorkspaceStore(container);

      final task = container
          .read(agentWorkspaceProvider.notifier)
          .startTask(goal: 'Complete lifecycle task');
      final thread = container
          .read(studioThreadProvider.notifier)
          .ensureThread(
            taskId: task.id,
            title: 'Lifecycle task',
            model: 'gpt-5-nano',
          );
      const summary = StudioContextSummary(projectLabel: 'project');
      _registerTurn(
        container,
        'req-task-complete',
        thread.id,
        summary: summary,
      );
      container
          .read(studioRequestLifecycleProvider.notifier)
          .registerRequest(
            requestId: 'req-task-complete',
            threadId: thread.id,
            taskId: task.id,
            model: 'gpt-5-nano',
            contextSummary: summary,
          );

      container
          .read(studioRequestLifecycleProvider.notifier)
          .completeRequest('req-task-complete', message: 'Task done.');

      final updatedTask = container
          .read(agentWorkspaceProvider)
          .tasks
          .firstWhere((candidate) => candidate.id == task.id);
      expect(updatedTask.status, AgentTaskStatus.completed);
      expect(updatedTask.result, 'Task done.');
    },
  );

  test('explicit cancelRequest cancels associated workspace task', () async {
    final container = _lifecycleContainer();
    addTearDown(container.dispose);
    await _waitForThreadStore(container);
    await _waitForWorkspaceStore(container);

    final task = container
        .read(agentWorkspaceProvider.notifier)
        .startTask(goal: 'Cancel lifecycle task');
    final thread = container
        .read(studioThreadProvider.notifier)
        .ensureThread(
          taskId: task.id,
          title: 'Lifecycle task',
          model: 'gpt-5-nano',
        );
    const summary = StudioContextSummary(projectLabel: 'project');
    _registerTurn(container, 'req-task-cancel', thread.id, summary: summary);
    container
        .read(studioRequestLifecycleProvider.notifier)
        .registerRequest(
          requestId: 'req-task-cancel',
          threadId: thread.id,
          taskId: task.id,
          model: 'gpt-5-nano',
          contextSummary: summary,
        );
    container
        .read(agentRequestProvider.notifier)
        .start(
          lane: AgentRequestLane.chat,
          requestId: 'req-task-cancel',
          model: 'gpt-5-nano',
        );
    container
        .read(agentRunProvider.notifier)
        .startRun(
          id: 'req-task-cancel',
          kind: AgentRunKind.chat,
          model: 'gpt-5-nano',
          message: 'Lifecycle direct cancel',
        );

    container
        .read(studioRequestLifecycleProvider.notifier)
        .cancelRequest('req-task-cancel', message: 'User cancelled.');

    final updatedThread = container
        .read(studioThreadProvider)
        .threads
        .firstWhere((candidate) => candidate.id == thread.id);
    expect(updatedThread.status, StudioThreadStatus.cancelled);
    expect(updatedThread.turns.single.status, StudioTurnStatus.cancelled);
    final updatedTask = container
        .read(agentWorkspaceProvider)
        .tasks
        .firstWhere((candidate) => candidate.id == task.id);
    expect(updatedTask.status, AgentTaskStatus.cancelled);
    expect(
      container.read(agentRequestProvider)[AgentRequestLane.chat]?.status,
      AgentRequestStatus.running,
    );
    expect(
      container.read(agentRunProvider).activeRuns[AgentRunKind.chat]?.status,
      AgentRunStatus.running,
    );
  });

  test(
    'completed requests ignore stale provider failure diagnostics',
    () async {
      final container = _lifecycleContainer();
      addTearDown(container.dispose);
      await _waitForThreadStore(container);

      final thread = container
          .read(studioThreadProvider.notifier)
          .ensureThread(title: 'Finish cleanly', model: 'gpt-5-nano');
      const summary = StudioContextSummary(projectLabel: 'project');
      _registerTurn(
        container,
        'req-stale-provider',
        thread.id,
        summary: summary,
      );
      container
          .read(studioRequestLifecycleProvider.notifier)
          .registerRequest(
            requestId: 'req-stale-provider',
            threadId: thread.id,
            model: 'gpt-5-nano',
            contextSummary: summary,
          );

      _emitRuntimeEvent(
        container,
        'req-stale-provider',
        EventType.messageCompleted,
        {
          'requestId': 'req-stale-provider',
          'content': 'Done.',
          'toolCalls': const [],
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      _emitRuntimeEvent(
        container,
        'req-stale-provider',
        EventType.providerLifecycle,
        {
          'requestId': 'req-stale-provider',
          'event': ProviderLifecycleEvent(
            requestId: 'req-stale-provider',
            kind: ProviderLifecycleEventKind.failed,
            timestamp: DateTime(2026, 1, 1, 0, 0, 1),
            model: 'gpt-5-nano',
            detail: 'Late provider failure should be ignored.',
          ),
        },
      );

      final updated = container
          .read(studioThreadProvider)
          .threads
          .firstWhere((candidate) => candidate.id == thread.id);
      expect(updated.status, StudioThreadStatus.done);
      expect(updated.phase, StudioSendPhase.completed);
      expect(updated.lastError, isNull);
      expect(updated.turns.single.status, StudioTurnStatus.completed);
      expect(
        updated.turns.single.providerDiagnostics
            .map((event) => event.kind)
            .toList(),
        isNot(contains(ProviderLifecycleEventKind.failed)),
      );
      expect(
        container
            .read(studioRequestLifecycleProvider)
            .find('req-stale-provider')
            ?.lastEventKind,
        StudioRequestLifecycleEventKind.completed,
      );
    },
  );

  test(
    'provider completion diagnostic does not downgrade streaming turn state',
    () {
      final container = _lifecycleContainer();
      addTearDown(container.dispose);

      final thread = container
          .read(studioThreadProvider.notifier)
          .ensureThread(title: 'Streaming answer', model: 'gpt-5-nano');
      const summary = StudioContextSummary(projectLabel: 'project');
      _registerTurn(
        container,
        'req-provider-completed',
        thread.id,
        summary: summary,
      );
      container
          .read(studioRequestLifecycleProvider.notifier)
          .registerRequest(
            requestId: 'req-provider-completed',
            threadId: thread.id,
            model: 'gpt-5-nano',
            contextSummary: summary,
          );

      _emitRuntimeEvent(
        container,
        'req-provider-completed',
        EventType.providerLifecycle,
        {
          'requestId': 'req-provider-completed',
          'event': ProviderLifecycleEvent(
            requestId: 'req-provider-completed',
            kind: ProviderLifecycleEventKind.firstTextDelta,
            timestamp: DateTime(2026),
            model: 'gpt-5-nano',
          ),
        },
      );
      expect(
        container
            .read(studioThreadProvider)
            .selectedThread!
            .turns
            .single
            .status,
        StudioTurnStatus.streaming,
      );

      _emitRuntimeEvent(
        container,
        'req-provider-completed',
        EventType.providerLifecycle,
        {
          'requestId': 'req-provider-completed',
          'event': ProviderLifecycleEvent(
            requestId: 'req-provider-completed',
            kind: ProviderLifecycleEventKind.completed,
            timestamp: DateTime(2026, 1, 1, 0, 0, 1),
            model: 'gpt-5-nano',
            detail: 'Provider completed before messageCompleted.',
          ),
        },
      );

      final updated = container.read(studioThreadProvider).selectedThread!;
      expect(updated.turns.single.status, StudioTurnStatus.streaming);
      expect(
        updated.turns.single.providerDiagnostics.map((event) => event.kind),
        contains(ProviderLifecycleEventKind.completed),
      );
      expect(
        container
            .read(studioRequestLifecycleProvider)
            .find('req-provider-completed')
            ?.lastEventKind,
        StudioRequestLifecycleEventKind.completed,
      );
    },
  );

  test(
    'provider fallback and tool-only diagnostics update progress clearly',
    () {
      final container = _lifecycleContainer();
      addTearDown(container.dispose);

      final thread = container
          .read(studioThreadProvider.notifier)
          .ensureThread(
            title: 'Tool-only provider response',
            model: 'gpt-5-nano',
          );
      const summary = StudioContextSummary(projectLabel: 'project');
      _registerTurn(
        container,
        'req-provider-fallback',
        thread.id,
        summary: summary,
      );
      container
          .read(studioRequestLifecycleProvider.notifier)
          .registerRequest(
            requestId: 'req-provider-fallback',
            threadId: thread.id,
            model: 'gpt-5-nano',
            contextSummary: summary,
          );

      final service = _runtimeEventsFor(container, 'req-provider-fallback');
      for (final diagnostic in [
        ProviderLifecycleEventKind.nonSseJson,
        ProviderLifecycleEventKind.jsonFallback,
        ProviderLifecycleEventKind.toolOnly,
      ]) {
        service.emit(EventType.providerLifecycle, {
          'requestId': 'req-provider-fallback',
          'event': ProviderLifecycleEvent(
            requestId: 'req-provider-fallback',
            kind: diagnostic,
            timestamp: DateTime(2026),
            model: 'gpt-5-nano',
            detail: switch (diagnostic) {
              ProviderLifecycleEventKind.nonSseJson =>
                'Circuit returned application/json instead of SSE.',
              ProviderLifecycleEventKind.jsonFallback =>
                'Circuit parsed a non-streaming JSON response.',
              ProviderLifecycleEventKind.toolOnly =>
                'Circuit returned tool calls without assistant text.',
              _ => diagnostic.name,
            },
          ),
        });
      }

      final updated = container.read(studioThreadProvider).selectedThread!;
      final turn = updated.turns.single;
      final progress = turn.events
          .where((event) => event.type == StudioTurnEventType.progress)
          .single;
      expect(progress.title, 'Tool-only response');
      expect(progress.detail, contains('tool calls without assistant text'));
      expect(turn.status, StudioTurnStatus.toolRunning);
      expect(
        turn.providerDiagnostics.map((event) => event.kind),
        containsAll([
          ProviderLifecycleEventKind.nonSseJson,
          ProviderLifecycleEventKind.jsonFallback,
          ProviderLifecycleEventKind.toolOnly,
        ]),
      );
      expect(
        container
            .read(studioRequestLifecycleProvider)
            .find('req-provider-fallback')
            ?.lastEventKind,
        StudioRequestLifecycleEventKind.toolRunning,
      );
    },
  );

  test(
    'outcome rejection stays recoverable when a reviewable patch exists',
    () {
      final container = _lifecycleContainer();
      addTearDown(container.dispose);

      final thread = container
          .read(studioThreadProvider.notifier)
          .ensureThread(title: 'Patch needs revision', model: 'gpt-5-nano');
      const summary = StudioContextSummary(projectLabel: 'project');
      _registerTurn(
        container,
        'req-reviewable-outcome',
        thread.id,
        summary: summary,
      );
      container
          .read(studioRequestLifecycleProvider.notifier)
          .registerRequest(
            requestId: 'req-reviewable-outcome',
            threadId: thread.id,
            model: 'gpt-5-nano',
            contextSummary: summary,
          );
      container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Prepared changes',
            runId: 'req-reviewable-outcome',
            edits: const [
              ProposedFileEdit(
                path: 'lib/app.dart',
                type: ProposedFileEditType.modify,
                before: 'old',
                after: 'new',
              ),
            ],
          );

      _runtimeEventsFor(
        container,
        'req-reviewable-outcome',
      ).emit(EventType.providerLifecycle, {
        'requestId': 'req-reviewable-outcome',
        'event': ProviderLifecycleEvent(
          requestId: 'req-reviewable-outcome',
          kind: ProviderLifecycleEventKind.outcomeRejected,
          timestamp: DateTime(2026),
          model: 'gpt-5-nano',
          detail:
              'Runtime rejected the model outcome, but a patch can be revised.',
        ),
      });

      final updated = container.read(studioThreadProvider).selectedThread!;
      final turn = updated.turns.single;
      expect(turn.status, StudioTurnStatus.toolRunning);
      expect(
        turn.providerDiagnostics.map((event) => event.kind),
        contains(ProviderLifecycleEventKind.outcomeRejected),
      );
      expect(
        container
            .read(studioRequestLifecycleProvider)
            .find('req-reviewable-outcome')
            ?.lastEventKind,
        StudioRequestLifecycleEventKind.toolRunning,
      );
    },
  );

  test(
    'message completion summary uses structured tool result evidence',
    () async {
      final container = _lifecycleContainer();
      addTearDown(container.dispose);
      await _waitForThreadStore(container);

      final thread = container
          .read(studioThreadProvider.notifier)
          .ensureThread(title: 'Verify app', model: 'gpt-5-nano');
      const summary = StudioContextSummary(projectLabel: 'project');
      _registerTurn(container, 'req-summary', thread.id, summary: summary);
      container
          .read(studioRequestLifecycleProvider.notifier)
          .registerRequest(
            requestId: 'req-summary',
            threadId: thread.id,
            model: 'gpt-5-nano',
            contextSummary: summary,
          );

      _emitRuntimeEvent(
        container,
        'req-summary',
        EventType.toolResultRecorded,
        {
          'requestId': 'req-summary',
          'result': const ToolResultEnvelope(
            toolCallId: 'cmd-1',
            toolName: 'run_command',
            status: ToolResultStatus.error,
            summary: 'flutter test failed.',
            stdout: '[exit code: 1]',
            diagnostic: '[exit code: 1]',
            data: {'exitCode': 1},
          ),
        },
      );
      _emitRuntimeEvent(container, 'req-summary', EventType.messageCompleted, {
        'requestId': 'req-summary',
        'content': 'I ran the requested check.',
        'toolCalls': const [],
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updated = container
          .read(studioThreadProvider)
          .threads
          .firstWhere((candidate) => candidate.id == thread.id);
      final turn = updated.turns.single;
      final completion = turn.events
          .where((event) => event.type == StudioTurnEventType.completionSummary)
          .single;
      expect(completion.title, 'Verification failed');
      expect(completion.detail, contains('Verification failed (exit 1)'));
      expect(completion.detail, contains('flutter test failed.'));
      expect(completion.detail, isNot('Ready for the next prompt.'));
    },
  );

  test('confirmationNeeded moves the thread into waiting for approval', () {
    final container = _lifecycleContainer();
    addTearDown(container.dispose);

    final thread = container
        .read(studioThreadProvider.notifier)
        .ensureThread(title: 'Run checks', model: 'gpt-5-nano');
    _registerTurn(
      container,
      'req-approval',
      thread.id,
      summary: const StudioContextSummary(projectLabel: 'project'),
    );
    container
        .read(studioRequestLifecycleProvider.notifier)
        .registerRequest(
          requestId: 'req-approval',
          threadId: thread.id,
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(projectLabel: 'project'),
        );

    final request = ConfirmationRequest(
      id: 'approval-1',
      toolCall: const ToolCallInfo(
        id: 'tool-1',
        name: 'run_command',
        arguments: {'command': 'npm test'},
      ),
      preview: 'npm test',
    );
    _emitRuntimeEvent(container, 'req-approval', EventType.confirmationNeeded, {
      'requestId': 'req-approval',
      'request': request,
    });

    final updated = container.read(studioThreadProvider).selectedThread!;
    expect(updated.status, StudioThreadStatus.waitingForApproval);
    expect(updated.phase, StudioSendPhase.waitingForApproval);
    final approval = updated.turns.single.events
        .where((event) => event.type == StudioTurnEventType.approvalRequest)
        .single;
    expect(approval.approvalId, request.id);
    expect(approval.approvalState, ApprovalRequestState.pending);
  });

  test('completeRequest expires pending approval and archives Studio turn', () {
    final container = _lifecycleContainer();
    addTearDown(container.dispose);

    final thread = container
        .read(studioThreadProvider.notifier)
        .ensureThread(title: 'Complete approval', model: 'gpt-5-nano');
    _registerTurn(
      container,
      'req-approval-complete',
      thread.id,
      summary: const StudioContextSummary(projectLabel: 'project'),
    );
    container
        .read(studioRequestLifecycleProvider.notifier)
        .registerRequest(
          requestId: 'req-approval-complete',
          threadId: thread.id,
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(projectLabel: 'project'),
        );

    _emitRuntimeEvent(
      container,
      'req-approval-complete',
      EventType.confirmationNeeded,
      {
        'requestId': 'req-approval-complete',
        'request': _approvalRequest('approval-complete'),
      },
    );
    container
        .read(studioRequestLifecycleProvider.notifier)
        .completeRequest(
          'req-approval-complete',
          message: 'Completed after approval wait.',
        );

    final updated = container
        .read(studioThreadProvider)
        .threads
        .firstWhere((candidate) => candidate.id == thread.id);
    final turn = updated.turns.single;
    final approval = turn.events
        .where((event) => event.type == StudioTurnEventType.approvalRequest)
        .single;
    expect(updated.status, StudioThreadStatus.done);
    expect(turn.status, StudioTurnStatus.completed);
    expect(approval.approvalState, ApprovalRequestState.expired);
    expect(
      container.read(studioTurnProvider).refForRequest('req-approval-complete'),
      isNull,
    );
    expect(
      container
          .read(studioTurnProvider)
          .archivedRefForRequest('req-approval-complete'),
      isNotNull,
    );
  });

  test('failRequest expires pending approval', () {
    final container = _lifecycleContainer();
    addTearDown(container.dispose);

    final thread = container
        .read(studioThreadProvider.notifier)
        .ensureThread(title: 'Fail approval', model: 'gpt-5-nano');
    _registerTurn(
      container,
      'req-approval-fail',
      thread.id,
      summary: const StudioContextSummary(projectLabel: 'project'),
    );
    container
        .read(studioRequestLifecycleProvider.notifier)
        .registerRequest(
          requestId: 'req-approval-fail',
          threadId: thread.id,
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(projectLabel: 'project'),
        );

    _emitRuntimeEvent(
      container,
      'req-approval-fail',
      EventType.confirmationNeeded,
      {
        'requestId': 'req-approval-fail',
        'request': _approvalRequest('approval-fail'),
      },
    );
    container
        .read(studioRequestLifecycleProvider.notifier)
        .failRequest('req-approval-fail', 'Provider failed.');

    final turn = container
        .read(studioThreadProvider)
        .threads
        .firstWhere((candidate) => candidate.id == thread.id)
        .turns
        .single;
    final approval = turn.events
        .where((event) => event.type == StudioTurnEventType.approvalRequest)
        .single;
    expect(turn.status, StudioTurnStatus.failed);
    expect(approval.approvalState, ApprovalRequestState.expired);
  });

  test('cancelRequest expires pending approval', () {
    final container = _lifecycleContainer();
    addTearDown(container.dispose);

    final thread = container
        .read(studioThreadProvider.notifier)
        .ensureThread(title: 'Cancel approval', model: 'gpt-5-nano');
    _registerTurn(
      container,
      'req-approval-cancel',
      thread.id,
      summary: const StudioContextSummary(projectLabel: 'project'),
    );
    container
        .read(studioRequestLifecycleProvider.notifier)
        .registerRequest(
          requestId: 'req-approval-cancel',
          threadId: thread.id,
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(projectLabel: 'project'),
        );

    _emitRuntimeEvent(
      container,
      'req-approval-cancel',
      EventType.confirmationNeeded,
      {
        'requestId': 'req-approval-cancel',
        'request': _approvalRequest('approval-cancel'),
      },
    );
    container
        .read(studioRequestLifecycleProvider.notifier)
        .cancelRequest('req-approval-cancel', message: 'User cancelled.');

    final turn = container
        .read(studioThreadProvider)
        .threads
        .firstWhere((candidate) => candidate.id == thread.id)
        .turns
        .single;
    final approval = turn.events
        .where((event) => event.type == StudioTurnEventType.approvalRequest)
        .single;
    expect(turn.status, StudioTurnStatus.cancelled);
    expect(approval.approvalState, ApprovalRequestState.expired);
  });

  test('stale approval events without runtime attachment are ignored', () {
    final container = _lifecycleContainer();
    addTearDown(container.dispose);

    final request = ConfirmationRequest(
      id: 'approval-text',
      toolCall: const ToolCallInfo(
        id: 'approval-text',
        name: 'edit_file',
        arguments: {'path': 'docs/topology.md'},
      ),
      preview: 'edit docs/topology.md',
    );
    final unattachedEvents = EventBus();
    unattachedEvents.emit(EventType.confirmationNeeded, {
      'requestId': 'stale-request',
      'request': request,
    });

    expect(container.read(studioThreadProvider).selectedThread, isNull);
    expect(
      container.read(studioRequestLifecycleProvider).activeRequests,
      isEmpty,
    );
  });

  test(
    'tool events render Codex-style activity rows and completion recap',
    () async {
      final container = _lifecycleContainer();
      addTearDown(container.dispose);
      await _waitForThreadStore(container);

      final thread = container
          .read(studioThreadProvider.notifier)
          .ensureThread(title: 'Implement feature', model: 'gpt-5-nano');
      _registerTurn(
        container,
        'req-tools',
        thread.id,
        summary: const StudioContextSummary(projectLabel: 'project'),
      );
      container
          .read(studioRequestLifecycleProvider.notifier)
          .registerRequest(
            requestId: 'req-tools',
            threadId: thread.id,
            model: 'gpt-5-nano',
            contextSummary: const StudioContextSummary(projectLabel: 'project'),
          );

      const command = ToolCallInfo(
        id: 'cmd-1',
        name: 'run_command',
        arguments: {'command': 'flutter analyze'},
      );
      _emitRuntimeEvent(container, 'req-tools', EventType.toolCallStarted, {
        'requestId': 'req-tools',
        'toolCall': command,
      });
      _emitRuntimeEvent(container, 'req-tools', EventType.toolCallCompleted, {
        'requestId': 'req-tools',
        'toolCall': command.copyWith(result: 'No issues found'),
      });
      const edit = ToolCallInfo(
        id: 'edit-1',
        name: 'edit_file',
        arguments: {'path': 'lib/main.dart'},
      );
      _emitRuntimeEvent(container, 'req-tools', EventType.toolCallCompleted, {
        'requestId': 'req-tools',
        'toolCall': edit.copyWith(result: 'Updated lib/main.dart'),
      });
      _emitRuntimeEvent(container, 'req-tools', EventType.messageCompleted, {
        'requestId': 'req-tools',
        'content': 'Done.',
        'toolCalls': const [],
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updated = container
          .read(studioThreadProvider)
          .threads
          .firstWhere((candidate) => candidate.id == thread.id);
      final events = updated.turns.single.events;
      expect(events.map((event) => event.title), contains('Ran command'));
      expect(events.map((event) => event.title), contains('Edited file'));
      expect(
        events.map((event) => event.title),
        contains('Ready for next prompt'),
      );
      expect(updated.sourceArtifacts, isEmpty);
    },
  );

  test('propose_patch creates a reviewable Studio plan artifact', () async {
    final container = _lifecycleContainer();
    addTearDown(container.dispose);
    await _waitForThreadStore(container);

    final thread = container
        .read(studioThreadProvider.notifier)
        .ensureThread(title: 'Build hello', model: 'gpt-5-nano');
    _registerTurn(
      container,
      'req-plan',
      thread.id,
      summary: const StudioContextSummary(projectLabel: 'project'),
    );
    container
        .read(studioRequestLifecycleProvider.notifier)
        .registerRequest(
          requestId: 'req-plan',
          threadId: thread.id,
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(projectLabel: 'project'),
          intent: TurnIntent.plan,
        );

    const patchTool = ToolCallInfo(
      id: 'patch-1',
      name: 'propose_patch',
      arguments: {
        'title': 'Create hello program',
        'summary': 'Create a small Python hello program.',
        'plan_markdown': '## Plan\n\n- Add hello.py\n- Add README.md',
        'files': [
          {
            'path': 'hello.py',
            'intent': 'Print Hello when executed',
            'operation': 'create',
            'content': 'print("Hello")\n',
          },
          {
            'path': 'README.md',
            'intent': 'Explain how to run it',
            'operation': 'modify',
          },
        ],
      },
    );

    _emitRuntimeEvent(container, 'req-plan', EventType.toolCallCompleted, {
      'requestId': 'req-plan',
      'toolCall': patchTool.copyWith(result: 'captured'),
    });

    final patch = container.read(patchProposalProvider).active;
    expect(patch, isNotNull);
    expect(patch!.isPlanOnly, isTrue);
    expect(patch.edits, isEmpty);
    expect(patch.title, 'Create hello program');
    expect(patch.planMarkdown, contains('Add hello.py'));
    expect(patch.plannedFiles, hasLength(2));
    expect(patch.plannedTargets, hasLength(2));
    expect(patch.plannedTargets.first.operation, ProposedFileEditType.create);
    expect(patch.plannedTargets.last.operation, ProposedFileEditType.modify);
    expect(container.read(studioShellProvider).mode, isNot(StudioMode.review));

    final updated = container
        .read(studioThreadProvider)
        .threads
        .firstWhere((candidate) => candidate.id == thread.id);
    expect(
      updated.turns.single.events.map((event) => event.title),
      contains('Plan ready for review'),
    );
  });

  test(
    'propose_patch with content creates a concrete patch artifact',
    () async {
      final container = _lifecycleContainer();
      addTearDown(container.dispose);
      await _waitForThreadStore(container);

      final thread = container
          .read(studioThreadProvider.notifier)
          .ensureThread(title: 'Implement hello', model: 'gpt-5-nano');
      _registerTurn(
        container,
        'req-patch',
        thread.id,
        summary: const StudioContextSummary(projectLabel: 'project'),
      );
      container
          .read(studioRequestLifecycleProvider.notifier)
          .registerRequest(
            requestId: 'req-patch',
            threadId: thread.id,
            model: 'gpt-5-nano',
            contextSummary: const StudioContextSummary(projectLabel: 'project'),
          );

      const patchTool = ToolCallInfo(
        id: 'patch-2',
        name: 'propose_patch',
        arguments: {
          'title': 'Create hello program',
          'summary': 'Add an executable hello script.',
          'files': [
            {
              'path': 'hello.py',
              'intent': 'Print Hello when executed',
              'operation': 'create',
              'content': 'print("Hello")\n',
            },
          ],
        },
      );

      _emitRuntimeEvent(container, 'req-patch', EventType.toolCallCompleted, {
        'requestId': 'req-patch',
        'toolCall': patchTool.copyWith(result: 'captured'),
      });

      final patch = container.read(patchProposalProvider).active;
      expect(patch, isNotNull);
      expect(patch!.isPlanOnly, isFalse);
      expect(patch.edits, hasLength(1));
      expect(patch.edits.single.path, 'hello.py');
      expect(patch.edits.single.after, 'print("Hello")\n');

      final updated = container
          .read(studioThreadProvider)
          .threads
          .firstWhere((candidate) => candidate.id == thread.id);
      expect(
        updated.turns.single.events.map((event) => event.title),
        contains('Patch ready'),
      );
    },
  );

  test(
    'propose_patch from implementation plus verification prompt preserves verification request',
    () async {
      final container = _lifecycleContainer();
      addTearDown(container.dispose);
      await _waitForThreadStore(container);

      final thread = container
          .read(studioThreadProvider.notifier)
          .ensureThread(title: 'Fix and test', model: 'gpt-5-nano');
      _registerTurn(
        container,
        'req-verify-patch',
        thread.id,
        summary: const StudioContextSummary(projectLabel: 'project'),
        prompt: 'Fix the login bug and run tests',
      );
      container
          .read(studioRequestLifecycleProvider.notifier)
          .registerRequest(
            requestId: 'req-verify-patch',
            threadId: thread.id,
            model: 'gpt-5-nano',
            contextSummary: const StudioContextSummary(projectLabel: 'project'),
          );

      const patchTool = ToolCallInfo(
        id: 'patch-verify',
        name: 'propose_patch',
        arguments: {
          'title': 'Fix login bug',
          'summary': 'Update login guard behavior.',
          'files': [
            {
              'path': 'lib/login.dart',
              'intent': 'Fix guard',
              'operation': 'create',
              'content': 'bool canLogin = true;\n',
            },
          ],
        },
      );

      _emitRuntimeEvent(
        container,
        'req-verify-patch',
        EventType.toolCallCompleted,
        {
          'requestId': 'req-verify-patch',
          'toolCall': patchTool.copyWith(result: 'captured'),
        },
      );

      final patch = container.read(patchProposalProvider).active;
      expect(patch, isNotNull);
      expect(patch!.verificationRequested, isTrue);
    },
  );

  test(
    'accepted plan implementation preserves verification request from plan context',
    () async {
      final container = _lifecycleContainer();
      addTearDown(container.dispose);
      await _waitForThreadStore(container);

      final thread = container
          .read(studioThreadProvider.notifier)
          .ensureThread(title: 'Implement plan', model: 'gpt-5-nano');
      _registerTurn(
        container,
        'req-accepted-plan-verify',
        thread.id,
        summary: const StudioContextSummary(projectLabel: 'project'),
        prompt:
            'Implement this approved plan.\n\nVerification was explicitly requested. Preserve that request in the patch proposal and suggested checks.',
        acceptedPlanState: AcceptedPlanState.implementationStarted,
      );
      container
          .read(studioTurnProvider.notifier)
          .startAcceptedPlanImplementation(
            'req-accepted-plan-verify',
            const AcceptedPlanContext(
              patchSetId: 'plan-verify',
              title: 'Fix login',
              summary: 'Fix the login guard.',
              markdown:
                  '# Plan\n\n- Update login guard.\n\n## Verification\n- Run login checks after apply.',
              plannedFiles: ['lib/login.dart — Fix guard'],
              verificationRequested: true,
            ),
          );
      container
          .read(studioRequestLifecycleProvider.notifier)
          .registerRequest(
            requestId: 'req-accepted-plan-verify',
            threadId: thread.id,
            model: 'gpt-5-nano',
            contextSummary: const StudioContextSummary(projectLabel: 'project'),
          );

      const patchTool = ToolCallInfo(
        id: 'patch-plan-verify',
        name: 'propose_patch',
        arguments: {
          'title': 'Fix login',
          'summary': 'Apply the accepted plan.',
          'files': [
            {
              'path': 'lib/login.dart',
              'intent': 'Fix guard',
              'operation': 'create',
              'content': 'bool canLogin = true;\n',
            },
          ],
        },
      );

      _emitRuntimeEvent(
        container,
        'req-accepted-plan-verify',
        EventType.toolCallCompleted,
        {
          'requestId': 'req-accepted-plan-verify',
          'toolCall': patchTool.copyWith(result: 'captured'),
        },
      );

      final patch = container.read(patchProposalProvider).active;
      expect(patch, isNotNull);
      expect(patch!.verificationRequested, isTrue);
    },
  );

  test('message errors fail the thread and ignore stale request events', () {
    final container = _lifecycleContainer();
    addTearDown(container.dispose);

    final thread = container
        .read(studioThreadProvider.notifier)
        .ensureThread(title: 'Build topology', model: 'gpt-5-nano');
    _registerTurn(
      container,
      'req-fail',
      thread.id,
      summary: const StudioContextSummary(projectLabel: 'project'),
    );
    container
        .read(studioRequestLifecycleProvider.notifier)
        .registerRequest(
          requestId: 'req-fail',
          threadId: thread.id,
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(projectLabel: 'project'),
        );

    _emitRuntimeEvent(container, 'other-request', EventType.messageChunk, {
      'requestId': 'other-request',
      'content': 'stale',
    });
    expect(
      container.read(studioThreadProvider).selectedThread!.streamingContent,
      isEmpty,
    );

    _emitRuntimeEvent(container, 'req-fail', EventType.messageError, {
      'requestId': 'req-fail',
      'error': 'Request timed out after 4 minutes',
    });

    final updated = container.read(studioThreadProvider).selectedThread!;
    expect(updated.status, StudioThreadStatus.failed);
    expect(updated.phase, StudioSendPhase.failed);
    expect(updated.lastError, contains('timed out'));
    expect(updated.turns.single.status, StudioTurnStatus.failed);
    expect(
      updated.turns.single.events
          .where((event) => event.type == StudioTurnEventType.error)
          .single
          .detail,
      contains('timed out'),
    );
  });

  test(
    'terminal provider diagnostics record progress without owning runtime failure',
    () {
      final container = _lifecycleContainer();
      addTearDown(container.dispose);

      final thread = container
          .read(studioThreadProvider.notifier)
          .ensureThread(title: 'Stream ended early', model: 'gpt-5-nano');
      _registerTurn(
        container,
        'req-stream-ended',
        thread.id,
        summary: const StudioContextSummary(projectLabel: 'project'),
      );
      container
          .read(studioRequestLifecycleProvider.notifier)
          .registerRequest(
            requestId: 'req-stream-ended',
            threadId: thread.id,
            model: 'gpt-5-nano',
            contextSummary: const StudioContextSummary(projectLabel: 'project'),
          );

      _emitRuntimeEvent(
        container,
        'req-stream-ended',
        EventType.providerLifecycle,
        {
          'requestId': 'req-stream-ended',
          'event': ProviderLifecycleEvent(
            requestId: 'req-stream-ended',
            kind: ProviderLifecycleEventKind.streamEndedWithoutDone,
            timestamp: DateTime(2026),
            model: 'gpt-5-nano',
            detail: 'Circuit stream ended before the [DONE] marker.',
          ),
        },
      );

      final updated = container.read(studioThreadProvider).selectedThread!;
      expect(updated.status, StudioThreadStatus.preflighting);
      expect(updated.phase, StudioSendPhase.preflighting);
      expect(updated.turns.single.status, StudioTurnStatus.failed);
      expect(
        updated.turns.single.providerDiagnostics.single.kind,
        ProviderLifecycleEventKind.streamEndedWithoutDone,
      );
      expect(
        container
            .read(studioRequestLifecycleProvider)
            .find('req-stream-ended')
            ?.lastEventKind,
        StudioRequestLifecycleEventKind.failed,
      );
    },
  );
}

void _registerTurn(
  ProviderContainer container,
  String requestId,
  String threadId, {
  required StudioContextSummary summary,
  String? prompt,
  String? modelPrompt,
  bool isResearch = false,
  AcceptedPlanState acceptedPlanState = AcceptedPlanState.none,
}) {
  container
      .read(studioTurnProvider.notifier)
      .registerTurn(
        requestId: requestId,
        threadId: threadId,
        taskId: null,
        userMessageId: 'user-$requestId',
        prompt: prompt ?? 'Prompt for $requestId',
        modelPrompt: modelPrompt,
        model: 'gpt-5-nano',
        contextSummary: summary,
        acceptedPlanState: acceptedPlanState,
        isResearch: isResearch,
      );
}

ConfirmationRequest _approvalRequest(String id) {
  return ConfirmationRequest(
    id: id,
    toolCall: ToolCallInfo(
      id: 'tool-$id',
      name: 'run_command',
      arguments: const {'command': 'npm test'},
    ),
    preview: 'npm test',
  );
}

Future<void> _waitForThreadStore(ProviderContainer container) async {
  for (var i = 0; i < 50; i += 1) {
    if (!container.read(studioThreadProvider).isLoading) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _waitForWorkspaceStore(ProviderContainer container) async {
  for (var i = 0; i < 50; i += 1) {
    if (!container.read(agentWorkspaceProvider).isLoading) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
