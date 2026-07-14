import 'dart:async';
import 'dart:io';

import 'package:circuit_ide/core/constants/design_tokens.dart';
import 'package:circuit_ide/agent/providers/provider_interface.dart';
import 'package:circuit_ide/agent/security/agent_tool_permission_policy.dart'
    as tool_policy;
import 'package:circuit_ide/agent/studio_agent_environment.dart';
import 'package:circuit_ide/models/agent_workspace.dart';
import 'package:circuit_ide/models/accepted_plan_context.dart';
import 'package:circuit_ide/models/chat_message.dart';
import 'package:circuit_ide/models/command_run.dart';
import 'package:circuit_ide/models/confirmation_request.dart';
import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/models/provider_lifecycle_event.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/models/settings_model.dart';
import 'package:circuit_ide/models/studio_right_drawer.dart';
import 'package:circuit_ide/models/studio_shell.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/models/studio_view_models.dart';
import 'package:circuit_ide/models/tool_call_info.dart';
import 'package:circuit_ide/models/tool_result_envelope.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:circuit_ide/models/workspace_session.dart';
import 'package:circuit_ide/agent/tools/tool_registry.dart';
import 'package:circuit_ide/enums/connection_status.dart';
import 'package:circuit_ide/enums/message_role.dart';
import 'package:circuit_ide/services/agent_service.dart';
import 'package:circuit_ide/state/agent_run_provider.dart';
import 'package:circuit_ide/state/agent_workspace_provider.dart';
import 'package:circuit_ide/state/agent_turn_runtime_provider.dart';
import 'package:circuit_ide/state/artifact_launch_provider.dart';
import 'package:circuit_ide/state/command_palette_provider.dart';
import 'package:circuit_ide/state/command_run_provider.dart';
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
import 'package:circuit_ide/ui/studio/studio_plan_continuation.dart';
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
  StudioThreadController.debugPersistDebounceOverride = Duration.zero;
  tearDownAll(() {
    StudioThreadController.debugPersistDebounceOverride = null;
  });

  Future<void> flushStudioThreadPersist(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1000));
  }

  test('StudioShellProvider transitions between core views', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(studioShellProvider).mode, StudioMode.home);
    expect(container.read(studioShellProvider).planModeEnabled, isFalse);

    container.read(studioShellProvider.notifier).togglePlanMode();
    expect(container.read(studioShellProvider).planModeEnabled, isTrue);

    container.read(studioShellProvider.notifier).setPlanModeEnabled(false);
    expect(container.read(studioShellProvider).planModeEnabled, isFalse);

    container
        .read(studioShellProvider.notifier)
        .setExecutionMode(StudioExecutionMode.worktree);
    expect(
      container.read(studioShellProvider).executionMode,
      StudioExecutionMode.local,
    );

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

  test(
    'StudioShellProvider keeps real back and forward navigation history',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(studioShellProvider.notifier);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Navigation thread');

      expect(container.read(studioShellProvider).canNavigateBack, isFalse);
      expect(container.read(studioShellProvider).canNavigateForward, isFalse);

      notifier.openProject('/tmp/project');
      expect(container.read(studioShellProvider).canNavigateBack, isTrue);
      expect(container.read(studioShellProvider).canNavigateForward, isFalse);

      notifier.openThread(thread.id);
      expect(container.read(studioShellProvider).mode, StudioMode.task);
      expect(container.read(studioThreadProvider).selectedThreadId, thread.id);

      notifier.navigateBack();
      expect(container.read(studioShellProvider).mode, StudioMode.home);
      expect(
        container.read(studioShellProvider).selectedProjectPath,
        '/tmp/project',
      );
      expect(container.read(studioThreadProvider).selectedThreadId, isNull);
      expect(container.read(studioShellProvider).canNavigateForward, isTrue);

      notifier.navigateForward();
      expect(container.read(studioShellProvider).mode, StudioMode.task);
      expect(container.read(studioThreadProvider).selectedThreadId, thread.id);
      expect(container.read(studioShellProvider).canNavigateBack, isTrue);
    },
  );

  testWidgets('Studio top bar utility buttons are functional', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioShell())),
      ),
    );

    expect(find.byTooltip('Open in'), findsOneWidget);
    expect(find.byTooltip('Command palette (⌘K)'), findsOneWidget);
    expect(find.byTooltip('Studio settings'), findsNothing);
    expect(find.byTooltip('Open review'), findsNothing);
    expect(find.byTooltip('Hide Progress panel (⌥⌘→)'), findsOneWidget);

    await tester.tap(find.byTooltip('Command palette (⌘K)'));
    await tester.pump();
    expect(container.read(commandPaletteProvider).isOpen, isTrue);
    container.read(commandPaletteProvider.notifier).close();
    await tester.pump();

    await tester.tap(find.byTooltip('Open in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review').last);
    await tester.pumpAndSettle();
    expect(container.read(studioShellProvider).mode, StudioMode.review);

    await tester.tap(find.byTooltip('Hide Progress panel (⌥⌘→)'));
    await tester.pump();
    expect(
      container.read(studioShellProvider).rightProgressPanelVisible,
      isFalse,
    );
    expect(find.byTooltip('Show Progress panel (⌥⌘→)'), findsOneWidget);

    await tester.tap(find.byTooltip('Open in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Files').last);
    await tester.pumpAndSettle();
    expect(
      container.read(studioShellProvider).rightProgressPanelVisible,
      isTrue,
    );
    expect(
      container.read(studioRightDrawerProvider).mode,
      StudioDrawerMode.files,
    );

    await tester.tap(find.byTooltip('Thread options'));
    await tester.pumpAndSettle();
    expect(find.text('Back to projects'), findsOneWidget);
    final backToProjects = tester.widget<Text>(find.text('Back to projects'));
    expect(backToProjects.style?.fontSize, FontSizes.xs);
    expect(backToProjects.style?.fontWeight, FontWeight.w500);
    final homeIcon = tester.widget<Icon>(
      find.byIcon(Icons.folder_outlined).last,
    );
    expect(homeIcon.size, 13);
  });

  testWidgets('Studio top bar Open in menu routes each drawer target', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Open in thread');
    container.read(studioShellProvider.notifier).openThread(thread.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioShell())),
      ),
    );

    for (final target in <String, StudioDrawerMode>{
      'Files': StudioDrawerMode.files,
      'Terminal': StudioDrawerMode.terminal,
    }.entries) {
      await tester.tap(find.byTooltip('Open in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(target.key).last);
      await tester.pumpAndSettle();

      expect(
        container.read(studioShellProvider).rightProgressPanelVisible,
        true,
      );
      expect(container.read(studioRightDrawerProvider).mode, target.value);
    }

    await tester.tap(find.byTooltip('Open in'));
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: find.text('Browser'),
        matching: find.byType(PopupMenuItem),
      ),
      findsNothing,
    );
    for (final hiddenMenuLabel in [
      'Environment',
      'Code',
      'Diff',
      'Sources',
      'Context',
    ]) {
      expect(
        find.ancestor(
          of: find.text(hiddenMenuLabel),
          matching: find.byType(PopupMenuItem),
        ),
        findsNothing,
      );
    }
    expect(find.text('Side chat'), findsOneWidget);
    expect(find.text('^⇧G'), findsOneWidget);
    expect(find.text('⌘T'), findsNothing);
    expect(find.text('⌘P'), findsOneWidget);
    expect(find.text('⌥⌘S'), findsOneWidget);
    final reviewMenuText = tester.widget<Text>(find.text('Review').last);
    expect(reviewMenuText.style?.fontSize, FontSizes.xs);
    expect(reviewMenuText.style?.fontWeight, FontWeight.w500);
    expect(
      tester
          .getSize(
            find
                .ancestor(
                  of: find.text('Review').last,
                  matching: find.byType(SizedBox),
                )
                .first,
          )
          .width,
      268,
    );
    expect(
      tester
          .widgetList<Icon>(find.byIcon(Icons.rate_review_outlined))
          .last
          .size,
      13,
    );
    await tester.tap(find.text('Review').last);
    await tester.pumpAndSettle();
    expect(container.read(studioShellProvider).mode, StudioMode.review);

    await tester.tap(find.byTooltip('Open in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Side chat').last);
    await tester.pumpAndSettle();
    expect(container.read(studioShellProvider).mode, StudioMode.task);
    expect(container.read(studioThreadProvider).selectedThreadId, thread.id);
  });

  testWidgets('Studio chrome typography and icons match compact visual scale', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Create role-based mini Salesforce');
    container.read(studioShellProvider.notifier).openThread(thread.id);
    await flushStudioThreadPersist(tester);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioShell())),
      ),
    );

    final titleText = tester.widget<Text>(
      find.text('Create role-based mini Salesforce').first,
    );
    expect(titleText.style?.fontSize, FontSizes.base);
    expect(titleText.style?.fontWeight, FontWeight.w600);
    expect(find.byTooltip('Back'), findsOneWidget);
    final titleRight = tester
        .getTopRight(find.text('Create role-based mini Salesforce').first)
        .dx;
    final overflowLeft = tester.getTopLeft(find.byTooltip('Thread options')).dx;
    expect(overflowLeft - titleRight, lessThanOrEqualTo(12));

    final openInText = tester.widget<Text>(find.text('Open in'));
    expect(openInText.style?.fontSize, FontSizes.xs);
    expect(openInText.style?.fontWeight, FontWeight.w600);

    final openInIcon = tester.widget<Icon>(
      find.byIcon(Icons.folder_special_outlined).first,
    );
    expect(openInIcon.size, 14);
    expect(find.byTooltip('Command palette (⌘K)'), findsOneWidget);
    expect(find.byTooltip('Studio settings'), findsNothing);
    expect(find.byTooltip('Open review'), findsNothing);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.tune_outlined).first).size,
      13,
    );

    final railText = tester.widget<Text>(find.text('New chat'));
    expect(railText.style?.fontSize, FontSizes.sm);

    final railIcon = tester.widget<Icon>(find.byIcon(Icons.edit_square).first);
    expect(railIcon.size, 14);

    final windowDots = tester
        .widgetList<Container>(find.byType(Container))
        .where((container) {
          final decoration = container.decoration;
          return decoration is BoxDecoration &&
              {
                const Color(0xFFFF5F57),
                const Color(0xFFFFBD2E),
                const Color(0xFF28C840),
              }.contains(decoration.color);
        });
    expect(windowDots, isEmpty);
  });

  testWidgets('Studio top bar keeps its actions usable at narrow desktop width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(760, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(
          title:
              'A deliberately long task title that must not hide Studio controls',
        );
    container.read(studioShellProvider.notifier).openThread(thread.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioShell())),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Open in'), findsOneWidget);
    expect(find.byTooltip('Command palette (⌘K)'), findsOneWidget);
    expect(find.byTooltip('Thread options'), findsOneWidget);

    await tester.tap(find.byTooltip('Open in'));
    await tester.pumpAndSettle();
    final menuRow = find
        .ancestor(of: find.text('Review').last, matching: find.byType(SizedBox))
        .first;
    expect(tester.getSize(menuRow).width, 268);
    expect(tester.takeException(), isNull);
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
    expect(StudioPromptMode.research.agentProfile, isNull);
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

  test('Studio model history skips explicitly hidden internal user turns', () {
    final started = DateTime(2026, 1, 1, 9);
    final thread = StudioThread(
      id: 'thread-hidden-turn-history',
      title: 'Hidden turn history',
      createdAt: started,
      updatedAt: started,
      turns: [
        StudioTurn(
          id: 'turn-hidden',
          threadId: 'thread-hidden-turn-history',
          requestId: 'request-hidden',
          userMessageId: 'user-hidden',
          prompt: 'Run these verification checks for the completed work.',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(projectLabel: 'project'),
          status: StudioTurnStatus.completed,
          createdAt: started,
          updatedAt: started.add(const Duration(seconds: 2)),
          completedAt: started.add(const Duration(seconds: 2)),
          events: [
            StudioTurnEvent.userMessage(
              id: 'user-hidden',
              turnId: 'turn-hidden',
              requestId: 'request-hidden',
              threadId: 'thread-hidden-turn-history',
              content: 'Run verification',
              timestamp: started,
              transcriptVisible: false,
            ),
            StudioTurnEvent.assistantMessage(
              turnId: 'turn-hidden',
              requestId: 'request-hidden',
              threadId: 'thread-hidden-turn-history',
              content: 'Verification command completed.',
              timestamp: started.add(const Duration(seconds: 1)),
            ),
          ],
        ),
      ],
    );

    final history = studioModelHistoryForThread(thread);

    expect(history.map((message) => message.role), [MessageRole.assistant]);
    expect(history.single.content, 'Verification command completed.');
  });

  test(
    'Studio model history skips accepted-plan prompts even without user events',
    () {
      final started = DateTime(2026, 1, 1, 9);
      final thread = StudioThread(
        id: 'thread-accepted-plan-history',
        title: 'Accepted plan history',
        createdAt: started,
        updatedAt: started,
        turns: [
          StudioTurn(
            id: 'turn-accepted-plan',
            threadId: 'thread-accepted-plan-history',
            requestId: 'request-accepted-plan',
            userMessageId: 'user-accepted-plan',
            prompt:
                'Implement this approved plan.\n\nUse the accepted plan context attached to this request as the source of truth.',
            model: 'gpt-5-nano',
            contextSummary: const StudioContextSummary(projectLabel: 'project'),
            intent: TurnIntent.code,
            acceptedPlanState: AcceptedPlanState.patchProposed,
            acceptedPlanContext: const AcceptedPlanContext(
              patchSetId: 'plan-1',
              title: 'Plan',
              summary: 'Implement one file.',
              markdown: '- Create hello.txt',
              plannedFiles: ['hello.txt — create'],
            ),
            status: StudioTurnStatus.completed,
            createdAt: started,
            updatedAt: started.add(const Duration(seconds: 2)),
            completedAt: started.add(const Duration(seconds: 2)),
            events: [
              StudioTurnEvent.assistantMessage(
                turnId: 'turn-accepted-plan',
                requestId: 'request-accepted-plan',
                threadId: 'thread-accepted-plan-history',
                content: 'Prepared changes for review.',
                timestamp: started.add(const Duration(seconds: 1)),
              ),
            ],
          ),
        ],
      );

      final history = studioModelHistoryForThread(thread);

      expect(history.map((message) => message.role), [MessageRole.assistant]);
      expect(history.single.content, 'Prepared changes for review.');
      expect(
        history.map((message) => message.content).join('\n'),
        isNot(contains('Implement this approved plan')),
      );
    },
  );

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

  testWidgets('Blocked Studio send preserves visible failed user turn', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
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
    await tester.pump();

    expect(result?.status, StudioSendStatus.blocked);
    expect(result?.error, contains('AI is not connected'));

    final thread = container.read(studioThreadProvider).selectedThread;
    expect(thread, isNotNull);
    expect(thread!.status, StudioThreadStatus.failed);
    expect(thread.turns, hasLength(1));

    final turn = thread.turns.single;
    expect(turn.prompt, 'hello');
    expect(turn.status, StudioTurnStatus.failed);
    expect(
      turn.events.any((event) => event.type == StudioTurnEventType.userMessage),
      isTrue,
    );
    expect(
      turn.events.any(
        (event) =>
            event.type == StudioTurnEventType.error &&
            event.detail.contains('AI is not connected'),
      ),
      isTrue,
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

  testWidgets('Broad build ideas start discovery before code', (tester) async {
    final provider = _ScriptedStudioProvider([
      const [
        ChatChunk(
          content:
              'You want a datacenter sizing tool for customer conversations. Before code, I need to understand inputs, outputs, sizing rules, and the first workflow. Key questions: what equipment families, what constraints, what output format, and who uses it?',
          promptTokens: 42,
          completionTokens: 34,
        ),
        ChatChunk(
          isDone: true,
          finishReason: 'stop',
          promptTokens: 42,
          completionTokens: 34,
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
      () => sendStudioMessage(
        capturedRef,
        'I want to build something to help me size out datacenters for customers',
      ),
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
    expect(provider.exposedTools, [isNot(contains('propose_patch'))]);

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
      contains('Before code'),
    );
    await flushStudioThreadPersist(tester);
  });

  testWidgets(
    'Studio context payload does not attach enterprise specialist context while gated',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
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

      final payload = buildStudioContextPayload(
        capturedRef,
        'Size a Cisco branch refresh with EoL switches, Wi-Fi 7 APs, and topology diagrams.',
      );

      expect(payload.specialistSelection.hasEnterpriseRouting, isFalse);
      expect(payload.specialistSelection.resolvedAgentIds, isEmpty);
      expect(
        payload.specialistSelection.rationale,
        contains('Enterprise specialist routing is disabled'),
      );
      expect(
        payload.attachments.map((attachment) => attachment.label),
        isNot(contains('Enterprise specialist routing')),
      );
      expect(
        payload.attachments.map((attachment) => attachment.id),
        everyElement(isNot(contains('enterprise-specialists'))),
      );
      expect(payload.summary.specialistLabels, isEmpty);
      expect(payload.summary.specialistRouting, isNull);
    },
  );

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

  testWidgets(
    'Patch verification helper runs suggested checks without model mediation',
    (tester) async {
      final root = Directory.systemTemp.createTempSync(
        'studio_patch_verify_sender_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.runAsync(
        () =>
            container.read(fileTreeProvider.notifier).openDirectory(root.path),
      );
      await tester.runAsync(
        () => container.read(studioThreadProvider.notifier).reload(),
      );
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Patch verification');
      container.read(studioShellProvider.notifier).openThread(thread.id);
      final patch = ProposedPatchSet(
        id: 'patch-verify-hidden',
        title: 'Applied patch',
        runId: 'request-applied',
        edits: const [
          ProposedFileEdit(
            path: 'lib/login.dart',
            type: ProposedFileEditType.modify,
            before: 'old',
            after: 'new',
          ),
        ],
        changedFiles: const ['lib/login.dart'],
        applyStatus: PatchApplyStatus.applied,
        verificationRequested: true,
        verificationSuggestions: const ['python3 -c "print(\'verify-ok\')"'],
        createdAt: DateTime(2026),
      );
      container.read(patchProposalProvider.notifier).preserveProposal(patch);
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
        () => verifyPatchFromStudio(capturedRef, patch),
      );
      await tester.runAsync(() async {
        for (var i = 0; i < 60; i++) {
          final updated = container.read(studioThreadProvider).selectedThread;
          final repaired = updated?.turns.where(
            (turn) =>
                turn.intent == TurnIntent.code &&
                turn.status == StudioTurnStatus.completed,
          );
          if (repaired?.isNotEmpty == true) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      });

      expect(result, isNotNull);
      expect(result!.status, StudioSendStatus.sent, reason: result.error);
      final updatedThread = container
          .read(studioThreadProvider)
          .selectedThread!;
      final turn = updatedThread.turns.singleWhere(
        (turn) => turn.requestId == result.requestId,
      );
      expect(turn.intent, TurnIntent.verify);
      expect(turn.prompt, 'Running verification');
      expect(turn.status, StudioTurnStatus.completed);
      expect(
        turn.events
            .singleWhere(
              (event) => event.type == StudioTurnEventType.userMessage,
            )
            .transcriptVisible,
        isFalse,
      );
      final history = studioModelHistoryForThread(updatedThread);
      expect(
        history.map((message) => message.content),
        isNot(contains('Running verification')),
      );
      expect(
        history.map((message) => message.content),
        isNot(
          contains('Run these verification checks for the completed work.'),
        ),
      );
      final commandRun = container.read(commandRunProvider).values.single;
      expect(commandRun.command, 'python3 -c "print(\'verify-ok\')"');
      expect(commandRun.status, CommandRunStatus.succeeded);
      expect(commandRun.combinedOutput, contains('verify-ok'));
      expect(
        turn.events
            .where(
              (event) =>
                  event.type == StudioTurnEventType.completionSummary &&
                  event.detail.contains('Verification completed.'),
            )
            .single
            .detail,
        contains('passed'),
      );
      final storedPatch = container
          .read(patchProposalProvider)
          .history
          .where((candidate) => candidate.id == patch.id)
          .firstOrNull;
      expect(storedPatch?.verificationRequestId, result.requestId);
      await tester.pump();
      await flushStudioThreadPersist(tester);
    },
  );

  testWidgets(
    'Patch verification helper includes failure output in final summary',
    (tester) async {
      final root = Directory.systemTemp.createTempSync(
        'studio_patch_verify_failure_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.runAsync(
        () =>
            container.read(fileTreeProvider.notifier).openDirectory(root.path),
      );
      await tester.runAsync(
        () => container.read(studioThreadProvider.notifier).reload(),
      );
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Patch verification failure');
      container.read(studioShellProvider.notifier).openThread(thread.id);
      final patch = ProposedPatchSet(
        id: 'patch-verify-failure-output',
        title: 'Applied patch',
        runId: 'request-applied-failure',
        edits: const [
          ProposedFileEdit(
            path: 'lib/login.dart',
            type: ProposedFileEditType.modify,
            before: 'old',
            after: 'new',
          ),
        ],
        changedFiles: const ['lib/login.dart'],
        applyStatus: PatchApplyStatus.applied,
        verificationRequested: true,
        verificationSuggestions: const [
          'python3 -c "raise SystemExit(\'verify-bad-output\')"',
          'python3 -c "print(\'should-not-run\')"',
        ],
        createdAt: DateTime(2026),
      );
      container.read(patchProposalProvider.notifier).preserveProposal(patch);
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
        () => verifyPatchFromStudio(capturedRef, patch),
      );
      await tester.runAsync(() async {
        for (var i = 0; i < 60; i++) {
          final updated = container.read(studioThreadProvider).selectedThread;
          final turn = updated?.turns.lastOrNull;
          if (turn?.status == StudioTurnStatus.completed) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      });

      expect(result, isNotNull);
      expect(result!.status, StudioSendStatus.sent, reason: result.error);
      final updatedThread = container
          .read(studioThreadProvider)
          .selectedThread!;
      final turn = updatedThread.turns.last;
      expect(turn.intent, TurnIntent.verify);
      expect(turn.status, StudioTurnStatus.completed);
      final commandRuns = container.read(commandRunProvider).values.toList();
      expect(commandRuns, hasLength(1));
      expect(commandRuns.single.status, CommandRunStatus.failed);
      final summary = turn.events
          .where(
            (event) =>
                event.type == StudioTurnEventType.completionSummary &&
                event.detail.contains('Verification failed.'),
          )
          .single
          .detail;
      expect(summary, contains('Failure output:'));
      expect(summary, contains('verify-bad-output'));
      expect(summary, contains('Skipped after first failure:'));
      expect(summary, contains('should-not-run'));
      expect(
        summary,
        contains('Next step: fix the failing command output above'),
      );
      final revisedPatch = container
          .read(patchProposalProvider)
          .history
          .singleWhere((candidate) => candidate.id == patch.id);
      expect(
        revisedPatch.approvalStatus,
        PatchApprovalStatus.revisionRequested,
      );
      expect(revisedPatch.applyStatus, PatchApplyStatus.applied);
      expect(revisedPatch.revisionPrompt, contains('[verification-repair-v1]'));
      expect(revisedPatch.revisionPrompt, contains('verify-bad-output'));
    },
  );

  testWidgets(
    'Failed verification prepares one reviewed repair and verifies the approved revision',
    (tester) async {
      final root = Directory.systemTemp.createTempSync(
        'studio_patch_verify_repair_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final target = File('${root.path}/failure.txt');
      target.writeAsStringSync('broken\n');
      const verificationCommand =
          'python3 -c "from pathlib import Path; assert Path(\'failure.txt\').read_text().startswith(\'fixed\')"';
      final service = AgentService();
      final provider = _ScriptedStudioProvider([
        const [
          ChatChunk(
            toolCallIndex: 0,
            toolCallId: 'inspect-failed-file',
            toolCallName: 'read_file',
            toolCallArguments: '{"path":"failure.txt"}',
          ),
          ChatChunk(isDone: true, finishReason: 'tool_calls'),
        ],
        const [
          ChatChunk(
            toolCallIndex: 0,
            toolCallId: 'repair-patch',
            toolCallName: 'propose_patch',
            toolCallArguments:
                '{"title":"Repair verification failure","summary":"Update the file so the approved check passes.","verification_steps":["python3 -c \\"from pathlib import Path; assert Path(\'failure.txt\').read_text().startswith(\'fixed\')\\""],"files":[{"path":"failure.txt","intent":"Repair failed verification","operation":"modify","before":"broken\\n","content":"fixed\\n"}]}',
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
      await tester.runAsync(
        () => container.read(studioThreadProvider.notifier).reload(),
      );
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Repair verification failure');
      container.read(studioShellProvider.notifier).openThread(thread.id);
      final originalPatch = ProposedPatchSet(
        id: 'patch-verify-repair-original',
        title: 'Initial patch',
        runId: 'request-verify-repair-original',
        edits: const [
          ProposedFileEdit(
            path: 'failure.txt',
            type: ProposedFileEditType.modify,
            before: 'original\n',
            after: 'broken\n',
          ),
        ],
        changedFiles: const ['failure.txt'],
        applyStatus: PatchApplyStatus.applied,
        verificationRequested: true,
        verificationSuggestions: const [verificationCommand],
        createdAt: DateTime(2026),
      );
      container
          .read(patchProposalProvider.notifier)
          .preserveProposal(originalPatch);
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

      final initialVerification = await tester.runAsync(
        () => verifyPatchFromStudio(capturedRef, originalPatch),
      );
      expect(
        initialVerification?.status,
        StudioSendStatus.sent,
        reason: initialVerification?.error,
      );
      await tester.runAsync(() async {
        for (var i = 0; i < 100; i++) {
          final patch = container.read(patchProposalProvider).active;
          final runtime = container.read(agentTurnRuntimeProvider);
          if (provider.messages.length == 2 &&
              !runtime.hasActiveStudioRequest &&
              patch?.title == 'Repair verification failure') {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();

      expect(provider.messages, hasLength(2));
      expect(provider.exposedTools.first, contains('read_file'));
      expect(provider.exposedTools.first, isNot(contains('propose_patch')));
      expect(provider.exposedTools.last, contains('propose_patch'));
      expect(provider.exposedTools.last, isNot(contains('run_command')));
      final failedPatch = container
          .read(patchProposalProvider)
          .history
          .firstWhere((candidate) => candidate.id == originalPatch.id);
      expect(failedPatch.approvalStatus, PatchApprovalStatus.revisionRequested);
      expect(failedPatch.revisionPrompt, contains('[verification-repair-v1]'));
      expect(target.readAsStringSync(), 'broken\n');
      final repairPatch = container.read(patchProposalProvider).active;
      expect(repairPatch, isNotNull);
      expect(repairPatch!.edits.single.after, 'fixed\n');
      expect(repairPatch.verificationRequested, isTrue);
      expect(repairPatch.verificationSuggestions, [verificationCommand]);
      final repairTurn = container
          .read(studioThreadProvider)
          .selectedThread!
          .turns
          .singleWhere((turn) => turn.requestId == repairPatch.runId);
      expect(repairTurn.intent, TurnIntent.code);
      expect(
        repairTurn.events
            .singleWhere(
              (event) => event.type == StudioTurnEventType.userMessage,
            )
            .transcriptVisible,
        isFalse,
      );

      final applyRepair = await tester.runAsync(
        () => container.read(patchProposalProvider.notifier).applyActive(),
      );
      expect(applyRepair?.status, PatchApplyStatus.applied);
      expect(target.readAsStringSync(), 'fixed\n');
      final appliedRepair = container
          .read(patchProposalProvider)
          .history
          .firstWhere((candidate) => candidate.id == repairPatch.id);
      expect(appliedRepair.verificationSuggestions, [verificationCommand]);

      final repairedVerification = await tester.runAsync(
        () => verifyPatchFromStudio(capturedRef, appliedRepair),
      );
      expect(
        repairedVerification?.status,
        StudioSendStatus.sent,
        reason: repairedVerification?.error,
      );
      await tester.runAsync(() async {
        for (var i = 0; i < 100; i++) {
          final turns = container
              .read(studioThreadProvider)
              .selectedThread!
              .turns;
          final latest = turns.singleWhere(
            (turn) => turn.requestId == repairedVerification!.requestId,
          );
          final runs = container.read(commandRunProvider).values;
          if (latest.intent == TurnIntent.verify &&
              latest.status == StudioTurnStatus.completed &&
              runs.length == 2 &&
              runs.last.status == CommandRunStatus.succeeded) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();

      final completedVerification = container
          .read(studioThreadProvider)
          .selectedThread!
          .turns
          .singleWhere(
            (turn) => turn.requestId == repairedVerification!.requestId,
          );
      expect(completedVerification.intent, TurnIntent.verify);
      expect(completedVerification.status, StudioTurnStatus.completed);
      expect(container.read(commandRunProvider).values, hasLength(2));
      expect(
        container.read(commandRunProvider).values.last.status,
        CommandRunStatus.succeeded,
      );
    },
  );

  testWidgets(
    'One Studio task completes code, approved verification repair, and successful re-verification',
    (tester) async {
      final root = Directory.systemTemp.createTempSync(
        'studio_full_edit_verify_task_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final target = File('${root.path}/failure.txt');
      target.writeAsStringSync('old\n');
      const verificationCommand =
          'python3 -c "from pathlib import Path; assert Path(\'failure.txt\').read_text().startswith(\'fixed\')"';
      final service = AgentService();
      final provider = _ScriptedStudioProvider([
        const [
          ChatChunk(
            toolCallIndex: 0,
            toolCallId: 'inspect-initial-file',
            toolCallName: 'read_file',
            toolCallArguments: '{"path":"failure.txt"}',
          ),
          ChatChunk(isDone: true, finishReason: 'tool_calls'),
        ],
        const [
          ChatChunk(
            toolCallIndex: 0,
            toolCallId: 'initial-patch',
            toolCallName: 'propose_patch',
            toolCallArguments:
                '{"title":"Initial failing change","summary":"Prepare the requested change and verify it.","verification_steps":["python3 -c \\"from pathlib import Path; assert Path(\'failure.txt\').read_text().startswith(\'fixed\')\\""],"files":[{"path":"failure.txt","intent":"Fix the failure","operation":"modify","before":"old\\n","content":"broken\\n"}]}',
          ),
          ChatChunk(isDone: true, finishReason: 'tool_calls'),
        ],
        const [
          ChatChunk(
            toolCallIndex: 0,
            toolCallId: 'inspect-repair-file',
            toolCallName: 'read_file',
            toolCallArguments: '{"path":"failure.txt"}',
          ),
          ChatChunk(isDone: true, finishReason: 'tool_calls'),
        ],
        const [
          ChatChunk(
            toolCallIndex: 0,
            toolCallId: 'repaired-patch',
            toolCallName: 'propose_patch',
            toolCallArguments:
                '{"title":"Repair verification failure","summary":"Update the file so the approved check passes.","verification_steps":["python3 -c \\"from pathlib import Path; assert Path(\'failure.txt\').read_text().startswith(\'fixed\')\\""],"files":[{"path":"failure.txt","intent":"Repair failed verification","operation":"modify","before":"broken\\n","content":"fixed\\n"}]}',
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

      final initial = await tester.runAsync(
        () => sendStudioMessage(capturedRef, 'Fix failure.txt and run tests'),
      );
      expect(initial?.status, StudioSendStatus.sent, reason: initial?.error);
      await tester.runAsync(() async {
        for (var i = 0; i < 100; i++) {
          final patch = container.read(patchProposalProvider).active;
          if (provider.messages.length == 2 &&
              !container
                  .read(agentTurnRuntimeProvider)
                  .hasActiveStudioRequest &&
              patch?.title == 'Initial failing change') {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      final initialPatch = container.read(patchProposalProvider).active;
      expect(initialPatch, isNotNull);
      expect(initialPatch!.verificationSuggestions, [verificationCommand]);
      expect(initialPatch.verificationRequested, isTrue);
      expect(
        container
            .read(studioThreadProvider)
            .selectedThread!
            .turns
            .singleWhere((turn) => turn.requestId == initial!.requestId)
            .intent,
        TurnIntent.code,
      );

      final applyInitial = await tester.runAsync(
        () => container.read(patchProposalProvider.notifier).applyActive(),
      );
      expect(applyInitial?.status, PatchApplyStatus.applied);
      expect(target.readAsStringSync(), 'broken\n');
      final appliedInitial = container
          .read(patchProposalProvider)
          .history
          .firstWhere((patch) => patch.id == initialPatch.id);

      final firstVerification = await tester.runAsync(
        () => verifyPatchFromStudio(capturedRef, appliedInitial),
      );
      expect(
        firstVerification?.status,
        StudioSendStatus.sent,
        reason: firstVerification?.error,
      );
      await tester.runAsync(() async {
        for (var i = 0; i < 120; i++) {
          final patch = container.read(patchProposalProvider).active;
          if (provider.messages.length == 4 &&
              !container
                  .read(agentTurnRuntimeProvider)
                  .hasActiveStudioRequest &&
              patch?.title == 'Repair verification failure') {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      final repairPatch = container.read(patchProposalProvider).active;
      expect(repairPatch, isNotNull);
      expect(target.readAsStringSync(), 'broken\n');
      expect(provider.exposedTools[2], contains('read_file'));
      expect(provider.exposedTools[3], contains('propose_patch'));
      expect(provider.exposedTools[3], isNot(contains('run_command')));
      final revisedInitial = container
          .read(patchProposalProvider)
          .history
          .firstWhere((patch) => patch.id == initialPatch.id);
      expect(
        revisedInitial.approvalStatus,
        PatchApprovalStatus.revisionRequested,
      );
      expect(
        revisedInitial.revisionPrompt,
        contains('[verification-repair-v1]'),
      );
      expect(
        container
            .read(patchProposalProvider)
            .history
            .where(
              (patch) =>
                  patch.revisionPrompt?.contains('[verification-repair-v1]') ??
                  false,
            ),
        hasLength(1),
      );

      final applyRepair = await tester.runAsync(
        () => container.read(patchProposalProvider.notifier).applyActive(),
      );
      expect(applyRepair?.status, PatchApplyStatus.applied);
      expect(target.readAsStringSync(), 'fixed\n');
      final appliedRepair = container
          .read(patchProposalProvider)
          .history
          .firstWhere((patch) => patch.id == repairPatch!.id);
      final finalVerification = await tester.runAsync(
        () => verifyPatchFromStudio(capturedRef, appliedRepair),
      );
      expect(
        finalVerification?.status,
        StudioSendStatus.sent,
        reason: finalVerification?.error,
      );
      await tester.runAsync(() async {
        for (var i = 0; i < 100; i++) {
          final runs = container.read(commandRunProvider).values;
          final finalTurn = container
              .read(studioThreadProvider)
              .selectedThread!
              .turns
              .singleWhere(
                (turn) => turn.requestId == finalVerification!.requestId,
              );
          if (runs.length == 2 &&
              runs.first.status == CommandRunStatus.failed &&
              runs.last.status == CommandRunStatus.succeeded &&
              finalTurn.status == StudioTurnStatus.completed) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });

      final completedThread = container
          .read(studioThreadProvider)
          .selectedThread!;
      expect(completedThread.turns, hasLength(4));
      expect(
        completedThread.turns.reversed.map((turn) => turn.intent),
        containsAllInOrder([
          TurnIntent.code,
          TurnIntent.verify,
          TurnIntent.code,
          TurnIntent.verify,
        ]),
      );
      expect(container.read(commandRunProvider).values, hasLength(2));
      expect(
        container.read(commandRunProvider).values.last.status,
        CommandRunStatus.succeeded,
      );
    },
  );

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
          'test -f lib/journey_marker.dart',
        ),
        isTrue,
      );
      expect(
        plan_prompts.isRunnableVerificationCommand('test -f .env'),
        isFalse,
      );
      expect(
        plan_prompts.isRunnableVerificationCommand('test -x lib/main.dart'),
        isFalse,
      );
      expect(
        plan_prompts.isRunnableVerificationCommand(
          'Review the changed files and run the project checks.',
        ),
        isFalse,
      );
      expect(
        plan_prompts.isRunnableVerificationCommand(
          'flutter test test/widget_test.dart',
        ),
        isTrue,
      );
      expect(
        plan_prompts.isRunnableVerificationCommand('flutter test /etc/passwd'),
        isFalse,
      );
      expect(
        plan_prompts.isRunnableVerificationCommand(
          'dart test ../outside_test.dart',
        ),
        isFalse,
      );
      expect(
        plan_prompts.isRunnableVerificationCommand(
          r'npm test -- C:\temp\foo.test.js',
        ),
        isFalse,
      );
    },
  );

  test('Patch verification prompt filters unsafe path-bearing commands', () {
    final patch = ProposedPatchSet(
      id: 'patch-verify-unsafe-paths',
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
        'flutter test /etc/passwd',
        'dart test ../outside_test.dart',
        r'npm test -- C:\temp\foo.test.js',
        'flutter test test/widget_test.dart',
      ],
      verificationRequested: true,
      createdAt: DateTime(2026),
    );

    final prompt = buildPatchVerificationPrompt(patch);

    expect(prompt, contains('- flutter test test/widget_test.dart'));
    expect(prompt, isNot(contains('/etc/passwd')));
    expect(prompt, isNot(contains('../outside_test.dart')));
    expect(prompt, isNot(contains(r'C:\temp\foo.test.js')));
  });

  test(
    'Applied verification-requested patches offer verification action once',
    () {
      final patch = ProposedPatchSet(
        id: 'patch-verify-action',
        title: 'Fix login',
        edits: const [],
        changedFiles: const ['lib/login.dart'],
        applyStatus: PatchApplyStatus.applied,
        verificationRequested: true,
        verificationRequestId: 'request-verify-action',
        verificationSuggestions: const ['flutter analyze'],
        createdAt: DateTime(2026),
      );

      expect(shouldOfferPatchVerification(patch), isFalse);
      expect(
        shouldOfferPatchVerification(
          patch.copyWith(verificationRequestId: null),
        ),
        isTrue,
      );
      final restored = ProposedPatchSet.fromJson(patch.toJson())!;
      expect(restored.verificationRequestId, 'request-verify-action');
      expect(shouldOfferPatchVerification(restored), isFalse);
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
    },
  );

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

    expect(find.text('New chat'), findsOneWidget);
    expect(find.text('Where should we start?'), findsOneWidget);
    final homeTitle = tester.widget<Text>(find.text('Where should we start?'));
    expect(homeTitle.style?.fontSize, FontSizes.lg);
    expect(homeTitle.style?.fontWeight, FontWeight.w600);
    expect(find.text('No project selected'), findsOneWidget);
    expect(find.text('Open project folder'), findsOneWidget);
    expect(
      find.textContaining('Circuit will only create a project'),
      findsOneWidget,
    );
    expect(find.text('Start with'), findsOneWidget);
    expect(find.text('Ask, plan, or describe work'), findsOneWidget);
    expect(find.text('Review first'), findsOneWidget);
    expect(find.text('Plan'), findsWidgets);
    expect(find.text('Default permissions'), findsNothing);
    expect(find.text('gpt-5-nano'), findsOneWidget);
    expect(find.text('In 50.0M left / Out 5.0M left'), findsOneWidget);
    expect(find.byTooltip('Open project folder'), findsOneWidget);
    final openProjectButton = find.ancestor(
      of: find.text('Open project folder'),
      matching: find.byType(OutlinedButton),
    );
    expect(
      find.descendant(
        of: openProjectButton,
        matching: find.byIcon(Icons.folder_open_outlined),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Forward'), findsOneWidget);
    expect(find.text('Work locally'), findsNothing);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Plugins'), findsNothing);
    expect(find.text('Automations'), findsNothing);
    expect(find.text('Circuit mobile'), findsNothing);
    expect(find.byTooltip('Enterprise specialist'), findsNothing);
    expect(find.text('Topology'), findsNothing);
    expect(find.text('Sizing'), findsNothing);
    expect(find.text('Lifecycle'), findsNothing);
    expect(find.byTooltip('Add context'), findsOneWidget);
    final addContextIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byTooltip('Add context'),
        matching: find.byIcon(Icons.add),
      ),
    );
    expect(addContextIcon.size, 14);
    expect(find.byTooltip('Voice input'), findsNothing);

    final newChatText = tester.widget<Text>(find.text('New chat'));
    expect(newChatText.style?.fontSize, FontSizes.sm);
    final searchText = tester.widget<Text>(find.text('Search'));
    expect(searchText.style?.fontSize, FontSizes.sm);
    final openProjectIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byTooltip('Open project folder'),
        matching: find.byIcon(Icons.folder_open_outlined),
      ),
    );
    expect(openProjectIcon.size, 14);

    await tester.tap(find.text('Search'));
    await tester.pump();
    expect(find.byTooltip('Close search'), findsOneWidget);
    expect(find.widgetWithIcon(IconButton, Icons.close), findsNothing);
    final closeSearchTooltip = find.byTooltip('Close search');
    final closeSearchIcon = tester.widget<Icon>(
      find.descendant(
        of: closeSearchTooltip,
        matching: find.byIcon(Icons.close),
      ),
    );
    expect(closeSearchIcon.size, 14);
    final closeSearchContainer = tester.widget<Container>(
      find
          .descendant(of: closeSearchTooltip, matching: find.byType(Container))
          .first,
    );
    final closeSearchDecoration = closeSearchContainer.decoration;
    expect(closeSearchDecoration, isA<BoxDecoration>());
    expect(
      (closeSearchDecoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(6),
    );
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
    expect(find.byTooltip('Check Circuit AI connection'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.byTooltip('Choose model'), findsOneWidget);
    final modelText = tester.widget<Text>(find.text('gpt-5-nano').first);
    expect(modelText.style?.fontSize, FontSizes.xs);

    await tester.tap(find.byTooltip('Choose model'));
    await tester.pumpAndSettle();
    expect(find.text('gemini-3.1-flash-lite').last, findsOneWidget);
    final menuModelText = tester.widget<Text>(find.text('gpt-5-nano').last);
    expect(menuModelText.style?.fontSize, FontSizes.xs);
    await tester.tap(find.text('gemini-3.1-flash-lite').last);
    await tester.pumpAndSettle();
    expect(
      container.read(settingsProvider).ciscoModel,
      'gemini-3.1-flash-lite',
    );

    expect(container.read(settingsProvider).thinkingMode, false);
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Turn thinking mode on'), findsOneWidget);
    await tester.tap(find.byTooltip('Turn thinking mode on'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).thinkingMode, true);
    expect(find.byTooltip('Turn thinking mode off'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Approval scope'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Approval scope'), findsOneWidget);
    expect(find.text('Auto approve'), findsNothing);
    expect(find.text('Advanced Editor'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Keyboard'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Send behavior'), findsOneWidget);
    expect(find.textContaining('Command palette'), findsOneWidget);
    expect(container.read(settingsProvider).sendOnEnter, isTrue);
    await tester.tap(find.byTooltip('Toggle whether Enter sends prompts'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).sendOnEnter, isFalse);
    expect(
      find.text('Shift+Enter sends a prompt; Enter inserts a new line.'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text('Diagnostics and privacy'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Retention: 14 days'), findsOneWidget);
    expect(find.text('Export redacted bundle'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Thread history recovery'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Repair history'), findsOneWidget);
    expect(find.text('Export recovery files'), findsOneWidget);
  });

  testWidgets('Studio hands off a completed background task from any view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final task = container
        .read(agentWorkspaceProvider.notifier)
        .startTask(goal: 'Check the deployment');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioShell())),
      ),
    );

    // The user opened the task, then left it before its background work
    // finished. The completion notice must still preserve the handoff.
    container.read(studioShellProvider.notifier).openTask(task.id);
    await tester.pump();
    container.read(studioShellProvider.notifier).openHome();
    await tester.pump();

    container
        .read(agentWorkspaceProvider.notifier)
        .completeTask(task.id, result: 'Deployment checks passed.');
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
        'Benny completed: Check the deployment. Open the task to review the result.',
      ),
      findsOneWidget,
    );
    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
    await tester.pumpAndSettle();
    expect(container.read(studioShellProvider).selectedTaskId, task.id);
    expect(container.read(studioShellProvider).mode, StudioMode.task);
  });

  testWidgets('Studio dispatches queued background tasks in workspace order', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1728, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = Directory.systemTemp.createTempSync(
      'studio_background_dispatch_',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: background_dispatch_fixture
environment:
  sdk: ^3.0.0
''');
    File('${root.path}/README.md').writeAsStringSync('Background queue.');
    final service = AgentService();
    final provider = _ScriptedStudioProvider([
      const [
        ChatChunk(content: 'First background result.'),
        ChatChunk(isDone: true, finishReason: 'stop'),
      ],
      const [
        ChatChunk(content: 'Second background result.'),
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
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioShell())),
      ),
    );
    await tester.runAsync(
      () => container.read(agentWorkspaceProvider.notifier).reload(),
    );
    await tester.pump();
    expect(container.read(agentWorkspaceProvider).isLoading, isFalse);

    final controller = container.read(agentWorkspaceProvider.notifier);
    final first = controller.startTask(
      goal: 'Inspect the first background item',
      backgroundExecutionRequested: true,
    );
    final second = controller.startTask(
      goal: 'Inspect the second background item',
      backgroundExecutionRequested: true,
    );
    expect(first.status, AgentTaskStatus.running);
    expect(second.status, AgentTaskStatus.queued);

    await tester.pump();
    for (var attempt = 0; attempt < 30; attempt++) {
      if (container
          .read(agentWorkspaceProvider)
          .tasks
          .every((task) => task.status == AgentTaskStatus.completed)) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
    }

    final tasks = container.read(agentWorkspaceProvider).tasks;
    expect(tasks, hasLength(2));
    expect(
      tasks.map((task) => task.status),
      everyElement(AgentTaskStatus.completed),
      reason: tasks
          .map(
            (task) =>
                '${task.goal}: ${task.status.name} (${task.activeRunId ?? 'idle'})',
          )
          .join('; '),
    );
    expect(tasks.map((task) => task.activeRunId), everyElement(isNull));
    expect(provider.messages, hasLength(2));
    expect(
      container
          .read(studioThreadProvider)
          .threads
          .where((thread) => thread.taskId == first.id)
          .single
          .turns
          .single
          .status,
      StudioTurnStatus.completed,
    );
    expect(
      container
          .read(studioThreadProvider)
          .threads
          .where((thread) => thread.taskId == second.id)
          .single
          .turns
          .single
          .status,
      StudioTurnStatus.completed,
    );
  });

  testWidgets('Studio background work survives leaving its task view', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1728, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = Directory.systemTemp.createTempSync(
      'studio_background_leave_task_',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: background_leave_task_fixture
environment:
  sdk: ^3.0.0
''');
    final service = AgentService();
    final provider = _GatedStudioProvider([
      const [
        ChatChunk(content: 'Background result after leaving the task.'),
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
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioShell())),
      ),
    );
    await tester.runAsync(
      () => container.read(agentWorkspaceProvider.notifier).reload(),
    );
    final task = container
        .read(agentWorkspaceProvider.notifier)
        .startTask(
          goal: 'Continue after the task view is closed',
          backgroundExecutionRequested: true,
        );
    for (
      var attempt = 0;
      attempt < 30 && !provider.started.isCompleted;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
    }
    expect(provider.started.isCompleted, isTrue);

    container.read(studioShellProvider.notifier).openTask(task.id);
    await tester.pump();
    expect(container.read(studioShellProvider).mode, StudioMode.task);
    container.read(studioShellProvider.notifier).openHome();
    await tester.pump();
    expect(container.read(studioShellProvider).mode, StudioMode.home);

    provider.complete();
    for (var attempt = 0; attempt < 30; attempt++) {
      if (container.read(agentWorkspaceProvider).tasks.single.status ==
          AgentTaskStatus.completed) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
    }

    final completed = container.read(agentWorkspaceProvider).tasks.single;
    expect(completed.status, AgentTaskStatus.completed);
    expect(completed.result, contains('Background result'));
    expect(
      container
          .read(studioThreadProvider)
          .threads
          .singleWhere((thread) => thread.taskId == task.id)
          .turns
          .single
          .status,
      StudioTurnStatus.completed,
    );
  });

  testWidgets(
    'a claimed background task waits instead of failing when Studio becomes busy',
    (tester) async {
      final root = Directory.systemTemp.createTempSync(
        'studio_background_busy_fixture_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: background_busy_fixture
environment:
  sdk: ^3.0.0
''');
      final service = AgentService();
      final provider = _GatedStudioProvider([
        const [
          ChatChunk(content: 'Foreground work completed.'),
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
        () =>
            container.read(fileTreeProvider.notifier).openDirectory(root.path),
      );
      await tester.runAsync(
        () => container.read(agentWorkspaceProvider.notifier).reload(),
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

      final task = container
          .read(agentWorkspaceProvider.notifier)
          .startTask(
            goal: 'Wait safely for the single Studio execution lane.',
            backgroundExecutionRequested: true,
          );
      final claimId = container
          .read(agentWorkspaceProvider.notifier)
          .claimBackgroundExecution(task.id);
      expect(claimId, isNotNull);

      final foreground = await tester.runAsync(
        () => sendStudioMessage(capturedRef, 'Keep Studio occupied.'),
      );
      expect(foreground?.status, StudioSendStatus.sent);
      for (
        var attempt = 0;
        attempt < 30 && !provider.started.isCompleted;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 25));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      expect(provider.started.isCompleted, isTrue);

      final deferred = await tester.runAsync(
        () => sendStudioMessage(
          capturedRef,
          task.goal,
          taskId: task.id,
          finishTask: true,
          deferTaskWhenStudioBusy: true,
        ),
      );
      expect(deferred?.status, StudioSendStatus.blocked);
      expect(deferred?.blockedByActiveRequest, isTrue);
      final waiting = container
          .read(agentWorkspaceProvider)
          .tasks
          .singleWhere((candidate) => candidate.id == task.id);
      expect(waiting.status, AgentTaskStatus.running);
      expect(waiting.activeRunId, claimId);

      expect(
        container
            .read(agentWorkspaceProvider.notifier)
            .releaseBackgroundExecutionClaim(task.id, claimId!),
        isTrue,
      );
      final released = container
          .read(agentWorkspaceProvider)
          .tasks
          .singleWhere((candidate) => candidate.id == task.id);
      expect(released.status, AgentTaskStatus.running);
      expect(released.activeRunId, isNull);

      provider.complete();
      await tester.runAsync(() async {
        for (
          var attempt = 0;
          attempt < 30 &&
              container.read(agentTurnRuntimeProvider).hasActiveStudioRequest;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
    },
  );

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
    container.read(studioThreadProvider);
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.runAsync(
      () => container.read(fileTreeProvider.notifier).openDirectory(root.path),
    );
    await tester.runAsync(
      () => container.read(studioThreadProvider.notifier).reload(),
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

  testWidgets('Studio rail collapses long project histories', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final root = Directory.systemTemp.createTempSync(
      'studio_rail_collapsed_history_',
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

    StudioThread? oldestThread;
    for (var index = 1; index <= 12; index += 1) {
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Rail thread $index');
      oldestThread ??= thread;
    }
    container
        .read(studioThreadProvider.notifier)
        .selectThread(oldestThread!.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioLeftRail())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rail thread 12'), findsOneWidget);
    expect(find.text('Rail thread 1'), findsOneWidget);
    expect(find.text('Rail thread 4'), findsNothing);
    expect(find.text('Show 3 more'), findsOneWidget);
    final historyToggle = find.byKey(
      const ValueKey('studio-rail-history-toggle'),
    );
    expect(
      tester.getSemantics(historyToggle),
      isSemantics(
        label: 'Show 3 more',
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(historyToggle);
    await tester.pumpAndSettle();

    expect(find.text('Rail thread 4'), findsOneWidget);
    expect(find.text('Show fewer'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Show 3 more'), findsOneWidget);
    await flushStudioThreadPersist(tester);
  });

  test('Studio rail uses compact status indicators only when needed', () {
    expect(
      studioRailShouldShowStatusIndicator(
        const TaskDisplayState(kind: TaskDisplayKind.done, label: 'Done'),
      ),
      isFalse,
    );
    expect(
      studioRailShouldShowStatusIndicator(
        const TaskDisplayState(kind: TaskDisplayKind.idle, label: 'Ready'),
      ),
      isFalse,
    );
    expect(
      studioRailShouldShowStatusIndicator(
        const TaskDisplayState(
          kind: TaskDisplayKind.queued,
          label: 'Queued',
          isActive: true,
        ),
      ),
      isTrue,
    );
    expect(
      studioRailShouldShowStatusIndicator(
        const TaskDisplayState(
          kind: TaskDisplayKind.working,
          label: 'Working',
          isActive: true,
        ),
      ),
      isTrue,
    );
    expect(
      studioRailShouldShowStatusIndicator(
        const TaskDisplayState(
          kind: TaskDisplayKind.failed,
          label: 'Failed',
          needsAttention: true,
        ),
      ),
      isTrue,
    );
    expect(
      studioRailShouldShowStatusIndicator(
        const TaskDisplayState(
          kind: TaskDisplayKind.waitingForApproval,
          label: 'Waiting',
          isActive: true,
          needsAttention: true,
        ),
      ),
      isTrue,
    );
    expect(
      studioRailShouldShowStatusIndicator(
        const TaskDisplayState(
          kind: TaskDisplayKind.continuationReady,
          label: 'Continue',
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
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    final slashStatusText = tester.widget<Text>(find.text('Status'));
    expect(slashStatusText.style?.fontSize, FontSizes.xs);
    expect(slashStatusText.style?.fontWeight, FontWeight.w600);
    final slashStatusDetail = tester.widget<Text>(
      find.text('Summarize project state'),
    );
    expect(slashStatusDetail.style?.fontSize, FontSizes.xxs);
    final slashStatusIcon = tester.widget<Icon>(
      find.byIcon(Icons.radio_button_checked).last,
    );
    expect(slashStatusIcon.size, 14);

    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();
    expect(
      container.read(studioShellProvider).composerText,
      'Summarize the current project status, branch, changes, and risks.',
    );

    await tester.enterText(find.byType(TextField).first, '/init');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Initialize'));
    await tester.pumpAndSettle();
    expect(
      container.read(studioShellProvider).composerText,
      'Inspect this project and explain its structure and best next steps.',
    );

    await tester.enterText(find.byType(TextField).first, '/');
    await tester.pumpAndSettle();
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
    expect(find.text('Research'), findsOneWidget);
    expect(find.text('Code'), findsWidgets);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Fix'), findsNothing);
    final askMenuText = tester.widget<Text>(find.text('Ask'));
    expect(askMenuText.style?.fontSize, FontSizes.xs);
    expect(askMenuText.style?.fontWeight, FontWeight.w500);
    await tester.tap(find.text('Research'));
    await tester.pumpAndSettle();
    expect(
      container.read(studioShellProvider).promptMode,
      StudioPromptMode.research,
    );
    await tester.tap(find.byTooltip('Task mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Choose model'));
    await tester.pumpAndSettle();
    expect(find.text('gemini-3.1-flash-lite'), findsOneWidget);
    expect(find.textContaining('120.0K context'), findsWidgets);
    final modelMenuText = tester.widget<Text>(
      find.text('gemini-3.1-flash-lite'),
    );
    expect(modelMenuText.style?.fontSize, FontSizes.xs);
    final modelMetaText = tester.widget<Text>(
      find.textContaining('120.0K context').first,
    );
    expect(modelMetaText.style?.fontSize, FontSizes.xxs);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Execution mode'));
    await tester.pumpAndSettle();
    expect(find.text('Local project'), findsOneWidget);
    final executionText = tester.widget<Text>(find.text('Local project'));
    expect(executionText.style?.fontSize, FontSizes.xs);
    expect(executionText.style?.fontWeight, FontWeight.w600);
    expect(find.text('Isolated worktree'), findsOneWidget);
    expect(
      find.text('Create a task branch and keep its files separate'),
      findsOneWidget,
    );
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

  testWidgets('Studio composer honors the Shift+Enter send preference', (
    tester,
  ) async {
    String? submitted;
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(_ShiftEnterSettingsNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
    expect(submitted, isNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(submitted, 'hello circuit');
  });

  testWidgets(
    'Studio composer exposes a visible cancel control for an active request',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Active request');
      container
          .read(studioThreadProvider.notifier)
          .markPhase(
            thread.id,
            status: StudioThreadStatus.streaming,
            phase: StudioSendPhase.streaming,
            requestId: 'active-request',
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: StudioPromptComposer(
                hintText: 'Ask Circuit',
                onSubmit: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.byTooltip('Cancel active request (Esc)'), findsOneWidget);
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    },
  );

  testWidgets('Studio composer typography and icons match compact scale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 220));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 720,
                child: StudioPromptComposer(
                  hintText: 'Ask for follow-up changes',
                  onSubmit: (_) {},
                  compact: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.style?.fontSize, FontSizes.md);
    expect(field.style?.height, 1.22);
    expect(field.decoration?.border, InputBorder.none);

    final hintStyle = field.decoration?.hintStyle;
    expect(hintStyle?.fontSize, FontSizes.md);
    expect(hintStyle?.height, 1.22);

    final reviewText = tester.widget<Text>(find.text('Review first'));
    expect(reviewText.style?.fontSize, FontSizes.xs);
    expect(reviewText.style?.fontWeight, FontWeight.w500);

    final planText = tester.widget<Text>(find.text('Plan'));
    expect(planText.style?.fontSize, FontSizes.xs);

    expect(find.byTooltip('Add context'), findsOneWidget);
    final addIcon = tester.widget<Icon>(find.byIcon(Icons.add));
    expect(addIcon.size, 14);

    final reviewIcon = tester.widget<Icon>(
      find.byIcon(Icons.back_hand_outlined),
    );
    expect(reviewIcon.size, 12);

    final sendIcon = tester.widget<Icon>(find.byIcon(Icons.arrow_upward));
    expect(sendIcon.size, 16);

    final sendButton = tester.widget<Container>(
      find
          .ancestor(
            of: find.byIcon(Icons.arrow_upward),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(sendButton.constraints?.minWidth, 28);
    expect(sendButton.constraints?.maxWidth, 28);
    expect(sendButton.constraints?.minHeight, 28);
    expect(sendButton.constraints?.maxHeight, 28);

    await tester.tap(find.byTooltip('Add context'));
    await tester.pump();
    expect(container.read(studioShellProvider).rightProgressPanelVisible, true);
    expect(
      container.read(studioRightDrawerProvider).mode,
      StudioDrawerMode.context,
    );
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

    expect(find.text('Plan accepted. Implementation started.'), findsOneWidget);
    expect(find.text('Implement this plan'), findsNothing);
    expect(
      find.text('No, and tell Circuit what to do differently'),
      findsNothing,
    );
    expect(find.text('Dismiss'), findsNothing);
    expect(find.text('Submit'), findsNothing);
    expect(find.text('Expand plan'), findsOneWidget);

    await tester.tap(find.text('Expand plan'));
    await tester.pump();
    expect(find.text('Collapse plan'), findsOneWidget);

    await tester.tap(find.text('Collapse plan'));
    await tester.pump();
    expect(find.text('Expand plan'), findsOneWidget);
  });

  testWidgets(
    'Continuation card renders from persisted turn without patch history',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Partial accepted plan');
      final now = DateTime(2026);
      const acceptedPlan = AcceptedPlanContext(
        patchSetId: 'plan-fallback',
        title: 'Two batch plan',
        summary: 'Create the greeting and documentation.',
        markdown: '# Plan\n\n- Create hello.txt\n- Create README.md',
        plannedFiles: [
          'hello.txt — Add greeting',
          'README.md — Document usage',
        ],
      );
      final turn = StudioTurn(
        id: 'turn-continuation-fallback',
        threadId: thread.id,
        requestId: 'request-continuation-fallback',
        userMessageId: 'message-continuation-fallback',
        prompt: 'Implement accepted plan',
        model: 'gpt-5-nano',
        contextSummary: const StudioContextSummary(projectLabel: 'project'),
        status: StudioTurnStatus.completed,
        intent: TurnIntent.code,
        acceptedPlanState: AcceptedPlanState.patchProposed,
        acceptedPlanContext: acceptedPlan,
        planTargetProgress: [
          PlanTargetProgress(
            path: 'hello.txt',
            intent: 'Add greeting',
            operation: ProposedFileEditType.create,
            state: PlanTargetProgressState.applied,
            patchSetId: 'patch-first-batch',
            updatedAt: now,
          ),
          PlanTargetProgress(
            path: 'README.md',
            intent: 'Document usage',
            operation: ProposedFileEditType.create,
            updatedAt: now,
          ),
        ],
        steps: [
          TurnStepRecord(
            step: TurnStep.continuation,
            status: TurnStepStatus.queued,
            title: 'Continue next batch',
            detail:
                '1 accepted-plan target still needs work. Remaining: README.md. Use Continue next batch to keep implementing the accepted plan.',
            startedAt: now,
          ),
        ],
        events: [
          StudioTurnEvent.completionSummary(
            id: 'patch-transaction-fallback-applied',
            turnId: 'turn-continuation-fallback',
            requestId: 'request-continuation-fallback',
            threadId: thread.id,
            title: 'Applied changes',
            detail:
                'Applied 1 files.\nNext batch: 1 accepted-plan target still needs work (README.md). Use Continue next batch to keep implementing the accepted plan.',
          ),
        ],
        createdAt: now,
        updatedAt: now,
        completedAt: now,
      );
      container
          .read(studioThreadProvider.notifier)
          .upsertTurn(thread.id, turn, select: true);

      expect(
        container.read(studioThreadProvider).selectedThread!.status,
        StudioThreadStatus.continuationReady,
      );
      expect(container.read(patchProposalProvider).history, isEmpty);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
        ),
      );
      await tester.pump();

      expect(find.text('Next batch available'), findsOneWidget);
      expect(
        find.textContaining('Plan progress: 1/2 targets applied'),
        findsOneWidget,
      );
      expect(find.textContaining('README.md'), findsWidgets);
      expect(find.text('Continue next batch'), findsWidgets);
    },
  );

  testWidgets('Completed accepted plan renders terminal plan progress', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Completed accepted plan');
    final now = DateTime(2026);
    final plan = container
        .read(patchProposalProvider.notifier)
        .propose(
          title: 'Two target plan',
          edits: const [],
          runId: 'request-complete-plan',
          planMarkdown: '# Plan\n\n- Create hello.txt\n- Create README.md',
          plannedFiles: const [
            'hello.txt — Add greeting',
            'README.md — Document usage',
          ],
        );
    container.read(patchProposalProvider.notifier).markPlanAccepted(plan.id);
    final turn = StudioTurn(
      id: 'turn-complete-plan',
      threadId: thread.id,
      requestId: 'request-complete-plan',
      userMessageId: 'message-complete-plan',
      prompt: 'Implement accepted plan',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      intent: TurnIntent.code,
      acceptedPlanState: AcceptedPlanState.implemented,
      acceptedPlanContext: AcceptedPlanContext(
        patchSetId: plan.id,
        title: 'Two target plan',
        summary: 'Create the greeting and documentation.',
        markdown: '# Plan\n\n- Create hello.txt\n- Create README.md',
        plannedFiles: const [
          'hello.txt — Add greeting',
          'README.md — Document usage',
        ],
      ),
      planTargetProgress: [
        PlanTargetProgress(
          path: 'hello.txt',
          intent: 'Add greeting',
          operation: ProposedFileEditType.create,
          state: PlanTargetProgressState.applied,
          patchSetId: 'patch-complete',
          updatedAt: now,
        ),
        PlanTargetProgress(
          path: 'README.md',
          intent: 'Document usage',
          operation: ProposedFileEditType.create,
          state: PlanTargetProgressState.applied,
          patchSetId: 'patch-complete',
          updatedAt: now,
        ),
      ],
      events: [
        StudioTurnEvent.completionSummary(
          id: 'patch-transaction-complete-applied',
          turnId: 'turn-complete-plan',
          requestId: 'request-complete-plan',
          threadId: thread.id,
          title: 'Applied changes',
          detail:
              'Applied 2 files.\n'
              'Accepted plan progress: all planned targets are complete.',
        ),
      ],
      createdAt: now,
      updatedAt: now,
      completedAt: now,
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
    await tester.pump();

    expect(
      find.textContaining('Plan progress: all 2 targets complete'),
      findsOneWidget,
    );
    expect(find.text('Applied'), findsWidgets);
    expect(find.textContaining('hello.txt'), findsWidgets);
    expect(find.textContaining('README.md'), findsWidgets);
    expect(find.text('Next batch available'), findsNothing);
    expect(find.text('Continue next batch'), findsNothing);
    expect(find.text('Implement this plan?'), findsNothing);
    expect(find.text('Yes, implement this plan'), findsNothing);
    expect(find.text('Plan accepted. Implementation started.'), findsOneWidget);
    expect(find.textContaining('Accepted plan progress'), findsOneWidget);
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

    expect(find.text('Plan accepted. Implementation started.'), findsOneWidget);
    expect(find.text('Dismiss'), findsNothing);

    final state = container.read(patchProposalProvider);
    final dismissedOldPlan = state.history.firstWhere(
      (patch) => patch.id == oldPlan.id,
    );
    final stillActivePlan = state.history.firstWhere(
      (patch) => patch.id == activePlan.id,
    );
    expect(dismissedOldPlan.approvalStatus, PatchApprovalStatus.approved);
    expect(dismissedOldPlan.applyStatus, isNull);
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

  testWidgets('Inline artifact card Review opens text artifacts in code mode', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final root = Directory.systemTemp.createTempSync(
      'studio-inline-artifact-review-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final file = File('${root.path}/report.md')..writeAsStringSync('# Report');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final threadController = container.read(studioThreadProvider.notifier);
    final thread = threadController.createBlankThread(title: 'Artifact review');
    const turnId = 'turn-inline-artifact-review';
    const requestId = 'request-inline-artifact-review';
    final artifact = GeneratedArtifact(
      id: 'inline-markdown',
      kind: GeneratedArtifactKind.markdown,
      status: GeneratedArtifactStatus.ready,
      fileName: 'report.md',
      filePath: file.path,
      summary: 'Created a Markdown report.',
      byteSize: file.lengthSync(),
      threadId: thread.id,
      requestId: requestId,
      createdAt: DateTime(2026),
    );
    final sourceArtifact = artifact.toSourceArtifact();
    final turn = StudioTurn(
      id: turnId,
      threadId: thread.id,
      requestId: requestId,
      userMessageId: 'message-inline-artifact-review',
      prompt: 'create a markdown report',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.assistantMessage(
          turnId: turnId,
          requestId: requestId,
          threadId: thread.id,
          content: 'Created the report artifact.',
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    threadController.upsertTurn(thread.id, turn, select: true);
    threadController.upsertSourceArtifact(thread.id, sourceArtifact);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );
    await tester.pump();

    expect(find.text('report.md'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);

    await tester.tap(find.text('Review'));
    await tester.pump();

    final drawer = container.read(studioRightDrawerProvider);
    expect(drawer.mode, StudioDrawerMode.code);
    expect(drawer.filePath, file.path);
  });

  testWidgets('Inline artifact card Open and Reveal dispatch file paths', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final root = Directory.systemTemp.createTempSync(
      'studio-inline-artifact-open-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final file = File('${root.path}/proposal.pptx')
      ..writeAsBytesSync([1, 2, 3]);
    final launched = <Uri>[];

    final container = ProviderContainer(
      overrides: [
        artifactLaunchProvider.overrideWithValue((uri) async {
          launched.add(uri);
          return true;
        }),
      ],
    );
    addTearDown(container.dispose);
    final threadController = container.read(studioThreadProvider.notifier);
    final thread = threadController.createBlankThread(title: 'Artifact open');
    const turnId = 'turn-inline-artifact-open';
    const requestId = 'request-inline-artifact-open';
    final artifact = GeneratedArtifact(
      id: 'inline-pptx',
      kind: GeneratedArtifactKind.powerPoint,
      status: GeneratedArtifactStatus.ready,
      fileName: 'proposal.pptx',
      filePath: file.path,
      summary: 'Created a PowerPoint deck.',
      byteSize: file.lengthSync(),
      threadId: thread.id,
      requestId: requestId,
      createdAt: DateTime(2026),
    );
    final turn = StudioTurn(
      id: turnId,
      threadId: thread.id,
      requestId: requestId,
      userMessageId: 'message-inline-artifact-open',
      prompt: 'create a deck',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.assistantMessage(
          turnId: turnId,
          requestId: requestId,
          threadId: thread.id,
          content: 'Created the deck artifact.',
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    threadController.upsertTurn(thread.id, turn, select: true);
    threadController.upsertSourceArtifact(
      thread.id,
      artifact.toSourceArtifact(),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Open'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Reveal'));
    await tester.pump();

    expect(launched.map((uri) => uri.toFilePath()), [file.path, root.path]);
  });

  testWidgets('Artifact card compares parent and regenerated child versions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final threadController = container.read(studioThreadProvider.notifier);
    final thread = threadController.createBlankThread(title: 'Version compare');
    const turnId = 'turn-artifact-version-compare';
    const requestId = 'request-artifact-version-compare';
    final parent = GeneratedArtifact(
      id: 'artifact-v1',
      kind: GeneratedArtifactKind.docx,
      status: GeneratedArtifactStatus.ready,
      fileName: 'review.docx',
      filePath: '/workspace/outputs/review.docx',
      summary: 'First report version.',
      byteSize: 1024,
      threadId: thread.id,
      requestId: requestId,
      createdAt: DateTime(2026),
      outputHash: 'aaaaaaaaaaaa',
    );
    final child = GeneratedArtifact(
      id: 'artifact-v2',
      kind: GeneratedArtifactKind.pdf,
      status: GeneratedArtifactStatus.ready,
      fileName: 'review-v2.pdf',
      filePath: '/workspace/outputs/review-v2.pdf',
      summary: 'Regenerated PDF version.',
      byteSize: 2048,
      threadId: thread.id,
      requestId: requestId,
      createdAt: DateTime(2026, 1, 2),
      version: 2,
      parentArtifactId: parent.id,
      outputHash: 'bbbbbbbbbbbb',
      generationRecipe: const ArtifactGenerationRecipe(
        prompt: 'Create an architecture review report',
        sourceContent: '# Review',
        compositionHash: 'cccccccccccc',
      ),
    );
    final turn = StudioTurn(
      id: turnId,
      threadId: thread.id,
      requestId: requestId,
      userMessageId: 'message-artifact-version-compare',
      prompt: 'create report',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.assistantMessage(
          turnId: turnId,
          requestId: requestId,
          threadId: thread.id,
          content: 'Created the regenerated report artifact.',
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    threadController.upsertTurn(thread.id, turn, select: true);
    threadController.upsertSourceArtifact(thread.id, parent.toSourceArtifact());
    threadController.upsertSourceArtifact(thread.id, child.toSourceArtifact());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Compare'));
    await tester.pumpAndSettle();

    expect(find.text('Artifact version comparison'), findsOneWidget);
    expect(find.text('review.docx'), findsWidgets);
    expect(find.text('review-v2.pdf'), findsWidgets);
    expect(find.text('v1'), findsOneWidget);
    expect(find.text('v2'), findsOneWidget);
  });

  testWidgets('Artifact-backed table responses collapse to outcome summary', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final root = Directory.systemTemp.createTempSync(
      'studio-artifact-table-collapse-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final file = File('${root.path}/customer_inventory.xlsx')
      ..writeAsBytesSync([80, 75, 3, 4]);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final threadController = container.read(studioThreadProvider.notifier);
    final thread = threadController.createBlankThread(title: 'Excel artifact');
    const turnId = 'turn-artifact-table-collapse';
    const requestId = 'request-artifact-table-collapse';
    final artifact = GeneratedArtifact(
      id: 'customer-inventory',
      kind: GeneratedArtifactKind.excel,
      status: GeneratedArtifactStatus.ready,
      fileName: 'customer_inventory.xlsx',
      filePath: file.path,
      summary: 'Created an Excel workbook.',
      byteSize: file.lengthSync(),
      previewRows: const [
        ['Product', 'Count', 'Status'],
        ['AIR-AP2802I-B-K9', '41', 'Active'],
      ],
      sheetCount: 1,
      threadId: thread.id,
      requestId: requestId,
      createdAt: DateTime(2026),
    );
    final tableRows = List.generate(
      12,
      (index) => '| AIR-AP2802I-B-K9-$index | Serial-$index | Active |',
    ).join('\n');
    final turn = StudioTurn(
      id: turnId,
      threadId: thread.id,
      requestId: requestId,
      userMessageId: 'message-artifact-table-collapse',
      prompt: 'create an Excel file from this inventory',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.assistantMessage(
          turnId: turnId,
          requestId: requestId,
          threadId: thread.id,
          content:
              'I created the Excel-ready inventory artifact.\n\n'
              '| Product | Serial | Status |\n'
              '| --- | --- | --- |\n'
              '$tableRows',
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    threadController.upsertTurn(thread.id, turn, select: true);
    threadController.upsertSourceArtifact(
      thread.id,
      artifact.toSourceArtifact(),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );
    await tester.pump();

    expect(find.text('customer_inventory.xlsx'), findsOneWidget);
    expect(find.textContaining('Created an Excel workbook.'), findsWidgets);
    expect(find.textContaining('AIR-AP2802I-B-K9-11'), findsNothing);
    expect(find.textContaining('| Product | Serial | Status |'), findsNothing);
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

  testWidgets('Empty failed thread updates from generic empty text to error', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'hi');
    container.read(studioThreadProvider.notifier).fail(thread.id, '');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    expect(
      find.text('No saved turns yet. Start a follow-up below.'),
      findsOneWidget,
    );

    container
        .read(studioThreadProvider.notifier)
        .fail(thread.id, 'AI is not connected. Reconnect before sending.');
    await tester.pump();

    expect(
      find.text('AI is not connected. Reconnect before sending.'),
      findsOneWidget,
    );
    expect(
      find.text('No saved turns yet. Start a follow-up below.'),
      findsNothing,
    );
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

  testWidgets('Internal fallback prompts stay out of Studio transcript', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Internal implementation turn');
    final turn = StudioTurn(
      id: 'turn-internal-fallback',
      threadId: thread.id,
      requestId: 'request-internal-fallback',
      userMessageId: 'message-internal-fallback',
      prompt:
          'Implement this approved plan.\n\nUse the accepted plan context attached to this request as the source of truth.',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.failed,
      events: [
        StudioTurnEvent.error(
          turnId: 'turn-internal-fallback',
          requestId: 'request-internal-fallback',
          threadId: thread.id,
          detail: 'The implementation needs a patch proposal.',
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
      lastError: 'The implementation needs a patch proposal.',
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

    expect(find.textContaining('Implement this approved plan'), findsNothing);
    expect(find.textContaining('accepted plan context'), findsNothing);
    expect(find.textContaining('implementation needs a patch'), findsWidgets);
  });

  testWidgets('Streaming assistant draft does not render twice', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Streaming thread');
    final turn = StudioTurn(
      id: 'turn-streaming',
      threadId: thread.id,
      requestId: 'request-streaming',
      userMessageId: 'message-streaming',
      prompt: 'stream a response',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.streaming,
      assistantDraft: 'partial response',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);
    container
        .read(studioThreadProvider.notifier)
        .markPhase(
          thread.id,
          status: StudioThreadStatus.streaming,
          phase: StudioSendPhase.streaming,
          requestId: 'request-streaming',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(projectLabel: 'project'),
          streamingContent: 'partial response',
        );
    container.read(studioShellProvider.notifier).openThread(thread.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    expect(find.text('partial response'), findsOneWidget);
    expect(find.text('Circuit AI is responding...'), findsNothing);
    await flushStudioThreadPersist(tester);
  });

  testWidgets('Active turn suppresses stale thread-level streaming fallback', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Streaming thread');
    final turn = StudioTurn(
      id: 'turn-streaming-empty-draft',
      threadId: thread.id,
      requestId: 'request-streaming-empty-draft',
      userMessageId: 'message-streaming-empty-draft',
      prompt: 'stream a response',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.streaming,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);
    container
        .read(studioThreadProvider.notifier)
        .markPhase(
          thread.id,
          status: StudioThreadStatus.streaming,
          phase: StudioSendPhase.streaming,
          requestId: 'request-streaming-empty-draft',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(projectLabel: 'project'),
          streamingContent: 'stale thread-level response',
        );
    container.read(studioShellProvider.notifier).openThread(thread.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    expect(find.text('stale thread-level response'), findsNothing);
    expect(find.text('Circuit AI is responding...'), findsNothing);
  });

  testWidgets(
    'Legacy thread-level streaming content is not rendered without a turn',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Legacy streaming thread');
      container
          .read(studioThreadProvider.notifier)
          .markPhase(
            thread.id,
            status: StudioThreadStatus.streaming,
            phase: StudioSendPhase.streaming,
            requestId: 'legacy-request',
            model: 'gpt-5-nano',
            contextSummary: const StudioContextSummary(projectLabel: 'project'),
            streamingContent: 'legacy thread-only response',
          );
      container.read(studioShellProvider.notifier).openThread(thread.id);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
        ),
      );

      expect(find.text('legacy thread-only response'), findsNothing);
      expect(find.text('Circuit AI is responding...'), findsNothing);
      expect(find.text('Legacy streaming thread'), findsOneWidget);
    },
  );

  testWidgets('Streaming plan draft renders inside plan card', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Streaming plan thread');
    final turn = StudioTurn(
      id: 'turn-streaming-plan',
      threadId: thread.id,
      requestId: 'request-streaming-plan',
      userMessageId: 'message-streaming-plan',
      prompt: 'create a plan',
      model: 'gpt-5-nano',
      intent: TurnIntent.plan,
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.streaming,
      assistantDraft: '# Draft plan\n\n- First planned step',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
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

    expect(find.text('Plan'), findsWidgets);
    expect(find.text('Drafting...'), findsOneWidget);
    expect(find.text('Draft plan'), findsOneWidget);
    expect(find.text('Expand plan'), findsOneWidget);
    expect(
      find.text('Actions unlock when Circuit finishes writing the plan.'),
      findsOneWidget,
    );
    expect(find.text('Implement this plan?'), findsOneWidget);
    expect(find.text('Yes, implement this plan'), findsOneWidget);
    expect(
      find.text('No, and tell Circuit what to do differently'),
      findsOneWidget,
    );
    expect(find.text('Submit'), findsOneWidget);
    expect(find.text('Circuit AI is responding...'), findsNothing);
    await flushStudioThreadPersist(tester);
  });

  testWidgets('Long streaming plan draft remains bounded in chat', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Long streaming plan thread');
    final turn = StudioTurn(
      id: 'turn-long-streaming-plan',
      threadId: thread.id,
      requestId: 'request-long-streaming-plan',
      userMessageId: 'message-long-streaming-plan',
      prompt: 'create a long plan',
      model: 'gpt-5-nano',
      intent: TurnIntent.plan,
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.streaming,
      assistantDraft: [
        '# Long draft plan',
        '',
        for (var i = 0; i < 30; i++)
          '- Step $i: inspect the project, refine the implementation boundary, and keep this plan reviewable.',
      ].join('\n'),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
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

    expect(find.text('Long draft plan'), findsOneWidget);
    final cardSize = tester.getSize(
      find.byKey(const Key('studio-plan-draft-card')),
    );
    expect(cardSize.height, lessThan(620));
    expect(find.text('Expand plan'), findsOneWidget);

    await tester.tap(find.text('Expand plan'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Collapse plan'), findsOneWidget);
    final expandedCardSize = tester.getSize(
      find.byKey(const Key('studio-plan-draft-card')),
    );
    expect(expandedCardSize.height, greaterThan(cardSize.height));
    expect(expandedCardSize.height, lessThan(760));
    expect(find.text('Circuit AI is responding...'), findsNothing);
    await flushStudioThreadPersist(tester);
  });

  testWidgets(
    'Synthesized final plan renders as one plan card without duplicate prose',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final planMarkdown = [
        '# Datacenter sizing workflow plan',
        '',
        '## Summary',
        'Create a guided sizing workflow for customer datacenter planning.',
        '',
        '## Key changes',
        '- Create the quota scoring screen for customer inputs.',
        '- Add the rack and power requirement model.',
        '- Define validation steps before implementation.',
      ].join('\n');
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Synthesized plan thread');
      final turn = StudioTurn(
        id: 'turn-synthesized-plan',
        threadId: thread.id,
        requestId: 'request-synthesized-plan',
        userMessageId: 'message-synthesized-plan',
        prompt: 'create a plan for this',
        model: 'gpt-5-nano',
        intent: TurnIntent.plan,
        contextSummary: const StudioContextSummary(projectLabel: 'project'),
        status: StudioTurnStatus.completed,
        events: [
          StudioTurnEvent.assistantMessage(
            turnId: 'turn-synthesized-plan',
            requestId: 'request-synthesized-plan',
            threadId: thread.id,
            content: planMarkdown,
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
              id: 'synthesized-plan-patch',
              title: 'Datacenter sizing workflow plan',
              edits: const [],
              runId: 'request-synthesized-plan',
              createdAt: DateTime(2026),
              comparisonSummary:
                  'Create a guided sizing workflow for customer datacenter planning.',
              planMarkdown: planMarkdown,
              plannedFiles: const ['docs/datacenter_sizing_plan.md — create'],
            ),
          );
      container.read(studioShellProvider.notifier).openThread(thread.id);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
        ),
      );

      expect(find.text('Plan'), findsWidgets);
      expect(find.text('Datacenter sizing workflow plan'), findsWidgets);
      expect(
        find.textContaining('Create the quota scoring screen'),
        findsOneWidget,
      );
      expect(find.text('Implement this plan?'), findsOneWidget);
    },
  );

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
    expect(find.text('Recovered plan'), findsWidgets);
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

    expect(find.text('Prepared 1 file'), findsOneWidget);
    expect(find.text('Prepared 1 files'), findsNothing);
    _expectCompactActionStyle(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Apply changes'),
          )
          .style,
    );
    _expectCompactActionStyle(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Ask for revision'),
          )
          .style,
    );
    await tester.tap(find.text('README.md'));
    await tester.pump();

    final drawer = container.read(studioRightDrawerProvider);
    expect(drawer.mode, StudioDrawerMode.diff);
    expect(drawer.diffId, patch.id);
    expect(drawer.patchFilePath, 'README.md');
  });

  testWidgets('Applied patch verification action stays compact in transcript', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Verification action thread');
    final turn = StudioTurn(
      id: 'turn-verify-action',
      threadId: thread.id,
      requestId: 'request-verify-action',
      userMessageId: 'message-verify-action',
      prompt: 'apply the patch',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.assistantMessage(
          turnId: 'turn-verify-action',
          requestId: 'request-verify-action',
          threadId: thread.id,
          content: 'The patch has been applied.',
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
            id: 'patch-verify-card',
            title: 'Applied patch',
            runId: 'request-verify-action',
            edits: const [
              ProposedFileEdit(
                path: 'lib/login.dart',
                type: ProposedFileEditType.modify,
                before: 'old',
                after: 'new',
              ),
            ],
            changedFiles: const ['lib/login.dart'],
            applyStatus: PatchApplyStatus.applied,
            diffSummary: 'Updated login copy.',
            verificationRequested: true,
            verificationSuggestions: const ['flutter analyze'],
            createdAt: DateTime(2026),
          ),
        );
    container.read(studioShellProvider.notifier).openThread(thread.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    expect(find.text('Run verification'), findsOneWidget);
    _expectCompactActionStyle(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Run verification'),
          )
          .style,
    );
  });

  testWidgets('Applied patch card shows linked verification result', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Verification result thread');
    final applyTurn = StudioTurn(
      id: 'turn-apply-result',
      threadId: thread.id,
      requestId: 'request-apply-result',
      userMessageId: 'message-apply-result',
      prompt: 'apply the patch',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.assistantMessage(
          turnId: 'turn-apply-result',
          requestId: 'request-apply-result',
          threadId: thread.id,
          content: 'The patch has been applied.',
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    final verifyTurn = StudioTurn(
      id: 'turn-verify-result',
      threadId: thread.id,
      requestId: 'request-verify-result',
      userMessageId: 'message-verify-result',
      prompt: 'Running verification',
      model: 'gpt-5-nano',
      intent: TurnIntent.verify,
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      toolResults: const [
        ToolResultEnvelope(
          toolCallId: 'verify-command',
          toolName: 'run_command',
          status: ToolResultStatus.success,
          summary: 'flutter analyze passed.',
          data: {'command': 'flutter analyze', 'exitCode': 0},
        ),
      ],
      events: [
        StudioTurnEvent.completionSummary(
          turnId: 'turn-verify-result',
          requestId: 'request-verify-result',
          threadId: thread.id,
          title: 'Verification summary',
          detail: 'Verification command completed.',
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, applyTurn, select: true);
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, verifyTurn, select: true);
    container
        .read(patchProposalProvider.notifier)
        .preserveProposal(
          ProposedPatchSet(
            id: 'patch-verify-result-card',
            title: 'Applied patch',
            runId: 'request-apply-result',
            edits: const [
              ProposedFileEdit(
                path: 'lib/login.dart',
                type: ProposedFileEditType.modify,
                before: 'old',
                after: 'new',
              ),
            ],
            changedFiles: const ['lib/login.dart'],
            applyStatus: PatchApplyStatus.applied,
            diffSummary: 'Updated login copy.',
            verificationRequested: true,
            verificationRequestId: 'request-verify-result',
            verificationSuggestions: const ['flutter analyze'],
            createdAt: DateTime(2026),
          ),
        );
    container.read(studioShellProvider.notifier).openThread(thread.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    expect(find.text('Verification completed'), findsOneWidget);
    expect(find.text('flutter analyze passed.'), findsOneWidget);
    expect(find.text('Run verification'), findsNothing);
  });

  testWidgets('Applied patch card shows deterministic verification failure', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Verification failure thread');
    final verifyTurn = StudioTurn(
      id: 'turn-verify-failed-result',
      threadId: thread.id,
      requestId: 'request-verify-failed-result',
      userMessageId: 'message-verify-failed-result',
      prompt: 'Running verification',
      model: 'gpt-5-nano',
      intent: TurnIntent.verify,
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      steps: [
        TurnStepRecord(
          step: TurnStep.verification,
          status: TurnStepStatus.failed,
          title: 'Command failed',
          detail: 'Command: python3 -c "import sys; sys.exit(2)"\nExit code: 2',
          startedAt: DateTime(2026),
          completedAt: DateTime(2026),
        ),
      ],
      events: [
        StudioTurnEvent.completionSummary(
          turnId: 'turn-verify-failed-result',
          requestId: 'request-verify-failed-result',
          threadId: thread.id,
          title: 'Verification failed',
          detail:
              'Verification failed.\n\nCommands run:\n- `python3 -c "import sys; sys.exit(2)"` — failed (exit 2)',
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, verifyTurn, select: true);
    container
        .read(patchProposalProvider.notifier)
        .preserveProposal(
          ProposedPatchSet(
            id: 'patch-verify-failed-card',
            title: 'Applied patch',
            runId: 'request-apply-failed-result',
            edits: const [
              ProposedFileEdit(
                path: 'lib/login.dart',
                type: ProposedFileEditType.modify,
                before: 'old',
                after: 'new',
              ),
            ],
            changedFiles: const ['lib/login.dart'],
            applyStatus: PatchApplyStatus.applied,
            diffSummary: 'Updated login copy.',
            verificationRequested: true,
            verificationRequestId: 'request-verify-failed-result',
            verificationSuggestions: const [
              'python3 -c "import sys; sys.exit(2)"',
            ],
            createdAt: DateTime(2026),
          ),
        );
    container.read(studioShellProvider.notifier).openThread(thread.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    expect(find.text('Verification failed'), findsWidgets);
    expect(find.textContaining('failed (exit 2)'), findsWidgets);
    expect(find.text('Run verification'), findsNothing);
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
    expect(find.byTooltip('Context details'), findsOneWidget);
    await tester.tap(find.byTooltip('Context details'));
    await tester.pump();
    expect(
      container.read(studioRightDrawerProvider).mode,
      StudioDrawerMode.context,
    );
    expect(find.text('Push'), findsNothing);
    expect(find.text('Create pull request'), findsNothing);
    expect(find.text('Ask for follow-up changes'), findsOneWidget);
  });

  testWidgets(
    'Studio user bubble typography matches compact transcript scale',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Bubble scale thread');
      final turn = StudioTurn(
        id: 'turn-bubble-scale',
        threadId: thread.id,
        requestId: 'request-bubble-scale',
        userMessageId: 'message-bubble-scale',
        prompt: 'Can we plan the dashboard first?',
        model: 'gpt-5-nano',
        contextSummary: const StudioContextSummary(projectLabel: 'project'),
        status: StudioTurnStatus.completed,
        events: [
          StudioTurnEvent.userMessage(
            id: 'message-bubble-scale',
            turnId: 'turn-bubble-scale',
            requestId: 'request-bubble-scale',
            threadId: thread.id,
            content: 'Can we plan the dashboard first?',
            timestamp: DateTime(2026),
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
      expect(
        container.read(studioThreadProvider).selectedThread?.id,
        thread.id,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
        ),
      );

      final bubble = tester.widget<Text>(
        find.text('Can we plan the dashboard first?').first,
      );
      expect(bubble.style?.fontSize, FontSizes.md);
      expect(bubble.style?.height, 1.28);
    },
  );

  testWidgets(
    'Studio assistant footer actions match compact transcript scale',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Assistant actions thread');
      final turn = StudioTurn(
        id: 'turn-assistant-actions',
        threadId: thread.id,
        requestId: 'request-assistant-actions',
        userMessageId: 'message-assistant-actions',
        prompt: 'Summarize this app.',
        model: 'gpt-5-nano',
        contextSummary: const StudioContextSummary(projectLabel: 'project'),
        status: StudioTurnStatus.completed,
        events: [
          StudioTurnEvent.assistantMessage(
            turnId: 'turn-assistant-actions',
            requestId: 'request-assistant-actions',
            threadId: thread.id,
            content: 'Here is the summary.',
            timestamp: DateTime(2026),
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

      expect(find.byTooltip('Copy response'), findsOneWidget);
      expect(find.byTooltip('Mark helpful'), findsOneWidget);
      expect(find.byTooltip('Mark needs work'), findsOneWidget);

      for (final iconData in [
        Icons.copy_outlined,
        Icons.thumb_up_alt_outlined,
        Icons.thumb_down_alt_outlined,
      ]) {
        final icon = tester.widget<Icon>(find.byIcon(iconData));
        expect(icon.size, 12);
        final box = tester.getSize(
          find
              .ancestor(
                of: find.byIcon(iconData),
                matching: find.byType(InkWell),
              )
              .first,
        );
        expect(box.width, 24);
        expect(box.height, 24);
        final decorated = tester.widget<Container>(
          find
              .ancestor(
                of: find.byIcon(iconData),
                matching: find.byType(Container),
              )
              .first,
        );
        final decoration = decorated.decoration;
        expect(decoration, isA<BoxDecoration>());
        expect(
          (decoration! as BoxDecoration).borderRadius,
          BorderRadius.circular(6),
        );
      }

      await tester.tap(find.byTooltip('Copy response'));
      await tester.pump();
      expect(find.text('Copied response'), findsOneWidget);

      await tester.tap(find.byTooltip('Mark helpful'));
      await tester.pump();
      expect(find.text('Marked helpful'), findsOneWidget);
    },
  );

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
    expect(find.byTooltip('Open context details'), findsOneWidget);
    expect(
      tester.getSize(find.byTooltip('Open context details')),
      const Size(28, 24),
    );
  });

  testWidgets('Progress panel hides routine ready task row', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Done thread');
    final turn = StudioTurn(
      id: 'turn-done-panel',
      threadId: thread.id,
      requestId: 'request-done-panel',
      userMessageId: 'message-done-panel',
      prompt: 'hello',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.userMessage(
          id: 'message-done-panel',
          turnId: 'turn-done-panel',
          requestId: 'request-done-panel',
          threadId: thread.id,
          content: 'hello',
          timestamp: DateTime(2026),
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
        child: const MaterialApp(home: Scaffold(body: StudioProgressPanel())),
      ),
    );

    expect(find.text('Environment'), findsOneWidget);
    expect(find.text('Task'), findsNothing);
    expect(find.text('Changes'), findsOneWidget);
    expect(find.text('No pending changes'), findsOneWidget);
    expect(find.byIcon(Icons.language), findsNWidgets(24));

    final changesText = tester.widget<Text>(find.text('Changes'));
    expect(changesText.style?.fontSize, FontSizes.sm);
    final sourceIcons = tester.widgetList<Icon>(find.byIcon(Icons.language));
    expect(sourceIcons.first.size, 11);
  });

  testWidgets('Progress panel reports historical patch changes', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Historical patch progress');
    final turn = StudioTurn(
      id: 'turn-historical-patch-panel',
      threadId: thread.id,
      requestId: 'request-historical-patch-panel',
      userMessageId: 'message-historical-patch-panel',
      prompt: 'apply the prepared change',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.userMessage(
          id: 'message-historical-patch-panel',
          turnId: 'turn-historical-patch-panel',
          requestId: 'request-historical-patch-panel',
          threadId: thread.id,
          content: 'apply the prepared change',
          timestamp: DateTime(2026),
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);

    final patchController = container.read(patchProposalProvider.notifier);
    final patch = patchController.propose(
      title: 'Prepared historical changes',
      runId: 'request-historical-patch-panel',
      edits: const [
        ProposedFileEdit(
          path: 'lib/main.dart',
          type: ProposedFileEditType.modify,
          before: 'old',
          after: 'new',
        ),
      ],
    );
    patchController.reject(patch.id);
    expect(container.read(patchProposalProvider).active, isNull);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioProgressPanel())),
      ),
    );

    expect(find.text('Changes'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    expect(find.text('No pending changes'), findsNothing);
  });

  testWidgets('Right progress drawer hides routine completed task row', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Completed drawer thread');
    final turn = StudioTurn(
      id: 'turn-done-drawer',
      threadId: thread.id,
      requestId: 'request-done-drawer',
      userMessageId: 'message-done-drawer',
      prompt: 'hello',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.userMessage(
          id: 'message-done-drawer',
          turnId: 'turn-done-drawer',
          requestId: 'request-done-drawer',
          threadId: thread.id,
          content: 'hello',
          timestamp: DateTime(2026),
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

    expect(find.text('Environment'), findsOneWidget);
    expect(find.text('Task'), findsNothing);
    expect(find.text('Changes'), findsOneWidget);
    expect(find.text('No pending changes'), findsOneWidget);
    expect(find.text('Latest event'), findsOneWidget);
  });

  testWidgets('Approval card is compact and exposes real review actions', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Approval card thread');
    final turn = StudioTurn(
      id: 'turn-approval-card',
      threadId: thread.id,
      requestId: 'request-approval-card',
      userMessageId: 'message-approval-card',
      prompt: 'verify changes',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.waitingForApproval,
      events: [
        StudioTurnEvent.userMessage(
          id: 'message-approval-card',
          turnId: 'turn-approval-card',
          requestId: 'request-approval-card',
          threadId: thread.id,
          content: 'verify changes',
          timestamp: DateTime(2026),
        ),
        StudioTurnEvent.approval(
          turnId: 'turn-approval-card',
          requestId: 'request-approval-card',
          threadId: thread.id,
          request: ConfirmationRequest(
            id: 'approval-card',
            toolCall: const ToolCallInfo(
              id: 'tool-approval-card',
              name: 'run_command',
              arguments: {'command': 'flutter test'},
            ),
            preview: 'flutter test',
            warnings: const ['Shell command requires review.'],
          ),
          timestamp: DateTime(2026, 1, 1, 0, 0, 1),
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
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    expect(find.text('Approval needed'), findsWidgets);
    expect(find.text('Review required'), findsOneWidget);
    expect(find.text('Circuit wants to use run command.'), findsOneWidget);
    expect(find.text('flutter test'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    expect(find.text('Approve for this turn'), findsOneWidget);
    expect(find.text('Approve once'), findsOneWidget);

    final preview = tester.widget<SelectableText>(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == 'flutter test',
      ),
    );
    expect(preview.style?.fontFamily, EditorDefaults.studioMonospaceFontFamily);

    final shieldIcon = tester.widget<Icon>(
      find.byIcon(Icons.shield_outlined).first,
    );
    expect(shieldIcon.size, 14);

    _expectCompactActionStyle(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Reject'))
          .style,
    );
    _expectCompactActionStyle(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Approve for this turn'),
          )
          .style,
    );
    _expectCompactActionStyle(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Approve once'),
          )
          .style,
    );
    expect(tester.widget<Icon>(find.byIcon(Icons.task_alt_outlined)).size, 14);
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

  testWidgets(
    'Progress drawer prefers prepared changes over provider diagnostics',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Prepared changes thread');
      final turn = StudioTurn(
        id: 'turn-prepared-changes',
        threadId: thread.id,
        requestId: 'request-prepared-changes',
        userMessageId: 'message-prepared-changes',
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
            'Runtime rejected the model outcome, but a reviewable patch exists.',
        providerDiagnostics: [
          ProviderLifecycleEvent(
            requestId: 'request-prepared-changes',
            turnId: 'turn-prepared-changes',
            kind: ProviderLifecycleEventKind.outcomeRejected,
            timestamp: DateTime(2026, 1, 1, 0, 0, 1),
            model: 'gpt-5-nano',
            detail:
                'Runtime rejected the model outcome, but a reviewable patch exists.',
          ),
          ProviderLifecycleEvent(
            requestId: 'request-prepared-changes',
            turnId: 'turn-prepared-changes',
            kind: ProviderLifecycleEventKind.failed,
            timestamp: DateTime(2026, 1, 1, 0, 0, 2),
            model: 'gpt-5-nano',
            detail: 'Provider failed.',
          ),
        ],
        events: [
          StudioTurnEvent.userMessage(
            id: 'message-prepared-changes',
            turnId: 'turn-prepared-changes',
            requestId: 'request-prepared-changes',
            threadId: thread.id,
            content: 'implement the plan',
            timestamp: DateTime(2026),
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
              id: 'patch-prepared-changes',
              title: 'Prepared repair',
              runId: 'request-prepared-changes',
              edits: const [
                ProposedFileEdit(
                  path: 'lib/main.dart',
                  type: ProposedFileEditType.modify,
                  before: 'old',
                  after: 'new',
                ),
              ],
              createdAt: DateTime(2026),
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
        ),
      );

      expect(find.text('Prepared changes'), findsWidgets);
      expect(
        find.text('Review, revise, or apply the prepared changes.'),
        findsOneWidget,
      );
      expect(find.text('Provider failed'), findsNothing);
    },
  );

  testWidgets(
    'Progress drawer prefers patch conflict event over later provider failure',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Patch conflict thread');
      final turn = StudioTurn(
        id: 'turn-patch-conflict-event',
        threadId: thread.id,
        requestId: 'request-patch-conflict-event',
        userMessageId: 'message-patch-conflict-event',
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
            'Provider failed after patch conflict was recorded for review.',
        providerDiagnostics: [
          ProviderLifecycleEvent(
            requestId: 'request-patch-conflict-event',
            turnId: 'turn-patch-conflict-event',
            kind: ProviderLifecycleEventKind.outcomeRejected,
            timestamp: DateTime(2026, 1, 1, 0, 0, 2),
            model: 'gpt-5-nano',
            detail:
                'Runtime rejected the model outcome after a patch conflict.',
          ),
          ProviderLifecycleEvent(
            requestId: 'request-patch-conflict-event',
            turnId: 'turn-patch-conflict-event',
            kind: ProviderLifecycleEventKind.failed,
            timestamp: DateTime(2026, 1, 1, 0, 0, 3),
            model: 'gpt-5-nano',
            detail: 'Provider failed.',
          ),
        ],
        events: [
          StudioTurnEvent.userMessage(
            id: 'message-patch-conflict-event',
            turnId: 'turn-patch-conflict-event',
            requestId: 'request-patch-conflict-event',
            threadId: thread.id,
            content: 'implement the plan',
            timestamp: DateTime(2026),
          ),
          StudioTurnEvent.completionSummary(
            id: 'patch-conflict-event',
            turnId: 'turn-patch-conflict-event',
            requestId: 'request-patch-conflict-event',
            threadId: thread.id,
            title: 'Patch conflict',
            detail:
                'File changed since proposal: plan/01_mvp_requirements.md\nAsk Circuit to rebase the proposal.',
            timestamp: DateTime(2026, 1, 1, 0, 0, 1),
          ),
          StudioTurnEvent.error(
            turnId: 'turn-patch-conflict-event',
            requestId: 'request-patch-conflict-event',
            threadId: thread.id,
            detail:
                'Provider failed after patch conflict was recorded for review.',
            timestamp: DateTime(2026, 1, 1, 0, 0, 4),
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

      expect(find.text('Patch conflict'), findsWidgets);
      expect(find.textContaining('File changed since proposal'), findsWidgets);
      expect(find.text('Provider failed'), findsNothing);
    },
  );

  testWidgets(
    'Progress drawer prefers continuation state over later provider failure',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Continuation thread');
      final turn = StudioTurn(
        id: 'turn-continuation-event',
        threadId: thread.id,
        requestId: 'request-continuation-event',
        userMessageId: 'message-continuation-event',
        prompt: 'implement the accepted plan',
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
            requestId: 'request-continuation-event',
            turnId: 'turn-continuation-event',
            kind: ProviderLifecycleEventKind.failed,
            timestamp: DateTime(2026, 1, 1, 0, 0, 3),
            model: 'gpt-5-nano',
            detail: 'Provider failed.',
          ),
        ],
        steps: [
          TurnStepRecord(
            step: TurnStep.continuation,
            status: TurnStepStatus.queued,
            title: 'Continue next batch',
            detail:
                '1 accepted-plan target still needs work. Remaining: README.md.',
            startedAt: DateTime(2026, 1, 1, 0, 0, 2),
          ),
        ],
        events: [
          StudioTurnEvent.userMessage(
            id: 'message-continuation-event',
            turnId: 'turn-continuation-event',
            requestId: 'request-continuation-event',
            threadId: thread.id,
            content: 'implement the accepted plan',
            timestamp: DateTime(2026),
          ),
          StudioTurnEvent.completionSummary(
            id: 'patch-transaction-turn-continuation-event-applied',
            turnId: 'turn-continuation-event',
            requestId: 'request-continuation-event',
            threadId: thread.id,
            title: 'Applied changes',
            detail:
                'Applied 1 files.\nHere’s what changed: lib/main.dart\nNext batch: 1 accepted-plan target still needs work. Remaining: README.md.',
            timestamp: DateTime(2026, 1, 1, 0, 0, 1),
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
              id: 'patch-continuation-event',
              title: 'First batch',
              runId: 'request-continuation-event',
              edits: const [
                ProposedFileEdit(
                  path: 'lib/main.dart',
                  type: ProposedFileEditType.create,
                  after: 'void main() {}\n',
                ),
              ],
              createdAt: DateTime(2026),
              applyStatus: PatchApplyStatus.applied,
              changedFiles: const ['lib/main.dart'],
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
        ),
      );

      expect(find.text('Continue next batch'), findsWidgets);
      expect(find.textContaining('README.md'), findsWidgets);
      expect(find.text('Provider failed'), findsNothing);
    },
  );

  testWidgets(
    'Progress drawer prefers patch conflict over queued continuation',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Conflict continuation thread');
      final turn = StudioTurn(
        id: 'turn-conflict-continuation',
        threadId: thread.id,
        requestId: 'request-conflict-continuation',
        userMessageId: 'message-conflict-continuation',
        prompt: 'continue the accepted plan',
        model: 'gpt-5-nano',
        contextSummary: const StudioContextSummary(
          rootPath: '/tmp/project',
          projectLabel: 'project',
          includedItemCount: 2,
          estimatedTokens: 120,
        ),
        status: StudioTurnStatus.completed,
        steps: [
          TurnStepRecord(
            step: TurnStep.continuation,
            status: TurnStepStatus.queued,
            title: 'Continue next batch',
            detail:
                '1 accepted-plan target still needs work. Remaining: README.md.',
            startedAt: DateTime(2026, 1, 1, 0, 0, 1),
          ),
        ],
        events: [
          StudioTurnEvent.userMessage(
            id: 'message-conflict-continuation',
            turnId: 'turn-conflict-continuation',
            requestId: 'request-conflict-continuation',
            threadId: thread.id,
            content: 'continue the accepted plan',
            timestamp: DateTime(2026),
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
              id: 'patch-conflict-continuation',
              title: 'Conflicted batch',
              runId: 'request-conflict-continuation',
              edits: const [
                ProposedFileEdit(
                  path: 'README.md',
                  type: ProposedFileEditType.modify,
                  before: 'old',
                  after: 'new',
                ),
              ],
              createdAt: DateTime(2026),
              applyStatus: PatchApplyStatus.conflict,
              conflictMessage: 'File changed since proposal: README.md',
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
        ),
      );

      expect(find.text('Patch conflict'), findsWidgets);
      expect(find.textContaining('File changed since proposal'), findsWidgets);
    },
  );

  testWidgets(
    'Progress drawer prefers patch revision request over provider diagnostics',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Patch revision thread');
      final turn = StudioTurn(
        id: 'turn-patch-revision-event',
        threadId: thread.id,
        requestId: 'request-patch-revision-event',
        userMessageId: 'message-patch-revision-event',
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
            'Provider failed after patch revision was requested for review.',
        providerDiagnostics: [
          ProviderLifecycleEvent(
            requestId: 'request-patch-revision-event',
            turnId: 'turn-patch-revision-event',
            kind: ProviderLifecycleEventKind.outcomeRejected,
            timestamp: DateTime(2026, 1, 1, 0, 0, 2),
            model: 'gpt-5-nano',
            detail:
                'Runtime rejected a model draft after revision was requested.',
          ),
          ProviderLifecycleEvent(
            requestId: 'request-patch-revision-event',
            turnId: 'turn-patch-revision-event',
            kind: ProviderLifecycleEventKind.failed,
            timestamp: DateTime(2026, 1, 1, 0, 0, 3),
            model: 'gpt-5-nano',
            detail: 'Provider failed.',
          ),
        ],
        events: [
          StudioTurnEvent.userMessage(
            id: 'message-patch-revision-event',
            turnId: 'turn-patch-revision-event',
            requestId: 'request-patch-revision-event',
            threadId: thread.id,
            content: 'implement the plan',
            timestamp: DateTime(2026),
          ),
          StudioTurnEvent.completionSummary(
            id: 'patch-revision-event',
            turnId: 'turn-patch-revision-event',
            requestId: 'request-patch-revision-event',
            threadId: thread.id,
            title: 'Patch revision requested',
            detail:
                'Patch revision requested.\nRefresh this patch against current files.',
            timestamp: DateTime(2026, 1, 1, 0, 0, 1),
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
              id: 'patch-revision-event',
              title: 'Revise stale patch',
              runId: 'request-patch-revision-event',
              approvalStatus: PatchApprovalStatus.revisionRequested,
              applyStatus: PatchApplyStatus.revisionRequested,
              revisionPrompt:
                  'Refresh this patch against current files and keep the accepted plan targets.',
              edits: const [
                ProposedFileEdit(
                  path: 'plan/01_mvp_requirements.md',
                  type: ProposedFileEditType.modify,
                  before: 'old',
                  after: 'new',
                ),
              ],
              createdAt: DateTime(2026),
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
        ),
      );

      expect(find.text('Patch revision requested'), findsWidgets);
      expect(
        find.textContaining('Refresh this patch against current files'),
        findsWidgets,
      );
      expect(find.text('Provider failed'), findsNothing);
    },
  );

  testWidgets(
    'Progress drawer prefers persisted patch revision event without active patch',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Persisted patch revision thread');
      final turn = StudioTurn(
        id: 'turn-persisted-patch-revision-event',
        threadId: thread.id,
        requestId: 'request-persisted-patch-revision-event',
        userMessageId: 'message-persisted-patch-revision-event',
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
            'Provider failed after patch revision was requested for review.',
        providerDiagnostics: [
          ProviderLifecycleEvent(
            requestId: 'request-persisted-patch-revision-event',
            turnId: 'turn-persisted-patch-revision-event',
            kind: ProviderLifecycleEventKind.outcomeRejected,
            timestamp: DateTime(2026, 1, 1, 0, 0, 2),
            model: 'gpt-5-nano',
            detail:
                'Runtime rejected a model draft after revision was requested.',
          ),
          ProviderLifecycleEvent(
            requestId: 'request-persisted-patch-revision-event',
            turnId: 'turn-persisted-patch-revision-event',
            kind: ProviderLifecycleEventKind.failed,
            timestamp: DateTime(2026, 1, 1, 0, 0, 3),
            model: 'gpt-5-nano',
            detail: 'Provider failed.',
          ),
        ],
        events: [
          StudioTurnEvent.userMessage(
            id: 'message-persisted-patch-revision-event',
            turnId: 'turn-persisted-patch-revision-event',
            requestId: 'request-persisted-patch-revision-event',
            threadId: thread.id,
            content: 'implement the plan',
            timestamp: DateTime(2026),
          ),
          StudioTurnEvent.completionSummary(
            id: 'patch-revision-event',
            turnId: 'turn-persisted-patch-revision-event',
            requestId: 'request-persisted-patch-revision-event',
            threadId: thread.id,
            title: 'Patch revision requested',
            detail:
                'Patch revision requested.\nRefresh this patch against current files.',
            timestamp: DateTime(2026, 1, 1, 0, 0, 1),
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

      expect(find.text('Patch revision requested'), findsWidgets);
      expect(
        find.textContaining('Refresh this patch against current files'),
        findsWidgets,
      );
      expect(find.text('Provider failed'), findsNothing);
    },
  );

  testWidgets(
    'Progress drawer prefers queued continuation over applied summary',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Continuation drawer thread');
      final now = DateTime(2026);
      final turn = StudioTurn(
        id: 'turn-continuation-drawer',
        threadId: thread.id,
        requestId: 'request-continuation-drawer',
        userMessageId: 'message-continuation-drawer',
        prompt: 'implement the first batch',
        model: 'gpt-5-nano',
        contextSummary: const StudioContextSummary(
          rootPath: '/tmp/project',
          projectLabel: 'project',
          includedItemCount: 2,
          estimatedTokens: 120,
        ),
        status: StudioTurnStatus.completed,
        steps: [
          TurnStepRecord(
            step: TurnStep.continuation,
            status: TurnStepStatus.queued,
            title: 'Continue next batch',
            detail:
                '1 accepted-plan target still needs work. Remaining: README.md. Use Continue next batch to keep implementing the accepted plan.',
            startedAt: now,
          ),
        ],
        events: [
          StudioTurnEvent.userMessage(
            id: 'message-continuation-drawer',
            turnId: 'turn-continuation-drawer',
            requestId: 'request-continuation-drawer',
            threadId: thread.id,
            content: 'implement the first batch',
            timestamp: now,
          ),
          StudioTurnEvent.completionSummary(
            id: 'applied-continuation-drawer',
            turnId: 'turn-continuation-drawer',
            requestId: 'request-continuation-drawer',
            threadId: thread.id,
            title: 'Applied changes',
            detail: 'Applied 1 files.',
            timestamp: now.add(const Duration(seconds: 1)),
          ),
        ],
        createdAt: now,
        updatedAt: now,
        completedAt: now,
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

      expect(find.text('Continue next batch'), findsOneWidget);
      expect(
        find.textContaining('1 accepted-plan target still needs work'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Progress drawer ignores active patches from another request', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Clean thread');
    final turn = StudioTurn(
      id: 'turn-clean-thread',
      threadId: thread.id,
      requestId: 'request-clean-thread',
      userMessageId: 'message-clean-thread',
      prompt: 'hello',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(
        rootPath: '/tmp/project',
        projectLabel: 'project',
        includedItemCount: 1,
        estimatedTokens: 42,
      ),
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.userMessage(
          id: 'message-clean-thread',
          turnId: 'turn-clean-thread',
          requestId: 'request-clean-thread',
          threadId: thread.id,
          content: 'hello',
          timestamp: DateTime(2026),
        ),
        StudioTurnEvent.assistantMessage(
          turnId: 'turn-clean-thread',
          requestId: 'request-clean-thread',
          threadId: thread.id,
          content: 'Hello.',
          timestamp: DateTime(2026, 1, 1, 0, 0, 1),
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026, 1, 1, 0, 0, 1),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);
    container
        .read(patchProposalProvider.notifier)
        .preserveProposal(
          ProposedPatchSet(
            id: 'patch-other-request',
            title: 'Other request patch',
            runId: 'request-other-thread',
            edits: const [
              ProposedFileEdit(
                path: 'lib/other.dart',
                type: ProposedFileEditType.create,
                after: 'void other() {}\n',
              ),
            ],
            createdAt: DateTime(2026),
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    expect(find.text('No pending changes'), findsOneWidget);
    expect(find.text('Prepared changes'), findsNothing);
    expect(
      find.text('Review, revise, or apply the prepared changes.'),
      findsNothing,
    );
  });

  testWidgets('Progress drawer ignores running commands from another request', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Clean command thread');
    final turn = StudioTurn(
      id: 'turn-clean-command-thread',
      threadId: thread.id,
      requestId: 'request-clean-command-thread',
      userMessageId: 'message-clean-command-thread',
      prompt: 'hello',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(
        rootPath: '/tmp/project',
        projectLabel: 'project',
        includedItemCount: 1,
        estimatedTokens: 42,
      ),
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.userMessage(
          id: 'message-clean-command-thread',
          turnId: 'turn-clean-command-thread',
          requestId: 'request-clean-command-thread',
          threadId: thread.id,
          content: 'hello',
          timestamp: DateTime(2026),
        ),
        StudioTurnEvent.assistantMessage(
          turnId: 'turn-clean-command-thread',
          requestId: 'request-clean-command-thread',
          threadId: thread.id,
          content: 'Hello.',
          timestamp: DateTime(2026, 1, 1, 0, 0, 1),
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026, 1, 1, 0, 0, 1),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);
    container
        .read(commandRunProvider.notifier)
        .start(
          id: 'command-other-request',
          command: 'npm run dev',
          requestId: 'request-other-thread',
          turnId: 'turn-other-thread',
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );

    expect(find.text('Command'), findsNothing);
    expect(find.text('npm run dev'), findsNothing);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets(
    'Progress drawer prefers applied change outcome over provider diagnostics',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Applied changes thread');
      final turn = StudioTurn(
        id: 'turn-applied-changes',
        threadId: thread.id,
        requestId: 'request-applied-changes',
        userMessageId: 'message-applied-changes',
        prompt: 'implement the plan',
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
            requestId: 'request-applied-changes',
            turnId: 'turn-applied-changes',
            kind: ProviderLifecycleEventKind.failed,
            timestamp: DateTime(2026, 1, 1, 0, 0, 2),
            model: 'gpt-5-nano',
            detail: 'Late provider failed diagnostic.',
          ),
        ],
        events: [
          StudioTurnEvent.userMessage(
            id: 'message-applied-changes',
            turnId: 'turn-applied-changes',
            requestId: 'request-applied-changes',
            threadId: thread.id,
            content: 'implement the plan',
            timestamp: DateTime(2026),
          ),
          StudioTurnEvent.completionSummary(
            id: 'summary-applied-changes',
            turnId: 'turn-applied-changes',
            requestId: 'request-applied-changes',
            threadId: thread.id,
            title: 'Applied changes',
            detail: 'Applied 2 files. Recommended next step: run tests.',
            timestamp: DateTime(2026, 1, 1, 0, 0, 1),
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
      await tester.pump();

      expect(find.text('Applied changes'), findsWidgets);
      expect(
        find.text('Applied 2 files. Recommended next step: run tests.'),
        findsWidgets,
      );
      expect(find.text('Provider failed'), findsNothing);
      expect(find.text('Late provider failed diagnostic.'), findsNothing);
    },
  );

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

    expect(find.text('Prepared 1 file'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('Apply changes'), findsOneWidget);
    expect(find.text('Ask for revision'), findsOneWidget);
    _expectCompactActionStyle(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Apply changes'),
          )
          .style,
    );
    _expectCompactActionStyle(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Ask for revision'),
          )
          .style,
    );

    expect(tester.widget<Icon>(find.byIcon(Icons.difference)).size, 14);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.description_outlined)).size,
      11,
    );
    expect(tester.widget<Icon>(find.byIcon(Icons.chevron_right)).size, 13);
    expect(tester.widget<Icon>(find.byIcon(Icons.check)).size, 13);

    final preview = tester.widget<SelectableText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText && (widget.data ?? '').contains('+ new'),
      ),
    );
    expect(preview.style?.fontFamily, EditorDefaults.studioMonospaceFontFamily);
  });

  testWidgets('Inline patch conflict card exposes recovery actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final root = Directory.systemTemp.createTempSync('studio_inline_conflict_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    File('${root.path}/README.md').writeAsStringSync('changed on disk');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(fileTreeProvider.notifier).openDirectory(root.path),
    );
    await tester.runAsync(
      () => container.read(studioThreadProvider.notifier).reload(),
    );
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Patch conflict thread');
    container.read(studioShellProvider.notifier).openThread(thread.id);
    container
        .read(studioTurnProvider.notifier)
        .registerTurn(
          requestId: 'request-inline-conflict',
          threadId: thread.id,
          taskId: null,
          userMessageId: 'message-inline-conflict',
          prompt: 'Apply patch',
          model: 'gpt-5-nano',
          contextSummary: StudioContextSummary(
            rootPath: root.path,
            projectLabel: 'project',
          ),
          intent: TurnIntent.code,
        );
    final patch = container
        .read(patchProposalProvider.notifier)
        .propose(
          title: 'Update readme',
          runId: 'request-inline-conflict',
          edits: const [
            ProposedFileEdit(
              path: 'README.md',
              type: ProposedFileEditType.modify,
              before: 'old',
              after: 'new',
            ),
          ],
        );

    final result = await tester.runAsync(
      () => container.read(patchProposalProvider.notifier).apply(patch.id),
    );
    expect(result?.status, PatchApplyStatus.conflict);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Patch conflict'), findsWidgets);
    expect(find.textContaining('Needs rebase before apply'), findsWidgets);
    expect(find.text('View current file'), findsOneWidget);
    expect(find.text('Refresh patch'), findsOneWidget);
    expect(find.text('Ask Circuit to rebase'), findsOneWidget);
    expect(find.text('Dismiss conflict'), findsOneWidget);

    await tester.tap(find.text('View current file'));
    await tester.pump();
    var drawer = container.read(studioRightDrawerProvider);
    expect(drawer.mode, StudioDrawerMode.code);
    expect(drawer.filePath, 'README.md');

    await tester.tap(find.text('Dismiss conflict'));
    await tester.pump();
    final dismissed = container.read(patchProposalProvider).active!;
    expect(dismissed.applyStatus, isNull);
    expect(dismissed.conflictMessage, isNull);
    expect(
      container.read(patchProposalProvider).message,
      'Patch conflict dismissed.',
    );
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
            plannedFiles: const ['lib/app.dart — create the app shell'],
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudioReviewPanel())),
        ),
      );

      expect(find.text('Plan ready'), findsOneWidget);
      expect(find.text('lib/app.dart'), findsOneWidget);
      expect(find.text('Implement this plan'), findsOneWidget);
      expect(find.text('Approve plan'), findsNothing);
      expect(find.text('Apply changes'), findsNothing);

      await tester.tap(find.text('lib/app.dart').first);
      await tester.pump();

      final drawer = container.read(studioRightDrawerProvider);
      expect(drawer.mode, StudioDrawerMode.code);
      expect(drawer.filePath, 'lib/app.dart');
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
    'Plan implementation sends structured context and offers next batch after partial apply',
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
        const [
          ChatChunk(
            toolCallIndex: 0,
            toolCallId: 'patch-readme',
            toolCallName: 'propose_patch',
            toolCallArguments:
                '{"title":"Document greeting","summary":"Add usage docs for the remaining accepted-plan target.","files":[{"path":"README.md","intent":"Document usage","operation":"create","content":"# Greeting\\n\\nRun the greeting example.\\n"}]}',
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
            plannedFiles: const [
              'hello.txt — Add greeting',
              'README.md — Document usage',
            ],
            verificationRequested: true,
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
      expect(thread!.title, isNot(contains('Implement this approved plan')));
      expect(thread.title, isNot(contains('accepted plan context')));
      final turn = thread.turns.single;
      expect(turn.intent, TurnIntent.code);
      expect(turn.status, StudioTurnStatus.completed);
      expect(turn.acceptedPlanState, AcceptedPlanState.patchProposed);
      expect(turn.taskTitle, 'Accepted greeting plan');
      expect(
        container
            .read(agentRunProvider)
            .recentRuns
            .any((candidate) => candidate.id == result!.requestId),
        isFalse,
      );
      final userEvent = turn.events.firstWhere(
        (event) => event.type == StudioTurnEventType.userMessage,
      );
      expect(userEvent.transcriptVisible, isFalse);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
        ),
      );
      expect(find.textContaining('Implement this approved plan'), findsNothing);
      expect(
        find.textContaining('Use the accepted plan context'),
        findsNothing,
      );

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
      expect(appliedPatch.verificationRequested, isTrue);
      expect(appliedPatch.verificationSuggestions, isNotEmpty);
      final updatedTurn = container
          .read(studioThreadProvider)
          .selectedThread!
          .turns
          .single;
      expect(
        container.read(studioThreadProvider).selectedThread!.status,
        StudioThreadStatus.continuationReady,
      );
      expect(updatedTurn.acceptedPlanState, AcceptedPlanState.patchProposed);
      expect(
        updatedTurn.planTargetProgress
            .firstWhere((target) => target.path == 'hello.txt')
            .state,
        PlanTargetProgressState.applied,
      );
      expect(
        updatedTurn.planTargetProgress
            .firstWhere((target) => target.path == 'README.md')
            .state,
        PlanTargetProgressState.pending,
      );
      final applyEvents = updatedTurn.events.where(
        (event) =>
            event.type == StudioTurnEventType.completionSummary &&
            event.title == 'Applied changes',
      );
      expect(applyEvents, hasLength(1));
      expect(applyEvents.single.detail, contains('Applied 1 files.'));
      expect(applyEvents.single.detail, contains('Created hello.txt'));
      expect(applyEvents.single.detail, contains('Next batch: 1'));
      expect(applyEvents.single.detail, contains('README.md'));
      expect(applyEvents.single.detail, contains('Use Continue next batch'));
      final verificationStep = updatedTurn.steps
          .where((step) => step.step == TurnStep.verification)
          .single;
      expect(verificationStep.status, TurnStepStatus.queued);
      expect(verificationStep.title, 'Verification ready');
      expect(verificationStep.detail, contains('Suggested checks'));
      expect(verificationStep.detail, contains('Verification was requested'));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
        ),
      );
      await tester.pump();

      expect(
        find.textContaining('Plan progress: 1/2 targets applied'),
        findsOneWidget,
      );
      expect(find.text('Pending'), findsWidgets);
      expect(find.textContaining('README.md'), findsWidgets);
      expect(find.text('Next batch available'), findsOneWidget);
      expect(find.text('Continue next batch'), findsWidgets);
      final continueButton = find.ancestor(
        of: find.text('Continue next batch'),
        matching: find.byType(FilledButton),
      );
      expect(continueButton, findsWidgets);
      expect(
        tester.widget<FilledButton>(continueButton.first).onPressed,
        isNotNull,
      );

      final continuation = studioPlanContinuationForPatch(
        patch: appliedPatch,
        threads: container.read(studioThreadProvider).threads,
      );
      expect(continuation, isNotNull);
      late WidgetRef continuationRef;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) {
                continuationRef = ref;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      final continuationResult = await tester.runAsync(
        () => implementPlanFromStudio(
          continuationRef,
          appliedPatch,
          acceptedPlanOverride: continuation!.acceptedPlan,
          displayText: 'Continuing approved plan',
        ),
      );
      expect(continuationResult?.status, StudioSendStatus.sent);
      await tester.runAsync(() async {
        for (var i = 0; i < 80; i++) {
          final runtime = container.read(agentTurnRuntimeProvider);
          if (!runtime.hasActiveStudioRequest &&
              provider.messages.length >= 2) {
            final latestTurn = container
                .read(studioThreadProvider)
                .selectedThread
                ?.turns
                .lastOrNull;
            if (latestTurn?.status == StudioTurnStatus.completed) {
              return;
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      });
      await tester.pump();

      expect(provider.messages, hasLength(2));
      final continuationPrompt = provider.messages.last.last.content;
      expect(continuationPrompt, contains('accepted plan context'));
      expect(continuationPrompt, contains('Continue the remaining'));
      expect(continuationPrompt, contains('README.md'));
      expect(continuationPrompt, isNot(contains('hello.txt')));
      expect(provider.exposedTools.last, contains('propose_patch'));
      expect(provider.exposedTools.last, isNot(contains('apply_patch_set')));
      expect(provider.exposedTools.last, isNot(contains('run_command')));

      final continuedThread = container
          .read(studioThreadProvider)
          .selectedThread!;
      expect(continuedThread.turns, hasLength(2));
      final continuationTurn = continuedThread.turns.first;
      expect(continuationTurn.status, StudioTurnStatus.completed);
      expect(
        continuationTurn.acceptedPlanState,
        AcceptedPlanState.patchProposed,
      );
      expect(continuationTurn.acceptedPlanContext?.plannedFiles, [
        'README.md — Document usage',
      ]);
      await flushStudioThreadPersist(tester);
    },
  );

  test('Reloaded partial plan apply still derives continuation', () {
    const acceptedPlan = AcceptedPlanContext(
      patchSetId: 'plan-reload',
      title: 'Two batch plan',
      summary: 'Create the greeting and documentation.',
      markdown: '# Plan\n\n- Create hello.txt\n- Create README.md',
      plannedFiles: ['hello.txt — Add greeting', 'README.md — Document usage'],
    );
    final now = DateTime(2026);
    final appliedPatch = ProposedPatchSet(
      id: 'patch-reload-first-batch',
      title: 'Create greeting',
      runId: 'request-reload-partial',
      edits: const [
        ProposedFileEdit(
          path: 'hello.txt',
          type: ProposedFileEditType.create,
          after: 'hello after restart\n',
        ),
      ],
      applyStatus: PatchApplyStatus.applied,
      changedFiles: const ['hello.txt'],
      checkpointId: 'checkpoint-reload',
      diffSummary: 'Created hello.txt (+1 lines)',
      createdAt: now,
    );
    final thread = StudioThread(
      id: 'thread-reload-partial',
      title: 'Reloaded partial plan',
      status: StudioThreadStatus.done,
      phase: StudioSendPhase.completed,
      turns: [
        StudioTurn(
          id: 'turn-reload-partial',
          threadId: 'thread-reload-partial',
          requestId: 'request-reload-partial',
          userMessageId: 'message-reload-partial',
          prompt: 'Implement accepted plan',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(projectLabel: 'project'),
          status: StudioTurnStatus.completed,
          intent: TurnIntent.code,
          acceptedPlanState: AcceptedPlanState.patchProposed,
          acceptedPlanContext: acceptedPlan,
          planTargetProgress: [
            PlanTargetProgress(
              path: 'hello.txt',
              intent: 'Add greeting',
              operation: ProposedFileEditType.create,
              state: PlanTargetProgressState.applied,
              patchSetId: 'patch-reload-first-batch',
              updatedAt: now,
            ),
            PlanTargetProgress(
              path: 'README.md',
              intent: 'Document usage',
              operation: ProposedFileEditType.create,
              updatedAt: now,
            ),
          ],
          events: [
            StudioTurnEvent.completionSummary(
              id: 'patch-transaction-turn-reload-partial-patch-reload-first-batch-applied',
              turnId: 'turn-reload-partial',
              requestId: 'request-reload-partial',
              threadId: 'thread-reload-partial',
              title: 'Applied changes',
              detail:
                  'Applied 1 files.\nHere’s what changed: hello.txt\nCheckpoint: checkpoint-reload\nCreated hello.txt (+1 lines)\nNext batch: 1 accepted-plan target still needs work (README.md). Use Continue next batch to keep implementing the accepted plan.',
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

    final continuation = studioPlanContinuationForPatch(
      patch: appliedPatch,
      threads: [thread],
    );

    expect(continuation, isNotNull);
    expect(continuation!.appliedCount, 1);
    expect(continuation.totalCount, 2);
    expect(continuation.summaryLabel, '1 target remains');
    expect(continuation.remainingTargets.single.path, 'README.md');
    expect(continuation.acceptedPlan.patchSetId, 'plan-reload:next-batch');
    expect(continuation.acceptedPlan.plannedFiles, [
      'README.md — Document usage',
    ]);
    expect(continuation.acceptedPlan.markdown, contains('README.md'));
    expect(continuation.acceptedPlan.markdown, isNot(contains('hello.txt')));
  });

  test('Reloaded partial plan with proposed target still derives continuation', () {
    const acceptedPlan = AcceptedPlanContext(
      patchSetId: 'plan-reload-proposed',
      title: 'Two batch plan',
      summary: 'Create the greeting and documentation.',
      markdown: '# Plan\n\n- Create hello.txt\n- Create README.md',
      plannedFiles: ['hello.txt — Add greeting', 'README.md — Document usage'],
    );
    final now = DateTime(2026);
    final appliedPatch = ProposedPatchSet(
      id: 'patch-reload-proposed-batch',
      title: 'Create greeting',
      runId: 'request-reload-proposed',
      edits: const [
        ProposedFileEdit(
          path: 'hello.txt',
          type: ProposedFileEditType.create,
          after: 'hello after restart\n',
        ),
      ],
      applyStatus: PatchApplyStatus.applied,
      changedFiles: const ['hello.txt'],
      checkpointId: 'checkpoint-reload-proposed',
      diffSummary: 'Created hello.txt (+1 lines)',
      createdAt: now,
    );
    final thread = StudioThread(
      id: 'thread-reload-proposed',
      title: 'Reloaded proposed plan target',
      status: StudioThreadStatus.done,
      phase: StudioSendPhase.completed,
      turns: [
        StudioTurn(
          id: 'turn-reload-proposed',
          threadId: 'thread-reload-proposed',
          requestId: 'request-reload-proposed',
          userMessageId: 'message-reload-proposed',
          prompt: 'Implement accepted plan',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(projectLabel: 'project'),
          status: StudioTurnStatus.completed,
          intent: TurnIntent.code,
          acceptedPlanState: AcceptedPlanState.patchProposed,
          acceptedPlanContext: acceptedPlan,
          planTargetProgress: [
            PlanTargetProgress(
              path: 'hello.txt',
              intent: 'Add greeting',
              operation: ProposedFileEditType.create,
              state: PlanTargetProgressState.applied,
              patchSetId: 'patch-reload-proposed-batch',
              updatedAt: now,
            ),
            PlanTargetProgress(
              path: 'README.md',
              intent: 'Document usage',
              operation: ProposedFileEditType.create,
              state: PlanTargetProgressState.proposed,
              patchSetId: 'patch-stale-docs',
              detail: 'Prepared previously but not applied.',
              updatedAt: now,
            ),
          ],
          events: [
            StudioTurnEvent.completionSummary(
              id: 'patch-transaction-turn-reload-proposed-patch-reload-proposed-batch-applied',
              turnId: 'turn-reload-proposed',
              requestId: 'request-reload-proposed',
              threadId: 'thread-reload-proposed',
              title: 'Applied changes',
              detail:
                  'Applied 1 files.\nHere’s what changed: hello.txt\nCheckpoint: checkpoint-reload-proposed\nNext batch: 1 accepted-plan target still needs work (README.md). Use Continue next batch to keep implementing the accepted plan.',
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

    final continuation = studioPlanContinuationForPatch(
      patch: appliedPatch,
      threads: [thread],
    );

    expect(continuation, isNotNull);
    expect(continuation!.appliedCount, 1);
    expect(continuation.totalCount, 2);
    expect(continuation.remainingTargets.single.path, 'README.md');
    expect(
      continuation.remainingTargets.single.state,
      PlanTargetProgressState.proposed,
    );
    expect(continuation.acceptedPlan.plannedFiles, [
      'README.md — Document usage',
    ]);
    expect(continuation.acceptedPlan.plannedTargets.single.path, 'README.md');
    expect(continuation.acceptedPlan.markdown, contains('README.md'));
    expect(continuation.acceptedPlan.markdown, isNot(contains('hello.txt')));
  });

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
    expect(find.text('Edited 1 file'), findsOneWidget);
    expect(find.text('Restore checkpoint'), findsOneWidget);
    expect(find.text('Checkpoint history · 1'), findsOneWidget);
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
    'Studio Review Panel exposes restore controls and checkpoint preview state',
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
      expect(find.text('Edited 1 file'), findsOneWidget);
      expect(find.text('Restore checkpoint'), findsOneWidget);

      final restoreButton = find.widgetWithText(
        OutlinedButton,
        'Restore checkpoint',
      );
      expect(restoreButton, findsOneWidget);
      final restore = tester.widget<OutlinedButton>(restoreButton);
      expect(restore.onPressed, isNotNull);
      await tester.runAsync(() async {
        final checkpointId = renderedPatch.checkpointId!;
        final preview = await container
            .read(patchProposalProvider.notifier)
            .previewCheckpointRestore(checkpointId);
        expect(preview, isNotNull);
        final result = await container
            .read(patchProposalProvider.notifier)
            .restoreCheckpoint(checkpointId);
        expect(result.status, PatchApplyStatus.restored);
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
      expect(find.text('Patch conflict'), findsOneWidget);
      expect(find.textContaining('Needs rebase before apply'), findsOneWidget);
      expect(
        find.textContaining('File changed since proposal'),
        findsOneWidget,
      );
      expect(find.text('Apply changes'), findsNothing);
      expect(find.text('Refresh patch'), findsOneWidget);
      expect(find.text('Ask Circuit to rebase'), findsOneWidget);

      await tester.tap(find.text('Ask Circuit to rebase'));
      await tester.pump();

      final revisedState = container.read(patchProposalProvider);
      expect(revisedState.active, isNotNull);
      expect(
        revisedState.active!.approvalStatus,
        PatchApprovalStatus.revisionRequested,
      );
      expect(
        revisedState.active!.revisionPrompt,
        contains('Refresh these proposed changes against the current files'),
      );
      expect(revisedState.active!.revisionPrompt, contains('README.md'));
      final shell = container.read(studioShellProvider);
      expect(shell.promptMode, StudioPromptMode.code);
      expect(
        shell.composerText,
        contains('Refresh these proposed changes against the current files'),
      );
      expect(shell.composerText, contains('README.md'));
    },
  );

  test('Patch rebase send includes structured revision context', () {
    final patch = ProposedPatchSet(
      id: 'patch-1',
      title: 'Update README',
      edits: const [
        ProposedFileEdit(
          path: 'README.md',
          type: ProposedFileEditType.modify,
          before: 'old',
          after: 'new',
          conflictMessage: 'File changed since proposal: README.md',
        ),
      ],
      createdAt: DateTime(2026, 1, 1),
      approvalStatus: PatchApprovalStatus.revisionRequested,
      applyStatus: PatchApplyStatus.conflict,
      conflictMessage: 'File changed since proposal: README.md',
      revisionPrompt:
          'Refresh these proposed changes against the current files and preserve the accepted plan intent. Resolve: File changed since proposal: README.md',
    );

    final attachment = debugPatchRevisionContextAttachment(patch);
    expect(attachment.label, 'Patch revision context');
    expect(attachment.content, contains('Patch revision request'));
    expect(attachment.content, contains('Patch title: Update README'));
    expect(
      attachment.content,
      contains('Current conflict: File changed since proposal: README.md'),
    );
    expect(attachment.content, contains('Current proposed files:'));
    expect(attachment.content, contains('README.md — modify'));

    final outbound = debugPatchRevisionOutboundPrompt(
      patch.revisionPrompt!,
      patch,
    );
    expect(outbound, contains('Use the attached "Patch revision context"'));
    expect(
      outbound,
      contains('Produce exactly one concrete `propose_patch` result'),
    );
    expect(outbound, contains('Do not run commands'));
    expect(outbound, contains('Patch to revise: Update README'));
  });

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

void _expectCompactActionStyle(ButtonStyle? style) {
  const states = <WidgetState>{};
  expect(style, isNotNull);
  expect(style!.minimumSize?.resolve(states), const Size(0, 24));
  expect(style.tapTargetSize, MaterialTapTargetSize.shrinkWrap);
  expect(style.textStyle?.resolve(states)?.fontSize, FontSizes.xs);
  expect(style.textStyle?.resolve(states)?.fontWeight, FontWeight.w600);
  final shape = style.shape?.resolve(states);
  expect(shape, isA<RoundedRectangleBorder>());
  expect(
    (shape! as RoundedRectangleBorder).borderRadius,
    BorderRadius.circular(7),
  );
}

class _ShiftEnterSettingsNotifier extends SettingsNotifier {
  @override
  SettingsModel build() => const SettingsModel(sendOnEnter: false);
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

class _GatedStudioProvider extends _ScriptedStudioProvider {
  final started = Completer<void>();
  final _release = Completer<void>();

  _GatedStudioProvider(super.rounds);

  void complete() {
    if (!_release.isCompleted) _release.complete();
  }

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
    if (!started.isCompleted) started.complete();
    await _release.future;
    final round = _index < rounds.length
        ? rounds[_index++]
        : const <ChatChunk>[];
    for (final chunk in round) {
      yield chunk;
    }
  }
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
