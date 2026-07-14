import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_run.dart';
import '../models/workspace_session.dart';
import 'agent_run_provider.dart';
import 'file_tree_provider.dart';
import 'git_provider.dart';
import '../services/macos_workspace_access.dart';
import 'project_profile_provider.dart';

class WorkspaceSessionController extends Notifier<WorkspaceSessionState> {
  @override
  WorkspaceSessionState build() => const WorkspaceSessionState();

  Future<WorkspaceBindingResult> openWorkspaceAndBindAgent(
    String path, {
    bool userSelected = false,
  }) async {
    state = state.copyWith(status: WorkspaceSessionStatus.opening, error: null);
    ref
        .read(agentRunProvider.notifier)
        .addEvent(
          AgentRunKind.backgroundTask,
          AgentRunEventType.contextPrepared,
          'Opening workspace',
          metadata: {'path': path},
        );

    final access = userSelected
        ? await ref
              .read(macosWorkspaceAccessProvider)
              .grantUserSelectedWorkspace(path)
        : await ref.read(macosWorkspaceAccessProvider).resumeWorkspace(path);
    if (!access.granted) {
      final message =
          access.message ??
          'Workspace access was not granted. Reopen the project folder and try again.';
      state = state.copyWith(
        status: WorkspaceSessionStatus.failed,
        rootPath: null,
        agentWorkingDir: null,
        lastOpenResult: null,
        error: message,
      );
      return WorkspaceBindingResult(success: false, message: message);
    }
    final workspacePath = access.path;

    final openResult = await ref
        .read(fileTreeProvider.notifier)
        .openDirectory(workspacePath);
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
      rootPath: workspacePath,
      agentWorkingDir: workspacePath,
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
            'rootPath': workspacePath,
            'agentWorkingDir': workspacePath,
            'isBound': 'true',
          },
        );
    return WorkspaceBindingResult(
      success: true,
      rootPath: workspacePath,
      agentWorkingDir: workspacePath,
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
