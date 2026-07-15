import 'dart:io';

import 'package:crypto/crypto.dart';

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
import 'package:circuit_ide/services/artifact_visual_preview_verifier.dart';
import 'package:circuit_ide/state/artifact_launch_provider.dart';
import 'package:circuit_ide/state/context_pack_provider.dart';
import 'package:circuit_ide/state/command_run_provider.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/git_provider.dart';
import 'package:circuit_ide/state/patch_proposal_provider.dart';
import 'package:circuit_ide/state/studio_code_edit_provider.dart';
import 'package:circuit_ide/state/studio_browser_provider.dart';
import 'package:circuit_ide/state/studio_right_drawer_provider.dart';
import 'package:circuit_ide/state/studio_shell_provider.dart';
import 'package:circuit_ide/state/studio_source_artifact_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/ui/studio/studio_right_drawer.dart';
import 'package:circuit_ide/ui/terminal/terminal_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
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
      StudioDrawerMode.browser,
    );
    expect(
      container.read(studioRightDrawerProvider).localUrl,
      'http://localhost:3000',
    );

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

  testWidgets(
    'Studio drawer exposes only the user-controlled browser preview',
    (tester) async {
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
      expect(find.text('Browser preview'), findsOneWidget);
    },
  );

  testWidgets('empty drawer states provide a real next action', (tester) async {
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

    expect(find.text('No file selected'), findsOneWidget);
    expect(find.text('Open files'), findsOneWidget);
    await tester.tap(find.text('Open files'));
    await tester.pumpAndSettle();
    expect(
      container.read(studioRightDrawerProvider).mode,
      StudioDrawerMode.files,
    );
    expect(find.text('No project selected'), findsOneWidget);
    expect(find.text('Back to projects'), findsOneWidget);

    final emptyModes = [
      (StudioDrawerMode.diff, 'No changes'),
      (StudioDrawerMode.terminal, 'No command logs'),
      (StudioDrawerMode.artifacts, 'No artifacts yet'),
      (StudioDrawerMode.sources, 'No sources yet'),
      (StudioDrawerMode.context, 'No context yet'),
    ];
    for (final entry in emptyModes) {
      container.read(studioRightDrawerProvider.notifier).openMode(entry.$1);
      await tester.pumpAndSettle();
      expect(find.text(entry.$2), findsOneWidget);
      expect(find.text('Start a task'), findsOneWidget);
    }
  });

  testWidgets('Browser drawer exposes bounded user-controlled page tabs', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.browser);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
      ),
    );
    await tester.pump();

    expect(find.text('New page'), findsOneWidget);
    expect(find.byTooltip('Open new browser tab'), findsOneWidget);
    await tester.tap(find.byTooltip('Open new browser tab'));
    await tester.pump();

    expect(container.read(studioBrowserProvider).tabs, hasLength(2));
    expect(find.text('New page'), findsNWidgets(2));
    expect(find.byTooltip('Close New page'), findsNWidgets(2));
  });

  test(
    'Studio drawer body guards stale browser mode behind the dedicated preview flag',
    () async {
      final source = [
        await File('lib/ui/studio/studio_right_drawer.dart').readAsString(),
        await File('lib/ui/studio/studio_browser_drawer.dart').readAsString(),
      ].join('\n');

      expect(source, contains('StudioFeatureFlags.browserPreview'));
      expect(source, contains('safeMode'));
      expect(source, contains('StudioDrawerMode.sources'));
      expect(source, contains('never gives the assistant browser control'));
    },
  );

  test(
    'Studio source artifacts quarantine notes but retain explicit selections',
    () {
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
              id: 'browser-selection',
              kind: StudioSourceArtifactKind.browserSelection,
              title: 'Selected browser text',
              subtitle: 'http://localhost:3000',
              value: 'Untrusted browser observation',
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
        contains(StudioSourceArtifactKind.browserSelection),
      );
      expect(
        artifacts.map((artifact) => artifact.kind),
        contains(StudioSourceArtifactKind.file),
      );
    },
  );

  testWidgets(
    'Studio drawer typography and icons use contextual compact chrome',
    (tester) async {
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

      expect(find.byTooltip('Open drawer view'), findsOneWidget);
      expect(find.text('Status'), findsNothing);
      expect(find.byTooltip('Progress'), findsNothing);
      expect(find.byTooltip('Artifacts'), findsNothing);
      expect(find.byTooltip('Context details'), findsOneWidget);
      expect(find.byIcon(Icons.language), findsNothing);

      container
          .read(studioRightDrawerProvider.notifier)
          .openMode(StudioDrawerMode.code);
      await tester.pump();

      final modeMenuIcon = tester.widget<Icon>(
        find.byIcon(Icons.tune_outlined),
      );
      expect(modeMenuIcon.size, 13);

      await tester.tap(find.byTooltip('Open drawer view'));
      await tester.pumpAndSettle();

      final codeIcon = tester.widget<Icon>(find.byIcon(Icons.code).last);
      expect(codeIcon.size, 13);
      final codeText = tester.widget<Text>(find.text('Code').last);
      expect(codeText.style?.fontSize, FontSizes.xs);

      final contextIcon = tester.widget<Icon>(
        find.byIcon(Icons.inventory_2_outlined).last,
      );
      expect(contextIcon.size, 13);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      container.read(studioRightDrawerProvider.notifier).toggleCollapsed();
      await tester.pumpAndSettle();

      expect(find.widgetWithIcon(IconButton, Icons.chevron_left), findsNothing);
      final collapsedExpandIcon = tester.widget<Icon>(
        find.byIcon(Icons.chevron_left),
      );
      expect(collapsedExpandIcon.size, 14);
      expect(find.byTooltip('Expand right panel'), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_checked), findsNothing);
      expect(find.byTooltip('Open drawer view'), findsNothing);
    },
  );

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

  test(
    'StudioSourceArtifactController persists generated artifacts from completed turns',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-generated-artifact-turn-',
      );
      addTearDown(() => root.delete(recursive: true));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(studioSourceArtifactProvider);
      final threadController = container.read(studioThreadProvider.notifier);
      final thread = threadController.createBlankThread(title: 'Artifact turn');
      final now = DateTime(2026);
      const turnId = 'turn-artifact';
      const requestId = 'request-artifact';
      final contextSummary = StudioContextSummary(
        rootPath: root.path,
        projectLabel: 'Artifact workspace',
        includedItemCount: 1,
        estimatedTokens: 120,
      );
      threadController.markPhase(
        thread.id,
        status: StudioThreadStatus.done,
        phase: StudioSendPhase.completed,
        requestId: requestId,
        contextSummary: contextSummary,
      );
      final turn = StudioTurn(
        id: turnId,
        threadId: thread.id,
        requestId: requestId,
        userMessageId: 'message-artifact',
        prompt: 'Create an Excel file from this inventory table.',
        model: 'gpt-5-nano',
        contextSummary: contextSummary,
        status: StudioTurnStatus.completed,
        events: [
          StudioTurnEvent.assistantMessage(
            turnId: turnId,
            requestId: requestId,
            threadId: thread.id,
            content: '''
| Product | Count | Notes |
| --- | ---: | --- |
| C9300 | 6 | MDF switching |
| CW9176 | 90 | Wireless APs |
''',
            timestamp: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
        completedAt: now,
      );

      threadController.upsertTurn(thread.id, turn, select: true);

      StudioThread? updated;
      for (var i = 0; i < 25; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        updated = container
            .read(studioThreadProvider)
            .threads
            .where((candidate) => candidate.id == thread.id)
            .firstOrNull;
        final hasGeneratedArtifact =
            updated?.sourceArtifacts.any(
              (artifact) =>
                  artifact.kind == StudioSourceArtifactKind.generatedArtifact,
            ) ??
            false;
        if (hasGeneratedArtifact) break;
      }

      final generatedArtifacts = updated!.sourceArtifacts
          .where(
            (artifact) =>
                artifact.kind == StudioSourceArtifactKind.generatedArtifact,
          )
          .map(GeneratedArtifact.fromSourceArtifact)
          .whereType<GeneratedArtifact>()
          .toList();
      expect(generatedArtifacts, isNotEmpty);
      expect(
        generatedArtifacts.map((artifact) => artifact.kind),
        contains(GeneratedArtifactKind.excel),
      );
      final excelArtifact = generatedArtifacts.firstWhere(
        (artifact) => artifact.kind == GeneratedArtifactKind.excel,
      );
      expect(excelArtifact.threadId, thread.id);
      expect(excelArtifact.requestId, requestId);
      expect(excelArtifact.fileName, endsWith('.xlsx'));
      expect(File(excelArtifact.filePath).existsSync(), isTrue);
      expect(excelArtifact.filePath, startsWith(root.path));
      final refreshedTurn = updated.turns.firstWhere(
        (candidate) => candidate.id == turnId,
      );
      expect(
        refreshedTurn.events
            .where(
              (event) => event.type == StudioTurnEventType.completionSummary,
            )
            .map((event) => event.title),
        contains('Created Excel file'),
      );
    },
  );

  test(
    'StudioSourceArtifactController records artifact materialization failures',
    () async {
      final rootFile = await File(
        '${Directory.systemTemp.path}/circuit-artifact-root-file-${DateTime.now().microsecondsSinceEpoch}',
      ).create();
      addTearDown(() => rootFile.delete());
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(studioSourceArtifactProvider);
      final threadController = container.read(studioThreadProvider.notifier);
      final thread = threadController.createBlankThread(
        title: 'Broken artifact turn',
      );
      final now = DateTime(2026);
      const turnId = 'turn-artifact-failed';
      const requestId = 'request-artifact-failed';
      final contextSummary = StudioContextSummary(
        rootPath: rootFile.path,
        projectLabel: 'Invalid artifact workspace',
        includedItemCount: 1,
        estimatedTokens: 120,
      );
      threadController.markPhase(
        thread.id,
        status: StudioThreadStatus.done,
        phase: StudioSendPhase.completed,
        requestId: requestId,
        contextSummary: contextSummary,
      );
      final turn = StudioTurn(
        id: turnId,
        threadId: thread.id,
        requestId: requestId,
        userMessageId: 'message-artifact-failed',
        prompt: 'Create an Excel file from this inventory table.',
        model: 'gpt-5-nano',
        contextSummary: contextSummary,
        status: StudioTurnStatus.completed,
        events: [
          StudioTurnEvent.assistantMessage(
            turnId: turnId,
            requestId: requestId,
            threadId: thread.id,
            content: '''
| Product | Count | Notes |
| --- | ---: | --- |
| C9300 | 6 | MDF switching |
''',
            timestamp: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
        completedAt: now,
      );

      threadController.upsertTurn(thread.id, turn, select: true);

      StudioThread? updated;
      for (var i = 0; i < 25; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        updated = container
            .read(studioThreadProvider)
            .threads
            .where((candidate) => candidate.id == thread.id)
            .firstOrNull;
        final failureEvents =
            updated?.turns
                .firstWhere((candidate) => candidate.id == turnId)
                .events
                .where((event) => event.id == 'artifact-failed-$turnId')
                .toList() ??
            const <StudioTurnEvent>[];
        if (failureEvents.isNotEmpty) break;
      }

      final refreshedTurn = updated!.turns.firstWhere(
        (candidate) => candidate.id == turnId,
      );
      final failureEvents = refreshedTurn.events
          .where((event) => event.id == 'artifact-failed-$turnId')
          .toList();
      expect(failureEvents, hasLength(1));
      expect(failureEvents.single.title, 'Could not create artifact');
      expect(
        failureEvents.single.detail,
        contains('Circuit could not create the requested artifact'),
      );
      expect(
        updated.sourceArtifacts.where(
          (artifact) =>
              artifact.kind == StudioSourceArtifactKind.generatedArtifact,
        ),
        isEmpty,
      );
    },
  );

  testWidgets('Artifacts drawer shows selected artifact metadata and binary preview', (
    tester,
  ) async {
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
        'qualityManifestVersion': '1.0',
        'hasReportQualityManifest': true,
        'hasVisualVerificationManifest': true,
        'hasRenderSafeContentFrame': true,
        'hasPublishingMetadata': true,
        'publishingMetadata': [
          'Report type: Architecture report',
          'Review path: Architecture review -> risk validation -> implementation decision',
          'Handoff readiness: Customer handoff ready',
        ],
        'externalHandoffManifest': [
          'Review owner: Architecture owner / customer sponsor',
          'Report type: Architecture report',
          'Review path: Architecture review -> risk validation -> implementation decision',
          'Handoff readiness: Customer handoff ready',
          'Evidence status: High - sources and assumptions captured',
          'Publishing gate: ready for stakeholder approval',
          'Source package: 3 source items attached',
          'Assumption package: 2 assumptions captured',
        ],
        'visualVerificationChecklist': [
          'Render-safe text frame',
          'US Letter media box',
          'Header and footer present',
          'Page numbers present',
          'Bookmark destinations resolve',
          'Table grid draws inside content frame',
        ],
        'reportEvidencePolicy': [
          'Report narrative is guidance; source appendices and source artifacts are the evidence record.',
          'Customer handoff requires checked sources, assumptions, decision owner, and approval gate.',
          'Use cited sources as the evidence register for external review.',
          'Review assumptions with the accountable owner before stakeholder handoff.',
        ],
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
        'pdfInspectionStatus': 'Verified',
        'pdfStructuralValid': true,
        'pdfExpectedReportChrome': true,
        'pdfParsedPageCount': 2,
        'pdfObjectCount': 24,
        'pdfHasOutlineTree': true,
        'pdfHasResolvableBookmarkDestinations': true,
        'pdfHasRenderSafeTextFrame': true,
        'pdfHasPageCountConsistency': true,
        'pdfHasVisualVerificationManifest': true,
        'pdfInspectionFailedChecks': <String>[],
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
    expect(find.textContaining('PDF Verified'), findsOneWidget);
    expect(find.textContaining('Ready for stakeholder review'), findsOneWidget);
    expect(find.text('PDF outline'), findsOneWidget);
    expect(find.text('2 pages'), findsOneWidget);
    expect(find.text('External handoff manifest'), findsOneWidget);
    expect(find.text('Publishing gate'), findsOneWidget);
    expect(find.text('ready for stakeholder approval'), findsOneWidget);
    expect(find.text('Review owner'), findsOneWidget);
    expect(find.text('Architecture owner / customer sponsor'), findsOneWidget);
    expect(find.text('Evidence status'), findsOneWidget);
    expect(
      find.text('High - sources and assumptions captured'),
      findsOneWidget,
    );
    expect(find.text('Section'), findsOneWidget);
    expect(find.text('Executive Summary'), findsOneWidget);
    expect(
      find.textContaining('Open to inspect the full document'),
      findsNothing,
    );
    expect(find.text('2 pages'), findsOneWidget);
    expect(
      find.text('PDF Report for customer handoff, final report'),
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
      findsAtLeastNWidgets(1),
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
    expect(find.text('PDF inspection'), findsOneWidget);
    expect(find.text('Verified'), findsAtLeastNWidgets(1));
    expect(find.text('PDF package'), findsOneWidget);
    expect(find.text('Structurally valid'), findsOneWidget);
    expect(find.text('PDF chrome'), findsOneWidget);
    expect(find.text('Customer-ready report'), findsOneWidget);
    expect(find.text('Parsed pages'), findsOneWidget);
    expect(find.text('PDF objects'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    expect(find.text('Bookmark links'), findsOneWidget);
    expect(find.text('Resolvable'), findsOneWidget);
    expect(find.text('Text frame'), findsOneWidget);
    expect(find.text('Render-safe'), findsOneWidget);
    expect(find.text('Page count'), findsOneWidget);
    expect(find.text('Consistent'), findsOneWidget);
    expect(find.text('Visual manifest'), findsOneWidget);
    expect(find.text('Included'), findsOneWidget);
    expect(find.text('Quality'), findsOneWidget);
    expect(find.text('Manifest v1.0'), findsOneWidget);
    expect(find.text('Publishing'), findsOneWidget);
    expect(
      find.text(
        'Report type: Architecture report, Review path: Architecture review -> risk validation -> implementation decision +1',
      ),
      findsOneWidget,
    );
    expect(find.text('Visual checks'), findsOneWidget);
    expect(
      find.text('Render-safe text frame, US Letter media box +4'),
      findsOneWidget,
    );
    expect(find.text('Evidence policy'), findsOneWidget);
    expect(find.textContaining('Report narrative is guidance'), findsOneWidget);
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
    expect(find.text('Bookmarks'), findsAtLeastNWidgets(1));
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
  });

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
      sheetCount: 22,
      metadata: const {
        'artifact': 'solution_sizing_workbook',
        'workbookKind': 'solution_sizing',
        'sheetCount': 22,
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
        'sizingReadinessLevel': 'Ready for requirements review',
        'sizingHandoffStatus': 'Requirements review workbook',
        'sizingDecisionPosture':
            'Advisory only - close hard gates before BOM recommendation',
        'hasSizingCustomerHandoffMatrix': true,
        'sizingCustomerHandoffGateCount': 6,
        'sizingCustomerHandoffReadyCount': 4,
        'sizingCustomerHandoffMatrix': [
          {
            'gate': 'Source evidence',
            'signal': 'Source workbook/table captured',
            'status': 'Ready',
            'ownerAction': 'Confirm source freshness and owner.',
            'ready': true,
          },
          {
            'gate': 'Power and access constraints',
            'signal': 'UPOE/mGig validation required',
            'status': 'Needs datasheet validation',
            'ownerAction': 'Validate AP draw, UPOE, mGig, and uplinks.',
            'ready': false,
          },
        ],
        'sizingQualityManifestVersion': '1.0',
        'sizingEvidencePolicy': [
          'Sizing workbook is advisory until source evidence is attached.: Source sheets are attached: Confirm source freshness and authority before recommendation.',
          'Do not treat lifecycle or EoX replacement PIDs as final model choice.: Lifecycle/current portfolio validation required: Use official lifecycle sources and current portfolio capability facts.',
          'Power, mGig, WAN, and HA gates must be closed before BOM confidence.: Wi-Fi 7; UPOE/mGig hard gate: Validate PoE/UPOE budget, AP draw, uplinks, inspected throughput, and redundancy.',
          'Assumptions must remain visible and owner-reviewable.: Assumptions captured: Review assumptions with the customer owner.',
        ],
        'sizingEvidencePolicyCount': 4,
        'sizingVisualVerificationChecklist': [
          'Open workbook and confirm all sizing sheets are visible.: Users need reviewable sheets for requirements, capacity, PoE, WAN, risks, and decisions.: Required',
          'Verify header rows are frozen/readable and columns fit the data.: Customer review fails quickly when workbook columns clip key inputs.: Required',
          'Review PoE Budget, Closet Power Plan, and WAN Throughput sheets.: Power and inspected-throughput assumptions drive model suitability.: High priority',
          'Confirm Candidate Validation and Requirement Gates show open risks.: The workbook should not imply a final BOM before hard gates close.: Required',
          'Check Evidence Policy and Publishing Readiness before sharing externally.: The file should state what evidence is missing and who owns follow-up.: Required',
        ],
        'sizingVisualVerificationChecklistCount': 5,
        'sizingPublishingMetadata': [
          'External handoff: Hard gates, validation roadmap, and customer follow-up questions are reviewed.: Owner approval required',
          'Audience: Customer or internal architecture review audience is identified.: Review required',
          'Decision posture: Medium - requirements review required: Needs requirements closure',
          'Evidence: Source sheets, datasheets, lifecycle dates, and customer inventory are attached.: Attached',
          'Assumptions: Sizing assumptions and unknowns are explicit.: Captured',
        ],
        'sizingPublishingMetadataCount': 5,
        'hasSizingQualityManifest': true,
        'hasSizingEvidencePolicy': true,
        'hasSizingVisualVerificationChecklist': true,
        'hasSizingPublishingMetadata': true,
        'hardGateFailures': [
          'Power budget: Needs datasheet validation',
          'WAN and security throughput: Needs platform validation',
          'Candidate facts: unverified product capability or lifecycle fit',
        ],
        'hardGateFailureCount': 3,
        'customerFollowUpQuestions': [
          'For Wi-Fi 7/high-power APs, what UPOE/UPOE+ and mGig requirements are mandatory?',
          'Which lifecycle/support sources and checked dates should govern final model selection?',
        ],
        'customerFollowUpQuestionCount': 2,
        'validationRoadmap': [
          'Lifecycle / support: Use official lifecycle sources; treat EoX replacement PID as a migration hint only.',
          'Candidate validation: close datasheet, lifecycle, licensing, PoE, mGig, uplink, and HA fit checks.',
        ],
        'validationRoadmapCount': 2,
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
    expect(find.text('Sizing readiness'), findsOneWidget);
    expect(find.text('Ready for requirements review'), findsOneWidget);
    expect(find.text('Sizing handoff'), findsOneWidget);
    expect(find.text('Requirements review workbook'), findsOneWidget);
    expect(find.text('Decision posture'), findsOneWidget);
    expect(
      find.text('Advisory only - close hard gates before BOM recommendation'),
      findsOneWidget,
    );
    expect(find.text('Handoff gates'), findsOneWidget);
    expect(find.text('4/6 ready'), findsOneWidget);
    expect(find.text('Sizing manifest'), findsOneWidget);
    expect(find.text('Manifest v1.0'), findsOneWidget);
    expect(find.text('Evidence policy'), findsOneWidget);
    expect(find.textContaining('Sizing workbook is advisory'), findsOneWidget);
    expect(find.text('Visual checks'), findsOneWidget);
    expect(
      find.textContaining('Open workbook and confirm all sizing sheets'),
      findsOneWidget,
    );
    expect(find.text('Publishing'), findsOneWidget);
    expect(find.textContaining('External handoff'), findsOneWidget);
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
    expect(find.text('Hard gates'), findsOneWidget);
    expect(find.textContaining('Power budget'), findsOneWidget);
    expect(find.text('Customer questions'), findsOneWidget);
    expect(find.textContaining('Wi-Fi 7/high-power APs'), findsOneWidget);
    expect(find.text('Validation roadmap'), findsOneWidget);
    expect(find.textContaining('Lifecycle / support'), findsOneWidget);
    expect(find.text('High-power AP/UPOE signal'), findsOneWidget);
    expect(find.text('mGig validation signal'), findsOneWidget);
    expect(find.text('Validation included'), findsOneWidget);
  });

  testWidgets('Artifacts drawer shows product comparison workbook metadata', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final artifact = GeneratedArtifact(
      id: 'comparison-1',
      kind: GeneratedArtifactKind.excel,
      status: GeneratedArtifactStatus.ready,
      fileName: 'access-comparison.xlsx',
      filePath: '/tmp/access-comparison.xlsx',
      summary:
          'Created a product comparison matrix with candidates, hard gates, evidence policy, and publishing readiness.',
      byteSize: 24576,
      previewRows: const [
        ['Decision Signal', 'Current Answer', 'Why It Matters', 'Next Action'],
        [
          'Recommended primary candidate',
          'C9300-48P',
          'Best balanced fit',
          'Validate datasheet and lifecycle source',
        ],
      ],
      sheetCount: 21,
      metadata: const {
        'artifact': 'product_comparison_matrix',
        'workbookKind': 'product_comparison',
        'sheetCount': 21,
        'candidateCount': 3,
        'requirementCount': 4,
        'hardGateEvaluationCount': 5,
        'atRiskGateCount': 2,
        'needsValidationGateCount': 3,
        'sourceConfidenceCount': 3,
        'shortlistCount': 3,
        'validationCheckCount': 5,
        'comparisonReadinessLevel': 'Medium - evidence review required',
        'comparisonHandoffStatus': 'Comparison review workbook',
        'comparisonDecisionPosture':
            'Advisory only - validate hard gates and source evidence before final recommendation',
        'hasComparisonCustomerHandoffMatrix': true,
        'comparisonCustomerHandoffGateCount': 6,
        'comparisonCustomerHandoffReadyCount': 2,
        'comparisonCustomerHandoffMatrix': [
          {
            'gate': 'Candidate set',
            'signal': '3 candidates captured',
            'status': 'Ready',
            'ownerAction': 'Confirm candidate roles.',
            'ready': true,
          },
          {
            'gate': 'Hard-gate fit',
            'signal': 'UPOE/high-power AP; multigig access',
            'status': 'Needs validation',
            'ownerAction': 'Validate power, mGig, lifecycle, and support.',
            'ready': false,
          },
        ],
        'recommendedCandidate': 'C9300-48P',
        'runnerUpCandidate': 'Meraki MS355',
        'requirementPressure':
            'UPOE/high-power AP; multigig access; lifecycle validation',
        'evidenceQuality': 'Needs source validation',
        'replacementCaveat': 'EoX replacement PID is migration hint only',
        'comparisonQualityManifestVersion': '1.0',
        'comparisonEvidencePolicy': [
          'Comparison matrix is advisory until source evidence is attached.: Source sheets are missing: Attach official datasheets, lifecycle records, and portfolio facts.',
          'Do not treat EoX replacement PIDs as final model choice.: Migration hints require current portfolio validation: Compare against current capabilities and requirements.',
          'Hard gates override fit score.: Power, mGig, uplink, lifecycle, and licensing constraints can reject a high-scoring candidate.',
          'Rejected alternatives need explicit reasons.: Every rejected candidate should state the failed requirement or missing evidence.',
        ],
        'comparisonEvidencePolicyCount': 4,
        'comparisonVisualVerificationChecklist': [
          'Open workbook and confirm all comparison sheets are visible.: Required',
          'Verify header rows are frozen/readable and columns fit product names.: Required',
          'Review Hard Gate Evaluation for At risk and Needs validation rows.: High priority',
          'Check Replacement Cautions before external handoff.: Required',
          'Confirm Sources Needed and Evidence Policy before sharing.: Required',
        ],
        'comparisonVisualVerificationChecklistCount': 5,
        'comparisonPublishingMetadata': [
          'External handoff: Hard gates, replacement cautions, and source gaps are reviewed.: Owner approval required',
          'Decision posture: Advisory until source evidence closes.: Review required',
          'Hard gates: At-risk and needs-validation rows are visible.: Required',
          'Lifecycle caveat: EoX replacement PID is treated as migration hint only.: Required',
          'Alternatives: Rejected candidates include explicit reasons.: Required',
        ],
        'comparisonPublishingMetadataCount': 5,
        'hasComparisonQualityManifest': true,
        'hasComparisonEvidencePolicy': true,
        'hasComparisonVisualVerificationChecklist': true,
        'hasComparisonPublishingMetadata': true,
        'qualityStatus': 'Needs evidence review',
        'qualityScore': 82,
        'qualityGates': [
          'Native format ready',
          'Comparison sheets packaged',
          'Evidence policy embedded',
          'Publishing readiness embedded',
        ],
        'qualityGaps': [
          'Attach official datasheets',
          'Attach lifecycle source dates',
        ],
        'qualityNextAction':
            'Validate official sources before customer handoff.',
        'hasCustomerReadyArtifact': false,
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

    expect(find.text('access-comparison.xlsx'), findsOneWidget);
    expect(
      find.textContaining('Excel • Needs evidence review'),
      findsOneWidget,
    );
    expect(find.text('Workbook preview'), findsOneWidget);
    expect(find.text('Recommended primary candidate'), findsOneWidget);

    await tester.tap(find.text('access-comparison.xlsx'));
    await tester.pump();

    expect(find.text('Quality'), findsOneWidget);
    expect(find.text('82/100'), findsOneWidget);
    expect(find.text('Needs evidence review'), findsAtLeastNWidgets(1));
    expect(find.text('Comparison readiness'), findsOneWidget);
    expect(find.text('Medium - evidence review required'), findsOneWidget);
    expect(find.text('Comparison handoff'), findsOneWidget);
    expect(find.text('Comparison review workbook'), findsOneWidget);
    expect(find.text('Decision posture'), findsOneWidget);
    expect(find.textContaining('Advisory only'), findsOneWidget);
    expect(find.text('Handoff gates'), findsOneWidget);
    expect(find.text('2/6 ready'), findsOneWidget);
    expect(find.text('Comparison manifest'), findsOneWidget);
    expect(find.text('Manifest v1.0'), findsOneWidget);
    expect(find.text('Primary'), findsOneWidget);
    expect(find.text('C9300-48P'), findsAtLeastNWidgets(1));
    expect(find.text('Runner-up'), findsOneWidget);
    expect(find.text('Meraki MS355'), findsOneWidget);
    expect(find.text('Hard gates'), findsAtLeastNWidgets(1));
    expect(find.textContaining('UPOE/high-power AP'), findsOneWidget);
    expect(find.text('Evidence'), findsOneWidget);
    expect(find.text('Needs source validation'), findsOneWidget);
    expect(find.text('Evidence policy'), findsOneWidget);
    expect(
      find.textContaining('Comparison matrix is advisory'),
      findsOneWidget,
    );
    expect(find.text('Visual checks'), findsOneWidget);
    expect(
      find.textContaining('Open workbook and confirm all comparison sheets'),
      findsOneWidget,
    );
    expect(find.text('Publishing'), findsOneWidget);
    expect(find.textContaining('External handoff'), findsOneWidget);
    expect(find.text('Candidates'), findsOneWidget);
    expect(find.text('3'), findsAtLeastNWidgets(1));
    expect(find.text('At-risk gates'), findsOneWidget);
    expect(find.text('Needs validation'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(
      find.text('Validate official sources before customer handoff.'),
      findsOneWidget,
    );
  });

  testWidgets('Artifacts drawer shows lifecycle EoX workbook metadata', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final artifact = GeneratedArtifact(
      id: 'lifecycle-1',
      kind: GeneratedArtifactKind.excel,
      status: GeneratedArtifactStatus.ready,
      fileName: 'lifecycle-eox-review.xlsx',
      filePath: '/tmp/lifecycle-eox-review.xlsx',
      summary:
          'Created a Lifecycle / EoX workbook with executive risk, date authority, replacement readiness, and evidence policy.',
      byteSize: 28672,
      previewRows: const [
        ['Decision Signal', 'Current Answer', 'Why It Matters', 'Next Action'],
        [
          'Highest lifecycle risk',
          'High',
          'Lifecycle risk drives refresh urgency',
          'Build migration plan',
        ],
      ],
      sheetCount: 21,
      metadata: const {
        'artifact': 'lifecycle_eox_workbook',
        'workbookKind': 'lifecycle_eox',
        'sheetCount': 21,
        'sourceSheetCount': 1,
        'lifecycleRecordCount': 2,
        'highRiskLifecycleCount': 1,
        'unknownLifecycleDateCount': 1,
        'urgencyItemCount': 2,
        'migrationHintCount': 2,
        'replacementSuitabilityCount': 2,
        'currentPortfolioCandidateCount': 3,
        'customerActionCount': 5,
        'lifecycleRiskCount': 2,
        'lifecycleReadinessLevel': 'High risk - source validation required',
        'lifecycleHandoffStatus': 'Lifecycle risk review workbook',
        'lifecycleDecisionPosture':
            'Lifecycle dates are authoritative only when sourced; replacement PIDs remain migration hints until current-fit validation closes.',
        'highestLifecycleRisk': 'High',
        'dateAuthority': 'Cisco EoX/API or official Cisco evidence required',
        'checkedDateStatus': 'Checked date 2026-06-30',
        'migrationPosture': 'Migration clue only',
        'modernRequirementPressure':
            'Wi-Fi 7, UPOE / 802.3bt, mGig / high-speed access',
        'hasOfficialLifecycleSource': true,
        'hasCheckedDateEvidence': true,
        'lifecycleQualityManifestVersion': '1.0',
        'lifecycleEvidencePolicy': [
          'Lifecycle dates require Cisco EoX/API or official Cisco evidence.: Cisco lifecycle source signal detected: Attach source URL/API record, checked date, and product-specific lifecycle fields before customer handoff.',
          'Replacement PIDs are migration hints only.: Migration or replacement hint detected: Compare suggestedMigrationPid against current portfolio, Wi-Fi 7, UPOE, mGig, uplink, licensing, and lifecycle runway requirements.',
          'Modern requirements can supersede EoX migration hints.: Wi-Fi 7, UPOE / 802.3bt, mGig / high-speed access: Reject or re-rank candidates that fail power, access speed, HA, licensing, or runway gates.',
          'Customer-facing lifecycle claims need checked dates.: Checked date 2026-06-30: Record when evidence was checked and refresh stale or incomplete records before external use.',
        ],
        'lifecycleEvidencePolicyCount': 4,
        'lifecycleVisualVerificationChecklist': [
          'Open workbook and confirm all lifecycle sheets are visible.: Required',
          'Verify lifecycle date columns and checked-date fields are readable.: Required',
          'Review Replacement Suitability and Migration Decision before sharing.: High priority',
          'Confirm Current Portfolio Shortlist includes supersede rules.: High priority',
          'Check Evidence Policy and Publishing Readiness before external handoff.: Required',
        ],
        'lifecycleVisualVerificationChecklistCount': 5,
        'lifecyclePublishingMetadata': [
          'External handoff: Official lifecycle source, checked date, replacement caveats, and current-fit validation are reviewed.: Owner approval required',
          'Decision posture: Lifecycle dates inform support risk; final model choice requires current portfolio and requirement matching.: Advisory',
          'Date authority: Cisco EoX/API or official Cisco lifecycle source is attached for every customer-facing date.: Detected',
          'Replacement caveat: EoX replacement PID is labeled suggestedMigrationPid and not final recommendation.: Required',
          'Modern requirements: Wi-Fi 7, UPOE, mGig, uplink, licensing, and HA gates are validated before BOM or model recommendation.: Required',
        ],
        'lifecyclePublishingMetadataCount': 5,
        'lifecycleCustomerHandoffMatrix': [
          'Official lifecycle date authority: Every customer-facing EoS/EoL/LDOS date is backed by Cisco EoX/API or official Cisco evidence.: Official Cisco lifecycle source signal detected: Ready: Attach source URL/API record for every lifecycle date.: Do not publish lifecycle dates without official source evidence.',
          'Checked-date traceability: Lifecycle evidence includes a visible checked date so stale data can be refreshed.: Checked 2026-06-30: Ready: Record checked date and refresh interval for each lifecycle lookup.: Customer handoff must show when lifecycle evidence was checked.',
          'Lifecycle completeness: All in-scope products have status, End of Sale, LDOS, risk, and source fields populated.: TBD lifecycle dates remain: Blocked: Fill missing lifecycle dates from official sources before final handoff.: Unknown dates must be labeled as gaps, not implied as validated.',
          'Migration hint caveat: EoX replacement PID is labeled as suggestedMigrationPid or migration hint only.: suggestedMigrationPid / replacement hint detected: Ready: Compare every migration hint against current portfolio alternatives.: Never present EoX replacement PID as final best model by itself.',
          'Current portfolio fit validation: Replacement recommendation checks current capabilities, lifecycle runway, licensing, HA, uplinks, PoE/UPOE, and mGig.: Wi-Fi 7, UPOE / 802.3bt, mGig / high-speed access: Needs validation: Attach current datasheet/catalog facts and rejected alternatives.: Final model choice requires current portfolio validation, not EoX hint alone.',
          'Risk posture and next action: High-risk lifecycle items have owner, urgency, and migration/revalidation action.: High-risk products detected: Needs review: Assign owner and migration plan before customer decision.: High-risk support dates should drive refresh urgency and customer communication.',
        ],
        'lifecycleCustomerHandoffGateCount': 6,
        'lifecycleCustomerHandoffReadyCount': 3,
        'hasLifecycleQualityManifest': true,
        'hasLifecycleEvidencePolicy': true,
        'hasLifecycleVisualVerificationChecklist': true,
        'hasLifecyclePublishingMetadata': true,
        'hasLifecycleCustomerHandoffMatrix': true,
        'qualityStatus': 'Needs evidence review',
        'qualityScore': 84,
        'qualityGates': [
          'Native format ready',
          'Lifecycle sheets packaged',
          'Evidence policy embedded',
          'Publishing readiness embedded',
        ],
        'qualityGaps': [
          'Validate replacement suitability',
          'Attach source URL/API record',
        ],
        'qualityNextAction':
            'Validate official lifecycle evidence before customer handoff.',
        'hasCustomerReadyArtifact': false,
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

    expect(find.text('lifecycle-eox-review.xlsx'), findsOneWidget);
    expect(
      find.textContaining('Excel • Needs evidence review'),
      findsOneWidget,
    );
    expect(find.text('Workbook preview'), findsOneWidget);
    expect(find.text('Highest lifecycle risk'), findsOneWidget);

    await tester.tap(find.text('lifecycle-eox-review.xlsx'));
    await tester.pump();

    expect(find.text('Quality'), findsOneWidget);
    expect(find.text('84/100'), findsOneWidget);
    expect(find.text('Lifecycle readiness'), findsOneWidget);
    expect(find.text('High risk - source validation required'), findsOneWidget);
    expect(find.text('Lifecycle handoff'), findsOneWidget);
    expect(find.text('Lifecycle risk review workbook'), findsOneWidget);
    expect(find.text('Decision posture'), findsOneWidget);
    expect(
      find.textContaining('Lifecycle dates are authoritative'),
      findsOneWidget,
    );
    expect(find.text('Handoff gates'), findsOneWidget);
    expect(find.text('3/6 ready'), findsOneWidget);
    expect(find.text('Lifecycle manifest'), findsOneWidget);
    expect(find.text('Manifest v1.0'), findsOneWidget);
    expect(find.text('Highest risk'), findsOneWidget);
    expect(find.text('High'), findsAtLeastNWidgets(1));
    expect(find.text('Date authority'), findsOneWidget);
    expect(
      find.text('Cisco EoX/API or official Cisco evidence required'),
      findsOneWidget,
    );
    expect(find.text('Checked date'), findsOneWidget);
    expect(find.text('Checked date 2026-06-30'), findsOneWidget);
    expect(find.text('Migration posture'), findsOneWidget);
    expect(find.text('Migration clue only'), findsOneWidget);
    expect(find.text('Modern requirements'), findsOneWidget);
    expect(find.textContaining('Wi-Fi 7'), findsAtLeastNWidgets(1));
    expect(find.text('Evidence policy'), findsOneWidget);
    expect(
      find.textContaining('Lifecycle dates require Cisco EoX/API'),
      findsOneWidget,
    );
    expect(find.text('Visual checks'), findsOneWidget);
    expect(
      find.textContaining('Open workbook and confirm all lifecycle sheets'),
      findsOneWidget,
    );
    expect(find.text('Publishing'), findsOneWidget);
    expect(find.textContaining('External handoff'), findsOneWidget);
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('High-risk items'), findsOneWidget);
    expect(find.text('Unknown dates'), findsOneWidget);
    expect(find.text('Migration hints'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(
      find.text(
        'Validate official lifecycle evidence before customer handoff.',
      ),
      findsOneWidget,
    );
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
            ['Slide', 'Type', 'Title', 'Role'],
            [
              '1',
              'Title',
              'Executive Brief',
              'Open with audience, purpose, and evidence count',
            ],
            ['2', 'Agenda', 'Decision Flow', 'Set the decision path'],
          ],
          sheetCount: 6,
          metadata: const {
            'artifactDescriptorId': 'powerpoint_deck',
            'artifactDescriptorLabel': 'PowerPoint Deck',
            'artifactPreviewSurface': 'Slide outline',
            'artifactUseCases': [
              'proposal',
              'architecture review',
              'business case',
            ],
            'artifactVerificationChecks': [
              'PPTX package opens/parses',
              'Slide outline metadata persists',
              'Deck readiness metadata renders',
            ],
            'deckType': 'Customer proposal deck',
            'handoffStatus': 'Ready for stakeholder review',
            'customerHandoffGateCount': 5,
            'customerHandoffGateReadyCount': 4,
            'decisionAsk':
                'Review the recommendation, confirm assumptions, and approve the next implementation step.',
            'theme': 'Light',
            'pptxInspectionStatus': 'Verified',
            'pptxSlideFileCount': 6,
            'pptxNotesFileCount': 6,
            'pptxHas16x9Layout': true,
            'pptxInspectionFailedChecks': <String>[],
            'audience': 'Executive stakeholders',
            'deckPurpose': 'Support a decision',
            'deliveryReadinessScore': 94,
            'deliveryReadinessLevel': 'Customer handoff ready',
            'deckStatusStrip': [
              'Readiness: Customer handoff ready',
              'Evidence: High - sources and assumptions captured',
              'Gate: reviewer approval ready',
            ],
            'deckStatusStripCount': 3,
            'hasDeckStatusStrip': true,
            'deckReviewPriority': 'Low - ready for stakeholder review',
            'deliveryReadinessDrivers': [
              'Executive delivery brief included',
              'Decision matrix included',
              'Stakeholder ownership lanes included',
              '2 supporting tables included',
              '3 assumptions captured',
              '5 source items captured',
            ],
            'deliveryReadinessDriverCount': 6,
            'audienceHandoffNotes': [
              'Audience: Executive stakeholders.',
              'Lead with: By the end, Executive stakeholders should support a decision because validate the recommendation.',
              'Decision ask: Review the recommendation, confirm assumptions, and approve the next implementation step.',
            ],
            'audienceHandoffNoteCount': 3,
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
              'Executive delivery brief',
              'Decision snapshot',
              'Recommendations',
              'Roadmap',
              'Data tables',
              'Assumptions/sources',
              'Appendix',
            ],
            'slidePreview': [
              '1. Title: Executive Brief - Open with audience, purpose, and evidence count',
              '2. Agenda: Decision Flow - Set the decision path',
              '3. Decision: Decision Snapshot - Summarize recommendation, risk, and next step',
            ],
            'slidePreviewCount': 3,
            'tableCoverage': '2 tables packaged',
            'sourceCoverage': '5 source items captured',
            'evidenceConfidence': 'High - sources and assumptions captured',
            'deckReviewChecklist': [
              'Confirm deck title, audience, and decision ask match the customer conversation.',
              'Review readout framing for account-specific phrasing.',
              'Validate decision matrix signals, risk posture, and next actions.',
            ],
            'deckVisualVerificationChecklist': [
              'Open the deck at 16:9 and verify title, agenda, decision, roadmap, assumptions, sources, and appendix slides are readable.',
              'Confirm visible slide copy is audience-facing; implementation detail belongs in speaker notes or appendix slides.',
              'Review table slides for readable row count, clipped values, and column alignment.',
            ],
            'deckVisualVerificationChecklistCount': 3,
            'deckEvidencePolicy': [
              'Slides are presentation guidance, not source evidence by themselves.',
              'Customer handoff requires source data, checked dates, assumptions, and owner approval.',
              'Use the cited source list as the evidence register for external review.',
            ],
            'deckEvidencePolicyCount': 3,
            'deckPublishingMetadata': [
              'Delivery readiness: Customer handoff ready',
              'Delivery score: 94/100',
              'Evidence confidence: High - sources and assumptions captured',
              'Handoff status: Ready for stakeholder review',
              'Publishing gate: ready for reviewer approval',
            ],
            'deckPublishingMetadataCount': 5,
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
              'Delivery brief',
              'Decision snapshot',
              'Recommendation slides',
              'Roadmap',
              'Speaker notes',
            ],
            'sectionCount': 4,
            'sectionDividerCount': 3,
            'deliveryBriefSlideCount': 1,
            'tableCount': 2,
            'tableSlideCount': 2,
            'recommendationSlideCount': 2,
            'assumptionCount': 3,
            'citationCount': 5,
            'hasCustomerReadyStructure': true,
            'hasCustomerReadyDeck': true,
            'hasDeliveryBrief': true,
            'hasSpeakerNotes': true,
            'speakerNoteCount': 6,
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
            'docxInspectionStatus': 'Verified',
            'docxStructuralValid': true,
            'docxExpectedReportStructure': true,
            'docxDeclaredWordCount': 860,
            'docxParagraphCount': 78,
            'docxHasTableOfContents': true,
            'docxHasExplicitTableGeometry': true,
            'docxHasRepeatingTableHeaders': true,
            'docxHasAccessibilityManifest': true,
            'docxInspectionFailedChecks': <String>[],
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
            'evidenceConfidence': 'High - sources and assumptions captured',
            'visualEvidenceReliability':
                'metadata_plus_ocr_or_user_description',
            'visualEvidenceCount': 4,
            'visualEvidenceSidecarCount': 2,
            'visualEvidenceMetadataOnlyCount': 2,
            'visualEvidenceReviewAction':
                'Validate OCR/description sidecar accuracy before customer-facing visual claims.',
            'visualVerificationChecklist': [
              'Open the DOCX in Word and verify headings, tables, appendices, header/footer, and sign-off sections render without clipping.',
              'Confirm table headers repeat and columns remain readable in print layout.',
              'Verify executive decision brief, recommendation summary, risk register, approval gates, and sign-off page appear in order.',
              'Confirm sources appendix is included with checked dates and source labels.',
              'Confirm assumptions appendix is explicit and owner-reviewable.',
            ],
            'reportEvidencePolicy': [
              'Report narrative is guidance; source appendices and source artifacts are the evidence record.',
              'Customer handoff requires checked sources, assumptions, decision owner, and approval gate.',
              'Use cited sources as the evidence register for external review.',
              'Review assumptions with the accountable owner before stakeholder handoff.',
            ],
            'reportReviewChecklist': [
              'Confirm report title, audience, decision owner, and decision ask.',
              'Review executive decision brief and recommendation summary for customer-specific language.',
              'Validate risk register, next-step action plan, and approval gates.',
            ],
            'reportHandoffActions': [
              'Send report to internal reviewer with source artifacts attached.',
              'Walk through the decision ask: Review findings, confirm assumptions, and approve the recommended architecture path.',
              'Keep cited sources with the handoff package.',
            ],
            'reportRiskFlags': <String>[],
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
      find.text(
        'PowerPoint Deck for proposal, architecture review, business case',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Word / DOCX Report for architecture document, implementation report',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Word • Architecture report • 860 words'),
      findsOneWidget,
    );
    expect(find.textContaining('Screenshot text attached'), findsOneWidget);
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
    expect(
      find.textContaining('Agenda, Delivery brief'),
      findsAtLeastNWidgets(1),
    );

    await tester.tap(find.text('executive-brief.pptx'));
    await tester.pump();

    expect(find.text('Deck'), findsOneWidget);
    expect(find.text('Customer proposal deck'), findsOneWidget);
    expect(find.text('Artifact'), findsOneWidget);
    expect(find.text('PowerPoint Deck'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Slide outline'), findsAtLeastNWidgets(1));
    expect(find.text('Use cases'), findsOneWidget);
    expect(
      find.textContaining('proposal, architecture review +1'),
      findsOneWidget,
    );
    expect(find.text('Artifact checks'), findsOneWidget);
    expect(find.textContaining('PPTX package opens/parses'), findsOneWidget);
    expect(find.text('Handoff'), findsOneWidget);
    expect(find.text('Ready for stakeholder review'), findsOneWidget);
    expect(find.text('Handoff gates'), findsOneWidget);
    expect(find.text('4/5 ready'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Audience'), findsOneWidget);
    expect(find.text('Executive stakeholders'), findsOneWidget);
    expect(find.text('Purpose'), findsOneWidget);
    expect(find.text('Support a decision'), findsOneWidget);
    expect(find.text('PPTX inspection'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Slide files'), findsOneWidget);
    expect(find.text('Speaker notes'), findsAtLeastNWidgets(1));
    expect(find.text('Layout'), findsOneWidget);
    expect(find.text('16:9'), findsOneWidget);
    expect(find.text('Delivery readiness'), findsOneWidget);
    expect(find.text('Customer handoff ready'), findsOneWidget);
    expect(find.text('Delivery score'), findsOneWidget);
    expect(find.text('94/100'), findsOneWidget);
    expect(find.text('Deck status'), findsOneWidget);
    expect(
      find.textContaining('Readiness: Customer handoff ready'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Evidence: High - sources and assumptions captured +1',
      ),
      findsOneWidget,
    );
    expect(find.text('Review priority'), findsOneWidget);
    expect(find.text('Low - ready for stakeholder review'), findsOneWidget);
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
    expect(find.textContaining('Opening, Agenda'), findsOneWidget);
    expect(find.textContaining('Executive delivery brief'), findsOneWidget);
    expect(find.text('Slide preview'), findsOneWidget);
    expect(
      find.textContaining(
        '1. Title: Executive Brief - Open with audience, purpose',
      ),
      findsOneWidget,
    );
    expect(find.text('Readiness'), findsOneWidget);
    expect(
      find.textContaining('Agenda, Delivery brief'),
      findsAtLeastNWidgets(1),
    );
    expect(find.text('Readiness drivers'), findsOneWidget);
    expect(
      find.textContaining('Executive delivery brief included'),
      findsOneWidget,
    );
    expect(find.text('Audience handoff'), findsOneWidget);
    expect(
      find.textContaining('Audience: Executive stakeholders.'),
      findsOneWidget,
    );
    expect(find.text('Sections'), findsOneWidget);
    expect(find.text('Dividers'), findsOneWidget);
    expect(find.text('Delivery brief'), findsOneWidget);
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
    expect(find.text('Visual checks'), findsOneWidget);
    expect(
      find.textContaining('Open the deck at 16:9 and verify title'),
      findsOneWidget,
    );
    expect(find.text('Evidence policy'), findsOneWidget);
    expect(
      find.textContaining(
        'Slides are presentation guidance, not source evidence by themselves.',
      ),
      findsOneWidget,
    );
    expect(find.text('Publishing'), findsOneWidget);
    expect(
      find.textContaining('Delivery readiness: Customer handoff ready'),
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
    expect(find.text('Speaker notes'), findsAtLeastNWidgets(1));
    expect(find.text('6'), findsAtLeastNWidgets(1));
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
    expect(find.text('DOCX inspection'), findsOneWidget);
    expect(find.text('Verified'), findsAtLeastNWidgets(1));
    expect(find.text('DOCX package'), findsOneWidget);
    expect(find.text('Structurally valid'), findsOneWidget);
    expect(find.text('DOCX structure'), findsOneWidget);
    expect(find.text('Customer-ready report'), findsOneWidget);
    expect(find.text('Declared words'), findsOneWidget);
    expect(find.text('860'), findsAtLeastNWidgets(1));
    expect(find.text('Paragraphs'), findsOneWidget);
    expect(find.text('78'), findsOneWidget);
    expect(find.text('Table of contents'), findsOneWidget);
    expect(find.text('Included'), findsOneWidget);
    expect(find.text('Table geometry'), findsOneWidget);
    expect(find.text('Fixed layout'), findsOneWidget);
    expect(find.text('Table headers'), findsOneWidget);
    expect(find.text('Repeating'), findsOneWidget);
    expect(find.text('Accessibility'), findsAtLeastNWidgets(1));
    expect(find.text('Manifest included'), findsOneWidget);
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
    expect(find.text('Evidence confidence'), findsOneWidget);
    expect(
      find.text('High - sources and assumptions captured'),
      findsOneWidget,
    );
    expect(find.text('Visual evidence'), findsOneWidget);
    expect(find.text('Screenshot text attached'), findsAtLeastNWidgets(1));
    expect(find.text('Visual items'), findsOneWidget);
    expect(find.text('4 captured'), findsOneWidget);
    expect(find.text('OCR/sidecar'), findsOneWidget);
    expect(find.text('2 attached'), findsOneWidget);
    expect(find.text('Metadata-only'), findsOneWidget);
    expect(find.text('2 need validation'), findsOneWidget);
    expect(find.text('Visual next step'), findsOneWidget);
    expect(
      find.textContaining('Validate OCR/description sidecar accuracy'),
      findsOneWidget,
    );
    expect(find.text('Visual checks'), findsOneWidget);
    expect(
      find.textContaining('Open the DOCX in Word and verify headings'),
      findsOneWidget,
    );
    expect(find.text('Evidence policy'), findsOneWidget);
    expect(find.textContaining('Report narrative is guidance'), findsOneWidget);
    expect(find.text('Report review'), findsOneWidget);
    expect(
      find.textContaining(
        'Confirm report title, audience, decision owner, and decision ask.',
      ),
      findsOneWidget,
    );
    expect(find.text('Handoff actions'), findsOneWidget);
    expect(
      find.textContaining(
        'Send report to internal reviewer with source artifacts attached.',
      ),
      findsOneWidget,
    );
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

  testWidgets('Artifacts drawer shows evidence pack handoff gates', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final artifact = GeneratedArtifact(
      id: 'evidence-pack-1',
      kind: GeneratedArtifactKind.docx,
      status: GeneratedArtifactStatus.ready,
      fileName: 'lifecycle-evidence-pack.docx',
      filePath: '/tmp/lifecycle-evidence-pack.docx',
      summary: 'Created an evidence pack.',
      byteSize: 12288,
      sheetCount: 9,
      metadata: const {
        'artifactTemplate': 'evidence_pack',
        'reportType': 'Evidence pack',
        'handoffStatus': 'Evidence review required',
        'evidenceConfidence': 'Medium - source review required',
        'evidenceCustomerHandoffGateCount': 6,
        'evidenceCustomerHandoffReadyCount': 3,
        'evidenceCustomerHandoffMatrix': [
          'Source authority: Customer-facing claims are backed by official, customer-provided, or clearly reliable evidence.: Authoritative source signal attached: Ready: Attach official/customer/reliable source evidence for each material claim.: Do not publish material claims without traceable source authority.',
          'Checked-date traceability: Every time-sensitive claim has a visible checked date and refresh owner.: Checked dates present: Ready: Add checked date, freshness window, and accountable evidence owner.: Lifecycle, pricing, capability, market, and support claims require checked dates.',
          'Unsupported-claim disposition: Unsupported claims are verified, qualified, rewritten, or removed before customer handoff.: 1 unsupported claim flagged: Blocked: Resolve every flagged claim and update customer-safe wording.: Unsupported claims cannot remain in final customer artifacts.',
        ],
        'hasEvidenceCustomerHandoffMatrix': true,
        'visualEvidenceReliability':
            'metadata_only_until_vision_or_user_description',
        'visualEvidenceCount': 2,
        'visualEvidenceMetadataOnlyCount': 2,
        'visualEvidenceRequiresVisionReview': true,
      },
      createdAt: DateTime(2026, 7, 2, 11),
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

    expect(find.text('lifecycle-evidence-pack.docx'), findsOneWidget);
    await tester.tap(find.text('lifecycle-evidence-pack.docx'));
    await tester.pump();

    expect(find.text('Evidence confidence'), findsOneWidget);
    expect(find.text('Medium - source review required'), findsOneWidget);
    expect(find.text('Handoff gates'), findsOneWidget);
    expect(find.text('3/6 ready'), findsOneWidget);
    expect(find.text('Visual evidence'), findsOneWidget);
    expect(find.text('Metadata-only screenshots'), findsOneWidget);
    expect(find.text('Vision review'), findsOneWidget);
  });

  testWidgets('Artifacts drawer shows business use case handoff gates', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final artifact = GeneratedArtifact(
      id: 'business-brief-1',
      kind: GeneratedArtifactKind.docx,
      status: GeneratedArtifactStatus.ready,
      fileName: 'acme-business-brief.docx',
      filePath: '/tmp/acme-business-brief.docx',
      summary: 'Created a business use case brief.',
      byteSize: 8192,
      sheetCount: 12,
      metadata: const {
        'artifactTemplate': 'business_use_case_brief',
        'reportType': 'Business use case brief',
        'handoffStatus': 'Discovery ready',
        'businessCaseExecutiveReadiness':
            'Discovery ready - validate evidence gaps before executive handoff',
        'businessCaseHandoffGateCount': 6,
        'businessCaseHandoffReadyCount': 4,
        'businessCaseCustomerHandoffMatrix': [
          'Sourced company and industry evidence: Every external business claim has a cited source and checked date.: Source evidence attached: Ready: Attach public/company/customer sources with checked dates.: Do not customer-share unsupported market, company, or value claims.',
          'Customer-specific use cases: Brief names concrete use cases tied to this customer or industry context.: 2 use cases captured: Ready: Confirm priority use cases with the business sponsor and workflow owner.: Generic use cases must be reframed around the customer before handoff.',
          'Value metric and baseline: Each priority use case has a measurable KPI, baseline, owner, or target hypothesis.: Value metrics need baseline: Blocked: Collect baseline KPI, measurement owner, and target improvement.: ROI/value claims stay advisory until baseline evidence is attached.',
        ],
        'hasBusinessCaseCustomerHandoffMatrix': true,
      },
      createdAt: DateTime(2026, 7, 2, 10),
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

    expect(find.text('acme-business-brief.docx'), findsOneWidget);
    await tester.tap(find.text('acme-business-brief.docx'));
    await tester.pump();

    expect(find.text('Business readiness'), findsOneWidget);
    expect(
      find.text(
        'Discovery ready - validate evidence gaps before executive handoff',
      ),
      findsOneWidget,
    );
    expect(find.text('Handoff gates'), findsOneWidget);
    expect(find.text('4/6 ready'), findsOneWidget);
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
        'topologyReadinessScore': 68,
        'topologyReadinessLevel': 'Needs validation before handoff',
        'topologyReviewChecklist': [
          'Confirm topology scope, site count, MDF/IDF boundaries, and ownership.',
          'Validate WAN handoffs, uplink speeds, routing preference, and failover test plan.',
          'Validate AP count, PoE/UPOE budget, mGig need, spare ports, and IDF-level power headroom.',
        ],
        'topologyHandoffActions': [
          'Package diagram with inventory, link schedule, assumptions, and validation gaps.',
          'Walk stakeholders through resiliency model, failover path, and outage domains.',
          'Confirm Wi-Fi/AP power, UPOE/UPOE+, mGig ports, and switch power supplies before model selection.',
        ],
        'topologyRiskFlags': [
          'Validation gap: Uplinks',
          'Failure domain: MDF / Core',
          'Wi-Fi 7 APs need explicit mGig access validation',
        ],
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
    expect(find.text('Readiness level'), findsOneWidget);
    expect(find.text('Needs validation before handoff'), findsOneWidget);
    expect(find.text('Readiness score'), findsOneWidget);
    expect(find.text('68/100'), findsOneWidget);
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
    expect(find.text('Topology review'), findsOneWidget);
    expect(
      find.textContaining('Confirm topology scope, site count'),
      findsOneWidget,
    );
    expect(find.text('Handoff actions'), findsOneWidget);
    expect(
      find.textContaining('Package diagram with inventory'),
      findsOneWidget,
    );
    expect(find.text('Topology risks'), findsOneWidget);
    expect(find.textContaining('Validation gap: Uplinks'), findsOneWidget);
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
        'chartReadinessScore': 74,
        'chartReadinessLevel': 'Needs owner review before handoff',
        'chartQualityManifestVersion': '1.0',
        'chartQualityStatus': 'Needs validation',
        'riskPosture': 'High risk - owner review required',
        'hasChartQualityManifest': true,
        'hasChartHandoffReadinessMatrix': true,
        'chartHandoffReadinessGateCount': 6,
        'chartHandoffReadinessReadyCount': 4,
        'chartVisualVerificationChecklist': [
          'SVG has title, description, viewBox, and embedded metadata',
          'Summary, risk legend, chart panels, and point labels are visible',
        ],
        'chartEvidencePolicy': [
          'Charts are decision support, not source evidence by themselves',
          'Customer handoff requires source table, checked date, units, and owner',
        ],
        'chartPublishingMetadata': [
          'Readiness score: 74/100',
          'Risk posture: High risk - owner review required',
        ],
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
        'decisionQuestions': [
          'Does the access design have enough PoE/UPOE reserve for AP draw, growth, and switch power-supply redundancy?',
          'Do WAN links support inspected throughput, failover behavior, and SLA expectations under peak load?',
          'Which lifecycle risks require near-term refresh, and which replacement choices need current portfolio validation?',
        ],
        'handoffChecklist': [
          'Confirm each chart uses current source data, units, date, and owner.',
          'Review threshold meaning for every high, medium, review, or warning signal.',
          'Attach source evidence or checked dates before external use.',
        ],
        'reviewerNextSteps': [
          'Assign owners and due dates before customer handoff.',
          'Validate capacity headroom against growth and failover assumptions.',
        ],
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
    expect(find.text('Readiness level'), findsOneWidget);
    expect(find.text('Needs owner review before handoff'), findsOneWidget);
    expect(find.text('Readiness score'), findsOneWidget);
    expect(find.text('74/100'), findsOneWidget);
    expect(find.text('Quality'), findsOneWidget);
    expect(find.text('Needs validation'), findsOneWidget);
    expect(find.text('Handoff gates'), findsOneWidget);
    expect(find.text('4/6 ready'), findsOneWidget);
    expect(find.text('Quality manifest'), findsOneWidget);
    expect(find.text('Manifest v1.0'), findsOneWidget);
    expect(find.text('Risk posture'), findsOneWidget);
    expect(find.text('High risk - owner review required'), findsOneWidget);
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
    expect(find.text('Visual checks'), findsOneWidget);
    expect(find.textContaining('SVG has title'), findsOneWidget);
    expect(find.text('Evidence policy'), findsOneWidget);
    expect(find.textContaining('Charts are decision support'), findsOneWidget);
    expect(find.text('Publishing'), findsOneWidget);
    expect(find.textContaining('Readiness score: 74/100'), findsOneWidget);
    expect(find.text('Decision questions'), findsOneWidget);
    expect(find.textContaining('Does the access design'), findsOneWidget);
    expect(find.text('Handoff checklist'), findsOneWidget);
    expect(find.textContaining('Confirm each chart uses'), findsOneWidget);
    expect(find.text('Reviewer next'), findsOneWidget);
    expect(find.textContaining('Assign owners'), findsOneWidget);
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
        'expectedArtifactCount': 3,
        'producedArtifactCount': 3,
        'expectedArtifactKinds': ['Word', 'PowerPoint', 'Chart'],
        'producedArtifactKinds': ['Word', 'PowerPoint', 'Chart'],
        'missingArtifactKinds': <String>[],
        'packageCompletenessStatus': 'Complete',
        'hasCompletePackage': true,
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
        'packagePreviewSurfaces': [
          'Executive brief preview',
          'Slide outline',
          'Chart visual preview',
        ],
        'packageVerificationChecks': [
          'Open every customer-ready file before sharing.',
          'Confirm assumptions and citations are present.',
          'Validate chart thresholds with the account team.',
        ],
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
    expect(find.text('Preview surfaces'), findsOneWidget);
    expect(find.text('Executive brief preview'), findsOneWidget);
    expect(find.text('Slide outline'), findsOneWidget);
    expect(find.text('Verification checks'), findsOneWidget);
    expect(
      find.text('Open every customer-ready file before sharing.'),
      findsOneWidget,
    );
    expect(find.text('deck.pptx'), findsAtLeastNWidgets(1));
    expect(find.text('PowerPoint'), findsAtLeastNWidgets(1));

    await tester.ensureVisible(find.text('deck.pptx').last);
    await tester.pump();
    await tester.tap(find.text('deck.pptx').last);
    await tester.pump();

    expect(
      container.read(studioRightDrawerProvider).selectedArtifactId,
      'generated-deck-1',
    );

    await tester.ensureVisible(find.text('business-case-package.md'));
    await tester.pump();
    await tester.tap(find.text('business-case-package.md'));
    await tester.pump();

    expect(find.text('Package'), findsOneWidget);
    expect(find.text('business use case package'), findsAtLeastNWidgets(1));
    expect(find.text('Package status'), findsOneWidget);
    expect(find.text('Package ready'), findsAtLeastNWidgets(1));
    expect(find.text('Completeness'), findsOneWidget);
    expect(find.text('Complete'), findsOneWidget);
    expect(find.text('Package score'), findsOneWidget);
    expect(find.text('92/100'), findsOneWidget);
    expect(find.text('Expected'), findsOneWidget);
    expect(find.text('Produced'), findsOneWidget);
    expect(find.text('Artifacts'), findsAtLeastNWidgets(1));
    expect(find.text('3'), findsAtLeastNWidgets(1));
    expect(find.text('Ready artifacts'), findsOneWidget);
    expect(find.text('3/3'), findsOneWidget);
    expect(find.text('Expected types'), findsOneWidget);
    expect(find.text('Produced types'), findsOneWidget);
    expect(find.textContaining('Word, PowerPoint +1'), findsAtLeastNWidgets(1));
    expect(find.text('Package next'), findsOneWidget);
    expect(
      find.text(
        'Review the package and share the selected customer-ready files.',
      ),
      findsAtLeastNWidgets(1),
    );
    expect(find.text('Review workflow'), findsOneWidget);
    expect(find.textContaining('Review Word report narrative'), findsOneWidget);
    expect(find.text('File types'), findsOneWidget);
    expect(find.textContaining('Word, PowerPoint +1'), findsAtLeastNWidgets(1));
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

  testWidgets('Artifacts drawer Open and Reveal dispatch file paths', (
    tester,
  ) async {
    const revealChannel = MethodChannel('circuitcode/file_reveal');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(revealChannel, (call) async => false);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(revealChannel, null);
    });
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
    final root = Directory.systemTemp.createTempSync('studio_artifact_open_');
    addTearDown(() => root.deleteSync(recursive: true));
    final file = File('${root.path}/proposal.pptx')
      ..writeAsBytesSync([1, 2, 3]);
    final preview = File('${root.path}/proposal.pptx.preview.svg')
      ..writeAsStringSync('<svg xmlns="http://www.w3.org/2000/svg"/>');
    final previewBytes = preview.readAsBytesSync();
    final artifact = GeneratedArtifact(
      id: 'pptx-1',
      kind: GeneratedArtifactKind.powerPoint,
      status: GeneratedArtifactStatus.ready,
      fileName: 'proposal.pptx',
      filePath: file.path,
      summary: 'Created a PowerPoint deck.',
      byteSize: file.lengthSync(),
      metadata: {
        'visualPreviewPath': preview.path,
        'visualPreviewSha256': sha256.convert(previewBytes).toString(),
        'visualPreviewByteSize': previewBytes.length,
        'visualPreviewPersistence': 'atomic-sidecar-v1',
      },
      createdAt: DateTime(2026, 6, 30, 9, 22),
      outputHash: sha256.convert(file.readAsBytesSync()).toString(),
    );
    final restored = GeneratedArtifact.fromSourceArtifact(
      artifact.toSourceArtifact(),
    );
    expect(restored, isNotNull);
    expect(
      (await const ArtifactVisualPreviewVerifier().verify(restored!)).isValid,
      isTrue,
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

    await tester.tap(find.widgetWithText(TextButton, 'Open'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Preview'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Reveal'));
    await tester.pump();

    expect(launched.map((uri) => uri.toFilePath()), [
      file.path,
      preview.path,
      root.path,
    ]);

    preview.writeAsStringSync('<svg>substituted visual review</svg>');
    await tester.tap(find.widgetWithText(TextButton, 'Preview'));
    await tester.pump();

    expect(launched.map((uri) => uri.toFilePath()), [
      file.path,
      preview.path,
      root.path,
    ]);
    expect(find.textContaining('no longer matches'), findsOneWidget);
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

  testWidgets('Artifacts drawer exposes topology deck export target', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final root = Directory.systemTemp.createTempSync('studio_diagram_export_');
    addTearDown(() => root.deleteSync(recursive: true));
    final outputDir = Directory('${root.path}/outputs')..createSync();
    final file = File('${outputDir.path}/campus-topology.svg')
      ..writeAsStringSync('<svg><title>Campus topology</title></svg>');
    final artifact = GeneratedArtifact(
      id: 'diagram-export-1',
      kind: GeneratedArtifactKind.diagram,
      status: GeneratedArtifactStatus.ready,
      fileName: 'campus-topology.svg',
      filePath: file.path,
      summary: 'Created an SVG topology diagram.',
      byteSize: file.lengthSync(),
      previewRows: const [
        ['Topology', '7 nodes / 6 links', 'Review before handoff.'],
      ],
      sheetCount: 1,
      metadata: const {
        'topologyType': 'Campus topology',
        'nodeCount': 7,
        'edgeCount': 6,
      },
      createdAt: DateTime(2026, 7, 2, 9, 30),
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

    await tester.tap(find.text('campus-topology.svg'));
    await tester.pump();
    expect(find.text('Export'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Export as'));
    await tester.tap(find.byTooltip('Export as'));
    await tester.pumpAndSettle();
    expect(find.text('PowerPoint deck'), findsOneWidget);
    expect(find.text('PDF report'), findsOneWidget);
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

  testWidgets(
    'Context drawer identifies the effective instruction order for a live turn',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(contextPackProvider.notifier)
          .buildForCodingTask(prompt: 'Review the current turn');
      container.read(studioRightDrawerProvider.notifier).openContext();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
        ),
      );
      await tester.pump();

      expect(find.text('Effective instructions'), findsOneWidget);
      expect(find.text('CircuitCode runtime policy'), findsOneWidget);
      expect(
        find.textContaining('Runtime policy → global CIRCUIT.md'),
        findsOneWidget,
      );
      expect(
        find.textContaining('CircuitCode policy always wins'),
        findsOneWidget,
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
