import 'dart:io';

import 'package:circuit_ide/models/agent_workspace.dart';
import 'package:circuit_ide/models/context_pack.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/models/studio_shell.dart';
import 'package:circuit_ide/state/agent_workspace_provider.dart';
import 'package:circuit_ide/state/context_pack_provider.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/patch_proposal_provider.dart';
import 'package:circuit_ide/state/project_profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('completion notice only hands off a live background transition', () {
    final active = AgentTask(
      id: 'background-task',
      mascotAlias: 'Benny',
      profile: AgentTaskProfile.verify,
      status: AgentTaskStatus.running,
      goal: 'Run the release checks',
      createdAt: DateTime(2026),
    );
    final completed = active.copyWith(
      status: AgentTaskStatus.completed,
      result: 'All checks passed.',
      completedAt: DateTime(2026, 1, 1, 1),
    );

    final notice = taskCompletionNotice(
      AgentWorkspaceState(tasks: [active]),
      AgentWorkspaceState(tasks: [completed]),
    );

    expect(notice?.taskId, 'background-task');
    expect(notice?.message, contains('Benny completed'));
    expect(notice?.message, contains('Open the task to review the result'));
    expect(
      taskCompletionNotice(null, AgentWorkspaceState(tasks: [completed])),
      isNull,
    );
    expect(
      taskCompletionNotice(
        AgentWorkspaceState(tasks: [completed]),
        AgentWorkspaceState(tasks: [completed]),
      ),
      isNull,
    );
  });

  test('Mascot aliases rotate deterministically and add suffixes', () {
    expect(AgentMascotNamePool.aliasForIndex(0), 'Benny');
    expect(AgentMascotNamePool.aliasForIndex(1), 'Clark');
    expect(AgentMascotNamePool.aliasForIndex(6), 'Skye');
    expect(AgentMascotNamePool.aliasForIndex(7), 'Benny 2');
  });

  test('Default agent tool policy is review-first for mutation', () {
    const policy = WorkspacePermissionConfiguration();

    expect(
      policy.dispositionFor(WorkspaceToolCapability.readTool),
      WorkspacePermissionDisposition.allow,
    );
    expect(
      policy.dispositionFor(WorkspaceToolCapability.writeTool),
      WorkspacePermissionDisposition.review,
    );
    expect(
      policy.dispositionFor(WorkspaceToolCapability.command),
      WorkspacePermissionDisposition.review,
    );
    expect(
      policy.dispositionFor(WorkspaceToolCapability.externalNetwork),
      WorkspacePermissionDisposition.block,
    );
  });

  test('Research tasks persist a web-only background profile', () {
    final task = AgentTask(
      id: 'research-task',
      mascotAlias: 'Benny',
      profile: AgentTaskProfile.research,
      goal: 'Compare current Wi-Fi 7 power guidance',
      backgroundExecutionRequested: true,
      createdAt: DateTime.utc(2026, 7, 13),
    );
    final restored = AgentTask.fromJson(task.toJson());
    final policy = AgentTaskProfileSpec.forProfile(
      AgentTaskProfile.research,
    ).policy;

    expect(restored?.profile, AgentTaskProfile.research);
    expect(restored?.backgroundExecutionRequested, isTrue);
    expect(
      policy.dispositionFor(WorkspaceToolCapability.readTool),
      WorkspacePermissionDisposition.block,
    );
    expect(
      policy.dispositionFor(WorkspaceToolCapability.writeTool),
      WorkspacePermissionDisposition.block,
    );
    expect(
      policy.dispositionFor(WorkspaceToolCapability.command),
      WorkspacePermissionDisposition.block,
    );
    expect(
      policy.dispositionFor(WorkspaceToolCapability.git),
      WorkspacePermissionDisposition.block,
    );
  });

  test('AgentWorkspaceStore persists project-scoped task history', () async {
    final root = await Directory.systemTemp.createTemp('agent_ws_project_');
    final storeRoot = await Directory.systemTemp.createTemp('agent_ws_config_');
    addTearDown(() => _delete(root));
    addTearDown(() => _delete(storeRoot));

    final store = AgentWorkspaceStore(baseDir: storeRoot.path);
    final task = AgentTask(
      id: 'task-1',
      mascotAlias: 'Benny',
      profile: AgentTaskProfile.investigate,
      status: AgentTaskStatus.waitingForApproval,
      goal: 'Investigate startup',
      workspaceMode: AgentTaskWorkspaceMode.isolatedWorktree,
      workspaceRoot: root.path,
      worktreePath: p.join(root.path, '.task-worktree'),
      worktreeBranch: 'circuit/task-1',
      worktreeBaseRevision: 'abc123',
      artifacts: [
        AgentTaskArtifact(
          id: 'ctx',
          type: AgentTaskArtifactType.contextPack,
          title: 'Context pack',
          detail: '3 items',
          createdAt: DateTime(2026),
        ),
      ],
      createdAt: DateTime(2026),
    );

    await store.save(root.path, [task]);
    final loaded = await store.load(root.path);

    expect(loaded.single.mascotAlias, 'Benny');
    expect(loaded.single.profile, AgentTaskProfile.investigate);
    expect(
      loaded.single.artifacts.single.type,
      AgentTaskArtifactType.contextPack,
    );
    expect(
      loaded.single.workspaceMode,
      AgentTaskWorkspaceMode.isolatedWorktree,
    );
    expect(loaded.single.worktreeBranch, 'circuit/task-1');
    expect(
      loaded.single.effectiveWorkspaceRoot,
      p.join(root.path, '.task-worktree'),
    );
  });

  test('AgentWorkspaceStore streams bounded task metadata pages', () async {
    final root = await Directory.systemTemp.createTemp('agent_task_page_');
    final storeRoot = await Directory.systemTemp.createTemp(
      'agent_page_store_',
    );
    addTearDown(() => _delete(root));
    addTearDown(() => _delete(storeRoot));
    final store = AgentWorkspaceStore(baseDir: storeRoot.path);
    final tasks = [
      for (var index = 0; index < 35; index++)
        AgentTask(
          id: 'task-$index',
          mascotAlias: 'Benny',
          profile: AgentTaskProfile.investigate,
          goal: 'Task $index',
          createdAt: DateTime.utc(2026, 7, 11, 12, index),
        ),
    ];
    await store.save(root.path, tasks);

    final first = await store.loadSummaryPage(root.path, limit: 12);
    final second = await store.loadSummaryPage(
      root.path,
      offset: first.nextOffset,
      limit: 12,
    );

    expect(first.totalCount, 35);
    expect(first.tasks, hasLength(12));
    expect(first.hasMore, isTrue);
    expect(second.offset, 12);
    expect(second.tasks, hasLength(12));
    expect(await File(store.summaryIndexPath(root.path)).exists(), isTrue);
  });

  test(
    'AgentWorkspaceStore marks interrupted active tasks failed on load',
    () async {
      final root = await Directory.systemTemp.createTemp('agent_ws_project_');
      final storeRoot = await Directory.systemTemp.createTemp(
        'agent_ws_config_',
      );
      addTearDown(() => _delete(root));
      addTearDown(() => _delete(storeRoot));

      final store = AgentWorkspaceStore(baseDir: storeRoot.path);
      final task = AgentTask(
        id: 'task-interrupted',
        mascotAlias: 'Benny',
        profile: AgentTaskProfile.investigate,
        status: AgentTaskStatus.running,
        goal: 'Investigate startup',
        activeRunId: 'run-interrupted',
        createdAt: DateTime(2026),
      );

      await store.save(root.path, [task]);

      final loaded = await store.load(root.path);

      expect(loaded.single.status, AgentTaskStatus.failed);
      expect(loaded.single.activeRunId, isNull);
      expect(loaded.single.completedAt, isNotNull);
      expect(
        loaded.single.error,
        contains('Interrupted while CircuitCode was closed'),
      );
    },
  );

  test('AgentWorkspaceStore preserves paused tasks on load', () async {
    final root = await Directory.systemTemp.createTemp('agent_ws_project_');
    final storeRoot = await Directory.systemTemp.createTemp('agent_ws_config_');
    addTearDown(() => _delete(root));
    addTearDown(() => _delete(storeRoot));

    final store = AgentWorkspaceStore(baseDir: storeRoot.path);
    final task = AgentTask(
      id: 'task-paused',
      mascotAlias: 'Benny',
      profile: AgentTaskProfile.patch,
      status: AgentTaskStatus.paused,
      goal: 'Resume after background pause',
      createdAt: DateTime(2026),
    );
    await store.save(root.path, [task]);

    final loaded = await store.load(root.path);

    expect(loaded.single.status, AgentTaskStatus.paused);
    expect(loaded.single.activeRunId, isNull);
    expect(loaded.single.completedAt, isNull);
  });

  test(
    'AgentWorkspaceStore pauses interrupted background tasks for resume',
    () async {
      final root = await Directory.systemTemp.createTemp('agent_ws_project_');
      final storeRoot = await Directory.systemTemp.createTemp(
        'agent_ws_config_',
      );
      addTearDown(() => _delete(root));
      addTearDown(() => _delete(storeRoot));

      final store = AgentWorkspaceStore(baseDir: storeRoot.path);
      final running = AgentTask(
        id: 'task-background-running',
        mascotAlias: 'Benny',
        profile: AgentTaskProfile.investigate,
        status: AgentTaskStatus.running,
        goal: 'Resume this background investigation',
        backgroundExecutionRequested: true,
        activeRunId: 'request-interrupted',
        createdAt: DateTime(2026),
      );
      final queued = AgentTask(
        id: 'task-background-queued',
        mascotAlias: 'Clark',
        profile: AgentTaskProfile.verify,
        status: AgentTaskStatus.queued,
        goal: 'Keep this queued verification task',
        backgroundExecutionRequested: true,
        createdAt: DateTime(2026, 1, 1, 1),
      );
      await store.save(root.path, [running, queued]);

      final loaded = await store.load(root.path);
      final resumable = loaded.firstWhere((task) => task.id == running.id);
      final restoredQueue = loaded.firstWhere((task) => task.id == queued.id);

      expect(resumable.status, AgentTaskStatus.paused);
      expect(resumable.activeRunId, isNull);
      expect(resumable.completedAt, isNull);
      expect(resumable.error, contains('Resume to continue safely'));
      expect(restoredQueue.status, AgentTaskStatus.queued);
      expect(restoredQueue.activeRunId, isNull);
    },
  );

  test(
    'AgentWorkspaceStore treats stale active tasks with results as completed',
    () async {
      final root = await Directory.systemTemp.createTemp('agent_ws_project_');
      final storeRoot = await Directory.systemTemp.createTemp(
        'agent_ws_config_',
      );
      addTearDown(() => _delete(root));
      addTearDown(() => _delete(storeRoot));

      final store = AgentWorkspaceStore(baseDir: storeRoot.path);
      final completedAt = DateTime(2026, 1, 2);
      final task = AgentTask(
        id: 'task-stale-complete',
        mascotAlias: 'Benny',
        profile: AgentTaskProfile.patch,
        status: AgentTaskStatus.running,
        goal: 'Update readme',
        activeRunId: 'run-stale',
        result: 'Finished.',
        createdAt: DateTime(2026),
        completedAt: completedAt,
      );

      await store.save(root.path, [task]);

      final loaded = await store.load(root.path);

      expect(loaded.single.status, AgentTaskStatus.completed);
      expect(loaded.single.activeRunId, isNull);
      expect(loaded.single.completedAt, completedAt);
      expect(loaded.single.result, 'Finished.');
      expect(loaded.single.error, isNull);
    },
  );

  test(
    'ContextPackController discovers approved project instruction files',
    () async {
      final root = await _sampleProject();
      addTearDown(() => _delete(root));
      await File(
        p.join(root.path, 'CIRCUIT.md'),
      ).writeAsString('Use Circuit review checkpoints.');
      await File(
        p.join(root.path, 'AGENTS.md'),
      ).writeAsString('Use review first.');
      await Directory(p.join(root.path, '.github')).create();
      await File(
        p.join(root.path, '.github', 'copilot-instructions.md'),
      ).writeAsString('Prefer small patches.');
      await Directory(
        p.join(root.path, '.circuit', 'rules'),
      ).create(recursive: true);
      await File(
        p.join(root.path, '.circuit', 'rules', 'security.md'),
      ).writeAsString('Do not auto-run mutation commands.');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      await container.read(projectProfileProvider.notifier).refresh();

      final pack = container
          .read(contextPackProvider.notifier)
          .buildForCodingTask();

      expect(
        pack.instructionItems.map((item) => item.source),
        containsAll([
          'CIRCUIT.md',
          'AGENTS.md',
          '.github/copilot-instructions.md',
          '.circuit/rules/security.md',
        ]),
      );
      expect(
        pack.visibleItems.any(
          (item) => item.type == ContextPackItemType.instruction,
        ),
        isTrue,
      );
    },
  );

  test(
    'isolated task context reads the worktree instead of the visible tree',
    () async {
      final visible = await _sampleProject();
      final worktree = await _sampleProject();
      addTearDown(() => _delete(visible));
      addTearDown(() => _delete(worktree));
      await Directory(p.join(visible.path, 'lib')).create();
      await Directory(p.join(worktree.path, 'lib')).create();
      await File(
        p.join(visible.path, 'lib', 'target.dart'),
      ).writeAsString('const source = "visible workspace";');
      await File(
        p.join(worktree.path, 'lib', 'target.dart'),
      ).writeAsString('const source = "isolated worktree";');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(fileTreeProvider.notifier)
          .openDirectory(visible.path);

      final pack = await container
          .read(contextPackProvider.notifier)
          .buildForCodingTaskWithFreshIndex(
            prompt: 'Update lib/target.dart',
            workspaceRoot: worktree.path,
          );

      expect(pack.projectKey, worktree.path);
      final target = pack.items.firstWhere(
        (item) => item.source == 'lib/target.dart',
      );
      expect(target.detail, contains('isolated worktree'));
      expect(target.detail, isNot(contains('visible workspace')));
    },
  );

  test(
    'ContextPackController applies ancestor instruction scopes from root to nearest file',
    () async {
      final root = await _sampleProject();
      addTearDown(() => _delete(root));
      await Directory(p.join(root.path, 'lib', 'auth')).create(recursive: true);
      await File(
        p.join(root.path, 'AGENTS.md'),
      ).writeAsString('Root guidance.');
      await File(
        p.join(root.path, 'lib', 'AGENTS.md'),
      ).writeAsString('Library guidance.');
      await File(
        p.join(root.path, 'lib', 'auth', 'AGENTS.md'),
      ).writeAsString('Auth guidance. <!-- local author note -->');
      await File(
        p.join(root.path, 'lib', 'auth', 'login.dart'),
      ).writeAsString('void login() {}');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      final pack = container
          .read(contextPackProvider.notifier)
          .buildForCodingTask(prompt: 'Review lib/auth/login.dart');
      final instructions = pack.instructionItems;
      final sources = instructions.map((item) => item.source).toList();

      expect(
        sources,
        containsAll(['AGENTS.md', 'lib/AGENTS.md', 'lib/auth/AGENTS.md']),
      );
      expect(
        sources.indexOf('AGENTS.md'),
        lessThan(sources.indexOf('lib/AGENTS.md')),
      );
      expect(
        sources.indexOf('lib/AGENTS.md'),
        lessThan(sources.indexOf('lib/auth/AGENTS.md')),
      );
      final scoped = instructions.firstWhere(
        (item) => item.source == 'lib/auth/AGENTS.md',
      );
      expect(scoped.detail, contains('Auth guidance.'));
      expect(scoped.detail, isNot(contains('local author note')));
      expect(
        scoped.retrievalReason,
        'nearest directory instruction · scope: lib/auth',
      );
    },
  );

  test(
    'ContextPackController records a deterministic effective instruction hierarchy',
    () async {
      final root = await _sampleProject();
      final globalConfig = await Directory.systemTemp.createTemp(
        'circuit_global_instruction_',
      );
      addTearDown(() => _delete(root));
      addTearDown(() => _delete(globalConfig));
      await File(
        p.join(globalConfig.path, 'CIRCUIT.md'),
      ).writeAsString('Global Circuit guidance. <!-- global comment -->');
      await Directory(p.join(root.path, 'lib', 'auth')).create(recursive: true);
      await File(
        p.join(root.path, 'CIRCUIT.md'),
      ).writeAsString('Workspace guidance.');
      await File(
        p.join(root.path, 'lib', 'AGENTS.md'),
      ).writeAsString('Library guidance.');
      await File(
        p.join(root.path, 'lib', 'auth', 'login.dart'),
      ).writeAsString('void login() {}');
      await Directory(
        p.join(root.path, '.circuit', 'rules'),
      ).create(recursive: true);
      await File(
        p.join(root.path, '.circuit', 'rules', 'auth.md'),
      ).writeAsString('''
---
patterns:
  - "lib/auth/**"
---
Auth rule guidance. <!-- rule comment -->
''');

      final container = ProviderContainer(
        overrides: [
          globalCircuitInstructionDirectoryProvider.overrideWithValue(
            globalConfig.path,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      final pack = container
          .read(contextPackProvider.notifier)
          .buildForCodingTask(prompt: 'Review lib/auth/login.dart');
      final instructions = pack.instructionItems;
      final sources = instructions.map((item) => item.source).toList();

      expect(sources.first, 'built-in CircuitCode policy');
      expect(
        sources,
        containsAll([
          'global CIRCUIT.md',
          'CIRCUIT.md',
          'lib/AGENTS.md',
          '.circuit/rules/auth.md',
        ]),
      );
      expect(
        sources.indexOf('global CIRCUIT.md'),
        lessThan(sources.indexOf('CIRCUIT.md')),
      );
      expect(
        sources.indexOf('CIRCUIT.md'),
        lessThan(sources.indexOf('lib/AGENTS.md')),
      );
      expect(
        sources.indexOf('lib/AGENTS.md'),
        lessThan(sources.indexOf('.circuit/rules/auth.md')),
      );
      final runtime = instructions.first;
      final global = instructions.firstWhere(
        (item) => item.source == 'global CIRCUIT.md',
      );
      final rule = instructions.firstWhere(
        (item) => item.source == '.circuit/rules/auth.md',
      );
      expect(runtime.retrievalReason, contains('highest precedence'));
      expect(global.detail, contains('Global Circuit guidance.'));
      expect(global.detail, isNot(contains('global comment')));
      expect(rule.sourceKind, ContextPackSourceKind.circuitRule);
      expect(rule.retrievalReason, contains('matched Circuit rule'));
      expect(rule.retrievalReason, contains('scope: matched path pattern'));
      expect(rule.detail, isNot(contains('rule comment')));
    },
  );

  test('Patch proposals attach to supervised agent tasks', () async {
    final root = await _sampleProject();
    addTearDown(() => _delete(root));
    final file = File(p.join(root.path, 'README.md'));
    await file.writeAsString('old\n');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(fileTreeProvider.notifier).openDirectory(root.path);
    await container.read(projectProfileProvider.notifier).refresh();
    await Future<void>.delayed(Duration.zero);

    final task = container
        .read(agentWorkspaceProvider.notifier)
        .startTask(goal: 'Update readme', profile: AgentTaskProfile.patch);
    final patch = container
        .read(patchProposalProvider.notifier)
        .propose(
          title: 'Update readme',
          agentTaskId: task.id,
          comparisonSummary: 'Small documentation update.',
          edits: const [
            ProposedFileEdit(
              path: 'README.md',
              type: ProposedFileEditType.modify,
              before: 'old\n',
              after: 'new\n',
            ),
          ],
        );

    final updatedTask = container.read(agentWorkspaceProvider).selectedTask;

    expect(patch.agentTaskId, task.id);
    expect(updatedTask?.mascotAlias, 'Benny');
    expect(updatedTask?.status, AgentTaskStatus.waitingForApproval);
    expect(updatedTask?.patchSetIds, contains(patch.id));
    expect(
      container.read(agentWorkspaceProvider.notifier).compareProposals(),
      contains('Small documentation update.'),
    );
  });

  test(
    'agent tasks pause and resume through the durable queue state',
    () async {
      final root = await _sampleProject();
      addTearDown(() => _delete(root));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final controller = container.read(agentWorkspaceProvider.notifier);
      final task = controller.startTask(
        goal: 'Pause this background-safe task',
        profile: AgentTaskProfile.investigate,
      );

      expect(controller.pauseTask(task.id), isTrue);
      expect(
        container.read(agentWorkspaceProvider).tasks.single.status,
        AgentTaskStatus.paused,
      );
      expect(container.read(agentWorkspaceProvider).runnableTasks, isEmpty);
      expect(controller.resumeTask(task.id), isTrue);
      expect(
        container.read(agentWorkspaceProvider).tasks.single.status,
        AgentTaskStatus.running,
      );
    },
  );

  test(
    'background execution claims bind one Studio request and cancel safely',
    () async {
      final root = await _sampleProject();
      addTearDown(() => _delete(root));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final controller = container.read(agentWorkspaceProvider.notifier);
      final task = controller.startTask(
        goal: 'Inspect background dispatch ownership',
        backgroundExecutionRequested: true,
      );

      expect(task.backgroundExecutionRequested, isTrue);
      final claimId = controller.claimBackgroundExecution(task.id);
      expect(claimId, isNotNull);
      expect(controller.claimBackgroundExecution(task.id), isNull);
      expect(
        controller.bindBackgroundExecutionRequest(
          task.id,
          claimId: claimId!,
          requestId: 'request-background-1',
        ),
        isTrue,
      );
      expect(
        container.read(agentWorkspaceProvider).tasks.single.activeRunId,
        'request-background-1',
      );

      controller.cancelTask(task.id);
      final cancelled = container.read(agentWorkspaceProvider).tasks.single;
      expect(cancelled.status, AgentTaskStatus.cancelled);
      expect(cancelled.activeRunId, isNull);
    },
  );

  test(
    'background execution claim releases without losing the queued task',
    () async {
      final root = await _sampleProject();
      addTearDown(() => _delete(root));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final controller = container.read(agentWorkspaceProvider.notifier);
      final task = controller.startTask(
        goal: 'Wait for the Studio runtime',
        backgroundExecutionRequested: true,
      );
      final claimId = controller.claimBackgroundExecution(task.id);

      expect(
        controller.releaseBackgroundExecutionClaim(task.id, claimId!),
        isTrue,
      );
      final released = container.read(agentWorkspaceProvider).tasks.single;
      expect(released.status, AgentTaskStatus.running);
      expect(released.activeRunId, isNull);
      expect(
        container.read(agentWorkspaceProvider).message,
        contains('waiting for the Studio runtime'),
      );
    },
  );

  test('current-workspace tasks queue behind an active mutable task', () async {
    final root = await _sampleProject();
    addTearDown(() => _delete(root));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(fileTreeProvider.notifier).openDirectory(root.path);

    final controller = container.read(agentWorkspaceProvider.notifier);
    final first = controller.startTask(
      goal: 'Prepare the first reviewed change',
      profile: AgentTaskProfile.patch,
    );
    final second = controller.startTask(
      goal: 'Prepare a separate reviewed change',
      profile: AgentTaskProfile.patch,
    );

    expect(first.status, AgentTaskStatus.running);
    expect(second.status, AgentTaskStatus.queued);
    expect(
      container.read(agentWorkspaceProvider).message,
      contains('queued until the current workspace is available'),
    );

    controller.completeTask(first.id, result: 'First change prepared.');

    final promoted = container
        .read(agentWorkspaceProvider)
        .tasks
        .firstWhere((task) => task.id == second.id);
    expect(promoted.status, AgentTaskStatus.running);
    expect(
      container.read(agentWorkspaceProvider).message,
      contains('started from the queue'),
    );
  });

  test(
    'pausing a current-workspace owner promotes its oldest queued follower',
    () async {
      final root = await _sampleProject();
      addTearDown(() => _delete(root));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      final controller = container.read(agentWorkspaceProvider.notifier);

      final first = controller.startTask(
        goal: 'Own the mutable workspace',
        backgroundExecutionRequested: true,
      );
      final second = controller.startTask(
        goal: 'Wait first in line',
        backgroundExecutionRequested: true,
      );
      final third = controller.startTask(
        goal: 'Wait second in line',
        backgroundExecutionRequested: true,
      );

      expect(controller.pauseTask(first.id), isTrue);
      final tasks = container.read(agentWorkspaceProvider).tasks;
      expect(
        tasks.firstWhere((task) => task.id == first.id).status,
        AgentTaskStatus.paused,
      );
      expect(
        tasks.firstWhere((task) => task.id == second.id).status,
        AgentTaskStatus.running,
      );
    expect(
      tasks.firstWhere((task) => task.id == third.id).status,
      AgentTaskStatus.queued,
    );
    expect(
      container.read(agentWorkspaceProvider).message,
      contains('started from the queue'),
    );
    expect(controller.claimBackgroundExecution(second.id), isNotNull);
    },
  );

  test('a resumed task returns to the durable queue tail', () async {
    final root = await _sampleProject();
    addTearDown(() => _delete(root));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(fileTreeProvider.notifier).openDirectory(root.path);
    final controller = container.read(agentWorkspaceProvider.notifier);

    final first = controller.startTask(goal: 'Original workspace owner');
    final second = controller.startTask(goal: 'Already waiting');
    expect(controller.pauseTask(first.id), isTrue);
    final third = controller.startTask(goal: 'Wait behind the promoted owner');
    expect(controller.resumeTask(first.id), isTrue);

    final queuedThird = container
        .read(agentWorkspaceProvider)
        .tasks
        .firstWhere((task) => task.id == third.id);
    final resumedFirst = container
        .read(agentWorkspaceProvider)
        .tasks
        .firstWhere((task) => task.id == first.id);
    expect(queuedThird.status, AgentTaskStatus.queued);
    expect(resumedFirst.status, AgentTaskStatus.queued);
    expect(resumedFirst.queuedAt, isNotNull);
    expect(queuedThird.queuedAt, isNotNull);
    expect(resumedFirst.queuedAt!.isAfter(queuedThird.queuedAt!), isTrue);
    expect(
      AgentTask.fromJson(resumedFirst.toJson())?.queuedAt,
      resumedFirst.queuedAt,
    );

    controller.completeTask(second.id);

    final tasks = container.read(agentWorkspaceProvider).tasks;
    expect(
      tasks.firstWhere((task) => task.id == third.id).status,
      AgentTaskStatus.running,
    );
    expect(
      tasks.firstWhere((task) => task.id == first.id).status,
      AgentTaskStatus.queued,
    );
  });

  test(
    'cancelling a queued task does not promote concurrent workspace work',
    () async {
      final root = await _sampleProject();
      addTearDown(() => _delete(root));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      final controller = container.read(agentWorkspaceProvider.notifier);

      final owner = controller.startTask(goal: 'Current workspace owner');
      final cancelled = controller.startTask(goal: 'Cancel this queued task');
      final stillQueued = controller.startTask(goal: 'Must remain queued');
      controller.cancelTask(cancelled.id);

      final tasks = container.read(agentWorkspaceProvider).tasks;
      expect(
        tasks.firstWhere((task) => task.id == owner.id).status,
        AgentTaskStatus.running,
      );
      expect(
        tasks.firstWhere((task) => task.id == cancelled.id).status,
        AgentTaskStatus.cancelled,
      );
      expect(
        tasks.firstWhere((task) => task.id == stillQueued.id).status,
        AgentTaskStatus.queued,
      );
    },
  );

  test('current-workspace queue has a bounded pending-task limit', () async {
    final root = await _sampleProject();
    addTearDown(() => _delete(root));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(fileTreeProvider.notifier).openDirectory(root.path);
    final controller = container.read(agentWorkspaceProvider.notifier);
    controller.startTask(goal: 'Active workspace owner');
    for (
      var index = 0;
      index < AgentWorkspaceController.maxQueuedCurrentWorkspaceTasks;
      index++
    ) {
      controller.startTask(goal: 'Queued task $index');
    }

    expect(
      () => controller.startTask(goal: 'One task too many'),
      throwsA(isA<StateError>()),
    );
  });

  test('queued current-workspace tasks explain their scheduler wait', () {
    final summary = StudioTaskSummary.fromTask(
      AgentTask(
        id: 'queued',
        mascotAlias: 'Benny',
        profile: AgentTaskProfile.patch,
        status: AgentTaskStatus.queued,
        goal: 'Prepare a reviewed patch',
        createdAt: DateTime(2026),
      ),
    );

    expect(summary.statusLabel, 'Queued');
    expect(summary.detail, 'Waiting for current workspace availability');
  });
}

Future<Directory> _sampleProject() async {
  final root = await Directory.systemTemp.createTemp('agent_ws_v4_');
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
