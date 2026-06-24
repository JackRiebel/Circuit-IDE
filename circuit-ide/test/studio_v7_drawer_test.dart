import 'dart:io';

import 'package:circuit_ide/models/context_pack.dart';
import 'package:circuit_ide/models/git_models.dart';
import 'package:circuit_ide/models/studio_right_drawer.dart';
import 'package:circuit_ide/models/studio_source_artifact.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/state/context_pack_provider.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/git_provider.dart';
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

  testWidgets('Studio drawer hides quarantined browser preview tab', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: Align(child: StudioRightDrawer())),
        ),
      ),
    );

    expect(find.byTooltip('Progress'), findsOneWidget);
    expect(find.byTooltip('Code'), findsOneWidget);
    expect(find.byTooltip('Diff'), findsOneWidget);
    expect(find.byTooltip('Files'), findsOneWidget);
    expect(find.byTooltip('Terminal output'), findsOneWidget);
    expect(find.byTooltip('Sources'), findsOneWidget);
    expect(find.byTooltip('Context details'), findsOneWidget);
    expect(find.byTooltip('Browser preview'), findsNothing);
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
    expect(find.text('README.md'), findsWidgets);
    expect(find.text('Review only'), findsOneWidget);
    expect(find.text('Stage'), findsNothing);
    expect(find.text('Unstage'), findsNothing);
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

      await tester.tap(find.text('Include next'));
      await tester.pump();

      expect(
        container
            .read(contextPackProvider.notifier)
            .includeNextTimePathsForCurrentRoot(),
        contains('important.dart'),
      );
    },
  );

  testWidgets('Context drawer hides removed live retrieval items before send', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final root = Directory.systemTemp.createTempSync('studio_context_remove_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    File(
      '${root.path}/important.dart',
    ).writeAsStringSync('void importantThing() {}\n');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(fileTreeProvider.notifier).openDirectory(root.path),
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

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();

    expect(find.text('important.dart'), findsNothing);
    expect(
      container.read(contextPackProvider)!.serializePrompt(),
      isNot(contains('importantThing')),
    );
  });
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
