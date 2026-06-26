import 'dart:io';

import 'package:circuit_ide/core/constants/design_tokens.dart';
import 'package:circuit_ide/models/command_run.dart';
import 'package:circuit_ide/models/context_pack.dart';
import 'package:circuit_ide/models/git_models.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/models/studio_right_drawer.dart';
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
import 'package:circuit_ide/state/studio_source_artifact_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/ui/studio/studio_right_drawer.dart';
import 'package:circuit_ide/ui/terminal/terminal_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    expect(find.text('Code'), findsWidgets);
    expect(find.text('Diff'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Terminal output'), findsOneWidget);
    expect(find.text('Sources'), findsWidgets);
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
    expect(find.byTooltip('Context details'), findsOneWidget);
    expect(find.byIcon(Icons.language), findsNWidgets(24));
    expect(tester.widget<Icon>(find.byIcon(Icons.language).last).size, 11);

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

    expect(find.text('lib/main.dart'), findsOneWidget);
    expect(find.textContaining('@@ -1 +1 @@'), findsOneWidget);
    expect(find.text('No changes'), findsNothing);
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
      BorderRadius.circular(7),
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
        BorderRadius.circular(7),
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
