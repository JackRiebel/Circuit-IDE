import 'dart:io';

import 'package:circuit_ide/agent/tools/tool_registry.dart';
import 'package:circuit_ide/core/utils/platform_utils.dart';
import 'package:circuit_ide/models/accepted_plan_context.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/models/studio_shell.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/patch_proposal_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/state/studio_turn_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  tearDown(() {
    PlatformUtils.configDirOverride = null;
  });

  test('end-to-end Studio reliability suite covers core user-pain flows', () {
    const suite = <_ReliabilitySource>[
      _ReliabilitySource(
        path: 'test/studio_core_reliability_contract_test.dart',
        markers: [
          'core intent classifier keeps greetings and discovery non-mutating',
          "'hello'",
          'I want to build something to help me size out datacenters for customers',
          'TurnIntent.chat',
          'TurnIntent.ask',
          'tool profiles preserve chat plan code verify boundaries',
          'permission policy denies mutation until app-owned review or approval',
        ],
      ),
      _ReliabilitySource(
        path: 'test/studio_shell_v5_test.dart',
        markers: [
          'Streaming assistant draft does not render twice',
          'Streaming plan draft renders inside plan card',
          'Long streaming plan draft remains bounded in chat',
          'Synthesized final plan renders as one plan card without duplicate prose',
          'Plan implementation sends structured context and offers next batch after partial apply',
          'Inline patch conflict card exposes recovery actions',
          'Refresh patch',
          'Patch verification helper runs suggested checks without model mediation',
          'Applied patch card shows linked verification result',
          'Applied patch card shows deterministic verification failure',
          'Studio Review Panel renders applied and restored checkpoints',
          'Progress drawer prefers patch conflict event over later provider failure',
          'Studio transcript hides routine context and tool status rows',
          'Internal fallback prompts stay out of Studio transcript',
          'Restore checkpoint',
        ],
      ),
      _ReliabilitySource(
        path: 'test/studio_turn_runtime_flow_test.dart',
        markers: [
          'AgentTurnRuntime turns accepted plan into concrete patch and app apply',
          'AgentTurnRuntime golden path plans, patches, applies, and verifies',
          'AgentTurnRuntime continuation batch completes source accepted plan',
          'approveOnce(\'verify-cat\')',
          'TurnStep.commandRun',
          'TurnStep.verification',
          'StudioThreadStatus.done',
          'streamingContent, isEmpty',
          'PlanTargetProgressState.applied',
        ],
      ),
      _ReliabilitySource(
        path: 'test/studio_thread_test.dart',
        markers: [
          'patch conflict transactions upsert by conflicted file across retries',
          'patch conflict transactions include rebase recovery guidance',
          'applied patch with suggested checks queues verification step',
          'failed verification command is journaled as a failed outcome',
          'active verification command is journaled before turn archive',
          'StudioThreadStore reloads partial accepted-plan apply as continuation ready',
          'StudioThreadStore reloads patch conflict as review without stale provider error',
          'StudioThreadStore marks interrupted active threads as failed on load',
          'StudioThreadStore normalizes interrupted turns recovered from journal',
          'StudioThreadStore keeps complete thread history on load',
        ],
      ),
      _ReliabilitySource(
        path: 'test/studio_v7_drawer_test.dart',
        markers: [
          'Studio Diff drawer opens historical patch by id',
          'Studio Diff drawer defaults to selected thread patch history',
          'Studio Diff drawer refreshes conflicted patch in place',
          'Studio Diff drawer explains stale selected patch review',
          'Studio source artifacts quarantine browser comments',
          'Studio Diff drawer exposes patch review actions',
          'Apply changes',
          'Ask for revision',
          'Context drawer can include omitted persisted retrieval paths next time',
        ],
      ),
      _ReliabilitySource(
        path: 'scripts/studio_reliability_suite.sh',
        markers: [
          'flutter analyze',
          'git diff --check',
          'AgentTurnRuntime classified hello stays chat-only and tool-free',
          'AgentTurnRuntime golden path plans, patches, applies, and verifies',
          'AgentTurnRuntime continuation batch completes source accepted plan',
          'Broad build ideas start discovery before code',
          'Streaming assistant draft does not render twice',
          'Streaming plan draft renders inside plan card',
          'Long streaming plan draft remains bounded in chat',
          'Patch verification helper runs suggested checks without model mediation',
          'Plan implementation sends structured context and offers next batch after partial apply',
          'Studio rail collapses long project histories',
          'StudioThreadStore reloads partial accepted-plan apply as continuation ready',
          'StudioThreadStore reloads patch conflict as review without stale provider error',
          'Studio Diff drawer defaults to selected thread patch history',
          'Studio Diff drawer explains stale selected patch review',
          'Studio source artifacts quarantine browser comments',
        ],
      ),
    ];

    for (final source in suite) {
      final text = File(source.path).readAsStringSync();
      for (final marker in source.markers) {
        expect(
          text,
          contains(marker),
          reason: '${source.path} should keep coverage marker: $marker',
        );
      }
    }
  });

  test('scenario: greetings and broad ideas cannot enter mutation flows', () {
    expect(
      IntentClassifier.classify(
        'hello',
        promptMode: StudioPromptMode.code,
        planModeEnabled: true,
      ),
      TurnIntent.chat,
    );
    expect(ToolRegistry.toolsForMode(AgentToolMode.chat), isEmpty);

    expect(
      IntentClassifier.classify(
        'I want to build something to help me size out datacenters for customers',
        promptMode: StudioPromptMode.code,
        planModeEnabled: true,
      ),
      TurnIntent.ask,
    );
    final askTools = ToolRegistry.toolsForMode(
      AgentToolMode.ask,
    ).map((tool) => tool.name).toSet();
    expect(askTools, containsAll({'read_file', 'search_files'}));
    expect(askTools, isNot(contains('propose_patch')));
    expect(askTools, isNot(contains('run_command')));
    expect(askTools, isNot(contains('apply_patch_set')));
  });

  test(
    'scenario: accepted plan applies first batch and reloads continuation ready',
    () async {
      final harness = await _ScenarioHarness.create(
        name: 'accepted_plan_batch',
      );
      addTearDown(harness.dispose);

      const requestId = 'request-accepted-plan-batch';
      final thread = harness.createThread('Datacenter sizing plan');
      const acceptedPlan = AcceptedPlanContext(
        patchSetId: 'plan-dc-sizing',
        title: 'Datacenter sizing MVP',
        summary: 'Build the first useful slice of a datacenter sizing tool.',
        markdown:
            '# Datacenter sizing MVP\n\n- Create lib/sizer.dart\n- Document usage in README.md',
        plannedTargets: [
          PlannedFileTarget(
            path: 'lib/sizer.dart',
            intent: 'Create core sizing model',
            operation: ProposedFileEditType.create,
          ),
          PlannedFileTarget(
            path: 'README.md',
            intent: 'Document usage and verification',
            operation: ProposedFileEditType.create,
          ),
        ],
        verificationRequested: true,
      );
      harness.registerTurn(
        threadId: thread.id,
        requestId: requestId,
        prompt: 'Implement this approved plan.',
        intent: TurnIntent.code,
        acceptedPlan: acceptedPlan,
      );

      final patch = harness.container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Datacenter sizing MVP first batch',
            runId: requestId,
            verificationRequested: true,
            edits: const [
              ProposedFileEdit(
                path: 'lib/sizer.dart',
                type: ProposedFileEditType.create,
                after:
                    'class DatacenterSizer {\n  int rackUnits(int servers) => servers * 2;\n}\n',
              ),
            ],
          );

      final result = await harness.container
          .read(patchProposalProvider.notifier)
          .apply(patch.id);

      expect(result.applied, isTrue);
      expect(result.changedFiles, ['lib/sizer.dart']);
      expect(result.checkpointId, isNotNull);
      expect(result.diffSummary, contains('Created lib/sizer.dart'));
      expect(
        await File(p.join(harness.project.path, 'lib/sizer.dart')).exists(),
        isTrue,
      );

      final turn = harness.latestTurn(thread.id, requestId);
      expect(turn.status, StudioTurnStatus.completed);
      expect(turn.acceptedPlanState, AcceptedPlanState.patchProposed);
      expect(
        turn.planTargetProgress
            .where((target) => target.path == 'lib/sizer.dart')
            .single
            .state,
        PlanTargetProgressState.applied,
      );
      expect(
        turn.planTargetProgress
            .where((target) => target.path == 'README.md')
            .single
            .state,
        PlanTargetProgressState.pending,
      );
      final summaryDetail = turn.events
          .where((event) => event.title == 'Applied changes')
          .map((event) => event.detail)
          .join('\n');
      expect(summaryDetail, contains('Changed files: lib/sizer.dart'));
      expect(summaryDetail, contains('Remaining plan targets:'));
      expect(summaryDetail, contains('README.md'));
      expect(summaryDetail, contains('Suggested checks:'));

      await harness.flushPersistence();
      final loaded = await harness.threadStore.load(harness.project.path);
      expect(loaded.single.status, StudioThreadStatus.continuationReady);
      expect(loaded.single.turns.single.status, StudioTurnStatus.completed);
      expect(loaded.single.streamingContent, isEmpty);
    },
  );

  test(
    'scenario: patch conflicts dedupe and keep recovery guidance actionable',
    () async {
      final harness = await _ScenarioHarness.create(name: 'conflict_dedupe');
      addTearDown(harness.dispose);
      await File(
        p.join(harness.project.path, 'README.md'),
      ).writeAsString('changed on disk\n');

      const requestId = 'request-conflict-dedupe';
      final thread = harness.createThread('Conflict handling');
      const acceptedPlan = AcceptedPlanContext(
        patchSetId: 'plan-readme-conflict',
        title: 'README update plan',
        summary: 'Update the README safely.',
        markdown: '# README update plan\n\n- Update README.md',
        plannedTargets: [
          PlannedFileTarget(
            path: 'README.md',
            intent: 'Update README content',
            operation: ProposedFileEditType.modify,
          ),
        ],
      );
      harness.registerTurn(
        threadId: thread.id,
        requestId: requestId,
        prompt: 'Apply prepared README change.',
        intent: TurnIntent.code,
        acceptedPlan: acceptedPlan,
      );
      final patch = harness.container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'README update',
            runId: requestId,
            edits: const [
              ProposedFileEdit(
                path: 'README.md',
                type: ProposedFileEditType.modify,
                before: 'old readme\n',
                after: 'new readme\n',
              ),
            ],
          );

      final first = await harness.container
          .read(patchProposalProvider.notifier)
          .apply(patch.id);
      final second = await harness.container
          .read(patchProposalProvider.notifier)
          .apply(patch.id);

      expect(first.status, PatchApplyStatus.conflict);
      expect(second.status, PatchApplyStatus.conflict);

      final turn = harness.latestTurn(thread.id, requestId);
      final conflictEvents = turn.events
          .where((event) => event.title == 'Patch conflict')
          .toList();
      expect(conflictEvents, hasLength(1));
      expect(conflictEvents.single.detail, contains('README.md'));
      expect(conflictEvents.single.detail, contains('Ask Circuit to rebase'));
      expect(
        turn.planTargetProgress
            .where((target) => target.path == 'README.md')
            .map((target) => target.state),
        contains(PlanTargetProgressState.conflict),
      );
    },
  );

  test(
    'scenario: verification command result is saved as outcome state',
    () async {
      final harness = await _ScenarioHarness.create(name: 'verify_outcome');
      addTearDown(harness.dispose);
      const requestId = 'request-verify-outcome';
      final thread = harness.createThread('Verify applied patch');
      harness.registerTurn(
        threadId: thread.id,
        requestId: requestId,
        prompt: 'Run verification.',
        intent: TurnIntent.verify,
      );

      harness.container
          .read(studioTurnProvider.notifier)
          .recordCommandRunResult(
            requestId,
            commandRunId: 'verify-1',
            command: 'dart test',
            status: 'succeeded',
            output: 'All tests passed\n',
            exitCode: 0,
          );

      final turn = harness.latestTurn(thread.id, requestId);
      expect(
        turn.steps
            .where((step) => step.step == TurnStep.commandRun)
            .single
            .status,
        TurnStepStatus.completed,
      );
      expect(
        turn.steps
            .where((step) => step.step == TurnStep.verification)
            .single
            .status,
        TurnStepStatus.completed,
      );
      expect(
        turn.events
            .where((event) => event.title == 'Ran command')
            .single
            .detail,
        contains('All tests passed'),
      );

      await harness.flushPersistence();
      final loaded = await harness.threadStore.load(harness.project.path);
      final loadedTurn = loaded.single.turns.single;
      expect(
        loadedTurn.steps.map((step) => step.step),
        contains(TurnStep.verification),
      );
      expect(
        loadedTurn.events.map((event) => event.title),
        contains('Ran command'),
      );
    },
  );

  test(
    'scenario: restart rail summary preserves state without full transcript payload',
    () async {
      final harness = await _ScenarioHarness.create(name: 'rail_summary');
      addTearDown(harness.dispose);

      const requestId = 'request-rail-summary';
      final thread = harness.createThread('Rail summary persistence');
      const acceptedPlan = AcceptedPlanContext(
        patchSetId: 'plan-rail-summary',
        title: 'Rail summary plan',
        summary: 'Apply one target and keep another queued for continuation.',
        markdown:
            '# Rail summary plan\n\n- Create lib/a.dart\n- Create lib/b.dart',
        plannedTargets: [
          PlannedFileTarget(
            path: 'lib/a.dart',
            intent: 'Create the first file',
            operation: ProposedFileEditType.create,
          ),
          PlannedFileTarget(
            path: 'lib/b.dart',
            intent: 'Create the second file',
            operation: ProposedFileEditType.create,
          ),
        ],
      );
      harness.registerTurn(
        threadId: thread.id,
        requestId: requestId,
        prompt: 'Implement this approved plan.',
        intent: TurnIntent.code,
        acceptedPlan: acceptedPlan,
      );

      final patch = harness.container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Rail summary first batch',
            runId: requestId,
            edits: const [
              ProposedFileEdit(
                path: 'lib/a.dart',
                type: ProposedFileEditType.create,
                after: 'const value = 1;\n',
              ),
            ],
          );
      final result = await harness.container
          .read(patchProposalProvider.notifier)
          .apply(patch.id);
      expect(result.applied, isTrue);

      await harness.flushPersistence();
      final fullThreads = await harness.threadStore.load(harness.project.path);
      final summaryThreads = await harness.threadStore.loadSummaries(
        harness.project.path,
      );

      expect(fullThreads.single.status, StudioThreadStatus.continuationReady);
      expect(fullThreads.single.turns.single.events, isNotEmpty);
      expect(
        summaryThreads.single.status,
        StudioThreadStatus.continuationReady,
      );
      expect(summaryThreads.single.turns, hasLength(1));
      expect(summaryThreads.single.turns.single.prompt, isEmpty);
      expect(summaryThreads.single.turns.single.events, isEmpty);
      expect(summaryThreads.single.turns.single.toolResults, isEmpty);
      expect(summaryThreads.single.streamingContent, isEmpty);
      expect(
        await File(
          harness.threadStore.summaryPath(harness.project.path),
        ).exists(),
        isTrue,
      );
    },
  );
}

