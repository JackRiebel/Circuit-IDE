import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_run.dart';
import '../models/workspace_session.dart';
import 'agent_run_provider.dart';
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

    await ref.read(gitProvider.notifier).refresh();
    await ref.read(projectProfileProvider.notifier).refresh();

    state = WorkspaceSessionState(
      rootPath: path,
      agentWorkingDir: path,
      status: WorkspaceSessionStatus.ready,
      lastOpenResult: openResult,
      lastBoundAt: DateTime.now(),
      error: null,
    );
    ref
        .read(agentRunProvider.notifier)
        .addEvent(
          AgentRunKind.backgroundTask,
          AgentRunEventType.contextPrepared,
          'Workspace bound',
          metadata: {
            'rootPath': path,
            'agentWorkingDir': path,
            'isBound': 'true',
          },
        );
    return WorkspaceBindingResult(
      success: true,
      rootPath: path,
      agentWorkingDir: path,
      message: 'Workspace ready.',
      openResult: openResult,
    );
  }

  void syncFromCurrentWorkspace() {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    state = WorkspaceSessionState(
      rootPath: rootPath,
      agentWorkingDir: rootPath,
      status: rootPath == null
          ? WorkspaceSessionStatus.closed
          : WorkspaceSessionStatus.ready,
      lastBoundAt: DateTime.now(),
      error: null,
    );
  }
}

final workspaceSessionProvider =
    NotifierProvider<WorkspaceSessionController, WorkspaceSessionState>(
      WorkspaceSessionController.new,
    );
