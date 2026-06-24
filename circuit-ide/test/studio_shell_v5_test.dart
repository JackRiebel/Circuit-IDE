import 'dart:io';

import 'package:circuit_ide/agent/providers/provider_interface.dart';
import 'package:circuit_ide/agent/security/agent_tool_permission_policy.dart'
    as tool_policy;
import 'package:circuit_ide/agent/studio_agent_environment.dart';
import 'package:circuit_ide/models/agent_workspace.dart';
import 'package:circuit_ide/models/accepted_plan_context.dart';
import 'package:circuit_ide/models/chat_message.dart';
import 'package:circuit_ide/models/confirmation_request.dart';
import 'package:circuit_ide/models/provider_lifecycle_event.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/models/studio_right_drawer.dart';
import 'package:circuit_ide/models/studio_shell.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/models/studio_view_models.dart';
import 'package:circuit_ide/models/tool_call_info.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:circuit_ide/models/workspace_session.dart';
import 'package:circuit_ide/agent/tools/tool_registry.dart';
import 'package:circuit_ide/enums/connection_status.dart';
import 'package:circuit_ide/enums/message_role.dart';
import 'package:circuit_ide/services/agent_service.dart';
import 'package:circuit_ide/state/agent_workspace_provider.dart';
import 'package:circuit_ide/state/agent_turn_runtime_provider.dart';
import 'package:circuit_ide/state/connection_provider.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/patch_proposal_provider.dart';
import 'package:circuit_ide/state/settings_provider.dart';
import 'package:circuit_ide/state/studio_right_drawer_provider.dart';
import 'package:circuit_ide/state/studio_shell_provider.dart';
import 'package:circuit_ide/state/studio_request_lifecycle_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/state/studio_turn_provider.dart';
import 'package:circuit_ide/state/workspace_session_provider.dart';
import 'package:circuit_ide/ui/studio/studio_review_panel.dart';
import 'package:circuit_ide/ui/studio/studio_shell.dart';
import 'package:circuit_ide/ui/studio/studio_home.dart';
import 'package:circuit_ide/ui/studio/studio_left_rail.dart';
import 'package:circuit_ide/ui/studio/studio_message_sender.dart';
import 'package:circuit_ide/ui/studio/studio_progress_panel.dart';
import 'package:circuit_ide/ui/studio/studio_prompt_composer.dart';
import 'package:circuit_ide/ui/studio/studio_task_view.dart';
import 'package:circuit_ide/ui/studio/studio_plan_prompts.dart' as plan_prompts;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  VisibilityDetectorController.instance.updateInterval = Duration.zero;

  test('StudioShellProvider transitions between core views', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(studioShellProvider).mode, StudioMode.home);
    expect(container.read(studioShellProvider).planModeEnabled, isFalse);

    container.read(studioShellProvider.notifier).togglePlanMode();
    expect(container.read(studioShellProvider).planModeEnabled, isTrue);

    container.read(studioShellProvider.notifier).setPlanModeEnabled(false);
    expect(container.read(studioShellProvider).planModeEnabled, isFalse);

    container.read(studioShellProvider.notifier).openProject('/tmp/project');
    expect(container.read(studioShellProvider).mode, StudioMode.home);
    expect(
      container.read(studioShellProvider).selectedProjectPath,
      '/tmp/project',
    );

    container.read(studioShellProvider.notifier).openTask('task-1');
    expect(container.read(studioShellProvider).mode, StudioMode.task);
    expect(container.read(studioShellProvider).selectedTaskId, 'task-1');

    container.read(studioShellProvider.notifier).openReview();
    expect(container.read(studioShellProvider).mode, StudioMode.review);

    container.read(studioShellProvider.notifier).openSettings();
    expect(container.read(studioShellProvider).mode, StudioMode.settings);

    expect(
      StudioMode.values.map((mode) => mode.name),
      isNot(contains('advancedEditor')),
    );
  });

  testWidgets('Studio top bar utility buttons are functional', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioShell())),
      ),
    );

    expect(find.byTooltip('Review changes'), findsOneWidget);
    expect(find.byTooltip('Hide Environment panel'), findsOneWidget);

    await tester.tap(find.byTooltip('Review changes'));
    await tester.pump();
    expect(container.read(studioShellProvider).mode, StudioMode.review);

    await tester.tap(find.byTooltip('Hide Environment panel'));
    await tester.pump();
    expect(
      container.read(studioShellProvider).rightProgressPanelVisible,
      isFalse,
    );
    expect(find.byTooltip('Show Environment panel'), findsOneWidget);
  });

  testWidgets('Studio top bar thread menu routes to real actions', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Create role-based mini Salesforce');
    container.read(studioShellProvider.notifier).openThread(thread.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioShell())),
      ),
    );

    expect(find.byTooltip('Current thread'), findsOneWidget);
    expect(find.byTooltip('Thread options'), findsOneWidget);

    await tester.tap(find.byTooltip('Thread options').first);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(container.read(studioShellProvider).mode, StudioMode.settings);
  });

  test('Studio prompt modes map to expected actions', () {
    expect(StudioPromptMode.ask.agentProfile, isNull);
    expect(StudioPromptMode.code.agentProfile, AgentTaskProfile.patch);
    expect(StudioPromptMode.fix.agentProfile, AgentTaskProfile.investigate);
    expect(StudioPromptMode.review.agentProfile, AgentTaskProfile.review);
    expect(
      studioTaskStatusLabel(AgentTaskStatus.waitingForApproval),
      'Needs review',
    );
  });

  test('Greeting-only prompts stay conversational', () {
    expect(isConversationalOnlyPrompt('hello'), isTrue);
    expect(isConversationalOnlyPrompt('Hi Circuit!'), isTrue);
    expect(isConversationalOnlyPrompt('thanks'), isTrue);
    expect(isConversationalOnlyPrompt('hello, build a script'), isFalse);
    expect(isConversationalOnlyPrompt('create a hello world script'), isFalse);
  });

  test('Studio model history is rebuilt from persisted turns first', () {
    final started = DateTime(2026, 1, 1, 9);
    final thread = StudioThread(
      id: 'thread-turn-history',
      title: 'Turn history',
      createdAt: started,
      updatedAt: started,
      messages: [
        StudioThreadMessage(
          id: 'legacy-user',
          role: MessageRole.user,
          content: 'legacy only',
          timestamp: started.subtract(const Duration(minutes: 10)),
        ),
      ],
      turns: [
        StudioTurn(
          id: 'turn-1',
          threadId: 'thread-turn-history',
          requestId: 'request-1',
          userMessageId: 'user-1',
          prompt: 'What changed?',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(projectLabel: 'project'),
          status: StudioTurnStatus.completed,
          createdAt: started,
          updatedAt: started,
          completedAt: started.add(const Duration(seconds: 3)),
          events: [
            StudioTurnEvent.assistantMessage(
              turnId: 'turn-1',
              requestId: 'request-1',
              threadId: 'thread-turn-history',
              content: 'The diff is ready.',
              timestamp: started.add(const Duration(seconds: 2)),
            ),
          ],
        ),
      ],
    );

    final history = studioModelHistoryForThread(thread);

    expect(history.map((message) => message.role), [
      MessageRole.user,
      MessageRole.assistant,
    ]);
    expect(history.map((message) => message.content), [
      'What changed?',
      'The diff is ready.',
    ]);
  });

  test('Studio model history ignores unmigrated legacy messages', () {
    final started = DateTime(2026, 1, 1, 9);
    final thread = StudioThread(
      id: 'thread-legacy-history',
      title: 'Legacy history',
      createdAt: started,
      updatedAt: started,
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
          timestamp: started.add(const Duration(seconds: 1)),
        ),
      ],
    );

    final history = studioModelHistoryForThread(thread);

    expect(history, isEmpty);
  });

  test('Studio model history pairs failed turns with error context', () {
    final started = DateTime(2026, 1, 1, 9);
    final thread = StudioThread(
      id: 'thread-failed-turn-history',
      title: 'Failed turn history',
      createdAt: started,
      updatedAt: started,
      turns: [
        StudioTurn(
          id: 'turn-failed',
          threadId: 'thread-failed-turn-history',
          requestId: 'request-failed',
          userMessageId: 'user-failed',
          prompt: 'Run the checks',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(projectLabel: 'project'),
          status: StudioTurnStatus.failed,
          createdAt: started,
          updatedAt: started,
          completedAt: started.add(const Duration(seconds: 3)),
          events: [
            StudioTurnEvent.error(
              turnId: 'turn-failed',
              requestId: 'request-failed',
              threadId: 'thread-failed-turn-history',
              detail: 'pytest was not installed.',
              timestamp: started.add(const Duration(seconds: 2)),
            ),
          ],
        ),
      ],
    );

    final history = studioModelHistoryForThread(thread);

    expect(history.map((message) => message.role), [
      MessageRole.user,
      MessageRole.assistant,
    ]);
    expect(history.map((message) => message.content), [
      'Run the checks',
      'pytest was not installed.',
    ]);
  });

  test(
    'Studio model history uses lastError for interrupted persisted turns',
    () {
      final started = DateTime(2026, 1, 1, 9);
      final thread = StudioThread(
        id: 'thread-interrupted-turn-history',
        title: 'Interrupted turn history',
        createdAt: started,
        updatedAt: started,
        turns: [
          StudioTurn(
            id: 'turn-interrupted',
            threadId: 'thread-interrupted-turn-history',
            requestId: 'request-interrupted',
            userMessageId: 'user-interrupted',
            prompt: 'Continue the refactor',
            model: 'gpt-5-nano',
            contextSummary: const StudioContextSummary(projectLabel: 'project'),
            status: StudioTurnStatus.failed,
            createdAt: started,
            updatedAt: started.add(const Duration(seconds: 2)),
            completedAt: started.add(const Duration(seconds: 2)),
            lastError: 'Interrupted while CircuitCode was closed.',
          ),
        ],
      );

      final history = studioModelHistoryForThread(thread);

      expect(history.map((message) => message.role), [
        MessageRole.user,
        MessageRole.assistant,
      ]);
      expect(history.map((message) => message.content), [
        'Continue the refactor',
        'Interrupted while CircuitCode was closed.',
      ]);
    },
  );

  test('Studio turn failure keeps specific provider diagnostic detail', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Provider failure');
    const requestId = 'request-specific-failure';
    container
        .read(studioTurnProvider.notifier)
        .registerTurn(
          requestId: requestId,
          threadId: thread.id,
          taskId: null,
          userMessageId: 'message-specific-failure',
          prompt: 'Implement this plan',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(
            rootPath: '/tmp/project',
            projectLabel: 'project',
          ),
          intent: TurnIntent.code,
        );
    final turnId = container
        .read(studioTurnProvider)
        .refForRequest(requestId)!
        .turnId;
    container
        .read(studioTurnProvider.notifier)
        .addProviderDiagnostic(
          requestId,
          ProviderLifecycleEvent(
            requestId: requestId,
            turnId: turnId,
            kind: ProviderLifecycleEventKind.malformedChunk,
            timestamp: DateTime(2026),
            model: 'gpt-5-nano',
            detail: 'Missing tool-call arguments.',
          ),
        );
    container
        .read(studioTurnProvider.notifier)
        .addProviderDiagnostic(
          requestId,
          ProviderLifecycleEvent(
            requestId: requestId,
            turnId: turnId,
            kind: ProviderLifecycleEventKind.failed,
            timestamp: DateTime(2026, 1, 1, 0, 0, 1),
            model: 'gpt-5-nano',
            detail: 'Provider failed.',
          ),
        );

    container
        .read(studioTurnProvider.notifier)
        .fail(requestId, 'Provider failed.');

    final turn = container
        .read(studioThreadProvider)
        .threads
        .singleWhere((candidate) => candidate.id == thread.id)
        .turns
        .single;
    expect(turn.status, StudioTurnStatus.failed);
    expect(turn.lastError, contains('Malformed stream chunk'));
    expect(turn.lastError, contains('Missing tool-call arguments.'));
    expect(turn.lastError, isNot(contains('Provider failed: Provider failed')));
  });

  test('Studio turn failure keeps no-first-byte provider diagnostic detail', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Transport failure');
    const requestId = 'request-no-first-byte';
    container
        .read(studioTurnProvider.notifier)
        .registerTurn(
          requestId: requestId,
          threadId: thread.id,
          taskId: null,
          userMessageId: 'message-no-first-byte',
          prompt: 'Create a patch',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(
            rootPath: '/tmp/project',
            projectLabel: 'project',
          ),
          intent: TurnIntent.code,
        );
    final turnId = container
        .read(studioTurnProvider)
        .refForRequest(requestId)!
        .turnId;
    container
        .read(studioTurnProvider.notifier)
        .addProviderDiagnostic(
          requestId,
          ProviderLifecycleEvent(
            requestId: requestId,
            turnId: turnId,
            kind: ProviderLifecycleEventKind.noFirstByte,
            timestamp: DateTime(2026),
            model: 'gpt-5-nano',
            detail:
                'Circuit API request failed before an HTTP response was received: connection refused.',
          ),
        );
    container
        .read(studioTurnProvider.notifier)
        .addProviderDiagnostic(
          requestId,
          ProviderLifecycleEvent(
            requestId: requestId,
            turnId: turnId,
            kind: ProviderLifecycleEventKind.failed,
            timestamp: DateTime(2026, 1, 1, 0, 0, 1),
            model: 'gpt-5-nano',
            detail: 'Provider failed.',
          ),
        );

    container
        .read(studioTurnProvider.notifier)
        .fail(requestId, 'Provider failed.');

    final turn = container
        .read(studioThreadProvider)
        .threads
        .singleWhere((candidate) => candidate.id == thread.id)
        .turns
        .single;
    expect(turn.status, StudioTurnStatus.failed);
    expect(turn.lastError, contains('No provider response bytes'));
    expect(turn.lastError, contains('before an HTTP response was received'));
    expect(turn.lastError, contains('connection refused'));
    expect(turn.lastError, isNot(contains('Provider failed: Provider failed')));
  });

  testWidgets('Code-mode small talk sends as chat without workspace or tools', (
    tester,
  ) async {
    final provider = _ScriptedStudioProvider([
      const [
        ChatChunk(
          content: 'Hello. How can I help?',
          promptTokens: 12,
          completionTokens: 5,
        ),
        ChatChunk(
          isDone: true,
          finishReason: 'stop',
          promptTokens: 12,
          completionTokens: 5,
        ),
      ],
    ]);
    final service = AgentService();
    final container = ProviderContainer(
      overrides: [
        agentServiceProvider.overrideWithValue(service),
        studioAgentEnvironmentOverrideProvider.overrideWithValue(
          StudioAgentEnvironment(
            provider: provider,
            model: 'gpt-5-nano',
            workspaceRoot: Directory.systemTemp.path,
            permissionPolicy: tool_policy.AgentToolPermissionPolicy(
              workingDir: Directory.systemTemp.path,
            ),
            events: service.events,
            onProviderEvent: (_) {},
          ),
        ),
      ],
    );
    addTearDown(service.dispose);
    addTearDown(container.dispose);
    container
        .read(connectionStatusProvider.notifier)
        .set(ConnectionStatus.connected);
    container
        .read(studioShellProvider.notifier)
        .setPromptMode(StudioPromptMode.code);
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, child) {
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final result = await tester.runAsync(
      () => sendStudioMessage(capturedRef, 'hello'),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 40; i++) {
        final runtime = container.read(agentTurnRuntimeProvider);
        final thread = container.read(studioThreadProvider).selectedThread;
        final turn = thread?.turns.firstOrNull;
        if (!runtime.hasActiveStudioRequest &&
            turn?.status == StudioTurnStatus.completed) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    });
    await tester.pump();

    expect(result?.status, StudioSendStatus.sent);
    expect(container.read(fileTreeProvider).rootPath, isNull);
    expect(container.read(studioShellProvider).selectedProjectPath, isNull);
    expect(provider.exposedTools, [isEmpty]);
    expect(provider.messages, hasLength(1));
    expect(provider.messages.single.last.content, contains('hello'));

    final thread = container.read(studioThreadProvider).selectedThread;
    expect(thread, isNotNull);
    expect(thread!.messages, isEmpty);
    final turn = thread.turns.single;
    expect(turn.intent, TurnIntent.chat);
    expect(turn.status, StudioTurnStatus.completed);
    expect(turn.contextSummary.projectLabel, 'No project selected');
    expect(turn.contextSummary.includedItemCount, 0);
    expect(
      turn.events.where((event) => event.type == StudioTurnEventType.tool),
      isEmpty,
    );
    expect(
      turn.events
          .where((event) => event.type == StudioTurnEventType.assistantMessage)
          .single
          .detail,
      'Hello. How can I help?',
    );
  });

  testWidgets('Vague fix prompts do not create a workspace or expose tools', (
    tester,
  ) async {
    final provider = _ScriptedStudioProvider([
      const [
        ChatChunk(
          content:
              'What should I look at? Point me to a file, error, or behavior and I can help narrow it down.',
          promptTokens: 18,
          completionTokens: 16,
        ),
        ChatChunk(
          isDone: true,
          finishReason: 'stop',
          promptTokens: 18,
          completionTokens: 16,
        ),
      ],
    ]);
    final service = AgentService();
    final container = ProviderContainer(
      overrides: [
        agentServiceProvider.overrideWithValue(service),
        studioAgentEnvironmentOverrideProvider.overrideWithValue(
          StudioAgentEnvironment(
            provider: provider,
            model: 'gpt-5-nano',
            workspaceRoot: Directory.systemTemp.path,
            permissionPolicy: tool_policy.AgentToolPermissionPolicy(
              workingDir: Directory.systemTemp.path,
            ),
            events: service.events,
            onProviderEvent: (_) {},
          ),
        ),
      ],
    );
    addTearDown(service.dispose);
    addTearDown(container.dispose);
    container
        .read(connectionStatusProvider.notifier)
        .set(ConnectionStatus.connected);
    container
        .read(studioShellProvider.notifier)
        .setPromptMode(StudioPromptMode.fix);
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, child) {
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final result = await tester.runAsync(
      () => sendStudioMessage(capturedRef, 'fix it'),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 40; i++) {
        final runtime = container.read(agentTurnRuntimeProvider);
        final thread = container.read(studioThreadProvider).selectedThread;
        final turn = thread?.turns.firstOrNull;
        if (!runtime.hasActiveStudioRequest &&
            turn?.status == StudioTurnStatus.completed) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    });
    await tester.pump();

    expect(result?.status, StudioSendStatus.sent);
    expect(container.read(fileTreeProvider).rootPath, isNull);
    expect(container.read(studioShellProvider).selectedProjectPath, isNull);
    expect(provider.exposedTools, [isEmpty]);

    final thread = container.read(studioThreadProvider).selectedThread;
    expect(thread, isNotNull);
    final turn = thread!.turns.single;
    expect(turn.intent, TurnIntent.ask);
    expect(turn.status, StudioTurnStatus.completed);
    expect(turn.contextSummary.projectLabel, 'No project selected');
    expect(
      turn.events.where((event) => event.type == StudioTurnEventType.tool),
      isEmpty,
    );
    expect(
      turn.events
          .where((event) => event.type == StudioTurnEventType.assistantMessage)
          .single
          .detail,
      contains('What should I look at?'),
    );
  });

  test('Plan continuation text only targets active plan artifacts', () {
    expect(isPlanImplementationContinuationText('go ahead'), isFalse);
    expect(isPlanImplementationContinuationText('Looks good to me.'), isFalse);
    expect(isPlanImplementationContinuationText('implement this plan'), isTrue);
    expect(isPlanImplementationContinuationText('apply the plan'), isTrue);
    expect(isPlanImplementationContinuationText('approve'), isFalse);
    expect(isPlanApprovalOnlyText('approve'), isTrue);
    expect(isPlanApprovalOnlyText('approve as described'), isTrue);
    expect(isPlanApprovalOnlyText('looks good'), isTrue);
    expect(isPlanApprovalOnlyText('go ahead'), isTrue);
    expect(
      isPlanImplementationContinuationText('go ahead but change X'),
      isFalse,
    );
    expect(actionablePlanForContinuation(const PatchProposalState()), isNull);

    final activePlan = ProposedPatchSet(
      id: 'plan-active',
      title: 'Plan',
      edits: const [],
      createdAt: DateTime(2026),
      planMarkdown: '# Plan',
      plannedFiles: const ['lib/main.dart'],
    );
    expect(
      actionablePlanForContinuation(PatchProposalState(active: activePlan)),
      same(activePlan),
    );
    final selectedThread = StudioThread(
      id: 'thread-selected',
      title: 'Selected',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      turns: [
        StudioTurn(
          id: 'turn-selected',
          threadId: 'thread-selected',
          requestId: 'request-selected',
          userMessageId: 'user-selected',
          prompt: 'current thread',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(projectLabel: 'project'),
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ],
    );
    expect(
      actionablePlanForContinuation(
        PatchProposalState(active: activePlan),
        thread: selectedThread,
      ),
      isNull,
    );

    final concretePatch = ProposedPatchSet(
      id: 'patch-active',
      title: 'Patch',
      edits: const [
        ProposedFileEdit(
          path: 'lib/main.dart',
          type: ProposedFileEditType.modify,
          before: 'old',
          after: 'new',
        ),
      ],
      createdAt: DateTime(2026),
    );
    expect(
      actionablePlanForContinuation(PatchProposalState(active: concretePatch)),
      isNull,
    );

    expect(
      actionablePlanForContinuation(
        PatchProposalState(
          history: [
            activePlan.copyWith(approvalStatus: PatchApprovalStatus.approved),
          ],
        ),
      ),
      isNull,
    );
  });

  testWidgets(
    'Vague plan approval text does not implement active plan artifacts',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .ensureThread(title: 'Plan thread', model: 'gpt-5-nano');
      container
          .read(studioThreadProvider.notifier)
          .upsertTurn(
            thread.id,
            StudioTurn(
              id: 'turn-plan',
              threadId: thread.id,
              requestId: 'request-plan',
              userMessageId: 'user-plan',
              prompt: 'make a plan',
              model: 'gpt-5-nano',
              contextSummary: const StudioContextSummary(
                projectLabel: 'project',
              ),
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
            select: true,
          );
      final plan = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Actionable plan',
            edits: const [],
            runId: 'request-plan',
            planMarkdown: '# Plan\n\n- Update lib/main.dart.',
            plannedFiles: const ['lib/main.dart'],
          );
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) {
                capturedRef = ref;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      final result = await tester.runAsync(
        () => sendStudioMessage(capturedRef, 'looks good'),
      );
      await tester.pump();

      expect(result?.status, StudioSendStatus.blocked);
      expect(result?.registeredRequest, isFalse);
      expect(result?.error, contains('Implement this plan button'));
      final selectedThread = container
          .read(studioThreadProvider)
          .selectedThread!;
      expect(selectedThread.messages, isEmpty);
      expect(selectedThread.turns, hasLength(1));
      expect(selectedThread.status, StudioThreadStatus.idle);
      expect(selectedThread.lastError, isNull);
      final guidanceEvents = selectedThread.turns.single.events.where(
        (event) =>
            event.type == StudioTurnEventType.completionSummary &&
            event.title == 'Use the plan card',
      );
      expect(guidanceEvents, hasLength(1));
      expect(
        guidanceEvents.single.detail,
        contains('Implement this plan button'),
      );
      final patchState = container.read(patchProposalProvider);
      final active = patchState.active?.id == plan.id
          ? patchState.active!
          : patchState.history.firstWhere(
              (candidate) => candidate.id == plan.id,
            );
      expect(active.approvalStatus, PatchApprovalStatus.proposed);
    },
  );

  test('Plan continuation is scoped to the selected thread request', () {
    final currentThread = StudioThread(
      id: 'thread-current',
      title: 'Current',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      turns: [
        StudioTurn(
          id: 'turn-current',
          threadId: 'thread-current',
          requestId: 'request-current',
          userMessageId: 'user-current',
          prompt: 'make a plan',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(projectLabel: 'project'),
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ],
    );
    final oldThreadPlan = ProposedPatchSet(
      id: 'plan-old-thread',
      title: 'Old thread plan',
      edits: const [],
      runId: 'request-old',
      createdAt: DateTime(2026),
      planMarkdown: '# Old plan',
      plannedFiles: const ['old.dart'],
    );
    final currentThreadPlan = ProposedPatchSet(
      id: 'plan-current-thread',
      title: 'Current thread plan',
      edits: const [],
      runId: 'request-current',
      createdAt: DateTime(2026, 1, 1, 0, 0, 1),
      planMarkdown: '# Current plan',
      plannedFiles: const ['current.dart'],
    );

    expect(
      actionablePlanForContinuation(
        PatchProposalState(history: [oldThreadPlan]),
        thread: currentThread,
      ),
      isNull,
    );
    expect(
      actionablePlanForContinuation(
        PatchProposalState(history: [oldThreadPlan, currentThreadPlan]),
        thread: currentThread,
      )?.id,
      'plan-current-thread',
    );
  });

  test('Plan continuation chooses newest matching historical plan', () {
    final thread = StudioThread(
      id: 'thread',
      title: 'Thread',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      turns: [
        StudioTurn(
          id: 'turn-old',
          threadId: 'thread',
          requestId: 'request-old',
          userMessageId: 'user-old',
          prompt: 'old plan',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(projectLabel: 'project'),
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
        StudioTurn(
          id: 'turn-new',
          threadId: 'thread',
          requestId: 'request-new',
          userMessageId: 'user-new',
          prompt: 'new plan',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(projectLabel: 'project'),
          createdAt: DateTime(2026, 1, 1, 0, 0, 2),
          updatedAt: DateTime(2026, 1, 1, 0, 0, 2),
        ),
      ],
    );
    final oldPlan = ProposedPatchSet(
      id: 'old-plan',
      title: 'Old plan',
      edits: const [],
      runId: 'request-old',
      createdAt: DateTime(2026),
      planMarkdown: '# Old plan',
      plannedFiles: const ['old.dart'],
    );
    final newPlan = ProposedPatchSet(
      id: 'new-plan',
      title: 'New plan',
      edits: const [],
      runId: 'request-new',
      createdAt: DateTime(2026, 1, 1, 0, 0, 2),
      planMarkdown: '# New plan',
      plannedFiles: const ['new.dart'],
    );

    expect(
      actionablePlanForContinuation(
        PatchProposalState(history: [oldPlan, newPlan]),
        thread: thread,
      )?.id,
      'new-plan',
    );
  });

  test('Plan continuation honors task-scoped plans', () {
    final taskPlan = ProposedPatchSet(
      id: 'plan-task',
      title: 'Task plan',
      edits: const [],
      agentTaskId: 'task-1',
      createdAt: DateTime(2026),
      planMarkdown: '# Task plan',
      plannedFiles: const ['task.dart'],
    );

    expect(
      actionablePlanForContinuation(
        PatchProposalState(active: taskPlan),
        taskId: 'task-2',
      ),
      isNull,
    );
    expect(
      actionablePlanForContinuation(
        PatchProposalState(active: taskPlan),
        taskId: 'task-1',
      )?.id,
      'plan-task',
    );
  });

  test('Plan implementation prompt includes full plan and planned files', () {
    final patch = ProposedPatchSet(
      id: 'plan-1',
      title: 'Plan',
      edits: const [],
      createdAt: DateTime(2026),
      planMarkdown: '# Build it\n\n- Add the service\n- Verify it',
      plannedFiles: const ['lib/main.dart - update entrypoint'],
      verificationRequested: true,
    );

    final prompt = buildPlanImplementationPrompt(
      AcceptedPlanContext.fromPatch(patch),
    );

    expect(prompt, contains('Implement this approved plan.'));
    expect(prompt, contains('accepted plan context'));
    expect(prompt, contains('- lib/main.dart - update entrypoint'));
    expect(prompt, contains('Verification was explicitly requested.'));
    expect(prompt, isNot(contains('\napprove\n')));
  });

  test('Patch verification prompt routes to Verify mode', () {
    final patch = ProposedPatchSet(
      id: 'patch-verify',
      title: 'Fix login',
      edits: const [
        ProposedFileEdit(
          path: 'lib/login.dart',
          type: ProposedFileEditType.modify,
          before: 'old',
          after: 'new',
        ),
      ],
      changedFiles: const ['lib/login.dart'],
      verificationSuggestions: const ['flutter analyze', 'flutter test'],
      verificationRequested: true,
      createdAt: DateTime(2026),
    );

    final prompt = buildPatchVerificationPrompt(patch);
    final intent = IntentClassifier.classify(
      prompt,
      promptMode: StudioPromptMode.ask,
      planModeEnabled: false,
    );

    expect(prompt, contains('Run these verification checks'));
    expect(prompt, contains('- flutter analyze'));
    expect(prompt, contains('- flutter test'));
    expect(intent, TurnIntent.verify);
    expect(
      studioToolModeForIntent(
        intent: intent,
        promptMode: StudioPromptMode.ask,
        hasWorkspace: true,
        planModeEnabled: false,
      ),
      AgentToolMode.verify,
    );
  });

  test(
    'Patch verification prompt ignores non-command advisory suggestions',
    () {
      final patch = ProposedPatchSet(
        id: 'patch-verify-advisory',
        title: 'Fix login',
        edits: const [
          ProposedFileEdit(
            path: 'lib/login.dart',
            type: ProposedFileEditType.modify,
            before: 'old',
            after: 'new',
          ),
        ],
        changedFiles: const ['lib/login.dart'],
        verificationSuggestions: const [
          'Review the changed files and run the project checks.',
          'flutter test',
        ],
        verificationRequested: true,
        createdAt: DateTime(2026),
      );

      final prompt = buildPatchVerificationPrompt(patch);

      expect(prompt, contains('- flutter test'));
      expect(prompt, isNot(contains('Review the changed files')));
      expect(
        plan_prompts.isRunnableVerificationCommand('flutter test'),
        isTrue,
      );
      expect(
        plan_prompts.isRunnableVerificationCommand(
          'Review the changed files and run the project checks.',
        ),
        isFalse,
      );
    },
  );

  test('Applied verification-requested patches offer verification action', () {
    final patch = ProposedPatchSet(
      id: 'patch-verify-action',
      title: 'Fix login',
      edits: const [],
      changedFiles: const ['lib/login.dart'],
      applyStatus: PatchApplyStatus.applied,
      verificationRequested: true,
      verificationSuggestions: const ['flutter analyze'],
      createdAt: DateTime(2026),
    );

    expect(shouldOfferPatchVerification(patch), isTrue);
    expect(
      shouldOfferPatchVerification(
        patch.copyWith(applyStatus: PatchApplyStatus.conflict),
      ),
      isFalse,
    );
    expect(
      shouldOfferPatchVerification(
        patch.copyWith(verificationSuggestions: const []),
      ),
      isFalse,
    );
    expect(
      shouldOfferPatchVerification(
        patch.copyWith(
          verificationSuggestions: const [
            'Review the changed files and run the project checks.',
          ],
        ),
      ),
      isFalse,
    );
  });

  test('PatchProposalController accepts a specific plan', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(patchProposalProvider.notifier);
    final plan = controller.propose(
      title: 'Plan',
      edits: const [],
      planMarkdown: '# Plan',
      plannedFiles: const ['README.md'],
    );

    controller.markPlanAccepted(plan.id);

    final state = container.read(patchProposalProvider);
    expect(state.active, isNull);
    expect(state.history.single.approvalStatus, PatchApprovalStatus.approved);
    expect(state.history.single.applyStatus, isNull);
  });

  testWidgets('Studio Home renders Codex-familiar prompt surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: StudioShell())),
      ),
    );

    expect(find.text('New task'), findsOneWidget);
    expect(find.text('What should Circuit do next?'), findsOneWidget);
    expect(find.text('No project selected'), findsOneWidget);
    expect(
      find.textContaining('Circuit will create a project only when'),
      findsOneWidget,
    );
    expect(find.text('Try'), findsOneWidget);
    expect(find.text('Do anything'), findsOneWidget);
    expect(find.text('Review first'), findsOneWidget);
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Default permissions'), findsNothing);
    expect(find.text('gpt-5-nano'), findsOneWidget);
    expect(find.text('In 50.0M left / Out 5.0M left'), findsOneWidget);
    expect(find.byTooltip('Open project folder'), findsOneWidget);
    expect(find.text('Work locally'), findsNothing);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Plugins'), findsNothing);
    expect(find.text('Automations'), findsNothing);
    expect(find.text('Circuit mobile'), findsNothing);
    expect(find.byTooltip('Add context'), findsNothing);
    expect(find.byTooltip('Voice input'), findsNothing);
  });

  testWidgets('Studio rail settings stays inside Studio runtime', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioShell())),
      ),
    );

    await tester.tap(find.text('Settings'));
    await tester.pump();

    expect(container.read(studioShellProvider).mode, StudioMode.settings);
    expect(find.text('Studio settings'), findsOneWidget);
    expect(find.textContaining('Core Studio stays'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Approval scope'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Approval scope'), findsOneWidget);
    expect(find.text('Auto approve'), findsNothing);
    expect(find.text('Advanced Editor'), findsNothing);
  });

  testWidgets('Studio Home shows turn-owned recent threads, not legacy tasks', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(agentWorkspaceProvider.notifier)
        .startTask(goal: 'Legacy workspace task');
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Recent Studio thread');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioHome())),
      ),
    );

    expect(find.text('Recent Studio thread'), findsOneWidget);
    expect(find.text('Legacy workspace task'), findsNothing);

    await tester.tap(find.text('Recent Studio thread'));
    await tester.pump();

    final shell = container.read(studioShellProvider);
    expect(shell.mode, StudioMode.task);
    expect(shell.selectedTaskId, isNull);
    expect(container.read(studioThreadProvider).selectedThreadId, thread.id);
  });

  testWidgets('Studio rail prefers task-backed threads over legacy task rows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final root = Directory.systemTemp.createTempSync(
      'studio_rail_thread_first_',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(fileTreeProvider.notifier).openDirectory(root.path),
    );
    await tester.runAsync(
      () => container.read(studioThreadProvider.notifier).reload(),
    );
    container.read(settingsProvider.notifier).addRecentProject(root.path);
    container.read(studioShellProvider.notifier).openProject(root.path);
    addTearDown(
      () => container
          .read(settingsProvider.notifier)
          .removeRecentProject(root.path),
    );
    final task = container
        .read(agentWorkspaceProvider.notifier)
        .startTask(goal: 'Legacy workspace task');
    final thread = container
        .read(studioThreadProvider.notifier)
        .ensureThread(
          taskId: task.id,
          title: 'Thread-owned migrated row',
          model: 'gpt-5-nano',
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioLeftRail())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Thread-owned migrated row'), findsOneWidget);
    expect(find.text('Legacy workspace task'), findsNothing);

    await tester.tap(find.text('Thread-owned migrated row'));
    await tester.pump();

    final shell = container.read(studioShellProvider);
    expect(shell.mode, StudioMode.task);
    expect(shell.selectedTaskId, isNull);
    expect(container.read(studioThreadProvider).selectedThreadId, thread.id);
  });

  test('Studio rail only shows status chips for active or attention rows', () {
    expect(
      studioRailShouldShowStatusChip(
        const TaskDisplayState(kind: TaskDisplayKind.done, label: 'Done'),
      ),
      isFalse,
    );
    expect(
      studioRailShouldShowStatusChip(
        const TaskDisplayState(kind: TaskDisplayKind.idle, label: 'Ready'),
      ),
      isFalse,
    );
    expect(
      studioRailShouldShowStatusChip(
        const TaskDisplayState(
          kind: TaskDisplayKind.working,
          label: 'Working',
          isActive: true,
        ),
      ),
      isTrue,
    );
    expect(
      studioRailShouldShowStatusChip(
        const TaskDisplayState(
          kind: TaskDisplayKind.failed,
          label: 'Failed',
          needsAttention: true,
        ),
      ),
      isTrue,
    );
  });

  test('Studio rail formats passive row age labels compactly', () {
    final now = DateTime(2026, 6, 24, 12);

    expect(studioRailAgeLabel(null, now: now), isNull);
    expect(
      studioRailAgeLabel(now.subtract(const Duration(seconds: 10)), now: now),
      'now',
    );
    expect(
      studioRailAgeLabel(now.subtract(const Duration(minutes: 12)), now: now),
      '12m',
    );
    expect(
      studioRailAgeLabel(now.subtract(const Duration(hours: 3)), now: now),
      '3h',
    );
    expect(
      studioRailAgeLabel(now.subtract(const Duration(days: 6)), now: now),
      '6d',
    );
    expect(
      studioRailAgeLabel(now.subtract(const Duration(days: 14)), now: now),
      '2w',
    );
    expect(
      studioRailAgeLabel(now.subtract(const Duration(days: 45)), now: now),
      '1mo',
    );
  });

  testWidgets('Studio Home submissions create threads, not legacy tasks', (
    tester,
  ) async {
    final provider = _ScriptedStudioProvider([
      const [
        ChatChunk(content: 'Here is the inline brief.'),
        ChatChunk(finishReason: 'stop', isDone: true),
      ],
    ]);
    final service = AgentService();
    final container = ProviderContainer(
      overrides: [
        agentServiceProvider.overrideWithValue(service),
        studioAgentEnvironmentOverrideProvider.overrideWithValue(
          StudioAgentEnvironment(
            provider: provider,
            model: 'gpt-5-nano',
            workspaceRoot: Directory.systemTemp.path,
            permissionPolicy: tool_policy.AgentToolPermissionPolicy(
              workingDir: Directory.systemTemp.path,
            ),
            events: service.events,
            onProviderEvent: (_) {},
          ),
        ),
      ],
    );
    addTearDown(service.dispose);
    addTearDown(container.dispose);
    container
        .read(connectionStatusProvider.notifier)
        .set(ConnectionStatus.connected);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioHome())),
      ),
    );

    await tester.enterText(
      find.byType(TextField),
      'create a business case brief inline in chat without writing files',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 60; i++) {
        final runtime = container.read(agentTurnRuntimeProvider);
        final lifecycle = container.read(studioRequestLifecycleProvider);
        final thread = container.read(studioThreadProvider).selectedThread;
        final turn = thread?.turns.firstOrNull;
        if (!runtime.hasActiveStudioRequest &&
            lifecycle.activeRequests.isEmpty &&
            turn?.status == StudioTurnStatus.completed) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    });
    await tester.pumpAndSettle();

    expect(provider.messages, hasLength(1));
    expect(
      container.read(agentTurnRuntimeProvider).hasActiveStudioRequest,
      isFalse,
    );
    expect(
      container.read(studioRequestLifecycleProvider).activeRequests,
      isEmpty,
    );
    expect(container.read(agentWorkspaceProvider).tasks, isEmpty);
    expect(container.read(studioShellProvider).selectedTaskId, isNull);
    expect(container.read(studioShellProvider).mode, StudioMode.task);
    final thread = container.read(studioThreadProvider).selectedThread;
    expect(thread, isNotNull);
    expect(thread!.taskId, isNull);
    expect(thread.turns.single.prompt, contains('business case brief'));
  });

  testWidgets('Studio composer menus expose only working controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioShell())),
      ),
    );

    expect(find.text('Review first'), findsOneWidget);
    expect(find.text('Auto approve tools'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '/');
    await tester.pumpAndSettle();
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Context'), findsOneWidget);
    expect(find.text('Terminal'), findsOneWidget);
    expect(find.text('/browser'), findsNothing);

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(
      container.read(studioRightDrawerProvider).mode,
      StudioDrawerMode.files,
    );

    await tester.enterText(find.byType(TextField).first, '/context');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Context'));
    await tester.pumpAndSettle();
    expect(
      container.read(studioRightDrawerProvider).mode,
      StudioDrawerMode.context,
    );

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();

    expect(container.read(studioShellProvider).planModeEnabled, isFalse);
    await tester.tap(find.text('Plan').first);
    await tester.pumpAndSettle();
    expect(container.read(studioShellProvider).planModeEnabled, isTrue);
    await tester.tap(find.text('Plan').first);
    await tester.pumpAndSettle();
    expect(container.read(studioShellProvider).planModeEnabled, isFalse);

    await tester.tap(find.byTooltip('Task mode'));
    await tester.pumpAndSettle();
    expect(find.text('Ask'), findsOneWidget);
    expect(find.text('Code'), findsWidgets);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Fix'), findsNothing);
    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Choose model'));
    await tester.pumpAndSettle();
    expect(find.text('gemini-3.1-flash-lite'), findsOneWidget);
    expect(find.textContaining('120.0K context'), findsWidgets);
  });

  testWidgets('Studio composer sends with Enter', (tester) async {
    String? submitted;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StudioPromptComposer(
              hintText: 'Ask Circuit',
              onSubmit: (text) => submitted = text,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'hello circuit');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(submitted, 'hello circuit');
    expect(find.text('hello circuit'), findsNothing);
  });

  testWidgets('Inline plan card is expandable and revision-ready', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Plan task');
    final turn = StudioTurn(
      id: 'turn-1',
      threadId: thread.id,
      requestId: 'request-1',
      userMessageId: 'message-1',
      prompt: 'make a plan',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.assistantMessage(
          turnId: 'turn-1',
          requestId: 'request-1',
          threadId: thread.id,
          content: 'Here is the plan.',
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);
    final plan = container
        .read(patchProposalProvider.notifier)
        .propose(
          title: 'Implementation plan',
          edits: const [],
          runId: 'request-1',
          planMarkdown:
              '# Plan\n\n'
              '${List.filled(18, '- Build a bounded plan card.').join('\n')}',
          plannedFiles: const ['lib/ui/studio/studio_task_view.dart'],
        );
    container.read(patchProposalProvider.notifier).markPlanAccepted(plan.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    expect(find.text('Plan accepted'), findsOneWidget);
    expect(find.text('Implement this plan'), findsNothing);
    expect(find.text('Tell Circuit what to change'), findsOneWidget);
    expect(find.text('Expand plan'), findsOneWidget);

    await tester.tap(find.text('Expand plan'));
    await tester.pump();
    expect(find.text('Collapse plan'), findsOneWidget);

    await tester.tap(find.text('Tell Circuit what to change'));
    await tester.pump();
    final shell = container.read(studioShellProvider);
    expect(shell.planModeEnabled, isTrue);
    expect(shell.composerText, 'Revise this plan. Change: ');
    final revisedPlan = container
        .read(patchProposalProvider)
        .history
        .firstWhere((patch) => patch.id == plan.id);
    expect(revisedPlan.approvalStatus, PatchApprovalStatus.revisionRequested);
    expect(revisedPlan.revisionPrompt, 'Revise this plan. Change: ');
  });

  testWidgets('Plan card dismiss targets the rendered plan id', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Plan dismiss');
    final turn = StudioTurn(
      id: 'turn-1',
      threadId: thread.id,
      requestId: 'request-1',
      userMessageId: 'message-1',
      prompt: 'make a plan',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.assistantMessage(
          turnId: 'turn-1',
          requestId: 'request-1',
          threadId: thread.id,
          content: 'Here is the plan.',
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);
    final oldPlan = container
        .read(patchProposalProvider.notifier)
        .propose(
          title: 'Old plan',
          edits: const [],
          runId: 'request-1',
          planMarkdown: '# Old plan',
          plannedFiles: const ['old.dart'],
        );
    container.read(patchProposalProvider.notifier).markPlanAccepted(oldPlan.id);
    final activePlan = container
        .read(patchProposalProvider.notifier)
        .propose(
          title: 'Active plan',
          edits: const [],
          planMarkdown: '# Active plan',
          plannedFiles: const ['active.dart'],
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    expect(find.text('Plan accepted'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pump();

    final state = container.read(patchProposalProvider);
    final dismissedOldPlan = state.history.firstWhere(
      (patch) => patch.id == oldPlan.id,
    );
    final stillActivePlan = state.history.firstWhere(
      (patch) => patch.id == activePlan.id,
    );
    expect(dismissedOldPlan.approvalStatus, PatchApprovalStatus.rejected);
    expect(dismissedOldPlan.applyStatus, PatchApplyStatus.rejected);
    expect(stillActivePlan.approvalStatus, PatchApprovalStatus.proposed);
    expect(state.active?.id, activePlan.id);
  });

  testWidgets('Studio transcript hides routine context and tool status rows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Quiet transcript');
    final turn = StudioTurn(
      id: 'turn-quiet',
      threadId: thread.id,
      requestId: 'request-quiet',
      userMessageId: 'message-quiet',
      prompt: 'review this project',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(
        rootPath: '/tmp/project',
        projectLabel: 'project',
        includedItemCount: 1,
        estimatedTokens: 80,
      ),
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.context(
          turnId: 'turn-quiet',
          requestId: 'request-quiet',
          threadId: thread.id,
          summary: const StudioContextSummary(
            rootPath: '/tmp/project',
            projectLabel: 'project',
            includedItemCount: 1,
            estimatedTokens: 80,
          ),
        ),
        StudioTurnEvent.progress(
          turnId: 'turn-quiet',
          requestId: 'request-quiet',
          threadId: thread.id,
          title: 'Still waiting',
          detail: 'Circuit AI has not returned output yet.',
          transcriptVisible: true,
        ),
        StudioTurnEvent.tool(
          turnId: 'turn-quiet',
          requestId: 'request-quiet',
          threadId: thread.id,
          toolCallId: 'tool-1',
          toolName: 'read_file',
          title: 'read_file',
          detail: 'completed',
        ),
        StudioTurnEvent.assistantMessage(
          turnId: 'turn-quiet',
          requestId: 'request-quiet',
          threadId: thread.id,
          content: 'Here is the useful response.',
        ),
        StudioTurnEvent.completionSummary(
          turnId: 'turn-quiet',
          requestId: 'request-quiet',
          threadId: thread.id,
          title: 'Ready for next prompt',
          detail: 'Ready for the next prompt.',
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    expect(find.text('review this project'), findsOneWidget);
    expect(find.text('Here is the useful response.'), findsOneWidget);
    expect(find.text('Project context'), findsNothing);
    expect(find.text('Still waiting'), findsNothing);
    expect(find.text('read_file'), findsNothing);
    expect(find.text('Ready for next prompt'), findsOneWidget);
  });

  testWidgets('Studio transcript renders meaningful completion summaries', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Completion summary transcript');
    final turn = StudioTurn(
      id: 'turn-summary',
      threadId: thread.id,
      requestId: 'request-summary',
      userMessageId: 'message-summary',
      prompt: 'apply the patch',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.assistantMessage(
          turnId: 'turn-summary',
          requestId: 'request-summary',
          threadId: thread.id,
          content: 'I prepared the patch summary.',
        ),
        StudioTurnEvent.completionSummary(
          turnId: 'turn-summary',
          requestId: 'request-summary',
          threadId: thread.id,
          title: 'Applied changes',
          detail: 'Applied 2 files.\nSuggested checks: flutter test',
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    expect(find.text('I prepared the patch summary.'), findsOneWidget);
    expect(find.text('Applied changes'), findsWidgets);
    expect(find.textContaining('Suggested checks: flutter test'), findsWidgets);
  });

  testWidgets('Terminal turn states do not render stale elapsed timers', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Old failed task');
    final oldStartedAt = DateTime.now().subtract(const Duration(days: 3));
    final turn = StudioTurn(
      id: 'turn-failed',
      threadId: thread.id,
      requestId: 'request-failed',
      userMessageId: 'message-failed',
      prompt: 'debug this',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.failed,
      events: [
        StudioTurnEvent.error(
          turnId: 'turn-failed',
          requestId: 'request-failed',
          threadId: thread.id,
          detail: 'The provider timed out.',
        ),
      ],
      createdAt: oldStartedAt,
      updatedAt: oldStartedAt,
      completedAt: oldStartedAt.add(const Duration(minutes: 4)),
      lastError: 'The provider timed out.',
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    expect(find.text('Failed'), findsWidgets);
    expect(find.textContaining('Failed for'), findsNothing);
  });

  testWidgets('Selected thread renders even when a legacy task is selected', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(agentWorkspaceProvider.notifier)
        .startTask(goal: 'Legacy workspace task');
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Thread-owned conversation');
    final turn = StudioTurn(
      id: 'turn-thread-owned',
      threadId: thread.id,
      requestId: 'request-thread-owned',
      userMessageId: 'message-thread-owned',
      prompt: 'thread prompt',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.assistantMessage(
          turnId: 'turn-thread-owned',
          requestId: 'request-thread-owned',
          threadId: thread.id,
          content: 'thread response',
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);
    container.read(studioShellProvider.notifier).openThread(thread.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    expect(find.text('thread prompt'), findsOneWidget);
    expect(find.text('thread response'), findsWidgets);
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byTooltip('Copy response'));
    await tester.pump();
    expect(copiedText, 'thread response');

    await tester.tap(find.byTooltip('Mark helpful'));
    await tester.pump();
    expect(find.text('Marked helpful'), findsOneWidget);

    await tester.tap(find.byTooltip('Mark needs work'));
    await tester.pump();
    expect(find.text('Marked needs work'), findsOneWidget);
    expect(find.text('Legacy workspace task'), findsNothing);
  });

  testWidgets('Task-backed thread shows patch card without live legacy task', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .ensureThread(
          taskId: 'missing-task',
          title: 'Recovered task-backed thread',
          model: 'gpt-5-nano',
        );
    final turn = StudioTurn(
      id: 'turn-plan',
      threadId: thread.id,
      requestId: 'request-plan',
      userMessageId: 'message-plan',
      prompt: 'make a plan',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.assistantMessage(
          turnId: 'turn-plan',
          requestId: 'request-plan',
          threadId: thread.id,
          content: 'Plan is ready.',
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);
    container
        .read(patchProposalProvider.notifier)
        .preserveProposal(
          ProposedPatchSet(
            id: 'plan-missing-task',
            title: 'Recovered plan',
            edits: const [],
            runId: 'request-plan',
            agentTaskId: 'missing-task',
            createdAt: DateTime(2026),
            planMarkdown: '# Recovered plan',
            plannedFiles: const ['README.md - document setup'],
          ),
        );
    container.read(studioShellProvider.notifier).openThread(thread.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    expect(container.read(agentWorkspaceProvider).tasks, isEmpty);
    expect(find.text('Plan is ready.'), findsWidgets);
    expect(find.text('Plan ready'), findsOneWidget);
    expect(find.textContaining('README.md'), findsOneWidget);
  });

  testWidgets('Transcript patch file rows open the diff drawer', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Patch row thread');
    final turn = StudioTurn(
      id: 'turn-patch-row',
      threadId: thread.id,
      requestId: 'request-patch-row',
      userMessageId: 'message-patch-row',
      prompt: 'update the readme',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.assistantMessage(
          turnId: 'turn-patch-row',
          requestId: 'request-patch-row',
          threadId: thread.id,
          content: 'I prepared the README update.',
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);
    final patch = container
        .read(patchProposalProvider.notifier)
        .propose(
          title: 'Update README',
          runId: 'request-patch-row',
          edits: const [
            ProposedFileEdit(
              path: 'README.md',
              type: ProposedFileEditType.modify,
              before: 'old',
              after: 'new',
            ),
          ],
        );
    container.read(studioShellProvider.notifier).openThread(thread.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    await tester.tap(find.text('README.md'));
    await tester.pump();

    final drawer = container.read(studioRightDrawerProvider);
    expect(drawer.mode, StudioDrawerMode.diff);
    expect(drawer.diffId, patch.id);
    expect(drawer.patchFilePath, 'README.md');
  });

  testWidgets('Studio Task View renders transcript and progress panel', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final task = container
        .read(agentWorkspaceProvider.notifier)
        .startTask(goal: 'Create role-based mini Salesforce');
    container.read(studioShellProvider.notifier).openTask(task.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    expect(find.text('Create role-based mini Salesforce'), findsWidgets);
    expect(find.text('Environment'), findsOneWidget);
    expect(find.byTooltip('Progress'), findsOneWidget);
    expect(find.text('Push'), findsNothing);
    expect(find.text('Create pull request'), findsNothing);
    expect(find.text('Ask for follow-up changes'), findsOneWidget);
  });

  testWidgets('Progress drawer shows selected-thread repair diagnostics', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Repair thread');
    final turn = StudioTurn(
      id: 'turn-repair',
      threadId: thread.id,
      requestId: 'request-repair',
      userMessageId: 'message-repair',
      prompt: 'fix login',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(
        rootPath: '/tmp/project',
        projectLabel: 'project',
        includedItemCount: 2,
        estimatedTokens: 120,
      ),
      status: StudioTurnStatus.completed,
      providerDiagnostics: [
        ProviderLifecycleEvent(
          requestId: 'request-repair',
          turnId: 'turn-repair',
          kind: ProviderLifecycleEventKind.outcomeRepair,
          timestamp: DateTime(2026),
          model: 'gpt-5-nano',
          detail: 'Runtime rejected vague prose and requested a repair.',
        ),
        ProviderLifecycleEvent(
          requestId: 'request-repair',
          turnId: 'turn-repair',
          kind: ProviderLifecycleEventKind.completed,
          timestamp: DateTime(2026, 1, 1, 0, 0, 1),
          model: 'gpt-5-nano',
          detail: 'Provider completed after repair.',
        ),
      ],
      events: [
        StudioTurnEvent.userMessage(
          id: 'message-repair',
          turnId: 'turn-repair',
          requestId: 'request-repair',
          threadId: thread.id,
          content: 'fix login',
          timestamp: DateTime(2026),
        ),
        StudioTurnEvent.assistantMessage(
          turnId: 'turn-repair',
          requestId: 'request-repair',
          threadId: thread.id,
          content: 'Patch proposal is ready for review.',
          timestamp: DateTime(2026, 1, 1, 0, 0, 2),
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    expect(find.text('Repair'), findsOneWidget);
    expect(find.text('1 model retry'), findsOneWidget);
    expect(find.text('Provider completed'), findsOneWidget);
    expect(find.text('Provider completed after repair.'), findsOneWidget);
  });

  testWidgets('Standalone progress panel uses selected thread without task', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Approval thread');
    final turn = StudioTurn(
      id: 'turn-approval-panel',
      threadId: thread.id,
      requestId: 'request-approval-panel',
      userMessageId: 'message-approval-panel',
      prompt: 'run checks',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(
        rootPath: '/tmp/project',
        projectLabel: 'project',
      ),
      status: StudioTurnStatus.waitingForApproval,
      events: [
        StudioTurnEvent.approval(
          turnId: 'turn-approval-panel',
          requestId: 'request-approval-panel',
          threadId: thread.id,
          request: ConfirmationRequest(
            id: 'approval-panel',
            toolCall: const ToolCallInfo(
              id: 'tool-approval-panel',
              name: 'run_command',
              arguments: {'command': 'flutter test'},
            ),
            preview: 'flutter test',
          ),
          timestamp: DateTime(2026),
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioProgressPanel())),
      ),
    );

    expect(find.text('Task'), findsOneWidget);
    expect(find.text('Approval'), findsOneWidget);
    expect(find.text('Required'), findsOneWidget);
  });

  testWidgets('Progress drawer prefers specific provider failure diagnostics', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Malformed stream thread');
    final turn = StudioTurn(
      id: 'turn-malformed',
      threadId: thread.id,
      requestId: 'request-malformed',
      userMessageId: 'message-malformed',
      prompt: 'implement the plan',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(
        rootPath: '/tmp/project',
        projectLabel: 'project',
        includedItemCount: 2,
        estimatedTokens: 120,
      ),
      status: StudioTurnStatus.failed,
      lastError: 'Malformed stream chunk: Missing tool arguments.',
      providerDiagnostics: [
        ProviderLifecycleEvent(
          requestId: 'request-malformed',
          turnId: 'turn-malformed',
          kind: ProviderLifecycleEventKind.firstByte,
          timestamp: DateTime(2026),
          model: 'gpt-5-nano',
        ),
        ProviderLifecycleEvent(
          requestId: 'request-malformed',
          turnId: 'turn-malformed',
          kind: ProviderLifecycleEventKind.malformedChunk,
          timestamp: DateTime(2026, 1, 1, 0, 0, 1),
          model: 'gpt-5-nano',
          detail: 'Missing tool arguments.',
        ),
        ProviderLifecycleEvent(
          requestId: 'request-malformed',
          turnId: 'turn-malformed',
          kind: ProviderLifecycleEventKind.failed,
          timestamp: DateTime(2026, 1, 1, 0, 0, 2),
          model: 'gpt-5-nano',
          detail: 'Provider failed.',
        ),
      ],
      events: [
        StudioTurnEvent.userMessage(
          id: 'message-malformed',
          turnId: 'turn-malformed',
          requestId: 'request-malformed',
          threadId: thread.id,
          content: 'implement the plan',
          timestamp: DateTime(2026),
        ),
        StudioTurnEvent.error(
          turnId: 'turn-malformed',
          requestId: 'request-malformed',
          threadId: thread.id,
          detail: 'Malformed stream chunk: Missing tool arguments.',
          timestamp: DateTime(2026, 1, 1, 0, 0, 3),
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    expect(find.text('Malformed stream chunk'), findsOneWidget);
    expect(find.text('Missing tool arguments.'), findsOneWidget);
    expect(find.text('Provider failed'), findsNothing);
  });

  testWidgets('Progress drawer explains no-first-byte provider failures', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'No first byte thread');
    final turn = StudioTurn(
      id: 'turn-no-first-byte',
      threadId: thread.id,
      requestId: 'request-no-first-byte',
      userMessageId: 'message-no-first-byte',
      prompt: 'implement the plan',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(
        rootPath: '/tmp/project',
        projectLabel: 'project',
        includedItemCount: 2,
        estimatedTokens: 120,
      ),
      status: StudioTurnStatus.failed,
      lastError:
          'No provider response bytes: Circuit API request failed before an HTTP response was received: connection refused.',
      providerDiagnostics: [
        ProviderLifecycleEvent(
          requestId: 'request-no-first-byte',
          turnId: 'turn-no-first-byte',
          kind: ProviderLifecycleEventKind.requestSent,
          timestamp: DateTime(2026),
          model: 'gpt-5-nano',
        ),
        ProviderLifecycleEvent(
          requestId: 'request-no-first-byte',
          turnId: 'turn-no-first-byte',
          kind: ProviderLifecycleEventKind.noFirstByte,
          timestamp: DateTime(2026, 1, 1, 0, 0, 1),
          model: 'gpt-5-nano',
          detail:
              'Circuit API request failed before an HTTP response was received: connection refused.',
        ),
        ProviderLifecycleEvent(
          requestId: 'request-no-first-byte',
          turnId: 'turn-no-first-byte',
          kind: ProviderLifecycleEventKind.failed,
          timestamp: DateTime(2026, 1, 1, 0, 0, 2),
          model: 'gpt-5-nano',
          detail: 'Provider failed.',
        ),
      ],
      events: [
        StudioTurnEvent.userMessage(
          id: 'message-no-first-byte',
          turnId: 'turn-no-first-byte',
          requestId: 'request-no-first-byte',
          threadId: thread.id,
          content: 'implement the plan',
          timestamp: DateTime(2026),
        ),
        StudioTurnEvent.error(
          turnId: 'turn-no-first-byte',
          requestId: 'request-no-first-byte',
          threadId: thread.id,
          detail:
              'No provider response bytes: Circuit API request failed before an HTTP response was received: connection refused.',
          timestamp: DateTime(2026, 1, 1, 0, 0, 3),
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    expect(find.text('No provider response bytes'), findsOneWidget);
    expect(
      find.text(
        'Circuit API request failed before an HTTP response was received: connection refused.',
      ),
      findsOneWidget,
    );
    expect(find.text('Provider failed'), findsNothing);
  });

  testWidgets('Progress drawer prefers timeout over generic provider failure', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Timeout thread');
    final turn = StudioTurn(
      id: 'turn-timeout',
      threadId: thread.id,
      requestId: 'request-timeout',
      userMessageId: 'message-timeout',
      prompt: 'implement the plan',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(
        rootPath: '/tmp/project',
        projectLabel: 'project',
      ),
      status: StudioTurnStatus.failed,
      lastError: 'Provider timed out: Request exceeded 4 minutes.',
      providerDiagnostics: [
        ProviderLifecycleEvent(
          requestId: 'request-timeout',
          turnId: 'turn-timeout',
          kind: ProviderLifecycleEventKind.firstByte,
          timestamp: DateTime(2026),
          model: 'gpt-5-nano',
        ),
        ProviderLifecycleEvent(
          requestId: 'request-timeout',
          turnId: 'turn-timeout',
          kind: ProviderLifecycleEventKind.timeout,
          timestamp: DateTime(2026, 1, 1, 0, 0, 1),
          model: 'gpt-5-nano',
          detail: 'Request exceeded 4 minutes.',
        ),
        ProviderLifecycleEvent(
          requestId: 'request-timeout',
          turnId: 'turn-timeout',
          kind: ProviderLifecycleEventKind.failed,
          timestamp: DateTime(2026, 1, 1, 0, 0, 2),
          model: 'gpt-5-nano',
          detail: 'Provider failed.',
        ),
      ],
      events: [
        StudioTurnEvent.userMessage(
          id: 'message-timeout',
          turnId: 'turn-timeout',
          requestId: 'request-timeout',
          threadId: thread.id,
          content: 'implement the plan',
          timestamp: DateTime(2026),
        ),
        StudioTurnEvent.error(
          turnId: 'turn-timeout',
          requestId: 'request-timeout',
          threadId: thread.id,
          detail: 'Provider timed out: Request exceeded 4 minutes.',
          timestamp: DateTime(2026, 1, 1, 0, 0, 3),
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    expect(find.text('Provider timed out'), findsOneWidget);
    expect(find.text('Request exceeded 4 minutes.'), findsOneWidget);
    expect(find.text('Provider failed'), findsNothing);
  });

  testWidgets('Studio Review Panel renders beginner patch review', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(patchProposalProvider.notifier)
        .propose(
          title: 'Update readme',
          edits: const [
            ProposedFileEdit(
              path: 'README.md',
              type: ProposedFileEditType.modify,
              before: 'old',
              after: 'new',
            ),
          ],
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioReviewPanel())),
      ),
    );

    expect(find.text('Circuit wants to change 1 files'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('Apply changes'), findsOneWidget);
    expect(find.text('Ask for revision'), findsOneWidget);
  });

  testWidgets('Studio Review Panel file rows open the diff drawer', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final patch = container
        .read(patchProposalProvider.notifier)
        .propose(
          title: 'Update readme',
          edits: const [
            ProposedFileEdit(
              path: 'README.md',
              type: ProposedFileEditType.modify,
              before: 'old',
              after: 'new',
              unifiedDiff: '--- README.md\n+++ README.md\n@@\n-old\n+new\n',
            ),
          ],
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioReviewPanel())),
      ),
    );

    await tester.tap(find.text('README.md').first);
    await tester.pump();

    final drawer = container.read(studioRightDrawerProvider);
    expect(drawer.mode, StudioDrawerMode.diff);
    expect(drawer.diffId, patch.id);
    expect(drawer.patchFilePath, 'README.md');
  });

  testWidgets(
    'Studio Review Panel exposes implementation for plan-only review',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Build plan',
            edits: const [],
            planMarkdown: '# Plan\n\n- Add lib/app.dart.',
            plannedFiles: const ['lib/app.dart'],
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudioReviewPanel())),
        ),
      );

      expect(find.text('Circuit created a plan'), findsOneWidget);
      expect(find.text('Implement this plan'), findsOneWidget);
      expect(find.text('Approve plan'), findsNothing);
      expect(find.text('Apply changes'), findsNothing);
    },
  );

  testWidgets(
    'Plan implementation restores mode and leaves plan proposed when preflight blocks',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('studio_plan_blocked_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.runAsync(
        () =>
            container.read(fileTreeProvider.notifier).openDirectory(root.path),
      );
      await container.read(agentServiceProvider).updateWorkingDir(root.path);
      final plan = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Blocked plan',
            edits: const [],
            planMarkdown: '# Plan\n\n- Add lib/app.dart.',
            plannedFiles: const ['lib/app.dart'],
          );
      container.read(studioShellProvider.notifier)
        ..setPlanModeEnabled(true)
        ..setPromptMode(StudioPromptMode.fix);
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, child) {
                  capturedRef = ref;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );

      final result = await tester.runAsync(
        () => implementPlanFromStudio(capturedRef, plan),
      );
      await tester.pump();

      expect(result?.status, StudioSendStatus.blocked);
      final patchState = container.read(patchProposalProvider);
      final patch = patchState.active?.id == plan.id
          ? patchState.active!
          : patchState.history.firstWhere(
              (candidate) => candidate.id == plan.id,
            );
      expect(patch.approvalStatus, PatchApprovalStatus.proposed);
      final shell = container.read(studioShellProvider);
      expect(shell.planModeEnabled, isTrue);
      expect(shell.promptMode, StudioPromptMode.fix);
    },
  );

  testWidgets(
    'Plan implementation sends structured context and produces a patch proposal',
    (tester) async {
      final root = Directory.systemTemp.createTempSync(
        'studio_plan_sender_patch_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final service = AgentService();
      final provider = _ScriptedStudioProvider([
        const [
          ChatChunk(
            toolCallIndex: 0,
            toolCallId: 'patch',
            toolCallName: 'propose_patch',
            toolCallArguments:
                '{"title":"Create greeting","summary":"Add the accepted greeting file.","files":[{"path":"hello.txt","intent":"Add greeting","operation":"create","content":"hello from accepted plan\\n"}]}',
          ),
          ChatChunk(isDone: true, finishReason: 'tool_calls'),
        ],
      ]);
      final container = ProviderContainer(
        overrides: [
          agentServiceProvider.overrideWithValue(service),
          workspaceSessionProvider.overrideWith(
            () => _ReadyWorkspaceSessionController(root.path),
          ),
          studioAgentEnvironmentOverrideProvider.overrideWithValue(
            StudioAgentEnvironment(
              provider: provider,
              model: 'gpt-5-nano',
              workspaceRoot: root.path,
              permissionPolicy: tool_policy.AgentToolPermissionPolicy(
                workingDir: root.path,
              ),
              events: service.events,
              onProviderEvent: (_) {},
            ),
          ),
        ],
      );
      addTearDown(service.dispose);
      addTearDown(container.dispose);
      container
          .read(connectionStatusProvider.notifier)
          .set(ConnectionStatus.connected);
      await tester.runAsync(
        () =>
            container.read(fileTreeProvider.notifier).openDirectory(root.path),
      );
      final plan = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Accepted greeting plan',
            edits: const [],
            planMarkdown: '# Plan\n\n- Create hello.txt.',
            plannedFiles: const ['hello.txt — Add greeting'],
          );
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) {
                capturedRef = ref;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      final result = await tester.runAsync(
        () => implementPlanFromStudio(capturedRef, plan),
      );
      await tester.runAsync(() async {
        for (var i = 0; i < 60; i++) {
          final runtime = container.read(agentTurnRuntimeProvider);
          final thread = container.read(studioThreadProvider).selectedThread;
          final turn = thread?.turns.firstOrNull;
          if (!runtime.hasActiveStudioRequest &&
              turn?.status == StudioTurnStatus.completed) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      });
      await tester.pump();

      expect(result?.status, StudioSendStatus.sent, reason: result?.error);
      expect(provider.messages, hasLength(1));
      expect(
        provider.messages.single.last.content,
        contains('accepted plan context'),
      );
      expect(provider.messages.single.last.content, contains('hello.txt'));
      expect(
        provider.messages.single.last.content,
        isNot(contains('\napprove\n')),
      );
      expect(provider.exposedTools.single, contains('propose_patch'));
      expect(provider.exposedTools.single, isNot(contains('apply_patch_set')));
      expect(provider.exposedTools.single, isNot(contains('run_command')));

      final thread = container.read(studioThreadProvider).selectedThread;
      expect(thread, isNotNull);
      final turn = thread!.turns.single;
      expect(turn.intent, TurnIntent.code);
      expect(turn.status, StudioTurnStatus.completed);
      expect(turn.acceptedPlanState, AcceptedPlanState.patchProposed);
      final patchState = container.read(patchProposalProvider);
      expect(patchState.active?.title, 'Create greeting');
      expect(patchState.active?.edits.single.path, 'hello.txt');
      expect(
        patchState.history
            .firstWhere((candidate) => candidate.id == plan.id)
            .approvalStatus,
        PatchApprovalStatus.approved,
      );

      final applyResult = await tester.runAsync(
        () => container.read(patchProposalProvider.notifier).applyActive(),
      );
      await tester.pump();

      expect(applyResult?.status, PatchApplyStatus.applied);
      expect(
        File('${root.path}/hello.txt').readAsStringSync(),
        'hello from accepted plan\n',
      );
      final appliedPatch = container
          .read(patchProposalProvider)
          .history
          .firstWhere((candidate) => candidate.title == 'Create greeting');
      expect(appliedPatch.applyStatus, PatchApplyStatus.applied);
      expect(appliedPatch.changedFiles, ['hello.txt']);
      expect(appliedPatch.checkpointId, isNotNull);
      final updatedTurn = container
          .read(studioThreadProvider)
          .selectedThread!
          .turns
          .single;
      final applyEvents = updatedTurn.events.where(
        (event) =>
            event.type == StudioTurnEventType.completionSummary &&
            event.title == 'Applied changes',
      );
      expect(applyEvents, hasLength(1));
      expect(applyEvents.single.detail, contains('Applied 1 files.'));
      expect(applyEvents.single.detail, contains('Created hello.txt'));
    },
  );

  testWidgets('Plan implementation fails vague prose instead of completing', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync(
      'studio_plan_sender_vague_',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final service = AgentService();
    final provider = _ScriptedStudioProvider([
      const [
        ChatChunk(content: 'Sure, I can implement that.'),
        ChatChunk(isDone: true, finishReason: 'stop'),
      ],
      const [
        ChatChunk(content: 'I will make those updates now.'),
        ChatChunk(isDone: true, finishReason: 'stop'),
      ],
    ]);
    final container = ProviderContainer(
      overrides: [
        agentServiceProvider.overrideWithValue(service),
        workspaceSessionProvider.overrideWith(
          () => _ReadyWorkspaceSessionController(root.path),
        ),
        studioAgentEnvironmentOverrideProvider.overrideWithValue(
          StudioAgentEnvironment(
            provider: provider,
            model: 'gpt-5-nano',
            workspaceRoot: root.path,
            permissionPolicy: tool_policy.AgentToolPermissionPolicy(
              workingDir: root.path,
            ),
            events: service.events,
            onProviderEvent: (_) {},
          ),
        ),
      ],
    );
    addTearDown(service.dispose);
    addTearDown(container.dispose);
    container
        .read(connectionStatusProvider.notifier)
        .set(ConnectionStatus.connected);
    await tester.runAsync(
      () => container.read(fileTreeProvider.notifier).openDirectory(root.path),
    );
    final plan = container
        .read(patchProposalProvider.notifier)
        .propose(
          title: 'Vague failure plan',
          edits: const [],
          planMarkdown: '# Plan\n\n- Create hello.txt.',
          plannedFiles: const ['hello.txt — Add greeting'],
        );
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, child) {
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final result = await tester.runAsync(
      () => implementPlanFromStudio(capturedRef, plan),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 60; i++) {
        final runtime = container.read(agentTurnRuntimeProvider);
        final thread = container.read(studioThreadProvider).selectedThread;
        final turn = thread?.turns.firstOrNull;
        if (!runtime.hasActiveStudioRequest &&
            turn?.status == StudioTurnStatus.failed) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    });
    await tester.pump();

    expect(result?.status, StudioSendStatus.sent, reason: result?.error);
    expect(provider.exposedTools, hasLength(2));
    expect(provider.exposedTools.first, contains('propose_patch'));
    final thread = container.read(studioThreadProvider).selectedThread;
    expect(thread, isNotNull);
    final turn = thread!.turns.single;
    expect(turn.status, StudioTurnStatus.failed);
    expect(turn.acceptedPlanState, AcceptedPlanState.failed);
    expect(
      turn.lastError,
      contains('accepted plan did not produce app-applyable file edits'),
    );
    expect(container.read(patchProposalProvider).active?.id, isNot(plan.id));
  });

  testWidgets('Studio Review Panel renders applied and restored checkpoints', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final root = Directory.systemTemp.createTempSync('studio_review_patch_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final readme = File('${root.path}/README.md');
    readme.writeAsStringSync('old');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(fileTreeProvider.notifier).openDirectory(root.path),
    );
    expect(container.read(fileTreeProvider).rootPath, root.path);
    container
        .read(patchProposalProvider.notifier)
        .propose(
          title: 'Update readme',
          edits: const [
            ProposedFileEdit(
              path: 'README.md',
              type: ProposedFileEditType.modify,
              before: 'old',
              after: 'new',
            ),
          ],
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioReviewPanel())),
      ),
    );

    expect(find.text('Apply changes'), findsOneWidget);

    final apply = await tester.runAsync(
      () => container.read(patchProposalProvider.notifier).applyActive(),
    );
    await tester.pump();

    expect(apply?.status, PatchApplyStatus.applied);
    expect(readme.readAsStringSync(), 'new');
    expect(find.text('Applied 1 files'), findsOneWidget);
    expect(find.text('Restore checkpoint'), findsOneWidget);
    expect(
      container.read(patchProposalProvider).history.first.applyStatus,
      PatchApplyStatus.applied,
    );

    final checkpointId = container
        .read(patchProposalProvider)
        .history
        .first
        .checkpointId!;
    final restore = await tester.runAsync(
      () => container
          .read(patchProposalProvider.notifier)
          .restoreCheckpoint(checkpointId),
    );
    await tester.pump();

    expect(restore?.status, PatchApplyStatus.restored);
    expect(readme.readAsStringSync(), 'old');
    expect(find.text('Checkpoint restored'), findsOneWidget);
    expect(
      container.read(patchProposalProvider).history.first.applyStatus,
      PatchApplyStatus.restored,
    );
  });

  testWidgets(
    'Studio Review Panel apply and restore buttons mutate only through review UI',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final root = Directory.systemTemp.createTempSync(
        'studio_review_button_apply_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final readme = File('${root.path}/README.md');
      readme.writeAsStringSync('old');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.runAsync(
        () =>
            container.read(fileTreeProvider.notifier).openDirectory(root.path),
      );
      container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Update readme',
            edits: const [
              ProposedFileEdit(
                path: 'README.md',
                type: ProposedFileEditType.modify,
                before: 'old',
                after: 'new',
              ),
            ],
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudioReviewPanel())),
        ),
      );

      final applyButton = find.widgetWithText(FilledButton, 'Apply changes');
      expect(applyButton, findsOneWidget);
      final apply = tester.widget<FilledButton>(applyButton);
      expect(apply.onPressed, isNotNull);
      await tester.runAsync(() async {
        apply.onPressed!();
        for (var i = 0; i < 20; i++) {
          final active = container.read(patchProposalProvider).active;
          if (active?.applyStatus == PatchApplyStatus.applied) return;
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      });
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 50));

      var state = container.read(patchProposalProvider);
      var renderedPatch = state.active ?? state.history.first;
      expect(readme.readAsStringSync(), 'new');
      expect(renderedPatch.applyStatus, PatchApplyStatus.applied);
      expect(renderedPatch.changedFiles, ['README.md']);
      expect(renderedPatch.checkpointId, isNotNull);
      expect(find.text('Applied 1 files'), findsOneWidget);
      expect(find.text('Restore checkpoint'), findsOneWidget);

      final restoreButton = find.widgetWithText(
        OutlinedButton,
        'Restore checkpoint',
      );
      expect(restoreButton, findsOneWidget);
      final restore = tester.widget<OutlinedButton>(restoreButton);
      expect(restore.onPressed, isNotNull);
      await tester.runAsync(() async {
        restore.onPressed!();
        for (var i = 0; i < 20; i++) {
          final current = container.read(patchProposalProvider);
          final restored =
              current.active ??
              (current.history.isEmpty ? null : current.history.first);
          if (restored?.applyStatus == PatchApplyStatus.restored) return;
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      });
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 50));

      state = container.read(patchProposalProvider);
      renderedPatch = state.active ?? state.history.first;
      expect(readme.readAsStringSync(), 'old');
      expect(renderedPatch.applyStatus, PatchApplyStatus.restored);
      expect(find.text('Checkpoint restored'), findsOneWidget);
    },
  );

  testWidgets(
    'Studio Review Panel apply button reports conflicts without writes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final root = Directory.systemTemp.createTempSync(
        'studio_review_conflict_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final readme = File('${root.path}/README.md');
      readme.writeAsStringSync('changed on disk');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.runAsync(
        () =>
            container.read(fileTreeProvider.notifier).openDirectory(root.path),
      );
      container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Update readme',
            edits: const [
              ProposedFileEdit(
                path: 'README.md',
                type: ProposedFileEditType.modify,
                before: 'old',
                after: 'new',
              ),
            ],
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudioReviewPanel())),
        ),
      );

      final applyButton = find.widgetWithText(FilledButton, 'Apply changes');
      expect(applyButton, findsOneWidget);
      final button = tester.widget<FilledButton>(applyButton);
      expect(button.onPressed, isNotNull);
      await tester.runAsync(() async {
        button.onPressed!();
        for (var i = 0; i < 20; i++) {
          final active = container.read(patchProposalProvider).active;
          if (active?.applyStatus != null) return;
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      });
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 50));

      final state = container.read(patchProposalProvider);
      expect(state.active, isNotNull);
      expect(state.active!.applyStatus, PatchApplyStatus.conflict);
      expect(state.active!.changedFiles, isEmpty);
      expect(state.checkpoints, isEmpty);
      expect(readme.readAsStringSync(), 'changed on disk');
      expect(find.text('Patch needs attention'), findsOneWidget);
      expect(
        find.textContaining('File changed since proposal'),
        findsOneWidget,
      );
      expect(find.text('Apply changes'), findsOneWidget);
    },
  );

  test(
    'PatchProposalController rejects Windows absolute paths before applying',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'studio_patch_windows_absolute_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      final patch = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Unsafe Windows path',
            edits: const [
              ProposedFileEdit(
                path: r'C:\temp\outside.txt',
                type: ProposedFileEditType.create,
                after: 'outside\n',
              ),
            ],
          );

      expect(patch.edits.single.path, r'C:/temp/outside.txt');
      final result = await container
          .read(patchProposalProvider.notifier)
          .apply(patch.id);

      expect(result.status, PatchApplyStatus.conflict);
      expect(result.conflictMessage, contains('outside the workspace'));
      expect(Directory('${root.path}/C:').existsSync(), isFalse);
      final state = container.read(patchProposalProvider);
      expect(state.active!.applyStatus, PatchApplyStatus.conflict);
      expect(state.checkpoints, isEmpty);
    },
  );
}

