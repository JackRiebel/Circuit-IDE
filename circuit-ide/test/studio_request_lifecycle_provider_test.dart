import 'package:circuit_ide/enums/event_type.dart';
import 'package:circuit_ide/models/confirmation_request.dart';
import 'package:circuit_ide/models/studio_request_lifecycle.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/models/tool_call_info.dart';
import 'package:circuit_ide/state/patch_proposal_provider.dart';
import 'package:circuit_ide/state/chat_provider.dart';
import 'package:circuit_ide/state/connection_provider.dart';
import 'package:circuit_ide/state/studio_request_lifecycle_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/state/studio_turn_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('streaming chunks update the registered Studio thread live', () {
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
    _registerTurn(container, 'req-stream', thread.id, summary: summary);
    container
        .read(studioRequestLifecycleProvider.notifier)
        .registerRequest(
          requestId: 'req-stream',
          threadId: thread.id,
          model: 'gpt-5-nano',
          contextSummary: summary,
        );

    container.read(agentServiceProvider).events.emit(EventType.messageChunk, {
      'requestId': 'req-stream',
      'content': 'Hello',
    });
    container.read(agentServiceProvider).events.emit(EventType.messageChunk, {
      'requestId': 'req-stream',
      'content': ' world',
    });

    final updated = container.read(studioThreadProvider).selectedThread!;
    expect(updated.status, StudioThreadStatus.streaming);
    expect(updated.phase, StudioSendPhase.streaming);
    expect(updated.streamingContent, 'Hello world');
    expect(updated.turns.single.assistantDraft, 'Hello world');
  });

  test(
    'message completion appends assistant content and marks thread done',
    () async {
      final container = ProviderContainer();
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

      container
          .read(agentServiceProvider)
          .events
          .emit(EventType.messageCompleted, {
            'requestId': 'req-done',
            'content': 'Hi! How can I help?',
            'toolCalls': const [],
          });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updated = container
          .read(studioThreadProvider)
          .threads
          .firstWhere((candidate) => candidate.id == thread.id);
      expect(updated.status, StudioThreadStatus.done);
      expect(updated.phase, StudioSendPhase.completed);
      expect(updated.streamingContent, isEmpty);
      expect(updated.messages.last.content, 'Hi! How can I help?');
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

  test('confirmationNeeded moves the thread into waiting for approval', () {
    final container = ProviderContainer();
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
    container.read(agentServiceProvider).events.emit(
      EventType.confirmationNeeded,
      {'requestId': 'req-approval', 'request': request},
    );

    final updated = container.read(studioThreadProvider).selectedThread!;
    expect(updated.status, StudioThreadStatus.waitingForApproval);
    expect(updated.phase, StudioSendPhase.waitingForApproval);
    final approval = updated.turns.single.events
        .where((event) => event.type == StudioTurnEventType.approvalRequest)
        .single;
    expect(approval.approvalId, request.id);
    expect(approval.approvalState, ApprovalRequestState.pending);
  });

  test(
    'typed approval resolves pending confirmation instead of becoming chat',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(chatProvider);

      final request = ConfirmationRequest(
        id: 'approval-text',
        toolCall: const ToolCallInfo(
          id: 'approval-text',
          name: 'edit_file',
          arguments: {'path': 'docs/topology.md'},
        ),
        preview: 'edit docs/topology.md',
      );
      container.read(agentServiceProvider).events.emit(
        EventType.confirmationNeeded,
        {'requestId': 'req-approval-text', 'request': request},
      );

      expect(container.read(chatProvider).pendingConfirmation?.id, request.id);
      expect(
        container
            .read(chatProvider.notifier)
            .handlePendingApprovalText('approve'),
        isTrue,
      );
      expect(container.read(chatProvider).pendingConfirmation, isNull);
      expect(container.read(chatProvider).messages, isEmpty);
    },
  );

  test(
    'tool events render Codex-style activity rows and completion recap',
    () async {
      final container = ProviderContainer();
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
      container.read(agentServiceProvider).events.emit(
        EventType.toolCallStarted,
        {'requestId': 'req-tools', 'toolCall': command},
      );
      container
          .read(agentServiceProvider)
          .events
          .emit(EventType.toolCallCompleted, {
            'requestId': 'req-tools',
            'toolCall': command.copyWith(result: 'No issues found'),
          });
      const edit = ToolCallInfo(
        id: 'edit-1',
        name: 'edit_file',
        arguments: {'path': 'lib/main.dart'},
      );
      container
          .read(agentServiceProvider)
          .events
          .emit(EventType.toolCallCompleted, {
            'requestId': 'req-tools',
            'toolCall': edit.copyWith(result: 'Updated lib/main.dart'),
          });
      container.read(agentServiceProvider).events.emit(
        EventType.messageCompleted,
        {'requestId': 'req-tools', 'content': 'Done.', 'toolCalls': const []},
      );
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
    final container = ProviderContainer();
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
        );

    const patchTool = ToolCallInfo(
      id: 'patch-1',
      name: 'propose_patch',
      arguments: {
        'title': 'Create hello program',
        'summary': 'Create a small Python hello program.',
        'plan_markdown': '## Plan\n\n- Add hello.py\n- Add README.md',
        'files': [
          {'path': 'hello.py', 'intent': 'Print Hello when executed'},
          {'path': 'README.md', 'intent': 'Explain how to run it'},
        ],
      },
    );

    container.read(agentServiceProvider).events.emit(
      EventType.toolCallCompleted,
      {
        'requestId': 'req-plan',
        'toolCall': patchTool.copyWith(result: 'captured'),
      },
    );

    final patch = container.read(patchProposalProvider).active;
    expect(patch, isNotNull);
    expect(patch!.isPlanOnly, isTrue);
    expect(patch.title, 'Create hello program');
    expect(patch.planMarkdown, contains('Add hello.py'));
    expect(patch.plannedFiles, hasLength(2));

    final updated = container
        .read(studioThreadProvider)
        .threads
        .firstWhere((candidate) => candidate.id == thread.id);
    expect(
      updated.turns.single.events.map((event) => event.title),
      contains('Plan ready for review'),
    );
  });

  test('message errors fail the thread and ignore stale request events', () {
    final container = ProviderContainer();
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

    container.read(agentServiceProvider).events.emit(EventType.messageChunk, {
      'requestId': 'other-request',
      'content': 'stale',
    });
    expect(
      container.read(studioThreadProvider).selectedThread!.streamingContent,
      isEmpty,
    );

    container.read(agentServiceProvider).events.emit(EventType.messageError, {
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
}

void _registerTurn(
  ProviderContainer container,
  String requestId,
  String threadId, {
  required StudioContextSummary summary,
}) {
  container
      .read(studioTurnProvider.notifier)
      .registerTurn(
        requestId: requestId,
        threadId: threadId,
        taskId: null,
        userMessageId: 'user-$requestId',
        prompt: 'Prompt for $requestId',
        model: 'gpt-5-nano',
        contextSummary: summary,
      );
}

Future<void> _waitForThreadStore(ProviderContainer container) async {
  for (var i = 0; i < 50; i += 1) {
    if (!container.read(studioThreadProvider).isLoading) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
