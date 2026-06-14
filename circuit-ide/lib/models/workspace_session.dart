import 'workspace_open_result.dart';

enum WorkspaceSessionStatus { closed, opening, ready, degraded, failed }

class WorkspaceBindingResult {
  final bool success;
  final String? rootPath;
  final String? agentWorkingDir;
  final String? message;
  final WorkspaceOpenResult? openResult;

  const WorkspaceBindingResult({
    required this.success,
    this.rootPath,
    this.agentWorkingDir,
    this.message,
    this.openResult,
  });
}

class WorkspaceSessionState {
  final String? rootPath;
  final String? agentWorkingDir;
  final WorkspaceSessionStatus status;
  final WorkspaceOpenResult? lastOpenResult;
  final DateTime? lastBoundAt;
  final String? error;

  const WorkspaceSessionState({
    this.rootPath,
    this.agentWorkingDir,
    this.status = WorkspaceSessionStatus.closed,
    this.lastOpenResult,
    this.lastBoundAt,
    this.error,
  });

  bool get hasWorkspace => rootPath != null;
  bool get isBound =>
      rootPath != null &&
      agentWorkingDir != null &&
      rootPath == agentWorkingDir;
  bool get canCode => status == WorkspaceSessionStatus.ready && isBound;

  WorkspaceSessionState copyWith({
    Object? rootPath = _sentinel,
    Object? agentWorkingDir = _sentinel,
    WorkspaceSessionStatus? status,
    Object? lastOpenResult = _sentinel,
    Object? lastBoundAt = _sentinel,
    Object? error = _sentinel,
  }) {
    return WorkspaceSessionState(
      rootPath: identical(rootPath, _sentinel)
          ? this.rootPath
          : rootPath as String?,
      agentWorkingDir: identical(agentWorkingDir, _sentinel)
          ? this.agentWorkingDir
          : agentWorkingDir as String?,
      status: status ?? this.status,
      lastOpenResult: identical(lastOpenResult, _sentinel)
          ? this.lastOpenResult
          : lastOpenResult as WorkspaceOpenResult?,
      lastBoundAt: identical(lastBoundAt, _sentinel)
          ? this.lastBoundAt
          : lastBoundAt as DateTime?,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

const _sentinel = Object();
