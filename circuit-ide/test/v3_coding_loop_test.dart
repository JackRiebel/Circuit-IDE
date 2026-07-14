import 'dart:io';

import 'package:circuit_ide/models/accepted_plan_context.dart';
import 'package:circuit_ide/models/context_pack.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/models/spec_models.dart';
import 'package:circuit_ide/models/specialist_agent.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/models/suggested_learning.dart';
import 'package:circuit_ide/models/work_item.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:circuit_ide/state/context_pack_provider.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/chat_provider.dart';
import 'package:circuit_ide/state/patch_proposal_provider.dart';
import 'package:circuit_ide/state/project_profile_provider.dart';
import 'package:circuit_ide/state/spec_provider.dart';
import 'package:circuit_ide/state/studio_shell_provider.dart';
import 'package:circuit_ide/state/suggested_learning_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/state/studio_turn_provider.dart';
import 'package:circuit_ide/state/work_item_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('ContextPack serializes visible context only', () {
    final pack = ContextPack(
      id: 'ctx',
      projectKey: 'project',
      createdAt: DateTime(2026),
      removedItemIds: const ['terminal'],
      items: const [
        ContextPackItem(
          id: 'profile',
          type: ContextPackItemType.projectProfile,
          title: 'Project',
          detail: 'Flutter app',
          estimatedTokens: 10,
        ),
        ContextPackItem(
          id: 'terminal',
          type: ContextPackItemType.terminal,
          title: 'Terminal',
          detail: 'secret output',
          estimatedTokens: 20,
        ),
      ],
    );

    expect(pack.visibleItems.map((item) => item.id), ['profile']);
    expect(pack.estimatedTokens, 10);
    expect(pack.serializePrompt(), contains('Flutter app'));
    expect(pack.serializePrompt(), isNot(contains('secret output')));
  });

  test('ContextPack serializes within retrieval budget', () {
    final pack = ContextPack(
      id: 'ctx-budget',
      projectKey: 'project',
      createdAt: DateTime(2026),
      items: const [
        ContextPackItem(
          id: 'profile',
          type: ContextPackItemType.projectProfile,
          title: 'Project',
          detail: 'Flutter app',
          estimatedTokens: 10,
          removable: false,
        ),
        ContextPackItem(
          id: 'active',
          type: ContextPackItemType.activeFile,
          title: 'main.dart',
          detail: 'void main() {}',
          estimatedTokens: 25,
          retrievalScore: 120,
        ),
        ContextPackItem(
          id: 'terminal',
          type: ContextPackItemType.terminal,
          title: 'Terminal',
          detail: 'very long terminal output',
          estimatedTokens: 80,
          retrievalScore: 5,
        ),
      ],
      retrievalResult: const ContextRetrievalResult(
        rankedCandidates: [
          ContextCandidate(
            id: 'active',
            title: 'main.dart',
            sourceKind: ContextPackSourceKind.editor,
            score: 120,
            estimatedTokens: 25,
            included: true,
            reason: 'active file',
          ),
          ContextCandidate(
            id: 'terminal',
            title: 'Terminal',
            sourceKind: ContextPackSourceKind.terminal,
            score: 5,
            estimatedTokens: 80,
            included: true,
            reason: 'recent terminal',
          ),
        ],
        budget: ContextBudgetReport(
          maxTokens: 60,
          reservedForResponse: 20,
          availableForContext: 40,
          usedTokens: 115,
        ),
      ),
    );

    final prompt = pack.serializePrompt();

    expect(pack.compactedVisibleItems.map((item) => item.id), [
      'profile',
      'active',
    ]);
    expect(pack.compactedOmittedItems.map((item) => item.id), ['terminal']);
    expect(prompt, contains('Flutter app'));
    expect(prompt, contains('void main()'));
    expect(prompt, isNot(contains('very long terminal output')));
    expect(prompt, contains('omitted to fit the selected model budget'));
  });

  test(
    'ContextPack serializes retrieval warnings even without visible items',
    () {
      final pack = ContextPack(
        id: 'ctx-warning-only',
        projectKey: 'project',
        createdAt: DateTime(2026),
        retrievalResult: const ContextRetrievalResult(
          rankedCandidates: [],
          budget: ContextBudgetReport(
            maxTokens: 1000,
            reservedForResponse: 200,
            availableForContext: 800,
            usedTokens: 0,
          ),
          warnings: [
            ContextPackWarning(
              message:
                  'Project instructions conflict with app permission policy; app policy wins.',
              itemId: 'instruction-conflict:approval',
            ),
          ],
        ),
      );

      final prompt = pack.serializePrompt();

      expect(prompt, contains('[context-warnings]'));
      expect(prompt, contains('app policy wins'));
    },
  );

  test('ContextPackController builds project profile context', () async {
    final root = await _sampleFlutterProject();
    addTearDown(() => _delete(root));
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(fileTreeProvider.notifier).openDirectory(root.path);
    await container.read(projectProfileProvider.notifier).refresh();

    final pack = container
        .read(contextPackProvider.notifier)
        .buildForCodingTask(prompt: 'Improve startup');

    expect(pack.visibleItems.first.type, ContextPackItemType.projectProfile);
    expect(pack.serializePrompt(), contains('Improve startup'));
    expect(pack.estimatedTokens, greaterThan(0));
    final retrieval = pack.retrievalResult!;
    expect(retrieval.rankedCandidates, isNotEmpty);
    expect(
      retrieval.rankedCandidates.map((candidate) => candidate.rank),
      orderedEquals([
        for (var index = 1; index <= retrieval.rankedCandidates.length; index++)
          index,
      ]),
    );
    expect(retrieval.rankedCandidates.first.contentFingerprint, isNotEmpty);
    final restored = ContextRetrievalResult.fromJson(retrieval.toJson())!;
    expect(restored.rankedCandidates.first.rank, 1);
    expect(
      restored.rankedCandidates.first.contentFingerprint,
      retrieval.rankedCandidates.first.contentFingerprint,
    );
  });

  test('ContextPackController includes pinned context on next build', () async {
    final root = await Directory.systemTemp.createTemp('context_include_next_');
    final prefsRoot = await Directory.systemTemp.createTemp(
      'context_include_next_prefs_',
    );
    addTearDown(() => _delete(root));
    addTearDown(() => _delete(prefsRoot));
    await Directory(p.join(root.path, 'lib')).create(recursive: true);
    await File(
      p.join(root.path, 'lib', 'important.dart'),
    ).writeAsString('class ImportantContext {}\n');

    final firstContainer = ProviderContainer(
      overrides: [
        contextPreferenceStoreProvider.overrideWithValue(
          ContextPreferenceStore(baseDir: prefsRoot.path),
        ),
      ],
    );
    addTearDown(firstContainer.dispose);

    await firstContainer
        .read(fileTreeProvider.notifier)
        .openDirectory(root.path);
    firstContainer
        .read(contextPackProvider.notifier)
        .includeNextTime('lib/important.dart');

    final container = ProviderContainer(
      overrides: [
        contextPreferenceStoreProvider.overrideWithValue(
          ContextPreferenceStore(baseDir: prefsRoot.path),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(fileTreeProvider.notifier).openDirectory(root.path);

    final pack = container
        .read(contextPackProvider.notifier)
        .buildForCodingTask(prompt: '');
    final included = pack.retrievalResult!.includedCandidates;

    expect(
      pack.visibleItems.map((item) => item.source),
      contains('lib/important.dart'),
    );
    expect(
      included
          .firstWhere((candidate) => candidate.path == 'lib/important.dart')
          .reason,
      contains('included next time from Context drawer'),
    );
  });

  test(
    'ContextPackController persists project exclusions and can reset them',
    () async {
      final root = await Directory.systemTemp.createTemp('context_exclude_');
      final prefsRoot = await Directory.systemTemp.createTemp(
        'context_exclude_prefs_',
      );
      addTearDown(() => _delete(root));
      addTearDown(() => _delete(prefsRoot));
      await Directory(p.join(root.path, 'lib')).create(recursive: true);
      await File(
        p.join(root.path, 'lib', 'ignored.dart'),
      ).writeAsString('class IgnoredContext {}\n');

      final store = ContextPreferenceStore(baseDir: prefsRoot.path);
      final firstContainer = ProviderContainer(
        overrides: [contextPreferenceStoreProvider.overrideWithValue(store)],
      );
      addTearDown(firstContainer.dispose);
      await firstContainer
          .read(fileTreeProvider.notifier)
          .openDirectory(root.path);
      final controller = firstContainer.read(contextPackProvider.notifier);
      controller.includeNextTime('lib/ignored.dart');
      controller.excludeForProject('lib/ignored.dart');

      expect(controller.includeNextTimePathsForCurrentRoot(), isEmpty);
      expect(
        controller.excludedPathsForCurrentRoot(),
        contains('lib/ignored.dart'),
      );
      expect(store.loadIncludedPaths(root.path), isEmpty);
      expect(store.loadExcludedPaths(root.path), contains('lib/ignored.dart'));

      final reloadedContainer = ProviderContainer(
        overrides: [contextPreferenceStoreProvider.overrideWithValue(store)],
      );
      addTearDown(reloadedContainer.dispose);
      await reloadedContainer
          .read(fileTreeProvider.notifier)
          .openDirectory(root.path);
      final reloaded = reloadedContainer.read(contextPackProvider.notifier);
      expect(
        reloaded.excludedPathsForCurrentRoot(),
        contains('lib/ignored.dart'),
      );

      reloaded.resetProjectContextChoices();
      expect(store.loadIncludedPaths(root.path), isEmpty);
      expect(store.loadExcludedPaths(root.path), isEmpty);
    },
  );

  test(
    'ContextPackController ranks symbol declaration files from index',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'context_symbol_rank_',
      );
      addTearDown(() => _delete(root));
      await Directory(
        p.join(root.path, 'lib', 'domain'),
      ).create(recursive: true);
      await Directory(p.join(root.path, 'docs')).create(recursive: true);
      await File(p.join(root.path, 'pubspec.yaml')).writeAsString('''
name: symbol_context
dependencies:
  flutter:
    sdk: flutter
''');
      await File(
        p.join(root.path, 'lib', 'domain', 'sizing_engine.dart'),
      ).writeAsString('''
class DatacenterSizingEngine {
  int scoreWanThroughput(int mbps) => mbps;
}
''');
      await File(p.join(root.path, 'docs', 'notes.md')).writeAsString('''
# Notes

DatacenterSizingEngine is mentioned here, but the implementation lives in code.
''');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final pack = await container
          .read(contextPackProvider.notifier)
          .buildForCodingTaskWithFreshIndex(
            prompt: 'Update DatacenterSizingEngine WAN scoring behavior',
          );
      final relevant = pack.visibleItems
          .where((item) => item.id.startsWith('relevant-file:'))
          .toList(growable: false);

      expect(relevant, isNotEmpty);
      expect(relevant.first.source, 'lib/domain/sizing_engine.dart');
      final candidate = pack.retrievalResult!.rankedCandidates.firstWhere(
        (item) => item.path == 'lib/domain/sizing_engine.dart',
      );
      expect(candidate.included, isTrue);
      expect(candidate.reason, contains('symbol "datacentersizingengine"'));
    },
  );

  test(
    'PatchProposalController applies and restores reviewed patches',
    () async {
      final root = await Directory.systemTemp.createTemp('patch_v3_');
      addTearDown(() => _delete(root));
      final file = File(p.join(root.path, 'README.md'));
      await file.writeAsString('old\n');
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      await _waitForThreadStore(container);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Patch transaction history');
      container
          .read(studioTurnProvider.notifier)
          .registerTurn(
            requestId: 'patch-transaction-turn',
            threadId: thread.id,
            taskId: null,
            userMessageId: 'user-patch-transaction-turn',
            prompt: 'Apply the reviewed patch',
            model: 'gpt-5-nano',
            contextSummary: StudioContextSummary(
              projectLabel: 'patch',
              rootPath: root.path,
            ),
          );
      final patchSet = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Update readme',
            runId: 'patch-transaction-turn',
            verificationRequested: true,
            edits: const [
              ProposedFileEdit(
                path: 'README.md',
                type: ProposedFileEditType.modify,
                before: 'old\n',
                after: 'new\n',
              ),
            ],
          );

      expect(container.read(patchProposalProvider).active?.id, patchSet.id);

      final result = await container
          .read(patchProposalProvider.notifier)
          .applyActive();

      expect(result.status, PatchApplyStatus.applied);
      expect(await file.readAsString(), 'new\n');
      expect(result.checkpointId, isNotNull);
      expect(result.verificationRequested, isTrue);

      final restore = await container
          .read(patchProposalProvider.notifier)
          .restoreCheckpoint(result.checkpointId!);

      expect(restore.status, PatchApplyStatus.restored);
      expect(await file.readAsString(), 'old\n');
      final restoredPatch = container
          .read(patchProposalProvider)
          .history
          .firstWhere((candidate) => candidate.id == patchSet.id);
      expect(restoredPatch.applyStatus, PatchApplyStatus.restored);
      expect(restoredPatch.changedFiles, ['README.md']);
      expect(restoredPatch.diffSummary, contains('Modified README.md'));
      expect(restoredPatch.verificationSuggestions, [
        'Run the relevant project checks for the changed files.',
      ]);
      expect(restoredPatch.verificationRequested, isTrue);

      final updatedThread = container
          .read(studioThreadProvider)
          .threads
          .firstWhere((candidate) => candidate.id == thread.id);
      final transactionEvents = updatedThread.turns.single.events
          .where(
            (event) =>
                event.type == StudioTurnEventType.completionSummary &&
                event.id.contains('patch-transaction'),
          )
          .toList();
      expect(transactionEvents, hasLength(2));
      expect(transactionEvents.map((event) => event.title), [
        'Applied changes',
        'Restored checkpoint',
      ]);
      expect(transactionEvents.first.detail, contains('Applied 1 files.'));
      expect(transactionEvents.first.detail, contains('Modified README.md'));
      expect(transactionEvents.first.detail, contains('Checkpoint:'));
      expect(transactionEvents.last.detail, contains('Restored 1 files.'));
      expect(transactionEvents.last.detail, contains('README.md'));
    },
  );

  test(
    'PatchProposalController records rejected and revision-requested patches on the originating turn',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'patch_review_outcomes_',
      );
      addTearDown(() => _delete(root));
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      await _waitForThreadStore(container);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Patch review outcome history');
      container
          .read(studioTurnProvider.notifier)
          .registerTurn(
            requestId: 'patch-review-turn',
            threadId: thread.id,
            taskId: null,
            userMessageId: 'user-patch-review-turn',
            prompt: 'Review the proposed patch',
            model: 'gpt-5-nano',
            contextSummary: StudioContextSummary(
              projectLabel: 'patch',
              rootPath: root.path,
            ),
          );

      final rejectedPatch = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Add rejected file',
            runId: 'patch-review-turn',
            edits: const [
              ProposedFileEdit(
                path: 'rejected.txt',
                type: ProposedFileEditType.create,
                after: 'not this\n',
              ),
            ],
          );

      container.read(patchProposalProvider.notifier).reject(rejectedPatch.id);

      final revisionPatch = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Add file needing revision',
            runId: 'patch-review-turn',
            edits: const [
              ProposedFileEdit(
                path: 'needs_revision.txt',
                type: ProposedFileEditType.create,
                after: 'almost\n',
              ),
            ],
          );
      container
          .read(patchProposalProvider.notifier)
          .requestRevision(
            PatchProposalRevisionRequest(
              patchSetId: revisionPatch.id,
              prompt: 'Use the customer-safe wording instead.',
            ),
          );

      final updatedThread = container
          .read(studioThreadProvider)
          .threads
          .firstWhere((candidate) => candidate.id == thread.id);
      final transactionEvents = updatedThread.turns.single.events
          .where(
            (event) =>
                event.type == StudioTurnEventType.completionSummary &&
                event.id.contains('patch-transaction'),
          )
          .toList();
      expect(transactionEvents, hasLength(2));
      expect(transactionEvents.map((event) => event.title), [
        'Patch rejected',
        'Patch revision requested',
      ]);
      expect(transactionEvents.first.detail, contains('Patch rejected.'));
      expect(
        transactionEvents.first.detail,
        contains('Patch: Add rejected file'),
      );
      expect(
        transactionEvents.last.detail,
        contains('Patch revision requested.'),
      );
      expect(
        transactionEvents.last.detail,
        contains('Use the customer-safe wording instead.'),
      );
      expect(
        transactionEvents.last.detail,
        contains('Patch: Add file needing revision'),
      );
    },
  );

  test(
    'PatchProposalController blocks proposed patches containing secrets',
    () async {
      final root = await Directory.systemTemp.createTemp('patch_secret_v3_');
      addTearDown(() => _delete(root));
      final file = File(p.join(root.path, 'token.txt'));
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Add token',
            edits: const [
              ProposedFileEdit(
                path: 'token.txt',
                type: ProposedFileEditType.create,
                after:
                    'GITHUB_TOKEN=ghp_abcdefghijklmnopqrstuvwxyzABCDEFGHIJ\n',
              ),
            ],
          );

      final result = await container
          .read(patchProposalProvider.notifier)
          .applyActive();

      expect(result.status, PatchApplyStatus.conflict);
      expect(result.conflictMessage, contains('possible critical'));
      expect(await file.exists(), isFalse);
    },
  );

  test(
    'PatchProposalController reloads active proposals and checkpoints by project',
    () async {
      final root = await Directory.systemTemp.createTemp('patch_reload_v3_');
      final storeRoot = await Directory.systemTemp.createTemp(
        'patch_reload_store_v3_',
      );
      addTearDown(() => _delete(root));
      addTearDown(() => _delete(storeRoot));
      final target = File(p.join(root.path, 'hello.txt'));
      final store = PatchProposalStore(baseDir: storeRoot.path);

      final firstContainer = ProviderContainer(
        overrides: [patchProposalStoreProvider.overrideWithValue(store)],
      );
      addTearDown(firstContainer.dispose);
      await firstContainer
          .read(fileTreeProvider.notifier)
          .openDirectory(root.path);
      final proposed = firstContainer
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Add greeting',
            edits: const [
              ProposedFileEdit(
                path: 'hello.txt',
                type: ProposedFileEditType.create,
                after: 'hello\n',
              ),
            ],
            planMarkdown: '# Plan\n\n- Add hello.txt',
            plannedTargets: const [
              PlannedFileTarget(
                path: 'hello.txt',
                intent: 'Add a greeting file.',
                operation: ProposedFileEditType.create,
              ),
            ],
          );
      await _waitForPatchStore(
        store,
        root.path,
        (state) => state.active?.id == proposed.id,
      );

      final secondContainer = ProviderContainer(
        overrides: [patchProposalStoreProvider.overrideWithValue(store)],
      );
      addTearDown(secondContainer.dispose);
      await secondContainer
          .read(fileTreeProvider.notifier)
          .openDirectory(root.path);
      secondContainer.read(patchProposalProvider);
      await _waitForPatchProvider(
        secondContainer,
        (state) => state.active?.id == proposed.id,
      );

      final reloaded = secondContainer.read(patchProposalProvider);
      expect(reloaded.active?.id, proposed.id);
      expect(reloaded.active?.title, 'Add greeting');
      expect(reloaded.active?.edits.single.after, 'hello\n');
      expect(
        reloaded.active?.plannedTargets.single.intent,
        contains('greeting'),
      );

      final applyResult = await secondContainer
          .read(patchProposalProvider.notifier)
          .apply(proposed.id);
      expect(applyResult.status, PatchApplyStatus.applied);
      expect(applyResult.checkpointId, isNotNull);
      expect(await target.readAsString(), 'hello\n');

      final thirdContainer = ProviderContainer(
        overrides: [patchProposalStoreProvider.overrideWithValue(store)],
      );
      addTearDown(thirdContainer.dispose);
      await thirdContainer
          .read(fileTreeProvider.notifier)
          .openDirectory(root.path);
      thirdContainer.read(patchProposalProvider);
      await _waitForPatchProvider(
        thirdContainer,
        (state) =>
            state.history.any(
              (patch) =>
                  patch.id == proposed.id &&
                  patch.applyStatus == PatchApplyStatus.applied,
            ) &&
            state.checkpoints.containsKey(applyResult.checkpointId),
      );

      final reloadedApplied = thirdContainer.read(patchProposalProvider);
      expect(reloadedApplied.active, isNull);
      final appliedPatch = reloadedApplied.history
          .where((patch) => patch.id == proposed.id)
          .single;
      expect(appliedPatch.applyStatus, PatchApplyStatus.applied);
      expect(appliedPatch.changedFiles, ['hello.txt']);
      expect(appliedPatch.checkpointId, applyResult.checkpointId);
      expect(
        reloadedApplied.checkpoints.containsKey(applyResult.checkpointId),
        isTrue,
      );

      final restoreResult = await thirdContainer
          .read(patchProposalProvider.notifier)
          .restoreCheckpoint(applyResult.checkpointId!);
      expect(restoreResult.status, PatchApplyStatus.restored);
      expect(await target.exists(), isFalse);
    },
  );

  test(
    'PatchProposalController restores every crash-injected partial patch on reload',
    () async {
      for (final interruptAfterMutation in [1, 2, 3]) {
        final root = await Directory.systemTemp.createTemp(
          'patch_crash_atomic_${interruptAfterMutation}_',
        );
        final storeRoot = await Directory.systemTemp.createTemp(
          'patch_crash_atomic_store_${interruptAfterMutation}_',
        );
        addTearDown(() => _delete(root));
        addTearDown(() => _delete(storeRoot));
        final modified = File(p.join(root.path, 'modified.txt'));
        final deleted = File(p.join(root.path, 'deleted.txt'));
        final created = File(p.join(root.path, 'nested', 'created.txt'));
        await modified.writeAsString('before modify\n');
        await deleted.writeAsString('before delete\n');

        final store = PatchProposalStore(
          baseDir: storeRoot.path,
          onMutationApplied: (completedMutations) {
            if (completedMutations == interruptAfterMutation) {
              throw const PatchApplySimulatedCrash();
            }
          },
        );
        final applyingContainer = ProviderContainer(
          overrides: [patchProposalStoreProvider.overrideWithValue(store)],
        );
        await applyingContainer
            .read(fileTreeProvider.notifier)
            .openDirectory(root.path);
        final patch = applyingContainer
            .read(patchProposalProvider.notifier)
            .propose(
              title: 'Crash-safe transaction',
              edits: const [
                ProposedFileEdit(
                  path: 'modified.txt',
                  type: ProposedFileEditType.modify,
                  before: 'before modify\n',
                  after: 'after modify\n',
                ),
                ProposedFileEdit(
                  path: 'nested/created.txt',
                  type: ProposedFileEditType.create,
                  after: 'created\n',
                ),
                ProposedFileEdit(
                  path: 'deleted.txt',
                  type: ProposedFileEditType.delete,
                  before: 'before delete\n',
                ),
              ],
            );

        final interrupted = await applyingContainer
            .read(patchProposalProvider.notifier)
            .apply(patch.id);
        expect(interrupted.status, PatchApplyStatus.failed);
        expect(await File(store.applyJournalPath(root.path)).exists(), isTrue);
        applyingContainer.dispose();

        final recoveryContainer = ProviderContainer(
          overrides: [patchProposalStoreProvider.overrideWithValue(store)],
        );
        addTearDown(recoveryContainer.dispose);
        await recoveryContainer
            .read(fileTreeProvider.notifier)
            .openDirectory(root.path);
        recoveryContainer.read(patchProposalProvider);
        await _waitForPatchProvider(
          recoveryContainer,
          (state) =>
              state.message?.contains('Recovered an interrupted') ?? false,
        );

        expect(await modified.readAsString(), 'before modify\n');
        expect(await deleted.readAsString(), 'before delete\n');
        expect(await created.exists(), isFalse);
        expect(await Directory(p.join(root.path, 'nested')).exists(), isFalse);
        expect(await File(store.applyJournalPath(root.path)).exists(), isFalse);
        final recoveredPatch = recoveryContainer
            .read(patchProposalProvider)
            .history
            .firstWhere((candidate) => candidate.id == patch.id);
        expect(recoveredPatch.applyStatus, PatchApplyStatus.failed);
        expect(recoveredPatch.checkpointId, isNull);
      }
    },
  );

  test(
    'PatchProposalController blocks proposed patches targeting secret paths',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'patch_secret_path_v3_',
      );
      addTearDown(() => _delete(root));
      final envFile = File(p.join(root.path, '.env'));
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Add env',
            edits: const [
              ProposedFileEdit(
                path: '.env',
                type: ProposedFileEditType.create,
                after: 'FEATURE_FLAG=true\n',
              ),
            ],
          );

      final result = await container
          .read(patchProposalProvider.notifier)
          .applyActive();

      expect(result.status, PatchApplyStatus.conflict);
      expect(result.conflictMessage, contains('Secret or environment file'));
      expect(await envFile.exists(), isFalse);
      expect(container.read(patchProposalProvider).checkpoints, isEmpty);
    },
  );

  test(
    'PatchProposalController blocks root and nested sensitive patch paths',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'patch_sensitive_paths_v3_',
      );
      addTearDown(() => _delete(root));

      Future<PatchApplyResult> applySingle(String path) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container
            .read(fileTreeProvider.notifier)
            .openDirectory(root.path);
        final patchSet = container
            .read(patchProposalProvider.notifier)
            .propose(
              title: 'Sensitive target',
              edits: [
                ProposedFileEdit(
                  path: path,
                  type: ProposedFileEditType.create,
                  after: 'token=value\n',
                ),
              ],
            );
        final result = await container
            .read(patchProposalProvider.notifier)
            .apply(patchSet.id);
        expect(container.read(patchProposalProvider).checkpoints, isEmpty);
        return result;
      }

      for (final path in [
        '.npmrc',
        '.netrc',
        'id_rsa',
        'id_ed25519',
        '.aws/config',
        'nested/.npmrc',
        '.ssh/id_ed25519',
      ]) {
        final result = await applySingle(path);
        expect(result.status, PatchApplyStatus.conflict, reason: path);
        expect(
          result.conflictMessage,
          contains('Secret or environment file'),
          reason: path,
        );
        expect(await File(p.join(root.path, path)).exists(), isFalse);
      }
    },
  );

  test(
    'PatchProposalController applies mixed create modify delete transaction and restores checkpoint',
    () async {
      final root = await Directory.systemTemp.createTemp('patch_mixed_v3_');
      addTearDown(() => _delete(root));
      await File(
        p.join(root.path, 'pubspec.yaml'),
      ).writeAsString('name: patch_mixed\n');
      final readme = File(p.join(root.path, 'README.md'));
      await readme.writeAsString('old readme\n');
      final obsolete = File(p.join(root.path, 'obsolete.txt'));
      await obsolete.writeAsString('remove me\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final patchSet = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Mixed transaction',
            edits: const [
              ProposedFileEdit(
                path: 'README.md',
                type: ProposedFileEditType.modify,
                before: 'old readme\n',
                after: 'new readme\n',
              ),
              ProposedFileEdit(
                path: 'lib/generated.dart',
                type: ProposedFileEditType.create,
                after: 'const generated = true;\n',
              ),
              ProposedFileEdit(
                path: 'obsolete.txt',
                type: ProposedFileEditType.delete,
                before: 'remove me\n',
              ),
            ],
          );

      final result = await container
          .read(patchProposalProvider.notifier)
          .apply(patchSet.id);

      expect(result.status, PatchApplyStatus.applied);
      expect(result.changedFiles, [
        'README.md',
        'lib/generated.dart',
        'obsolete.txt',
      ]);
      expect(result.diffSummary, contains('Modified README.md'));
      expect(result.diffSummary, contains('Created lib/generated.dart'));
      expect(result.diffSummary, contains('Deleted obsolete.txt'));
      expect(result.verificationSuggestions, contains('flutter analyze'));
      expect(result.verificationSuggestions, contains('flutter test'));
      expect(await readme.readAsString(), 'new readme\n');
      expect(
        await File(p.join(root.path, 'lib', 'generated.dart')).readAsString(),
        'const generated = true;\n',
      );
      expect(await obsolete.exists(), isFalse);

      final restore = await container
          .read(patchProposalProvider.notifier)
          .restoreCheckpoint(result.checkpointId!);

      expect(restore.status, PatchApplyStatus.restored);
      expect(await readme.readAsString(), 'old readme\n');
      expect(
        await File(p.join(root.path, 'lib', 'generated.dart')).exists(),
        isFalse,
      );
      expect(await Directory(p.join(root.path, 'lib')).exists(), isFalse);
      expect(await obsolete.readAsString(), 'remove me\n');
      final restoredPatch = container
          .read(patchProposalProvider)
          .history
          .firstWhere((candidate) => candidate.id == patchSet.id);
      expect(restoredPatch.applyStatus, PatchApplyStatus.restored);
      expect(restoredPatch.changedFiles, [
        'README.md',
        'lib/generated.dart',
        'obsolete.txt',
      ]);
      expect(restoredPatch.diffSummary, contains('Modified README.md'));
      expect(restoredPatch.diffSummary, contains('Created lib/generated.dart'));
      expect(restoredPatch.diffSummary, contains('Deleted obsolete.txt'));
      expect(
        restoredPatch.verificationSuggestions,
        contains('flutter analyze'),
      );
      expect(restoredPatch.verificationSuggestions, contains('flutter test'));
    },
  );

  test(
    'PatchProposalController leaves earlier files untouched when a later edit conflicts',
    () async {
      final root = await Directory.systemTemp.createTemp('patch_conflict_v3_');
      addTearDown(() => _delete(root));
      final first = File(p.join(root.path, 'first.txt'));
      await first.writeAsString('first old\n');
      final second = File(p.join(root.path, 'second.txt'));
      await second.writeAsString('second changed\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final patchSet = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Late conflict',
            edits: const [
              ProposedFileEdit(
                path: 'first.txt',
                type: ProposedFileEditType.modify,
                before: 'first old\n',
                after: 'first new\n',
              ),
              ProposedFileEdit(
                path: 'second.txt',
                type: ProposedFileEditType.modify,
                before: 'second old\n',
                after: 'second new\n',
              ),
            ],
          );

      final result = await container
          .read(patchProposalProvider.notifier)
          .apply(patchSet.id);

      expect(result.status, PatchApplyStatus.conflict);
      expect(result.conflictMessage, contains('second.txt'));
      expect(await first.readAsString(), 'first old\n');
      expect(await second.readAsString(), 'second changed\n');
    },
  );

  test(
    'PatchProposalController maps prose conflict paths to one accepted-plan target',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'patch_prose_conflict_v3_',
      );
      addTearDown(() => _delete(root));

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      await _waitForThreadStore(container);

      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Accepted plan prose conflict');
      const acceptedPlan = AcceptedPlanContext(
        patchSetId: 'plan-prose-conflict',
        title: 'Two file plan',
        summary: 'Create app and docs files.',
        markdown: '- Create app.py\n- Create docs.md',
        plannedFiles: ['app.py — Create app', 'docs.md — Create docs'],
      );
      final turn = container
          .read(studioTurnProvider.notifier)
          .registerTurn(
            requestId: 'request-prose-conflict',
            threadId: thread.id,
            taskId: null,
            userMessageId: 'message-prose-conflict',
            prompt: 'Implement accepted plan',
            model: 'gpt-5-nano',
            contextSummary: StudioContextSummary(
              projectLabel: 'patch',
              rootPath: root.path,
            ),
            intent: TurnIntent.code,
            acceptedPlanState: AcceptedPlanState.patchProposed,
            acceptedPlanContext: acceptedPlan,
            userMessageTranscriptVisible: false,
          );

      final patchSet = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Create app and docs',
            runId: 'request-prose-conflict',
            edits: const [
              ProposedFileEdit(
                path: 'app.py',
                type: ProposedFileEditType.create,
                after: 'print("hi")\n',
              ),
              ProposedFileEdit(
                path: 'docs.md',
                type: ProposedFileEditType.create,
              ),
            ],
          );

      final result = await container
          .read(patchProposalProvider.notifier)
          .apply(patchSet.id);

      expect(result.status, PatchApplyStatus.conflict);
      expect(result.conflictMessage, contains('docs.md'));
      expect(await File(p.join(root.path, 'app.py')).exists(), isFalse);

      final updatedTurn = container
          .read(studioThreadProvider)
          .threads
          .where((candidate) => candidate.id == thread.id)
          .single
          .turns
          .where((candidate) => candidate.id == turn.id)
          .single;
      expect(
        updatedTurn.planTargetProgress
            .firstWhere((target) => target.path == 'app.py')
            .state,
        PlanTargetProgressState.pending,
      );
      expect(
        updatedTurn.planTargetProgress
            .firstWhere((target) => target.path == 'docs.md')
            .state,
        PlanTargetProgressState.conflict,
      );
      final conflictEvents = updatedTurn.events.where(
        (event) =>
            event.type == StudioTurnEventType.completionSummary &&
            event.title == 'Patch conflict',
      );
      expect(conflictEvents, hasLength(1));
      expect(conflictEvents.single.detail, contains('docs.md'));
      expect(conflictEvents.single.detail, contains('revise the patch'));
    },
  );

  test(
    'PatchProposalController refuses to apply plan-only proposals',
    () async {
      final root = await Directory.systemTemp.createTemp('patch_plan_only_v3_');
      addTearDown(() => _delete(root));
      final marker = File(p.join(root.path, 'marker.txt'));
      await marker.writeAsString('unchanged\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final patchSet = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Plan only',
            planMarkdown: '# Plan\n\nCreate a README update.',
            plannedFiles: const ['README.md — update docs'],
            edits: const [],
          );

      final result = await container
          .read(patchProposalProvider.notifier)
          .apply(patchSet.id);

      expect(result.status, PatchApplyStatus.conflict);
      expect(result.conflictMessage, contains('Plan-only proposals'));
      expect(result.conflictMessage, contains('concrete patch'));
      expect(await marker.readAsString(), 'unchanged\n');
      expect(container.read(patchProposalProvider).checkpoints, isEmpty);
      final updatedPatch = container.read(patchProposalProvider).active!;
      expect(updatedPatch.id, patchSet.id);
      expect(updatedPatch.applyStatus, PatchApplyStatus.conflict);
      expect(updatedPatch.changedFiles, isEmpty);
    },
  );

  test('PatchProposalController refuses empty patch proposals', () async {
    final root = await Directory.systemTemp.createTemp('patch_empty_v3_');
    addTearDown(() => _delete(root));
    final marker = File(p.join(root.path, 'marker.txt'));
    await marker.writeAsString('unchanged\n');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(fileTreeProvider.notifier).openDirectory(root.path);

    final patchSet = container
        .read(patchProposalProvider.notifier)
        .propose(title: 'Empty patch', edits: const []);

    final result = await container
        .read(patchProposalProvider.notifier)
        .apply(patchSet.id);

    expect(result.status, PatchApplyStatus.conflict);
    expect(result.conflictMessage, contains('no concrete file edits'));
    expect(await marker.readAsString(), 'unchanged\n');
    expect(container.read(patchProposalProvider).checkpoints, isEmpty);
    final updatedPatch = container.read(patchProposalProvider).active!;
    expect(updatedPatch.id, patchSet.id);
    expect(updatedPatch.applyStatus, PatchApplyStatus.conflict);
    expect(updatedPatch.changedFiles, isEmpty);
  });

  test(
    'PatchProposalController only suggests runnable verification commands',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'patch_verify_commands_',
      );
      addTearDown(() => _delete(root));
      await File(
        p.join(root.path, 'main.go'),
      ).writeAsString('package main\nfunc main() {}\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final patchSet = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Update Go file',
            edits: const [
              ProposedFileEdit(
                path: 'main.go',
                type: ProposedFileEditType.modify,
                before: 'package main\nfunc main() {}\n',
                after: 'package main\nfunc main() { println("ok") }\n',
              ),
            ],
          );

      final noConfigResult = await container
          .read(patchProposalProvider.notifier)
          .apply(patchSet.id);
      expect(noConfigResult.verificationSuggestions, isEmpty);

      await File(
        p.join(root.path, 'go.mod'),
      ).writeAsString('module example.com/app\n\ngo 1.22\n');
      await File(
        p.join(root.path, 'main.go'),
      ).writeAsString('package main\nfunc main() {}\n');
      final withGoMod = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Update Go file again',
            edits: const [
              ProposedFileEdit(
                path: 'main.go',
                type: ProposedFileEditType.modify,
                before: 'package main\nfunc main() {}\n',
                after: 'package main\nfunc main() { println("ok") }\n',
              ),
            ],
          );
      final goResult = await container
          .read(patchProposalProvider.notifier)
          .apply(withGoMod.id);
      expect(goResult.verificationSuggestions, contains('go test ./...'));
    },
  );

  test(
    'PatchProposalController filters unsafe package verification scripts',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'patch_verify_unsafe_',
      );
      addTearDown(() => _delete(root));
      await File(p.join(root.path, 'README.md')).writeAsString('old\n');
      await File(p.join(root.path, 'package.json')).writeAsString('''
{"scripts":{"test":"curl https://example.com","lint":"cat .env","build":"npm run deploy","deploy":"firebase deploy"}}
''');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final patchSet = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Update readme',
            edits: const [
              ProposedFileEdit(
                path: 'README.md',
                type: ProposedFileEditType.modify,
                before: 'old\n',
                after: 'new\n',
              ),
            ],
            verificationRequested: true,
          );

      final result = await container
          .read(patchProposalProvider.notifier)
          .apply(patchSet.id);

      expect(result.status, PatchApplyStatus.applied);
      expect(result.verificationSuggestions, [
        'Run the relevant project checks for the changed files.',
      ]);
      expect(result.verificationSuggestions, isNot(contains('npm test')));
      expect(result.verificationSuggestions, isNot(contains('npm run lint')));
      expect(result.verificationSuggestions, isNot(contains('npm run build')));
      final restoredPatch = container
          .read(patchProposalProvider)
          .history
          .firstWhere((candidate) => candidate.id == patchSet.id);
      expect(restoredPatch.verificationSuggestions, [
        'Run the relevant project checks for the changed files.',
      ]);
    },
  );

  test(
    'PatchProposalController rejects duplicate file targets before writing',
    () async {
      final root = await Directory.systemTemp.createTemp('patch_duplicate_v3_');
      addTearDown(() => _delete(root));
      final readme = File(p.join(root.path, 'README.md'));
      await readme.writeAsString('old\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final patchSet = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Duplicate target',
            edits: const [
              ProposedFileEdit(
                path: 'README.md',
                type: ProposedFileEditType.modify,
                before: 'old\n',
                after: 'first change\n',
              ),
              ProposedFileEdit(
                path: './README.md',
                type: ProposedFileEditType.modify,
                before: 'first change\n',
                after: 'second change\n',
              ),
            ],
          );

      final result = await container
          .read(patchProposalProvider.notifier)
          .apply(patchSet.id);

      expect(result.status, PatchApplyStatus.conflict);
      expect(result.conflictMessage, contains('multiple edits'));
      expect(await readme.readAsString(), 'old\n');
      expect(container.read(patchProposalProvider).checkpoints, isEmpty);
      final updatedPatch = container
          .read(patchProposalProvider)
          .history
          .firstWhere((candidate) => candidate.id == patchSet.id);
      expect(updatedPatch.applyStatus, PatchApplyStatus.conflict);
      expect(updatedPatch.changedFiles, isEmpty);
    },
  );

  test(
    'PatchProposalController rejects duplicate targets with Windows separators',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'patch_windows_dupe_v3_',
      );
      addTearDown(() => _delete(root));
      final file = File(p.join(root.path, 'lib', 'main.dart'));
      await file.parent.create(recursive: true);
      await file.writeAsString('old\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final patchSet = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Duplicate Windows-style target',
            edits: const [
              ProposedFileEdit(
                path: 'lib/main.dart',
                type: ProposedFileEditType.modify,
                before: 'old\n',
                after: 'first change\n',
              ),
              ProposedFileEdit(
                path: r'lib\main.dart',
                type: ProposedFileEditType.modify,
                before: 'old\n',
                after: 'second change\n',
              ),
            ],
          );

      final result = await container
          .read(patchProposalProvider.notifier)
          .apply(patchSet.id);

      expect(result.status, PatchApplyStatus.conflict);
      expect(result.conflictMessage, contains('multiple edits'));
      expect(await file.readAsString(), 'old\n');
      expect(File(p.join(root.path, r'lib\main.dart')).existsSync(), isFalse);
      expect(container.read(patchProposalProvider).checkpoints, isEmpty);
    },
  );

  test(
    'PatchProposalController rejects paths that traverse symlinks',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'patch_symlink_root_v3_',
      );
      final outside = await Directory.systemTemp.createTemp(
        'patch_symlink_outside_v3_',
      );
      addTearDown(() => _delete(root));
      addTearDown(() => _delete(outside));
      final outsideFile = File(p.join(outside.path, 'target.txt'));
      await outsideFile.writeAsString('outside\n');
      await Link(p.join(root.path, 'linked')).create(outside.path);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final patchSet = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Unsafe symlink edit',
            edits: const [
              ProposedFileEdit(
                path: 'linked/target.txt',
                type: ProposedFileEditType.modify,
                before: 'outside\n',
                after: 'escaped\n',
              ),
            ],
          );

      final result = await container
          .read(patchProposalProvider.notifier)
          .apply(patchSet.id);

      expect(result.status, PatchApplyStatus.conflict);
      expect(result.conflictMessage, contains('symlink'));
      expect(await outsideFile.readAsString(), 'outside\n');
      expect(container.read(patchProposalProvider).checkpoints, isEmpty);
      final updatedPatch = container
          .read(patchProposalProvider)
          .history
          .firstWhere((candidate) => candidate.id == patchSet.id);
      expect(updatedPatch.applyStatus, PatchApplyStatus.conflict);
      expect(updatedPatch.changedFiles, isEmpty);
    },
  );

  test(
    'PatchProposalController refuses checkpoint restore through symlinks',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'patch_restore_symlink_root_v3_',
      );
      final outside = await Directory.systemTemp.createTemp(
        'patch_restore_symlink_outside_v3_',
      );
      addTearDown(() => _delete(root));
      addTearDown(() => _delete(outside));
      final targetDir = Directory(p.join(root.path, 'safe'));
      await targetDir.create();
      final targetFile = File(p.join(targetDir.path, 'target.txt'));
      await targetFile.writeAsString('old\n');
      final outsideFile = File(p.join(outside.path, 'target.txt'));
      await outsideFile.writeAsString('outside\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final patchSet = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Safe edit',
            edits: const [
              ProposedFileEdit(
                path: 'safe/target.txt',
                type: ProposedFileEditType.modify,
                before: 'old\n',
                after: 'new\n',
              ),
            ],
          );
      final applyResult = await container
          .read(patchProposalProvider.notifier)
          .apply(patchSet.id);
      expect(applyResult.status, PatchApplyStatus.applied);
      expect(applyResult.checkpointId, isNotNull);

      await targetDir.delete(recursive: true);
      await Link(p.join(root.path, 'safe')).create(outside.path);

      final restoreResult = await container
          .read(patchProposalProvider.notifier)
          .restoreCheckpoint(applyResult.checkpointId!);

      expect(restoreResult.status, PatchApplyStatus.failed);
      expect(restoreResult.message, contains('symlink'));
      expect(await outsideFile.readAsString(), 'outside\n');
    },
  );

  test(
    'PatchProposalController preflights checkpoint restore before mutating files',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'patch_restore_preflight_v3_',
      );
      addTearDown(() => _delete(root));
      final first = File(p.join(root.path, 'first.txt'));
      final second = File(p.join(root.path, 'second.txt'));
      await first.writeAsString('first old\n');
      await second.writeAsString('second old\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final patchSet = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Update two files',
            edits: const [
              ProposedFileEdit(
                path: 'first.txt',
                type: ProposedFileEditType.modify,
                before: 'first old\n',
                after: 'first new\n',
              ),
              ProposedFileEdit(
                path: 'second.txt',
                type: ProposedFileEditType.modify,
                before: 'second old\n',
                after: 'second new\n',
              ),
            ],
          );
      final applyResult = await container
          .read(patchProposalProvider.notifier)
          .apply(patchSet.id);
      expect(applyResult.status, PatchApplyStatus.applied);
      expect(applyResult.checkpointId, isNotNull);
      expect(await first.readAsString(), 'first new\n');
      expect(await second.readAsString(), 'second new\n');

      await second.delete();
      await Directory(second.path).create();

      final restoreResult = await container
          .read(patchProposalProvider.notifier)
          .restoreCheckpoint(applyResult.checkpointId!);

      expect(restoreResult.status, PatchApplyStatus.failed);
      expect(restoreResult.message, contains('second.txt'));
      expect(restoreResult.message, contains('directory'));
      expect(await first.readAsString(), 'first new\n');
      expect(await Directory(second.path).exists(), isTrue);
      final restoredPatch = container
          .read(patchProposalProvider)
          .history
          .firstWhere((candidate) => candidate.id == patchSet.id);
      expect(restoredPatch.applyStatus, PatchApplyStatus.applied);
    },
  );

  test(
    'Checkpoint restore previews later user changes and creates a reversible checkpoint',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'patch_restore_preview_v3_',
      );
      addTearDown(() => _delete(root));
      final readme = File(p.join(root.path, 'README.md'));
      await readme.writeAsString('before patch\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      final patch = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Update readme',
            workItemId: 'task-checkpoint-preview',
            verificationRequested: true,
            edits: const [
              ProposedFileEdit(
                path: 'README.md',
                type: ProposedFileEditType.modify,
                before: 'before patch\n',
                after: 'after patch\n',
              ),
            ],
          );
      final applied = await container
          .read(patchProposalProvider.notifier)
          .apply(patch.id);
      expect(applied.status, PatchApplyStatus.applied);
      await readme.writeAsString('later user change\n');

      final preview = await container
          .read(patchProposalProvider.notifier)
          .previewCheckpointRestore(applied.checkpointId!);
      expect(preview, isNotNull);
      expect(preview!.hasLaterUserChanges, isTrue);
      expect(preview.files.single.path, 'README.md');
      expect(
        preview.files.single.state,
        CheckpointRestoreFileState.laterUserChange,
      );
      expect(preview.verificationStatus, 'Verification requested');

      final denied = await container
          .read(patchProposalProvider.notifier)
          .restoreCheckpoint(applied.checkpointId!);
      expect(denied.status, PatchApplyStatus.conflict);
      expect(denied.conflictMessage, contains('changed after the patch'));
      expect(await readme.readAsString(), 'later user change\n');

      final restored = await container
          .read(patchProposalProvider.notifier)
          .restoreCheckpoint(applied.checkpointId!, allowOverwrite: true);
      expect(restored.status, PatchApplyStatus.restored);
      expect(await readme.readAsString(), 'before patch\n');
      final rollback = container
          .read(patchProposalProvider)
          .checkpoints
          .values
          .singleWhere(
            (checkpoint) =>
                checkpoint.restoresCheckpointId == applied.checkpointId,
          );
      expect(rollback.patchSetId, patch.id);
      expect(rollback.workItemId, 'task-checkpoint-preview');

      final reversed = await container
          .read(patchProposalProvider.notifier)
          .restoreCheckpoint(rollback.id);
      expect(reversed.status, PatchApplyStatus.restored);
      expect(await readme.readAsString(), 'later user change\n');
    },
  );

  test(
    'Checkpoint restore journal recovers a forced interruption without changing patch history',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'patch_restore_crash_v3_',
      );
      final storeRoot = await Directory.systemTemp.createTemp(
        'patch_restore_crash_store_v3_',
      );
      addTearDown(() => _delete(root));
      addTearDown(() => _delete(storeRoot));
      final file = File(p.join(root.path, 'README.md'));
      await file.writeAsString('before\n');
      final normalStore = PatchProposalStore(baseDir: storeRoot.path);

      final applyingContainer = ProviderContainer(
        overrides: [patchProposalStoreProvider.overrideWithValue(normalStore)],
      );
      await applyingContainer
          .read(fileTreeProvider.notifier)
          .openDirectory(root.path);
      final patch = applyingContainer
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Crash-safe restore',
            edits: const [
              ProposedFileEdit(
                path: 'README.md',
                type: ProposedFileEditType.modify,
                before: 'before\n',
                after: 'after\n',
              ),
            ],
          );
      final applied = await applyingContainer
          .read(patchProposalProvider.notifier)
          .apply(patch.id);
      expect(applied.status, PatchApplyStatus.applied);
      applyingContainer.dispose();

      final interruptedStore = PatchProposalStore(
        baseDir: storeRoot.path,
        onMutationApplied: (completed) {
          if (completed == 1) throw const PatchApplySimulatedCrash();
        },
      );
      final interruptedContainer = ProviderContainer(
        overrides: [
          patchProposalStoreProvider.overrideWithValue(interruptedStore),
        ],
      );
      await interruptedContainer
          .read(fileTreeProvider.notifier)
          .openDirectory(root.path);
      interruptedContainer.read(patchProposalProvider);
      await _waitForPatchProvider(
        interruptedContainer,
        (state) => state.checkpoints.containsKey(applied.checkpointId),
      );

      final interrupted = await interruptedContainer
          .read(patchProposalProvider.notifier)
          .restoreCheckpoint(applied.checkpointId!);
      expect(interrupted.status, PatchApplyStatus.failed);
      expect(await file.readAsString(), 'before\n');
      expect(
        await File(normalStore.applyJournalPath(root.path)).exists(),
        isTrue,
      );
      interruptedContainer.dispose();

      final recoveryContainer = ProviderContainer(
        overrides: [patchProposalStoreProvider.overrideWithValue(normalStore)],
      );
      addTearDown(recoveryContainer.dispose);
      await recoveryContainer
          .read(fileTreeProvider.notifier)
          .openDirectory(root.path);
      recoveryContainer.read(patchProposalProvider);
      await _waitForPatchProvider(
        recoveryContainer,
        (state) =>
            state.message?.contains('interrupted checkpoint restore') ?? false,
      );

      expect(await file.readAsString(), 'after\n');
      expect(
        await File(normalStore.applyJournalPath(root.path)).exists(),
        isFalse,
      );
      final recoveredPatch = recoveryContainer
          .read(patchProposalProvider)
          .history
          .firstWhere((candidate) => candidate.id == patch.id);
      expect(recoveredPatch.applyStatus, PatchApplyStatus.applied);
      expect(recoveredPatch.checkpointId, applied.checkpointId);
    },
  );

  test(
    'PatchProposalController rejects empty and workspace-root patch targets',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'patch_bad_target_v3_',
      );
      addTearDown(() => _delete(root));
      final marker = File(p.join(root.path, 'marker.txt'));
      await marker.writeAsString('unchanged\n');

      Future<PatchApplyResult> applySingle(String path) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container
            .read(fileTreeProvider.notifier)
            .openDirectory(root.path);
        final patchSet = container
            .read(patchProposalProvider.notifier)
            .propose(
              title: 'Bad target',
              edits: [
                ProposedFileEdit(
                  path: path,
                  type: ProposedFileEditType.create,
                  after: 'bad\n',
                ),
              ],
            );
        final result = await container
            .read(patchProposalProvider.notifier)
            .apply(patchSet.id);
        expect(container.read(patchProposalProvider).checkpoints, isEmpty);
        return result;
      }

      final blankResult = await applySingle('   ');
      expect(blankResult.status, PatchApplyStatus.conflict);
      expect(blankResult.conflictMessage, contains('outside the workspace'));
      expect(await marker.readAsString(), 'unchanged\n');

      final dotResult = await applySingle('.');
      expect(dotResult.status, PatchApplyStatus.conflict);
      expect(dotResult.conflictMessage, contains('outside the workspace'));
      expect(await marker.readAsString(), 'unchanged\n');
    },
  );

  test(
    'PatchProposalController rejects control characters in patch targets',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'patch_control_target_v3_',
      );
      addTearDown(() => _delete(root));
      final marker = File(p.join(root.path, 'marker.txt'));
      await marker.writeAsString('unchanged\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final patchSet = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Bad control target',
            edits: const [
              ProposedFileEdit(
                path: 'lib/bad\nname.dart',
                type: ProposedFileEditType.create,
                after: 'bad\n',
              ),
            ],
          );

      final result = await container
          .read(patchProposalProvider.notifier)
          .apply(patchSet.id);

      expect(result.status, PatchApplyStatus.conflict);
      expect(result.conflictMessage, contains('control characters'));
      expect(await marker.readAsString(), 'unchanged\n');
      expect(await File(p.join(root.path, 'lib')).exists(), isFalse);
      expect(container.read(patchProposalProvider).checkpoints, isEmpty);
    },
  );

  test(
    'PatchProposalController rejects directory targets before writing',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'patch_directory_target_v3_',
      );
      addTearDown(() => _delete(root));
      await Directory(p.join(root.path, 'docs')).create();
      final marker = File(p.join(root.path, 'marker.txt'));
      await marker.writeAsString('unchanged\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final patchSet = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Directory target',
            edits: const [
              ProposedFileEdit(
                path: 'docs',
                type: ProposedFileEditType.modify,
                before: 'old\n',
                after: 'new\n',
              ),
            ],
          );

      final result = await container
          .read(patchProposalProvider.notifier)
          .apply(patchSet.id);

      expect(result.status, PatchApplyStatus.conflict);
      expect(result.conflictMessage, contains('target is a directory'));
      expect(await marker.readAsString(), 'unchanged\n');
      expect(container.read(patchProposalProvider).checkpoints, isEmpty);
    },
  );

  test(
    'PatchProposalController rejects non-directory parents before writing',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'patch_non_directory_parent_v3_',
      );
      addTearDown(() => _delete(root));
      final parent = File(p.join(root.path, 'parent'));
      await parent.writeAsString('not a directory\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final patchSet = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Non-directory parent',
            edits: const [
              ProposedFileEdit(
                path: 'parent/child.txt',
                type: ProposedFileEditType.create,
                after: 'child\n',
              ),
            ],
          );

      final result = await container
          .read(patchProposalProvider.notifier)
          .apply(patchSet.id);

      expect(result.status, PatchApplyStatus.conflict);
      expect(
        result.conflictMessage,
        contains('parent path is not a directory'),
      );
      expect(await parent.readAsString(), 'not a directory\n');
      expect(
        await File(p.join(root.path, 'parent', 'child.txt')).exists(),
        isFalse,
      );
      expect(container.read(patchProposalProvider).checkpoints, isEmpty);
    },
  );

  test(
    'PatchProposalController rejects obstructing ancestor paths before writing',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'patch_obstructing_ancestor_v3_',
      );
      addTearDown(() => _delete(root));
      final blocker = File(p.join(root.path, 'lib'));
      await blocker.writeAsString('not a directory\n');
      final marker = File(p.join(root.path, 'marker.txt'));
      await marker.writeAsString('unchanged\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final patchSet = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Obstructed nested create',
            edits: const [
              ProposedFileEdit(
                path: 'lib/generated/file.dart',
                type: ProposedFileEditType.create,
                after: 'const generated = true;\n',
              ),
            ],
          );

      final result = await container
          .read(patchProposalProvider.notifier)
          .apply(patchSet.id);

      expect(result.status, PatchApplyStatus.conflict);
      expect(
        result.conflictMessage,
        contains('parent path is not a directory'),
      );
      expect(result.conflictMessage, contains('lib'));
      expect(await blocker.readAsString(), 'not a directory\n');
      expect(await marker.readAsString(), 'unchanged\n');
      expect(
        await File(p.join(root.path, 'lib', 'generated', 'file.dart')).exists(),
        isFalse,
      );
      expect(container.read(patchProposalProvider).checkpoints, isEmpty);
    },
  );

  test('PatchProposalController rejects no-op modify patches', () async {
    final root = await Directory.systemTemp.createTemp('patch_noop_v3_');
    addTearDown(() => _delete(root));
    final readme = File(p.join(root.path, 'README.md'));
    await readme.writeAsString('same\n');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(fileTreeProvider.notifier).openDirectory(root.path);
    container.read(patchProposalProvider);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final patchSet = container
        .read(patchProposalProvider.notifier)
        .propose(
          title: 'No-op modify',
          edits: const [
            ProposedFileEdit(
              path: 'README.md',
              type: ProposedFileEditType.modify,
              before: 'same\n',
              after: 'same\n',
            ),
          ],
        );

    final result = await container
        .read(patchProposalProvider.notifier)
        .apply(patchSet.id);

    expect(result.status, PatchApplyStatus.conflict);
    expect(result.conflictMessage, contains('does not change'));
    expect(await readme.readAsString(), 'same\n');
    expect(container.read(patchProposalProvider).checkpoints, isEmpty);
    final updatedPatch = container.read(patchProposalProvider).active!;
    expect(updatedPatch.id, patchSet.id);
    expect(updatedPatch.applyStatus, PatchApplyStatus.conflict);
    expect(updatedPatch.changedFiles, isEmpty);
  });

  test('PatchProposalController rejects empty create patches', () async {
    final root = await Directory.systemTemp.createTemp(
      'patch_empty_create_v3_',
    );
    addTearDown(() => _delete(root));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(fileTreeProvider.notifier).openDirectory(root.path);

    final patchSet = container
        .read(patchProposalProvider.notifier)
        .propose(
          title: 'Empty create',
          edits: const [
            ProposedFileEdit(
              path: 'lib/generated.dart',
              type: ProposedFileEditType.create,
              after: '',
            ),
          ],
        );

    final result = await container
        .read(patchProposalProvider.notifier)
        .apply(patchSet.id);

    expect(result.status, PatchApplyStatus.conflict);
    expect(result.conflictMessage, contains('leaves lib/generated.dart empty'));
    expect(File(p.join(root.path, 'lib/generated.dart')).existsSync(), isFalse);
    expect(container.read(patchProposalProvider).checkpoints, isEmpty);
    final updatedPatch = container.read(patchProposalProvider).active!;
    expect(updatedPatch.id, patchSet.id);
    expect(updatedPatch.applyStatus, PatchApplyStatus.conflict);
    expect(updatedPatch.changedFiles, isEmpty);
  });

  test(
    'PatchProposalController rejects binary or non-UTF8 patch targets clearly',
    () async {
      final root = await Directory.systemTemp.createTemp('patch_binary_v3_');
      addTearDown(() => _delete(root));
      final asset = File(p.join(root.path, 'asset.bin'));
      await asset.writeAsBytes([0xff, 0xfe, 0xfd]);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final patchSet = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Unsafe binary edit',
            edits: const [
              ProposedFileEdit(
                path: 'asset.bin',
                type: ProposedFileEditType.modify,
                before: 'old text\n',
                after: 'new text\n',
              ),
            ],
          );

      final result = await container
          .read(patchProposalProvider.notifier)
          .apply(patchSet.id);

      expect(result.status, PatchApplyStatus.conflict);
      expect(result.conflictMessage, contains('not readable as UTF-8 text'));
      expect(result.conflictMessage, contains('asset.bin'));
      expect(await asset.readAsBytes(), [0xff, 0xfe, 0xfd]);
      expect(container.read(patchProposalProvider).checkpoints, isEmpty);
    },
  );

  test(
    'PatchProposalController rejects create modify delete existence mismatches',
    () async {
      final root = await Directory.systemTemp.createTemp('patch_existence_v3_');
      addTearDown(() => _delete(root));
      final existing = File(p.join(root.path, 'existing.txt'));
      await existing.writeAsString('keep me\n');

      Future<PatchApplyResult> applySingle(ProposedFileEdit edit) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container
            .read(fileTreeProvider.notifier)
            .openDirectory(root.path);
        final patchSet = container
            .read(patchProposalProvider.notifier)
            .propose(title: 'Unsafe edit', edits: [edit]);
        return container
            .read(patchProposalProvider.notifier)
            .apply(patchSet.id);
      }

      final createResult = await applySingle(
        const ProposedFileEdit(
          path: 'existing.txt',
          type: ProposedFileEditType.create,
          after: 'overwrite\n',
        ),
      );
      expect(createResult.status, PatchApplyStatus.conflict);
      expect(createResult.conflictMessage, contains('already exists'));
      expect(await existing.readAsString(), 'keep me\n');

      final modifyResult = await applySingle(
        const ProposedFileEdit(
          path: 'missing.txt',
          type: ProposedFileEditType.modify,
          after: 'new\n',
        ),
      );
      expect(modifyResult.status, PatchApplyStatus.conflict);
      expect(modifyResult.conflictMessage, contains('missing for modify'));
      expect(await File(p.join(root.path, 'missing.txt')).exists(), isFalse);

      final deleteResult = await applySingle(
        const ProposedFileEdit(
          path: 'also-missing.txt',
          type: ProposedFileEditType.delete,
        ),
      );
      expect(deleteResult.status, PatchApplyStatus.conflict);
      expect(deleteResult.conflictMessage, contains('missing for delete'));
    },
  );

  test(
    'PatchProposalController rejects diff-only edits without writing empty files',
    () async {
      final root = await Directory.systemTemp.createTemp('patch_diff_only_v3_');
      addTearDown(() => _delete(root));
      final readme = File(p.join(root.path, 'README.md'));
      await readme.writeAsString('old\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final patchSet = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Diff-only patch',
            edits: const [
              ProposedFileEdit(
                path: 'README.md',
                type: ProposedFileEditType.modify,
                before: 'old\n',
                unifiedDiff: '-old\n+new\n',
              ),
            ],
          );

      final result = await container
          .read(patchProposalProvider.notifier)
          .apply(patchSet.id);

      expect(result.status, PatchApplyStatus.conflict);
      expect(result.conflictMessage, contains('missing full target content'));
      expect(await readme.readAsString(), 'old\n');
      expect(container.read(patchProposalProvider).checkpoints, isEmpty);
      final updatedPatch = container
          .read(patchProposalProvider)
          .history
          .firstWhere((candidate) => candidate.id == patchSet.id);
      expect(updatedPatch.applyStatus, PatchApplyStatus.conflict);
      expect(updatedPatch.changedFiles, isEmpty);
    },
  );

  test(
    'PatchProposalController normalizes workspace absolute paths to relative paths',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'patch_absolute_paths_v3_',
      );
      addTearDown(() => _delete(root));
      final readme = File(p.join(root.path, 'README.md'));
      await readme.writeAsString('old\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final patchSet = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Absolute path patch',
            plannedFiles: [p.join(root.path, 'lib', 'new.dart')],
            edits: [
              ProposedFileEdit(
                path: p.join(root.path, 'README.md'),
                type: ProposedFileEditType.modify,
                before: 'old\n',
                after: 'new\n',
              ),
            ],
          );

      expect(patchSet.edits.single.path, 'README.md');
      expect(patchSet.plannedFiles, ['lib/new.dart']);

      final result = await container
          .read(patchProposalProvider.notifier)
          .apply(patchSet.id);

      expect(result.status, PatchApplyStatus.applied);
      expect(result.changedFiles, ['README.md']);
      expect(result.diffSummary, contains('Modified README.md'));
      expect(await readme.readAsString(), 'new\n');
    },
  );

  test(
    'PatchProposalController requires prior content for modify and delete',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'patch_missing_before_v3_',
      );
      addTearDown(() => _delete(root));
      final readme = File(p.join(root.path, 'README.md'));
      final obsolete = File(p.join(root.path, 'obsolete.txt'));
      await readme.writeAsString('old\n');
      await obsolete.writeAsString('remove me\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final patchSet = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Unsafe stale-blind patch',
            edits: const [
              ProposedFileEdit(
                path: 'README.md',
                type: ProposedFileEditType.modify,
                after: 'new\n',
              ),
              ProposedFileEdit(
                path: 'obsolete.txt',
                type: ProposedFileEditType.delete,
              ),
            ],
          );

      final result = await container
          .read(patchProposalProvider.notifier)
          .apply(patchSet.id);

      expect(result.status, PatchApplyStatus.conflict);
      expect(
        result.conflictMessage,
        contains('missing expected prior content'),
      );
      expect(await readme.readAsString(), 'old\n');
      expect(await obsolete.readAsString(), 'remove me\n');
      expect(container.read(patchProposalProvider).checkpoints, isEmpty);
      final updatedPatch = container
          .read(patchProposalProvider)
          .history
          .firstWhere((candidate) => candidate.id == patchSet.id);
      expect(updatedPatch.applyStatus, PatchApplyStatus.conflict);
      expect(updatedPatch.changedFiles, isEmpty);
    },
  );

  test('WorkItemStore persists project-scoped history', () async {
    final root = await Directory.systemTemp.createTemp('work_store_v3_');
    final storeRoot = await Directory.systemTemp.createTemp('work_config_v3_');
    addTearDown(() => _delete(root));
    addTearDown(() => _delete(storeRoot));
    final store = WorkItemStore(baseDir: storeRoot.path);
    final item = WorkItem(
      id: 'work-1',
      prompt: 'Improve vibe coding',
      status: WorkItemStatus.ready,
      contextPreview: const ['Flutter app'],
      artifacts: [
        WorkItemArtifact(
          id: 'ctx',
          type: WorkItemArtifactType.context,
          title: 'Context pack',
          detail: '1 item',
          createdAt: DateTime(2026),
        ),
      ],
      createdAt: DateTime(2026),
    );

    await store.save(root.path, [item]);
    final loaded = await store.load(root.path);

    expect(loaded.single.prompt, 'Improve vibe coding');
    expect(loaded.single.contextPreview, ['Flutter app']);
    expect(loaded.single.artifacts.single.type, WorkItemArtifactType.context);
  });

  test('WorkItemStore preserves more than thirty history items', () async {
    final root = await Directory.systemTemp.createTemp('work_store_v3_');
    final storeRoot = await Directory.systemTemp.createTemp('work_config_v3_');
    addTearDown(() => _delete(root));
    addTearDown(() => _delete(storeRoot));
    final store = WorkItemStore(baseDir: storeRoot.path);
    final now = DateTime(2026);
    final items = [
      for (var index = 0; index < 35; index++)
        WorkItem(
          id: 'work-$index',
          prompt: 'Task $index',
          status: WorkItemStatus.ready,
          createdAt: now.add(Duration(minutes: index)),
        ),
    ];

    await store.save(root.path, items);

    final loaded = await store.load(root.path);

    expect(loaded, hasLength(35));
    expect(loaded.map((item) => item.id), contains('work-0'));
    expect(loaded.map((item) => item.id), contains('work-34'));
  });

  test('WorkItem execution does not bypass Studio turn runtime', () async {
    final container = ProviderContainer(
      overrides: [
        workItemHistoryProvider.overrideWith(
          _FakeWorkItemHistoryController.new,
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(workItemProvider.notifier).start('Fix login safely');
    await container.read(workItemProvider.notifier).sendToChat();

    final item = container.read(workItemProvider)!;
    expect(item.status, WorkItemStatus.failed);
    expect(item.result, contains('request-local turn runtime'));
    expect(item.steps[1].error, contains('Legacy global chat execution'));
    expect(container.read(chatProvider).messages, isEmpty);
  });

  test('Spec execution does not use the legacy blocking agent loop', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(specProvider.notifier)
        .loadForTesting(
          Spec(
            id: 'spec-1',
            name: 'Spec',
            status: SpecStatus.ready,
            createdAt: DateTime(2026),
            steps: const [
              SpecStep(
                id: 'step-1',
                description: 'Implement auth fix',
                executionPrompt: 'Fix auth',
                order: 0,
              ),
            ],
          ),
        );

    await container.read(specProvider.notifier).execute();

    final spec = container.read(specProvider)!;
    expect(spec.status, SpecStatus.failed);
    expect(spec.steps.single.error, contains('request-local turn runtime'));
    expect(container.read(chatProvider).messages, isEmpty);
  });

  test(
    'Studio-adjacent providers do not call legacy blocking sendMessage',
    () async {
      final files = [
        'lib/state/work_item_provider.dart',
        'lib/state/spec_provider.dart',
        'lib/state/vericoding_provider.dart',
      ];

      for (final path in files) {
        final source = await File(path).readAsString();
        expect(
          source,
          isNot(contains('sendMessage(')),
          reason: '$path must not bypass AgentTurnRuntime.',
        );
      }
    },
  );

  test('Studio runtime surface stays free of legacy global chat state', () async {
    final files = <File>[
      ...Directory('lib/ui/studio')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      ...Directory('lib/state').listSync().whereType<File>().where(
        (file) =>
            p.basename(file.path).startsWith('studio_') &&
            file.path.endsWith('.dart'),
      ),
      File('lib/state/agent_turn_runtime_provider.dart'),
      File('lib/state/workspace_session_provider.dart'),
      File('lib/state/command_run_provider.dart'),
      File('lib/state/memories_provider.dart'),
    ];

    const legacyMarkers = {
      'chatProvider',
      'agentServiceProvider',
      'pendingConfirmation',
      'CircuitAgent',
    };

    for (final file in files) {
      final source = await file.readAsString();
      for (final marker in legacyMarkers) {
        expect(
          source,
          isNot(contains(marker)),
          reason:
              '${file.path} must stay request-local and must not read legacy global chat/runtime state.',
        );
      }
    }
  });

  test('Studio-adjacent project shortcuts do not use legacy chat', () async {
    final source = await File(
      'lib/ui/project/project_cockpit_panel.dart',
    ).readAsString();

    expect(source, isNot(contains('chatProvider')));
    expect(source, isNot(contains('agentServiceProvider')));
    expect(source, contains('sendStudioMessage('));
  });

  test('Studio command registry does not call legacy chat runtime', () async {
    final source = await File(
      'lib/core/commands/core_command_registry.dart',
    ).readAsString();

    expect(source, isNot(contains('chatProvider')));
    expect(source, isNot(contains('agentServiceProvider')));
    expect(source, isNot(contains('connectWithSavedCredentials')));
    expect(source, isNot(contains('sendMessage(')));
    expect(source, isNot(contains('project.explain')));
    expect(source, isNot(contains('project.summarizeChanges')));
    expect(source, isNot(contains('ai.reconnect')));
    expect(source, contains("'context.toggleActiveFile'"));
    expect(source, contains("'context.toggleTerminal'"));
    expect(source, contains("'context.toggleGitDiff'"));
  });

  test(
    'Studio turn runtime does not load legacy global agent config',
    () async {
      final source = await File(
        'lib/state/agent_turn_runtime_provider.dart',
      ).readAsString();

      expect(source, isNot(contains('AgentConfig.load')));
      expect(source, isNot(contains('loadSystemPrompt')));
    },
  );

  test(
    'Studio turn runtime does not use legacy AgentService runtime state',
    () async {
      final source = await File(
        'lib/state/agent_turn_runtime_provider.dart',
      ).readAsString();

      expect(source, isNot(contains('agentServiceProvider')));
      expect(source, isNot(contains('chatProvider')));
      expect(source, isNot(contains('CircuitAgent')));
      expect(source, isNot(contains('sendMessage(')));
      expect(source, isNot(contains('service.state.workingDir')));
      expect(source, isNot(contains('service.state.model')));
      expect(source, contains('studioAgentConnectionProvider'));
      expect(source, contains('workspaceContextProvider'));
      expect(source, contains('settings.ciscoModel'));
    },
  );

  test('Studio screen auto-connect does not use legacy AgentService', () async {
    final source = await File('lib/ui/screens/ide_screen.dart').readAsString();

    expect(source, isNot(contains('agentServiceProvider')));
    expect(source, isNot(contains('AgentService')));
    expect(source, isNot(contains('connectWithSavedCredentials')));
    expect(source, isNot(contains('service.connect(')));
    expect(source, contains('studioAgentConnectionProvider'));
  });

  test(
    'Studio connection facade owns provider without reading AgentService',
    () async {
      final source = await File(
        'lib/state/studio_provider_connection.dart',
      ).readAsString();
      final start = source.indexOf('class StudioAgentConnectionController');
      final studioConnectionSource = source.substring(start);

      expect(studioConnectionSource, contains('ProviderRegistry'));
      expect(studioConnectionSource, contains('provider.connect'));
      expect(studioConnectionSource, isNot(contains('agentServiceProvider')));
      expect(studioConnectionSource, isNot(contains('AgentService')));
      expect(studioConnectionSource, isNot(contains('CircuitAgent')));
    },
  );

  test(
    'Studio workspace session does not bind through legacy AgentService',
    () async {
      final source = await File(
        'lib/state/workspace_session_provider.dart',
      ).readAsString();

      expect(source, isNot(contains('agentServiceProvider')));
      expect(source, isNot(contains('updateWorkingDir(')));
      expect(source, contains('fileTreeProvider'));
      expect(source, contains('WorkspaceSessionStatus.ready'));
    },
  );

  test(
    'Studio request lifecycle only listens to runtime-scoped events',
    () async {
      final source = await File(
        'lib/state/studio_request_lifecycle_provider.dart',
      ).readAsString();

      expect(source, isNot(contains('agentServiceProvider')));
      expect(source, isNot(contains('studioLegacyAgentEventBridgeProvider')));
      expect(source, isNot(contains('connection_provider.dart')));
      expect(source, isNot(contains('streamingContent')));
      expect(source, contains('attachRuntimeEvents'));
      expect(source, contains('_runtimeEventBindings'));
      expect(source, contains('appendAssistantDelta'));
    },
  );

  test(
    'Studio command run controller only listens to runtime-scoped events',
    () async {
      final source = await File(
        'lib/state/command_run_provider.dart',
      ).readAsString();

      expect(source, isNot(contains('agentServiceProvider')));
      expect(source, isNot(contains('legacyCommandRunEventBridgeProvider')));
      expect(source, isNot(contains('connection_provider.dart')));
      expect(source, isNot(contains('cancelActiveCommands(')));
      expect(source, contains('attachRuntimeEvents'));
      expect(source, contains('_runtimeEventBindings'));
    },
  );

  test('Studio token usage display does not read legacy chat state', () async {
    final composerSource = await File(
      'lib/ui/studio/studio_prompt_composer.dart',
    ).readAsString();
    final tokenSource = await File(
      'lib/state/studio_token_usage_provider.dart',
    ).readAsString();

    expect(composerSource, isNot(contains('chatProvider')));
    expect(composerSource, isNot(contains('tokenUsageProvider')));
    expect(composerSource, isNot(contains('lastTokenUsageProvider')));
    expect(composerSource, isNot(contains('costInfoProvider')));
    expect(composerSource, isNot(contains('token_provider.dart')));
    expect(composerSource, contains('studioTokenUsageForTaskViewProvider'));

    expect(tokenSource, isNot(contains('chatProvider')));
    expect(tokenSource, isNot(contains('token_provider.dart')));
    expect(tokenSource, contains('studioThreadProvider'));
  });

  test(
    'Studio task title does not fall back to unrelated selected thread',
    () async {
      // The shell composes the feature modules; task-scoped title selection
      // belongs to the persistent top-bar module after the Studio split.
      final source = await File(
        'lib/ui/studio/studio_top_bar.dart',
      ).readAsString();

      expect(
        source,
        contains('threadState.threadForTaskView(studio.selectedTaskId);'),
      );
      expect(
        source,
        isNot(
          contains('threadState.threadForTaskView(studio.selectedTaskId) ??'),
        ),
        reason:
            'A missing task-scoped thread should show the neutral task title instead of leaking another selected thread.',
      );
    },
  );

  test(
    'legacy chat token state is explicitly quarantined outside Studio',
    () async {
      final legacyTokenSource = await File(
        'lib/state/legacy_chat_token_provider.dart',
      ).readAsString();
      final tokenTrackerSource = await File(
        'lib/ui/chat/token_tracker.dart',
      ).readAsString();

      expect(legacyTokenSource, contains('legacyChatTokenUsageProvider'));
      expect(legacyTokenSource, contains('chatProvider'));
      expect(legacyTokenSource, contains('Legacy Advanced Editor token state'));
      expect(tokenTrackerSource, contains('legacyChatTokenUsageProvider'));
      expect(tokenTrackerSource, contains('legacy_chat_token_provider.dart'));
      expect(File('lib/state/token_provider.dart').existsSync(), isFalse);
    },
  );

  test('Studio context memory extraction avoids legacy AgentService', () async {
    final source = await File(
      'lib/state/memories_provider.dart',
    ).readAsString();

    expect(source, isNot(contains('agentServiceProvider')));
    expect(source, isNot(contains('sendOneShot(')));
    expect(source, contains('studioAgentConnectionProvider'));
    expect(source, contains('provider.chat('));
  });

  test('Studio UI files do not import legacy chat runtime providers', () async {
    final studioFiles = await Directory('lib/ui/studio')
        .list(recursive: true)
        .where((entity) => entity is File && entity.path.endsWith('.dart'))
        .cast<File>()
        .toList();

    expect(studioFiles, isNotEmpty);
    for (final file in studioFiles) {
      final source = await file.readAsString();
      final importBlock = source
          .split('\n')
          .where((line) => line.trimLeft().startsWith('import '))
          .join('\n');
      expect(
        importBlock,
        isNot(contains('chat_provider.dart')),
        reason: '${file.path} must render from Studio turns, not ChatNotifier.',
      );
      expect(
        importBlock,
        isNot(contains('token_provider.dart')),
        reason: '${file.path} must use Studio token providers.',
      );
      expect(
        importBlock,
        isNot(contains('connection_provider.dart')),
        reason:
            '${file.path} must not reach AgentService/CircuitAgent through legacy connection providers.',
      );
    }
  });

  test('Git commit message helper uses stateless generation', () async {
    final source = await File('lib/ui/git/git_panel.dart').readAsString();

    expect(source, contains('sendOneShot('));
    expect(source, isNot(contains('sendMessage(')));
  });

  test(
    'Custom agents enter only through Studio while legacy agents stay quarantined',
    () async {
      final managerSource = await File(
        'lib/state/agent_manager_provider.dart',
      ).readAsString();
      expect(
        managerSource,
        contains('Custom agents run only from the Studio composer'),
      );
      expect(managerSource, isNot(contains('CircuitAgent')));
      expect(managerSource, isNot(contains('agentServiceProvider')));
      expect(managerSource, isNot(contains('autoApprove')));
      expect(
        await File('lib/agent/tools/orchestrate_tool.dart').exists(),
        isFalse,
        reason:
            'The legacy full-access subagent tool must not remain available outside a scoped Studio delegation runtime.',
      );
      for (final path in [
        'lib/agent/tools/tool_registry.dart',
        'lib/agent/tools/tool_executor.dart',
        'lib/agent/agent.dart',
        'lib/services/agent_service.dart',
      ]) {
        final source = await File(path).readAsString();
        expect(
          source,
          isNot(contains('orchestrate')),
          reason: '$path must not retain the legacy subagent route.',
        );
      }

      final sources = {
        'lib/state/ghost_mode_provider.dart': '_ghostModeEnabled => false',
        'lib/state/background_agent_provider.dart':
            '_backgroundAgentsEnabled => false',
      };

      for (final entry in sources.entries) {
        final source = await File(entry.key).readAsString();
        expect(source, contains(entry.value), reason: entry.key);
        expect(
          source,
          contains('request-local turn runtime'),
          reason: '${entry.key} should explain why execution is paused.',
        );
      }

      final ghostSource = await File(
        'lib/state/ghost_mode_provider.dart',
      ).readAsString();
      final statusBarSource = await File(
        'lib/ui/layout/status_bar.dart',
      ).readAsString();
      expect(
        statusBarSource,
        contains('StudioFeatureFlags.advancedStudioSurfaces'),
        reason:
            'Ghost status UI must stay hidden from the stable Studio chrome until Ghost Mode is migrated to the turn runtime.',
      );
      expect(
        statusBarSource.indexOf('StudioFeatureFlags.advancedStudioSurfaces'),
        lessThan(statusBarSource.indexOf('GhostStatusWidget')),
        reason:
            'Ghost status UI should be mounted only behind the advanced Studio surface flag.',
      );
      final startGhostSource = _methodBody(
        ghostSource,
        'Future<void> startGhost',
        'Future<void> undoGhost',
      );
      expect(
        startGhostSource.indexOf('if (!_ghostModeEnabled)'),
        lessThan(startGhostSource.indexOf('ref.read(agentServiceProvider)')),
        reason:
            'Ghost Mode must fail closed before touching legacy AgentService.',
      );
      final undoGhostSource = _methodBody(
        ghostSource,
        'Future<void> undoGhost',
        'void dismissTask',
      );
      expect(
        undoGhostSource.indexOf('if (!_ghostModeEnabled)'),
        lessThan(undoGhostSource.indexOf('ref.read(agentServiceProvider)')),
        reason:
            'Ghost undo must stay quarantined while Ghost Mode is disabled.',
      );

      final backgroundSource = await File(
        'lib/state/background_agent_provider.dart',
      ).readAsString();
      for (final marker in [
        'void _setupListeners',
        'void _handleFileSaveTrigger',
        'void handleGitCommitTrigger',
        'void handleProjectOpenTrigger',
        'void _handlePeriodicTriggers',
      ]) {
        final methodSource = _methodBody(
          backgroundSource,
          marker,
          marker == 'void _handlePeriodicTriggers'
              ? 'bool _checkCooldown'
              : _nextBackgroundMarker(marker),
        );
        expect(
          methodSource.indexOf('if (!_backgroundAgentsEnabled)'),
          lessThan(methodSource.indexOf('ref.read(agentServiceProvider)')),
          reason:
              '$marker must fail closed before touching legacy AgentService.',
        );
      }

      final senderSource = [
        await File('lib/ui/studio/studio_message_sender.dart').readAsString(),
        await File(
          'lib/ui/studio/studio_custom_agent_routing.dart',
        ).readAsString(),
        await File('lib/ui/studio/studio_context_payload.dart').readAsString(),
      ].join('\n');
      final agentSource = await File('lib/agent/agent.dart').readAsString();
      final featureFlagSource = await File(
        'lib/core/config/studio_feature_flags.dart',
      ).readAsString();
      expect(
        featureFlagSource,
        contains('static const enterpriseSpecialists = false'),
      );
      expect(
        senderSource,
        contains('StudioFeatureFlags.enterpriseSpecialists'),
      );
      expect(
        senderSource,
        contains('Enterprise specialist routing is disabled'),
      );
      expect(
        senderSource,
        contains('SpecialistAgentRouter().route(prompt)'),
        reason:
            'Specialist routing may return only after the explicit Studio feature gate is enabled.',
      );
      expect(
        agentSource,
        contains('StudioFeatureFlags.advancedStudioSurfaces'),
      );
      expect(
        agentSource.indexOf('StudioFeatureFlags.advancedStudioSurfaces'),
        lessThan(agentSource.indexOf('..._mcpTools')),
        reason:
            'Legacy CircuitAgent must not expose MCP tools unless advanced surfaces are explicitly enabled.',
      );

      final shellProviderSource = await File(
        'lib/state/studio_shell_provider.dart',
      ).readAsString();
      expect(
        shellProviderSource,
        contains('StudioFeatureFlags.advancedStudioSurfaces'),
        reason:
            'Unsupported execution modes must be coerced until the Studio runtime owns their sandbox boundary.',
      );
      expect(
        shellProviderSource,
        contains('StudioExecutionMode.local'),
        reason: 'Studio should fail closed to local execution mode.',
      );
    },
  );

  test('Disabled Studio specialists coerce to Auto in shell state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(studioShellProvider.notifier)
        .setSpecialistAgent(SpecialistAgentId.solutionSizer);

    expect(
      container.read(studioShellProvider).specialistAgentId,
      SpecialistAgentId.auto,
      reason:
          'Specialist agents stay quarantined until they use the same turn runtime, context, and permission contract as core Studio.',
    );
  });

  test(
    'Notebook AI helpers stay quarantined from legacy AgentService',
    () async {
      final source = await File(
        'lib/state/notebook_provider.dart',
      ).readAsString();

      expect(source, isNot(contains('agentServiceProvider')));
      expect(source, isNot(contains('sendOneShot(')));
      expect(source, contains('StudioFeatureFlags.advancedStudioSurfaces'));
      expect(
        source,
        contains(
          'Notebook AI generation is paused while notebooks are migrated',
        ),
      );
      expect(
        source,
        contains(
          'Notebook AI explanation is paused while notebooks are migrated',
        ),
      );
    },
  );

  test('SuggestedLearningController reviews memories before saving', () async {
    final root = await _sampleFlutterProject();
    addTearDown(() => _delete(root));
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(fileTreeProvider.notifier).openDirectory(root.path);
    final suggestion = container
        .read(suggestedLearningProvider.notifier)
        .suggestMemory(name: 'review-first', content: 'Always review writes.');

    expect(suggestion.type, SuggestedLearningType.memory);
    expect(container.read(suggestedLearningProvider).pending, hasLength(1));

    container.read(suggestedLearningProvider.notifier).reject(suggestion.id);

    expect(container.read(suggestedLearningProvider).pending, isEmpty);
  });
}

