import 'package:circuit_ide/models/agent_workspace.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/models/studio_shell.dart';
import 'package:circuit_ide/state/agent_workspace_provider.dart';
import 'package:circuit_ide/state/patch_proposal_provider.dart';
import 'package:circuit_ide/state/studio_shell_provider.dart';
import 'package:circuit_ide/ui/studio/studio_review_panel.dart';
import 'package:circuit_ide/ui/studio/studio_shell.dart';
import 'package:circuit_ide/ui/studio/studio_task_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('StudioShellProvider transitions between core views', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(studioShellProvider).mode, StudioMode.home);

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
    expect(find.text('Default permissions'), findsNothing);
    expect(find.text('gpt-5-nano'), findsOneWidget);
    expect(find.text('In 50.0M left / Out 5.0M left'), findsOneWidget);
    expect(find.text('Work locally'), findsNothing);
    expect(find.text('Search'), findsNothing);
    expect(find.text('Plugins'), findsNothing);
    expect(find.text('Automations'), findsNothing);
    expect(find.text('Circuit mobile'), findsNothing);
    expect(find.byTooltip('Add context'), findsNothing);
    expect(find.byTooltip('Voice input'), findsNothing);
  });

  testWidgets('Studio composer menus expose only working controls', (
    tester,
  ) async {
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

    await tester.tap(find.text('gpt-5-nano'));
    await tester.pumpAndSettle();
    expect(find.text('gemini-3.1-flash-lite'), findsOneWidget);
    expect(find.textContaining('120.0K context'), findsWidgets);
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
