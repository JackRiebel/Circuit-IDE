import 'package:circuit_ide/models/agent_workspace.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/models/studio_shell.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/state/agent_workspace_provider.dart';
import 'package:circuit_ide/state/patch_proposal_provider.dart';
import 'package:circuit_ide/state/studio_shell_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/ui/studio/studio_review_panel.dart';
import 'package:circuit_ide/ui/studio/studio_shell.dart';
import 'package:circuit_ide/ui/studio/studio_prompt_composer.dart';
import 'package:circuit_ide/ui/studio/studio_task_view.dart';
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

    container.read(studioShellProvider.notifier).openAdvancedEditor();
    expect(container.read(studioShellProvider).mode, StudioMode.advancedEditor);
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

  test('Plan implementation prompt includes full plan and planned files', () {
    final patch = ProposedPatchSet(
      id: 'plan-1',
      title: 'Plan',
      edits: const [],
      createdAt: DateTime(2026),
      planMarkdown: '# Build it\n\n- Add the service\n- Verify it',
      plannedFiles: const ['lib/main.dart - update entrypoint'],
    );

    final prompt = buildPlanImplementationPrompt(patch);

    expect(prompt, contains('Implement this approved plan.'));
    expect(prompt, contains('# Build it'));
    expect(prompt, contains('- lib/main.dart - update entrypoint'));
    expect(prompt, isNot(contains('\napprove\n')));
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
    expect(state.history.single.applyStatus, PatchApplyStatus.applied);
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
    expect(find.text('What should we build in Circuit-IDE?'), findsOneWidget);
    expect(find.text('Do anything'), findsOneWidget);
    expect(find.text('Review first'), findsOneWidget);
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Default permissions'), findsNothing);
    expect(find.text('gpt-5-nano'), findsOneWidget);
    expect(find.text('In 50.0M left / Out 5.0M left'), findsOneWidget);
    expect(find.text('Work locally'), findsNothing);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Plugins'), findsNothing);
    expect(find.text('Automations'), findsNothing);
    expect(find.text('Circuit mobile'), findsNothing);
    expect(find.byTooltip('Add context'), findsNothing);
    expect(find.byTooltip('Voice input'), findsNothing);
  });

  testWidgets('Studio composer menus expose only working controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: StudioShell())),
      ),
    );

    await tester.tap(find.text('Review first'));
    await tester.pumpAndSettle();
    expect(find.text('Auto approve tools'), findsOneWidget);
    await tester.tap(find.text('Auto approve tools'));
    await tester.pumpAndSettle();
    expect(find.text('Auto approve tools'), findsOneWidget);

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
    expect(find.text('Ready for next prompt'), findsNothing);
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
    expect(find.text('Progress'), findsOneWidget);
    expect(find.text('Environment'), findsOneWidget);
    expect(find.text('Push'), findsNothing);
    expect(find.text('Create pull request'), findsNothing);
    expect(find.text('Ask for follow-up changes'), findsOneWidget);
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
}
