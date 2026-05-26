import '../state/ai_context_provider.dart';

enum WorkspaceLifecycleStatus {
  empty,
  loading,
  indexing,
  ready,
  error,
  cancelled,
}

class WorkspaceIndexProgress {
  final String label;
  final int files;
  final int directories;
  final DateTime updatedAt;

  const WorkspaceIndexProgress({
    required this.label,
    this.files = 0,
    this.directories = 0,
    required this.updatedAt,
  });
}

class WorkspaceContextState {
  final String? rootPath;
  final WorkspaceLifecycleStatus status;
  final WorkspaceIndexProgress? fileIndexProgress;
  final WorkspaceIndexProgress? lsdfProgress;
  final LsdfIndexStatus lsdfStatus;
  final String? message;
  final String? error;
  final DateTime? refreshedAt;
  final bool cancelRequested;

  const WorkspaceContextState({
    this.rootPath,
    this.status = WorkspaceLifecycleStatus.empty,
    this.fileIndexProgress,
    this.lsdfProgress,
    this.lsdfStatus = LsdfIndexStatus.idle,
    this.message,
    this.error,
    this.refreshedAt,
    this.cancelRequested = false,
  });

  bool get isBusy =>
      status == WorkspaceLifecycleStatus.loading ||
      status == WorkspaceLifecycleStatus.indexing;

  WorkspaceContextState copyWith({
    String? rootPath,
    WorkspaceLifecycleStatus? status,
    WorkspaceIndexProgress? fileIndexProgress,
    WorkspaceIndexProgress? lsdfProgress,
    LsdfIndexStatus? lsdfStatus,
    Object? message = _sentinel,
    Object? error = _sentinel,
    Object? refreshedAt = _sentinel,
    bool? cancelRequested,
  }) {
    return WorkspaceContextState(
      rootPath: rootPath ?? this.rootPath,
      status: status ?? this.status,
      fileIndexProgress: fileIndexProgress ?? this.fileIndexProgress,
      lsdfProgress: lsdfProgress ?? this.lsdfProgress,
      lsdfStatus: lsdfStatus ?? this.lsdfStatus,
      message: identical(message, _sentinel)
          ? this.message
          : message as String?,
      error: identical(error, _sentinel) ? this.error : error as String?,
      refreshedAt: identical(refreshedAt, _sentinel)
          ? this.refreshedAt
          : refreshedAt as DateTime?,
      cancelRequested: cancelRequested ?? this.cancelRequested,
    );
  }
}

const _sentinel = Object();