class _ReliabilitySource {
  final String path;
  final List<String> markers;

  const _ReliabilitySource({required this.path, required this.markers});
}

class _ScenarioHarness {
  final Directory root;
  final Directory project;
  final ProviderContainer container;
  final StudioThreadStore threadStore;

  const _ScenarioHarness({
    required this.root,
    required this.project,
    required this.container,
    required this.threadStore,
  });

  static Future<_ScenarioHarness> create({required String name}) async {
    final root = await Directory.systemTemp.createTemp('studio_e2e_$name');
    final config = await Directory(p.join(root.path, 'config')).create();
    final project = await Directory(p.join(root.path, 'project')).create();
    PlatformUtils.configDirOverride = config.path;
    final patchStore = PatchProposalStore(
      baseDir: p.join(root.path, 'patches'),
    );
    final container = ProviderContainer(
      overrides: [patchProposalStoreProvider.overrideWithValue(patchStore)],
    );
    await container.read(fileTreeProvider.notifier).openDirectory(project.path);
    await container.read(studioThreadProvider.notifier).reload();
    final threadStore = StudioThreadStore(
      baseDir: p.join(config.path, 'studio_threads'),
    );
    return _ScenarioHarness(
      root: root,
      project: project,
      container: container,
      threadStore: threadStore,
    );
  }

