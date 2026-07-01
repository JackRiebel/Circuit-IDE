import 'dart:io';

import 'package:circuit_ide/core/constants/design_tokens.dart';
import 'package:circuit_ide/models/command_run.dart';
import 'package:circuit_ide/models/context_pack.dart';
import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/models/git_models.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/models/studio_right_drawer.dart';
import 'package:circuit_ide/models/studio_shell.dart';
import 'package:circuit_ide/models/studio_source_artifact.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/state/context_pack_provider.dart';
import 'package:circuit_ide/state/command_run_provider.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/git_provider.dart';
import 'package:circuit_ide/state/patch_proposal_provider.dart';
import 'package:circuit_ide/state/studio_code_edit_provider.dart';
import 'package:circuit_ide/state/studio_right_drawer_provider.dart';
import 'package:circuit_ide/state/studio_shell_provider.dart';
import 'package:circuit_ide/state/studio_source_artifact_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/ui/studio/studio_right_drawer.dart';
import 'package:circuit_ide/ui/terminal/terminal_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> flushStudioThreadPersist(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1000));
  }

  test('detectLocalUrls finds local preview URLs and strips punctuation', () {
    final urls = detectLocalUrls(
      'Preview at http://127.0.0.1:4173. Also open http://localhost:3000/app), '
      'but ignore https://example.com.',
    );

    expect(urls, contains('http://127.0.0.1:4173'));
    expect(urls, contains('http://localhost:3000/app'));
    expect(urls, isNot(contains('https://example.com')));
  });

  test('StudioRightDrawerController opens artifact-specific surfaces', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(studioRightDrawerProvider.notifier);

    controller.openArtifact(
      StudioSourceArtifact(
        id: 'preview',
        kind: StudioSourceArtifactKind.localUrl,
        title: 'localhost',
        subtitle: 'http://localhost:3000',
        value: 'http://localhost:3000',
        localUrl: 'http://localhost:3000',
        createdAt: DateTime(2026),
      ),
    );

    expect(
      container.read(studioRightDrawerProvider).mode,
      StudioDrawerMode.sources,
    );
    expect(container.read(studioRightDrawerProvider).localUrl, isNull);

    controller.openArtifact(
      StudioSourceArtifact(
        id: 'command',
        kind: StudioSourceArtifactKind.command,
        title: 'npm run dev',
        subtitle: 'running',
        value: 'ready',
        commandRunId: 'run-1',
        createdAt: DateTime(2026),
      ),
    );

    expect(
      container.read(studioRightDrawerProvider).mode,
      StudioDrawerMode.terminal,
    );
    expect(container.read(studioRightDrawerProvider).commandRunId, 'run-1');

    controller.openPatchFile('patch-1', 'lib/main.dart');

    final state = container.read(studioRightDrawerProvider);
    expect(state.mode, StudioDrawerMode.diff);
    expect(state.diffId, 'patch-1');
    expect(state.patchFilePath, 'lib/main.dart');
    expect(state.filePath, 'lib/main.dart');

    controller.openContext();
    expect(
      container.read(studioRightDrawerProvider).mode,
      StudioDrawerMode.context,
    );
  });

  testWidgets('Studio drawer hides quarantined browser preview tab', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.code);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Align(child: StudioRightDrawer())),
        ),
      ),
    );

    expect(find.byTooltip('Open drawer view'), findsOneWidget);

    await tester.tap(find.byTooltip('Open drawer view'));
    await tester.pumpAndSettle();

    expect(find.text('Progress'), findsWidgets);
    expect(find.text('Artifacts'), findsAtLeastNWidgets(1));
    expect(find.text('Code'), findsWidgets);
    expect(find.text('Diff'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Terminal output'), findsOneWidget);
    expect(find.text('Context details'), findsOneWidget);
    expect(find.byTooltip('Browser preview'), findsNothing);
  });

  test(
    'Studio drawer body guards stale browser mode behind feature flag',
    () async {
      final source = await File(
        'lib/ui/studio/studio_right_drawer.dart',
      ).readAsString();

      expect(source, contains('StudioFeatureFlags.advancedStudioSurfaces'));
      expect(source, contains('safeMode'));
      expect(source, contains('StudioDrawerMode.sources'));
    },
  );

  test('Studio source artifacts quarantine browser comments', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(studioSourceArtifactProvider.notifier)
        .add(
          StudioSourceArtifact(
            id: 'browser-comment',
            kind: StudioSourceArtifactKind.browserComment,
            title: 'Browser comment',
            subtitle: 'http://localhost:3000',
            value: 'note',
            threadId: 'thread-1',
            localUrl: 'http://localhost:3000',
            createdAt: DateTime(2026),
          ),
        );
    container
        .read(studioSourceArtifactProvider.notifier)
        .add(
          StudioSourceArtifact(
            id: 'file-artifact',
            kind: StudioSourceArtifactKind.file,
            title: 'lib/main.dart',
            subtitle: 'Context file',
            value: 'lib/main.dart',
            threadId: 'thread-1',
            filePath: 'lib/main.dart',
            createdAt: DateTime(2026),
          ),
        );

    final artifacts = container
        .read(studioSourceArtifactProvider)
        .forThread('thread-1');
    expect(
      artifacts.map((artifact) => artifact.kind),
      isNot(contains(StudioSourceArtifactKind.browserComment)),
    );
    expect(
      artifacts.map((artifact) => artifact.kind),
      contains(StudioSourceArtifactKind.file),
    );
  });

  testWidgets('Studio drawer typography and icons match compact chrome scale', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Align(child: StudioRightDrawer())),
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('Progress').first);
    expect(title.style?.fontSize, FontSizes.sm);
    expect(title.style?.fontWeight, FontWeight.w500);

    final contextIcon = tester.widget<Icon>(
      find.byIcon(Icons.inventory_2_outlined).first,
    );
    expect(contextIcon.size, 13);
    expect(find.byTooltip('Open drawer view'), findsNothing);
    expect(find.text('Status'), findsNothing);
    expect(find.byTooltip('Progress'), findsOneWidget);
    expect(find.byTooltip('Artifacts'), findsOneWidget);
    expect(find.byTooltip('Context details'), findsOneWidget);
    expect(find.byIcon(Icons.language), findsNothing);

    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.code);
    await tester.pump();

    final modeMenuIcon = tester.widget<Icon>(find.byIcon(Icons.tune_outlined));
    expect(modeMenuIcon.size, 13);

    await tester.tap(find.byTooltip('Open drawer view'));
    await tester.pumpAndSettle();

    final codeIcon = tester.widget<Icon>(find.byIcon(Icons.code).last);
    expect(codeIcon.size, 13);
    final codeText = tester.widget<Text>(find.text('Code').last);
    expect(codeText.style?.fontSize, FontSizes.xs);

    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    container.read(studioRightDrawerProvider.notifier).toggleCollapsed();
    await tester.pump();

    expect(find.widgetWithIcon(IconButton, Icons.chevron_left), findsNothing);
    final collapsedExpandIcon = tester.widget<Icon>(
      find.byIcon(Icons.chevron_left),
    );
    expect(collapsedExpandIcon.size, 14);
    final collapsedModeFinder = find.byIcon(Icons.radio_button_checked).first;
    final collapsedModeIcon = tester.widget<Icon>(collapsedModeFinder);
    expect(collapsedModeIcon.size, 13);
    final collapsedModeContainer = tester.widget<Container>(
      find
          .ancestor(of: collapsedModeFinder, matching: find.byType(Container))
          .first,
    );
    final collapsedModeDecoration = collapsedModeContainer.decoration;
    expect(collapsedModeDecoration, isA<BoxDecoration>());
    expect(
      (collapsedModeDecoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(7),
    );
  });

  testWidgets('Studio terminal drawer is command-log only', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.terminal);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Align(child: StudioRightDrawer())),
        ),
      ),
    );

    expect(find.byType(TerminalPanel), findsNothing);
    expect(find.text('No command logs'), findsOneWidget);
    expect(
      find.textContaining('does not expose an interactive terminal'),
      findsOneWidget,
    );
  });

  testWidgets('Studio terminal drawer scopes command logs to selected thread', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Command thread');
    final turn = StudioTurn(
      id: 'turn-selected',
      threadId: thread.id,
      requestId: 'request-selected',
      userMessageId: 'message-selected',
      prompt: 'Run selected command',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);
    await flushStudioThreadPersist(tester);

    final commandController = container.read(commandRunProvider.notifier);
    commandController.start(
      id: 'cmd-selected',
      command: 'npm test',
      requestId: 'request-selected',
      turnId: 'turn-selected',
      taskId: thread.taskId,
    );
    commandController.append(
      'cmd-selected',
      CommandRunEventType.stdout,
      'selected output\n',
    );
    commandController.finish(
      'cmd-selected',
      status: CommandRunStatus.succeeded,
      exitCode: 0,
    );
    commandController.start(
      id: 'cmd-foreign',
      command: 'npm run dev',
      requestId: 'request-foreign',
      turnId: 'turn-foreign',
      taskId: 'other-task',
    );
    commandController.append(
      'cmd-foreign',
      CommandRunEventType.stdout,
      'leaked output\n',
    );
    commandController.finish(
      'cmd-foreign',
      status: CommandRunStatus.succeeded,
      exitCode: 0,
    );

    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.terminal);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Align(child: StudioRightDrawer())),
        ),
      ),
    );

    expect(find.text('npm test'), findsNWidgets(2));
    expect(find.textContaining('selected output'), findsOneWidget);
    expect(find.text('npm run dev'), findsNothing);
    expect(find.textContaining('leaked output'), findsNothing);

    container
        .read(studioRightDrawerProvider.notifier)
        .openCommand('cmd-foreign');
    await tester.pump();

    expect(find.text('npm run dev'), findsNothing);
    expect(find.textContaining('leaked output'), findsNothing);
    expect(find.textContaining('selected output'), findsOneWidget);
  });

  testWidgets('Studio terminal drawer restores persisted command logs', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Restored command thread');
    final timestamp = DateTime(2026, 1, 1, 10);
    final turn = StudioTurn(
      id: 'turn-restored-command',
      threadId: thread.id,
      requestId: 'request-restored-command',
      userMessageId: 'message-restored-command',
      prompt: 'Verify the change',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      createdAt: timestamp,
      updatedAt: timestamp,
      completedAt: timestamp,
      events: [
        StudioTurnEvent.completionSummary(
          id: 'command-run-turn-restored-command-cmd-restored',
          turnId: 'turn-restored-command',
          requestId: 'request-restored-command',
          threadId: thread.id,
          title: 'Ran command',
          detail: 'Command: npm test\nExit code: 0\nrestored output\n',
          timestamp: timestamp,
        ),
      ],
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);
    await flushStudioThreadPersist(tester);
    expect(container.read(commandRunProvider), isEmpty);

    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.terminal);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Align(child: StudioRightDrawer())),
        ),
      ),
    );

    expect(find.text('npm test'), findsWidgets);
    expect(find.textContaining('restored output'), findsOneWidget);
    expect(find.text('No command logs'), findsNothing);
  });

  testWidgets('Studio Git diff drawer is review-only', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: [gitProvider.overrideWith(_ReviewOnlyGitNotifier.new)],
    );
    addTearDown(container.dispose);
    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.diff);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Repository changes'), findsOneWidget);
    final repositoryChanges = tester.widget<Text>(
      find.text('Repository changes'),
    );
    expect(repositoryChanges.style?.fontWeight, FontWeight.w600);
    expect(find.text('README.md'), findsWidgets);
    expect(find.text('Review only'), findsOneWidget);
    final reviewOnly = tester.widget<Text>(find.text('Review only'));
    expect(reviewOnly.style?.fontWeight, FontWeight.w600);
    expect(find.text('Stage'), findsNothing);
    expect(find.text('Unstage'), findsNothing);
  });

  testWidgets('Studio Diff drawer opens historical patch by id', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final patchController = container.read(patchProposalProvider.notifier);
    final patch = patchController.propose(
      title: 'Prepared archived changes',
      edits: const [
        ProposedFileEdit(
          path: 'lib/main.dart',
          type: ProposedFileEditType.modify,
          before: 'old',
          after: 'new',
          unifiedDiff: '@@ -1 +1 @@\n-old\n+new',
        ),
        ProposedFileEdit(
          path: 'lib/feature.dart',
          type: ProposedFileEditType.create,
          after: 'feature',
          unifiedDiff: '@@ -0,0 +1 @@\n+feature',
        ),
      ],
    );
    patchController.reject(patch.id);
    expect(container.read(patchProposalProvider).active, isNull);
    expect(
      container.read(patchProposalProvider).history.map((item) => item.id),
      contains(patch.id),
    );
    container
        .read(studioRightDrawerProvider.notifier)
        .openPatchFile(patch.id, 'lib/main.dart');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Align(child: StudioRightDrawer())),
        ),
      ),
    );

    expect(find.text('Prepared archived changes'), findsOneWidget);
    expect(find.textContaining('2 files', findRichText: true), findsOneWidget);
    expect(find.text('lib/main.dart'), findsWidgets);
    expect(find.textContaining('@@ -1 +1 @@'), findsOneWidget);
    expect(find.text('No changes'), findsNothing);

    await tester.tap(find.text('lib/feature.dart').first);
    await tester.pump();

    final drawer = container.read(studioRightDrawerProvider);
    expect(drawer.diffId, patch.id);
    expect(drawer.patchFilePath, 'lib/feature.dart');
    expect(find.textContaining('@@ -0,0 +1 @@'), findsOneWidget);
  });

  testWidgets('Studio Diff drawer defaults to selected thread patch history', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final threadController = container.read(studioThreadProvider.notifier);
    final thread = threadController.createBlankThread(title: 'Patch owner');
    final timestamp = DateTime(2026, 1, 2);
    threadController.upsertTurn(
      thread.id,
      StudioTurn(
        id: 'turn-owner',
        threadId: thread.id,
        requestId: 'request-owner',
        userMessageId: 'message-owner',
        prompt: 'Prepare changes',
        model: 'gpt-5-nano',
        contextSummary: const StudioContextSummary(projectLabel: 'project'),
        status: StudioTurnStatus.completed,
        createdAt: timestamp,
        updatedAt: timestamp,
        completedAt: timestamp,
      ),
      select: true,
    );
    await flushStudioThreadPersist(tester);

    final patchController = container.read(patchProposalProvider.notifier);
    final threadPatch = patchController.propose(
      title: 'Thread-owned prepared changes',
      runId: 'request-owner',
      edits: const [
        ProposedFileEdit(
          path: 'lib/thread_owned.dart',
          type: ProposedFileEditType.create,
          after: 'void threadOwned() {}\n',
          unifiedDiff:
              '--- /dev/null\n+++ lib/thread_owned.dart\n@@\n+void threadOwned() {}\n',
        ),
      ],
    );
    patchController.preserveProposal(
      threadPatch.copyWith(
        applyStatus: PatchApplyStatus.applied,
        changedFiles: const ['lib/thread_owned.dart'],
        diffSummary: 'Created lib/thread_owned.dart (+1 lines)',
      ),
    );
    patchController.propose(
      title: 'Unrelated active patch',
      runId: 'request-other',
      edits: const [
        ProposedFileEdit(
          path: 'lib/unrelated.dart',
          type: ProposedFileEditType.create,
          after: 'void unrelated() {}\n',
          unifiedDiff:
              '--- /dev/null\n+++ lib/unrelated.dart\n@@\n+void unrelated() {}\n',
        ),
      ],
    );
    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.diff);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Align(child: StudioRightDrawer())),
        ),
      ),
    );

    expect(find.text('Thread-owned prepared changes'), findsOneWidget);
    expect(find.text('lib/thread_owned.dart'), findsWidgets);
    expect(find.textContaining('void threadOwned'), findsOneWidget);
    expect(find.text('Unrelated active patch'), findsNothing);
    expect(find.text('No changes'), findsNothing);
  });

  testWidgets('Studio Diff drawer explains stale selected patch review', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(studioRightDrawerProvider.notifier)
        .openPatchFile('missing-patch', 'lib/missing.dart');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Align(child: StudioRightDrawer())),
        ),
      ),
    );

    expect(find.text('Patch review unavailable'), findsOneWidget);
    expect(find.textContaining('missing-patch'), findsOneWidget);
    expect(find.text('No changes'), findsNothing);

    await tester.tap(find.text('Show repo changes'));
    await tester.pump();

    final drawer = container.read(studioRightDrawerProvider);
    expect(drawer.mode, StudioDrawerMode.diff);
    expect(drawer.diffId, isNull);
    expect(drawer.patchFilePath, isNull);
  });

  testWidgets('Studio Diff drawer virtualizes large patch bodies', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final largeDiff = [
      '@@ -0,0 +600 @@',
      for (var index = 0; index < 600; index++)
        '+line-${index.toString().padLeft(3, '0')}',
    ].join('\n');
    final patch = container
        .read(patchProposalProvider.notifier)
        .propose(
          title: 'Prepared large changes',
          edits: [
            ProposedFileEdit(
              path: 'lib/large.dart',
              type: ProposedFileEditType.create,
              after: List.generate(
                600,
                (index) => 'line-${index.toString().padLeft(3, '0')}',
              ).join('\n'),
              unifiedDiff: largeDiff,
            ),
          ],
        );
    container
        .read(studioRightDrawerProvider.notifier)
        .openPatchFile(patch.id, 'lib/large.dart');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
      ),
    );

    expect(find.text('+line-000'), findsOneWidget);
    expect(find.text('+line-599'), findsNothing);

    await tester.dragUntilVisible(
      find.text('+line-599'),
      find.byKey(const ValueKey('studio-virtualized-text-lines')),
      const Offset(0, -500),
    );

    expect(find.text('+line-599'), findsOneWidget);
  });

  testWidgets('Studio Diff drawer exposes patch review actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final patch = container
        .read(patchProposalProvider.notifier)
        .propose(
          title: 'Prepared drawer changes',
          edits: const [
            ProposedFileEdit(
              path: 'README.md',
              type: ProposedFileEditType.modify,
              before: 'old',
              after: 'new',
              unifiedDiff: '@@ -1 +1 @@\n-old\n+new',
            ),
          ],
        );
    container
        .read(studioRightDrawerProvider.notifier)
        .openPatchFile(patch.id, 'README.md');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
      ),
    );

    expect(find.text('Apply changes'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    expect(find.text('Ask for revision'), findsOneWidget);

    await tester.tap(find.text('Ask for revision'));
    await tester.pump();

    final updatedPatch = container.read(patchProposalProvider).active!;
    expect(updatedPatch.id, patch.id);
    expect(updatedPatch.approvalStatus, PatchApprovalStatus.revisionRequested);
    final shell = container.read(studioShellProvider);
    expect(shell.promptMode, StudioPromptMode.code);
    expect(shell.composerText, 'Revise these proposed changes. Change: ');
  });

  testWidgets('Studio Diff drawer builds readable diffs from before after text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final patch = container
        .read(patchProposalProvider.notifier)
        .propose(
          title: 'Prepared content-only changes',
          edits: const [
            ProposedFileEdit(
              path: 'lib/content_only.dart',
              type: ProposedFileEditType.modify,
              before: 'class Example {\n  int value = 1;\n}\n',
              after:
                  'class Example {\n  int value = 2;\n  String label = "ready";\n}\n',
            ),
          ],
        );
    container
        .read(studioRightDrawerProvider.notifier)
        .openPatchFile(patch.id, 'lib/content_only.dart');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
      ),
    );

    expect(find.text('Prepared content-only changes'), findsOneWidget);
    expect(find.textContaining('+2 -1', findRichText: true), findsOneWidget);
    expect(find.text('@@ -1,3 +1,4 @@'), findsOneWidget);
    expect(find.text(' class Example {'), findsOneWidget);
    expect(find.text('-  int value = 1;'), findsOneWidget);
    expect(find.text('+  int value = 2;'), findsOneWidget);
    expect(find.text('+  String label = "ready";'), findsOneWidget);
    expect(find.text('- class Example {\\n  int value = 1;\\n}'), findsNothing);
  });

  testWidgets('Studio Diff drawer refreshes conflicted patch in place', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final root = Directory.systemTemp.createTempSync('studio_drawer_refresh_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    File('${root.path}/README.md').writeAsStringSync('changed on disk');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(fileTreeProvider.notifier).openDirectory(root.path),
    );
    final patch = container
        .read(patchProposalProvider.notifier)
        .propose(
          title: 'Conflicted drawer changes',
          edits: const [
            ProposedFileEdit(
              path: 'README.md',
              type: ProposedFileEditType.modify,
              before: 'old',
              after: 'new',
              unifiedDiff: '@@ -1 +1 @@\n-old\n+new',
            ),
          ],
        );
    final result = await tester.runAsync(
      () => container.read(patchProposalProvider.notifier).apply(patch.id),
    );
    expect(result?.status, PatchApplyStatus.conflict);
    container
        .read(studioRightDrawerProvider.notifier)
        .openPatchFile(patch.id, 'README.md');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
      ),
    );

    expect(find.text('Refresh patch'), findsOneWidget);
    expect(find.text('Ask Circuit to rebase'), findsOneWidget);

    await tester.tap(find.text('Refresh patch'));
    await tester.pump();

    final refreshedPatch = container.read(patchProposalProvider).active!;
    expect(refreshedPatch.id, patch.id);
    expect(
      refreshedPatch.approvalStatus,
      PatchApprovalStatus.revisionRequested,
    );
    final shell = container.read(studioShellProvider);
    expect(shell.promptMode, StudioPromptMode.code);
    expect(
      shell.composerText,
      contains('Refresh this patch against the current file contents'),
    );
    expect(shell.composerText, isNot(contains('accepted plan intent')));
  });

  testWidgets('Studio code drawer is read-only', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final root = Directory.systemTemp.createTempSync('studio_code_drawer_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    File('${root.path}/README.md').writeAsStringSync('hello preview\n');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(fileTreeProvider.notifier).openDirectory(root.path),
    );
    await tester.runAsync(
      () => container.read(studioCodeEditProvider.notifier).open('README.md'),
    );
    container.read(studioRightDrawerProvider.notifier).openFile('README.md');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('Read only'), findsOneWidget);
    expect(find.textContaining('hello preview'), findsOneWidget);
    expect(find.widgetWithIcon(IconButton, Icons.copy), findsNothing);
    final copyIcon = tester.widget<Icon>(find.byIcon(Icons.copy));
    expect(copyIcon.size, 14);
    final copyContainer = tester.widget<Container>(
      find
          .ancestor(
            of: find.byIcon(Icons.copy),
            matching: find.byType(Container),
          )
          .first,
    );
    final copyDecoration = copyContainer.decoration;
    expect(copyDecoration, isA<BoxDecoration>());
    expect(
      (copyDecoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(6),
    );
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Revert'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  test('StudioSourceArtifactController keeps long source history', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(studioSourceArtifactProvider.notifier);

    for (var i = 0; i < 130; i++) {
      controller.add(
        StudioSourceArtifact(
          id: 'artifact-$i',
          kind: StudioSourceArtifactKind.command,
          title: 'command $i',
          subtitle: 'completed',
          value: 'output $i',
          createdAt: DateTime(2026).add(Duration(minutes: i)),
        ),
      );
    }

    final artifacts = container.read(studioSourceArtifactProvider).artifacts;
    expect(artifacts, hasLength(130));
    expect(artifacts.first.id, 'artifact-129');
    expect(artifacts.last.id, 'artifact-0');
  });

  testWidgets(
    'Artifacts drawer shows selected artifact metadata and binary preview',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final artifact = GeneratedArtifact(
        id: 'pdf-1',
        kind: GeneratedArtifactKind.pdf,
        status: GeneratedArtifactStatus.ready,
        fileName: 'campus-refresh.pdf',
        filePath: '/tmp/campus-refresh.pdf',
        summary: 'Created a PDF handoff report.',
        byteSize: 2048,
        previewRows: const [
          ['Section', 'Type', 'Items'],
          ['1', 'Executive Summary', '1'],
          ['2', 'Recommendations', '4'],
        ],
        sheetCount: 2,
        metadata: const {
          'reportType': 'Architecture report',
          'audience': 'Architecture reviewers',
          'reportPurpose': 'Review findings, risks, and recommendations',
          'handoffStatus': 'Ready for stakeholder review',
          'decisionOwner': 'Architecture owner / customer sponsor',
          'decisionAsk':
              'Review findings, confirm assumptions, and approve the recommended architecture path.',
          'reviewPath':
              'Architecture review -> risk validation -> implementation decision',
          'documentParts': [
            'Executive decision brief',
            'Recommendation summary',
            'Risk register',
            'Next-step action plan',
            'Document map',
            'Evidence confidence matrix',
            'Approval gates',
            'Validation checklist',
            'Data tables',
            'Assumptions appendix',
            'Sources appendix',
          ],
          'readinessSignals': [
            'Decision brief',
            'Recommendation summary',
            'Risk register',
            'Next steps',
            'Validation checklist',
            'Data tables',
            'Assumptions',
            'Sources',
          ],
          'pageCount': 2,
          'bookmarkCount': 8,
          'reportSectionCount': 12,
          'sectionCount': 4,
          'tableCount': 1,
          'assumptionCount': 2,
          'citationCount': 3,
          'evidenceGapCount': 0,
          'approvalGateCount': 4,
          'tableCoverage': '1 table packaged',
          'evidenceCoverage': '3 source items captured',
          'appendixCoverage': '2 assumptions, 3 source items in appendices',
          'validationGaps': <String>[],
          'validationGapCount': 0,
          'hasCustomerReadyPackage': true,
          'hasCustomerReadyPdf': true,
        },
        threadId: null,
        requestId: 'request-pdf',
        createdAt: DateTime(2026, 6, 30, 9, 12),
      );
      container
          .read(studioSourceArtifactProvider.notifier)
          .add(artifact.toSourceArtifact());
      container
          .read(studioRightDrawerProvider.notifier)
          .openMode(StudioDrawerMode.artifacts);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
        ),
      );
      await tester.pump();

      expect(find.text('campus-refresh.pdf'), findsOneWidget);
      expect(
        find.textContaining('PDF • Architecture report • 8 bookmarks'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Ready for stakeholder review'),
        findsOneWidget,
      );
      expect(find.text('PDF outline'), findsOneWidget);
      expect(find.text('2 pages'), findsOneWidget);
      expect(find.text('Section'), findsOneWidget);
      expect(find.text('Executive Summary'), findsOneWidget);
      expect(
        find.textContaining('Open to inspect the full document'),
        findsNothing,
      );
      expect(find.text('2 pages'), findsOneWidget);
      expect(
        find.text('Final handoff artifact for fixed review'),
        findsOneWidget,
      );

      await tester.tap(find.text('campus-refresh.pdf'));
      await tester.pump();

      expect(find.text('Type'), findsAtLeastNWidgets(1));
      expect(find.text('Architecture report'), findsOneWidget);
      expect(find.text('Audience'), findsAtLeastNWidgets(1));
      expect(find.text('Architecture reviewers'), findsOneWidget);
      expect(find.text('Purpose'), findsAtLeastNWidgets(1));
      expect(
        find.text('Review findings, risks, and recommendations'),
        findsOneWidget,
      );
      expect(find.text('Handoff'), findsOneWidget);
      expect(find.text('Ready for stakeholder review'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      expect(
        find.text('Architecture owner / customer sponsor'),
        findsOneWidget,
      );
      expect(find.text('Ask'), findsOneWidget);
      expect(
        find.text(
          'Review findings, confirm assumptions, and approve the recommended architecture path.',
        ),
        findsOneWidget,
      );
      expect(find.text('Review path'), findsOneWidget);
      expect(
        find.text(
          'Architecture review -> risk validation -> implementation decision',
        ),
        findsOneWidget,
      );
      expect(find.text('Parts'), findsOneWidget);
      expect(
        find.textContaining(
          'Executive decision brief, Recommendation summary +9',
        ),
        findsOneWidget,
      );
      expect(find.text('Readiness'), findsAtLeastNWidgets(1));
      expect(
        find.text('Decision brief, Recommendation summary +6'),
        findsOneWidget,
      );
      expect(find.text('1 table packaged'), findsOneWidget);
      expect(find.text('Evidence'), findsOneWidget);
      expect(find.text('3 source items captured'), findsOneWidget);
      expect(find.text('Appendices'), findsOneWidget);
      expect(
        find.text('2 assumptions, 3 source items in appendices'),
        findsOneWidget,
      );
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Format'), findsOneWidget);
      expect(find.text('Pages'), findsOneWidget);
      expect(find.text('Bookmarks'), findsOneWidget);
      expect(find.text('Report parts'), findsOneWidget);
      expect(find.text('Sections'), findsOneWidget);
      expect(find.text('Tables'), findsOneWidget);
      expect(find.text('Assumptions'), findsOneWidget);
      expect(find.text('Sources'), findsOneWidget);
      expect(find.text('Approval gates'), findsOneWidget);
      expect(find.text('Package'), findsOneWidget);
      expect(find.text('Customer-ready report flow'), findsOneWidget);
      expect(find.text('Handoff package'), findsOneWidget);
      expect(find.text('Final customer PDF'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      expect(find.text('Request'), findsOneWidget);
      expect(find.text('Folder'), findsOneWidget);
      expect(find.text('Path'), findsOneWidget);
      expect(find.text('request-pdf'), findsOneWidget);
      expect(find.text('/tmp/campus-refresh.pdf'), findsOneWidget);
    },
  );

  testWidgets('Artifacts drawer shows solution sizing workbook metadata', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final artifact = GeneratedArtifact(
      id: 'sizing-1',
      kind: GeneratedArtifactKind.excel,
      status: GeneratedArtifactStatus.ready,
      fileName: 'campus-sizing.xlsx',
      filePath: '/tmp/campus-sizing.xlsx',
      summary:
          'Created a solution sizing workbook with executive summary, PoE, WAN, validation, and source sheets.',
      byteSize: 16384,
      previewRows: const [
        [
          'Executive Signal',
          'Current Value',
          'Sizing Interpretation',
          'Next Action',
        ],
        [
          'Demand baseline',
          '500 users, 90 APs, 6 switches',
          'Review',
          'Confirm',
        ],
      ],
      sheetCount: 19,
      metadata: const {
        'artifact': 'solution_sizing_workbook',
        'workbookKind': 'solution_sizing',
        'sheetCount': 19,
        'sourceSheetCount': 1,
        'requirementCount': 5,
        'gateCount': 6,
        'candidateCheckCount': 3,
        'riskCount': 5,
        'highRiskCount': 3,
        'validationCheckCount': 5,
        'recommendationCount': 2,
        'users': '500',
        'accessPoints': '90',
        'switches': '6',
        'wan': '2 Gbps',
        'growth': '25%',
        'hasHighPowerApSignal': true,
        'hasMultigigSignal': true,
        'hasLifecycleValidation': true,
        'qualityStatus': 'Customer ready',
        'qualityScore': 96,
        'qualityGates': [
          'File generated',
          'Native format ready',
          'Workbook sheets packaged',
          'Header and data rows detected',
        ],
        'qualityGaps': [],
        'qualityNextAction': 'Ready for customer handoff.',
        'hasCustomerReadyArtifact': true,
      },
      createdAt: DateTime(2026, 7, 1, 12),
    );
    container
        .read(studioSourceArtifactProvider.notifier)
        .add(artifact.toSourceArtifact());
    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.artifacts);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
      ),
    );
    await tester.pump();

    expect(find.text('campus-sizing.xlsx'), findsOneWidget);
    expect(find.textContaining('Excel • Customer ready'), findsOneWidget);
    expect(find.textContaining('500 users'), findsAtLeastNWidgets(1));
    expect(find.textContaining('2 Gbps'), findsOneWidget);
    expect(find.textContaining('6 gates'), findsOneWidget);
    expect(find.textContaining('5 risks'), findsOneWidget);
    expect(find.text('Workbook preview'), findsOneWidget);
    expect(find.text('Demand baseline'), findsOneWidget);

    await tester.tap(find.text('campus-sizing.xlsx'));
    await tester.pump();

    expect(find.text('Users'), findsOneWidget);
    expect(find.text('Quality'), findsOneWidget);
    expect(find.text('Customer ready'), findsAtLeastNWidgets(1));
    expect(find.text('Score'), findsOneWidget);
    expect(find.text('96/100'), findsOneWidget);
    expect(find.text('Gates'), findsAtLeastNWidgets(1));
    expect(
      find.textContaining('File generated, Native format ready +2'),
      findsOneWidget,
    );
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Ready for customer handoff.'), findsOneWidget);
    expect(find.text('Ready'), findsAtLeastNWidgets(1));
    expect(find.text('Customer handoff candidate'), findsOneWidget);
    expect(find.text('APs'), findsOneWidget);
    expect(find.text('Switches'), findsOneWidget);
    expect(find.text('WAN'), findsOneWidget);
    expect(find.text('Growth'), findsOneWidget);
    expect(find.text('Gates'), findsAtLeastNWidgets(1));
    expect(find.text('Risks'), findsOneWidget);
    expect(find.text('High risk'), findsOneWidget);
    expect(find.text('Candidate checks'), findsOneWidget);
    expect(find.text('Validation'), findsOneWidget);
    expect(find.text('Recommendations'), findsOneWidget);
    expect(find.text('Power'), findsOneWidget);
    expect(find.text('Access speed'), findsOneWidget);
    expect(find.text('Lifecycle'), findsOneWidget);
    expect(find.text('High-power AP/UPOE signal'), findsOneWidget);
    expect(find.text('mGig validation signal'), findsOneWidget);
    expect(find.text('Validation included'), findsOneWidget);
  });

  testWidgets('Artifacts drawer explains deck and document artifacts', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(studioSourceArtifactProvider.notifier)
      ..add(
        GeneratedArtifact(
          id: 'deck-1',
          kind: GeneratedArtifactKind.powerPoint,
          status: GeneratedArtifactStatus.ready,
          fileName: 'executive-brief.pptx',
          filePath: '/tmp/executive-brief.pptx',
          summary: 'Created a customer presentation deck.',
          byteSize: 8192,
          previewRows: const [
            ['Slide', 'Type', 'Title'],
            ['1', 'Title', 'Executive Brief'],
            ['2', 'Agenda', 'Decision Flow'],
          ],
          sheetCount: 6,
          metadata: const {
            'deckType': 'Customer proposal deck',
            'handoffStatus': 'Ready for stakeholder review',
            'decisionAsk':
                'Review the recommendation, confirm assumptions, and approve the next implementation step.',
            'theme': 'Light',
            'audience': 'Executive stakeholders',
            'deckPurpose': 'Support a decision',
            'narrativeArc': 'Context -> risk -> recommendation -> action',
            'agendaItems': [
              'Executive summary',
              'Current State',
              'Recommended Architecture',
              'Data tables and supporting detail',
              'Assumptions and sources',
            ],
            'slideFamilies': [
              'Opening',
              'Agenda',
              'Decision snapshot',
              'Recommendations',
              'Roadmap',
              'Data tables',
              'Assumptions/sources',
              'Appendix',
            ],
            'tableCoverage': '2 tables packaged',
            'sourceCoverage': '5 source items captured',
            'evidenceConfidence': 'High - sources and assumptions captured',
            'deckReviewChecklist': [
              'Confirm deck title, audience, and decision ask match the customer conversation.',
              'Review presenter talk track for account-specific phrasing.',
              'Validate decision matrix signals, risk posture, and next actions.',
            ],
            'deckHandoffActions': [
              'Send deck to internal reviewer with the source artifact attached.',
              'Walk through the decision ask: Review the recommendation, confirm assumptions, and approve the next implementation step.',
              'Keep cited sources with the handoff package.',
            ],
            'presentationRiskFlags': <String>[],
            'validationGaps': <String>[],
            'validationGapCount': 0,
            'readinessSignals': [
              'Agenda',
              'Decision snapshot',
              'Recommendation slides',
              'Roadmap',
              'Speaker notes',
            ],
            'sectionCount': 4,
            'sectionDividerCount': 3,
            'tableCount': 2,
            'tableSlideCount': 2,
            'recommendationSlideCount': 2,
            'assumptionCount': 3,
            'citationCount': 5,
            'hasCustomerReadyStructure': true,
            'hasCustomerReadyDeck': true,
            'hasSpeakerNotes': true,
          },
          createdAt: DateTime(2026, 6, 30, 9, 15),
        ).toSourceArtifact(),
      )
      ..add(
        GeneratedArtifact(
          id: 'docx-1',
          kind: GeneratedArtifactKind.docx,
          status: GeneratedArtifactStatus.ready,
          fileName: 'architecture-review.docx',
          filePath: '/tmp/architecture-review.docx',
          summary: 'Created an architecture review report.',
          byteSize: 4096,
          previewRows: const [
            ['Section', 'Type', 'Items'],
            ['1', 'Findings', '5'],
            ['2', 'Risk Register', '4'],
          ],
          sheetCount: 4,
          metadata: const {
            'reportType': 'Architecture report',
            'audience': 'Architecture reviewers',
            'reportPurpose': 'Review findings, risks, and recommendations',
            'handoffStatus': 'Ready for stakeholder review',
            'decisionOwner': 'Architecture owner / customer sponsor',
            'decisionAsk':
                'Review findings, confirm assumptions, and approve the recommended architecture path.',
            'reviewPath':
                'Architecture review -> risk validation -> implementation decision',
            'documentParts': [
              'Executive decision brief',
              'Recommendation summary',
              'Risk register',
              'Next-step action plan',
              'Document map',
              'Evidence confidence matrix',
              'Approval gates',
              'Validation checklist',
              'Data tables',
              'Assumptions appendix',
              'Sources appendix',
            ],
            'readinessSignals': [
              'Decision brief',
              'Recommendation summary',
              'Risk register',
              'Next steps',
              'Validation checklist',
              'Data tables',
              'Assumptions',
              'Sources',
            ],
            'wordCount': 860,
            'reportSectionCount': 12,
            'sectionCount': 4,
            'tableCount': 3,
            'assumptionCount': 2,
            'citationCount': 6,
            'evidenceGapCount': 0,
            'approvalGateCount': 4,
            'tableCoverage': '3 tables packaged',
            'evidenceCoverage': '6 source items captured',
            'appendixCoverage': '2 assumptions, 6 source items in appendices',
            'validationGaps': <String>[],
            'validationGapCount': 0,
            'hasCustomerReadyPackage': true,
            'hasCustomerReadyReport': true,
          },
          createdAt: DateTime(2026, 6, 30, 9, 16),
        ).toSourceArtifact(),
      );
    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.artifacts);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
      ),
    );
    await tester.pump();

    expect(find.text('executive-brief.pptx'), findsOneWidget);
    expect(find.text('architecture-review.docx'), findsOneWidget);
    expect(
      find.text('Presentation artifact for customer-ready decks'),
      findsOneWidget,
    );
    expect(
      find.text('Document artifact for reports, briefs, and handoffs'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Word • Architecture report • 860 words'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Ready for stakeholder review'),
      findsAtLeastNWidgets(1),
    );
    expect(find.text('Slide outline'), findsOneWidget);
    expect(find.text('Report outline'), findsOneWidget);
    expect(find.text('Executive Brief'), findsOneWidget);
    expect(find.text('Risk Register'), findsOneWidget);
    expect(
      find.textContaining('PowerPoint • Customer proposal deck • Light theme'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Ready for stakeholder review'),
      findsAtLeastNWidgets(1),
    );
    expect(find.textContaining('6 slides'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Agenda, Decision snapshot +3'), findsOneWidget);

    await tester.tap(find.text('executive-brief.pptx'));
    await tester.pump();

    expect(find.text('Deck'), findsOneWidget);
    expect(find.text('Customer proposal deck'), findsOneWidget);
    expect(find.text('Handoff'), findsOneWidget);
    expect(find.text('Ready for stakeholder review'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Audience'), findsOneWidget);
    expect(find.text('Executive stakeholders'), findsOneWidget);
    expect(find.text('Purpose'), findsOneWidget);
    expect(find.text('Support a decision'), findsOneWidget);
    expect(find.text('Ask'), findsOneWidget);
    expect(
      find.text(
        'Review the recommendation, confirm assumptions, and approve the next implementation step.',
      ),
      findsOneWidget,
    );
    expect(find.text('Narrative'), findsOneWidget);
    expect(
      find.text('Context -> risk -> recommendation -> action'),
      findsOneWidget,
    );
    expect(find.text('Agenda'), findsAtLeastNWidgets(1));
    expect(
      find.textContaining('Executive summary, Current State +3'),
      findsOneWidget,
    );
    expect(find.text('Slide families'), findsOneWidget);
    expect(find.textContaining('Opening, Agenda +6'), findsOneWidget);
    expect(find.text('Readiness'), findsOneWidget);
    expect(find.text('Agenda, Decision snapshot +3'), findsOneWidget);
    expect(find.text('Sections'), findsOneWidget);
    expect(find.text('Dividers'), findsOneWidget);
    expect(find.text('Tables'), findsAtLeastNWidgets(1));
    expect(find.text('2 tables packaged'), findsOneWidget);
    expect(find.text('5 source items captured'), findsOneWidget);
    expect(find.text('Evidence confidence'), findsOneWidget);
    expect(
      find.text('High - sources and assumptions captured'),
      findsOneWidget,
    );
    expect(find.text('Deck review'), findsOneWidget);
    expect(
      find.textContaining(
        'Confirm deck title, audience, and decision ask match the customer conversation.',
      ),
      findsOneWidget,
    );
    expect(find.text('Handoff actions'), findsOneWidget);
    expect(
      find.textContaining(
        'Send deck to internal reviewer with the source artifact attached.',
      ),
      findsOneWidget,
    );
    expect(find.text('Table slides'), findsOneWidget);
    expect(find.text('Recommendations'), findsOneWidget);
    expect(find.text('Assumptions'), findsOneWidget);
    expect(find.text('Sources'), findsAtLeastNWidgets(1));
    expect(find.text('Structure'), findsOneWidget);
    expect(find.text('Customer-ready deck flow'), findsOneWidget);
    expect(find.text('Package'), findsOneWidget);
    expect(find.text('Stakeholder-review deck'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Speaker notes included'), findsOneWidget);
    expect(find.text('5'), findsAtLeastNWidgets(1));
    expect(find.textContaining('6 slide deck ready'), findsNothing);
    expect(find.textContaining('Word document ready'), findsNothing);

    await tester.tap(find.text('architecture-review.docx'));
    await tester.pump();

    expect(find.text('Type'), findsAtLeastNWidgets(1));
    expect(find.text('Architecture report'), findsOneWidget);
    expect(find.text('Audience'), findsAtLeastNWidgets(1));
    expect(find.text('Architecture reviewers'), findsOneWidget);
    expect(find.text('Purpose'), findsAtLeastNWidgets(1));
    expect(
      find.text('Review findings, risks, and recommendations'),
      findsOneWidget,
    );
    expect(find.text('Handoff'), findsOneWidget);
    expect(find.text('Ready for stakeholder review'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Architecture owner / customer sponsor'), findsOneWidget);
    expect(find.text('Ask'), findsOneWidget);
    expect(
      find.text(
        'Review findings, confirm assumptions, and approve the recommended architecture path.',
      ),
      findsOneWidget,
    );
    expect(find.text('Review path'), findsOneWidget);
    expect(
      find.text(
        'Architecture review -> risk validation -> implementation decision',
      ),
      findsOneWidget,
    );
    expect(find.text('Parts'), findsOneWidget);
    expect(
      find.textContaining(
        'Executive decision brief, Recommendation summary +9',
      ),
      findsOneWidget,
    );
    expect(find.text('Readiness'), findsAtLeastNWidgets(1));
    expect(
      find.text('Decision brief, Recommendation summary +6'),
      findsOneWidget,
    );
    expect(find.text('Tables'), findsAtLeastNWidgets(1));
    expect(find.text('3 tables packaged'), findsOneWidget);
    expect(find.text('Evidence'), findsOneWidget);
    expect(find.text('6 source items captured'), findsOneWidget);
    expect(find.text('Appendices'), findsOneWidget);
    expect(
      find.text('2 assumptions, 6 source items in appendices'),
      findsOneWidget,
    );
    expect(find.text('Approval gates'), findsOneWidget);
    expect(find.text('Package'), findsOneWidget);
    expect(find.text('Customer-ready report flow'), findsOneWidget);
    expect(find.text('Handoff package'), findsOneWidget);
    expect(find.text('Stakeholder-ready Word report'), findsOneWidget);
  });

  testWidgets('Artifacts drawer shows topology readiness metadata', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final artifact = GeneratedArtifact(
      id: 'diagram-1',
      kind: GeneratedArtifactKind.diagram,
      status: GeneratedArtifactStatus.ready,
      fileName: 'campus-topology.svg',
      filePath: '/tmp/campus-topology.svg',
      summary: 'Created an SVG topology diagram with 7 nodes and 6 links.',
      byteSize: 6144,
      previewRows: const [
        ['Signal', 'Value', 'Guidance'],
        ['Topology', '7 nodes / 6 links', 'Review before handoff.'],
        ['AP power', '2700W est.', 'Validate UPOE budget.'],
        ['Access ports', '90/144 AP ports', 'Validate spare ports per IDF.'],
      ],
      metadata: const {
        'topologyType': 'Multi-site topology',
        'handoffStatus': 'Draft - validate topology inputs',
        'resiliencyModel': 'Dual WAN + HA',
        'designZones': [
          'Sites',
          'WAN / Cloud',
          'Security Edge',
          'MDF / Core',
          'IDF / Access',
          'Wireless / Clients',
        ],
        'nodeCount': 7,
        'edgeCount': 6,
        'siteCount': 4,
        'idfCount': 3,
        'apCount': 90,
        'accessPortCount': 144,
        'estimatedApPowerWatts': 2700,
        'readinessSignals': ['Redundancy', 'Power', 'Evidence'],
        'validationGaps': ['Uplinks'],
        'validationGapCount': 1,
        'hasCustomerReadyTopology': false,
      },
      createdAt: DateTime(2026, 7, 1, 10),
    );
    container
        .read(studioSourceArtifactProvider.notifier)
        .add(artifact.toSourceArtifact());
    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.artifacts);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
      ),
    );
    await tester.pump();

    expect(find.text('campus-topology.svg'), findsOneWidget);
    expect(
      find.textContaining('Diagram • Multi-site topology • 7 nodes'),
      findsOneWidget,
    );
    expect(find.textContaining('Dual WAN + HA'), findsOneWidget);
    expect(find.textContaining('1 gaps'), findsOneWidget);
    expect(find.text('Topology readiness'), findsOneWidget);
    expect(find.text('7 nodes'), findsOneWidget);
    expect(find.text('AP power'), findsOneWidget);
    expect(find.text('2700W est.'), findsOneWidget);
    expect(find.text('90/144 AP ports'), findsOneWidget);

    await tester.tap(find.text('campus-topology.svg'));
    await tester.pump();

    expect(find.text('Topology'), findsAtLeastNWidgets(1));
    expect(find.text('Multi-site topology'), findsOneWidget);
    expect(find.text('Handoff'), findsOneWidget);
    expect(find.text('Draft - validate topology inputs'), findsOneWidget);
    expect(find.text('Resiliency'), findsOneWidget);
    expect(find.text('Dual WAN + HA'), findsOneWidget);
    expect(find.text('Zones'), findsOneWidget);
    expect(find.text('Sites, WAN / Cloud +4'), findsOneWidget);
    expect(find.text('Nodes'), findsOneWidget);
    expect(find.text('Links'), findsOneWidget);
    expect(find.text('Sites'), findsAtLeastNWidgets(1));
    expect(find.text('IDFs'), findsOneWidget);
    expect(find.text('APs'), findsOneWidget);
    expect(find.text('Access ports'), findsAtLeastNWidgets(1));
    expect(find.text('AP power'), findsAtLeastNWidgets(1));
    expect(find.text('Readiness'), findsOneWidget);
    expect(find.text('Redundancy, Power +1'), findsOneWidget);
    expect(find.text('Validation gaps'), findsOneWidget);
    expect(find.text('Uplinks'), findsOneWidget);
  });

  testWidgets('Artifacts drawer shows chart pack metadata', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final artifact = GeneratedArtifact(
      id: 'chart-1',
      kind: GeneratedArtifactKind.chart,
      status: GeneratedArtifactStatus.ready,
      fileName: 'enterprise-chart-pack.svg',
      filePath: '/tmp/enterprise-chart-pack.svg',
      summary: 'Created an SVG chart pack with 4 charts.',
      byteSize: 7168,
      previewRows: const [
        ['Chart', 'Signal', 'Data points'],
        ['PoE Budget', 'PoE/UPOE', '4'],
        ['WAN Capacity', 'WAN Capacity', '3'],
        ['Lifecycle Risk', 'Lifecycle', '3'],
      ],
      sheetCount: 4,
      metadata: const {
        'artifact': 'chart_pack',
        'chartPackType': 'Enterprise readiness chart pack',
        'handoffStatus': 'Review required - high risk signals',
        'decisionPurpose': 'Capacity and lifecycle decision support',
        'chartCount': 4,
        'pointCount': 18,
        'highRiskCount': 2,
        'mediumRiskCount': 3,
        'lowRiskCount': 6,
        'signals': ['PoE/UPOE', 'WAN Capacity', 'Lifecycle'],
        'chartFamilies': [
          'PoE Budget',
          'WAN Capacity',
          'Lifecycle Risk',
          'Risk Scorecard',
          'Validation Gates',
        ],
        'readinessSignals': [
          'Source data',
          'Risk labels',
          'Capacity signals',
          'Decision context',
          'High-risk review required',
        ],
        'validationGaps': <String>[],
        'validationGapCount': 0,
        'hasCustomerReadyChartPack': false,
        'validationGateCount': 4,
        'recommendedActionCount': 3,
      },
      createdAt: DateTime(2026, 7, 1, 11),
    );
    container
        .read(studioSourceArtifactProvider.notifier)
        .add(artifact.toSourceArtifact());
    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.artifacts);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
      ),
    );
    await tester.pump();

    expect(find.text('enterprise-chart-pack.svg'), findsOneWidget);
    expect(
      find.textContaining(
        'Chart • Enterprise readiness chart pack • 18 points',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Review required - high risk signals'),
      findsOneWidget,
    );
    expect(find.textContaining('PoE/UPOE, WAN Capacity +1'), findsOneWidget);
    expect(find.text('Chart summary'), findsOneWidget);
    expect(find.text('Lifecycle Risk'), findsOneWidget);

    await tester.tap(find.text('enterprise-chart-pack.svg'));
    await tester.pump();

    expect(find.text('Charts'), findsAtLeastNWidgets(1));
    expect(find.text('Pack'), findsOneWidget);
    expect(find.text('Handoff'), findsOneWidget);
    expect(find.text('Purpose'), findsOneWidget);
    expect(find.text('Enterprise readiness chart pack'), findsOneWidget);
    expect(
      find.text('Capacity and lifecycle decision support'),
      findsOneWidget,
    );
    expect(find.text('Data points'), findsAtLeastNWidgets(1));
    expect(find.text('High risk'), findsOneWidget);
    expect(find.text('Review'), findsAtLeastNWidgets(1));
    expect(find.text('Low/active'), findsOneWidget);
    expect(find.text('Signals'), findsOneWidget);
    expect(find.text('Families'), findsOneWidget);
    expect(find.textContaining('PoE Budget, WAN Capacity +3'), findsOneWidget);
    expect(find.text('Readiness'), findsOneWidget);
    expect(find.textContaining('Source data, Risk labels +3'), findsOneWidget);
    expect(find.text('Validation'), findsOneWidget);
    expect(find.text('Actions'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('4 gates'), findsOneWidget);
    expect(find.text('3 recommended'), findsOneWidget);
  });

  testWidgets('Artifacts drawer shows package manifest metadata', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final root = Directory.systemTemp.createTempSync(
      'studio_package_manifest_',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final file = File('${root.path}/business-case-package.md')
      ..writeAsStringSync('# Business Use Case Package');
    final briefFile = File('${root.path}/brief.docx')..writeAsBytesSync([1, 2]);
    final deckFile = File('${root.path}/deck.pptx')..writeAsBytesSync([3, 4]);
    final chartFile = File('${root.path}/value-chart.svg')
      ..writeAsStringSync('<svg></svg>');
    final artifact = GeneratedArtifact(
      id: 'package-1',
      kind: GeneratedArtifactKind.markdown,
      status: GeneratedArtifactStatus.ready,
      fileName: 'business-case-package.md',
      filePath: file.path,
      summary: 'Created a package manifest for 3 generated artifacts.',
      byteSize: file.lengthSync(),
      previewRows: const [
        ['Artifact', 'Type', 'Status'],
        ['brief.docx', 'Word', 'Ready'],
        ['deck.pptx', 'PowerPoint', 'Ready'],
        ['value-chart.svg', 'Chart', 'Ready'],
      ],
      sheetCount: 3,
      metadata: const {
        'artifact': 'artifact_package_manifest',
        'packageLabel': 'business use case package',
        'artifactCount': 3,
        'artifactFiles': ['brief.docx', 'deck.pptx', 'value-chart.svg'],
        'qualityStatus': 'Package ready',
        'qualityScore': 100,
        'packageQualityStatus': 'Package ready',
        'packageNextAction':
            'Review the package and share the selected customer-ready files.',
        'readyArtifactCount': 3,
        'fallbackArtifactCount': 0,
        'failedArtifactCount': 0,
        'averageQualityScore': 92,
        'packageReviewWorkflow': [
          'Review Word report narrative, assumptions, citations, and sign-off gates.',
          'Review deck slide order, speaker notes, and customer-facing framing.',
          'Review chart thresholds, risk labels, and executive insights.',
          'Open each generated artifact from the Artifacts drawer before sharing.',
        ],
        'packageFileTypes': ['Word', 'PowerPoint', 'Chart'],
        'packageReadinessSignals': [
          'Word: Native format ready',
          'PowerPoint: Native format ready',
          'Chart: Preview available',
        ],
        'hasCustomerReadyArtifact': true,
      },
      createdAt: DateTime(2026, 7, 1, 12),
    );
    final brief = GeneratedArtifact(
      id: 'brief-1',
      kind: GeneratedArtifactKind.docx,
      status: GeneratedArtifactStatus.ready,
      fileName: 'brief.docx',
      filePath: briefFile.path,
      summary: 'Created a Word brief.',
      byteSize: briefFile.lengthSync(),
      sheetCount: 4,
      createdAt: DateTime(2026, 7, 1, 11, 57),
    );
    final deck = GeneratedArtifact(
      id: 'deck-1',
      kind: GeneratedArtifactKind.powerPoint,
      status: GeneratedArtifactStatus.ready,
      fileName: 'deck.pptx',
      filePath: deckFile.path,
      summary: 'Created an executive deck.',
      byteSize: deckFile.lengthSync(),
      sheetCount: 6,
      createdAt: DateTime(2026, 7, 1, 11, 58),
    );
    final chart = GeneratedArtifact(
      id: 'chart-1',
      kind: GeneratedArtifactKind.chart,
      status: GeneratedArtifactStatus.ready,
      fileName: 'value-chart.svg',
      filePath: chartFile.path,
      summary: 'Created a value chart.',
      byteSize: chartFile.lengthSync(),
      previewRows: const [
        ['Metric', 'Value'],
        ['Pipeline', 'High'],
      ],
      sheetCount: 1,
      createdAt: DateTime(2026, 7, 1, 11, 59),
    );
    for (final companion in [brief, deck, chart]) {
      container
          .read(studioSourceArtifactProvider.notifier)
          .add(companion.toSourceArtifact());
    }
    container
        .read(studioSourceArtifactProvider.notifier)
        .add(artifact.toSourceArtifact());
    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.artifacts);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
      ),
    );
    await tester.pump();

    expect(find.text('business-case-package.md'), findsOneWidget);
    expect(
      find.textContaining(
        'Markdown • Package ready • business use case package • 3 artifacts',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Package manifest for the generated deliverable set'),
      findsOneWidget,
    );
    expect(find.text('Package contents'), findsOneWidget);
    expect(find.text('Package deliverables'), findsOneWidget);
    expect(find.text('deck.pptx'), findsAtLeastNWidgets(1));
    expect(find.text('PowerPoint'), findsAtLeastNWidgets(1));

    await tester.tap(find.text('deck.pptx').last);
    await tester.pump();

    expect(
      container.read(studioRightDrawerProvider).selectedArtifactId,
      'generated-deck-1',
    );

    await tester.tap(find.text('business-case-package.md'));
    await tester.pump();

    expect(find.text('Package'), findsOneWidget);
    expect(find.text('business use case package'), findsOneWidget);
    expect(find.text('Package status'), findsOneWidget);
    expect(find.text('Package ready'), findsAtLeastNWidgets(1));
    expect(find.text('Package score'), findsOneWidget);
    expect(find.text('92/100'), findsOneWidget);
    expect(find.text('Artifacts'), findsAtLeastNWidgets(1));
    expect(find.text('3'), findsAtLeastNWidgets(1));
    expect(find.text('Ready artifacts'), findsOneWidget);
    expect(find.text('3/3'), findsOneWidget);
    expect(find.text('Package next'), findsOneWidget);
    expect(
      find.text(
        'Review the package and share the selected customer-ready files.',
      ),
      findsOneWidget,
    );
    expect(find.text('Review workflow'), findsOneWidget);
    expect(find.textContaining('Review Word report narrative'), findsOneWidget);
    expect(find.text('File types'), findsOneWidget);
    expect(find.textContaining('Word, PowerPoint +1'), findsOneWidget);
    expect(find.text('Package signals'), findsOneWidget);
    expect(
      find.textContaining(
        'Word: Native format ready, PowerPoint: Native format ready +1',
      ),
      findsOneWidget,
    );
    expect(find.text('Files'), findsOneWidget);
    expect(find.textContaining('brief.docx, deck.pptx +1'), findsOneWidget);
  });

  testWidgets('Artifacts drawer Review opens text artifacts in code mode', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final root = Directory.systemTemp.createTempSync('studio_artifact_review_');
    addTearDown(() => root.deleteSync(recursive: true));
    final file = File('${root.path}/report.md')..writeAsStringSync('# Report');
    final artifact = GeneratedArtifact(
      id: 'markdown-1',
      kind: GeneratedArtifactKind.markdown,
      status: GeneratedArtifactStatus.ready,
      fileName: 'report.md',
      filePath: file.path,
      summary: 'Created a Markdown report.',
      byteSize: file.lengthSync(),
      createdAt: DateTime(2026, 6, 30, 9, 20),
    );
    container
        .read(studioSourceArtifactProvider.notifier)
        .add(artifact.toSourceArtifact());
    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.artifacts);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
      ),
    );
    await tester.pump();

    expect(find.text('report.md'), findsOneWidget);
    await tester.tap(find.text('Review'));
    await tester.pump();

    final drawer = container.read(studioRightDrawerProvider);
    expect(drawer.mode, StudioDrawerMode.code);
    expect(drawer.filePath, file.path);
  });

  testWidgets('Artifacts drawer exposes CSV export targets', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final root = Directory.systemTemp.createTempSync('studio_artifact_export_');
    addTearDown(() => root.deleteSync(recursive: true));
    final outputDir = Directory('${root.path}/outputs')..createSync();
    final file = File('${outputDir.path}/inventory.csv')
      ..writeAsStringSync('Product,Count\nC9300,6\nCW9176,90\n');
    final artifact = GeneratedArtifact(
      id: 'csv-1',
      kind: GeneratedArtifactKind.csv,
      status: GeneratedArtifactStatus.ready,
      fileName: 'inventory.csv',
      filePath: file.path,
      summary: 'Created a CSV inventory.',
      byteSize: file.lengthSync(),
      previewRows: const [
        ['Product', 'Count'],
        ['C9300', '6'],
      ],
      createdAt: DateTime(2026, 6, 30, 9, 25),
    );
    container
        .read(studioSourceArtifactProvider.notifier)
        .add(artifact.toSourceArtifact());
    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.artifacts);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
      ),
    );
    await tester.pump();

    expect(find.text('Export'), findsOneWidget);
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.text('Excel workbook'), findsOneWidget);
    expect(find.text('Markdown'), findsOneWidget);
  });

  test(
    'StudioSourceArtifactController exports CSV artifacts to XLSX',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final root = Directory.systemTemp.createTempSync(
        'studio_artifact_export_',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final outputDir = Directory('${root.path}/outputs')..createSync();
      final file = File('${outputDir.path}/inventory.csv')
        ..writeAsStringSync('Product,Count\nC9300,6\nCW9176,90\n');
      final artifact = GeneratedArtifact(
        id: 'csv-controller-1',
        kind: GeneratedArtifactKind.csv,
        status: GeneratedArtifactStatus.ready,
        fileName: 'inventory.csv',
        filePath: file.path,
        summary: 'Created a CSV inventory.',
        byteSize: file.lengthSync(),
        previewRows: const [
          ['Product', 'Count'],
          ['C9300', '6'],
        ],
        createdAt: DateTime(2026, 6, 30, 9, 25),
      );

      final exported = await container
          .read(studioSourceArtifactProvider.notifier)
          .exportGeneratedArtifact(artifact, GeneratedArtifactKind.excel);

      expect(exported, isNotNull);
      expect(exported!.kind, GeneratedArtifactKind.excel);
      expect(File(exported.filePath).existsSync(), isTrue);
    },
  );

  test(
    'StudioSourceArtifactController restores historical patches by request',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(studioSourceArtifactProvider);

      final threadController = container.read(studioThreadProvider.notifier);
      final owningThread = threadController.createBlankThread(
        title: 'Owning thread',
      );
      final timestamp = DateTime(2026, 1, 2);
      threadController.upsertTurn(
        owningThread.id,
        StudioTurn(
          id: 'turn-owner',
          threadId: owningThread.id,
          requestId: 'request-owner',
          userMessageId: 'message-owner',
          prompt: 'Prepare changes',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(projectLabel: 'project'),
          status: StudioTurnStatus.completed,
          createdAt: timestamp,
          updatedAt: timestamp,
          completedAt: timestamp,
        ),
        select: true,
      );
      final selectedThread = threadController.createBlankThread(
        title: 'Currently selected thread',
      );
      expect(
        container.read(studioThreadProvider).selectedThread?.id,
        selectedThread.id,
      );

      final patchController = container.read(patchProposalProvider.notifier);
      final patch = patchController.propose(
        title: 'Historical request patch',
        runId: 'request-owner',
        edits: const [
          ProposedFileEdit(
            path: 'lib/owner.dart',
            type: ProposedFileEditType.create,
            after: 'void owner() {}\n',
            unifiedDiff:
                '--- /dev/null\n+++ lib/owner.dart\n@@\n+void owner() {}\n',
          ),
        ],
      );
      patchController.reject(patch.id);

      final sourceState = container.read(studioSourceArtifactProvider);
      final owningArtifacts = sourceState.forThread(owningThread.id);
      expect(
        owningArtifacts.where((artifact) => artifact.patchSetId == patch.id),
        isNotEmpty,
      );
      expect(
        owningArtifacts
            .where(
              (artifact) =>
                  artifact.patchSetId == patch.id &&
                  artifact.kind == StudioSourceArtifactKind.diff,
            )
            .single
            .filePath,
        'lib/owner.dart',
      );

      final selectedArtifacts = sourceState
          .forThread(selectedThread.id)
          .where((artifact) => artifact.patchSetId == patch.id)
          .toList();
      expect(selectedArtifacts, isEmpty);
    },
  );

  test('StudioSourceArtifactController scopes live commands by request', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(studioSourceArtifactProvider);

    final threadController = container.read(studioThreadProvider.notifier);
    final owningThread = threadController.createBlankThread(
      title: 'Command owner',
    );
    final timestamp = DateTime(2026, 1, 3);
    threadController.upsertTurn(
      owningThread.id,
      StudioTurn(
        id: 'turn-command-owner',
        threadId: owningThread.id,
        requestId: 'request-command-owner',
        userMessageId: 'message-command-owner',
        prompt: 'Run checks',
        model: 'gpt-5-nano',
        contextSummary: const StudioContextSummary(projectLabel: 'project'),
        status: StudioTurnStatus.completed,
        createdAt: timestamp,
        updatedAt: timestamp,
        completedAt: timestamp,
      ),
      select: true,
    );
    final selectedThread = threadController.createBlankThread(
      title: 'Selected elsewhere',
    );
    expect(
      container.read(studioThreadProvider).selectedThread?.id,
      selectedThread.id,
    );

    final commandController = container.read(commandRunProvider.notifier);
    commandController.start(
      id: 'cmd-owner',
      command: 'npm test',
      requestId: 'request-command-owner',
      turnId: 'turn-command-owner',
    );
    commandController.append(
      'cmd-owner',
      CommandRunEventType.stdout,
      'owner output\nhttp://localhost:4173\n',
    );
    commandController.finish(
      'cmd-owner',
      status: CommandRunStatus.succeeded,
      exitCode: 0,
    );

    final sourceState = container.read(studioSourceArtifactProvider);
    final owningArtifacts = sourceState.forThread(owningThread.id);
    expect(
      owningArtifacts.where((artifact) => artifact.commandRunId == 'cmd-owner'),
      isNotEmpty,
    );
    expect(
      owningArtifacts
          .where(
            (artifact) =>
                artifact.commandRunId == 'cmd-owner' &&
                artifact.kind == StudioSourceArtifactKind.localUrl,
          )
          .single
          .localUrl,
      'http://localhost:4173',
    );
    expect(
      sourceState
          .forThread(selectedThread.id)
          .where((artifact) => artifact.commandRunId == 'cmd-owner'),
      isEmpty,
    );
  });

  test('StudioSourceArtifactController restores persisted command events', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(studioSourceArtifactProvider);

    final threadController = container.read(studioThreadProvider.notifier);
    final owningThread = threadController.createBlankThread(
      title: 'Persisted command owner',
    );
    final timestamp = DateTime(2026, 1, 4);
    final turn = StudioTurn(
      id: 'turn-persisted-command',
      threadId: owningThread.id,
      requestId: 'request-persisted-command',
      userMessageId: 'message-persisted-command',
      prompt: 'Verify',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      createdAt: timestamp,
      updatedAt: timestamp,
      completedAt: timestamp,
      events: [
        StudioTurnEvent.completionSummary(
          id: 'command-run-turn-persisted-command-cmd-restored-source',
          turnId: 'turn-persisted-command',
          requestId: 'request-persisted-command',
          threadId: owningThread.id,
          title: 'Ran command',
          detail:
              'Command: npm test\nExit code: 0\nrestored source output\nhttp://localhost:5173\nFull log: /tmp/circuit-command.log\n',
          timestamp: timestamp,
        ),
      ],
    );
    threadController.upsertTurn(owningThread.id, turn, select: true);

    final sourceState = container.read(studioSourceArtifactProvider);
    final owningArtifacts = sourceState.forThread(owningThread.id);
    expect(
      owningArtifacts.where(
        (artifact) => artifact.commandRunId == 'cmd-restored-source',
      ),
      isNotEmpty,
    );
    expect(
      owningArtifacts
          .where(
            (artifact) =>
                artifact.commandRunId == 'cmd-restored-source' &&
                artifact.kind == StudioSourceArtifactKind.command,
          )
          .single
          .value,
      'restored source output\nhttp://localhost:5173',
    );
    expect(
      owningArtifacts
          .where(
            (artifact) =>
                artifact.commandRunId == 'cmd-restored-source' &&
                artifact.kind == StudioSourceArtifactKind.command,
          )
          .single
          .filePath,
      '/tmp/circuit-command.log',
    );
    expect(
      owningArtifacts
          .where(
            (artifact) =>
                artifact.commandRunId == 'cmd-restored-source' &&
                artifact.kind == StudioSourceArtifactKind.localUrl,
          )
          .single
          .localUrl,
      'http://localhost:5173',
    );
  });

  testWidgets(
    'Context drawer can include omitted persisted retrieval paths next time',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final root = Directory.systemTemp.createTempSync(
        'studio_context_drawer_',
      );
      final preferenceRoot = Directory.systemTemp.createTempSync(
        'studio_context_prefs_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
        if (await preferenceRoot.exists()) {
          await preferenceRoot.delete(recursive: true);
        }
      });
      File(
        '${root.path}/important.dart',
      ).writeAsStringSync('void importantThing() {}\n');

      final container = ProviderContainer(
        overrides: [
          contextPreferenceStoreProvider.overrideWithValue(
            ContextPreferenceStore(baseDir: preferenceRoot.path),
          ),
        ],
      );
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
          .createBlankThread(title: 'Persisted context');
      const retrieval = ContextRetrievalResult(
        rankedCandidates: [
          ContextCandidate(
            id: 'omitted-important',
            title: 'important.dart',
            path: 'important.dart',
            sourceKind: ContextPackSourceKind.editor,
            score: 92,
            estimatedTokens: 8,
            included: false,
            reason: 'indexed relevant file',
          ),
        ],
        budget: ContextBudgetReport(
          maxTokens: 100000,
          reservedForResponse: 4096,
          availableForContext: 95904,
          usedTokens: 0,
        ),
      );
      final turn = StudioTurn(
        id: 'turn-context',
        threadId: thread.id,
        requestId: 'request-context',
        userMessageId: 'message-context',
        prompt: 'Use the important file',
        model: 'gpt-5-nano',
        contextSummary: const StudioContextSummary(projectLabel: 'project'),
        status: StudioTurnStatus.completed,
        contextRetrieval: retrieval,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        completedAt: DateTime(2026),
      );
      container
          .read(studioThreadProvider.notifier)
          .upsertTurn(thread.id, turn, select: true);
      await flushStudioThreadPersist(tester);
      container.read(studioRightDrawerProvider.notifier).openContext();

      expect(container.read(contextPackProvider), isNull);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
        ),
      );
      await tester.pump();

      expect(find.text('important.dart'), findsOneWidget);
      expect(find.text('Include next'), findsOneWidget);
      final includeNext = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Include next'),
      );
      expect(includeNext.style?.minimumSize?.resolve({}), const Size(0, 28));
      expect(
        includeNext.style?.tapTargetSize,
        MaterialTapTargetSize.shrinkWrap,
      );
      final includeShape = includeNext.style?.shape?.resolve({});
      expect(includeShape, isA<RoundedRectangleBorder>());
      expect(
        (includeShape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(7),
      );

      await tester.tap(find.text('Include next'));
      await tester.pump();

      expect(
        container
            .read(contextPackProvider.notifier)
            .includeNextTimePathsForCurrentRoot(),
        contains('important.dart'),
      );
      expect(find.text('Remove next'), findsOneWidget);

      await tester.tap(find.text('Remove next'));
      await tester.pump();

      expect(
        container
            .read(contextPackProvider.notifier)
            .includeNextTimePathsForCurrentRoot(),
        isNot(contains('important.dart')),
      );
      expect(find.text('Include next'), findsOneWidget);
    },
  );

  testWidgets(
    'Context drawer shows all persisted omitted candidates beyond first page',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final root = Directory.systemTemp.createTempSync(
        'studio_context_many_omitted_',
      );
      final preferenceRoot = Directory.systemTemp.createTempSync(
        'studio_context_many_omitted_prefs_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
        if (await preferenceRoot.exists()) {
          await preferenceRoot.delete(recursive: true);
        }
      });
      for (var index = 0; index < 25; index++) {
        File(
          '${root.path}/omitted_$index.dart',
        ).writeAsStringSync('void omitted$index() {}\n');
      }

      final container = ProviderContainer(
        overrides: [
          contextPreferenceStoreProvider.overrideWithValue(
            ContextPreferenceStore(baseDir: preferenceRoot.path),
          ),
        ],
      );
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
          .createBlankThread(title: 'Many omitted context files');
      final retrieval = ContextRetrievalResult(
        rankedCandidates: [
          for (var index = 0; index < 25; index++)
            ContextCandidate(
              id: 'omitted-$index',
              title: 'omitted_$index.dart',
              path: 'omitted_$index.dart',
              sourceKind: ContextPackSourceKind.editor,
              score: 100 - index,
              estimatedTokens: 8,
              included: false,
              reason: 'indexed relevant file; omitted from this turn.',
            ),
        ],
        budget: const ContextBudgetReport(
          maxTokens: 100000,
          reservedForResponse: 4096,
          availableForContext: 95904,
          usedTokens: 0,
        ),
      );
      final turn = StudioTurn(
        id: 'turn-many-omitted',
        threadId: thread.id,
        requestId: 'request-many-omitted',
        userMessageId: 'message-many-omitted',
        prompt: 'Use omitted files',
        model: 'gpt-5-nano',
        contextSummary: const StudioContextSummary(projectLabel: 'project'),
        status: StudioTurnStatus.completed,
        contextRetrieval: retrieval,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        completedAt: DateTime(2026),
      );
      container
          .read(studioThreadProvider.notifier)
          .upsertTurn(thread.id, turn, select: true);
      await flushStudioThreadPersist(tester);
      container.read(studioRightDrawerProvider.notifier).openContext();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
        ),
      );
      await tester.pump();

      expect(find.text('omitted_0.dart'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('omitted_24.dart'),
        420,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('omitted_24.dart'), findsOneWidget);

      await tester.tap(find.text('Include next').last);
      await tester.pump();

      expect(
        container
            .read(contextPackProvider.notifier)
            .includeNextTimePathsForCurrentRoot(),
        contains('omitted_24.dart'),
      );
    },
  );

  testWidgets('Context drawer can remove include-next persisted paths', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final root = Directory.systemTemp.createTempSync('studio_context_unpin_');
    final preferenceRoot = Directory.systemTemp.createTempSync(
      'studio_context_unpin_prefs_',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
      if (await preferenceRoot.exists()) {
        await preferenceRoot.delete(recursive: true);
      }
    });
    File(
      '${root.path}/important.dart',
    ).writeAsStringSync('void importantThing() {}\n');

    final container = ProviderContainer(
      overrides: [
        contextPreferenceStoreProvider.overrideWithValue(
          ContextPreferenceStore(baseDir: preferenceRoot.path),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(fileTreeProvider.notifier).openDirectory(root.path),
    );
    container
        .read(contextPackProvider.notifier)
        .includeNextTime('important.dart');
    container.read(contextPackProvider.notifier).buildForCodingTask(prompt: '');
    container.read(studioRightDrawerProvider.notifier).openContext();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
      ),
    );
    await tester.pump();

    expect(find.text('important.dart'), findsOneWidget);
    expect(find.text('Remove next'), findsOneWidget);
    expect(
      container
          .read(contextPackProvider.notifier)
          .includeNextTimePathsForCurrentRoot(),
      contains('important.dart'),
    );

    await tester.tap(find.text('Remove next'));
    await tester.pump();

    expect(
      container
          .read(contextPackProvider.notifier)
          .includeNextTimePathsForCurrentRoot(),
      isNot(contains('important.dart')),
    );
    expect(find.text('important.dart'), findsNothing);
  });

  testWidgets('Context drawer renders persisted instruction safety warnings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(studioThreadProvider.notifier).reload(),
    );

    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Context warning');
    const retrieval = ContextRetrievalResult(
      rankedCandidates: [
        ContextCandidate(
          id: 'instruction:CLAUDE.md',
          title: 'CLAUDE.md',
          path: 'CLAUDE.md',
          sourceKind: ContextPackSourceKind.instructionFile,
          score: 80,
          estimatedTokens: 12,
          included: true,
          reason: 'Project instruction file.',
        ),
      ],
      budget: ContextBudgetReport(
        maxTokens: 100000,
        reservedForResponse: 4096,
        availableForContext: 95904,
        usedTokens: 12,
      ),
      warnings: [
        ContextPackWarning(
          itemId: 'instruction:CLAUDE.md',
          message:
              'CLAUDE.md contains permission-like instructions. Circuit treats project instruction files as guidance only; app policy still controls tools, approvals, and workspace boundaries.',
        ),
      ],
    );
    final turn = StudioTurn(
      id: 'turn-warning',
      threadId: thread.id,
      requestId: 'request-warning',
      userMessageId: 'message-warning',
      prompt: 'Review instructions',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      contextRetrieval: retrieval,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);
    await flushStudioThreadPersist(tester);
    container.read(studioRightDrawerProvider.notifier).openContext();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
      ),
    );
    await tester.pump();

    expect(find.textContaining('CLAUDE.md contains permission-like'), findsOne);
    expect(find.textContaining('guidance only'), findsOne);
  });

  testWidgets('Context drawer renders persisted instruction conflict warnings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(studioThreadProvider.notifier).reload(),
    );

    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Context conflict');
    const retrieval = ContextRetrievalResult(
      rankedCandidates: [
        ContextCandidate(
          id: 'instruction:AGENTS.md',
          title: 'AGENTS.md',
          path: 'AGENTS.md',
          sourceKind: ContextPackSourceKind.instructionFile,
          score: 80,
          estimatedTokens: 12,
          included: true,
          reason: 'Project instruction file.',
        ),
        ContextCandidate(
          id: 'instruction:CLAUDE.md',
          title: 'CLAUDE.md',
          path: 'CLAUDE.md',
          sourceKind: ContextPackSourceKind.instructionFile,
          score: 79,
          estimatedTokens: 12,
          included: true,
          reason: 'Project instruction file.',
        ),
      ],
      budget: ContextBudgetReport(
        maxTokens: 100000,
        reservedForResponse: 4096,
        availableForContext: 95904,
        usedTokens: 24,
      ),
      warnings: [
        ContextPackWarning(
          message:
              'Project instruction files contain conflicting approval guidance (AGENTS.md vs CLAUDE.md). Circuit treats instructions as guidance only; app permission policy decides when tools require review.',
        ),
        ContextPackWarning(
          message:
              'Project instruction files contain conflicting workspace-boundary guidance (AGENTS.md vs CLAUDE.md). Circuit enforces the selected workspace root regardless of instruction text.',
        ),
      ],
    );
    final turn = StudioTurn(
      id: 'turn-conflict',
      threadId: thread.id,
      requestId: 'request-conflict',
      userMessageId: 'message-conflict',
      prompt: 'Review conflicting instructions',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      contextRetrieval: retrieval,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: DateTime(2026),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);
    await flushStudioThreadPersist(tester);
    container.read(studioRightDrawerProvider.notifier).openContext();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
      ),
    );
    await tester.pump();

    expect(find.textContaining('conflicting approval guidance'), findsOne);
    expect(
      find.textContaining('conflicting workspace-boundary guidance'),
      findsOne,
    );
    expect(find.textContaining('app permission policy decides'), findsOne);
    expect(find.textContaining('selected workspace root'), findsOne);
  });

  testWidgets(
    'Context drawer shows and restores removed live retrieval items',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final root = Directory.systemTemp.createTempSync(
        'studio_context_remove_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      File(
        '${root.path}/important.dart',
      ).writeAsStringSync('void importantThing() {}\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.runAsync(
        () =>
            container.read(fileTreeProvider.notifier).openDirectory(root.path),
      );
      container
          .read(contextPackProvider.notifier)
          .buildForCodingTask(prompt: 'inspect important.dart');
      container.read(studioRightDrawerProvider.notifier).openContext();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
        ),
      );
      await tester.pump();

      expect(find.text('important.dart'), findsOneWidget);
      expect(
        container.read(contextPackProvider)!.serializePrompt(),
        contains('importantThing'),
      );
      final removeButton = find.byTooltip('Remove from next send');
      expect(removeButton, findsWidgets);
      expect(
        find.descendant(
          of: removeButton.first,
          matching: find.byType(IconButton),
        ),
        findsNothing,
      );
      final closeIcon = tester.widget<Icon>(
        find.descendant(
          of: removeButton.first,
          matching: find.byIcon(Icons.close),
        ),
      );
      expect(closeIcon.size, 14);
      final closeContainer = tester.widget<Container>(
        find
            .descendant(
              of: removeButton.first,
              matching: find.byType(Container),
            )
            .first,
      );
      final closeDecoration = closeContainer.decoration;
      expect(closeDecoration, isA<BoxDecoration>());
      expect(
        (closeDecoration! as BoxDecoration).borderRadius,
        BorderRadius.circular(6),
      );

      await tester.tap(removeButton.first);
      await tester.pump();

      expect(find.text('Removed from next send'), findsOneWidget);
      expect(find.text('important.dart'), findsOneWidget);
      expect(
        container.read(contextPackProvider)!.serializePrompt(),
        isNot(contains('importantThing')),
      );

      await tester.tap(find.text('Restore'));
      await tester.pump();

      expect(find.text('Removed from next send'), findsNothing);
      expect(find.text('important.dart'), findsOneWidget);
      expect(
        container.read(contextPackProvider)!.serializePrompt(),
        contains('importantThing'),
      );
    },
  );
}

class _ReviewOnlyGitNotifier extends GitNotifier {
  @override
  GitState build() => const GitState(
    status: GitStatus(
      branch: 'main',
      unstaged: [
        GitFileChange(path: 'README.md', type: GitChangeType.modified),
      ],
    ),
  );

  @override
  Future<String> getDiff({String? path, bool staged = false}) async {
    return '''
diff --git a/README.md b/README.md
--- a/README.md
+++ b/README.md
@@ -1 +1 @@
-before
+after
''';
  }
}
