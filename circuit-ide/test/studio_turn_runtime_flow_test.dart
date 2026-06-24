import 'dart:async';
import 'dart:io';

import 'package:circuit_ide/agent/providers/provider_interface.dart';
import 'package:circuit_ide/agent/security/agent_tool_permission_policy.dart';
import 'package:circuit_ide/agent/studio_agent_environment.dart';
import 'package:circuit_ide/agent/tools/tool_registry.dart';
import 'package:circuit_ide/enums/event_type.dart';
import 'package:circuit_ide/models/accepted_plan_context.dart';
import 'package:circuit_ide/models/agent_preflight.dart';
import 'package:circuit_ide/models/agent_request.dart';
import 'package:circuit_ide/models/agent_run.dart';
import 'package:circuit_ide/models/chat_message.dart';
import 'package:circuit_ide/models/confirmation_request.dart';
import 'package:circuit_ide/models/provider_lifecycle_event.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/models/studio_shell.dart';
import 'package:circuit_ide/models/studio_request_lifecycle.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/models/tool_call_info.dart';
import 'package:circuit_ide/models/tool_result_envelope.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:circuit_ide/services/agent_service.dart';
import 'package:circuit_ide/state/agent_request_provider.dart';
import 'package:circuit_ide/state/agent_run_provider.dart';
import 'package:circuit_ide/state/agent_turn_runtime_provider.dart';
import 'package:circuit_ide/state/connection_provider.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/patch_proposal_provider.dart';
import 'package:circuit_ide/state/settings_provider.dart';
import 'package:circuit_ide/state/studio_request_lifecycle_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/state/studio_turn_provider.dart';
import 'package:circuit_ide/ui/studio/studio_message_sender.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'AgentTurnRuntime preflight uses visible Studio connection state',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final result = await container
          .read(agentTurnRuntimeProvider.notifier)
          .preflightMessage('hello', const [])
          .timeout(const Duration(seconds: 1));

      expect(
        result.issues.map((issue) => issue.message),
        contains('AI is not connected. Reconnect before sending.'),
      );
      expect(
        result.issues.map((issue) => issue.recoveryAction),
        contains(AgentPreflightRecoveryAction.reconnect),
      );
    },
  );

  test(
    'AgentTurnRuntime early provider failure closes registered turn without lifecycle',
    () async {
      final service = AgentService();
      addTearDown(service.dispose);
      final container = ProviderContainer(
        overrides: [agentServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      await _waitForThreadStore(container);
      const requestId = 'runtime-no-provider-no-lifecycle';
      final thread = container
          .read(studioThreadProvider.notifier)
          .ensureThread(title: 'No provider runtime', model: 'gpt-5-nano');
      container
          .read(studioTurnProvider.notifier)
          .registerTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            userMessageId: 'user-$requestId',
            prompt: 'hello',
            model: 'gpt-5-nano',
            contextSummary: const StudioContextSummary(
              projectLabel: 'runtime',
              rootPath: '/tmp/runtime',
            ),
            intent: TurnIntent.chat,
          );

      await container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'hello',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.chat,
            intent: TurnIntent.chat,
            model: 'gpt-5-nano',
            retryPrompt: 'hello',
            finishTask: false,
          );

      final updatedThread = container
          .read(studioThreadProvider)
          .threads
          .firstWhere((candidate) => candidate.id == thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        updatedThread.turns.single.lastError,
        contains('Circuit AI is not connected'),
      );
      expect(container.read(agentTurnRuntimeProvider).activeSessions, isEmpty);
    },
  );

  test(
    'AgentTurnRuntime turns accepted plan into concrete patch and app apply',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_runtime_');
      addTearDown(() => _delete(root));
      final service = AgentService();
      addTearDown(service.dispose);
      final provider = _ScriptedProvider([
        const [
          ChatChunk(
            toolCallIndex: 0,
            toolCallId: 'patch',
            toolCallName: 'propose_patch',
            toolCallArguments:
                '{"title":"Create hello file","summary":"Add a text greeting.","files":[{"path":"hello.txt","intent":"Add greeting","operation":"create","content":"hello runtime\\n"}]}',
          ),
          ChatChunk(finishReason: 'tool_calls', isDone: true),
        ],
      ]);
      final environment = StudioAgentEnvironment(
        provider: provider,
        model: 'gpt-5-nano',
        workspaceRoot: root.path,
        permissionPolicy: AgentToolPermissionPolicy(workingDir: root.path),
        events: service.events,
        onProviderEvent: (event) {
          service.events.emit(EventType.providerLifecycle, {
            'event': event,
            'requestId': event.requestId,
          });
        },
      );
      final container = ProviderContainer(
        overrides: [
          agentServiceProvider.overrideWithValue(service),
          studioAgentEnvironmentOverrideProvider.overrideWithValue(environment),
        ],
      );
      addTearDown(container.dispose);
      await _waitForThreadStore(container);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      final thread = container
          .read(studioThreadProvider.notifier)
          .ensureThread(title: 'Implement accepted plan', model: 'gpt-5-nano');
      const requestId = 'runtime-plan';
      const acceptedPlan = AcceptedPlanContext(
        patchSetId: 'plan',
        title: 'Accepted plan',
        summary: 'Add a hello text file.',
        markdown: '- Create hello.txt',
        plannedFiles: ['hello.txt — Add greeting'],
        plannedTargets: [
          PlannedFileTarget(
            path: 'hello.txt',
            intent: 'Add greeting',
            operation: ProposedFileEditType.create,
          ),
        ],
      );
      container
          .read(studioTurnProvider.notifier)
          .registerTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            userMessageId: 'user-message',
            prompt: 'Implement this plan',
            model: 'gpt-5-nano',
            contextSummary: const StudioContextSummary(
              projectLabel: 'runtime',
              rootPath: '/tmp/runtime',
            ),
            intent: TurnIntent.code,
            acceptedPlanState: AcceptedPlanState.accepted,
            acceptedPlanContext: acceptedPlan,
          );
      container
          .read(studioRequestLifecycleProvider.notifier)
          .registerRequest(
            requestId: requestId,
            threadId: thread.id,
            model: 'gpt-5-nano',
            contextSummary: const StudioContextSummary(
              projectLabel: 'runtime',
              rootPath: '/tmp/runtime',
            ),
          );

      await container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: acceptedPlan,
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(agentTurnRuntimeProvider).activeSessions, isEmpty);
      final updatedThread = container
          .read(studioThreadProvider)
          .threads
          .firstWhere((candidate) => candidate.id == thread.id);
      expect(updatedThread.status, StudioThreadStatus.done);
      expect(updatedThread.turns.single.status, StudioTurnStatus.completed);
      expect(
        updatedThread.turns.single.acceptedPlanState,
        AcceptedPlanState.patchProposed,
      );
      expect(
        updatedThread.turns.single.acceptedPlanContext?.patchSetId,
        'plan',
      );
      expect(updatedThread.turns.single.acceptedPlanContext?.plannedFiles, [
        'hello.txt — Add greeting',
      ]);
      expect(
        updatedThread
            .turns
            .single
            .acceptedPlanContext
            ?.plannedTargets
            .single
            .operation,
        ProposedFileEditType.create,
      );
      expect(provider.exposedTools, hasLength(1));
      expect(
        updatedThread.turns.single.events.where(
          (event) => event.type == StudioTurnEventType.assistantMessage,
        ),
        isEmpty,
      );
      final patch = container.read(patchProposalProvider).active;
      expect(patch, isNotNull);
      expect(patch!.isPlanOnly, isFalse);
      expect(patch.edits.single.path, 'hello.txt');
      expect(patch.edits.single.after, 'hello runtime\n');
      expect(
        provider.exposedTools.expand((round) => round),
        isNot(contains('apply_patch_set')),
      );

      final apply = await container
          .read(patchProposalProvider.notifier)
          .applyActive();
      expect(apply.status, PatchApplyStatus.applied);
      expect(apply.checkpointId, isNotNull);
      expect(apply.changedFiles, ['hello.txt']);
      expect(
        await File(p.join(root.path, 'hello.txt')).readAsString(),
        'hello runtime\n',
      );
      final threadAfterApply = container
          .read(studioThreadProvider)
          .threads
          .firstWhere((candidate) => candidate.id == thread.id);
      final transactionEvents = threadAfterApply.turns.single.events
          .where(
            (event) =>
                event.type == StudioTurnEventType.completionSummary &&
                event.id.startsWith('patch-transaction-'),
          )
          .toList(growable: false);
      expect(transactionEvents, hasLength(1));
      expect(transactionEvents.single.title, 'Applied changes');
      expect(transactionEvents.single.detail, contains('Applied 1 files.'));
      expect(transactionEvents.single.detail, contains('Created hello.txt'));
      expect(transactionEvents.single.detail, contains('Checkpoint:'));
    },
  );

  test(
    'AgentTurnRuntime golden path plans, patches, applies, and verifies',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'plan',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Greeting file plan","summary":"Create a small greeting artifact.","plan_markdown":"# Plan\\n\\n- Create hello.txt with a greeting.\\n- Review the patch.\\n\\n## Assumptions\\n- The workspace root is the correct target.\\n\\n## Verification\\n- Verify the file contents after apply.","assumptions":["The workspace root is the correct target."],"verification_steps":["Verify the file contents after apply."],"files":[{"path":"hello.txt","intent":"Create greeting file","operation":"create"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'patch',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Create greeting file","summary":"Add hello.txt.","files":[{"path":"hello.txt","intent":"Create greeting file","operation":"create","content":"hello golden path\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'verify-cat',
              toolCallName: 'run_command',
              toolCallArguments: '{"command":"cat hello.txt"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(content: 'Verified hello.txt contents.'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      final storeRoot = await Directory.systemTemp.createTemp(
        'studio_golden_store_',
      );
      addTearDown(() => _delete(storeRoot));

      const planRequestId = 'golden-plan';
      final thread = harness.registerTurn(
        requestId: planRequestId,
        prompt: 'Create a plan for a greeting file',
        intent: TurnIntent.plan,
      );
      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: planRequestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Create a plan for a greeting file',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.plan,
            intent: TurnIntent.plan,
            model: 'gpt-5-nano',
            retryPrompt: 'Create a plan for a greeting file',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final planPatch = harness.container.read(patchProposalProvider).active;
      expect(planPatch, isNotNull);
      expect(planPatch!.isPlanOnly, isTrue);
      expect(planPatch.plannedFiles, ['hello.txt — Create greeting file']);
      var updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.done);
      expect(updatedThread.turns, hasLength(1));
      expect(updatedThread.turns.single.intent, TurnIntent.plan);
      expect(updatedThread.turns.single.status, StudioTurnStatus.completed);
      expect(
        harness.scriptedProvider?.exposedTools.first,
        contains('propose_patch'),
      );
      expect(
        harness.scriptedProvider?.exposedTools.first,
        isNot(contains('run_command')),
      );

      harness.container
          .read(patchProposalProvider.notifier)
          .markPlanAccepted(planPatch.id);

      const implementationRequestId = 'golden-implement';
      harness.registerTurn(
        requestId: implementationRequestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
        intent: TurnIntent.code,
      );
      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: implementationRequestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: AcceptedPlanContext.fromPatch(planPatch),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final concretePatch = harness.container
          .read(patchProposalProvider)
          .active;
      expect(concretePatch, isNotNull);
      expect(concretePatch!.isPlanOnly, isFalse);
      expect(concretePatch.edits.single.path, 'hello.txt');
      updatedThread = harness.thread(thread.id);
      final implementationTurn = updatedThread.turns.firstWhere(
        (turn) => turn.requestId == implementationRequestId,
      );
      expect(implementationTurn.status, StudioTurnStatus.completed);
      expect(
        implementationTurn.acceptedPlanState,
        AcceptedPlanState.patchProposed,
      );
      expect(
        harness.scriptedProvider?.exposedTools[1],
        contains('propose_patch'),
      );
      expect(
        harness.scriptedProvider?.exposedTools[1],
        isNot(contains('apply_patch_set')),
      );

      final apply = await harness.container
          .read(patchProposalProvider.notifier)
          .apply(concretePatch.id);
      expect(apply.status, PatchApplyStatus.applied);
      expect(apply.checkpointId, isNotNull);
      expect(apply.changedFiles, ['hello.txt']);
      expect(
        await File(p.join(harness.root.path, 'hello.txt')).readAsString(),
        'hello golden path\n',
      );
      updatedThread = harness.thread(thread.id);
      final implementationTurnAfterApply = updatedThread.turns.firstWhere(
        (turn) => turn.requestId == implementationRequestId,
      );
      expect(
        implementationTurnAfterApply.acceptedPlanState,
        AcceptedPlanState.implemented,
      );
      final applyEvents = implementationTurnAfterApply.events
          .where(
            (event) =>
                event.type == StudioTurnEventType.completionSummary &&
                event.id.startsWith('patch-transaction-'),
          )
          .toList(growable: false);
      expect(applyEvents, hasLength(1));
      expect(applyEvents.single.title, 'Applied changes');
      expect(applyEvents.single.detail, contains('Applied 1 files.'));
      expect(applyEvents.single.detail, contains('Created hello.txt'));
      expect(applyEvents.single.detail, contains('Checkpoint:'));

      const verifyRequestId = 'golden-verify';
      harness.registerTurn(
        requestId: verifyRequestId,
        prompt: 'Verify the greeting file',
        intent: TurnIntent.verify,
      );
      final verifyFuture = harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: verifyRequestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Verify the greeting file',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.verify,
            intent: TurnIntent.verify,
            model: 'gpt-5-nano',
            retryPrompt: 'Verify the greeting file',
            finishTask: false,
          );

      await _waitUntil(() {
        final current = harness.thread(thread.id);
        return current.turns.any(
          (turn) =>
              turn.requestId == verifyRequestId &&
              turn.events.any(
                (event) =>
                    event.type == StudioTurnEventType.approvalRequest &&
                    event.approvalId == 'verify-cat' &&
                    event.approvalState == ApprovalRequestState.pending,
              ),
        );
      });
      harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .approveOnce('verify-cat');
      await verifyFuture;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.done);
      expect(updatedThread.turns, hasLength(3));
      final verifyTurn = updatedThread.turns.firstWhere(
        (turn) => turn.requestId == verifyRequestId,
      );
      expect(verifyTurn.status, StudioTurnStatus.completed);
      expect(
        verifyTurn.toolResults
            .where((result) => result.toolName == 'run_command')
            .single
            .stdout,
        contains('hello golden path'),
      );
      expect(
        verifyTurn.events
            .where(
              (event) => event.type == StudioTurnEventType.assistantMessage,
            )
            .single
            .content,
        'Verified hello.txt contents.',
      );
      expect(
        harness.container.read(agentTurnRuntimeProvider).activeSessions,
        isEmpty,
      );

      final store = StudioThreadStore(baseDir: storeRoot.path);
      await store.save(harness.root.path, [updatedThread]);
      final reloadedThreads = await store.load(harness.root.path);
      expect(reloadedThreads, hasLength(1));
      final reloadedThread = reloadedThreads.single;
      expect(reloadedThread.status, StudioThreadStatus.done);
      expect(reloadedThread.requestId, isNull);
      expect(reloadedThread.streamingContent, isEmpty);
      expect(reloadedThread.turns, hasLength(3));
      expect(reloadedThread.turns.map((turn) => turn.status).toSet(), {
        StudioTurnStatus.completed,
      });
      final reloadedImplementation = reloadedThread.turns.firstWhere(
        (turn) => turn.requestId == implementationRequestId,
      );
      expect(
        reloadedImplementation.acceptedPlanState,
        AcceptedPlanState.implemented,
      );
      expect(
        reloadedImplementation.events.any(
          (event) =>
              event.type == StudioTurnEventType.completionSummary &&
              event.title == 'Applied changes' &&
              event.detail.contains('Created hello.txt'),
        ),
        isTrue,
      );
      final reloadedVerify = reloadedThread.turns.firstWhere(
        (turn) => turn.requestId == verifyRequestId,
      );
      expect(
        reloadedVerify.toolResults
            .where((result) => result.toolName == 'run_command')
            .single
            .stdout,
        contains('hello golden path'),
      );
      expect(
        reloadedVerify.events
            .where(
              (event) => event.type == StudioTurnEventType.assistantMessage,
            )
            .single
            .content,
        'Verified hello.txt contents.',
      );
    },
  );

  test(
    'AgentTurnRuntime classified hello stays chat-only and tool-free',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(content: 'Hello. How can I help?'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);

      const prompt = 'hello';
      final intent = IntentClassifier.classify(
        prompt,
        promptMode: StudioPromptMode.code,
        planModeEnabled: false,
      );
      final toolMode = studioToolModeForIntent(
        intent: intent,
        promptMode: StudioPromptMode.code,
        hasWorkspace: true,
        planModeEnabled: false,
      );
      final outboundText = studioOutboundPromptForIntent(
        text: prompt,
        intent: intent,
        planModeEnabled: false,
      );

      expect(intent, TurnIntent.chat);
      expect(toolMode, AgentToolMode.chat);
      expect(outboundText, contains('Do not inspect the project'));
      expect(outboundText, contains('do not run tools'));
      expect(studioIntentRequiresWorkspace(intent), isFalse);

      const requestId = 'classified-hello';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: prompt,
        intent: intent,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: outboundText,
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: toolMode,
            intent: intent,
            model: 'gpt-5-nano',
            retryPrompt: prompt,
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.lastError, isNull);
      final turn = updatedThread.turns.singleWhere(
        (candidate) => candidate.requestId == requestId,
      );
      expect(turn.status, StudioTurnStatus.completed);
      expect(updatedThread.lastError, isNull);
      expect(updatedThread.status, StudioThreadStatus.done);
      expect(turn.intent, TurnIntent.chat);
      expect(turn.toolResults, isEmpty);
      expect(harness.scriptedProvider?.exposedTools.single, isEmpty);
      expect(
        turn.events
            .where(
              (event) => event.type == StudioTurnEventType.assistantMessage,
            )
            .single
            .content,
        'Hello. How can I help?',
      );
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test(
    'AgentTurnRuntime classified vague fix prompt stays read-only and blocks patch attempts',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'too-eager-patch',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Too eager","summary":"This should not be allowed from Ask mode.","files":[{"path":"lib/main.dart","intent":"Guess at a fix","operation":"create","content":"void main() {}\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);

      const prompt = 'fix it';
      final intent = IntentClassifier.classify(
        prompt,
        promptMode: StudioPromptMode.fix,
        planModeEnabled: false,
      );
      final toolMode = studioToolModeForIntent(
        intent: intent,
        promptMode: StudioPromptMode.fix,
        hasWorkspace: true,
        planModeEnabled: false,
      );

      expect(intent, TurnIntent.ask);
      expect(toolMode, AgentToolMode.ask);
      expect(studioIntentRequiresWorkspace(intent), isFalse);

      const requestId = 'classified-vague-fix';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: prompt,
        intent: intent,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: prompt,
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: toolMode,
            intent: intent,
            model: 'gpt-5-nano',
            retryPrompt: prompt,
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final turn = updatedThread.turns.singleWhere(
        (candidate) => candidate.requestId == requestId,
      );
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(turn.status, StudioTurnStatus.failed);
      expect(turn.lastError, contains('unavailable tool'));
      expect(harness.scriptedProvider?.exposedTools.single, isNotEmpty);
      expect(
        harness.scriptedProvider?.exposedTools.single,
        isNot(contains('propose_patch')),
      );
      expect(
        turn.providerDiagnostics.map((event) => event.kind),
        contains(ProviderLifecycleEventKind.unavailableTool),
      );
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test(
    'AgentTurnRuntime classified inline artifact request stays read-only and blocks patch attempts',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'summary-patch',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Write summary file","summary":"This should not be allowed from Ask mode.","files":[{"path":"SUMMARY.md","intent":"Write summary","operation":"create","content":"# Summary\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);

      const prompt = 'write me a summary of this project';
      final intent = IntentClassifier.classify(
        prompt,
        promptMode: StudioPromptMode.code,
        planModeEnabled: false,
      );
      final toolMode = studioToolModeForIntent(
        intent: intent,
        promptMode: StudioPromptMode.code,
        hasWorkspace: true,
        planModeEnabled: false,
      );

      expect(intent, TurnIntent.ask);
      expect(toolMode, AgentToolMode.ask);
      expect(studioIntentRequiresWorkspace(intent), isFalse);

      const requestId = 'classified-inline-summary';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: prompt,
        intent: intent,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: prompt,
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: toolMode,
            intent: intent,
            model: 'gpt-5-nano',
            retryPrompt: prompt,
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final turn = updatedThread.turns.singleWhere(
        (candidate) => candidate.requestId == requestId,
      );
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(turn.status, StudioTurnStatus.failed);
      expect(turn.lastError, contains('unavailable tool'));
      expect(harness.scriptedProvider?.exposedTools.single, isNotEmpty);
      expect(
        harness.scriptedProvider?.exposedTools.single,
        isNot(contains('propose_patch')),
      );
      expect(
        turn.providerDiagnostics.map((event) => event.kind),
        contains(ProviderLifecycleEventKind.unavailableTool),
      );
      expect(harness.container.read(patchProposalProvider).active, isNull);
      expect(
        await File(p.join(harness.root.path, 'SUMMARY.md')).exists(),
        isFalse,
      );
    },
  );

  test(
    'AgentTurnRuntime classified code with verification defers commands until patch apply',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'read-login',
              toolCallName: 'read_file',
              toolCallArguments: '{"path":"login.dart"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'patch-login',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Fix login redirect","summary":"Update the login redirect and defer tests until the patch is applied.","files":[{"path":"login.dart","intent":"Fix redirect","operation":"modify","before":"String route = \'old\';\\n","content":"String route = \'new\';\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(content: 'Patch proposal is ready for review.'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      final loginFile = File(p.join(harness.root.path, 'login.dart'));
      await loginFile.writeAsString("String route = 'old';\n");

      const prompt = 'fix the login redirect and run tests';
      final intent = IntentClassifier.classify(
        prompt,
        promptMode: StudioPromptMode.fix,
        planModeEnabled: false,
      );
      final toolMode = studioToolModeForIntent(
        intent: intent,
        promptMode: StudioPromptMode.fix,
        hasWorkspace: true,
        planModeEnabled: false,
      );
      final outboundText = studioOutboundPromptForIntent(
        text: prompt,
        intent: intent,
        planModeEnabled: false,
      );

      expect(intent, TurnIntent.code);
      expect(toolMode, AgentToolMode.fix);
      expect(outboundText, contains('implementation and verification'));
      expect(outboundText, contains('produce app-applyable file edits'));
      expect(outboundText, contains('separate Verify turn'));
      expect(outboundText, contains('Do not run shell commands'));

      const requestId = 'classified-code-verify';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: prompt,
        intent: intent,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: outboundText,
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: toolMode,
            intent: intent,
            model: 'gpt-5-nano',
            retryPrompt: prompt,
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final exposedTools = harness.scriptedProvider!.exposedTools;
      expect(exposedTools, hasLength(2));
      expect(exposedTools[0], contains('read_file'));
      expect(exposedTools[0], isNot(contains('propose_patch')));
      expect(exposedTools[0], isNot(contains('run_command')));
      expect(exposedTools[1], contains('propose_patch'));
      for (final round in exposedTools) {
        expect(round, isNot(contains('run_command')));
        expect(round, isNot(contains('write_file')));
        expect(round, isNot(contains('apply_patch_set')));
      }

      final updatedThread = harness.thread(thread.id);
      final turn = updatedThread.turns.singleWhere(
        (candidate) => candidate.requestId == requestId,
      );
      expect(turn.status, StudioTurnStatus.completed);
      expect(updatedThread.status, StudioThreadStatus.done);
      expect(
        turn.toolResults.map((result) => result.toolName),
        containsAll(['read_file', 'propose_patch']),
      );
      final patch = harness.container.read(patchProposalProvider).active;
      expect(patch, isNotNull);
      expect(patch!.isPlanOnly, isFalse);
      expect(patch.edits.single.path, 'login.dart');
      expect(await loginFile.readAsString(), "String route = 'old';\n");

      final apply = await harness.container
          .read(patchProposalProvider.notifier)
          .applyActive();
      expect(apply.status, PatchApplyStatus.applied);
      expect(apply.changedFiles, ['login.dart']);
      expect(await loginFile.readAsString(), "String route = 'new';\n");
    },
  );

  test(
    'AgentTurnRuntime assembles split streaming tool-call arguments into patch proposals',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'read-hello',
              toolCallName: 'read_file',
              toolCallArguments: '{"path":"hello.txt"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'split-patch',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Update hello file","summary":"Update hello file.","files":[{"path":"hello.txt","intent":"Update hello file","operation":"modify","before":"old greeting\\n",',
            ),
            ChatChunk(
              toolCallIndex: 0,
              toolCallArguments: '"content":"hello split stream\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      await File(
        p.join(harness.root.path, 'hello.txt'),
      ).writeAsString('old greeting\n');

      const requestId = 'split-patch-tool-call';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Update hello file',
        intent: TurnIntent.code,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Update hello file',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            model: 'gpt-5-nano',
            retryPrompt: 'Update hello file',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final turn = updatedThread.turns.singleWhere(
        (candidate) => candidate.requestId == requestId,
      );
      expect(turn.status, StudioTurnStatus.completed);
      expect(
        turn.toolResults.map((result) => result.toolName),
        containsAll(['read_file', 'propose_patch']),
      );
      expect(turn.toolResults.last.status, ToolResultStatus.success);
      expect(turn.lastError, isNull);
      final patch = harness.container.read(patchProposalProvider).active;
      expect(patch, isNotNull);
      expect(patch!.edits.single.path, 'hello.txt');
      expect(patch.edits.single.after, 'hello split stream\n');
    },
  );

  test(
    'AgentTurnRuntime stops tool-only inspection loops with a blocking question',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'read-one',
              toolCallName: 'read_file',
              toolCallArguments: '{"path":"one.txt"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'read-two',
              toolCallName: 'read_file',
              toolCallArguments: '{"path":"two.txt"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'read-three',
              toolCallName: 'read_file',
              toolCallArguments: '{"path":"three.txt"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'read-four',
              toolCallName: 'read_file',
              toolCallArguments: '{"path":"four.txt"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      for (final name in const ['one.txt', 'two.txt', 'three.txt']) {
        await File(p.join(harness.root.path, name)).writeAsString('$name\n');
      }

      const requestId = 'tool-only-loop-stop';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Fix the vague issue',
        intent: TurnIntent.code,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Fix the vague issue',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.fix,
            intent: TurnIntent.code,
            model: 'gpt-5-nano',
            retryPrompt: 'Fix the vague issue',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final turn = updatedThread.turns.singleWhere(
        (candidate) => candidate.requestId == requestId,
      );
      expect(turn.lastError, isNull);
      expect(turn.status, StudioTurnStatus.completed);
      expect(turn.completedAt, isNotNull);
      expect(updatedThread.status, StudioThreadStatus.done);
      expect(
        turn.events
            .where(
              (event) => event.type == StudioTurnEventType.assistantMessage,
            )
            .single
            .content,
        'Which file should I inspect next?',
      );
      expect(turn.toolResults.map((result) => result.toolCallId), [
        'read-one',
        'read-two',
        'read-three',
      ]);
      expect(harness.scriptedProvider!.exposedTools, hasLength(3));
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test(
    'AgentTurnRuntime app-side apply rejects stale multi-file patch without partial writes',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'patch',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Update two files","summary":"Modify both files together.","files":[{"path":"first.txt","intent":"Update first file","operation":"modify","before":"first old\\n","content":"first new\\n"},{"path":"second.txt","intent":"Update second file","operation":"modify","before":"second old\\n","content":"second new\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      await File(
        p.join(harness.root.path, 'first.txt'),
      ).writeAsString('first old\n');
      await File(
        p.join(harness.root.path, 'second.txt'),
      ).writeAsString('second drifted\n');

      const requestId = 'runtime-stale-multifile-apply';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this accepted plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this accepted plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Update both files as a transaction.',
              markdown: '- Modify first.txt\n- Modify second.txt',
              plannedTargets: [
                PlannedFileTarget(
                  path: 'first.txt',
                  intent: 'Update first file',
                  operation: ProposedFileEditType.modify,
                ),
                PlannedFileTarget(
                  path: 'second.txt',
                  intent: 'Update second file',
                  operation: ProposedFileEditType.modify,
                ),
              ],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this accepted plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final turn = updatedThread.turns.singleWhere(
        (candidate) => candidate.requestId == requestId,
      );
      expect(updatedThread.status, StudioThreadStatus.done);
      expect(turn.status, StudioTurnStatus.completed);
      expect(turn.acceptedPlanState, AcceptedPlanState.patchProposed);

      final patch = harness.container.read(patchProposalProvider).active;
      expect(patch, isNotNull);
      expect(patch!.edits.map((edit) => edit.path), [
        'first.txt',
        'second.txt',
      ]);

      final apply = await harness.container
          .read(patchProposalProvider.notifier)
          .applyActive();
      expect(apply.status, PatchApplyStatus.conflict);
      expect(apply.conflictMessage, contains('second.txt'));
      expect(apply.checkpointId, isNull);
      expect(apply.changedFiles, isEmpty);
      expect(
        await File(p.join(harness.root.path, 'first.txt')).readAsString(),
        'first old\n',
      );
      expect(
        await File(p.join(harness.root.path, 'second.txt')).readAsString(),
        'second drifted\n',
      );

      final state = harness.container.read(patchProposalProvider);
      expect(state.active, isNotNull);
      expect(state.active!.applyStatus, PatchApplyStatus.conflict);
      expect(state.active!.changedFiles, isEmpty);
      expect(state.checkpoints, isEmpty);
      final turnAfterConflict = harness
          .thread(thread.id)
          .turns
          .singleWhere((candidate) => candidate.requestId == requestId);
      expect(turnAfterConflict.acceptedPlanState, AcceptedPlanState.failed);
    },
  );

  test(
    'AgentTurnRuntime rejects accepted-plan patches that omit planned files',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'patch',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Update first file only","summary":"This patch only covers part of the accepted plan.","files":[{"path":"first.txt","intent":"Update first file","operation":"modify","before":"first old\\n","content":"first new\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);

      const requestId = 'runtime-partial-accepted-plan';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this accepted plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this accepted plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Update both files as a transaction.',
              markdown: '- Modify first.txt\n- Modify second.txt',
              plannedFiles: ['first.txt', 'second.txt'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this accepted plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final turn = updatedThread.turns.singleWhere(
        (candidate) => candidate.requestId == requestId,
      );
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(turn.status, StudioTurnStatus.failed);
      expect(turn.acceptedPlanState, AcceptedPlanState.failed);
      expect(turn.lastError, contains('cover every planned file'));
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test(
    'AgentTurnRuntime rejects accepted-plan patches with mismatched file intent',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'patch',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Wrong intent patch","summary":"This touches the accepted file for the wrong reason.","files":[{"path":"first.txt","intent":"Update auth helper","operation":"modify","before":"first old\\n","content":"first new\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);

      const requestId = 'runtime-wrong-intent-accepted-plan';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this accepted plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this accepted plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Update the first file entrypoint.',
              markdown: '- Modify first.txt to update the entrypoint',
              plannedFiles: ['first.txt — Update first file'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this accepted plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final turn = updatedThread.turns.singleWhere(
        (candidate) => candidate.requestId == requestId,
      );
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(turn.status, StudioTurnStatus.failed);
      expect(turn.acceptedPlanState, AcceptedPlanState.failed);
      expect(turn.lastError, contains('cover every planned file'));
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test(
    'AgentTurnRuntime repairs accepted-plan prose after read-only inspection',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'read-main',
              toolCallName: 'read_file',
              toolCallArguments: '{"path":"lib/main.dart"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(
              content:
                  'I inspected the file and can make the requested change.',
            ),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'patch-repair',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Update main greeting","summary":"Change the greeting text.","files":[{"path":"lib/main.dart","intent":"Update greeting","operation":"modify","before":"void main() => print(\\"old\\");\\n","content":"void main() => print(\\"new\\");\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(content: 'Patch proposal is ready for review.'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      await Directory(p.join(harness.root.path, 'lib')).create();
      await File(
        p.join(harness.root.path, 'lib/main.dart'),
      ).writeAsString('void main() => print("old");\n');

      const requestId = 'runtime-read-then-repair';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this accepted plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this accepted plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted greeting plan',
              summary: 'Update lib/main.dart greeting.',
              markdown: '- Modify lib/main.dart',
              plannedFiles: ['lib/main.dart'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this accepted plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final turn = updatedThread.turns.singleWhere(
        (candidate) => candidate.requestId == requestId,
      );
      expect(updatedThread.status, StudioThreadStatus.done);
      expect(turn.status, StudioTurnStatus.completed);
      expect(turn.acceptedPlanState, AcceptedPlanState.patchProposed);
      expect(
        turn.providerDiagnostics.map((event) => event.kind),
        contains(ProviderLifecycleEventKind.outcomeRepair),
      );
      expect(
        turn.events.where(
          (event) => event.type == StudioTurnEventType.assistantMessage,
        ),
        isEmpty,
      );
      final patch = harness.container.read(patchProposalProvider).active;
      expect(patch, isNotNull);
      expect(patch!.edits.single.path, 'lib/main.dart');
      expect(patch.edits.single.after, 'void main() => print("new");\n');
    },
  );

  test(
    'AgentTurnRuntime repairs path-only accepted-plan patches with wrong intent',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'wrong-copy-patch',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Update login copy","summary":"Change login button text.","files":[{"path":"lib/router.dart","intent":"Update login copy","operation":"modify","before":"const redirect = \\"/old\\";\\n","content":"const redirect = \\"/old\\"; // Sign in\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'repair-redirect-patch',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Fix login redirect","summary":"Route login redirects to the dashboard.","files":[{"path":"lib/router.dart","intent":"Fix login redirect","operation":"modify","before":"const redirect = \\"/old\\";\\n","content":"const redirect = \\"/dashboard\\";\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      await Directory(p.join(harness.root.path, 'lib')).create();
      await File(
        p.join(harness.root.path, 'lib/router.dart'),
      ).writeAsString('const redirect = "/old";\n');

      const requestId = 'runtime-path-only-plan-wrong-intent';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this accepted plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this accepted plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Fix login redirect',
              summary: 'Fix the login redirect bug in lib/router.dart.',
              markdown:
                  '- Update lib/router.dart so login redirects correctly.',
              plannedFiles: ['lib/router.dart'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this accepted plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final turn = updatedThread.turns.singleWhere(
        (candidate) => candidate.requestId == requestId,
      );
      expect(updatedThread.status, StudioThreadStatus.done);
      expect(turn.status, StudioTurnStatus.completed);
      expect(turn.acceptedPlanState, AcceptedPlanState.patchProposed);
      expect(
        turn.providerDiagnostics.map((event) => event.kind),
        contains(ProviderLifecycleEventKind.outcomeRepair),
      );
      final patch = harness.container.read(patchProposalProvider).active;
      expect(patch, isNotNull);
      expect(patch!.title, 'Fix login redirect');
      expect(patch.edits.single.path, 'lib/router.dart');
      expect(patch.edits.single.after, 'const redirect = "/dashboard";\n');
    },
  );

  test(
    'AgentTurnRuntime recovers conflicted accepted-plan patch through revision',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'patch-conflict',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Update config","summary":"Use the accepted config value.","files":[{"path":"config.txt","intent":"Update config","operation":"modify","before":"old\\n","content":"new\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(content: 'Patch proposal is ready.'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'patch-revision',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Update config after drift","summary":"Use the current file contents as the patch base.","files":[{"path":"config.txt","intent":"Update config","operation":"modify","before":"drifted\\n","content":"new\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(content: 'Revised patch proposal is ready.'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      await File(
        p.join(harness.root.path, 'config.txt'),
      ).writeAsString('drifted\n');

      const firstRequestId = 'runtime-conflicted-patch';
      final thread = harness.registerTurn(
        requestId: firstRequestId,
        prompt: 'Implement this accepted plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: firstRequestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this accepted plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted config plan',
              summary: 'Update config.txt.',
              markdown: '- Modify config.txt',
              plannedFiles: ['config.txt'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this accepted plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final firstPatch = harness.container.read(patchProposalProvider).active;
      expect(firstPatch, isNotNull);
      final conflict = await harness.container
          .read(patchProposalProvider.notifier)
          .applyActive();
      expect(conflict.status, PatchApplyStatus.conflict);
      expect(conflict.conflictMessage, contains('config.txt'));
      expect(
        await File(p.join(harness.root.path, 'config.txt')).readAsString(),
        'drifted\n',
      );

      harness.container
          .read(patchProposalProvider.notifier)
          .requestRevision(
            PatchProposalRevisionRequest(
              patchSetId: firstPatch!.id,
              prompt: 'Use the current config.txt contents as the patch base.',
            ),
          );
      final revisionRequested = harness.container
          .read(patchProposalProvider)
          .history
          .firstWhere((patch) => patch.id == firstPatch.id);
      expect(
        revisionRequested.approvalStatus,
        PatchApprovalStatus.revisionRequested,
      );
      expect(revisionRequested.applyStatus, PatchApplyStatus.conflict);
      expect(revisionRequested.revisionPrompt, contains('current config'));

      const revisionRequestId = 'runtime-conflicted-patch-revision';
      final revisionThread = harness.registerTurn(
        requestId: revisionRequestId,
        prompt: 'Revise the accepted plan patch',
        acceptedPlanState: AcceptedPlanState.accepted,
      );
      expect(revisionThread.id, thread.id);

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: revisionRequestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Revise the accepted plan patch',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted config plan',
              summary: 'Update config.txt.',
              markdown: '- Modify config.txt',
              plannedFiles: ['config.txt'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Revise the accepted plan patch',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final revisedPatch = harness.container.read(patchProposalProvider).active;
      expect(revisedPatch, isNotNull);
      expect(revisedPatch!.id, isNot(firstPatch.id));
      final supersededPatch = harness.container
          .read(patchProposalProvider)
          .history
          .firstWhere((patch) => patch.id == firstPatch.id);
      expect(supersededPatch.supersededBy, revisedPatch.id);
      expect(supersededPatch.applyStatus, PatchApplyStatus.conflict);
      expect(
        supersededPatch.approvalStatus,
        PatchApprovalStatus.revisionRequested,
      );

      final applied = await harness.container
          .read(patchProposalProvider.notifier)
          .applyActive();
      expect(applied.status, PatchApplyStatus.applied);
      expect(applied.changedFiles, ['config.txt']);
      expect(applied.checkpointId, isNotNull);
      expect(
        await File(p.join(harness.root.path, 'config.txt')).readAsString(),
        'new\n',
      );

      final state = harness.container.read(patchProposalProvider);
      expect(state.active, isNull);
      final appliedPatch = state.history.firstWhere(
        (patch) => patch.id == revisedPatch.id,
      );
      expect(appliedPatch.applyStatus, PatchApplyStatus.applied);
      expect(appliedPatch.checkpointId, applied.checkpointId);
      expect(
        state.history.firstWhere((patch) => patch.id == firstPatch.id),
        isNotNull,
      );
    },
  );

  test(
    'AgentTurnRuntime applies accepted-plan mixed file operations with verification suggestions',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'patch',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Implement auth cleanup","summary":"Create, update, and remove files as one patch.","files":[{"path":"lib/auth.dart","intent":"Update auth status","operation":"modify","before":"String status = \\"old\\";\\n","content":"String status = \\"new\\";\\n"},{"path":"lib/auth_helper.dart","intent":"Add helper","operation":"create","content":"String helper() => \\"ready\\";\\n"},{"path":"docs/old_auth.md","intent":"Remove stale docs","operation":"delete","before":"old docs\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);

      await Directory(p.join(harness.root.path, 'lib')).create(recursive: true);
      await Directory(
        p.join(harness.root.path, 'docs'),
      ).create(recursive: true);
      await File(
        p.join(harness.root.path, 'lib', 'auth.dart'),
      ).writeAsString('String status = "old";\n');
      await File(
        p.join(harness.root.path, 'docs', 'old_auth.md'),
      ).writeAsString('old docs\n');
      await File(
        p.join(harness.root.path, 'pubspec.yaml'),
      ).writeAsString('name: runtime_patch_test\n');

      const requestId = 'runtime-mixed-apply';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this accepted plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this accepted plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted auth cleanup plan',
              summary: 'Update auth code, add helper, and remove old docs.',
              markdown:
                  '- Modify lib/auth.dart\n- Create lib/auth_helper.dart\n- Delete docs/old_auth.md',
              plannedTargets: [
                PlannedFileTarget(
                  path: 'lib/auth.dart',
                  intent: 'Update auth status',
                  operation: ProposedFileEditType.modify,
                ),
                PlannedFileTarget(
                  path: 'lib/auth_helper.dart',
                  intent: 'Add helper',
                  operation: ProposedFileEditType.create,
                ),
                PlannedFileTarget(
                  path: 'docs/old_auth.md',
                  intent: 'Remove stale docs',
                  operation: ProposedFileEditType.delete,
                ),
              ],
              verificationRequested: true,
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this accepted plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final turn = updatedThread.turns.singleWhere(
        (candidate) => candidate.requestId == requestId,
      );
      expect(updatedThread.status, StudioThreadStatus.done);
      expect(turn.status, StudioTurnStatus.completed);
      expect(turn.acceptedPlanState, AcceptedPlanState.patchProposed);

      final patch = harness.container.read(patchProposalProvider).active;
      expect(patch, isNotNull);
      expect(patch!.edits.map((edit) => edit.path), [
        'lib/auth.dart',
        'lib/auth_helper.dart',
        'docs/old_auth.md',
      ]);
      expect(patch.verificationRequested, isTrue);
      expect(
        harness.scriptedProvider!.exposedTools.expand((round) => round),
        isNot(contains('apply_patch_set')),
      );
      expect(
        harness.scriptedProvider!.exposedTools.expand((round) => round),
        isNot(contains('run_command')),
      );

      final apply = await harness.container
          .read(patchProposalProvider.notifier)
          .applyActive();
      expect(apply.status, PatchApplyStatus.applied);
      expect(apply.checkpointId, isNotNull);
      expect(apply.changedFiles, [
        'lib/auth.dart',
        'lib/auth_helper.dart',
        'docs/old_auth.md',
      ]);
      expect(apply.diffSummary, contains('lib/auth.dart'));
      expect(apply.diffSummary, contains('lib/auth_helper.dart'));
      expect(apply.diffSummary, contains('docs/old_auth.md'));
      expect(apply.verificationRequested, isTrue);
      expect(apply.verificationSuggestions, isNotEmpty);
      expect(apply.verificationSuggestions, contains('flutter analyze'));
      expect(apply.verificationSuggestions, contains('flutter test'));
      final turnAfterApply = harness
          .thread(thread.id)
          .turns
          .singleWhere((candidate) => candidate.requestId == requestId);
      expect(turnAfterApply.acceptedPlanState, AcceptedPlanState.implemented);

      expect(
        await File(
          p.join(harness.root.path, 'lib', 'auth.dart'),
        ).readAsString(),
        'String status = "new";\n',
      );
      expect(
        await File(
          p.join(harness.root.path, 'lib', 'auth_helper.dart'),
        ).readAsString(),
        'String helper() => "ready";\n',
      );
      expect(
        await File(p.join(harness.root.path, 'docs', 'old_auth.md')).exists(),
        isFalse,
      );

      final state = harness.container.read(patchProposalProvider);
      final renderedPatch = state.active ?? state.history.first;
      expect(renderedPatch.applyStatus, PatchApplyStatus.applied);
      expect(renderedPatch.checkpointId, apply.checkpointId);
      expect(
        renderedPatch.verificationSuggestions,
        apply.verificationSuggestions,
      );

      final restored = await harness.container
          .read(patchProposalProvider.notifier)
          .restoreCheckpoint(apply.checkpointId!);
      expect(restored.status, PatchApplyStatus.restored);
      expect(restored.checkpointId, apply.checkpointId);
      expect(restored.changedFiles, [
        'lib/auth.dart',
        'lib/auth_helper.dart',
        'docs/old_auth.md',
      ]);

      expect(
        await File(
          p.join(harness.root.path, 'lib', 'auth.dart'),
        ).readAsString(),
        'String status = "old";\n',
      );
      expect(
        await File(
          p.join(harness.root.path, 'lib', 'auth_helper.dart'),
        ).exists(),
        isFalse,
      );
      expect(
        await File(
          p.join(harness.root.path, 'docs', 'old_auth.md'),
        ).readAsString(),
        'old docs\n',
      );

      final restoredState = harness.container.read(patchProposalProvider);
      final restoredPatch = restoredState.history.firstWhere(
        (candidate) => candidate.id == patch.id,
      );
      expect(restoredPatch.applyStatus, PatchApplyStatus.restored);
      expect(restoredPatch.changedFiles, restored.changedFiles);
      expect(restoredState.message, 'Restored 3 files.');
    },
  );

  test(
    'AgentTurnRuntime repairs accepted-plan patches with mismatched operations',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'patch',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Delete auth instead","summary":"Wrong operation for the accepted plan.","files":[{"path":"lib/auth.dart","intent":"Update auth status","operation":"delete","before":"String status = \\"old\\";\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'patch-repair',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Update auth status","summary":"Correctly modifies the accepted plan target.","files":[{"path":"lib/auth.dart","intent":"Update auth status","operation":"modify","before":"String status = \\"old\\";\\n","content":"String status = \\"new\\";\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);

      await Directory(p.join(harness.root.path, 'lib')).create(recursive: true);
      await File(
        p.join(harness.root.path, 'lib', 'auth.dart'),
      ).writeAsString('String status = "old";\n');

      const requestId = 'runtime-wrong-operation';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this accepted plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this accepted plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted auth update plan',
              summary: 'Modify auth status.',
              markdown: '- Modify lib/auth.dart',
              plannedFiles: ['lib/auth.dart — Update auth status'],
              plannedTargets: [
                PlannedFileTarget(
                  path: 'lib/auth.dart',
                  intent: 'Update auth status',
                  operation: ProposedFileEditType.modify,
                ),
              ],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this accepted plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final turn = updatedThread.turns.singleWhere(
        (candidate) => candidate.requestId == requestId,
      );
      expect(updatedThread.status, StudioThreadStatus.done);
      expect(turn.status, StudioTurnStatus.completed);
      expect(turn.acceptedPlanState, AcceptedPlanState.patchProposed);
      expect(
        turn.providerDiagnostics.map((event) => event.kind),
        contains(ProviderLifecycleEventKind.outcomeRepair),
      );
      final patch = harness.container.read(patchProposalProvider).active;
      expect(patch, isNotNull);
      expect(patch!.edits.single.type, ProposedFileEditType.modify);
      expect(patch.edits.single.after, 'String status = "new";\n');
      expect(
        await File(
          p.join(harness.root.path, 'lib', 'auth.dart'),
        ).readAsString(),
        'String status = "old";\n',
      );
    },
  );

  test(
    'AgentTurnRuntime fails cleanly when provider returns no bytes',
    () async {
      final harness = await _RuntimeHarness.create(rounds: const [[]]);
      addTearDown(harness.dispose);
      const requestId = 'runtime-empty';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Add a file.',
              markdown: '- Create file.txt',
              plannedFiles: ['file.txt'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        harness.container.read(agentTurnRuntimeProvider).activeSessions,
        isEmpty,
      );
      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        updatedThread.turns.single.acceptedPlanState,
        AcceptedPlanState.failed,
      );
      expect(updatedThread.turns.single.lastError, contains('no bytes'));
      expect(
        updatedThread.turns.single.providerDiagnostics.map(
          (event) => event.kind,
        ),
        contains(ProviderLifecycleEventKind.noFirstByte),
      );
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test(
    'AgentTurnRuntime does not duplicate provider no-first-byte diagnostics',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              lifecycleKind: ProviderLifecycleEventKind.noFirstByte,
              lifecycleDetail: 'Provider closed with no bytes.',
            ),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-provider-no-first-byte';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Add a file.',
              markdown: '- Create file.txt',
              plannedFiles: ['file.txt'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final diagnostics = updatedThread.turns.single.providerDiagnostics;
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        diagnostics
            .where(
              (event) => event.kind == ProviderLifecycleEventKind.noFirstByte,
            )
            .length,
        1,
      );
      expect(
        diagnostics.map((event) => event.kind),
        contains(ProviderLifecycleEventKind.failed),
      );
    },
  );

  test(
    'AgentTurnRuntime fails done-only provider responses as no output',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [ChatChunk(finishReason: 'stop', isDone: true)],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-done-only';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Add a file.',
              markdown: '- Create file.txt',
              plannedFiles: ['file.txt'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        updatedThread.turns.single.acceptedPlanState,
        AcceptedPlanState.failed,
      );
      expect(updatedThread.turns.single.lastError, contains('no bytes'));
      expect(
        updatedThread.turns.single.providerDiagnostics.map(
          (event) => event.kind,
        ),
        contains(ProviderLifecycleEventKind.noFirstByte),
      );
      expect(
        updatedThread.turns.single.providerDiagnostics.map(
          (event) => event.kind,
        ),
        isNot(contains(ProviderLifecycleEventKind.firstByte)),
      );
    },
  );

  test(
    'AgentTurnRuntime persists non-streaming no-output provider diagnostics',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              lifecycleKind: ProviderLifecycleEventKind.connected,
              lifecycleDetail: 'HTTP 200',
            ),
            ChatChunk(lifecycleKind: ProviderLifecycleEventKind.firstByte),
            ChatChunk(
              lifecycleKind: ProviderLifecycleEventKind.nonSseJson,
              lifecycleDetail: 'Provider returned application/json.',
            ),
            ChatChunk(
              lifecycleKind: ProviderLifecycleEventKind.jsonFallback,
              lifecycleDetail: 'Parsed non-streaming response.',
            ),
            ChatChunk(
              lifecycleKind: ProviderLifecycleEventKind.noTextOrTool,
              lifecycleDetail: 'JSON response had no assistant text or tools.',
            ),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-json-no-output';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'hello',
        intent: TurnIntent.chat,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'hello',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.chat,
            intent: TurnIntent.chat,
            model: 'gpt-5-nano',
            retryPrompt: 'hello',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final diagnostics = updatedThread.turns.single.providerDiagnostics;
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(updatedThread.turns.single.lastError, contains('No model output'));
      expect(updatedThread.turns.single.lastError, contains('without text'));
      expect(
        updatedThread.turns.single.events
            .where((event) => event.type == StudioTurnEventType.error)
            .single
            .detail,
        contains('No model output'),
      );
      expect(
        diagnostics.map((event) => event.kind),
        containsAll([
          ProviderLifecycleEventKind.connected,
          ProviderLifecycleEventKind.firstByte,
          ProviderLifecycleEventKind.nonSseJson,
          ProviderLifecycleEventKind.jsonFallback,
          ProviderLifecycleEventKind.noTextOrTool,
        ]),
      );
      expect(
        diagnostics
            .firstWhere(
              (event) => event.kind == ProviderLifecycleEventKind.noTextOrTool,
            )
            .detail,
        contains('no assistant text'),
      );
      final lifecycle = harness.container
          .read(studioRequestLifecycleProvider)
          .find(requestId);
      expect(lifecycle?.lastEventKind, StudioRequestLifecycleEventKind.failed);
      expect(lifecycle?.lastEventDetail, contains('without text'));
    },
  );

  test(
    'AgentTurnRuntime preserves malformed stream diagnostics on successful turn',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(lifecycleKind: ProviderLifecycleEventKind.firstByte),
            ChatChunk(
              lifecycleKind: ProviderLifecycleEventKind.malformedChunk,
              lifecycleDetail: 'Malformed SSE line ignored.',
            ),
            ChatChunk(content: 'Recovered after a malformed stream chunk.'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-malformed-recover';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'hello',
        intent: TurnIntent.chat,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'hello',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.chat,
            intent: TurnIntent.chat,
            model: 'gpt-5-nano',
            retryPrompt: 'hello',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.done);
      expect(updatedThread.turns.single.status, StudioTurnStatus.completed);
      expect(
        updatedThread.turns.single.providerDiagnostics.map(
          (event) => event.kind,
        ),
        contains(ProviderLifecycleEventKind.malformedChunk),
      );
      expect(
        updatedThread.turns.single.events
            .where(
              (event) => event.type == StudioTurnEventType.assistantMessage,
            )
            .single
            .content,
        'Recovered after a malformed stream chunk.',
      );
    },
  );

  test(
    'AgentTurnRuntime fails accepted-plan implementation that only re-plans',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'patch',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Still a plan","summary":"No concrete edits.","files":[{"path":"file.txt","intent":"create later"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-replan';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Add a file.',
              markdown: '- Create file.txt',
              plannedFiles: ['file.txt'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        harness.container.read(agentTurnRuntimeProvider).activeSessions,
        isEmpty,
      );
      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        updatedThread.turns.single.acceptedPlanState,
        AcceptedPlanState.failed,
      );
      expect(
        updatedThread.turns.single.lastError,
        contains('app-applyable file edits'),
      );
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test(
    'AgentTurnRuntime rejects accepted-plan diff-only patch proposals',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'patch',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Diff-only patch","summary":"Shows a diff but no target content.","files":[{"path":"file.txt","intent":"create greeting","operation":"modify","unified_diff":"-old\\\\n+new\\\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-diff-only-patch';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Add a file.',
              markdown: '- Create file.txt',
              plannedFiles: ['file.txt'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        updatedThread.turns.single.acceptedPlanState,
        AcceptedPlanState.failed,
      );
      expect(
        updatedThread.turns.single.lastError,
        contains('app-applyable file edits'),
      );
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test('AgentTurnRuntime rejects accepted-plan no-op modify proposals', () async {
    final harness = await _RuntimeHarness.create(
      rounds: const [
        [
          ChatChunk(
            toolCallIndex: 0,
            toolCallId: 'patch',
            toolCallName: 'propose_patch',
            toolCallArguments:
                '{"title":"No-op patch","summary":"Leaves the file unchanged.","files":[{"path":"file.txt","intent":"update greeting","operation":"modify","before":"hello\\\\n","content":"hello\\\\n"}]}',
          ),
          ChatChunk(finishReason: 'tool_calls', isDone: true),
        ],
      ],
    );
    addTearDown(harness.dispose);
    const requestId = 'runtime-noop-patch';
    final thread = harness.registerTurn(
      requestId: requestId,
      prompt: 'Implement this plan',
      acceptedPlanState: AcceptedPlanState.accepted,
    );

    await harness.container
        .read(agentTurnRuntimeProvider.notifier)
        .startTurn(
          requestId: requestId,
          threadId: thread.id,
          taskId: null,
          outboundText: 'Implement this plan',
          attachments: const [],
          historyOverride: const <ChatMessage>[],
          toolMode: AgentToolMode.code,
          intent: TurnIntent.code,
          acceptedPlan: const AcceptedPlanContext(
            patchSetId: 'plan',
            title: 'Accepted plan',
            summary: 'Update a file.',
            markdown: '- Update file.txt',
            plannedFiles: ['file.txt'],
          ),
          model: 'gpt-5-nano',
          retryPrompt: 'Implement this plan',
          finishTask: false,
        );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final updatedThread = harness.thread(thread.id);
    expect(updatedThread.status, StudioThreadStatus.failed);
    expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
    expect(
      updatedThread.turns.single.acceptedPlanState,
      AcceptedPlanState.failed,
    );
    expect(
      updatedThread.turns.single.lastError,
      contains('app-applyable file edits'),
    );
    expect(harness.container.read(patchProposalProvider).active, isNull);
  });

  test(
    'AgentTurnRuntime rejects accepted-plan path-only delete proposals',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'patch',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Delete stale file","summary":"Remove an obsolete file.","files":[{"path":"obsolete.txt","intent":"remove stale artifact","operation":"delete"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-path-only-delete-patch';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Remove an obsolete artifact.',
              markdown: '- Delete obsolete.txt',
              plannedFiles: ['obsolete.txt'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        updatedThread.turns.single.acceptedPlanState,
        AcceptedPlanState.failed,
      );
      expect(
        updatedThread.turns.single.lastError,
        contains('app-applyable file edits'),
      );
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test(
    'AgentTurnRuntime rejects accepted-plan patch aliases for the same file',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'patch',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Update main","summary":"Two edits target the same file through path aliases.","files":[{"path":"lib/main.dart","intent":"First edit","operation":"modify","before":"void old() {}\\\\n","content":"void one() {}\\\\n"},{"path":"./lib//main.dart","intent":"Second edit","operation":"modify","before":"void old() {}\\\\n","content":"void two() {}\\\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-aliased-duplicate-patch';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Update the main entrypoint.',
              markdown: '- Update lib/main.dart',
              plannedFiles: ['lib/main.dart'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        updatedThread.turns.single.acceptedPlanState,
        AcceptedPlanState.failed,
      );
      expect(
        updatedThread.turns.single.lastError,
        contains('app-applyable file edits'),
      );
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test(
    'AgentTurnRuntime fails explicit code turns that finish as vague prose',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(content: 'I fixed the login redirect bug.'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
          [
            ChatChunk(content: 'The login redirect is handled now.'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-code-vague';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'fix the login redirect bug',
        intent: TurnIntent.code,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'fix the login redirect bug',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.fix,
            intent: TurnIntent.code,
            model: 'gpt-5-nano',
            retryPrompt: 'fix the login redirect bug',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        updatedThread.turns.single.lastError,
        contains('app-applyable file edits'),
      );
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test(
    'AgentTurnRuntime fails accepted plans that ask for generic approval',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(content: 'Should I proceed with this implementation?'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-plan-generic-approval';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Add a route.',
              markdown: '- Add route file',
              plannedFiles: ['lib/router.dart'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        updatedThread.turns.single.acceptedPlanState,
        AcceptedPlanState.failed,
      );
      expect(updatedThread.turns.single.lastError, contains('approval text'));
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test(
    'AgentTurnRuntime rejects patch proposals that still ask for typed approval',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(content: 'Reply approve and I will apply these changes.'),
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'patch',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Add greeting","summary":"Create a greeting file.","files":[{"path":"hello.txt","intent":"create greeting","operation":"create","content":"hello\\\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-patch-plus-typed-approval';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Add a greeting file.',
              markdown: '- Add hello.txt',
              plannedFiles: ['hello.txt'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        updatedThread.turns.single.acceptedPlanState,
        AcceptedPlanState.failed,
      );
      expect(updatedThread.turns.single.lastError, contains('review UI'));
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test(
    'AgentTurnRuntime rejects patch proposals that ask for prose approval',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(content: 'Please approve the patch plan as described.'),
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'patch',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Add greeting","summary":"Create a greeting file.","files":[{"path":"hello.txt","intent":"create greeting","operation":"create","content":"hello\\\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-patch-plus-prose-approval';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Add a greeting file.',
              markdown: '- Add hello.txt',
              plannedFiles: ['hello.txt'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        updatedThread.turns.single.acceptedPlanState,
        AcceptedPlanState.failed,
      );
      expect(updatedThread.turns.single.lastError, contains('approval text'));
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test(
    'AgentTurnRuntime rejects patch proposals that claim they are applied',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              content:
                  'Done, I implemented the requested changes and tests pass.',
            ),
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'patch',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Add greeting","summary":"Create a greeting file.","files":[{"path":"hello.txt","intent":"create greeting","operation":"create","content":"hello\\\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-patch-plus-false-completion';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Add a greeting file.',
              markdown: '- Add hello.txt',
              plannedFiles: ['hello.txt'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        updatedThread.turns.single.acceptedPlanState,
        AcceptedPlanState.failed,
      );
      expect(
        updatedThread.turns.single.lastError,
        contains('already applied or verified'),
      );
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test(
    'AgentTurnRuntime lets explicit code turns ask one missing-context question',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(content: 'Which login route should I update?'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-code-question';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'fix the login redirect bug',
        intent: TurnIntent.code,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'fix the login redirect bug',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.fix,
            intent: TurnIntent.code,
            model: 'gpt-5-nano',
            retryPrompt: 'fix the login redirect bug',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.done);
      expect(updatedThread.turns.single.status, StudioTurnStatus.completed);
      expect(
        updatedThread.turns.single.events
            .where(
              (event) => event.type == StudioTurnEventType.assistantMessage,
            )
            .single
            .content,
        'Which login route should I update?',
      );
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test(
    'AgentTurnRuntime lets accepted plans ask one missing-context question',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(content: 'What route path should lib/router.dart add?'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-plan-question';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Add a route.',
              markdown: '- Add route file',
              plannedFiles: ['lib/router.dart'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.done);
      expect(updatedThread.turns.single.status, StudioTurnStatus.completed);
      expect(
        updatedThread.turns.single.acceptedPlanState,
        AcceptedPlanState.blockedForMissingContext,
      );
      expect(
        updatedThread.turns.single.events
            .where(
              (event) => event.type == StudioTurnEventType.assistantMessage,
            )
            .single
            .content,
        'What route path should lib/router.dart add?',
      );
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test(
    'AgentTurnRuntime rejects accepted-plan questions for already planned target files',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(content: 'Which file should receive the new route?'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-plan-redundant-target-question';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Add a route.',
              markdown: '- Add route file',
              plannedFiles: ['lib/router.dart'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        updatedThread.turns.single.acceptedPlanState,
        AcceptedPlanState.failed,
      );
      expect(
        updatedThread.turns.single.lastError,
        contains('already names the implementation target files'),
      );
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test(
    'AgentTurnRuntime completes chat turns without exposing tools',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(content: 'Hello.'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-chat';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'hello',
        intent: TurnIntent.chat,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'hello',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.chat,
            intent: TurnIntent.chat,
            model: 'gpt-5-nano',
            retryPrompt: 'hello',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.done);
      expect(updatedThread.turns.single.status, StudioTurnStatus.completed);
      expect(
        updatedThread.turns.single.events
            .where(
              (event) => event.type == StudioTurnEventType.assistantMessage,
            )
            .single
            .content,
        'Hello.',
      );
      expect(harness.scriptedProvider?.exposedTools.single, isEmpty);
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test('AgentTurnRuntime rejects tool calls in chat mode', () async {
    final harness = await _RuntimeHarness.create(
      rounds: const [
        [
          ChatChunk(
            toolCallIndex: 0,
            toolCallId: 'read',
            toolCallName: 'read_file',
            toolCallArguments: '{"path":"README.md"}',
          ),
          ChatChunk(finishReason: 'tool_calls', isDone: true),
        ],
      ],
    );
    addTearDown(harness.dispose);
    const requestId = 'runtime-chat-tool';
    final thread = harness.registerTurn(
      requestId: requestId,
      prompt: 'hello',
      intent: TurnIntent.chat,
    );

    await harness.container
        .read(agentTurnRuntimeProvider.notifier)
        .startTurn(
          requestId: requestId,
          threadId: thread.id,
          taskId: null,
          outboundText: 'hello',
          attachments: const [],
          historyOverride: const <ChatMessage>[],
          toolMode: AgentToolMode.chat,
          intent: TurnIntent.chat,
          model: 'gpt-5-nano',
          retryPrompt: 'hello',
          finishTask: false,
        );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final updatedThread = harness.thread(thread.id);
    expect(updatedThread.status, StudioThreadStatus.failed);
    expect(updatedThread.turns.single.lastError, contains('unavailable tool'));
    expect(harness.scriptedProvider?.exposedTools.single, isEmpty);
    expect(
      updatedThread.turns.single.providerDiagnostics.map((event) => event.kind),
      contains(ProviderLifecycleEventKind.unavailableTool),
    );
  });

  test('AgentTurnRuntime rejects patch proposals in ask mode', () async {
    final harness = await _RuntimeHarness.create(
      rounds: const [
        [
          ChatChunk(
            toolCallIndex: 0,
            toolCallId: 'patch',
            toolCallName: 'propose_patch',
            toolCallArguments:
                '{"title":"Oops","summary":"Should not propose.","files":[{"path":"README.md","intent":"modify","content":"bad"}]}',
          ),
          ChatChunk(finishReason: 'tool_calls', isDone: true),
        ],
      ],
    );
    addTearDown(harness.dispose);
    const requestId = 'runtime-ask-patch';
    final thread = harness.registerTurn(
      requestId: requestId,
      prompt: 'what is in this project?',
      intent: TurnIntent.ask,
    );

    await harness.container
        .read(agentTurnRuntimeProvider.notifier)
        .startTurn(
          requestId: requestId,
          threadId: thread.id,
          taskId: null,
          outboundText: 'what is in this project?',
          attachments: const [],
          historyOverride: const <ChatMessage>[],
          toolMode: AgentToolMode.ask,
          intent: TurnIntent.ask,
          model: 'gpt-5-nano',
          retryPrompt: 'what is in this project?',
          finishTask: false,
        );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final updatedThread = harness.thread(thread.id);
    expect(updatedThread.status, StudioThreadStatus.failed);
    expect(updatedThread.turns.single.lastError, contains('unavailable tool'));
    expect(
      harness.scriptedProvider?.exposedTools.single,
      isNot(contains('propose_patch')),
    );
    expect(harness.container.read(patchProposalProvider).active, isNull);
  });

  test(
    'AgentTurnRuntime rejects read-only turns that claim mutation or verification',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(content: 'I updated lib/main.dart and ran the tests.'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-ask-false-work-claim';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'what is wrong with this project?',
        intent: TurnIntent.ask,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'what is wrong with this project?',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.ask,
            intent: TurnIntent.ask,
            model: 'gpt-5-nano',
            retryPrompt: 'what is wrong with this project?',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(
        updatedThread.turns.single.lastError,
        contains('read-only turn claimed'),
      );
    },
  );

  test(
    'AgentTurnRuntime rejects confident read-only findings after failed inspection',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'read-missing',
              toolCallName: 'read_file',
              toolCallArguments: '{"path":"missing.dart"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(content: 'I found no issues in missing.dart.'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-ask-failed-inspection-claim';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'check missing.dart for issues',
        intent: TurnIntent.ask,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'check missing.dart for issues',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.ask,
            intent: TurnIntent.ask,
            model: 'gpt-5-nano',
            retryPrompt: 'check missing.dart for issues',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(
        updatedThread.turns.single.lastError,
        contains('could not inspect the requested context'),
      );
    },
  );

  test('AgentTurnRuntime rejects commands in plan mode', () async {
    final harness = await _RuntimeHarness.create(
      rounds: const [
        [
          ChatChunk(
            toolCallIndex: 0,
            toolCallId: 'cmd',
            toolCallName: 'run_command',
            toolCallArguments: '{"command":"pytest -q"}',
          ),
          ChatChunk(finishReason: 'tool_calls', isDone: true),
        ],
      ],
    );
    addTearDown(harness.dispose);
    const requestId = 'runtime-plan-command';
    final thread = harness.registerTurn(
      requestId: requestId,
      prompt: 'make a plan',
      intent: TurnIntent.plan,
    );

    await harness.container
        .read(agentTurnRuntimeProvider.notifier)
        .startTurn(
          requestId: requestId,
          threadId: thread.id,
          taskId: null,
          outboundText: 'make a plan',
          attachments: const [],
          historyOverride: const <ChatMessage>[],
          toolMode: AgentToolMode.plan,
          intent: TurnIntent.plan,
          model: 'gpt-5-nano',
          retryPrompt: 'make a plan',
          finishTask: false,
        );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final updatedThread = harness.thread(thread.id);
    expect(updatedThread.status, StudioThreadStatus.failed);
    expect(updatedThread.turns.single.lastError, contains('unavailable tool'));
    expect(
      harness.scriptedProvider?.exposedTools.single,
      isNot(contains('run_command')),
    );
  });

  test(
    'AgentTurnRuntime verify command waits for scoped approval and resumes',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'cmd',
              toolCallName: 'run_command',
              toolCallArguments: '{"command":"pwd"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(content: 'Verification command completed.'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-verify-command';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'run pwd',
        intent: TurnIntent.verify,
      );

      final runFuture = harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'run pwd',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.verify,
            intent: TurnIntent.verify,
            model: 'gpt-5-nano',
            retryPrompt: 'run pwd',
            finishTask: false,
          );

      await _waitUntil(() {
        final updated = harness.thread(thread.id);
        return updated.turns.single.events.any(
          (event) =>
              event.type == StudioTurnEventType.approvalRequest &&
              event.approvalId == 'cmd' &&
              event.approvalState == ApprovalRequestState.pending,
        );
      });

      var updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.waitingForApproval);
      final pendingApproval = updatedThread.turns.single.events.singleWhere(
        (event) => event.approvalId == 'cmd',
      );
      expect(pendingApproval.toolName, 'run_command');
      expect(pendingApproval.approvalPreview, contains('pwd'));
      expect(
        pendingApproval.approvalWarnings,
        contains('Shell command requires review.'),
      );

      harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .approveOnce('cmd');
      await runFuture;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.done);
      expect(updatedThread.turns.single.status, StudioTurnStatus.completed);
      expect(
        updatedThread.turns.single.events
            .singleWhere((event) => event.approvalId == 'cmd')
            .approvalState,
        ApprovalRequestState.approved,
      );
      expect(
        updatedThread.turns.single.toolResults
            .where((result) => result.toolName == 'run_command')
            .single
            .stdout,
        contains(harness.root.path),
      );
      expect(
        updatedThread.turns.single.events
            .where(
              (event) => event.type == StudioTurnEventType.assistantMessage,
            )
            .single
            .content,
        'Verification command completed.',
      );
      expect(
        harness.scriptedProvider?.exposedTools.first,
        contains('run_command'),
      );
    },
  );

  test(
    'AgentTurnRuntime rejects Verify prose without an approved command',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(content: 'The tests should pass.'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-verify-prose-only';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'verify tests pass',
        intent: TurnIntent.verify,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'verify tests pass',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.verify,
            intent: TurnIntent.verify,
            model: 'gpt-5-nano',
            retryPrompt: 'verify tests pass',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        updatedThread.turns.single.lastError,
        contains('approved command'),
      );
      expect(
        updatedThread.turns.single.events.where(
          (event) => event.type == StudioTurnEventType.assistantMessage,
        ),
        isEmpty,
      );
    },
  );

  test(
    'AgentTurnRuntime ignores global auto-approve settings for Studio commands',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'cmd',
              toolCallName: 'run_command',
              toolCallArguments: '{"command":"pwd"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      harness.container.read(settingsProvider.notifier).setAutoApprove(true);
      const requestId = 'runtime-global-auto-approve-ignored';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'run pwd',
        intent: TurnIntent.verify,
      );

      final runFuture = harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'run pwd',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.verify,
            intent: TurnIntent.verify,
            model: 'gpt-5-nano',
            retryPrompt: 'run pwd',
            finishTask: false,
          );

      await _waitUntil(() {
        final updated = harness.thread(thread.id);
        return updated.turns.single.events.any(
          (event) =>
              event.type == StudioTurnEventType.approvalRequest &&
              event.approvalId == 'cmd' &&
              event.approvalState == ApprovalRequestState.pending,
        );
      });

      var updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.waitingForApproval);
      expect(updatedThread.turns.single.toolResults, isEmpty);
      expect(
        updatedThread.turns.single.events
            .singleWhere((event) => event.approvalId == 'cmd')
            .approvalWarnings,
        contains('Shell command requires review.'),
      );

      harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .rejectApproval('cmd');
      await runFuture;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        updatedThread.turns.single.events
            .singleWhere((event) => event.approvalId == 'cmd')
            .approvalState,
        ApprovalRequestState.rejected,
      );
      expect(
        updatedThread.turns.single.toolResults.where(
          (result) => result.toolName == 'run_command',
        ),
        isEmpty,
      );
    },
  );

  test(
    'AgentTurnRuntime rejects false-success summaries after failed commands',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'fail-cmd',
              toolCallName: 'run_command',
              toolCallArguments: '{"command":"false"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(content: 'All tests passed and everything is green.'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-verify-false-success';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'verify the project',
        intent: TurnIntent.verify,
      );

      final runFuture = harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'verify the project',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.verify,
            intent: TurnIntent.verify,
            model: 'gpt-5-nano',
            retryPrompt: 'verify the project',
            finishTask: false,
          );

      await _waitUntil(() {
        final updated = harness.thread(thread.id);
        return updated.turns.single.events.any(
          (event) =>
              event.type == StudioTurnEventType.approvalRequest &&
              event.approvalId == 'fail-cmd' &&
              event.approvalState == ApprovalRequestState.pending,
        );
      });
      harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .approveOnce('fail-cmd');
      await runFuture;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(updatedThread.turns.single.lastError, contains('claimed success'));
      final commandResult = updatedThread.turns.single.toolResults
          .where((result) => result.toolName == 'run_command')
          .single;
      expect(commandResult.status, ToolResultStatus.error);
      expect(commandResult.data['exitCode'], 1);
      expect(
        updatedThread.turns.single.events.where(
          (event) => event.type == StudioTurnEventType.assistantMessage,
        ),
        isEmpty,
      );
    },
  );

  test(
    'AgentTurnRuntime rejects false-success summaries after irrelevant commands',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'pwd-cmd',
              toolCallName: 'run_command',
              toolCallArguments: '{"command":"pwd"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(content: 'All tests passed and everything is green.'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-verify-irrelevant-command-false-success';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'verify the project',
        intent: TurnIntent.verify,
      );

      final runFuture = harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'verify the project',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.verify,
            intent: TurnIntent.verify,
            model: 'gpt-5-nano',
            retryPrompt: 'verify the project',
            finishTask: false,
          );

      await _waitUntil(() {
        final updated = harness.thread(thread.id);
        return updated.turns.single.events.any(
          (event) =>
              event.type == StudioTurnEventType.approvalRequest &&
              event.approvalId == 'pwd-cmd' &&
              event.approvalState == ApprovalRequestState.pending,
        );
      });
      harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .approveOnce('pwd-cmd');
      await runFuture;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(updatedThread.turns.single.lastError, contains('did not match'));
      final commandResult = updatedThread.turns.single.toolResults
          .where((result) => result.toolName == 'run_command')
          .single;
      expect(commandResult.status, ToolResultStatus.success);
      expect(commandResult.stdout, contains(harness.root.path));
      expect(
        updatedThread.turns.single.events.where(
          (event) => event.type == StudioTurnEventType.assistantMessage,
        ),
        isEmpty,
      );
    },
  );

  test(
    'AgentTurnRuntime rejects Verify summaries that claim mutation',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'cmd',
              toolCallName: 'run_command',
              toolCallArguments: '{"command":"pwd"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(
              content: 'I updated lib/main.dart and the checks passed.',
            ),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-verify-mutation-claim';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'verify the project',
        intent: TurnIntent.verify,
      );

      final runFuture = harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'verify the project',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.verify,
            intent: TurnIntent.verify,
            model: 'gpt-5-nano',
            retryPrompt: 'verify the project',
            finishTask: false,
          );

      await _waitUntil(() {
        final updated = harness.thread(thread.id);
        return updated.turns.single.events.any(
          (event) =>
              event.type == StudioTurnEventType.approvalRequest &&
              event.approvalId == 'cmd' &&
              event.approvalState == ApprovalRequestState.pending,
        );
      });
      harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .approveOnce('cmd');
      await runFuture;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        updatedThread.turns.single.lastError,
        contains('claimed files or changes were made'),
      );
      expect(
        updatedThread.turns.single.events.where(
          (event) => event.type == StudioTurnEventType.assistantMessage,
        ),
        isEmpty,
      );
    },
  );

  test(
    'AgentTurnRuntime approve-for-turn auto-approves later Verify commands',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'pwd',
              toolCallName: 'run_command',
              toolCallArguments: '{"command":"pwd"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'ls',
              toolCallName: 'run_command',
              toolCallArguments: '{"command":"ls"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(content: 'Verification commands completed.'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-verify-approve-turn';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'run pwd and ls',
        intent: TurnIntent.verify,
      );

      final runFuture = harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'run pwd and ls',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.verify,
            intent: TurnIntent.verify,
            model: 'gpt-5-nano',
            retryPrompt: 'run pwd and ls',
            finishTask: false,
          );

      await _waitUntil(() {
        final updated = harness.thread(thread.id);
        return updated.turns.single.events.any(
          (event) =>
              event.type == StudioTurnEventType.approvalRequest &&
              event.approvalId == 'pwd' &&
              event.approvalState == ApprovalRequestState.pending,
        );
      });

      harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .approveForTurn('pwd');
      await runFuture;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final turn = updatedThread.turns.single;
      expect(updatedThread.status, StudioThreadStatus.done);
      expect(turn.status, StudioTurnStatus.completed);
      expect(
        turn.events
            .singleWhere((event) => event.approvalId == 'pwd')
            .approvalState,
        ApprovalRequestState.approved,
      );
      expect(turn.events.where((event) => event.approvalId == 'ls'), isEmpty);
      expect(
        turn.toolResults
            .where((result) => result.toolName == 'run_command')
            .map((result) => result.toolCallId),
        containsAll(['pwd', 'ls']),
      );
      expect(
        turn.events
            .where(
              (event) => event.type == StudioTurnEventType.assistantMessage,
            )
            .single
            .content,
        'Verification commands completed.',
      );
    },
  );

  test(
    'AgentTurnRuntime typed approval ignores mixed user instructions',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'pwd',
              toolCallName: 'run_command',
              toolCallArguments: '{"command":"pwd"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'ls',
              toolCallName: 'run_command',
              toolCallArguments: '{"command":"ls"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(content: 'Verification commands completed.'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-verify-mixed-approval-text';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'run pwd and ls',
        intent: TurnIntent.verify,
      );

      final runFuture = harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'run pwd and ls',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.verify,
            intent: TurnIntent.verify,
            model: 'gpt-5-nano',
            retryPrompt: 'run pwd and ls',
            finishTask: false,
          );

      await _waitUntil(() {
        final updated = harness.thread(thread.id);
        return updated.turns.single.events.any(
          (event) =>
              event.type == StudioTurnEventType.approvalRequest &&
              event.approvalId == 'pwd' &&
              event.approvalState == ApprovalRequestState.pending,
        );
      });

      final runtime = harness.container.read(agentTurnRuntimeProvider.notifier);
      expect(
        runtime.handlePendingApprovalText(
          "approve for this turn but don't run tests",
        ),
        isFalse,
      );
      expect(
        runtime.handlePendingApprovalText('approve for this task'),
        isFalse,
      );
      expect(runtime.handlePendingApprovalText('approve all'), isFalse);
      expect(runtime.handlePendingApprovalText('approve everything'), isFalse);
      var turn = harness.thread(thread.id).turns.single;
      expect(
        turn.events
            .singleWhere((event) => event.approvalId == 'pwd')
            .approvalState,
        ApprovalRequestState.pending,
      );
      expect(turn.toolResults, isEmpty);

      expect(
        runtime.handlePendingApprovalText('approve for this turn'),
        isTrue,
      );
      await runFuture;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      turn = harness.thread(thread.id).turns.single;
      expect(turn.status, StudioTurnStatus.completed);
      expect(
        turn.events
            .singleWhere((event) => event.approvalId == 'pwd')
            .approvalState,
        ApprovalRequestState.approved,
      );
      expect(turn.events.where((event) => event.approvalId == 'ls'), isEmpty);
      expect(
        turn.toolResults
            .where((result) => result.toolName == 'run_command')
            .map((result) => result.toolCallId),
        containsAll(['pwd', 'ls']),
      );
    },
  );

  test(
    'AgentTurnRuntime typed approval ignores stale visible approval events',
    () async {
      final harness = await _RuntimeHarness.create();
      addTearDown(harness.dispose);
      const requestId = 'runtime-stale-visible-approval';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'run pwd',
        intent: TurnIntent.verify,
      );

      final request = ConfirmationRequest(
        id: 'stale-pwd',
        toolCall: const ToolCallInfo(
          id: 'stale-pwd',
          name: 'run_command',
          arguments: {'command': 'pwd'},
          requiresConfirmation: true,
        ),
        preview: 'Execute: pwd',
        warnings: const ['Shell command requires review.'],
      );
      harness.container
          .read(studioTurnProvider.notifier)
          .upsertApproval(requestId, request);

      var turn = harness.thread(thread.id).turns.single;
      expect(
        turn.events
            .singleWhere((event) => event.approvalId == 'stale-pwd')
            .approvalState,
        ApprovalRequestState.pending,
      );

      expect(
        harness.container
            .read(agentTurnRuntimeProvider.notifier)
            .handlePendingApprovalText('approve'),
        isFalse,
      );

      turn = harness.thread(thread.id).turns.single;
      expect(
        turn.events
            .singleWhere((event) => event.approvalId == 'stale-pwd')
            .approvalState,
        ApprovalRequestState.pending,
      );
    },
  );

  test(
    'AgentTurnRuntime typed approval targets active approval when concurrent turn is blocked',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'old-cmd',
              toolCallName: 'run_command',
              toolCallArguments: '{"command":"pwd"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(content: 'Original command completed.'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      final activeThread = harness.registerTurn(
        requestId: 'runtime-active-approval',
        prompt: 'run pwd',
        intent: TurnIntent.verify,
      );

      final activeFuture = harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: 'runtime-active-approval',
            threadId: activeThread.id,
            taskId: null,
            outboundText: 'run pwd',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.verify,
            intent: TurnIntent.verify,
            model: 'gpt-5-nano',
            retryPrompt: 'run pwd',
            finishTask: false,
          );

      await _waitUntil(() {
        final updated = harness.thread(activeThread.id);
        return updated.turns.any(
          (turn) => turn.events.any(
            (event) =>
                event.type == StudioTurnEventType.approvalRequest &&
                event.approvalId == 'old-cmd' &&
                event.approvalState == ApprovalRequestState.pending,
          ),
        );
      });

      harness.container.read(studioThreadProvider.notifier).selectThread(null);
      final blockedThread = harness.registerTurn(
        requestId: 'runtime-blocked-approval',
        prompt: 'run ls',
        intent: TurnIntent.verify,
      );
      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: 'runtime-blocked-approval',
            threadId: blockedThread.id,
            taskId: null,
            outboundText: 'run ls',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.verify,
            intent: TurnIntent.verify,
            model: 'gpt-5-nano',
            retryPrompt: 'run ls',
            finishTask: false,
          );

      expect(
        harness.thread(blockedThread.id).status,
        StudioThreadStatus.failed,
      );
      expect(
        harness.thread(blockedThread.id).turns.single.status,
        StudioTurnStatus.failed,
      );

      harness.container
          .read(studioThreadProvider.notifier)
          .selectThread(activeThread.id);
      final runtime = harness.container.read(agentTurnRuntimeProvider.notifier);
      expect(runtime.handlePendingApprovalText('approve'), isTrue);

      await _waitUntil(() {
        final updated = harness.thread(activeThread.id);
        return updated.turns.any(
          (turn) => turn.events.any(
            (event) =>
                event.approvalId == 'old-cmd' &&
                event.approvalState == ApprovalRequestState.approved,
          ),
        );
      });

      var thread = harness.thread(activeThread.id);
      final activeApproval = thread.turns
          .expand((turn) => turn.events)
          .singleWhere((event) => event.approvalId == 'old-cmd');
      expect(activeApproval.approvalState, ApprovalRequestState.approved);

      await activeFuture;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      thread = harness.thread(activeThread.id);
      expect(
        thread.turns
            .expand((turn) => turn.toolResults)
            .where((result) => result.toolName == 'run_command')
            .map((result) => result.toolCallId),
        ['old-cmd'],
      );
    },
  );

  test(
    'AgentTurnRuntime approve-for-turn cannot bypass destructive git commands',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'pwd',
              toolCallName: 'run_command',
              toolCallArguments: '{"command":"pwd"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'delete-branch',
              toolCallName: 'run_command',
              toolCallArguments: '{"command":"git branch -D old-feature"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-verify-turn-grant-dangerous-git';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'run pwd and then delete the branch',
        intent: TurnIntent.verify,
      );

      final runFuture = harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'run pwd and then delete the branch',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.verify,
            intent: TurnIntent.verify,
            model: 'gpt-5-nano',
            retryPrompt: 'run pwd and then delete the branch',
            finishTask: false,
          );

      await _waitUntil(() {
        final updated = harness.thread(thread.id);
        return updated.turns.single.events.any(
          (event) =>
              event.type == StudioTurnEventType.approvalRequest &&
              event.approvalId == 'pwd' &&
              event.approvalState == ApprovalRequestState.pending,
        );
      });

      harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .approveForTurn('pwd');
      await runFuture;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final turn = updatedThread.turns.single;
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(turn.status, StudioTurnStatus.failed);
      expect(turn.lastError, contains('Destructive shell commands'));
      expect(
        turn.events.where((event) => event.approvalId == 'delete-branch'),
        isEmpty,
      );
      final commandResultIds = turn.toolResults
          .where((result) => result.toolName == 'run_command')
          .map((result) => result.toolCallId);
      expect(commandResultIds, contains('pwd'));
      expect(commandResultIds, isNot(contains('delete-branch')));
      expect(
        harness.container.read(agentTurnRuntimeProvider).activeSessions,
        isEmpty,
      );
    },
  );

  test(
    'AgentTurnRuntime approve-once does not approve later Verify commands',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'pwd',
              toolCallName: 'run_command',
              toolCallArguments: '{"command":"pwd"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'ls',
              toolCallName: 'run_command',
              toolCallArguments: '{"command":"ls"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
          [
            ChatChunk(content: 'Verification commands completed.'),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-verify-approve-once';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'run pwd and ls',
        intent: TurnIntent.verify,
      );

      final runFuture = harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'run pwd and ls',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.verify,
            intent: TurnIntent.verify,
            model: 'gpt-5-nano',
            retryPrompt: 'run pwd and ls',
            finishTask: false,
          );

      await _waitUntil(() {
        final updated = harness.thread(thread.id);
        return updated.turns.single.events.any(
          (event) =>
              event.type == StudioTurnEventType.approvalRequest &&
              event.approvalId == 'pwd' &&
              event.approvalState == ApprovalRequestState.pending,
        );
      });

      harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .approveOnce('pwd');

      await _waitUntil(() {
        final updated = harness.thread(thread.id);
        return updated.turns.single.events.any(
          (event) =>
              event.type == StudioTurnEventType.approvalRequest &&
              event.approvalId == 'ls' &&
              event.approvalState == ApprovalRequestState.pending,
        );
      });

      var updatedThread = harness.thread(thread.id);
      var turn = updatedThread.turns.single;
      expect(updatedThread.status, StudioThreadStatus.waitingForApproval);
      expect(
        turn.events
            .singleWhere((event) => event.approvalId == 'pwd')
            .approvalState,
        ApprovalRequestState.approved,
      );
      expect(
        turn.events
            .singleWhere((event) => event.approvalId == 'ls')
            .approvalState,
        ApprovalRequestState.pending,
      );
      expect(
        turn.toolResults
            .where((result) => result.toolName == 'run_command')
            .map((result) => result.toolCallId),
        ['pwd'],
      );

      harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .approveOnce('ls');
      await runFuture;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      updatedThread = harness.thread(thread.id);
      turn = updatedThread.turns.single;
      expect(updatedThread.status, StudioThreadStatus.done);
      expect(turn.status, StudioTurnStatus.completed);
      expect(
        turn.events
            .singleWhere((event) => event.approvalId == 'ls')
            .approvalState,
        ApprovalRequestState.approved,
      );
      expect(
        turn.toolResults
            .where((result) => result.toolName == 'run_command')
            .map((result) => result.toolCallId),
        ['pwd', 'ls'],
      );
    },
  );

  test(
    'AgentTurnRuntime rejection fails Verify turn without running command',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'pwd',
              toolCallName: 'run_command',
              toolCallArguments: '{"command":"pwd"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-verify-reject-command';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'run pwd',
        intent: TurnIntent.verify,
      );

      final runFuture = harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'run pwd',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.verify,
            intent: TurnIntent.verify,
            model: 'gpt-5-nano',
            retryPrompt: 'run pwd',
            finishTask: false,
          );

      await _waitUntil(() {
        final updated = harness.thread(thread.id);
        return updated.turns.single.events.any(
          (event) =>
              event.type == StudioTurnEventType.approvalRequest &&
              event.approvalId == 'pwd' &&
              event.approvalState == ApprovalRequestState.pending,
        );
      });

      harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .rejectApproval('pwd');
      await runFuture;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final turn = updatedThread.turns.single;
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(turn.status, StudioTurnStatus.failed);
      expect(turn.lastError, contains('rejected'));
      expect(
        turn.events
            .singleWhere((event) => event.approvalId == 'pwd')
            .approvalState,
        ApprovalRequestState.rejected,
      );
      expect(
        turn.toolResults.where((result) => result.toolName == 'run_command'),
        isEmpty,
      );
      expect(
        harness.container.read(agentTurnRuntimeProvider).activeSessions,
        isEmpty,
      );
    },
  );

  test(
    'AgentTurnRuntime blocks dangerous Verify commands without approval',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'dangerous',
              toolCallName: 'run_command',
              toolCallArguments: '{"command":"rm -rf /"}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-verify-dangerous-command';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'run rm -rf /',
        intent: TurnIntent.verify,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'run rm -rf /',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.verify,
            intent: TurnIntent.verify,
            model: 'gpt-5-nano',
            retryPrompt: 'run rm -rf /',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final turn = updatedThread.turns.single;
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(turn.status, StudioTurnStatus.failed);
      expect(
        turn.lastError,
        contains('Destructive shell commands are blocked'),
      );
      expect(
        turn.events.where(
          (event) => event.type == StudioTurnEventType.approvalRequest,
        ),
        isEmpty,
      );
      expect(
        turn.toolResults.where((result) => result.toolName == 'run_command'),
        isEmpty,
      );
      expect(
        harness.container.read(agentTurnRuntimeProvider).activeSessions,
        isEmpty,
      );
    },
  );

  test('AgentTurnRuntime rejects thin plan proposals in plan mode', () async {
    final harness = await _RuntimeHarness.create(
      rounds: const [
        [
          ChatChunk(
            toolCallIndex: 0,
            toolCallId: 'patch',
            toolCallName: 'propose_patch',
            toolCallArguments:
                '{"title":"Thin plan","summary":"Too vague.","files":[]}',
          ),
          ChatChunk(finishReason: 'tool_calls', isDone: true),
        ],
        [
          ChatChunk(content: 'Plan ready.'),
          ChatChunk(finishReason: 'stop', isDone: true),
        ],
      ],
    );
    addTearDown(harness.dispose);
    const requestId = 'runtime-plan-thin';
    final thread = harness.registerTurn(
      requestId: requestId,
      prompt: 'make a plan',
      intent: TurnIntent.plan,
    );

    await harness.container
        .read(agentTurnRuntimeProvider.notifier)
        .startTurn(
          requestId: requestId,
          threadId: thread.id,
          taskId: null,
          outboundText: 'make a plan',
          attachments: const [],
          historyOverride: const <ChatMessage>[],
          toolMode: AgentToolMode.plan,
          intent: TurnIntent.plan,
          model: 'gpt-5-nano',
          retryPrompt: 'make a plan',
          finishTask: false,
        );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final updatedThread = harness.thread(thread.id);
    expect(updatedThread.status, StudioThreadStatus.failed);
    expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
    expect(
      updatedThread.turns.single.lastError,
      contains('reviewable plan card'),
    );
    expect(harness.container.read(patchProposalProvider).active, isNull);
  });

  test('AgentTurnRuntime rejects concrete edit proposals in plan mode', () async {
    final harness = await _RuntimeHarness.create(
      rounds: const [
        [
          ChatChunk(
            toolCallIndex: 0,
            toolCallId: 'patch',
            toolCallName: 'propose_patch',
            toolCallArguments:
                '{"title":"Concrete edit too early","summary":"This tries to skip plan acceptance.","plan_markdown":"# Plan\\n\\n- Create the route fix.\\n- Review the patch.\\n- Verify the behavior.","files":[{"path":"lib/router.dart","intent":"Fix redirect","operation":"modify","before":"void oldRedirect() {}\\n","content":"void fixRedirect() {}\\n"}]}',
          ),
          ChatChunk(finishReason: 'tool_calls', isDone: true),
        ],
        [
          ChatChunk(content: 'Plan ready.'),
          ChatChunk(finishReason: 'stop', isDone: true),
        ],
      ],
    );
    addTearDown(harness.dispose);
    const requestId = 'runtime-plan-concrete-edit';
    final thread = harness.registerTurn(
      requestId: requestId,
      prompt: 'make a plan',
      intent: TurnIntent.plan,
    );

    await harness.container
        .read(agentTurnRuntimeProvider.notifier)
        .startTurn(
          requestId: requestId,
          threadId: thread.id,
          taskId: null,
          outboundText: 'make a plan',
          attachments: const [],
          historyOverride: const <ChatMessage>[],
          toolMode: AgentToolMode.plan,
          intent: TurnIntent.plan,
          model: 'gpt-5-nano',
          retryPrompt: 'make a plan',
          finishTask: false,
        );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final updatedThread = harness.thread(thread.id);
    expect(updatedThread.status, StudioThreadStatus.failed);
    expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
    expect(updatedThread.turns.single.lastError, contains('plan-only'));
    expect(harness.container.read(patchProposalProvider).active, isNull);
  });

  test(
    'AgentTurnRuntime rejects plan cards that claim implementation happened',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(content: 'I implemented the plan and ran the tests.'),
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'patch',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Auth cleanup plan","summary":"Review and simplify the login error path.","plan_markdown":"Inspect the auth flow, identify the smallest login error-path patch, then propose app-reviewable file edits and verification steps.","files":[{"path":"lib/auth.dart","intent":"Review login handling"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-plan-false-completion';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'make a plan',
        intent: TurnIntent.plan,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'make a plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.plan,
            intent: TurnIntent.plan,
            model: 'gpt-5-nano',
            retryPrompt: 'make a plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        updatedThread.turns.single.lastError,
        contains('claimed changes were applied'),
      );
    },
  );

  test(
    'AgentTurnRuntime keeps advisory topology diagrams in chat without patch tools',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              content:
                  'Here is the topology in chat:\n\n```mermaid\ngraph LR\n  HQ[HQ] --> WAN[Dual WAN]\n```\n\nAssumptions: placeholder links.',
            ),
            ChatChunk(finishReason: 'stop', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const prompt = 'create a topology diagram for 3 branches and dual WAN';
      final intent = IntentClassifier.classify(
        prompt,
        promptMode: StudioPromptMode.code,
        planModeEnabled: false,
      );
      final toolMode = studioToolModeForIntent(
        intent: intent,
        promptMode: StudioPromptMode.code,
        hasWorkspace: true,
        planModeEnabled: false,
      );
      final outboundText = studioOutboundPromptForIntent(
        text: prompt,
        intent: intent,
        planModeEnabled: false,
      );
      const requestId = 'runtime-advisory-topology';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: prompt,
        intent: intent,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: outboundText,
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: toolMode,
            intent: intent,
            model: 'gpt-5-nano',
            retryPrompt: prompt,
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(intent, TurnIntent.ask);
      expect(outboundText, contains('Produce the answer directly in chat'));
      expect(harness.scriptedProvider!.exposedTools, hasLength(1));
      expect(
        harness.scriptedProvider!.exposedTools.single,
        contains('read_file'),
      );
      expect(
        harness.scriptedProvider!.exposedTools.single,
        isNot(contains('propose_patch')),
      );
      expect(
        harness.scriptedProvider!.exposedTools.single,
        isNot(contains('run_command')),
      );
      final updatedThread = harness.thread(thread.id);
      final turn = updatedThread.turns.single;
      expect(updatedThread.status, StudioThreadStatus.done);
      expect(turn.status, StudioTurnStatus.completed);
      expect(
        turn.events
            .where(
              (event) => event.type == StudioTurnEventType.assistantMessage,
            )
            .single
            .content,
        contains('```mermaid'),
      );
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test(
    'AgentTurnRuntime routes explicit topology file output to plan-only patch review',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'topology-plan',
              toolCallName: 'propose_patch',
              toolCallArguments:
                  '{"title":"Topology diagram plan","summary":"Create a Markdown topology artifact for review.","plan_markdown":"# Plan\\n\\n## Assumptions\\n- Three branches use dual WAN.\\n\\n## Steps\\n- Create docs/topology.md with a Mermaid diagram.\\n\\n## Verification\\n- Review the rendered Mermaid diagram.","files":[{"path":"docs/topology.md","intent":"Create topology Markdown diagram","operation":"create"}],"assumptions":["Three branches use dual WAN."],"verification_steps":["Review the Mermaid diagram."]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const prompt = 'create docs/topology.md with a topology diagram';
      final intent = IntentClassifier.classify(
        prompt,
        promptMode: StudioPromptMode.code,
        planModeEnabled: false,
      );
      final toolMode = studioToolModeForIntent(
        intent: intent,
        promptMode: StudioPromptMode.code,
        hasWorkspace: true,
        planModeEnabled: false,
      );
      final outboundText = studioOutboundPromptForIntent(
        text: prompt,
        intent: intent,
        planModeEnabled: false,
      );
      const requestId = 'runtime-topology-file-plan';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: prompt,
        intent: intent,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: outboundText,
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: toolMode,
            intent: intent,
            model: 'gpt-5-nano',
            retryPrompt: prompt,
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(intent, TurnIntent.plan);
      expect(outboundText, contains('Plan Mode is enabled'));
      expect(harness.scriptedProvider!.exposedTools, hasLength(1));
      expect(
        harness.scriptedProvider!.exposedTools.single,
        contains('propose_patch'),
      );
      expect(
        harness.scriptedProvider!.exposedTools.single,
        isNot(contains('run_command')),
      );
      final updatedThread = harness.thread(thread.id);
      final turn = updatedThread.turns.single;
      expect(updatedThread.status, StudioThreadStatus.done);
      expect(turn.status, StudioTurnStatus.completed);
      final patch = harness.container.read(patchProposalProvider).active;
      expect(patch, isNotNull);
      expect(patch!.isPlanOnly, isTrue);
      expect(patch.plannedTargets.single.path, 'docs/topology.md');
      expect(patch.edits, isEmpty);
      expect(
        File(p.join(harness.root.path, 'docs', 'topology.md')).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'AgentTurnRuntime records no-first-byte when provider throws before bytes',
    () async {
      final harness = await _RuntimeHarness.create(
        provider: const _ThrowingProvider('socket closed before headers'),
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-provider-throw';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Add a file.',
              markdown: '- Create file.txt',
              plannedFiles: ['file.txt'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(
        updatedThread.turns.single.acceptedPlanState,
        AcceptedPlanState.failed,
      );
      expect(updatedThread.turns.single.lastError, contains('socket closed'));
      expect(
        updatedThread.turns.single.providerDiagnostics.map(
          (event) => event.kind,
        ),
        contains(ProviderLifecycleEventKind.noFirstByte),
      );
      expect(
        updatedThread.turns.single.providerDiagnostics.map(
          (event) => event.kind,
        ),
        contains(ProviderLifecycleEventKind.failed),
      );
    },
  );

  test(
    'AgentTurnRuntime fails provider streams that close without done marker',
    () async {
      final harness = await _RuntimeHarness.create(
        provider: const _ProviderStreamEndsWithoutDone(),
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-provider-early-close';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'hello',
        intent: TurnIntent.chat,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'hello',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.chat,
            intent: TurnIntent.chat,
            model: 'gpt-5-nano',
            retryPrompt: 'hello',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final turn = updatedThread.turns.single;
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(turn.status, StudioTurnStatus.failed);
      expect(turn.lastError, contains('Stream ended early'));
      expect(turn.lastError, contains('without the [DONE] terminator'));
      expect(
        turn.events
            .where((event) => event.type == StudioTurnEventType.error)
            .single
            .detail,
        contains('Stream ended early'),
      );
      expect(
        turn.providerDiagnostics.map((event) => event.kind),
        contains(ProviderLifecycleEventKind.streamEndedWithoutDone),
      );
      expect(
        turn.providerDiagnostics.map((event) => event.kind),
        contains(ProviderLifecycleEventKind.failed),
      );
      expect(
        turn.events.where(
          (event) => event.type == StudioTurnEventType.assistantMessage,
        ),
        isEmpty,
      );
    },
  );

  test(
    'AgentTurnRuntime fails provider streams that error after partial text',
    () async {
      final harness = await _RuntimeHarness.create(
        provider: const _ProviderErrorAfterPartialText(),
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-provider-error-after-partial-text';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'hello',
        intent: TurnIntent.chat,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'hello',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.chat,
            intent: TurnIntent.chat,
            model: 'gpt-5-nano',
            retryPrompt: 'hello',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final turn = updatedThread.turns.single;
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(turn.status, StudioTurnStatus.failed);
      expect(turn.lastError, contains('SSE error event'));
      expect(
        turn.providerDiagnostics.map((event) => event.kind),
        contains(ProviderLifecycleEventKind.firstByte),
      );
      expect(
        turn.providerDiagnostics.map((event) => event.kind),
        contains(ProviderLifecycleEventKind.firstTextDelta),
      );
      expect(
        turn.providerDiagnostics.map((event) => event.kind),
        contains(ProviderLifecycleEventKind.failed),
      );
      expect(
        turn.providerDiagnostics.map((event) => event.kind),
        isNot(contains(ProviderLifecycleEventKind.completed)),
      );
      expect(
        turn.events.where(
          (event) => event.type == StudioTurnEventType.assistantMessage,
        ),
        isEmpty,
      );
    },
  );

  test(
    'AgentTurnRuntime preserves provider authentication diagnostics',
    () async {
      final harness = await _RuntimeHarness.create(
        provider: const _ProviderAuthFails(),
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-provider-auth-failed';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Add a file.',
              markdown: '- Create file.txt',
              plannedFiles: ['file.txt'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final diagnostics = updatedThread.turns.single.providerDiagnostics.map(
        (event) => event.kind,
      );
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        updatedThread.turns.single.lastError,
        contains('Circuit authentication failed'),
      );
      expect(diagnostics, contains(ProviderLifecycleEventKind.authFailed));
      expect(diagnostics, contains(ProviderLifecycleEventKind.failed));
      expect(
        diagnostics,
        isNot(contains(ProviderLifecycleEventKind.connected)),
      );
    },
  );

  test(
    'AgentTurnRuntime preserves provider timeout without extra no-first-byte',
    () async {
      final harness = await _RuntimeHarness.create(
        provider: const _ProviderTimesOutThenThrows(),
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-provider-timeout';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Add a file.',
              markdown: '- Create file.txt',
              plannedFiles: ['file.txt'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final diagnostics = updatedThread.turns.single.providerDiagnostics.map(
        (event) => event.kind,
      );
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        updatedThread.turns.single.lastError,
        contains('Provider timed out'),
      );
      expect(updatedThread.turns.single.lastError, contains('timed out'));
      expect(diagnostics, contains(ProviderLifecycleEventKind.timeout));
      expect(
        diagnostics,
        isNot(contains(ProviderLifecycleEventKind.noFirstByte)),
      );
      expect(diagnostics, contains(ProviderLifecycleEventKind.failed));
    },
  );

  test(
    'AgentTurnRuntime rejects unavailable tool calls before execution',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'apply',
              toolCallName: 'apply_patch_set',
              toolCallArguments:
                  '{"files":[{"path":"hello.txt","operation":"create","content":"should not write\\n"}]}',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-unavailable-tool';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Add a file.',
              markdown: '- Create hello.txt',
              plannedFiles: ['hello.txt'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        updatedThread.turns.single.acceptedPlanState,
        AcceptedPlanState.failed,
      );
      expect(
        updatedThread.turns.single.lastError,
        contains('unavailable tool'),
      );
      expect(
        updatedThread.turns.single.providerDiagnostics.map(
          (event) => event.kind,
        ),
        contains(ProviderLifecycleEventKind.unavailableTool),
      );
      expect(
        File(p.join(harness.root.path, 'hello.txt')).existsSync(),
        isFalse,
      );
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test(
    'AgentTurnRuntime rejects malformed tool arguments before execution',
    () async {
      final harness = await _RuntimeHarness.create(
        rounds: const [
          [
            ChatChunk(
              toolCallIndex: 0,
              toolCallId: 'patch',
              toolCallName: 'propose_patch',
              toolCallArguments: '{"title":',
            ),
            ChatChunk(finishReason: 'tool_calls', isDone: true),
          ],
        ],
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-malformed-tool-args';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Add a file.',
              markdown: '- Create file.txt',
              plannedFiles: ['file.txt'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final diagnostics = updatedThread.turns.single.providerDiagnostics.map(
        (event) => event.kind,
      );
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(updatedThread.turns.single.lastError, contains('malformed tool'));
      expect(diagnostics, contains(ProviderLifecycleEventKind.malformedChunk));
      expect(harness.container.read(patchProposalProvider).active, isNull);
    },
  );

  test(
    'AgentTurnRuntime fails provider streams that error during partial tool calls',
    () async {
      final harness = await _RuntimeHarness.create(
        provider: const _ProviderErrorDuringPartialToolCall(),
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-provider-error-during-partial-tool';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Add a file.',
              markdown: '- Create file.txt',
              plannedFiles: ['file.txt'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updatedThread = harness.thread(thread.id);
      final turn = updatedThread.turns.single;
      final diagnostics = turn.providerDiagnostics.map((event) => event.kind);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(turn.status, StudioTurnStatus.failed);
      expect(turn.acceptedPlanState, AcceptedPlanState.failed);
      expect(turn.lastError, contains('tool stream failed'));
      expect(diagnostics, contains(ProviderLifecycleEventKind.firstByte));
      expect(diagnostics, contains(ProviderLifecycleEventKind.firstToolDelta));
      expect(diagnostics, contains(ProviderLifecycleEventKind.failed));
      expect(
        diagnostics,
        isNot(contains(ProviderLifecycleEventKind.completed)),
      );
      expect(
        turn.events.where(
          (event) => event.type == StudioTurnEventType.approvalRequest,
        ),
        isEmpty,
      );
      expect(
        turn.toolResults.where((result) => result.toolName == 'propose_patch'),
        isEmpty,
      );
      expect(harness.container.read(patchProposalProvider).active, isNull);
      expect(File(p.join(harness.root.path, 'file.txt')).existsSync(), isFalse);
    },
  );

  test(
    'AgentTurnRuntime rejects concurrent startTurn calls at runtime',
    () async {
      final provider = _CancellableProvider();
      final harness = await _RuntimeHarness.create(provider: provider);
      addTearDown(harness.dispose);
      const firstRequestId = 'runtime-concurrent-first';
      final firstThread = harness.registerTurn(
        requestId: firstRequestId,
        prompt: 'keep running',
        intent: TurnIntent.chat,
      );

      final firstFuture = harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: firstRequestId,
            threadId: firstThread.id,
            taskId: null,
            outboundText: 'keep running',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.chat,
            intent: TurnIntent.chat,
            model: 'gpt-5-nano',
            retryPrompt: 'keep running',
            finishTask: false,
          );
      await provider.started.future.timeout(const Duration(seconds: 1));
      expect(
        harness.container.read(agentTurnRuntimeProvider).activeSessions.keys,
        contains(firstRequestId),
      );

      harness.container.read(studioThreadProvider.notifier).selectThread(null);
      const secondRequestId = 'runtime-concurrent-second';
      final secondThread = harness.registerTurn(
        requestId: secondRequestId,
        prompt: 'second request',
        intent: TurnIntent.chat,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: secondRequestId,
            threadId: secondThread.id,
            taskId: null,
            outboundText: 'second request',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.chat,
            intent: TurnIntent.chat,
            model: 'gpt-5-nano',
            retryPrompt: 'second request',
            finishTask: false,
          );

      final activeRequestIds = harness.container
          .read(agentTurnRuntimeProvider)
          .activeSessions
          .keys;
      expect(activeRequestIds, contains(firstRequestId));
      expect(activeRequestIds, isNot(contains(secondRequestId)));

      final blockedThread = harness.thread(secondThread.id);
      expect(blockedThread.status, StudioThreadStatus.failed);
      expect(blockedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        blockedThread.turns.single.lastError,
        contains('request is already running'),
      );
      expect(
        harness.thread(firstThread.id).status,
        isNot(StudioThreadStatus.failed),
      );

      harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .cancel(firstRequestId);
      await firstFuture;
    },
  );

  test(
    'AgentTurnRuntime cancellation closes turn, lane, run, and diagnostics',
    () async {
      final provider = _CancellableProvider();
      final harness = await _RuntimeHarness.create(provider: provider);
      addTearDown(harness.dispose);
      const requestId = 'runtime-cancel';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      final runFuture = harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Add a file.',
              markdown: '- Create file.txt',
              plannedFiles: ['file.txt'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await provider.started.future;

      harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .cancel(requestId);
      await runFuture;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        harness.container.read(agentTurnRuntimeProvider).activeSessions,
        isEmpty,
      );
      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.cancelled);
      expect(updatedThread.turns.single.status, StudioTurnStatus.cancelled);
      expect(
        updatedThread.turns.single.providerDiagnostics.map(
          (event) => event.kind,
        ),
        contains(ProviderLifecycleEventKind.cancelled),
      );
      expect(
        updatedThread.turns.single.providerDiagnostics.map(
          (event) => event.kind,
        ),
        isNot(contains(ProviderLifecycleEventKind.failed)),
      );
      expect(
        harness.container
            .read(agentRequestProvider)[AgentRequestLane.chat]
            ?.status,
        AgentRequestStatus.done,
      );
      expect(
        harness.container
            .read(agentRequestProvider)[AgentRequestLane.chat]
            ?.cancelRequested,
        isTrue,
      );
      final recentRun = harness.container
          .read(agentRunProvider)
          .recentRuns
          .firstWhere((run) => run.id == requestId);
      expect(recentRun.status, AgentRunStatus.cancelled);
      expect(recentRun.cancelRequested, isTrue);
    },
  );

  test(
    'AgentTurnRuntime treats provider cancellation throws as cancelled',
    () async {
      final harness = await _RuntimeHarness.create(
        provider: const _ProviderCancelsThenThrows(),
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-provider-cancel-throw';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Add a file.',
              markdown: '- Create file.txt',
              plannedFiles: ['file.txt'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        harness.container.read(agentTurnRuntimeProvider).activeSessions,
        isEmpty,
      );
      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.cancelled);
      expect(updatedThread.turns.single.status, StudioTurnStatus.cancelled);
      expect(
        updatedThread.turns.single.providerDiagnostics.map(
          (event) => event.kind,
        ),
        contains(ProviderLifecycleEventKind.cancelled),
      );
      expect(
        updatedThread.turns.single.providerDiagnostics.map(
          (event) => event.kind,
        ),
        isNot(contains(ProviderLifecycleEventKind.failed)),
      );
      final recentRun = harness.container
          .read(agentRunProvider)
          .recentRuns
          .firstWhere((run) => run.id == requestId);
      expect(recentRun.status, AgentRunStatus.cancelled);
    },
  );

  test(
    'AgentTurnRuntime timeout closes turn, lane, run, and diagnostics',
    () async {
      final provider = _CancellableProvider();
      final harness = await _RuntimeHarness.create(
        provider: provider,
        turnTimeout: const Duration(milliseconds: 30),
      );
      addTearDown(harness.dispose);
      const requestId = 'runtime-timeout';
      final thread = harness.registerTurn(
        requestId: requestId,
        prompt: 'Implement this plan',
        acceptedPlanState: AcceptedPlanState.accepted,
      );

      await harness.container
          .read(agentTurnRuntimeProvider.notifier)
          .startTurn(
            requestId: requestId,
            threadId: thread.id,
            taskId: null,
            outboundText: 'Implement this plan',
            attachments: const [],
            historyOverride: const <ChatMessage>[],
            toolMode: AgentToolMode.code,
            intent: TurnIntent.code,
            acceptedPlan: const AcceptedPlanContext(
              patchSetId: 'plan',
              title: 'Accepted plan',
              summary: 'Add a file.',
              markdown: '- Create file.txt',
              plannedFiles: ['file.txt'],
            ),
            model: 'gpt-5-nano',
            retryPrompt: 'Implement this plan',
            finishTask: false,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        harness.container.read(agentTurnRuntimeProvider).activeSessions,
        isEmpty,
      );
      final updatedThread = harness.thread(thread.id);
      expect(updatedThread.status, StudioThreadStatus.failed);
      expect(updatedThread.turns.single.status, StudioTurnStatus.failed);
      expect(
        updatedThread.turns.single.acceptedPlanState,
        AcceptedPlanState.failed,
      );
      expect(updatedThread.turns.single.lastError, contains('timed out'));
      expect(
        updatedThread.turns.single.providerDiagnostics.map(
          (event) => event.kind,
        ),
        contains(ProviderLifecycleEventKind.timeout),
      );
      expect(
        harness.container
            .read(agentRequestProvider)[AgentRequestLane.chat]
            ?.status,
        AgentRequestStatus.failed,
      );
      final recentRun = harness.container
          .read(agentRunProvider)
          .recentRuns
          .firstWhere((run) => run.id == requestId);
      expect(recentRun.status, AgentRunStatus.failed);
      expect(recentRun.error, contains('timed out'));
    },
  );
}

class _RuntimeHarness {
  final Directory root;
  final AgentService service;
  final AIProvider provider;
  final ProviderContainer container;

  _RuntimeHarness._({
    required this.root,
    required this.service,
    required this.provider,
    required this.container,
  });

  static Future<_RuntimeHarness> create({
    List<List<ChatChunk>>? rounds,
    AIProvider? provider,
    Duration? turnTimeout,
  }) async {
    final root = await Directory.systemTemp.createTemp('studio_runtime_');
    final service = AgentService();
    final effectiveProvider = provider ?? _ScriptedProvider(rounds ?? const []);
    final environment = StudioAgentEnvironment(
      provider: effectiveProvider,
      model: 'gpt-5-nano',
      workspaceRoot: root.path,
      permissionPolicy: AgentToolPermissionPolicy(workingDir: root.path),
      events: service.events,
      onProviderEvent: (event) {
        service.events.emit(EventType.providerLifecycle, {
          'event': event,
          'requestId': event.requestId,
        });
      },
    );
    final container = ProviderContainer(
      overrides: [
        agentServiceProvider.overrideWithValue(service),
        studioAgentEnvironmentOverrideProvider.overrideWithValue(environment),
        if (turnTimeout != null)
          studioTurnTimeoutProvider.overrideWithValue(turnTimeout),
      ],
    );
    await _waitForThreadStore(container);
    await container.read(fileTreeProvider.notifier).openDirectory(root.path);
    return _RuntimeHarness._(
      root: root,
      service: service,
      provider: effectiveProvider,
      container: container,
    );
  }

  _ScriptedProvider? get scriptedProvider =>
      provider is _ScriptedProvider ? provider as _ScriptedProvider : null;

  StudioThread registerTurn({
    required String requestId,
    required String prompt,
    AcceptedPlanState acceptedPlanState = AcceptedPlanState.none,
    TurnIntent intent = TurnIntent.code,
  }) {
    final thread = container
        .read(studioThreadProvider.notifier)
        .ensureThread(title: 'Runtime flow', model: 'gpt-5-nano');
    container
        .read(studioTurnProvider.notifier)
        .registerTurn(
          requestId: requestId,
          threadId: thread.id,
          taskId: null,
          userMessageId: 'user-$requestId',
          prompt: prompt,
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(
            projectLabel: 'runtime',
            rootPath: '/tmp/runtime',
          ),
          intent: intent,
          acceptedPlanState: acceptedPlanState,
        );
    container
        .read(studioRequestLifecycleProvider.notifier)
        .registerRequest(
          requestId: requestId,
          threadId: thread.id,
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(
            projectLabel: 'runtime',
            rootPath: '/tmp/runtime',
          ),
        );
    return thread;
  }

  StudioThread thread(String id) {
    return container
        .read(studioThreadProvider)
        .threads
        .firstWhere((candidate) => candidate.id == id);
  }

  Future<void> dispose() async {
    container.dispose();
    service.dispose();
    await _delete(root);
  }
}

class _ScriptedProvider implements AIProvider {
  final List<List<ChatChunk>> rounds;
  final List<List<String>> exposedTools = [];
  var _index = 0;

  _ScriptedProvider(this.rounds);

  @override
  List<ModelInfo> get availableModels => const [
    ModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano', contextWindow: 1000),
  ];

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities();

  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
    id: 'scripted',
    displayName: 'Scripted',
    shortName: 'scripted',
  );

  @override
  bool get isConnected => true;

  @override
  String get name => 'scripted';

  @override
  Stream<ChatChunk> chat(
    List<ChatMessage> messages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async* {
    exposedTools.add(tools.map((tool) => tool.name).toList());
    final round = _index < rounds.length
        ? rounds[_index++]
        : const <ChatChunk>[];
    for (final chunk in round) {
      yield chunk;
    }
  }

  @override
  Future<void> connect(Map<String, String> credentials) async {}

  @override
  void cancelActiveRequest() {}

  @override
  Future<ConnectorHealth> checkHealth() async => ConnectorHealth(
    status: ConnectorHealthStatus.connected,
    message: 'Connected',
    checkedAt: DateTime.now(),
  );

  @override
  void disconnect() {}

  @override
  Future<List<ConnectorModelInfo>> refreshModels() async => const [
    ConnectorModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano'),
  ];
}

class _ThrowingProvider implements AIProvider {
  final String message;

  const _ThrowingProvider(this.message);

  @override
  List<ModelInfo> get availableModels => const [
    ModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano', contextWindow: 1000),
  ];

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities();

  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
    id: 'throwing',
    displayName: 'Throwing',
    shortName: 'throwing',
  );

  @override
  bool get isConnected => true;

  @override
  String get name => 'throwing';

  @override
  Stream<ChatChunk> chat(
    List<ChatMessage> messages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async* {
    throw Exception(message);
  }

  @override
  Future<void> connect(Map<String, String> credentials) async {}

  @override
  void cancelActiveRequest() {}

  @override
  Future<ConnectorHealth> checkHealth() async => ConnectorHealth(
    status: ConnectorHealthStatus.connected,
    message: 'Connected',
    checkedAt: DateTime.now(),
  );

  @override
  void disconnect() {}

  @override
  Future<List<ConnectorModelInfo>> refreshModels() async => const [
    ConnectorModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano'),
  ];
}

class _ProviderStreamEndsWithoutDone implements AIProvider {
  const _ProviderStreamEndsWithoutDone();

  @override
  List<ModelInfo> get availableModels => const [
    ModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano', contextWindow: 1000),
  ];

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities();

  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
    id: 'provider-early-close',
    displayName: 'Provider Early Close',
    shortName: 'earlyclose',
  );

  @override
  bool get isConnected => true;

  @override
  String get name => 'provider-early-close';

  @override
  Stream<ChatChunk> chat(
    List<ChatMessage> messages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async* {
    yield const ChatChunk(lifecycleKind: ProviderLifecycleEventKind.firstByte);
    yield const ChatChunk(content: 'Partial response');
    yield const ChatChunk(
      lifecycleKind: ProviderLifecycleEventKind.streamEndedWithoutDone,
      lifecycleDetail:
          'Circuit SSE stream ended without the [DONE] terminator.',
    );
    yield const ChatChunk(
      lifecycleKind: ProviderLifecycleEventKind.failed,
      lifecycleDetail:
          'Circuit SSE stream ended without the [DONE] terminator.',
    );
    throw Exception('Circuit SSE stream ended without the [DONE] terminator.');
  }

  @override
  Future<void> connect(Map<String, String> credentials) async {}

  @override
  void cancelActiveRequest() {}

  @override
  Future<ConnectorHealth> checkHealth() async => ConnectorHealth(
    status: ConnectorHealthStatus.connected,
    message: 'Connected',
    checkedAt: DateTime.now(),
  );

  @override
  void disconnect() {}

  @override
  Future<List<ConnectorModelInfo>> refreshModels() async => const [
    ConnectorModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano'),
  ];
}

class _ProviderErrorAfterPartialText implements AIProvider {
  const _ProviderErrorAfterPartialText();

  @override
  List<ModelInfo> get availableModels => const [
    ModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano', contextWindow: 1000),
  ];

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities();

  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
    id: 'provider-error-after-partial',
    displayName: 'Provider Error After Partial',
    shortName: 'partialerror',
  );

  @override
  bool get isConnected => true;

  @override
  String get name => 'provider-error-after-partial';

  @override
  Stream<ChatChunk> chat(
    List<ChatMessage> messages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async* {
    const detail =
        'Circuit SSE error event: connector failed after partial text';
    yield const ChatChunk(lifecycleKind: ProviderLifecycleEventKind.firstByte);
    yield const ChatChunk(content: 'Partial response');
    yield const ChatChunk(
      lifecycleKind: ProviderLifecycleEventKind.failed,
      lifecycleDetail: detail,
    );
    throw Exception(detail);
  }

  @override
  Future<void> connect(Map<String, String> credentials) async {}

  @override
  void cancelActiveRequest() {}

  @override
  Future<ConnectorHealth> checkHealth() async => ConnectorHealth(
    status: ConnectorHealthStatus.connected,
    message: 'Connected',
    checkedAt: DateTime.now(),
  );

  @override
  void disconnect() {}

  @override
  Future<List<ConnectorModelInfo>> refreshModels() async => const [
    ConnectorModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano'),
  ];
}

class _ProviderErrorDuringPartialToolCall implements AIProvider {
  const _ProviderErrorDuringPartialToolCall();

  @override
  List<ModelInfo> get availableModels => const [
    ModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano', contextWindow: 1000),
  ];

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities();

  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
    id: 'provider-error-during-tool',
    displayName: 'Provider Error During Tool',
    shortName: 'toolerror',
  );

  @override
  bool get isConnected => true;

  @override
  String get name => 'provider-error-during-tool';

  @override
  Stream<ChatChunk> chat(
    List<ChatMessage> messages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async* {
    const detail = 'Circuit SSE error event: tool stream failed';
    yield const ChatChunk(lifecycleKind: ProviderLifecycleEventKind.firstByte);
    yield const ChatChunk(
      lifecycleKind: ProviderLifecycleEventKind.firstToolDelta,
    );
    yield const ChatChunk(
      toolCallIndex: 0,
      toolCallId: 'patch',
      toolCallName: 'propose_patch',
      toolCallArguments: '{"title":',
    );
    yield const ChatChunk(
      lifecycleKind: ProviderLifecycleEventKind.failed,
      lifecycleDetail: detail,
    );
    throw Exception(detail);
  }

  @override
  Future<void> connect(Map<String, String> credentials) async {}

  @override
  void cancelActiveRequest() {}

  @override
  Future<ConnectorHealth> checkHealth() async => ConnectorHealth(
    status: ConnectorHealthStatus.connected,
    message: 'Connected',
    checkedAt: DateTime.now(),
  );

  @override
  void disconnect() {}

  @override
  Future<List<ConnectorModelInfo>> refreshModels() async => const [
    ConnectorModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano'),
  ];
}

class _ProviderAuthFails implements AIProvider {
  const _ProviderAuthFails();

  @override
  List<ModelInfo> get availableModels => const [
    ModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano', contextWindow: 1000),
  ];

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities();

  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
    id: 'provider-auth-fails',
    displayName: 'Provider Auth Fails',
    shortName: 'authfail',
  );

  @override
  bool get isConnected => true;

  @override
  String get name => 'provider-auth-fails';

  @override
  Stream<ChatChunk> chat(
    List<ChatMessage> messages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async* {
    yield const ChatChunk(
      lifecycleKind: ProviderLifecycleEventKind.authFailed,
      lifecycleDetail:
          'Circuit authentication failed: credentials are missing.',
    );
    yield const ChatChunk(
      lifecycleKind: ProviderLifecycleEventKind.failed,
      lifecycleDetail:
          'Circuit authentication failed: credentials are missing.',
    );
    throw Exception('Circuit authentication failed: credentials are missing.');
  }

  @override
  Future<void> connect(Map<String, String> credentials) async {}

  @override
  void cancelActiveRequest() {}

  @override
  Future<ConnectorHealth> checkHealth() async => ConnectorHealth(
    status: ConnectorHealthStatus.tokenFailed,
    message: 'Credentials missing',
    checkedAt: DateTime.now(),
  );

  @override
  void disconnect() {}

  @override
  Future<List<ConnectorModelInfo>> refreshModels() async => const [
    ConnectorModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano'),
  ];
}

class _CancellableProvider implements AIProvider {
  final Completer<void> started = Completer<void>();
  final Completer<void> _cancelled = Completer<void>();

  @override
  List<ModelInfo> get availableModels => const [
    ModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano', contextWindow: 1000),
  ];

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities();

  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
    id: 'cancellable',
    displayName: 'Cancellable',
    shortName: 'cancel',
  );

  @override
  bool get isConnected => true;

  @override
  String get name => 'cancellable';

  @override
  Stream<ChatChunk> chat(
    List<ChatMessage> messages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async* {
    if (!started.isCompleted) started.complete();
    yield const ChatChunk(lifecycleKind: ProviderLifecycleEventKind.firstByte);
    await _cancelled.future;
  }

  @override
  Future<void> connect(Map<String, String> credentials) async {}

  @override
  void cancelActiveRequest() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }

  @override
  Future<ConnectorHealth> checkHealth() async => ConnectorHealth(
    status: ConnectorHealthStatus.connected,
    message: 'Connected',
    checkedAt: DateTime.now(),
  );

  @override
  void disconnect() {}

  @override
  Future<List<ConnectorModelInfo>> refreshModels() async => const [
    ConnectorModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano'),
  ];
}

class _ProviderCancelsThenThrows implements AIProvider {
  const _ProviderCancelsThenThrows();

  @override
  List<ModelInfo> get availableModels => const [
    ModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano', contextWindow: 1000),
  ];

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities();

  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
    id: 'provider-cancels',
    displayName: 'Provider Cancels',
    shortName: 'cancelthrow',
  );

  @override
  bool get isConnected => true;

  @override
  String get name => 'provider-cancels';

  @override
  Stream<ChatChunk> chat(
    List<ChatMessage> messages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async* {
    yield const ChatChunk(lifecycleKind: ProviderLifecycleEventKind.firstByte);
    yield const ChatChunk(
      lifecycleKind: ProviderLifecycleEventKind.cancelled,
      lifecycleDetail: 'Provider cancelled the request.',
    );
    throw Exception('Request cancelled');
  }

  @override
  Future<void> connect(Map<String, String> credentials) async {}

  @override
  void cancelActiveRequest() {}

  @override
  Future<ConnectorHealth> checkHealth() async => ConnectorHealth(
    status: ConnectorHealthStatus.connected,
    message: 'Connected',
    checkedAt: DateTime.now(),
  );

  @override
  void disconnect() {}

  @override
  Future<List<ConnectorModelInfo>> refreshModels() async => const [
    ConnectorModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano'),
  ];
}

class _ProviderTimesOutThenThrows implements AIProvider {
  const _ProviderTimesOutThenThrows();

  @override
  List<ModelInfo> get availableModels => const [
    ModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano', contextWindow: 1000),
  ];

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities();

  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
    id: 'provider-timeout',
    displayName: 'Provider Timeout',
    shortName: 'timeout',
  );

  @override
  bool get isConnected => true;

  @override
  String get name => 'provider-timeout';

  @override
  Stream<ChatChunk> chat(
    List<ChatMessage> messages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async* {
    yield const ChatChunk(
      lifecycleKind: ProviderLifecycleEventKind.timeout,
      lifecycleDetail: 'Circuit API request timed out.',
    );
    throw Exception('Circuit API request timed out.');
  }

  @override
  Future<void> connect(Map<String, String> credentials) async {}

  @override
  void cancelActiveRequest() {}

  @override
  Future<ConnectorHealth> checkHealth() async => ConnectorHealth(
    status: ConnectorHealthStatus.connected,
    message: 'Connected',
    checkedAt: DateTime.now(),
  );

  @override
  void disconnect() {}

  @override
  Future<List<ConnectorModelInfo>> refreshModels() async => const [
    ConnectorModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano'),
  ];
}

Future<void> _delete(Directory directory) async {
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
}

Future<void> _waitForThreadStore(ProviderContainer container) async {
  for (var i = 0; i < 50; i += 1) {
    if (!container.read(studioThreadProvider).isLoading) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var i = 0; i < 100; i += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for condition.');
}