String _methodBody(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(start, isNonNegative, reason: startMarker);
  expect(end, isNonNegative, reason: endMarker);
  return source.substring(start, end);
}

String _nextBackgroundMarker(String marker) {
  return switch (marker) {
    'void _setupListeners' => 'void _onAgentCompleted',
    'void _handleFileSaveTrigger' => 'void handleGitCommitTrigger',
    'void handleGitCommitTrigger' => 'void handleProjectOpenTrigger',
    'void handleProjectOpenTrigger' => 'void _handlePeriodicTriggers',
    _ => 'bool _checkCooldown',
  };
}

class _FakeWorkItemHistoryController extends WorkItemHistoryController {
  @override
  WorkItemHistory build() => const WorkItemHistory();

  @override
  Future<void> upsert(WorkItem item) async {
    state = WorkItemHistory(items: [item]);
  }
}

Future<Directory> _sampleFlutterProject() async {
  final root = await Directory.systemTemp.createTemp('context_pack_v3_');
  await File(p.join(root.path, 'pubspec.yaml')).writeAsString('''
name: sample
dependencies:
  flutter:
    sdk: flutter
''');
  await Directory(p.join(root.path, 'lib')).create();
  await File(
    p.join(root.path, 'lib', 'main.dart'),
  ).writeAsString('void main() {}\n');
  return root;
}

Future<void> _delete(Directory directory) async {
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
}

Future<void> _waitForThreadStore(ProviderContainer container) async {
  for (var i = 0; i < 20; i++) {
    if (!container.read(studioThreadProvider).isLoading) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _waitForPatchProvider(
  ProviderContainer container,
  bool Function(PatchProposalState state) ready,
) async {
  for (var i = 0; i < 40; i++) {
    if (ready(container.read(patchProposalProvider))) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _waitForPatchStore(
  PatchProposalStore store,
  String rootPath,
  bool Function(PatchProposalState state) ready,
) async {
  for (var i = 0; i < 40; i++) {
    if (ready(await store.load(rootPath))) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
