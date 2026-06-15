import 'dart:io';

import 'package:circuit_ide/enums/message_role.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('StudioThreadStore persists isolated histories per project', () async {
    final root = await Directory.systemTemp.createTemp('studio_threads_');
    addTearDown(() => root.delete(recursive: true));
    final projectA = await Directory('${root.path}/project-a').create();
    final projectB = await Directory('${root.path}/project-b').create();
    final store = StudioThreadStore(baseDir: '${root.path}/history');
    final now = DateTime(2026);

    final threadA = StudioThread(
      id: 'thread-a',
      taskId: 'task-a',
      title: 'Review project A',
      status: StudioThreadStatus.done,
      phase: StudioSendPhase.completed,
      contextSummary: StudioContextSummary(
        rootPath: projectA.path,
        projectLabel: 'project-a',
        includedItemCount: 2,
        estimatedTokens: 120,
      ),
      messages: [
        StudioThreadMessage(
          id: 'message-a',
          role: MessageRole.user,
          content: 'hi',
          timestamp: now,
        ),
      ],
      turns: [
        StudioTurn(
          id: 'turn-a',
          threadId: 'thread-a',
          requestId: 'request-a',
          userMessageId: 'message-a',
          prompt: 'hi',
          model: 'gpt-5-nano',
          contextSummary: StudioContextSummary(
            rootPath: projectA.path,
            projectLabel: 'project-a',
            includedItemCount: 2,
            estimatedTokens: 120,
          ),
          status: StudioTurnStatus.completed,
          events: [
            StudioTurnEvent.userMessage(
              id: 'event-user-a',
              turnId: 'turn-a',
              requestId: 'request-a',
              threadId: 'thread-a',
              content: 'hi',
              timestamp: now,
            ),
            StudioTurnEvent.assistantMessage(
              turnId: 'turn-a',
              requestId: 'request-a',
              threadId: 'thread-a',
              content: 'hello back',
              timestamp: now.add(const Duration(seconds: 1)),
            ),
          ],
          createdAt: now,
          updatedAt: now,
          completedAt: now.add(const Duration(seconds: 1)),
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    await store.save(projectA.path, [threadA]);
    await store.save(projectB.path, const []);

    final loadedA = await store.load(projectA.path);
    final loadedB = await store.load(projectB.path);

    expect(loadedA, hasLength(1));
    expect(loadedA.single.id, 'thread-a');
    expect(loadedA.single.contextSummary?.rootPath, projectA.path);
    expect(loadedA.single.messages.single.content, 'hi');
    expect(loadedA.single.turns.single.prompt, 'hi');
    expect(
      loadedA.single.turns.single.events
          .where((event) => event.type == StudioTurnEventType.assistantMessage)
          .single
          .content,
      'hello back',
    );
    expect(loadedB, isEmpty);
  });

  test('StudioTaskLifecycleState labels user-visible thread states', () {
    final now = DateTime(2026);

    StudioTaskLifecycleState stateFor(StudioThreadStatus status) {
      return StudioTaskLifecycleState.fromThread(
        StudioThread(
          id: status.name,
          title: status.name,
          status: status,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    expect(stateFor(StudioThreadStatus.streaming).label, 'Working');
    expect(stateFor(StudioThreadStatus.waitingForApproval).label, 'Waiting');
    expect(
      stateFor(StudioThreadStatus.waitingForApproval).needsAttention,
      isTrue,
    );
    expect(stateFor(StudioThreadStatus.done).label, 'Done');
    expect(stateFor(StudioThreadStatus.failed).needsAttention, isTrue);
  });

  test(
    'StudioTaskLifecycleState treats stale active saved threads as done',
    () {
      final now = DateTime(2026);
      final thread = StudioThread(
        id: 'thread-stale',
        title: 'Old completed request',
        status: StudioThreadStatus.streaming,
        phase: StudioSendPhase.streaming,
        turns: [
          StudioTurn(
            id: 'turn-stale',
            threadId: 'thread-stale',
            requestId: 'request-stale',
            userMessageId: 'message-stale',
            prompt: 'hello',
            model: 'gpt-5-nano',
            contextSummary: const StudioContextSummary(projectLabel: 'project'),
            status: StudioTurnStatus.completed,
            events: [
              StudioTurnEvent.assistantMessage(
                turnId: 'turn-stale',
                requestId: 'request-stale',
                threadId: 'thread-stale',
                content: 'Done.',
                timestamp: now,
              ),
            ],
            createdAt: now,
            updatedAt: now,
            completedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      final state = StudioTaskLifecycleState.fromThread(thread);

      expect(state.status, StudioThreadStatus.done);
      expect(state.label, 'Done');
      expect(state.isActive, isFalse);
    },
  );
}
