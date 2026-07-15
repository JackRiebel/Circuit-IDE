import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/models/agent_workspace.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/state/agent_workspace_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/performance_budget_fixture.dart';

void main() {
  test(
    'history indexes page 5,000 tasks and hydrate a 1,000-turn thread',
    () async {
      final root = await Directory.systemTemp.createTemp('history_scale_');
      addTearDown(() => _delete(root));
      final taskStore = AgentWorkspaceStore(
        baseDir: p.join(root.path, 'tasks'),
      );
      final threadStore = StudioThreadStore(
        baseDir: p.join(root.path, 'threads'),
      );
      final project = Directory(p.join(root.path, 'project'));
      await project.create();
      final timestamp = DateTime.utc(2026, 7, 11);
      final tasks = [
        for (var index = 0; index < 5000; index++)
          AgentTask(
            id: 'task-$index',
            mascotAlias: 'Benny',
            profile: AgentTaskProfile.investigate,
            goal: 'Scale task $index',
            createdAt: timestamp.add(Duration(seconds: index)),
          ),
      ];
      final turns = [
        for (var index = 0; index < 1000; index++)
          StudioTurn(
            id: 'turn-$index',
            threadId: 'thread-scale',
            requestId: 'request-$index',
            userMessageId: 'message-$index',
            prompt: 'Task $index',
            model: 'test-model',
            contextSummary: const StudioContextSummary(projectLabel: 'Scale'),
            status: StudioTurnStatus.completed,
            createdAt: timestamp.add(Duration(seconds: index)),
            updatedAt: timestamp.add(Duration(seconds: index)),
            completedAt: timestamp.add(Duration(seconds: index)),
          ),
      ];
      await taskStore.save(project.path, tasks);
      await threadStore.save(project.path, [
        StudioThread(
          id: 'thread-scale',
          title: 'Scale transcript',
          turns: turns,
          createdAt: timestamp,
          updatedAt: timestamp.add(const Duration(seconds: 999)),
        ),
      ]);
      final threadSummaryIndex = File(
        threadStore.summaryIndexPath(project.path),
      );
      await threadSummaryIndex.writeAsString(
        [
          jsonEncode({
            'kind': 'circuit.studio-thread-summary-index',
            'version': 1,
            'totalCount': 1000,
          }),
          for (var index = 0; index < 1000; index++)
            jsonEncode(
              StudioThread(
                id: 'thread-summary-$index',
                title: 'Scale conversation $index',
                createdAt: timestamp.add(Duration(seconds: index)),
                updatedAt: timestamp.add(Duration(seconds: index)),
              ).toJson(),
            ),
        ].join('\n'),
      );

      final budgets = await PerformanceBudgetFixture.load();
      late AgentTaskSummaryPage page;
      late StudioThreadSummaryPage threadPage;
      late StudioThread? hydrated;
      final taskPageWatch = Stopwatch()..start();
      page = await taskStore.loadSummaryPage(project.path, limit: 24);
      taskPageWatch.stop();
      budgets.expectDuration('task_summary_page_5000', taskPageWatch.elapsed);

      final threadPageWatch = Stopwatch()..start();
      threadPage = await threadStore.loadSummaryPage(project.path, limit: 24);
      threadPageWatch.stop();
      budgets.expectDuration(
        'thread_summary_page_1000',
        threadPageWatch.elapsed,
      );

      final hydrationWatch = Stopwatch()..start();
      hydrated = await threadStore.loadThread(project.path, 'thread-scale');
      hydrationWatch.stop();
      budgets.expectDuration('thread_hydration_1000', hydrationWatch.elapsed);

      expect(page.totalCount, 5000);
      expect(page.tasks, hasLength(24));
      expect(page.hasMore, isTrue);
      expect(threadPage.totalCount, 1000);
      expect(threadPage.threads, hasLength(24));
      expect(threadPage.threads, everyElement(isA<StudioThread>()));
      expect(
        threadPage.threads.every((thread) => !thread.detailLoaded),
        isTrue,
      );
      expect(hydrated?.detailLoaded, isTrue);
      expect(hydrated?.turns, hasLength(1000));
    },
  );

  test('500 projects page metadata without opening full histories', () async {
    final root = await Directory.systemTemp.createTemp('history_projects_');
    addTearDown(() => _delete(root));
    final taskStore = AgentWorkspaceStore(baseDir: p.join(root.path, 'tasks'));
    final threadStore = StudioThreadStore(
      baseDir: p.join(root.path, 'threads'),
    );
    final timestamp = DateTime.utc(2026, 7, 11);
    final projects = [
      for (var index = 0; index < 500; index++)
        Directory(p.join(root.path, 'project-$index')),
    ];
    for (var index = 0; index < projects.length; index++) {
      final project = projects[index];
      await project.create();
      final taskIndex = File(taskStore.summaryIndexPath(project.path));
      final threadIndex = File(threadStore.summaryIndexPath(project.path));
      await taskIndex.parent.create(recursive: true);
      await threadIndex.parent.create(recursive: true);
      await taskIndex.writeAsString(
        [
          jsonEncode({
            'kind': 'circuit.agent-task-summary-index',
            'version': 1,
            'totalCount': 10,
          }),
          for (var row = 0; row < 10; row++)
            jsonEncode(
              AgentTask(
                id: 'task-$index-$row',
                mascotAlias: 'Benny',
                profile: AgentTaskProfile.investigate,
                goal: 'Project $index task $row',
                createdAt: timestamp,
              ).toJson(),
            ),
        ].join('\n'),
      );
      await threadIndex.writeAsString(
        [
          jsonEncode({
            'kind': 'circuit.studio-thread-summary-index',
            'version': 1,
            'totalCount': 10,
          }),
          for (var row = 0; row < 10; row++)
            jsonEncode(
              StudioThread(
                id: 'thread-$index-$row',
                title: 'Project $index conversation $row',
                createdAt: timestamp,
                updatedAt: timestamp,
              ).toJson(),
            ),
        ].join('\n'),
      );
    }
    final stopwatch = Stopwatch()..start();
    for (final project in projects) {
      final taskPage = await taskStore.loadSummaryPage(project.path, limit: 2);
      final threadPage = await threadStore.loadSummaryPage(
        project.path,
        limit: 2,
      );
      expect(taskPage.tasks, hasLength(2));
      expect(threadPage.threads, hasLength(2));
    }
    stopwatch.stop();
    final budgets = await PerformanceBudgetFixture.load();
    budgets.expectDuration('project_metadata_pages_500', stopwatch.elapsed);
  });
}

Future<void> _delete(Directory directory) async {
  try {
    if (await directory.exists()) await directory.delete(recursive: true);
  } catch (_) {}
}
