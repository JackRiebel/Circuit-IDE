enum WorkspaceOpenFailureReason { missing, notDirectory, unreadable, unknown }

enum RecentProjectStatus { available, missing, unreadable, unknown }

class WorkspaceOpenResult {
  final String path;
  final bool success;
  final WorkspaceOpenFailureReason? failureReason;
  final String? message;

  const WorkspaceOpenResult._({
    required this.path,
    required this.success,
    this.failureReason,
    this.message,
  });

  const WorkspaceOpenResult.success(String path)
    : this._(path: path, success: true);

  const WorkspaceOpenResult.failure({
    required String path,
    required WorkspaceOpenFailureReason reason,
    required String message,
  }) : this._(
         path: path,
         success: false,
         failureReason: reason,
         message: message,
       );

  RecentProjectStatus get recentProjectStatus {
    return switch (failureReason) {
      null => RecentProjectStatus.available,
      WorkspaceOpenFailureReason.missing => RecentProjectStatus.missing,
      WorkspaceOpenFailureReason.unreadable => RecentProjectStatus.unreadable,
      WorkspaceOpenFailureReason.notDirectory => RecentProjectStatus.missing,
      WorkspaceOpenFailureReason.unknown => RecentProjectStatus.unknown,
    };
  }
}
