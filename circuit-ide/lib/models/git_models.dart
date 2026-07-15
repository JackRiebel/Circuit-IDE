class GitStatus {
  final List<GitFileChange> staged;
  final List<GitFileChange> unstaged;
  final List<GitFileChange> untracked;
  final String branch;
  final String? upstream;
  final int ahead;
  final int behind;

  const GitStatus({
    this.staged = const [],
    this.unstaged = const [],
    this.untracked = const [],
    this.branch = '',
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
  });

  bool get isClean => staged.isEmpty && unstaged.isEmpty && untracked.isEmpty;
  int get totalChanges => staged.length + unstaged.length + untracked.length;
}

class GitFileChange {
  final String path;
  final GitChangeType type;
  final String? oldPath;

  const GitFileChange({required this.path, required this.type, this.oldPath});
}

enum GitChangeType {
  added('A', 'Added'),
  modified('M', 'Modified'),
  deleted('D', 'Deleted'),
  renamed('R', 'Renamed'),
  copied('C', 'Copied'),
  untracked('?', 'Untracked');

  const GitChangeType(this.code, this.label);
  final String code;
  final String label;

  static GitChangeType fromCode(String code) {
    return GitChangeType.values.firstWhere(
      (t) => t.code == code,
      orElse: () => GitChangeType.modified,
    );
  }
}

class GitCommit {
  final String hash;
  final String shortHash;
  final String message;
  final String author;
  final DateTime date;

  const GitCommit({
    required this.hash,
    required this.shortHash,
    required this.message,
    required this.author,
    required this.date,
  });
}

enum GitMutationType {
  stage,
  unstage,
  discardFile,
  discardHunk,
  commit,
  createBranch,
  push,
}

/// A user-reviewable Git operation. The UI must present this before calling
/// the corresponding mutation; it contains only operational evidence, never
/// credentials or a shell command string.
class GitMutationPreview {
  final GitMutationType type;
  final String title;
  final String summary;
  final List<String> affectedPaths;
  final String diffPreview;
  final String undoGuidance;
  final bool requiresConfirmation;
  final bool canApply;
  final String? blockedReason;
  final String? commitMessage;
  final String? branchName;
  final GitDiffHunk? hunk;

  const GitMutationPreview({
    required this.type,
    required this.title,
    required this.summary,
    this.affectedPaths = const [],
    this.diffPreview = '',
    required this.undoGuidance,
    this.requiresConfirmation = true,
    this.canApply = true,
    this.blockedReason,
    this.commitMessage,
    this.branchName,
    this.hunk,
  });
}

class GitMutationResult {
  final GitMutationPreview preview;
  final bool applied;
  final String evidence;
  final String undoGuidance;

  const GitMutationResult({
    required this.preview,
    required this.applied,
    required this.evidence,
    required this.undoGuidance,
  });
}

/// A stable, reviewable hunk from an unstaged text diff.
class GitDiffHunk {
  final String path;
  final String header;
  final String patch;

  const GitDiffHunk({
    required this.path,
    required this.header,
    required this.patch,
  });

  String get label => '$path · $header';
}
