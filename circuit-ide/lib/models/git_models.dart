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

  const GitFileChange({
    required this.path,
    required this.type,
    this.oldPath,
  });
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
