class GitTaskWorktree {
  final String repositoryRoot;
  final String path;
  final String branch;
  final String baseRevision;

  const GitTaskWorktree({
    required this.repositoryRoot,
    required this.path,
    required this.branch,
    required this.baseRevision,
  });
}

/// A reviewable transfer from an isolated task worktree to its source branch.
/// This does not contain a shell command and is deliberately invalidated if
/// the source branch or either worktree has changed since preview.
class GitWorktreeHandoffPreview {
  final String repositoryRoot;
  final String worktreePath;
  final String branch;
  final String baseRevision;
  final String summary;
  final String diffPreview;
  final List<String> changedPaths;
  final int commitCount;
  final bool canApply;
  final String? blockedReason;

  const GitWorktreeHandoffPreview({
    required this.repositoryRoot,
    required this.worktreePath,
    required this.branch,
    required this.baseRevision,
    required this.summary,
    this.diffPreview = '',
    this.changedPaths = const [],
    this.commitCount = 0,
    this.canApply = true,
    this.blockedReason,
  });
}

class GitWorktreeHandoffResult {
  final GitWorktreeHandoffPreview preview;
  final bool applied;
  final String evidence;

  const GitWorktreeHandoffResult({
    required this.preview,
    required this.applied,
    required this.evidence,
  });
}
