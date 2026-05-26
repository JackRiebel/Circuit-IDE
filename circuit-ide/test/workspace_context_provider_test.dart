import 'dart:io';

import 'package:circuit_ide/models/workspace_context.dart';
import 'package:circuit_ide/models/agent_run.dart';
import 'package:circuit_ide/state/agent_run_provider.dart';
import 'package:circuit_ide/state/workspace_context_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'WorkspaceContextController indexes files and prepares L-SDF map',
    () async {
      final root = await Directory.systemTemp.createTemp('workspace_context_');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      await File(
        p.join(root.path, 'main.dart'),
      ).writeAsString('void main() {}\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(workspaceContextProvider.notifier)
          .openWorkspace(root.path);

      final state = container.read(workspaceContextProvider);
      expect(state.status, WorkspaceLifecycleStatus.ready);
      expect(state.fileIndexProgress?.files, 1);
      expect(state.lsdfProgress?.files, 1);
      expect(await File(p.join(root.path, 'project.lsdf')).exists(), isTrue);
      expect(
        container
            .read(agentRunProvider)
            .recentRuns
            .any((run) => run.kind == AgentRunKind.backgroundTask),
        isTrue,
      );
    },
  );

  test('WorkspaceContextController exposes cancelled health state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(workspaceContextProvider.notifier).cancel();

    final state = container.read(workspaceContextProvider);
    expect(state.status, WorkspaceLifecycleStatus.cancelled);
    expect(state.cancelRequested, isTrue);
    expect(state.message, 'Workspace context cancelled');
    expect(state.refreshedAt, isNotNull);
  });
}
