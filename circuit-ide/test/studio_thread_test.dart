import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/enums/message_role.dart';
import 'package:circuit_ide/models/accepted_plan_context.dart';
import 'package:circuit_ide/models/context_pack.dart';
import 'package:circuit_ide/models/provider_lifecycle_event.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/models/studio_source_artifact.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/models/tool_result_envelope.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/state/studio_turn_provider.dart';
import 'package:circuit_ide/ui/studio/studio_plan_continuation.dart';
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
    final toolEvent = StudioTurnEvent.tool(
      turnId: 'turn',
      requestId: 'request',
      threadId: 'thread',
      toolCallId: 'tool-call',
      toolName: 'read_file',
      title: 'read_file',
      detail: 'completed',
      timestamp: now,
    );
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
    expect(toolEvent.transcriptVisible, isFalse);
    expect(toolEvent.toJson()['transcriptVisible'], isFalse);
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
    expect(loadedA.single.messages, isEmpty);
    expect(loadedA.single.turns.single.prompt, 'hi');
    expect(
      loadedA.single.turns.single.events
          .where((event) => event.type == StudioTurnEventType.assistantMessage)
          .single
          .content,
      'hello back',
    );
    final savedJson =
        jsonDecode(await File(store.historyPath(projectA.path)).readAsString())
            as List<dynamic>;
    expect((savedJson.single as Map<String, dynamic>)['messages'], isEmpty);
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
      expect(thread.messages, isEmpty);
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
      expect(thread.messages, isEmpty);
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
    expect(stateFor(StudioThreadStatus.continuationReady).label, 'Continue');
    expect(
      stateFor(StudioThreadStatus.continuationReady).needsAttention,
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
            steps: [
              TurnStepRecord(
                step: TurnStep.providerRequest,
                status: TurnStepStatus.completed,
                title: 'Provider completed',
                startedAt: now,
                completedAt: now,
              ),
              TurnStepRecord(
                step: TurnStep.streaming,
                status: TurnStepStatus.running,
                title: 'Streaming response',
                detail: 'Receiving text.',
                startedAt: now.add(const Duration(milliseconds: 1)),
              ),
            ],
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
      final steps = loaded.single.turns.single.steps;
      expect(
        steps.firstWhere((step) => step.step == TurnStep.streaming).status,
        TurnStepStatus.failed,
      );
      expect(
        steps.firstWhere((step) => step.step == TurnStep.streaming).detail,
        contains('Interrupted while CircuitCode was closed'),
      );
      expect(
        steps.firstWhere((step) => step.step == TurnStep.finalSummary).status,
        TurnStepStatus.failed,
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

      expect(loadedThread.status, StudioThreadStatus.continuationReady);
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
    'StudioThreadStore preserves partial accepted-plan target progress on load',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final now = DateTime(2026);

      final thread = StudioThread(
        id: 'thread-partial-plan',
        title: 'Implement accepted plan',
        status: StudioThreadStatus.done,
        phase: StudioSendPhase.completed,
        requestId: 'stale-request',
        streamingContent: 'stale draft',
        lastError: 'stale error',
        turns: [
          StudioTurn(
            id: 'turn-partial-plan',
            threadId: 'thread-partial-plan',
            requestId: 'request-partial-plan',
            userMessageId: 'message-partial-plan',
            prompt: 'Implement accepted plan',
            model: 'gpt-5-nano',
            intent: TurnIntent.code,
            contextSummary: StudioContextSummary(
              rootPath: project.path,
              projectLabel: 'project',
            ),
            status: StudioTurnStatus.completed,
            acceptedPlanState: AcceptedPlanState.patchProposed,
            acceptedPlanContext: const AcceptedPlanContext(
              patchSetId: 'plan-partial',
              title: 'Datacenter sizing MVP',
              summary: 'Implement the first batch of the accepted MVP plan.',
              markdown:
                  '# Plan\n\n- Create core sizing model\n- Document usage',
              plannedFiles: [
                'lib/sizer.dart — Create core sizing model',
                'README.md — Document usage',
              ],
            ),
            planTargetProgress: [
              PlanTargetProgress(
                path: 'lib/sizer.dart',
                intent: 'Create core sizing model',
                operation: ProposedFileEditType.create,
                state: PlanTargetProgressState.applied,
                patchSetId: 'patch-batch-1',
                detail: 'Applied in first batch.',
                updatedAt: now.add(const Duration(milliseconds: 1)),
              ),
              PlanTargetProgress(
                path: 'README.md',
                intent: 'Document usage',
                operation: ProposedFileEditType.create,
                state: PlanTargetProgressState.pending,
                updatedAt: now.add(const Duration(milliseconds: 1)),
              ),
            ],
            toolResults: const [
              ToolResultEnvelope(
                toolCallId: 'tool-patch-batch-1',
                toolName: 'propose_patch',
                status: ToolResultStatus.success,
                summary: 'Prepared first implementation batch.',
                artifacts: ['patch-batch-1'],
                changedFiles: ['lib/sizer.dart'],
              ),
            ],
            events: [
              StudioTurnEvent.completionSummary(
                id: 'patch-transaction-turn-partial-plan-patch-batch-1',
                turnId: 'turn-partial-plan',
                requestId: 'request-partial-plan',
                threadId: 'thread-partial-plan',
                title: 'Applied changes',
                detail: [
                  'Applied 1 files.',
                  'Files: lib/sizer.dart',
                  'Checkpoint: checkpoint-partial',
                  '- Created lib/sizer.dart (+42 lines)',
                  'Suggested checks: dart test',
                  'Patch: Datacenter sizing MVP first batch',
                ].join('\n'),
                timestamp: now.add(const Duration(milliseconds: 2)),
              ),
            ],
            createdAt: now,
            updatedAt: now.add(const Duration(milliseconds: 2)),
            completedAt: now.add(const Duration(milliseconds: 2)),
          ),
        ],
        createdAt: now,
        updatedAt: now.add(const Duration(milliseconds: 2)),
      );

      await store.save(project.path, [thread]);

      final loaded = await store.load(project.path);
      final loadedThread = loaded.single;
      final loadedTurn = loadedThread.turns.single;

      expect(loadedThread.status, StudioThreadStatus.continuationReady);
      expect(loadedThread.phase, StudioSendPhase.completed);
      expect(loadedThread.requestId, isNull);
      expect(loadedThread.streamingContent, isEmpty);
      expect(loadedThread.lastError, isNull);
      expect(loadedTurn.status, StudioTurnStatus.completed);
      expect(loadedTurn.acceptedPlanState, AcceptedPlanState.patchProposed);
      expect(loadedTurn.acceptedPlanContext?.patchSetId, 'plan-partial');
      expect(loadedTurn.lastError, isNull);
      expect(
        loadedTurn.planTargetProgress
            .where((target) => target.path == 'lib/sizer.dart')
            .single
            .state,
        PlanTargetProgressState.applied,
      );
      expect(
        loadedTurn.planTargetProgress
            .where((target) => target.path == 'README.md')
            .single
            .state,
        PlanTargetProgressState.pending,
      );
      expect(loadedTurn.toolResults.single.changedFiles, ['lib/sizer.dart']);
      final transaction = loadedTurn.events
          .where(
            (event) =>
                event.type == StudioTurnEventType.completionSummary &&
                event.id.startsWith('patch-transaction-'),
          )
          .single;
      expect(transaction.title, 'Applied changes');
      expect(transaction.detail, contains('Checkpoint: checkpoint-partial'));
      expect(transaction.detail, contains('Created lib/sizer.dart'));
    },
  );

  test(
    'accepted plan remains actionable when a conflict target still needs work',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Accepted plan conflict');
      const acceptedPlan = AcceptedPlanContext(
        patchSetId: 'plan-conflict',
        title: 'Two file plan',
        summary: 'Implement two planned files.',
        markdown: '# Plan\n\n- Create app shell\n- Document usage',
        plannedFiles: [
          'lib/app.dart — Create app shell',
          'README.md — Document usage',
        ],
      );
      final turn = container
          .read(studioTurnProvider.notifier)
          .registerTurn(
            requestId: 'request-conflict-plan',
            threadId: thread.id,
            taskId: null,
            userMessageId: 'message-conflict-plan',
            prompt: 'Implement accepted plan',
            model: 'gpt-5-nano',
            contextSummary: const StudioContextSummary(
              rootPath: '/tmp/project',
              projectLabel: 'project',
            ),
            intent: TurnIntent.code,
            acceptedPlanState: AcceptedPlanState.patchProposed,
            acceptedPlanContext: acceptedPlan,
            userMessageTranscriptVisible: false,
          );
      container
          .read(studioTurnProvider.notifier)
          .updatePlanTargetProgress(
            'request-conflict-plan',
            patchSetId: 'patch-conflict',
            paths: const ['lib/app.dart'],
            targetState: PlanTargetProgressState.conflict,
            detail: 'File changed since proposal.',
          );

      container
          .read(studioTurnProvider.notifier)
          .recordPatchTransaction(
            'request-conflict-plan',
            patchSetId: 'patch-docs',
            title: 'Applied changes',
            detail: 'Applied 1 files.\nFiles: README.md',
            paths: const ['README.md'],
            applyStatus: PatchApplyStatus.applied,
          );

      final updatedTurn = container
          .read(studioThreadProvider)
          .threads
          .where((candidate) => candidate.id == thread.id)
          .single
          .turns
          .where((candidate) => candidate.id == turn.id)
          .single;
      expect(updatedTurn.acceptedPlanState, AcceptedPlanState.patchProposed);
      expect(
        updatedTurn.planTargetProgress
            .where((target) => target.path == 'lib/app.dart')
            .single
            .state,
        PlanTargetProgressState.conflict,
      );
      expect(
        updatedTurn.planTargetProgress
            .where((target) => target.path == 'README.md')
            .single
            .state,
        PlanTargetProgressState.applied,
      );
      final transaction = updatedTurn.events
          .where(
            (event) =>
                event.type == StudioTurnEventType.completionSummary &&
                event.id.startsWith('patch-transaction-'),
          )
          .single;
      expect(transaction.detail, contains('Next batch: 1'));
      expect(transaction.detail, contains('lib/app.dart'));
      expect(
        transaction.detail,
        isNot(contains('all planned targets are complete')),
      );

      final continuation = studioPlanContinuationForTurn(updatedTurn);
      expect(continuation, isNotNull);
      expect(
        continuation!.acceptedPlan.markdown,
        contains(
          'lib/app.dart — Create app shell (patch conflict needs rebase/revision; File changed since proposal.)',
        ),
      );
      expect(continuation.acceptedPlan.markdown, isNot(contains('README.md')));
    },
  );

  test(
    'patch conflict transactions upsert by conflicted file across retries',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Patch conflict retry');
      final turn = container
          .read(studioTurnProvider.notifier)
          .registerTurn(
            requestId: 'request-conflict-retry',
            threadId: thread.id,
            taskId: null,
            userMessageId: 'message-conflict-retry',
            prompt: 'Apply patch',
            model: 'gpt-5-nano',
            contextSummary: const StudioContextSummary(
              rootPath: '/tmp/project',
              projectLabel: 'project',
            ),
            intent: TurnIntent.code,
          );

      final notifier = container.read(studioTurnProvider.notifier);
      notifier.recordPatchTransaction(
        'request-conflict-retry',
        patchSetId: 'patch-retry-1',
        title: 'Patch conflict',
        detail: 'File changed since proposal: plan/01_mvp_requirements.md',
        paths: const ['plan/01_mvp_requirements.md'],
        applyStatus: PatchApplyStatus.conflict,
      );
      notifier.recordPatchTransaction(
        'request-conflict-retry',
        patchSetId: 'patch-retry-2',
        title: 'Patch conflict',
        detail:
            'File changed since proposal: plan/01_mvp_requirements.md\nAsk Circuit to rebase the proposal.',
        paths: const ['plan/01_mvp_requirements.md'],
        applyStatus: PatchApplyStatus.conflict,
      );

      final updatedTurn = container
          .read(studioThreadProvider)
          .threads
          .where((candidate) => candidate.id == thread.id)
          .single
          .turns
          .where((candidate) => candidate.id == turn.id)
          .single;
      final conflictEvents = updatedTurn.events.where(
        (event) =>
            event.type == StudioTurnEventType.completionSummary &&
            event.title == 'Patch conflict',
      );
      expect(conflictEvents, hasLength(1));
      expect(
        conflictEvents.single.id,
        'patch-transaction-${turn.id}-conflict-plan-01-mvp-requirements-md',
      );
      expect(conflictEvents.single.detail, contains('rebase the proposal'));
    },
  );

  test('patch conflict transactions include rebase recovery guidance', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Patch conflict guidance');
    final turn = container
        .read(studioTurnProvider.notifier)
        .registerTurn(
          requestId: 'request-conflict-guidance',
          threadId: thread.id,
          taskId: null,
          userMessageId: 'message-conflict-guidance',
          prompt: 'Apply patch',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(
            rootPath: '/tmp/project',
            projectLabel: 'project',
          ),
          intent: TurnIntent.code,
        );

    container
        .read(studioTurnProvider.notifier)
        .recordPatchTransaction(
          'request-conflict-guidance',
          patchSetId: 'patch-conflict-guidance',
          title: 'Patch conflict',
          detail: 'File changed since proposal: README.md',
          paths: const ['README.md'],
          applyStatus: PatchApplyStatus.conflict,
        );

    final updatedTurn = container
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == thread.id)
        .single
        .turns
        .where((candidate) => candidate.id == turn.id)
        .single;
    final event = updatedTurn.events
        .where(
          (candidate) =>
              candidate.type == StudioTurnEventType.completionSummary &&
              candidate.title == 'Patch conflict',
        )
        .single;
    expect(event.detail, contains('Ask Circuit to rebase the proposal'));
    final patchStep = updatedTurn.steps
        .where((candidate) => candidate.step == TurnStep.patchProposal)
        .single;
    expect(patchStep.status, TurnStepStatus.failed);
    expect(patchStep.detail, contains('Ask Circuit to rebase the proposal'));
  });

  test('applied patch with suggested checks queues verification step', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Patch verification step');
    final turn = container
        .read(studioTurnProvider.notifier)
        .registerTurn(
          requestId: 'request-verification-step',
          threadId: thread.id,
          taskId: null,
          userMessageId: 'message-verification-step',
          prompt: 'Apply patch',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(
            rootPath: '/tmp/project',
            projectLabel: 'project',
          ),
          intent: TurnIntent.code,
        );

    container
        .read(studioTurnProvider.notifier)
        .recordPatchTransaction(
          'request-verification-step',
          patchSetId: 'patch-verification-step',
          title: 'Applied changes',
          detail:
              'Applied 1 files.\nHere’s what changed: lib/main.dart\nSuggested checks: flutter analyze · flutter test\nVerification was requested for this patch.',
          paths: const ['lib/main.dart'],
          applyStatus: PatchApplyStatus.applied,
        );

    final updatedTurn = container
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == thread.id)
        .single
        .turns
        .where((candidate) => candidate.id == turn.id)
        .single;
    final verificationStep = updatedTurn.steps
        .where((step) => step.step == TurnStep.verification)
        .single;
    expect(verificationStep.status, TurnStepStatus.queued);
    expect(verificationStep.title, 'Verification ready');
    expect(verificationStep.detail, contains('Suggested checks'));
    expect(verificationStep.detail, contains('Verification was requested'));
  });

  test('failed verification command is journaled as a failed outcome', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Failed verification journal');
    container
        .read(studioTurnProvider.notifier)
        .registerTurn(
          requestId: 'request-failed-verify-command',
          threadId: thread.id,
          taskId: null,
          userMessageId: 'message-failed-verify-command',
          prompt: 'Run verification',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(
            rootPath: '/tmp/project',
            projectLabel: 'project',
          ),
          intent: TurnIntent.verify,
        );
    container
        .read(studioTurnProvider.notifier)
        .complete(
          'request-failed-verify-command',
          content: 'Verification finished with a failing check.',
        );

    container
        .read(studioTurnProvider.notifier)
        .recordCommandRunResult(
          'request-failed-verify-command',
          commandRunId: 'cmd-failed-verify',
          command: 'flutter test',
          status: 'failed',
          output: 'Some tests failed',
          exitCode: 1,
        );

    final updatedTurn = container
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == thread.id)
        .single
        .turns
        .single;
    final commandRunStep = updatedTurn.steps
        .where((step) => step.step == TurnStep.commandRun)
        .single;
    expect(commandRunStep.status, TurnStepStatus.failed);
    expect(commandRunStep.title, 'Command failed');
    expect(commandRunStep.detail, contains('Command: flutter test'));
    expect(commandRunStep.detail, contains('Exit code: 1'));
    expect(commandRunStep.detail, contains('Some tests failed'));

    final verificationStep = updatedTurn.steps
        .where((step) => step.step == TurnStep.verification)
        .single;
    expect(verificationStep.status, TurnStepStatus.failed);
    expect(verificationStep.detail, contains('Some tests failed'));

    final event = updatedTurn.events
        .where(
          (candidate) =>
              candidate.id == 'command-run-${updatedTurn.id}-cmd-failed-verify',
        )
        .single;
    expect(event.title, 'Command failed');
    expect(event.detail, contains('Exit code: 1'));
    expect(event.detail, contains('Some tests failed'));
  });

  test('active verification command is journaled before turn archive', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Active command journal');
    container
        .read(studioTurnProvider.notifier)
        .registerTurn(
          requestId: 'request-active-command',
          threadId: thread.id,
          taskId: null,
          userMessageId: 'message-active-command',
          prompt: 'Run verification',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(
            rootPath: '/tmp/project',
            projectLabel: 'project',
          ),
          intent: TurnIntent.verify,
        );

    container
        .read(studioTurnProvider.notifier)
        .recordCommandRunResult(
          'request-active-command',
          commandRunId: 'cmd-active',
          command: 'flutter analyze',
          status: 'succeeded',
          output: 'No issues found!',
          exitCode: 0,
        );

    final activeTurn = container
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == thread.id)
        .single
        .turns
        .single;
    expect(activeTurn.status, StudioTurnStatus.buildingContext);
    final commandRunStep = activeTurn.steps
        .where((step) => step.step == TurnStep.commandRun)
        .single;
    expect(commandRunStep.status, TurnStepStatus.completed);
    expect(commandRunStep.detail, contains('Command: flutter analyze'));
    expect(commandRunStep.detail, contains('No issues found!'));
    final event = activeTurn.events
        .where(
          (candidate) =>
              candidate.id == 'command-run-${activeTurn.id}-cmd-active',
        )
        .single;
    expect(event.title, 'Ran command');
    expect(event.detail, contains('Exit code: 0'));

    container
        .read(studioTurnProvider.notifier)
        .complete('request-active-command', content: 'Verification passed.');
    final completedTurn = container
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == thread.id)
        .single
        .turns
        .single;
    expect(completedTurn.status, StudioTurnStatus.completed);
    expect(
      completedTurn.events
          .where(
            (candidate) =>
                candidate.id == 'command-run-${completedTurn.id}-cmd-active',
          )
          .single
          .detail,
      contains('No issues found!'),
    );
  });

  test('active provider diagnostics are journaled before turn archive', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Active provider diagnostics');
    container
        .read(studioTurnProvider.notifier)
        .registerTurn(
          requestId: 'request-active-provider',
          threadId: thread.id,
          taskId: null,
          userMessageId: 'message-active-provider',
          prompt: 'Stream a response',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(
            rootPath: '/tmp/project',
            projectLabel: 'project',
          ),
          intent: TurnIntent.ask,
        );

    container
        .read(studioTurnProvider.notifier)
        .addProviderDiagnostic(
          'request-active-provider',
          ProviderLifecycleEvent(
            requestId: 'request-active-provider',
            turnId: 'turn-active-provider',
            model: 'gpt-5-nano',
            kind: ProviderLifecycleEventKind.firstByte,
            timestamp: DateTime(2026),
            detail: 'Circuit AI started responding.',
          ),
        );
    container
        .read(studioTurnProvider.notifier)
        .addProviderDiagnostic(
          'request-active-provider',
          ProviderLifecycleEvent(
            requestId: 'request-active-provider',
            turnId: 'turn-active-provider',
            model: 'gpt-5-nano',
            kind: ProviderLifecycleEventKind.firstTextDelta,
            timestamp: DateTime(2026, 1, 1, 0, 0, 1),
            detail: 'First streamed token arrived.',
          ),
        );

    final activeTurn = container
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == thread.id)
        .single
        .turns
        .single;
    expect(activeTurn.providerDiagnostics.map((event) => event.kind), [
      ProviderLifecycleEventKind.firstByte,
      ProviderLifecycleEventKind.firstTextDelta,
    ]);
    final providerStep = activeTurn.steps
        .where((step) => step.step == TurnStep.providerRequest)
        .single;
    expect(providerStep.status, TurnStepStatus.running);
    expect(providerStep.title, 'First byte received');
    expect(providerStep.detail, 'Circuit AI started responding.');
    final streamingStep = activeTurn.steps
        .where((step) => step.step == TurnStep.streaming)
        .single;
    expect(streamingStep.status, TurnStepStatus.running);
    expect(streamingStep.title, 'First text received');
    expect(streamingStep.detail, 'First streamed token arrived.');

    container
        .read(studioTurnProvider.notifier)
        .complete('request-active-provider', content: 'Streaming completed.');
    final completedTurn = container
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == thread.id)
        .single
        .turns
        .single;
    expect(completedTurn.status, StudioTurnStatus.completed);
    expect(completedTurn.providerDiagnostics.map((event) => event.kind), [
      ProviderLifecycleEventKind.firstByte,
      ProviderLifecycleEventKind.firstTextDelta,
    ]);
  });

  test('applied accepted-plan patch queues continuation step', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Patch continuation step');
    const acceptedPlan = AcceptedPlanContext(
      patchSetId: 'plan-continuation-step',
      title: 'Continuation plan',
      summary: 'Implement two files in batches.',
      markdown: '- Create lib/main.dart\n- Create README.md',
      plannedFiles: [
        'lib/main.dart — Create entry point',
        'README.md — Document usage',
      ],
      plannedTargets: [
        PlannedFileTarget(
          path: 'lib/main.dart',
          intent: 'Create entry point',
          operation: ProposedFileEditType.create,
        ),
        PlannedFileTarget(
          path: 'README.md',
          intent: 'Document usage',
          operation: ProposedFileEditType.create,
        ),
      ],
    );
    final turn = container
        .read(studioTurnProvider.notifier)
        .registerTurn(
          requestId: 'request-continuation-step',
          threadId: thread.id,
          taskId: null,
          userMessageId: 'message-continuation-step',
          prompt: 'Implement this approved plan.',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(
            rootPath: '/tmp/project',
            projectLabel: 'project',
          ),
          intent: TurnIntent.code,
          acceptedPlanState: AcceptedPlanState.implementationStarted,
          acceptedPlanContext: acceptedPlan,
        );

    container
        .read(studioTurnProvider.notifier)
        .recordPatchTransaction(
          'request-continuation-step',
          patchSetId: 'patch-continuation-step',
          title: 'Applied changes',
          detail:
              'Applied 1 files.\nHere’s what changed: lib/main.dart\nCheckpoint: checkpoint-continuation',
          paths: const ['lib/main.dart'],
          applyStatus: PatchApplyStatus.applied,
        );

    final updatedTurn = container
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == thread.id)
        .single
        .turns
        .where((candidate) => candidate.id == turn.id)
        .single;
    final continuationStep = updatedTurn.steps
        .where((step) => step.step == TurnStep.continuation)
        .single;
    expect(continuationStep.status, TurnStepStatus.queued);
    expect(continuationStep.title, 'Continue next batch');
    expect(continuationStep.detail, contains('1 accepted-plan target'));
    expect(continuationStep.detail, contains('README.md'));
    final updatedThread = container
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == thread.id)
        .single;
    expect(updatedThread.status, StudioThreadStatus.continuationReady);
    expect(
      StudioTaskLifecycleState.fromThread(updatedThread).label,
      'Continue',
    );
    final transaction = updatedTurn.events
        .where(
          (event) =>
              event.type == StudioTurnEventType.completionSummary &&
              event.title == 'Applied changes',
        )
        .single;
    expect(transaction.detail, contains('Next batch: 1 accepted-plan target'));
    expect(transaction.detail, contains('README.md'));
  });

  test('final accepted-plan patch completes without continuation step', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Patch final step');
    const acceptedPlan = AcceptedPlanContext(
      patchSetId: 'plan-final-step',
      title: 'Final plan',
      summary: 'Implement two files in one final batch.',
      markdown: '- Create lib/main.dart\n- Create README.md',
      plannedFiles: [
        'lib/main.dart — Create entry point',
        'README.md — Document usage',
      ],
      plannedTargets: [
        PlannedFileTarget(
          path: 'lib/main.dart',
          intent: 'Create entry point',
          operation: ProposedFileEditType.create,
        ),
        PlannedFileTarget(
          path: 'README.md',
          intent: 'Document usage',
          operation: ProposedFileEditType.create,
        ),
      ],
    );
    final turn = container
        .read(studioTurnProvider.notifier)
        .registerTurn(
          requestId: 'request-final-step',
          threadId: thread.id,
          taskId: null,
          userMessageId: 'message-final-step',
          prompt: 'Implement this approved plan.',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(
            rootPath: '/tmp/project',
            projectLabel: 'project',
          ),
          intent: TurnIntent.code,
          acceptedPlanState: AcceptedPlanState.implementationStarted,
          acceptedPlanContext: acceptedPlan,
        );

    container
        .read(studioTurnProvider.notifier)
        .recordPatchTransaction(
          'request-final-step',
          patchSetId: 'patch-final-step',
          title: 'Applied changes',
          detail:
              'Applied 2 files.\nHere’s what changed: lib/main.dart, README.md\nCheckpoint: checkpoint-final',
          paths: const ['lib/main.dart', 'README.md'],
          applyStatus: PatchApplyStatus.applied,
        );

    final updatedThread = container
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == thread.id)
        .single;
    final updatedTurn = updatedThread.turns
        .where((candidate) => candidate.id == turn.id)
        .single;
    expect(updatedThread.status, StudioThreadStatus.done);
    expect(
      StudioTaskLifecycleState.fromThread(updatedThread).label,
      isNot('Continue'),
    );
    expect(updatedTurn.status, StudioTurnStatus.completed);
    expect(updatedTurn.acceptedPlanState, AcceptedPlanState.implemented);
    expect(
      updatedTurn.steps.where((step) => step.step == TurnStep.continuation),
      isEmpty,
    );
    expect(
      updatedTurn.planTargetProgress.map((target) => target.state).toSet(),
      {PlanTargetProgressState.applied},
    );
    final transaction = updatedTurn.events
        .where(
          (event) =>
              event.type == StudioTurnEventType.completionSummary &&
              event.title == 'Applied changes',
        )
        .single;
    expect(transaction.detail, contains('Applied 2 files.'));
    expect(
      transaction.detail,
      contains('Accepted plan progress: all planned targets are complete.'),
    );
    expect(transaction.detail, isNot(contains('Continue next batch')));
  });

  test(
    'StudioThreadStore reloads partial accepted-plan apply as continuation ready',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final now = DateTime(2026);
      final turn = StudioTurn(
        id: 'turn-continuation-reload',
        threadId: 'thread-continuation-reload',
        requestId: 'request-continuation-reload',
        userMessageId: 'message-continuation-reload',
        prompt: 'Implement approved plan',
        model: 'gpt-5-nano',
        contextSummary: StudioContextSummary(
          rootPath: project.path,
          projectLabel: 'project',
        ),
        status: StudioTurnStatus.completed,
        acceptedPlanState: AcceptedPlanState.patchProposed,
        steps: [
          TurnStepRecord(
            step: TurnStep.patchProposal,
            status: TurnStepStatus.completed,
            title: 'Applied changes',
            detail: 'Applied first batch.',
            startedAt: now,
            completedAt: now,
          ),
          TurnStepRecord(
            step: TurnStep.continuation,
            status: TurnStepStatus.queued,
            title: 'Continue next batch',
            detail: '1 accepted-plan target still needs work (README.md).',
            startedAt: now,
          ),
        ],
        events: [
          StudioTurnEvent.completionSummary(
            id: 'patch-transaction-continuation-reload',
            turnId: 'turn-continuation-reload',
            requestId: 'request-continuation-reload',
            threadId: 'thread-continuation-reload',
            title: 'Applied changes',
            detail:
                'Applied 1 files.\nNext batch: 1 accepted-plan target still needs work (README.md). Use Continue next batch to keep implementing the accepted plan.',
            patchSetId: 'patch-continuation-reload',
            timestamp: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
        completedAt: now,
      );
      final thread = StudioThread(
        id: 'thread-continuation-reload',
        title: 'Continuation reload',
        status: StudioThreadStatus.continuationReady,
        phase: StudioSendPhase.completed,
        requestId: 'stale-request',
        streamingContent: 'stale stream',
        turns: [turn],
        lastError: 'Provider failed after the apply event.',
        createdAt: now,
        updatedAt: now,
      );

      await store.save(project.path, [thread]);

      final loaded = await store.load(project.path);

      expect(loaded, hasLength(1));
      expect(loaded.single.status, StudioThreadStatus.continuationReady);
      expect(loaded.single.phase, StudioSendPhase.completed);
      expect(loaded.single.requestId, isNull);
      expect(loaded.single.streamingContent, isEmpty);
      expect(loaded.single.lastError, isNull);
      expect(loaded.single.turns.single.status, StudioTurnStatus.completed);
      expect(
        loaded.single.turns.single.steps
            .where((step) => step.step == TurnStep.continuation)
            .single
            .status,
        TurnStepStatus.queued,
      );
      expect(
        StudioTaskLifecycleState.fromThread(loaded.single).label,
        'Continue',
      );
    },
  );

  test(
    'StudioThreadStore reloads patch conflict as review without stale provider error',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final now = DateTime(2026);
      final turn = StudioTurn(
        id: 'turn-conflict-reload',
        threadId: 'thread-conflict-reload',
        requestId: 'request-conflict-reload',
        userMessageId: 'message-conflict-reload',
        prompt: 'Implement approved plan',
        model: 'gpt-5-nano',
        contextSummary: StudioContextSummary(
          rootPath: project.path,
          projectLabel: 'project',
        ),
        status: StudioTurnStatus.completed,
        acceptedPlanState: AcceptedPlanState.patchProposed,
        steps: [
          TurnStepRecord(
            step: TurnStep.patchProposal,
            status: TurnStepStatus.failed,
            title: 'Patch conflict',
            detail:
                'File changed since proposal: plan/01_mvp_requirements.md\nAsk Circuit to rebase the proposal.',
            startedAt: now,
            completedAt: now,
          ),
        ],
        events: [
          StudioTurnEvent.completionSummary(
            id: 'patch-conflict-conflict-reload',
            turnId: 'turn-conflict-reload',
            requestId: 'request-conflict-reload',
            threadId: 'thread-conflict-reload',
            title: 'Patch conflict',
            detail:
                'File changed since proposal: plan/01_mvp_requirements.md\nAsk Circuit to rebase the proposal.',
            patchSetId: 'patch-conflict-reload',
            timestamp: now,
          ),
        ],
        providerDiagnostics: [
          ProviderLifecycleEvent(
            requestId: 'request-conflict-reload',
            turnId: 'turn-conflict-reload',
            kind: ProviderLifecycleEventKind.outcomeRejected,
            timestamp: now,
            model: 'gpt-5-nano',
            detail:
                'Runtime rejected the model outcome after a patch conflict.',
          ),
        ],
        createdAt: now,
        updatedAt: now,
        completedAt: now,
        lastError: 'Provider failed after patch conflict was recorded.',
      );
      final thread = StudioThread(
        id: 'thread-conflict-reload',
        title: 'Patch conflict reload',
        status: StudioThreadStatus.failed,
        phase: StudioSendPhase.failed,
        requestId: 'stale-request',
        streamingContent: 'stale stream',
        turns: [turn],
        lastError: 'Provider failed after patch conflict was recorded.',
        createdAt: now,
        updatedAt: now,
      );

      await store.save(project.path, [thread]);

      final loaded = await store.load(project.path);

      expect(loaded, hasLength(1));
      expect(loaded.single.status, StudioThreadStatus.reviewingPatch);
      expect(loaded.single.phase, StudioSendPhase.completed);
      expect(loaded.single.requestId, isNull);
      expect(loaded.single.streamingContent, isEmpty);
      expect(loaded.single.lastError, isNull);
      expect(
        StudioTaskLifecycleState.fromThread(loaded.single).label,
        'Review',
      );
      expect(
        loaded.single.turns.single.events
            .where((event) => event.title == 'Patch conflict')
            .single
            .detail,
        contains('rebase the proposal'),
      );
    },
  );

  test('accepted-plan directory targets are updated by child file patches', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Directory target plan');
    const acceptedPlan = AcceptedPlanContext(
      patchSetId: 'plan-directory-targets',
      title: 'Directory target plan',
      summary: 'Create frontend and backend folders.',
      markdown: '- Create frontend/webform/\n- Create backend/server/',
      plannedFiles: [
        'frontend/webform/ — Create web form directory',
        'backend/server/ — Create server directory',
        'docs/discovery_plan.md — Document discovery plan',
      ],
    );
    final turn = container
        .read(studioTurnProvider.notifier)
        .registerTurn(
          requestId: 'request-directory-targets',
          threadId: thread.id,
          taskId: null,
          userMessageId: 'message-directory-targets',
          prompt: 'Implement accepted plan',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(
            rootPath: '/tmp/project',
            projectLabel: 'project',
          ),
          intent: TurnIntent.code,
          acceptedPlanState: AcceptedPlanState.patchProposed,
          acceptedPlanContext: acceptedPlan,
          userMessageTranscriptVisible: false,
        );

    container
        .read(studioTurnProvider.notifier)
        .recordPatchTransaction(
          'request-directory-targets',
          patchSetId: 'patch-directory-targets',
          title: 'Applied changes',
          detail:
              'Applied 2 files.\nFiles: frontend/webform/index.html, backend/server/app.py',
          paths: const ['frontend/webform/index.html', 'backend/server/app.py'],
          applyStatus: PatchApplyStatus.applied,
        );

    final updatedTurn = container
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == thread.id)
        .single
        .turns
        .where((candidate) => candidate.id == turn.id)
        .single;
    expect(updatedTurn.acceptedPlanState, AcceptedPlanState.patchProposed);
    expect(
      updatedTurn.planTargetProgress
          .where((target) => target.path == 'frontend/webform/')
          .single
          .state,
      PlanTargetProgressState.applied,
    );
    expect(
      updatedTurn.planTargetProgress
          .where((target) => target.path == 'backend/server/')
          .single
          .state,
      PlanTargetProgressState.applied,
    );
    expect(
      updatedTurn.planTargetProgress
          .where((target) => target.path == 'docs/discovery_plan.md')
          .single
          .state,
      PlanTargetProgressState.pending,
    );
    final transaction = updatedTurn.events
        .where(
          (event) =>
              event.type == StudioTurnEventType.completionSummary &&
              event.id.startsWith('patch-transaction-'),
        )
        .single;
    expect(transaction.detail, contains('Next batch: 1'));
    expect(transaction.detail, contains('docs/discovery_plan.md'));
    expect(
      transaction.detail,
      isNot(contains('still need work (frontend/webform/')),
    );
    expect(
      transaction.detail,
      isNot(contains('still need work (backend/server/')),
    );
  });

  test('patch revision requests keep accepted-plan targets actionable', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Patch revision state');
    const acceptedPlan = AcceptedPlanContext(
      patchSetId: 'plan-revision',
      title: 'Revision plan',
      summary: 'Update config.',
      markdown: '- Modify config.txt',
      plannedFiles: ['config.txt — Update config'],
    );
    final turn = container
        .read(studioTurnProvider.notifier)
        .registerTurn(
          requestId: 'request-revision-state',
          threadId: thread.id,
          taskId: null,
          userMessageId: 'message-revision-state',
          prompt: 'Implement accepted plan',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(
            rootPath: '/tmp/project',
            projectLabel: 'project',
          ),
          intent: TurnIntent.code,
          acceptedPlanState: AcceptedPlanState.patchProposed,
          acceptedPlanContext: acceptedPlan,
          userMessageTranscriptVisible: false,
        );
    final notifier = container.read(studioTurnProvider.notifier);
    notifier.recordPatchTransaction(
      'request-revision-state',
      patchSetId: 'patch-revision-state',
      title: 'Patch conflict',
      detail: 'File changed since proposal: config.txt',
      paths: const ['config.txt'],
      applyStatus: PatchApplyStatus.conflict,
    );
    notifier.recordPatchTransaction(
      'request-revision-state',
      patchSetId: 'patch-revision-state',
      title: 'Patch revision requested',
      detail:
          'Patch revision requested.\nUse current config.txt contents.\nPatch: Update config',
      paths: const ['config.txt'],
      applyStatus: PatchApplyStatus.revisionRequested,
    );

    final updatedTurn = container
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == thread.id)
        .single
        .turns
        .where((candidate) => candidate.id == turn.id)
        .single;
    expect(updatedTurn.acceptedPlanState, AcceptedPlanState.patchProposed);
    expect(
      updatedTurn.planTargetProgress.single.state,
      PlanTargetProgressState.proposed,
    );
    expect(
      updatedTurn.events.where((event) => event.title == 'Patch rejected'),
      isEmpty,
    );
    expect(
      updatedTurn.events.where(
        (event) => event.title == 'Patch revision requested',
      ),
      hasLength(1),
    );
    expect(
      updatedTurn.steps
          .where((step) => step.title == 'Patch revision requested')
          .single
          .status,
      TurnStepStatus.queued,
    );
  });

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
      final journalRecords =
          (await File(store.journalPath(project.path)).readAsLines())
              .map((line) => jsonDecode(line) as Map<String, dynamic>)
              .where((record) => record['kind'] == 'patch_transaction')
              .toList(growable: false);
      expect(journalRecords, hasLength(2));
      expect(journalRecords.first['status'], PatchApplyStatus.rejected.name);
      expect(
        journalRecords.last['status'],
        PatchApplyStatus.revisionRequested.name,
      );
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
    'StudioThreadStore expires pending approvals recovered only from journal',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final now = DateTime(2026);

      final approvalEvent = StudioTurnEvent(
        id: 'approval-request-journal-only',
        turnId: 'turn-journal-approval',
        requestId: 'request-journal-approval',
        threadId: 'thread-journal-approval',
        type: StudioTurnEventType.approvalRequest,
        title: 'Approval needed',
        detail: 'Review the command.',
        timestamp: now,
        toolCallId: 'tool-journal-command',
        toolName: 'run_command',
        approvalId: 'approval-journal-command',
        approvalState: ApprovalRequestState.pending,
        approvalPreview: 'Execute: flutter test',
      );

      await store.save(project.path, [
        StudioThread(
          id: 'thread-journal-approval',
          title: 'Journal approval recovery',
          status: StudioThreadStatus.waitingForApproval,
          phase: StudioSendPhase.waitingForApproval,
          requestId: 'request-journal-approval',
          turns: [
            StudioTurn(
              id: 'turn-journal-approval',
              threadId: 'thread-journal-approval',
              requestId: 'request-journal-approval',
              userMessageId: 'message-journal-approval',
              prompt: 'verify',
              model: 'gpt-5-nano',
              intent: TurnIntent.verify,
              contextSummary: StudioContextSummary(
                rootPath: project.path,
                projectLabel: 'project',
              ),
              status: StudioTurnStatus.waitingForApproval,
              events: [
                StudioTurnEvent.userMessage(
                  id: 'message-journal-approval',
                  turnId: 'turn-journal-approval',
                  requestId: 'request-journal-approval',
                  threadId: 'thread-journal-approval',
                  content: 'verify',
                  timestamp: now,
                ),
                approvalEvent,
              ],
              steps: [
                TurnStepRecord(
                  step: TurnStep.approvalWait,
                  status: TurnStepStatus.running,
                  title: 'Waiting for approval',
                  detail: 'Execute: flutter test',
                  startedAt: now,
                ),
              ],
              createdAt: now,
              updatedAt: now,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      await File(store.historyPath(project.path)).delete();
      final journal = File(store.journalPath(project.path));
      final withoutSnapshots = (await journal.readAsLines())
          .where((line) {
            final record = jsonDecode(line) as Map<String, dynamic>;
            return record['kind'] != 'thread_snapshot';
          })
          .join('\n');
      await journal.writeAsString('$withoutSnapshots\n');

      final loaded = await store.load(project.path);
      final loadedThread = loaded.single;
      final loadedTurn = loadedThread.turns.single;
      final approvalEvents = loadedTurn.events
          .where((event) => event.type == StudioTurnEventType.approvalRequest)
          .toList(growable: false);

      expect(loadedThread.status, StudioThreadStatus.failed);
      expect(loadedThread.phase, StudioSendPhase.failed);
      expect(loadedThread.requestId, isNull);
      expect(loadedTurn.status, StudioTurnStatus.failed);
      expect(loadedTurn.completedAt, isNotNull);
      expect(approvalEvents, isNotEmpty);
      expect(approvalEvents.map((event) => event.approvalState).toSet(), {
        ApprovalRequestState.expired,
      });
      expect(
        loadedTurn.steps
            .singleWhere((step) => step.step == TurnStep.approvalWait)
            .status,
        TurnStepStatus.failed,
      );
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

  test(
    'StudioThreadStore prefers newer journal snapshot over stale history file',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final now = DateTime(2026);

      StudioTurn turn(String id, int minutes) => StudioTurn(
        id: id,
        threadId: 'thread-stale-history',
        requestId: 'request-$id',
        userMessageId: 'message-$id',
        prompt: 'prompt $id',
        model: 'gpt-5-nano',
        contextSummary: StudioContextSummary(
          rootPath: project.path,
          projectLabel: 'project',
        ),
        status: StudioTurnStatus.completed,
        createdAt: now.add(Duration(minutes: minutes)),
        updatedAt: now.add(Duration(minutes: minutes)),
        completedAt: now.add(Duration(minutes: minutes, seconds: 1)),
      );

      final oldThread = StudioThread(
        id: 'thread-stale-history',
        title: 'Stale history thread',
        status: StudioThreadStatus.done,
        phase: StudioSendPhase.completed,
        turns: [turn('one', 0)],
        createdAt: now,
        updatedAt: now,
      );
      await store.save(project.path, [oldThread]);

      final newerThread = oldThread.copyWith(
        turns: [turn('one', 0), turn('two', 1)],
        updatedAt: now.add(const Duration(minutes: 1)),
      );
      final journal = File(store.journalPath(project.path));
      final newerSnapshot = {
        'kind': 'thread_snapshot',
        'threadId': newerThread.id,
        'threadTitle': newerThread.title,
        'status': newerThread.status.name,
        'phase': newerThread.phase.name,
        'turnCount': newerThread.turns.length,
        'updatedAt': newerThread.updatedAt.toIso8601String(),
        'capturedAt': DateTime.now()
            .add(const Duration(seconds: 1))
            .toIso8601String(),
        'thread': newerThread.toJson(),
      };
      await journal.writeAsString(
        '${jsonEncode(newerSnapshot)}\n',
        mode: FileMode.append,
        flush: true,
      );

      final loaded = await store.load(project.path);

      expect(loaded, hasLength(1));
      expect(loaded.single.turns, hasLength(2));
      expect(loaded.single.turns.map((loadedTurn) => loadedTurn.id), [
        'one',
        'two',
      ]);
    },
  );

  test('StudioThreadStore writes a persistent turn journal sidecar', () async {
    final root = await Directory.systemTemp.createTemp('studio_threads_');
    addTearDown(() => root.delete(recursive: true));
    final project = await Directory('${root.path}/project').create();
    final store = StudioThreadStore(baseDir: '${root.path}/history');
    final now = DateTime(2026);
    final omittedCandidates = [
      for (var index = 0; index < 25; index++)
        ContextCandidate(
          id: 'candidate-omitted-$index',
          title: 'old_$index.dart',
          path: 'lib/old_$index.dart',
          sourceKind: ContextPackSourceKind.editor,
          score: 64 - index,
          estimatedTokens: 300,
          included: false,
          reason: 'Budget overflow',
        ),
    ];
    final contextRetrieval = ContextRetrievalResult(
      rankedCandidates: [
        const ContextCandidate(
          id: 'candidate-included',
          title: 'main.dart',
          path: 'lib/main.dart',
          sourceKind: ContextPackSourceKind.editor,
          score: 98,
          estimatedTokens: 120,
          included: true,
          reason: 'Direct path mention',
        ),
        ...omittedCandidates,
      ],
      budget: const ContextBudgetReport(
        maxTokens: 1000,
        reservedForResponse: 200,
        availableForContext: 800,
        usedTokens: 120,
      ),
      warnings: const [
        ContextPackWarning(message: 'Omitted candidates for budget.'),
      ],
    );
    final thread = StudioThread(
      id: 'thread-journal',
      title: 'Journal thread',
      status: StudioThreadStatus.done,
      phase: StudioSendPhase.completed,
      turns: [
        StudioTurn(
          id: 'turn-journal',
          threadId: 'thread-journal',
          requestId: 'request-journal',
          userMessageId: 'message-journal',
          prompt: 'verify the patch',
          model: 'gpt-5-nano',
          contextSummary: StudioContextSummary(
            rootPath: project.path,
            projectLabel: 'project',
          ),
          status: StudioTurnStatus.completed,
          acceptedPlanState: AcceptedPlanState.patchProposed,
          acceptedPlanContext: const AcceptedPlanContext(
            patchSetId: 'plan-journal',
            title: 'Journal accepted plan',
            summary: 'Create an entry point and README.',
            markdown: 'Implement lib/main.dart, then document it.',
            plannedFiles: [
              'lib/main.dart — Create entry point',
              'README.md — Document usage',
            ],
            plannedTargets: [
              PlannedFileTarget(
                path: 'lib/main.dart',
                intent: 'Create entry point',
                operation: ProposedFileEditType.create,
              ),
              PlannedFileTarget(
                path: 'README.md',
                intent: 'Document usage',
                operation: ProposedFileEditType.create,
              ),
            ],
            verificationRequested: true,
          ),
          planTargetProgress: [
            PlanTargetProgress(
              path: 'lib/main.dart',
              intent: 'Create entry point',
              operation: ProposedFileEditType.create,
              state: PlanTargetProgressState.proposed,
              patchSetId: 'patch-1',
              detail: 'Prepared in first batch.',
              updatedAt: now.add(const Duration(milliseconds: 3)),
            ),
          ],
          contextRetrieval: contextRetrieval,
          steps: [
            TurnStepRecord(
              step: TurnStep.contextBuild,
              status: TurnStepStatus.completed,
              title: 'Context built',
              detail: 'Loaded project context.',
              startedAt: now,
              completedAt: now,
            ),
            TurnStepRecord(
              step: TurnStep.patchProposal,
              status: TurnStepStatus.completed,
              title: 'Prepared changes',
              detail: 'Prepared first batch.',
              startedAt: now.add(const Duration(milliseconds: 1)),
              completedAt: now.add(const Duration(milliseconds: 2)),
            ),
            TurnStepRecord(
              step: TurnStep.verification,
              status: TurnStepStatus.completed,
              title: 'Ran command',
              detail: 'Command: flutter test\nExit code: 0\nAll tests passed!',
              startedAt: now.add(const Duration(milliseconds: 4)),
              completedAt: now.add(const Duration(milliseconds: 5)),
            ),
            TurnStepRecord(
              step: TurnStep.commandRun,
              status: TurnStepStatus.completed,
              title: 'Ran command',
              detail: 'Command: flutter test\nExit code: 0\nAll tests passed!',
              startedAt: now.add(const Duration(milliseconds: 4)),
              completedAt: now.add(const Duration(milliseconds: 5)),
            ),
          ],
          events: [
            StudioTurnEvent.userMessage(
              id: 'message-journal',
              turnId: 'turn-journal',
              requestId: 'request-journal',
              threadId: 'thread-journal',
              content: 'verify the patch',
              timestamp: now,
            ),
            StudioTurnEvent(
              id: 'approval-request-journal',
              turnId: 'turn-journal',
              requestId: 'request-journal',
              threadId: 'thread-journal',
              type: StudioTurnEventType.approvalRequest,
              title: 'Approval needed',
              detail: 'Review command.',
              timestamp: now.add(const Duration(milliseconds: 1)),
              toolCallId: 'tool-journal',
              toolName: 'run_command',
              approvalId: 'approval-journal',
              approvalState: ApprovalRequestState.approved,
              approvalPreview: 'Execute: flutter test',
              approvalWarnings: ['Shell command requires review.'],
            ),
            StudioTurnEvent.completionSummary(
              id: 'patch-transaction-turn-journal-patch-1',
              turnId: 'turn-journal',
              requestId: 'request-journal',
              threadId: 'thread-journal',
              title: 'Applied changes',
              detail:
                  'Applied 1 files.\nHere’s what changed: lib/main.dart\nCheckpoint: checkpoint-journal\nNext batch: 1 accepted-plan target still needs work (README.md). Use Continue next batch to keep implementing the accepted plan.',
              patchSetId: 'patch-1',
              timestamp: now.add(const Duration(milliseconds: 2)),
            ),
            StudioTurnEvent.completionSummary(
              id: 'patch-transaction-turn-journal-patch-2',
              turnId: 'turn-journal',
              requestId: 'request-journal',
              threadId: 'thread-journal',
              title: 'Applied changes',
              detail:
                  'Applied 2 files.\nFiles: lib/router.dart, README.md\nCheckpoint: checkpoint-files-line',
              patchSetId: 'patch-2',
              timestamp: now.add(const Duration(milliseconds: 3)),
            ),
            StudioTurnEvent.completionSummary(
              id: 'command-run-turn-journal-cmd-journal',
              turnId: 'turn-journal',
              requestId: 'request-journal',
              threadId: 'thread-journal',
              title: 'Ran command',
              detail: 'Command: flutter test\nExit code: 0\nAll tests passed!',
              timestamp: now.add(const Duration(milliseconds: 5)),
            ),
          ],
          toolResults: const [
            ToolResultEnvelope(
              toolCallId: 'tool-journal',
              toolName: 'run_command',
              status: ToolResultStatus.success,
              summary: 'flutter test passed',
              stdout: 'All tests passed!\n',
              data: {'command': 'flutter test', 'exitCode': 0},
            ),
          ],
          providerDiagnostics: [
            ProviderLifecycleEvent(
              requestId: 'request-journal',
              turnId: 'turn-journal',
              kind: ProviderLifecycleEventKind.completed,
              timestamp: now,
              model: 'gpt-5-nano',
              detail: 'completed',
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

    await store.save(project.path, [thread]);

    final journal = File(store.journalPath(project.path));
    expect(await journal.exists(), isTrue);
    final records = (await journal.readAsLines())
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList(growable: false);

    expect(records.map((record) => record['kind']), contains('turn'));
    expect(
      records.map((record) => record['kind']),
      contains('thread_snapshot'),
    );
    expect(records.map((record) => record['kind']), contains('turn_event'));
    expect(records.map((record) => record['kind']), contains('approval'));
    expect(
      records.map((record) => record['kind']),
      contains('context_retrieval'),
    );
    expect(records.map((record) => record['kind']), contains('turn_step'));
    expect(records.map((record) => record['kind']), contains('accepted_plan'));
    expect(records.map((record) => record['kind']), contains('plan_target'));
    expect(
      records.map((record) => record['kind']),
      contains('patch_transaction'),
    );
    expect(records.map((record) => record['kind']), contains('tool_result'));
    expect(
      records.map((record) => record['kind']),
      contains('provider_diagnostic'),
    );
    expect(records.map((record) => record['kind']), contains('command_run'));
    expect(
      records.firstWhere((record) => record['kind'] == 'turn')['status'],
      StudioTurnStatus.completed.name,
    );
    final snapshotRecord = records.firstWhere(
      (record) => record['kind'] == 'thread_snapshot',
    );
    expect(snapshotRecord['threadId'], 'thread-journal');
    expect(snapshotRecord['turnCount'], 1);
    final snapshotThread = snapshotRecord['thread'] as Map<String, dynamic>;
    expect(snapshotThread['id'], 'thread-journal');
    expect(snapshotThread['turns'], isA<List<dynamic>>());
    expect(snapshotThread['turns'], hasLength(1));
    expect(
      ((snapshotThread['turns'] as List<dynamic>).single
          as Map<String, dynamic>)['id'],
      'turn-journal',
    );
    expect(
      records.firstWhere(
        (record) => record['kind'] == 'tool_result',
      )['result']['toolName'],
      'run_command',
    );
    final commandRecord = records.firstWhere(
      (record) => record['kind'] == 'command_run',
    );
    expect(commandRecord['command'], 'flutter test');
    expect(commandRecord['exitCode'], 0);
    expect(commandRecord['stdout'], 'All tests passed!\n');
    final contextRecord = records.firstWhere(
      (record) => record['kind'] == 'context_retrieval',
    );
    expect(contextRecord['includedCount'], 1);
    expect(contextRecord['omittedCount'], 25);
    expect(contextRecord['warningCount'], 1);
    expect(contextRecord['budget']['usedTokens'], 120);
    expect(contextRecord['included'].single['path'], 'lib/main.dart');
    final omittedPaths = (contextRecord['omitted'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map((record) => record['path'])
        .toList(growable: false);
    expect(omittedPaths, hasLength(25));
    expect(omittedPaths, contains('lib/old_0.dart'));
    expect(omittedPaths, contains('lib/old_24.dart'));
    final stepRecords = records
        .where((record) => record['kind'] == 'turn_step')
        .toList(growable: false);
    expect(stepRecords, hasLength(4));
    expect(stepRecords.first['step']['step'], TurnStep.contextBuild.name);
    expect(stepRecords.first['step']['status'], TurnStepStatus.completed.name);
    expect(stepRecords[1]['step']['step'], TurnStep.patchProposal.name);
    expect(stepRecords[1]['step']['detail'], 'Prepared first batch.');
    expect(
      stepRecords.map((record) => record['step']['step']),
      contains(TurnStep.commandRun.name),
    );
    expect(stepRecords.last['step']['step'], TurnStep.commandRun.name);
    expect(stepRecords.last['step']['title'], 'Ran command');
    expect(stepRecords.last['step']['detail'], contains('flutter test'));
    final acceptedPlanRecord = records.firstWhere(
      (record) => record['kind'] == 'accepted_plan',
    );
    expect(acceptedPlanRecord['patchSetId'], 'plan-journal');
    expect(acceptedPlanRecord['title'], 'Journal accepted plan');
    expect(
      acceptedPlanRecord['acceptedPlanState'],
      AcceptedPlanState.patchProposed.name,
    );
    expect(acceptedPlanRecord['plannedFileCount'], 2);
    expect(acceptedPlanRecord['plannedTargetCount'], 2);
    expect(acceptedPlanRecord['verificationRequested'], isTrue);
    expect(
      acceptedPlanRecord['plannedFiles'],
      contains('README.md — Document usage'),
    );
    expect(acceptedPlanRecord['plannedTargets'].first['path'], 'lib/main.dart');
    final planTargetRecord = records.firstWhere(
      (record) => record['kind'] == 'plan_target',
    );
    expect(planTargetRecord['path'], 'lib/main.dart');
    expect(planTargetRecord['state'], PlanTargetProgressState.proposed.name);
    expect(planTargetRecord['patchSetId'], 'patch-1');
    final approvalRecord = records.firstWhere(
      (record) => record['kind'] == 'approval',
    );
    expect(approvalRecord['approvalId'], 'approval-journal');
    expect(approvalRecord['toolName'], 'run_command');
    expect(approvalRecord['status'], ApprovalRequestState.approved.name);
    expect(approvalRecord['preview'], 'Execute: flutter test');
    final transactionRecords = records
        .where((record) => record['kind'] == 'patch_transaction')
        .toList(growable: false);
    expect(transactionRecords, hasLength(2));
    final transactionRecord = transactionRecords.first;
    expect(transactionRecord['title'], 'Applied changes');
    expect(transactionRecord['patchSetId'], 'patch-1');
    expect(transactionRecord['detail'], contains('checkpoint-journal'));
    expect(transactionRecord['status'], PatchApplyStatus.applied.name);
    expect(transactionRecord['paths'], ['lib/main.dart']);
    expect(transactionRecord['checkpointId'], 'checkpoint-journal');
    expect(transactionRecord['remainingPlanTargets'], 1);
    expect(transactionRecord['continueNextBatchAvailable'], isTrue);
    final filesLineTransaction = transactionRecords.last;
    expect(filesLineTransaction['patchSetId'], 'patch-2');
    expect(filesLineTransaction['checkpointId'], 'checkpoint-files-line');
    expect(filesLineTransaction['paths'], ['lib/router.dart', 'README.md']);
    final commandOutcomeRecord = records
        .where((record) => record['kind'] == 'turn_event')
        .firstWhere(
          (record) =>
              (record['event'] as Map<String, dynamic>)['id'] ==
              'command-run-turn-journal-cmd-journal',
        );
    final commandOutcome =
        commandOutcomeRecord['event'] as Map<String, dynamic>;
    expect(commandOutcome['title'], 'Ran command');
    expect(commandOutcome['detail'], contains('All tests passed!'));
    final providerDiagnosticRecord = records.firstWhere(
      (record) => record['kind'] == 'provider_diagnostic',
    );
    expect(providerDiagnosticRecord['threadId'], 'thread-journal');
    expect(providerDiagnosticRecord['turnId'], 'turn-journal');
    expect(providerDiagnosticRecord['requestId'], 'request-journal');
    final providerDiagnostic =
        providerDiagnosticRecord['diagnostic'] as Map<String, dynamic>;
    expect(
      providerDiagnostic['kind'],
      ProviderLifecycleEventKind.completed.name,
    );
    expect(providerDiagnostic['detail'], 'completed');
    expect(providerDiagnostic['model'], 'gpt-5-nano');
  });

  test(
    'StudioThreadStore journals command outcome events without tool results',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final now = DateTime(2026);
      final thread = StudioThread(
        id: 'thread-command-event',
        title: 'Command event thread',
        status: StudioThreadStatus.done,
        phase: StudioSendPhase.completed,
        turns: [
          StudioTurn(
            id: 'turn-command-event',
            threadId: 'thread-command-event',
            requestId: 'request-command-event',
            userMessageId: 'message-command-event',
            prompt: 'verify',
            model: 'gpt-5-nano',
            status: StudioTurnStatus.completed,
            contextSummary: StudioContextSummary(
              rootPath: project.path,
              projectLabel: 'project',
            ),
            events: [
              StudioTurnEvent.userMessage(
                id: 'message-command-event',
                turnId: 'turn-command-event',
                requestId: 'request-command-event',
                threadId: 'thread-command-event',
                content: 'verify',
                timestamp: now,
              ),
              StudioTurnEvent.completionSummary(
                id: 'command-run-turn-command-event-cmd-event',
                turnId: 'turn-command-event',
                requestId: 'request-command-event',
                threadId: 'thread-command-event',
                title: 'Ran command',
                detail:
                    'Command: flutter analyze\nExit code: 0\nNo issues found!',
                timestamp: now.add(const Duration(milliseconds: 1)),
              ),
            ],
            createdAt: now,
            updatedAt: now,
            completedAt: now.add(const Duration(milliseconds: 1)),
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      await store.save(project.path, [thread]);

      final records =
          (await File(store.journalPath(project.path)).readAsLines())
              .map((line) => jsonDecode(line) as Map<String, dynamic>)
              .toList(growable: false);
      final commandRecord = records.singleWhere(
        (record) => record['kind'] == 'command_run',
      );

      expect(commandRecord['toolCallId'], 'cmd-event');
      expect(commandRecord['command'], 'flutter analyze');
      expect(commandRecord['status'], ToolResultStatus.success.name);
      expect(commandRecord['exitCode'], 0);
      expect(commandRecord['diagnostic'], contains('Command: flutter analyze'));
      expect(commandRecord['diagnostic'], contains('No issues found!'));
      expect(commandRecord['stdout'], contains('No issues found!'));
    },
  );

  test(
    'StudioThreadStore recovers thread history from journal snapshots',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final now = DateTime(2026);
      final thread = StudioThread(
        id: 'thread-recovery',
        title: 'Recovered thread',
        status: StudioThreadStatus.done,
        phase: StudioSendPhase.completed,
        turns: [
          StudioTurn(
            id: 'turn-recovery',
            threadId: 'thread-recovery',
            requestId: 'request-recovery',
            userMessageId: 'message-recovery',
            prompt: 'build the thing',
            model: 'gpt-5-nano',
            contextSummary: StudioContextSummary(
              rootPath: project.path,
              projectLabel: 'project',
            ),
            status: StudioTurnStatus.completed,
            events: [
              StudioTurnEvent.userMessage(
                id: 'message-recovery',
                turnId: 'turn-recovery',
                requestId: 'request-recovery',
                threadId: 'thread-recovery',
                content: 'build the thing',
                timestamp: now,
              ),
              StudioTurnEvent.assistantMessage(
                turnId: 'turn-recovery',
                requestId: 'request-recovery',
                threadId: 'thread-recovery',
                content: 'Done.',
                timestamp: now.add(const Duration(seconds: 1)),
              ),
            ],
            createdAt: now,
            updatedAt: now.add(const Duration(seconds: 1)),
            completedAt: now.add(const Duration(seconds: 1)),
          ),
        ],
        createdAt: now,
        updatedAt: now.add(const Duration(seconds: 1)),
      );

      await store.save(project.path, [thread]);
      await File(store.historyPath(project.path)).delete();

      final recovered = await store.load(project.path);

      expect(recovered, hasLength(1));
      expect(recovered.single.id, 'thread-recovery');
      expect(recovered.single.status, StudioThreadStatus.done);
      expect(recovered.single.phase, StudioSendPhase.completed);
      expect(recovered.single.turns, hasLength(1));
      expect(recovered.single.turns.single.id, 'turn-recovery');
      expect(recovered.single.turns.single.status, StudioTurnStatus.completed);
      expect(
        recovered.single.turns.single.events
            .where(
              (event) => event.type == StudioTurnEventType.assistantMessage,
            )
            .single
            .content,
        'Done.',
      );
    },
  );

  test(
    'StudioThreadStore replays lifecycle journal records when snapshots are missing',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final now = DateTime(2026);
      final thread = StudioThread(
        id: 'thread-replay',
        title: 'Replay thread',
        status: StudioThreadStatus.continuationReady,
        phase: StudioSendPhase.completed,
        turns: [
          StudioTurn(
            id: 'turn-replay',
            threadId: 'thread-replay',
            requestId: 'request-replay',
            userMessageId: 'message-replay',
            prompt: 'Implement this approved plan.',
            model: 'gpt-5-nano',
            intent: TurnIntent.code,
            contextSummary: StudioContextSummary(
              rootPath: project.path,
              projectLabel: 'project',
            ),
            status: StudioTurnStatus.completed,
            acceptedPlanState: AcceptedPlanState.patchProposed,
            acceptedPlanContext: const AcceptedPlanContext(
              patchSetId: 'plan-replay',
              title: 'Replay accepted plan',
              summary: 'Create app and docs.',
              markdown: 'Create lib/app.dart, then README.md.',
              plannedTargets: [
                PlannedFileTarget(
                  path: 'lib/app.dart',
                  intent: 'Create app shell',
                  operation: ProposedFileEditType.create,
                ),
                PlannedFileTarget(
                  path: 'README.md',
                  intent: 'Document usage',
                  operation: ProposedFileEditType.create,
                ),
              ],
            ),
            planTargetProgress: [
              PlanTargetProgress(
                path: 'lib/app.dart',
                intent: 'Create app shell',
                operation: ProposedFileEditType.create,
                state: PlanTargetProgressState.applied,
                patchSetId: 'patch-replay',
                detail: 'Applied changes',
                updatedAt: now.add(const Duration(milliseconds: 1)),
              ),
              PlanTargetProgress(
                path: 'README.md',
                intent: 'Document usage',
                operation: ProposedFileEditType.create,
                updatedAt: now.add(const Duration(milliseconds: 2)),
              ),
            ],
            contextRetrieval: const ContextRetrievalResult(
              rankedCandidates: [
                ContextCandidate(
                  id: 'candidate-replay',
                  title: 'app.dart',
                  path: 'lib/app.dart',
                  sourceKind: ContextPackSourceKind.editor,
                  score: 99,
                  estimatedTokens: 100,
                  included: true,
                  reason: 'Accepted plan target',
                ),
              ],
              budget: ContextBudgetReport(
                maxTokens: 1000,
                reservedForResponse: 200,
                availableForContext: 800,
                usedTokens: 100,
              ),
            ),
            steps: [
              TurnStepRecord(
                step: TurnStep.patchProposal,
                status: TurnStepStatus.completed,
                title: 'Applied changes',
                detail: 'Applied first batch.',
                startedAt: now,
                completedAt: now.add(const Duration(milliseconds: 1)),
              ),
              TurnStepRecord(
                step: TurnStep.continuation,
                status: TurnStepStatus.queued,
                title: 'Continue next batch',
                detail: 'README.md still needs work.',
                startedAt: now.add(const Duration(milliseconds: 2)),
              ),
              TurnStepRecord(
                step: TurnStep.commandRun,
                status: TurnStepStatus.completed,
                title: 'Ran command',
                detail:
                    'Command: flutter test\nExit code: 0\nAll tests passed!',
                startedAt: now.add(const Duration(milliseconds: 3)),
                completedAt: now.add(const Duration(milliseconds: 4)),
              ),
            ],
            events: [
              StudioTurnEvent.userMessage(
                id: 'message-replay',
                turnId: 'turn-replay',
                requestId: 'request-replay',
                threadId: 'thread-replay',
                content: 'Implement this approved plan.',
                timestamp: now,
                transcriptVisible: false,
              ),
              StudioTurnEvent(
                id: 'approval-request-replay',
                turnId: 'turn-replay',
                requestId: 'request-replay',
                threadId: 'thread-replay',
                type: StudioTurnEventType.approvalRequest,
                title: 'Approval needed',
                detail: 'Review the tool request.',
                timestamp: now.add(const Duration(milliseconds: 1)),
                toolCallId: 'tool-replay',
                toolName: 'run_command',
                approvalId: 'approval-replay',
                approvalState: ApprovalRequestState.approved,
                approvalPreview: 'Execute: flutter test',
                approvalWarnings: const ['Shell command requires review.'],
              ),
              StudioTurnEvent.completionSummary(
                id: 'patch-transaction-turn-replay-patch-replay-applied',
                turnId: 'turn-replay',
                requestId: 'request-replay',
                threadId: 'thread-replay',
                title: 'Applied changes',
                detail:
                    'Applied 1 files.\nHere’s what changed: lib/app.dart\nCheckpoint: replay-checkpoint\nNext batch: 1 accepted-plan target still needs work (README.md). Use Continue next batch to keep implementing the accepted plan.',
                patchSetId: 'patch-replay',
                timestamp: now.add(const Duration(milliseconds: 1)),
              ),
              StudioTurnEvent.completionSummary(
                id: 'command-run-turn-replay-cmd-replay',
                turnId: 'turn-replay',
                requestId: 'request-replay',
                threadId: 'thread-replay',
                title: 'Ran command',
                detail:
                    'Command: flutter test\nExit code: 0\nAll tests passed!',
                timestamp: now.add(const Duration(milliseconds: 3)),
              ),
            ],
            providerDiagnostics: [
              ProviderLifecycleEvent(
                requestId: 'request-replay',
                turnId: 'turn-replay',
                kind: ProviderLifecycleEventKind.completed,
                timestamp: now.add(const Duration(milliseconds: 2)),
                model: 'gpt-5-nano',
              ),
            ],
            createdAt: now,
            updatedAt: now.add(const Duration(milliseconds: 2)),
            completedAt: now.add(const Duration(milliseconds: 2)),
          ),
        ],
        createdAt: now,
        updatedAt: now.add(const Duration(milliseconds: 2)),
      );

      await store.save(project.path, [thread]);
      await File(store.historyPath(project.path)).delete();
      final journal = File(store.journalPath(project.path));
      final withoutSnapshots = (await journal.readAsLines())
          .where((line) {
            final record = jsonDecode(line) as Map<String, dynamic>;
            return !{
              'thread_snapshot',
              'turn',
              'turn_event',
              'turn_step',
            }.contains(record['kind']);
          })
          .join('\n');
      await journal.writeAsString('$withoutSnapshots\n');

      final recovered = await store.load(project.path);

      expect(recovered, hasLength(1));
      expect(recovered.single.id, 'thread-replay');
      expect(recovered.single.status, StudioThreadStatus.continuationReady);
      expect(recovered.single.phase, StudioSendPhase.completed);
      expect(recovered.single.turns, hasLength(1));
      final turn = recovered.single.turns.single;
      expect(turn.status, StudioTurnStatus.completed);
      expect(turn.model, 'gpt-5-nano');
      expect(turn.acceptedPlanContext?.patchSetId, 'plan-replay');
      expect(turn.acceptedPlanContext?.markdown, contains('README.md'));
      expect(turn.planTargetProgress, hasLength(2));
      expect(
        turn.planTargetProgress
            .singleWhere((target) => target.path == 'lib/app.dart')
            .state,
        PlanTargetProgressState.applied,
      );
      expect(
        turn.planTargetProgress
            .singleWhere((target) => target.path == 'README.md')
            .state,
        PlanTargetProgressState.pending,
      );
      expect(
        turn.contextRetrieval?.includedCandidates.single.path,
        'lib/app.dart',
      );
      expect(
        turn.steps
            .singleWhere((step) => step.step == TurnStep.continuation)
            .status,
        TurnStepStatus.queued,
      );
      expect(
        turn.events
            .singleWhere(
              (event) =>
                  event.type == StudioTurnEventType.approvalRequest &&
                  event.approvalId == 'approval-replay',
            )
            .approvalState,
        ApprovalRequestState.approved,
      );
      expect(
        turn.events
            .singleWhere((event) => event.title == 'Applied changes')
            .detail,
        contains('Continue next batch'),
      );
      final commandRunStep = turn.steps.singleWhere(
        (step) => step.step == TurnStep.commandRun,
      );
      expect(commandRunStep.status, TurnStepStatus.completed);
      expect(commandRunStep.detail, contains('flutter test'));
      expect(
        turn.events
            .singleWhere(
              (event) => event.id == 'command-run-turn-replay-cmd-replay',
            )
            .detail,
        contains('All tests passed'),
      );
      expect(
        turn.providerDiagnostics.single.kind,
        ProviderLifecycleEventKind.completed,
      );
    },
  );

  test(
    'StudioThreadStore journal recovery does not title internal plan implementation turns',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final journal = File(store.journalPath(project.path));
      await journal.parent.create(recursive: true);
      final now = DateTime(2026);
      final records = [
        {
          'kind': 'turn',
          'threadId': 'thread-internal-title',
          'threadTitle':
              'Implement this approved plan. Use the accepted plan context.',
          'turnId': 'turn-internal-title',
          'requestId': 'request-internal-title',
          'intent': TurnIntent.code.name,
          'status': StudioTurnStatus.completed.name,
          'model': 'gpt-5-nano',
          'acceptedPlanState': AcceptedPlanState.patchProposed.name,
          'createdAt': now.toIso8601String(),
          'updatedAt': now
              .add(const Duration(milliseconds: 1))
              .toIso8601String(),
          'completedAt': now
              .add(const Duration(milliseconds: 1))
              .toIso8601String(),
        },
        {
          'kind': 'turn_event',
          'threadId': 'thread-internal-title',
          'threadTitle':
              'Implement this approved plan. Use the accepted plan context.',
          'turnId': 'turn-internal-title',
          'requestId': 'request-internal-title',
          'event': StudioTurnEvent.userMessage(
            id: 'message-internal-title',
            turnId: 'turn-internal-title',
            requestId: 'request-internal-title',
            threadId: 'thread-internal-title',
            content:
                'Implement this approved plan.\n\nUse the accepted plan context attached to this request as the source of truth.',
            timestamp: now,
            transcriptVisible: false,
          ).toJson(),
          'capturedAt': now.toIso8601String(),
        },
        {
          'kind': 'accepted_plan',
          'threadId': 'thread-internal-title',
          'threadTitle':
              'Implement this approved plan. Use the accepted plan context.',
          'turnId': 'turn-internal-title',
          'requestId': 'request-internal-title',
          'patchSetId': 'plan-internal-title',
          'title': 'Network diagram generator plan',
          'summary': 'Create the network diagram generator in batches.',
          'markdown': 'Create the CLI and renderer modules.',
          'acceptedPlanState': AcceptedPlanState.patchProposed.name,
          'plannedTargets': const [
            PlannedFileTarget(
              path: 'tools/network-diagram/cli.py',
              intent: 'Create CLI entrypoint',
              operation: ProposedFileEditType.create,
            ),
          ].map((target) => target.toJson()).toList(),
          'updatedAt': now
              .add(const Duration(milliseconds: 1))
              .toIso8601String(),
        },
      ];
      await journal.writeAsString('${records.map(jsonEncode).join('\n')}\n');

      final recovered = await store.load(project.path);

      expect(recovered, hasLength(1));
      expect(recovered.single.title, 'Network diagram generator plan');
      final turn = recovered.single.turns.single;
      expect(turn.prompt, isEmpty);
      expect(
        turn.events.where(
          (event) =>
              event.type == StudioTurnEventType.userMessage &&
              event.transcriptVisible,
        ),
        isEmpty,
      );
    },
  );

  test(
    'StudioThreadStore replays accepted-plan prose conflict paths from journal',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final journal = File(store.journalPath(project.path));
      await journal.parent.create(recursive: true);
      final now = DateTime(2026);
      final records = [
        {
          'kind': 'turn',
          'threadId': 'thread-journal-conflict',
          'threadTitle': 'Journal conflict replay',
          'turnId': 'turn-journal-conflict',
          'requestId': 'request-journal-conflict',
          'intent': TurnIntent.code.name,
          'status': StudioTurnStatus.completed.name,
          'model': 'gpt-5-nano',
          'acceptedPlanState': AcceptedPlanState.patchProposed.name,
          'createdAt': now.toIso8601String(),
          'updatedAt': now
              .add(const Duration(milliseconds: 1))
              .toIso8601String(),
          'completedAt': now
              .add(const Duration(milliseconds: 1))
              .toIso8601String(),
        },
        {
          'kind': 'accepted_plan',
          'threadId': 'thread-journal-conflict',
          'threadTitle': 'Journal conflict replay',
          'turnId': 'turn-journal-conflict',
          'requestId': 'request-journal-conflict',
          'patchSetId': 'plan-journal-conflict',
          'title': 'Journal conflict plan',
          'summary': 'Create app and docs.',
          'markdown': 'Create app.py and docs.md.',
          'acceptedPlanState': AcceptedPlanState.patchProposed.name,
          'plannedTargets': const [
            PlannedFileTarget(
              path: 'app.py',
              intent: 'Create the app entrypoint',
              operation: ProposedFileEditType.create,
            ),
            PlannedFileTarget(
              path: 'docs.md',
              intent: 'Document usage',
              operation: ProposedFileEditType.create,
            ),
          ].map((target) => target.toJson()).toList(),
          'updatedAt': now.toIso8601String(),
        },
        {
          'kind': 'patch_transaction',
          'threadId': 'thread-journal-conflict',
          'threadTitle': 'Journal conflict replay',
          'turnId': 'turn-journal-conflict',
          'requestId': 'request-journal-conflict',
          'eventId': 'patch-transaction-turn-journal-conflict-conflict',
          'patchSetId': 'patch-journal-conflict',
          'title': 'Patch conflict',
          'detail':
              'Patch leaves docs.md empty. Ask Circuit to revise the patch with complete file contents before applying.',
          'status': 'conflict',
          'createdAt': now
              .add(const Duration(milliseconds: 1))
              .toIso8601String(),
        },
      ];
      await journal.writeAsString('${records.map(jsonEncode).join('\n')}\n');

      final recovered = await store.load(project.path);

      expect(recovered, hasLength(1));
      expect(recovered.single.status, StudioThreadStatus.reviewingPatch);
      expect(recovered.single.phase, StudioSendPhase.completed);
      final turn = recovered.single.turns.single;
      expect(turn.acceptedPlanState, AcceptedPlanState.patchProposed);
      expect(turn.planTargetProgress, hasLength(2));
      expect(
        turn.planTargetProgress
            .singleWhere((target) => target.path == 'docs.md')
            .state,
        PlanTargetProgressState.conflict,
      );
      expect(
        turn.planTargetProgress
            .singleWhere((target) => target.path == 'app.py')
            .state,
        PlanTargetProgressState.pending,
      );
      expect(
        StudioTaskLifecycleState.fromThread(recovered.single).label,
        'Review',
      );
    },
  );

  test(
    'StudioThreadStore recovers interrupted active patch proposal as reviewable',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final now = DateTime(2026);
      final turn = StudioTurn(
        id: 'turn-active-patch-recover',
        threadId: 'thread-active-patch-recover',
        requestId: 'request-active-patch-recover',
        userMessageId: 'message-active-patch-recover',
        prompt: 'Implement the accepted plan',
        model: 'gpt-5-nano',
        contextSummary: StudioContextSummary(
          rootPath: project.path,
          projectLabel: 'project',
        ),
        status: StudioTurnStatus.streaming,
        acceptedPlanState: AcceptedPlanState.patchProposed,
        steps: [
          TurnStepRecord(
            step: TurnStep.patchProposal,
            status: TurnStepStatus.running,
            title: 'Prepared changes',
            detail: 'Prepared first reviewable batch.',
            startedAt: now,
          ),
        ],
        events: [
          StudioTurnEvent.completionSummary(
            id: 'patch-transaction-turn-active-patch-recover-patch-proposed',
            turnId: 'turn-active-patch-recover',
            requestId: 'request-active-patch-recover',
            threadId: 'thread-active-patch-recover',
            title: 'Prepared changes',
            detail: 'Prepared 1 files.',
            patchSetId: 'patch-proposed',
            timestamp: now.add(const Duration(milliseconds: 1)),
          ),
        ],
        createdAt: now,
        updatedAt: now.add(const Duration(milliseconds: 1)),
      );
      final thread = StudioThread(
        id: 'thread-active-patch-recover',
        title: 'Active patch recover',
        status: StudioThreadStatus.streaming,
        phase: StudioSendPhase.streaming,
        requestId: 'request-active-patch-recover',
        streamingContent: 'stale draft',
        turns: [turn],
        createdAt: now,
        updatedAt: now,
      );

      await store.save(project.path, [thread]);

      final loaded = await store.load(project.path);

      expect(loaded, hasLength(1));
      expect(loaded.single.status, StudioThreadStatus.reviewingPatch);
      expect(loaded.single.phase, StudioSendPhase.completed);
      expect(loaded.single.requestId, isNull);
      expect(loaded.single.streamingContent, isEmpty);
      expect(loaded.single.lastError, isNull);
      final loadedTurn = loaded.single.turns.single;
      expect(loadedTurn.status, StudioTurnStatus.completed);
      expect(loadedTurn.lastError, isNull);
      expect(loadedTurn.assistantDraft, isEmpty);
      expect(loadedTurn.acceptedPlanState, AcceptedPlanState.patchProposed);
      expect(
        loadedTurn.steps
            .singleWhere((step) => step.step == TurnStep.patchProposal)
            .status,
        TurnStepStatus.completed,
      );
    },
  );

  test(
    'StudioThreadStore recovers interrupted partial accepted-plan apply as continuation',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final now = DateTime(2026);
      final turn = StudioTurn(
        id: 'turn-active-continuation-recover',
        threadId: 'thread-active-continuation-recover',
        requestId: 'request-active-continuation-recover',
        userMessageId: 'message-active-continuation-recover',
        prompt: 'Implement the accepted plan',
        model: 'gpt-5-nano',
        contextSummary: StudioContextSummary(
          rootPath: project.path,
          projectLabel: 'project',
        ),
        status: StudioTurnStatus.streaming,
        acceptedPlanState: AcceptedPlanState.patchProposed,
        acceptedPlanContext: const AcceptedPlanContext(
          patchSetId: 'plan-active-continuation',
          title: 'Recover continuation plan',
          summary: 'Create app and docs.',
          markdown: 'Create lib/app.dart, then README.md.',
          plannedFiles: [
            'lib/app.dart — Create app shell',
            'README.md — Document usage',
          ],
          plannedTargets: [
            PlannedFileTarget(
              path: 'lib/app.dart',
              intent: 'Create app shell',
              operation: ProposedFileEditType.create,
            ),
            PlannedFileTarget(
              path: 'README.md',
              intent: 'Document usage',
              operation: ProposedFileEditType.create,
            ),
          ],
        ),
        planTargetProgress: [
          PlanTargetProgress(
            path: 'lib/app.dart',
            intent: 'Create app shell',
            operation: ProposedFileEditType.create,
            state: PlanTargetProgressState.applied,
            patchSetId: 'patch-app',
            updatedAt: now.add(const Duration(milliseconds: 1)),
          ),
          PlanTargetProgress(
            path: 'README.md',
            intent: 'Document usage',
            operation: ProposedFileEditType.create,
            state: PlanTargetProgressState.pending,
            updatedAt: now.add(const Duration(milliseconds: 1)),
          ),
        ],
        steps: [
          TurnStepRecord(
            step: TurnStep.patchProposal,
            status: TurnStepStatus.completed,
            title: 'Applied changes',
            detail:
                'Applied 1 files.\nNext batch: 1 accepted-plan target still needs work (README.md). Use Continue next batch to keep implementing the accepted plan.',
            startedAt: now,
            completedAt: now,
          ),
          TurnStepRecord(
            step: TurnStep.continuation,
            status: TurnStepStatus.running,
            title: 'Continue next batch',
            detail: 'README.md still needs work.',
            startedAt: now.add(const Duration(milliseconds: 2)),
          ),
        ],
        events: [
          StudioTurnEvent.completionSummary(
            id: 'patch-transaction-turn-active-continuation-recover-patch-app-applied',
            turnId: 'turn-active-continuation-recover',
            requestId: 'request-active-continuation-recover',
            threadId: 'thread-active-continuation-recover',
            title: 'Applied changes',
            detail:
                'Applied 1 files.\nHere’s what changed: lib/app.dart\nCheckpoint: checkpoint-active\nNext batch: 1 accepted-plan target still needs work (README.md). Use Continue next batch to keep implementing the accepted plan.',
            patchSetId: 'patch-app',
            timestamp: now.add(const Duration(milliseconds: 1)),
          ),
        ],
        createdAt: now,
        updatedAt: now.add(const Duration(milliseconds: 2)),
      );
      final thread = StudioThread(
        id: 'thread-active-continuation-recover',
        title: 'Active continuation recover',
        status: StudioThreadStatus.streaming,
        phase: StudioSendPhase.streaming,
        requestId: 'request-active-continuation-recover',
        streamingContent: 'stale draft',
        turns: [turn],
        createdAt: now,
        updatedAt: now,
      );

      await store.save(project.path, [thread]);

      final loaded = await store.load(project.path);

      expect(loaded, hasLength(1));
      expect(loaded.single.status, StudioThreadStatus.continuationReady);
      expect(loaded.single.phase, StudioSendPhase.completed);
      expect(loaded.single.requestId, isNull);
      expect(loaded.single.streamingContent, isEmpty);
      expect(loaded.single.lastError, isNull);
      final loadedTurn = loaded.single.turns.single;
      expect(loadedTurn.status, StudioTurnStatus.completed);
      expect(loadedTurn.acceptedPlanState, AcceptedPlanState.patchProposed);
      expect(
        loadedTurn.planTargetProgress
            .firstWhere((target) => target.path == 'lib/app.dart')
            .state,
        PlanTargetProgressState.applied,
      );
      expect(
        loadedTurn.planTargetProgress
            .firstWhere((target) => target.path == 'README.md')
            .state,
        PlanTargetProgressState.pending,
      );
      expect(
        loadedTurn.steps
            .singleWhere((step) => step.step == TurnStep.continuation)
            .status,
        TurnStepStatus.completed,
      );
      expect(
        StudioTaskLifecycleState.fromThread(loaded.single).label,
        'Continue',
      );
    },
  );

  test(
    'StudioThreadStore normalizes interrupted turns recovered from journal',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final now = DateTime(2026);
      final interrupted = StudioThread(
        id: 'thread-journal-interrupted',
        title: 'Journal interrupted request',
        status: StudioThreadStatus.streaming,
        phase: StudioSendPhase.streaming,
        requestId: 'request-journal-interrupted',
        turns: [
          StudioTurn(
            id: 'turn-journal-interrupted',
            threadId: 'thread-journal-interrupted',
            requestId: 'request-journal-interrupted',
            userMessageId: 'message-journal-interrupted',
            prompt: 'keep streaming',
            model: 'gpt-5-nano',
            contextSummary: StudioContextSummary(
              rootPath: project.path,
              projectLabel: 'project',
            ),
            status: StudioTurnStatus.streaming,
            steps: [
              TurnStepRecord(
                step: TurnStep.providerRequest,
                status: TurnStepStatus.completed,
                title: 'Provider completed',
                startedAt: now,
                completedAt: now,
              ),
              TurnStepRecord(
                step: TurnStep.streaming,
                status: TurnStepStatus.running,
                title: 'Streaming response',
                detail: 'Receiving text.',
                startedAt: now.add(const Duration(milliseconds: 1)),
              ),
            ],
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      await store.save(project.path, [interrupted]);
      await File(store.historyPath(project.path)).delete();

      final recovered = await store.load(project.path);

      expect(recovered, hasLength(1));
      expect(recovered.single.status, StudioThreadStatus.failed);
      expect(recovered.single.phase, StudioSendPhase.failed);
      expect(recovered.single.requestId, isNull);
      final recoveredTurn = recovered.single.turns.single;
      expect(recoveredTurn.status, StudioTurnStatus.failed);
      expect(
        recoveredTurn.lastError,
        contains('Interrupted while CircuitCode was closed'),
      );
      expect(
        recoveredTurn.steps
            .firstWhere((step) => step.step == TurnStep.streaming)
            .status,
        TurnStepStatus.failed,
      );
      expect(
        recoveredTurn.steps
            .firstWhere((step) => step.step == TurnStep.finalSummary)
            .title,
        'Turn interrupted',
      );
    },
  );

  test(
    'StudioThreadStore falls back to journal snapshots when history is corrupt',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final now = DateTime(2026);
      final thread = StudioThread(
        id: 'thread-corrupt-recovery',
        title: 'Corrupt recovery',
        status: StudioThreadStatus.done,
        phase: StudioSendPhase.completed,
        turns: [
          StudioTurn(
            id: 'turn-corrupt-recovery',
            threadId: 'thread-corrupt-recovery',
            requestId: 'request-corrupt-recovery',
            userMessageId: 'message-corrupt-recovery',
            prompt: 'remember this',
            model: 'gpt-5-nano',
            contextSummary: StudioContextSummary(
              rootPath: project.path,
              projectLabel: 'project',
            ),
            status: StudioTurnStatus.completed,
            createdAt: now,
            updatedAt: now,
            completedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      await store.save(project.path, [thread]);
      await File(store.historyPath(project.path)).writeAsString('{not json');

      final recovered = await store.load(project.path);

      expect(recovered, hasLength(1));
      expect(recovered.single.id, 'thread-corrupt-recovery');
      expect(recovered.single.turns.single.id, 'turn-corrupt-recovery');
    },
  );

  test(
    'StudioThreadStore skips malformed journal bytes during recovery',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final now = DateTime(2026);
      final thread = StudioThread(
        id: 'thread-malformed-journal-recovery',
        title: 'Malformed journal recovery',
        status: StudioThreadStatus.done,
        phase: StudioSendPhase.completed,
        turns: [
          StudioTurn(
            id: 'turn-malformed-journal-recovery',
            threadId: 'thread-malformed-journal-recovery',
            requestId: 'request-malformed-journal-recovery',
            userMessageId: 'message-malformed-journal-recovery',
            prompt: 'recover this',
            model: 'gpt-5-nano',
            contextSummary: StudioContextSummary(
              rootPath: project.path,
              projectLabel: 'project',
            ),
            status: StudioTurnStatus.completed,
            createdAt: now,
            updatedAt: now,
            completedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      await store.save(project.path, [thread]);
      final journal = File(store.journalPath(project.path));
      final journalBytes = await journal.readAsBytes();
      await journal.writeAsBytes([0xff, 0xfe, 0xfd, 0x0a, ...journalBytes]);
      await File(store.historyPath(project.path)).writeAsString('{not json');

      final recovered = await store.load(project.path);

      expect(recovered, hasLength(1));
      expect(recovered.single.id, 'thread-malformed-journal-recovery');
      expect(
        recovered.single.turns.single.id,
        'turn-malformed-journal-recovery',
      );
    },
  );

  test(
    'StudioThreadStore appends safely when existing journal has malformed bytes',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final journal = File(store.journalPath(project.path));
      await journal.parent.create(recursive: true);
      await journal.writeAsBytes([0xff, 0xfe, 0xfd, 0x0a]);
      final now = DateTime(2026);
      final thread = StudioThread(
        id: 'thread-malformed-journal-append',
        title: 'Malformed journal append',
        status: StudioThreadStatus.done,
        phase: StudioSendPhase.completed,
        turns: [
          StudioTurn(
            id: 'turn-malformed-journal-append',
            threadId: 'thread-malformed-journal-append',
            requestId: 'request-malformed-journal-append',
            userMessageId: 'message-malformed-journal-append',
            prompt: 'append this',
            model: 'gpt-5-nano',
            contextSummary: StudioContextSummary(
              rootPath: project.path,
              projectLabel: 'project',
            ),
            status: StudioTurnStatus.completed,
            createdAt: now,
            updatedAt: now,
            completedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      await store.save(project.path, [thread]);

      final journalText = utf8.decode(
        await journal.readAsBytes(),
        allowMalformed: true,
      );
      expect(journalText, contains('thread-malformed-journal-append'));
    },
  );

  test(
    'StudioThreadStore journal preserves lifecycle transitions across saves',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final startedAt = DateTime(2026);
      final completedAt = startedAt.add(const Duration(seconds: 2));

      StudioThread threadWithStep(TurnStepStatus status) {
        final terminal = status == TurnStepStatus.completed;
        return StudioThread(
          id: 'thread-transition',
          title: 'Transition thread',
          status: terminal
              ? StudioThreadStatus.done
              : StudioThreadStatus.streaming,
          phase: terminal
              ? StudioSendPhase.completed
              : StudioSendPhase.streaming,
          turns: [
            StudioTurn(
              id: 'turn-transition',
              threadId: 'thread-transition',
              requestId: 'request-transition',
              userMessageId: 'message-transition',
              prompt: 'stream a response',
              model: 'gpt-5-nano',
              contextSummary: StudioContextSummary(
                rootPath: project.path,
                projectLabel: 'project',
              ),
              status: terminal
                  ? StudioTurnStatus.completed
                  : StudioTurnStatus.streaming,
              steps: [
                TurnStepRecord(
                  step: TurnStep.streaming,
                  status: status,
                  title: terminal ? 'Stream completed' : 'Streaming',
                  detail: terminal
                      ? 'Assistant response completed.'
                      : 'Assistant response is streaming.',
                  startedAt: startedAt,
                  completedAt: terminal ? completedAt : null,
                ),
              ],
              createdAt: startedAt,
              updatedAt: terminal ? completedAt : startedAt,
              completedAt: terminal ? completedAt : null,
            ),
          ],
          createdAt: startedAt,
          updatedAt: terminal ? completedAt : startedAt,
        );
      }

      await store.save(project.path, [threadWithStep(TurnStepStatus.running)]);
      await store.save(project.path, [
        threadWithStep(TurnStepStatus.completed),
      ]);
      await store.save(project.path, [
        threadWithStep(TurnStepStatus.completed),
      ]);

      final records =
          (await File(store.journalPath(project.path)).readAsLines())
              .map((line) => jsonDecode(line) as Map<String, dynamic>)
              .toList(growable: false);
      final stepStatuses = records
          .where((record) => record['kind'] == 'turn_step')
          .map(
            (record) =>
                (record['step'] as Map<String, dynamic>)['status'] as String,
          )
          .toList(growable: false);

      expect(stepStatuses, contains(TurnStepStatus.running.name));
      expect(stepStatuses, contains(TurnStepStatus.completed.name));
      expect(
        stepStatuses
            .where((status) => status == TurnStepStatus.completed.name)
            .length,
        1,
      );
    },
  );

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