class _ScriptedStudioProvider implements AIProvider {
  final List<List<ChatChunk>> rounds;
  final List<List<String>> exposedTools = [];
  final List<List<ChatMessage>> messages = [];
  var _index = 0;

  _ScriptedStudioProvider(this.rounds);

  @override
  List<ModelInfo> get availableModels => const [
    ModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano', contextWindow: 1000),
  ];

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities();

  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
    id: 'scripted-studio',
    displayName: 'Scripted Studio',
    shortName: 'scripted',
  );

  @override
  bool get isConnected => true;

  @override
  String get name => 'scripted-studio';

  @override
  Stream<ChatChunk> chat(
    List<ChatMessage> messages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async* {
    this.messages.add(List<ChatMessage>.from(messages));
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
  void disconnect() {}

  @override
  void cancelActiveRequest() {}

  @override
  Future<ConnectorHealth> checkHealth() async => ConnectorHealth(
    status: ConnectorHealthStatus.connected,
    message: 'Connected',
    checkedAt: DateTime.now(),
  );

  @override
  Future<List<ConnectorModelInfo>> refreshModels() async => const [
    ConnectorModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano'),
  ];
}

class _ReadyWorkspaceSessionController extends WorkspaceSessionController {
  final String rootPath;

  _ReadyWorkspaceSessionController(this.rootPath);

  @override
  WorkspaceSessionState build() => WorkspaceSessionState(
    rootPath: rootPath,
    agentWorkingDir: rootPath,
    status: WorkspaceSessionStatus.ready,
    lastBoundAt: DateTime.now(),
  );

  @override
  void syncFromCurrentWorkspace() {
    state = WorkspaceSessionState(
      rootPath: rootPath,
      agentWorkingDir: rootPath,
      status: WorkspaceSessionStatus.ready,
      lastBoundAt: DateTime.now(),
    );
  }
}
