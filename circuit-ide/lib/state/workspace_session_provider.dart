import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_run.dart';
import '../models/workspace_session.dart';
import 'agent_run_provider.dart';
import 'connection_provider.dart';
import 'file_tree_provider.dart';
import 'git_provider.dart';
import 'project_profile_provider.dart';

class WorkspaceSessionController extends Notifier<WorkspaceSessionState> {
  @override
  WorkspaceSessionState build() => const WorkspaceSessionState();

  Future<WorkspaceBindingResult> openWorkspaceAndBindAgent(String path) async {
    state = state.copyWith(status: WorkspaceSessionStatus.opening, error: null);
    ref
        .read(agentRunProvider.notifier)
        .addEvent(
          AgentRunKind.backgroundTask,
          AgentRunEventType.contextPrepared,
          'Opening workspace',
          metadata: {'path': path},
        );

    final openResult = await ref
        .read(fileTreeProvider.notifier)
        .openDirectory(path);
    if (!openResult.success) {
      state = state.copyWith(
        status: WorkspaceSessionStatus.failed,
        rootPath: null,
        agentWorkingDir: null,
        lastOpenResult: openResult,
        error: openResult.message,
      );
      return WorkspaceBindingResult(
        success: false,
        message: openResult.message,
        openResult: openResult,
      );
    }

    await ref.read(agentServiceProvider).updateWorkingDir(path);
    await ref.read(gitProvider.notifier).refresh();
    await ref.read(projectProfileProvider.notifier).refresh();

    final agentWorkingDir = ref.read(agentServiceProvider).state.workingDir;
    final isBound = agentWorkingDir == path;
    state = WorkspaceSessionState(
      rootPath: path,
      agentWorkingDir: agentWorkingDir,
      status: isBound
          ? WorkspaceSessionStatus.ready
          : WorkspaceSessionStatus.degraded,
      lastOpenResult: openResult,
      lastBoundAt: DateTime.now(),
      error: isBound ? null : 'Agent working directory did not bind.',
    );
    ref
        .read(agentRunProvider.notifier)
        .addEvent(
          AgentRunKind.backgroundTask,
          AgentRunEventType.contextPrepared,
          isBound ? 'Workspace bound' : 'Workspace binding degraded',
          metadata: {
            'rootPath': path,
            'agentWorkingDir': agentWorkingDir,
            'isBound': isBound.toString(),
          },
        );
    return WorkspaceBindingResult(
      success: isBound,
      rootPath: path,
      agentWorkingDir: agentWorkingDir,
      message: isBound ? 'Workspace ready.' : state.error,
      openResult: openResult,
    );
  }

  void syncFromCurrentWorkspace() {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    final agentWorkingDir = ref.read(agentServiceProvider).state.workingDir;
    state = WorkspaceSessionState(
      rootPath: rootPath,
      agentWorkingDir: agentWorkingDir,
      status: rootPath == null
          ? WorkspaceSessionStatus.closed
          : rootPath == agentWorkingDir
          ? WorkspaceSessionStatus.ready
          : WorkspaceSessionStatus.degraded,
      lastBoundAt: DateTime.now(),
      error: rootPath == null || rootPath == agentWorkingDir
          ? null
          : 'Agent is not bound to the selected workspace.',
    );
  }
}

final workspaceSessionProvider =
    NotifierProvider<WorkspaceSessionController, WorkspaceSessionState>(
      WorkspaceSessionController.new,
    );
