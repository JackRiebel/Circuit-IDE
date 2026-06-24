import 'dart:io';

import 'package:circuit_ide/enums/message_role.dart';
import 'package:circuit_ide/models/accepted_plan_context.dart';
import 'package:circuit_ide/models/context_pack.dart';
import 'package:circuit_ide/models/provider_lifecycle_event.dart';
import 'package:circuit_ide/models/studio_source_artifact.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/models/tool_result_envelope.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/state/studio_turn_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('routine Studio turn events are non-transcript by default', () {
    final now = DateTime(2026);
    final contextEvent = StudioTurnEvent.context(
      turnId: 'turn',
      requestId: 'request',
      threadId: 'thread',
      summary: const StudioContextSummary(
        rootPath: '/tmp/project',
        projectLabel: 'project',
      ),
      timestamp: now,
    );
    final restoredContext = StudioTurnEvent.fromJson({
      'id': 'context-turn',
      'turnId': 'turn',
      'requestId': 'request',
      'threadId': 'thread',
      'type': StudioTurnEventType.context.name,
      'title': 'Project context',
      'detail': '/tmp/project',
      'timestamp': now.toIso8601String(),
    })!;
    final restoredProgress = StudioTurnEvent.fromJson({
      'id': 'progress-turn',
      'turnId': 'turn',
      'requestId': 'request',
      'threadId': 'thread',
      'type': StudioTurnEventType.progress.name,
      'title': 'Still waiting',
      'detail': 'Provider has not returned output yet.',
      'timestamp': now.toIso8601String(),
    })!;
    final restoredTool = StudioTurnEvent.fromJson({
      'id': 'tool-request-tool',
      'turnId': 'turn',
      'requestId': 'request',
      'threadId': 'thread',
      'type': StudioTurnEventType.tool.name,
      'title': 'read_file',
      'detail': 'completed',
      'timestamp': now.toIso8601String(),
    })!;
    final restoredAssistant = StudioTurnEvent.fromJson({
      'id': 'assistant-turn',
      'turnId': 'turn',
      'requestId': 'request',
      'threadId': 'thread',
      'type': StudioTurnEventType.assistantMessage.name,
      'title': 'Assistant response',
      'detail': 'Useful response',
      'content': 'Useful response',
      'timestamp': now.toIso8601String(),
    })!;

    expect(contextEvent.transcriptVisible, isFalse);
    expect(contextEvent.toJson()['transcriptVisible'], isFalse);
    expect(restoredContext.transcriptVisible, isFalse);
    expect(restoredProgress.transcriptVisible, isFalse);
    expect(restoredTool.transcriptVisible, isFalse);
    expect(restoredAssistant.transcriptVisible, isTrue);
  });

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

  test(
    'StudioThreadStore migrates legacy message-only threads into turns on load',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'studio_legacy_messages_',
      );
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final started = DateTime(2026, 1, 2, 9);
      final legacyThread = StudioThread(
        id: 'thread-legacy',
        title: 'Legacy thread',
        status: StudioThreadStatus.streaming,
        phase: StudioSendPhase.streaming,
        requestId: 'stale-request',
        streamingContent: 'stale draft',
        messages: [
          StudioThreadMessage(
            id: 'legacy-user',
            role: MessageRole.user,
            content: 'legacy question',
            timestamp: started,
          ),
          StudioThreadMessage(
            id: 'legacy-assistant',
            role: MessageRole.assistant,
            content: 'legacy answer',
            timestamp: started.add(const Duration(seconds: 2)),
          ),
        ],
        createdAt: started,
        updatedAt: started.add(const Duration(seconds: 2)),
      );

      await store.save(project.path, [legacyThread]);
      final loaded = await store.load(project.path);

      expect(loaded, hasLength(1));
      final thread = loaded.single;
      expect(thread.status, StudioThreadStatus.done);
      expect(thread.phase, StudioSendPhase.completed);
      expect(thread.requestId, isNull);
      expect(thread.streamingContent, isEmpty);
      expect(thread.lastError, isNull);
      expect(thread.turns, hasLength(1));
      final turn = thread.turns.single;
      expect(turn.id, startsWith('legacy-turn-thread-legacy'));
      expect(turn.prompt, 'legacy question');
      expect(turn.status, StudioTurnStatus.completed);
      expect(
        turn.events
            .where((event) => event.type == StudioTurnEventType.userMessage)
            .single
            .content,
        'legacy question',
      );
      expect(
        turn.events
            .where(
              (event) => event.type == StudioTurnEventType.assistantMessage,
            )
            .single
            .content,
        'legacy answer',
      );
    },
  );

  test(
    'StudioThreadStore preserves multiple legacy message turns in order',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'studio_legacy_multi_turn_',
      );
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final started = DateTime(2026, 1, 2, 9);
      final legacyThread = StudioThread(
        id: 'thread-legacy-multi',
        title: 'Legacy multi turn thread',
        status: StudioThreadStatus.streaming,
        phase: StudioSendPhase.streaming,
        requestId: 'stale-request',
        streamingContent: 'stale draft',
        messages: [
          StudioThreadMessage(
            id: 'legacy-user-1',
            role: MessageRole.user,
            content: 'first question',
            timestamp: started,
          ),
          StudioThreadMessage(
            id: 'legacy-assistant-1',
            role: MessageRole.assistant,
            content: 'first answer',
            timestamp: started.add(const Duration(seconds: 1)),
          ),
          StudioThreadMessage(
            id: 'legacy-user-2',
            role: MessageRole.user,
            content: 'second question',
            timestamp: started.add(const Duration(seconds: 2)),
          ),
          StudioThreadMessage(
            id: 'legacy-assistant-2a',
            role: MessageRole.assistant,
            content: 'second answer part one',
            timestamp: started.add(const Duration(seconds: 3)),
          ),
          StudioThreadMessage(
            id: 'legacy-assistant-2b',
            role: MessageRole.assistant,
            content: 'second answer part two',
            timestamp: started.add(const Duration(seconds: 4)),
          ),
        ],
        createdAt: started,
        updatedAt: started.add(const Duration(seconds: 4)),
      );

      await store.save(project.path, [legacyThread]);
      final loaded = await store.load(project.path);

      final thread = loaded.single;
      expect(thread.status, StudioThreadStatus.done);
      expect(thread.phase, StudioSendPhase.completed);
      expect(thread.requestId, isNull);
      expect(thread.streamingContent, isEmpty);
      expect(thread.turns, hasLength(2));
      expect(thread.turns.map((turn) => turn.requestId), [
        'legacy-request-thread-legacy-multi-1',
        'legacy-request-thread-legacy-multi-2',
      ]);
      expect(thread.turns.map((turn) => turn.prompt), [
        'first question',
        'second question',
      ]);
      expect(
        thread.turns.last.events
            .where(
              (event) => event.type == StudioTurnEventType.assistantMessage,
            )
            .single
            .content,
        'second answer part one\n\nsecond answer part two',
      );
    },
  );

  test('task-scoped thread lookup does not fall back to selected thread', () {
    final now = DateTime(2026);
    final selectedThread = StudioThread(
      id: 'thread-a',
      taskId: 'task-a',
      title: 'Task A',
      status: StudioThreadStatus.done,
      createdAt: now,
      updatedAt: now,
    );
    final state = StudioThreadState(
      threads: [selectedThread],
      selectedThreadId: selectedThread.id,
    );

    expect(state.threadForTaskView(null), selectedThread);
    expect(state.threadForTaskView('task-a'), selectedThread);
    expect(state.threadForTaskView('missing-task'), isNull);
  });

  test(
    'StudioThreadController preserves all source artifacts for long threads',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Long artifact history');

      for (var i = 0; i < 130; i++) {
        container
            .read(studioThreadProvider.notifier)
            .upsertSourceArtifact(
              thread.id,
              StudioSourceArtifact(
                id: 'artifact-$i',
                kind: StudioSourceArtifactKind.diff,
                title: 'file_$i.dart',
                subtitle: 'Diff',
                value: 'diff $i',
                threadId: thread.id,
                requestId: 'request-$i',
                filePath: 'file_$i.dart',
                createdAt: DateTime(2026).add(Duration(minutes: i)),
              ),
            );
      }

      final updated = container
          .read(studioThreadProvider)
          .threads
          .singleWhere((candidate) => candidate.id == thread.id);
      expect(updated.sourceArtifacts, hasLength(130));
      expect(updated.sourceArtifacts.first.id, 'artifact-129');
      expect(updated.sourceArtifacts.last.id, 'artifact-0');
    },
  );

  test(
    'StudioTurnController keeps archived request refs for long histories',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Long request history');

      for (var i = 0; i < 55; i++) {
        container
            .read(studioTurnProvider.notifier)
            .registerTurn(
              requestId: 'request-$i',
              threadId: thread.id,
              taskId: null,
              userMessageId: 'message-$i',
              prompt: 'prompt $i',
              model: 'gpt-5-nano',
              contextSummary: const StudioContextSummary(
                projectLabel: 'project',
              ),
              intent: TurnIntent.chat,
            );
        container
            .read(studioTurnProvider.notifier)
            .complete('request-$i', content: 'response $i');
      }

      container
          .read(studioTurnProvider.notifier)
          .addProviderDiagnostic(
            'request-0',
            ProviderLifecycleEvent(
              requestId: 'request-0',
              turnId: 'ignored-by-request-ref-lookup',
              kind: ProviderLifecycleEventKind.completed,
              timestamp: DateTime(2026),
              model: 'gpt-5-nano',
              detail: 'late diagnostic still attaches',
            ),
          );

      final updated = container
          .read(studioThreadProvider)
          .threads
          .singleWhere((candidate) => candidate.id == thread.id);
      final oldestTurn = updated.turns.singleWhere(
        (turn) => turn.requestId == 'request-0',
      );
      expect(oldestTurn.providerDiagnostics, hasLength(1));
      expect(
        oldestTurn.providerDiagnostics.single.detail,
        contains('late diagnostic'),
      );
      expect(
        container.read(studioTurnProvider).archivedRefForRequest('request-0'),
        isNotNull,
      );
    },
  );

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

  test(
    'StudioTaskLifecycleState ignores legacy messages for active status',
    () {
      final now = DateTime(2026);
      final thread = StudioThread(
        id: 'thread-legacy-active',
        title: 'Legacy active',
        status: StudioThreadStatus.streaming,
        phase: StudioSendPhase.streaming,
        messages: [
          StudioThreadMessage(
            id: 'legacy-assistant',
            role: MessageRole.assistant,
            content: 'Old answer',
            timestamp: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      final state = StudioTaskLifecycleState.fromThread(thread);

      expect(state.status, StudioThreadStatus.streaming);
      expect(state.label, 'Working');
      expect(state.isActive, isTrue);
    },
  );

  test(
    'StudioThreadStore marks interrupted active threads as failed on load',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final now = DateTime(2026);

      final interrupted = StudioThread(
        id: 'thread-interrupted',
        title: 'Interrupted request',
        status: StudioThreadStatus.streaming,
        phase: StudioSendPhase.streaming,
        requestId: 'request-interrupted',
        turns: [
          StudioTurn(
            id: 'turn-interrupted',
            threadId: 'thread-interrupted',
            requestId: 'request-interrupted',
            userMessageId: 'message-interrupted',
            prompt: 'review this',
            model: 'gpt-5-nano',
            contextSummary: StudioContextSummary(
              rootPath: project.path,
              projectLabel: 'project',
            ),
            status: StudioTurnStatus.streaming,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      await store.save(project.path, [interrupted]);

      final loaded = await store.load(project.path);

      expect(loaded.single.status, StudioThreadStatus.failed);
      expect(loaded.single.phase, StudioSendPhase.failed);
      expect(loaded.single.requestId, isNull);
      expect(loaded.single.turns.single.status, StudioTurnStatus.failed);
      expect(
        loaded.single.turns.single.lastError,
        contains('Interrupted while CircuitCode was closed'),
      );
    },
  );

  test(
    'StudioThreadStore reconciles inactive saved threads with interrupted latest turns',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final now = DateTime(2026);

      await store.save(project.path, [
        StudioThread(
          id: 'thread-inconsistent',
          title: 'Serialized as done',
          status: StudioThreadStatus.done,
          phase: StudioSendPhase.completed,
          turns: [
            StudioTurn(
              id: 'turn-active',
              threadId: 'thread-inconsistent',
              requestId: 'request-active',
              userMessageId: 'message-active',
              prompt: 'review this',
              model: 'gpt-5-nano',
              contextSummary: StudioContextSummary(
                rootPath: project.path,
                projectLabel: 'project',
              ),
              status: StudioTurnStatus.streaming,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      ]);

      final loaded = await store.load(project.path);
      final loadedThread = loaded.single;

      expect(loadedThread.status, StudioThreadStatus.failed);
      expect(loadedThread.phase, StudioSendPhase.failed);
      expect(loadedThread.requestId, isNull);
      expect(loadedThread.streamingContent, isEmpty);
      expect(loadedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        loadedThread.turns.single.lastError,
        contains('Interrupted while CircuitCode was closed'),
      );
    },
  );

  test(
    'StudioThreadStore preserves completed plan patch verify turn history on load',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final now = DateTime(2026);

      const contextRetrieval = ContextRetrievalResult(
        rankedCandidates: [
          ContextCandidate(
            id: 'file-lib',
            title: 'lib/main.dart',
            path: 'lib/main.dart',
            sourceKind: ContextPackSourceKind.editor,
            score: 92,
            estimatedTokens: 140,
            included: true,
            reason: 'direct path mention',
          ),
          ContextCandidate(
            id: 'file-test',
            title: 'test/main_test.dart',
            path: 'test/main_test.dart',
            sourceKind: ContextPackSourceKind.diagnostics,
            score: 77,
            estimatedTokens: 110,
            included: false,
            reason: 'omitted by token budget',
          ),
        ],
        budget: ContextBudgetReport(
          maxTokens: 1000,
          reservedForResponse: 300,
          availableForContext: 700,
          usedTokens: 650,
        ),
        warnings: [
          ContextPackWarning(message: 'One high-score file was omitted.'),
        ],
      );

      final thread = StudioThread(
        id: 'thread-golden',
        title: 'Build greeting feature',
        status: StudioThreadStatus.done,
        phase: StudioSendPhase.completed,
        requestId: 'stale-request-id',
        streamingContent: 'stale assistant draft',
        lastError: 'old transient error',
        turns: [
          StudioTurn(
            id: 'turn-plan',
            threadId: 'thread-golden',
            requestId: 'request-plan',
            userMessageId: 'message-plan',
            prompt: 'Plan the change',
            model: 'gpt-5-nano',
            intent: TurnIntent.plan,
            contextSummary: StudioContextSummary(
              rootPath: project.path,
              projectLabel: 'project',
              includedItemCount: 2,
              estimatedTokens: 650,
            ),
            status: StudioTurnStatus.completed,
            acceptedPlanState: AcceptedPlanState.accepted,
            contextRetrieval: contextRetrieval,
            providerDiagnostics: [
              ProviderLifecycleEvent(
                requestId: 'request-plan',
                turnId: 'turn-plan',
                kind: ProviderLifecycleEventKind.firstTextDelta,
                timestamp: now.add(const Duration(milliseconds: 10)),
                model: 'gpt-5-nano',
              ),
              ProviderLifecycleEvent(
                requestId: 'request-plan',
                turnId: 'turn-plan',
                kind: ProviderLifecycleEventKind.completed,
                timestamp: now.add(const Duration(milliseconds: 20)),
                model: 'gpt-5-nano',
              ),
            ],
            toolResults: const [
              ToolResultEnvelope(
                toolCallId: 'tool-plan',
                toolName: 'propose_patch',
                status: ToolResultStatus.success,
                summary: 'Prepared reviewable plan.',
                artifacts: ['patch-plan'],
              ),
            ],
            events: [
              StudioTurnEvent.assistantMessage(
                turnId: 'turn-plan',
                requestId: 'request-plan',
                threadId: 'thread-golden',
                content: 'Here is the plan.',
                timestamp: now.add(const Duration(milliseconds: 30)),
              ),
            ],
            createdAt: now,
            updatedAt: now,
            completedAt: now.add(const Duration(seconds: 1)),
          ),
          StudioTurn(
            id: 'turn-code',
            threadId: 'thread-golden',
            requestId: 'request-code',
            userMessageId: 'message-code',
            prompt: 'Implement accepted plan',
            model: 'gpt-5-nano',
            intent: TurnIntent.code,
            contextSummary: StudioContextSummary(
              rootPath: project.path,
              projectLabel: 'project',
              includedItemCount: 2,
              estimatedTokens: 650,
            ),
            status: StudioTurnStatus.completed,
            acceptedPlanState: AcceptedPlanState.patchProposed,
            acceptedPlanContext: const AcceptedPlanContext(
              patchSetId: 'patch-plan',
              title: 'Greeting feature plan',
              summary: 'Implement the accepted greeting feature plan.',
              markdown: '# Plan\n\n- Update lib/main.dart',
              plannedFiles: ['lib/main.dart'],
              verificationRequested: true,
            ),
            toolResults: const [
              ToolResultEnvelope(
                toolCallId: 'tool-patch',
                toolName: 'propose_patch',
                status: ToolResultStatus.success,
                summary: 'Prepared concrete edits.',
                artifacts: ['patch-code'],
                changedFiles: ['lib/main.dart'],
              ),
            ],
            providerDiagnostics: [
              ProviderLifecycleEvent(
                requestId: 'request-code',
                turnId: 'turn-code',
                kind: ProviderLifecycleEventKind.toolOnly,
                timestamp: now.add(const Duration(seconds: 2)),
                model: 'gpt-5-nano',
              ),
            ],
            events: [
              StudioTurnEvent.completionSummary(
                id: 'patch-transaction-turn-code-patch-code-1',
                turnId: 'turn-code',
                requestId: 'request-code',
                threadId: 'thread-golden',
                title: 'Applied changes',
                detail: [
                  'Applied 1 files.',
                  'Files: lib/main.dart',
                  'Checkpoint: checkpoint-code',
                  '- Modified lib/main.dart (+4 -1 lines)',
                  'Suggested checks: flutter test',
                  'Patch: Greeting feature implementation',
                ].join('\n'),
                timestamp: now.add(const Duration(seconds: 3)),
              ),
            ],
            createdAt: now.add(const Duration(seconds: 2)),
            updatedAt: now.add(const Duration(seconds: 2)),
            completedAt: now.add(const Duration(seconds: 3)),
          ),
          StudioTurn(
            id: 'turn-verify',
            threadId: 'thread-golden',
            requestId: 'request-verify',
            userMessageId: 'message-verify',
            prompt: 'Verify the change',
            model: 'gpt-5-nano',
            intent: TurnIntent.verify,
            contextSummary: StudioContextSummary(
              rootPath: project.path,
              projectLabel: 'project',
              includedItemCount: 1,
              estimatedTokens: 120,
            ),
            status: StudioTurnStatus.completed,
            toolResults: const [
              ToolResultEnvelope(
                toolCallId: 'tool-verify',
                toolName: 'run_command',
                status: ToolResultStatus.success,
                summary: 'Verification passed.',
                stdout: 'ok\n',
              ),
            ],
            createdAt: now.add(const Duration(seconds: 4)),
            updatedAt: now.add(const Duration(seconds: 4)),
            completedAt: now.add(const Duration(seconds: 5)),
          ),
        ],
        createdAt: now,
        updatedAt: now.add(const Duration(seconds: 5)),
      );

      await store.save(project.path, [thread]);

      final loaded = await store.load(project.path);
      final loadedThread = loaded.single;

      expect(loadedThread.status, StudioThreadStatus.done);
      expect(loadedThread.phase, StudioSendPhase.completed);
      expect(loadedThread.requestId, isNull);
      expect(loadedThread.streamingContent, isEmpty);
      expect(loadedThread.lastError, isNull);
      expect(loadedThread.turns, hasLength(3));
      expect(loadedThread.turns.map((turn) => turn.status).toSet(), {
        StudioTurnStatus.completed,
      });
      expect(
        loadedThread.turns
            .where((turn) => turn.id == 'turn-plan')
            .single
            .contextRetrieval
            ?.omittedCandidates
            .single
            .path,
        'test/main_test.dart',
      );
      expect(
        loadedThread.turns
            .where((turn) => turn.id == 'turn-plan')
            .single
            .acceptedPlanState,
        AcceptedPlanState.accepted,
      );
      expect(
        loadedThread.turns
            .where((turn) => turn.id == 'turn-code')
            .single
            .acceptedPlanState,
        AcceptedPlanState.patchProposed,
      );
      final loadedCodeTurn = loadedThread.turns
          .where((turn) => turn.id == 'turn-code')
          .single;
      expect(loadedCodeTurn.acceptedPlanContext?.patchSetId, 'patch-plan');
      expect(loadedCodeTurn.acceptedPlanContext?.plannedFiles, [
        'lib/main.dart',
      ]);
      expect(loadedCodeTurn.acceptedPlanContext?.verificationRequested, isTrue);
      expect(loadedCodeTurn.toolResults.single.changedFiles, ['lib/main.dart']);
      final patchTransaction = loadedCodeTurn.events
          .where(
            (event) =>
                event.type == StudioTurnEventType.completionSummary &&
                event.id.startsWith('patch-transaction-'),
          )
          .single;
      expect(patchTransaction.title, 'Applied changes');
      expect(patchTransaction.detail, contains('Applied 1 files.'));
      expect(patchTransaction.detail, contains('Modified lib/main.dart'));
      expect(patchTransaction.detail, contains('Checkpoint: checkpoint-code'));
      expect(
        patchTransaction.detail,
        contains('Suggested checks: flutter test'),
      );
      expect(
        loadedThread.turns
            .where((turn) => turn.id == 'turn-verify')
            .single
            .toolResults
            .single
            .stdout,
        'ok\n',
      );
    },
  );

  test(
    'StudioThreadStore preserves rejected and revision-requested patch transaction events',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final now = DateTime(2026);

      final thread = StudioThread(
        id: 'thread-review-outcomes',
        title: 'Review patch outcomes',
        status: StudioThreadStatus.done,
        phase: StudioSendPhase.completed,
        turns: [
          StudioTurn(
            id: 'turn-review-outcomes',
            threadId: 'thread-review-outcomes',
            requestId: 'request-review-outcomes',
            userMessageId: 'message-review-outcomes',
            prompt: 'Review the proposed patch',
            model: 'gpt-5-nano',
            intent: TurnIntent.code,
            contextSummary: StudioContextSummary(
              rootPath: project.path,
              projectLabel: 'project',
            ),
            status: StudioTurnStatus.completed,
            events: [
              StudioTurnEvent.completionSummary(
                id: 'patch-transaction-turn-review-outcomes-rejected-1',
                turnId: 'turn-review-outcomes',
                requestId: 'request-review-outcomes',
                threadId: 'thread-review-outcomes',
                title: 'Patch rejected',
                detail: 'Patch rejected.\nPatch: Add unsafe wording',
                timestamp: now.add(const Duration(milliseconds: 10)),
              ),
              StudioTurnEvent.completionSummary(
                id: 'patch-transaction-turn-review-outcomes-revision-1',
                turnId: 'turn-review-outcomes',
                requestId: 'request-review-outcomes',
                threadId: 'thread-review-outcomes',
                title: 'Patch revision requested',
                detail:
                    'Patch revision requested.\nUse safer customer wording.\nPatch: Add customer note',
                timestamp: now.add(const Duration(milliseconds: 20)),
              ),
            ],
            createdAt: now,
            updatedAt: now.add(const Duration(milliseconds: 20)),
            completedAt: now.add(const Duration(milliseconds: 20)),
          ),
        ],
        createdAt: now,
        updatedAt: now.add(const Duration(milliseconds: 20)),
      );

      await store.save(project.path, [thread]);

      final loaded = await store.load(project.path);
      final events = loaded.single.turns.single.events
          .where(
            (event) =>
                event.type == StudioTurnEventType.completionSummary &&
                event.id.startsWith('patch-transaction-'),
          )
          .toList(growable: false);

      expect(events, hasLength(2));
      expect(events.map((event) => event.title), [
        'Patch rejected',
        'Patch revision requested',
      ]);
      expect(events.first.detail, contains('Add unsafe wording'));
      expect(events.last.detail, contains('Use safer customer wording.'));
    },
  );

  test(
    'StudioThread latestContextRetrieval returns newest saved turn context',
    () {
      final now = DateTime(2026);
      const oldRetrieval = ContextRetrievalResult(
        rankedCandidates: [
          ContextCandidate(
            id: 'old',
            title: 'old_context.dart',
            path: 'lib/old_context.dart',
            sourceKind: ContextPackSourceKind.diagnostics,
            score: 60,
            estimatedTokens: 80,
            included: true,
            reason: 'old turn context',
          ),
        ],
        budget: ContextBudgetReport(
          maxTokens: 1000,
          reservedForResponse: 300,
          availableForContext: 700,
          usedTokens: 80,
        ),
      );
      const newestRetrieval = ContextRetrievalResult(
        rankedCandidates: [
          ContextCandidate(
            id: 'newest',
            title: 'newest_context.dart',
            path: 'lib/newest_context.dart',
            sourceKind: ContextPackSourceKind.diagnostics,
            score: 98,
            estimatedTokens: 120,
            included: true,
            reason: 'newest turn context',
          ),
        ],
        budget: ContextBudgetReport(
          maxTokens: 1000,
          reservedForResponse: 300,
          availableForContext: 700,
          usedTokens: 120,
        ),
      );

      final thread = StudioThread(
        id: 'thread-context',
        title: 'Context history',
        turns: [
          StudioTurn(
            id: 'turn-old',
            threadId: 'thread-context',
            requestId: 'request-old',
            userMessageId: 'message-old',
            prompt: 'First task',
            model: 'gpt-5-nano',
            intent: TurnIntent.ask,
            contextSummary: const StudioContextSummary(projectLabel: 'project'),
            status: StudioTurnStatus.completed,
            contextRetrieval: oldRetrieval,
            createdAt: now,
            updatedAt: now,
          ),
          StudioTurn(
            id: 'turn-middle',
            threadId: 'thread-context',
            requestId: 'request-middle',
            userMessageId: 'message-middle',
            prompt: 'No context here',
            model: 'gpt-5-nano',
            intent: TurnIntent.chat,
            contextSummary: const StudioContextSummary(projectLabel: 'project'),
            status: StudioTurnStatus.completed,
            createdAt: now.add(const Duration(seconds: 1)),
            updatedAt: now.add(const Duration(seconds: 1)),
          ),
          StudioTurn(
            id: 'turn-newest',
            threadId: 'thread-context',
            requestId: 'request-newest',
            userMessageId: 'message-newest',
            prompt: 'Latest task',
            model: 'gpt-5-nano',
            intent: TurnIntent.code,
            contextSummary: const StudioContextSummary(projectLabel: 'project'),
            status: StudioTurnStatus.completed,
            contextRetrieval: newestRetrieval,
            createdAt: now.add(const Duration(seconds: 2)),
            updatedAt: now.add(const Duration(seconds: 2)),
          ),
        ],
        createdAt: now,
        updatedAt: now.add(const Duration(seconds: 2)),
      );

      expect(
        thread.latestContextRetrieval?.includedCandidates.single.path,
        'lib/newest_context.dart',
      );
      final persistedOrderThread = thread.copyWith(
        turns: thread.turns.reversed.toList(),
      );
      expect(
        persistedOrderThread
            .latestContextRetrieval
            ?.includedCandidates
            .single
            .path,
        'lib/newest_context.dart',
      );
    },
  );

  test(
    'StudioThreadStore clears stale runtime fields on failed loaded threads',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final now = DateTime(2026);

      await store.save(project.path, [
        StudioThread(
          id: 'thread-failed',
          title: 'Failed request',
          status: StudioThreadStatus.failed,
          phase: StudioSendPhase.failed,
          requestId: 'stale-request-id',
          streamingContent: 'partial assistant draft',
          lastError: 'Provider timed out.',
          turns: [
            StudioTurn(
              id: 'turn-failed',
              threadId: 'thread-failed',
              requestId: 'request-failed',
              userMessageId: 'message-failed',
              prompt: 'review this',
              model: 'gpt-5-nano',
              contextSummary: StudioContextSummary(
                rootPath: project.path,
                projectLabel: 'project',
              ),
              status: StudioTurnStatus.failed,
              lastError: 'Provider timed out.',
              createdAt: now,
              updatedAt: now,
              completedAt: now.add(const Duration(seconds: 1)),
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      ]);

      final loaded = await store.load(project.path);
      final loadedThread = loaded.single;

      expect(loadedThread.status, StudioThreadStatus.failed);
      expect(loadedThread.phase, StudioSendPhase.failed);
      expect(loadedThread.requestId, isNull);
      expect(loadedThread.streamingContent, isEmpty);
      expect(loadedThread.lastError, 'Provider timed out.');
      expect(loadedThread.turns.single.status, StudioTurnStatus.failed);
    },
  );

  test(
    'StudioThreadStore expires pending approvals when reopening interrupted turn',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final now = DateTime(2026);

      final approvalEvent = StudioTurnEvent(
        id: 'approval-request-command',
        turnId: 'turn-approval',
        requestId: 'request-approval',
        threadId: 'thread-approval',
        type: StudioTurnEventType.approvalRequest,
        title: 'Approval needed',
        detail: 'Review the command.',
        timestamp: now,
        toolCallId: 'tool-command',
        toolName: 'run_command',
        approvalId: 'approval-command',
        approvalState: ApprovalRequestState.pending,
        approvalPreview: 'Execute: flutter test',
      );

      await store.save(project.path, [
        StudioThread(
          id: 'thread-approval',
          title: 'Waiting for approval',
          status: StudioThreadStatus.waitingForApproval,
          phase: StudioSendPhase.waitingForApproval,
          requestId: 'request-approval',
          turns: [
            StudioTurn(
              id: 'turn-approval',
              threadId: 'thread-approval',
              requestId: 'request-approval',
              userMessageId: 'message-approval',
              prompt: 'verify',
              model: 'gpt-5-nano',
              intent: TurnIntent.verify,
              contextSummary: StudioContextSummary(
                rootPath: project.path,
                projectLabel: 'project',
              ),
              status: StudioTurnStatus.waitingForApproval,
              events: [approvalEvent],
              createdAt: now,
              updatedAt: now,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      ]);

      final loaded = await store.load(project.path);
      final loadedThread = loaded.single;
      final loadedTurn = loadedThread.turns.single;
      final loadedApproval = loadedTurn.events.single;

      expect(loadedThread.status, StudioThreadStatus.failed);
      expect(loadedThread.phase, StudioSendPhase.failed);
      expect(loadedThread.requestId, isNull);
      expect(loadedTurn.status, StudioTurnStatus.failed);
      expect(loadedTurn.completedAt, isNotNull);
      expect(loadedApproval.approvalState, ApprovalRequestState.expired);
      expect(loadedApproval.approvalPreview, 'Execute: flutter test');
    },
  );

  test(
    'StudioThreadStore fails interrupted accepted-plan transaction state',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final now = DateTime(2026);

      await store.save(project.path, [
        StudioThread(
          id: 'thread-accepted-plan-interrupted',
          title: 'Implement accepted plan',
          status: StudioThreadStatus.streaming,
          phase: StudioSendPhase.streaming,
          requestId: 'request-code',
          turns: [
            StudioTurn(
              id: 'turn-code',
              threadId: 'thread-accepted-plan-interrupted',
              requestId: 'request-code',
              userMessageId: 'message-code',
              prompt: 'Implement this plan',
              model: 'gpt-5-nano',
              intent: TurnIntent.code,
              contextSummary: StudioContextSummary(
                rootPath: project.path,
                projectLabel: 'project',
              ),
              status: StudioTurnStatus.streaming,
              acceptedPlanState: AcceptedPlanState.implementationStarted,
              acceptedPlanContext: const AcceptedPlanContext(
                patchSetId: 'plan-1',
                title: 'Plan',
                summary: 'Implement the planned route change.',
                markdown: '- Update lib/router.dart',
                plannedFiles: ['lib/router.dart — Update route behavior'],
              ),
              createdAt: now,
              updatedAt: now,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      ]);

      final loaded = await store.load(project.path);
      final loadedThread = loaded.single;
      final loadedTurn = loadedThread.turns.single;

      expect(loadedThread.status, StudioThreadStatus.failed);
      expect(loadedThread.phase, StudioSendPhase.failed);
      expect(loadedThread.requestId, isNull);
      expect(loadedTurn.status, StudioTurnStatus.failed);
      expect(loadedTurn.acceptedPlanState, AcceptedPlanState.failed);
      expect(loadedTurn.acceptedPlanContext?.patchSetId, 'plan-1');
      expect(
        loadedTurn.lastError,
        contains('Interrupted while CircuitCode was closed'),
      );
    },
  );

  test(
    'StudioThreadStore preserves saved updatedAt while normalizing stale active status',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final savedAt = DateTime(2026, 1, 2, 3, 4, 5);

      await store.save(project.path, [
        StudioThread(
          id: 'thread-stale-active',
          title: 'Completed but stale active',
          status: StudioThreadStatus.streaming,
          phase: StudioSendPhase.streaming,
          requestId: 'request-stale-active',
          streamingContent: 'old draft',
          turns: [
            StudioTurn(
              id: 'turn-complete',
              threadId: 'thread-stale-active',
              requestId: 'request-stale-active',
              userMessageId: 'message-complete',
              prompt: 'done request',
              model: 'gpt-5-nano',
              contextSummary: StudioContextSummary(
                rootPath: project.path,
                projectLabel: 'project',
              ),
              status: StudioTurnStatus.completed,
              createdAt: savedAt,
              updatedAt: savedAt,
              completedAt: savedAt.add(const Duration(seconds: 1)),
            ),
          ],
          createdAt: savedAt,
          updatedAt: savedAt,
        ),
      ]);

      final loaded = await store.load(project.path);
      final loadedThread = loaded.single;

      expect(loadedThread.status, StudioThreadStatus.done);
      expect(loadedThread.requestId, isNull);
      expect(loadedThread.streamingContent, isEmpty);
      expect(loadedThread.updatedAt, savedAt);
    },
  );

  test('StudioThreadStore keeps complete turn history on load', () async {
    final root = await Directory.systemTemp.createTemp('studio_threads_');
    addTearDown(() => root.delete(recursive: true));
    final project = await Directory('${root.path}/project').create();
    final store = StudioThreadStore(baseDir: '${root.path}/history');
    final now = DateTime(2026);

    final turns = [
      for (var index = 0; index < 125; index++)
        StudioTurn(
          id: 'turn-$index',
          threadId: 'thread-history',
          requestId: 'request-$index',
          userMessageId: 'message-$index',
          prompt: 'prompt $index',
          model: 'gpt-5-nano',
          contextSummary: StudioContextSummary(
            rootPath: project.path,
            projectLabel: 'project',
          ),
          status: StudioTurnStatus.completed,
          createdAt: now.add(Duration(minutes: index)),
          updatedAt: now.add(Duration(minutes: index)),
          completedAt: now.add(Duration(minutes: index, seconds: 1)),
        ),
    ];

    await store.save(project.path, [
      StudioThread(
        id: 'thread-history',
        title: 'Long history',
        status: StudioThreadStatus.done,
        phase: StudioSendPhase.completed,
        turns: turns,
        createdAt: now,
        updatedAt: now.add(const Duration(hours: 3)),
      ),
    ]);

    final loaded = await store.load(project.path);

    expect(loaded.single.turns, hasLength(125));
    expect(loaded.single.turns.map((turn) => turn.id), contains('turn-0'));
    expect(loaded.single.turns.map((turn) => turn.id), contains('turn-124'));
  });

  test('StudioThreadStore keeps complete thread history on load', () async {
    final root = await Directory.systemTemp.createTemp('studio_threads_');
    addTearDown(() => root.delete(recursive: true));
    final project = await Directory('${root.path}/project').create();
    final store = StudioThreadStore(baseDir: '${root.path}/history');
    final now = DateTime(2026);

    final threads = [
      for (var index = 0; index < 75; index++)
        StudioThread(
          id: 'thread-$index',
          title: 'Historical thread $index',
          status: StudioThreadStatus.done,
          phase: StudioSendPhase.completed,
          turns: [
            StudioTurn(
              id: 'turn-$index',
              threadId: 'thread-$index',
              requestId: 'request-$index',
              userMessageId: 'message-$index',
              prompt: 'prompt $index',
              model: 'gpt-5-nano',
              contextSummary: StudioContextSummary(
                rootPath: project.path,
                projectLabel: 'project',
              ),
              status: StudioTurnStatus.completed,
              createdAt: now.add(Duration(minutes: index)),
              updatedAt: now.add(Duration(minutes: index)),
              completedAt: now.add(Duration(minutes: index, seconds: 1)),
            ),
          ],
          createdAt: now.add(Duration(minutes: index)),
          updatedAt: now.add(Duration(minutes: index, seconds: 1)),
        ),
    ];

    await store.save(project.path, threads);

    final loaded = await store.load(project.path);

    expect(loaded, hasLength(75));
    expect(loaded.map((thread) => thread.id), contains('thread-0'));
    expect(loaded.map((thread) => thread.id), contains('thread-74'));
    expect(
      loaded
          .firstWhere((thread) => thread.id == 'thread-0')
          .turns
          .single
          .prompt,
      'prompt 0',
    );
    expect(
      loaded
          .firstWhere((thread) => thread.id == 'thread-74')
          .turns
          .single
          .prompt,
      'prompt 74',
    );
  });

  test('StudioTurnEvent preserves absent approval state through JSON', () {
    final event = StudioTurnEvent.assistantMessage(
      turnId: 'turn',
      requestId: 'request',
      threadId: 'thread',
      content: 'Done.',
      timestamp: DateTime(2026),
    );

    final loaded = StudioTurnEvent.fromJson(event.toJson());

    expect(loaded, isNotNull);
    expect(loaded!.type, StudioTurnEventType.assistantMessage);
    expect(loaded.approvalState, isNull);
  });
}