  StudioThread createThread(String title) {
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: title);
    return thread;
  }

  StudioTurn registerTurn({
    required String threadId,
    required String requestId,
    required String prompt,
    required TurnIntent intent,
    AcceptedPlanContext? acceptedPlan,
  }) {
    return container
        .read(studioTurnProvider.notifier)
        .registerTurn(
          requestId: requestId,
          threadId: threadId,
          taskId: null,
          userMessageId: 'message-$requestId',
          prompt: prompt,
          model: 'gpt-5-nano',
          intent: intent,
          acceptedPlanState: acceptedPlan == null
              ? AcceptedPlanState.none
              : AcceptedPlanState.accepted,
          acceptedPlanContext: acceptedPlan,
          contextSummary: StudioContextSummary(
            rootPath: project.path,
            projectLabel: 'project',
            includedItemCount: 1,
            estimatedTokens: 128,
          ),
        );
  }

  StudioTurn latestTurn(String threadId, String requestId) {
    return container
        .read(studioThreadProvider)
        .threads
        .where((thread) => thread.id == threadId)
        .single
        .turns
        .where((turn) => turn.requestId == requestId)
        .single;
  }

  Future<void> flushPersistence() async {
    await Future<void>.delayed(const Duration(milliseconds: 1100));
  }

  Future<void> dispose() async {
    await flushPersistence();
    container.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    PlatformUtils.configDirOverride = null;
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}
