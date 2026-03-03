enum DiffType { unchanged, added, removed, modified }

class DiffLine {
  final int? leftLineNum;
  final int? rightLineNum;
  final String? leftContent;
  final String? rightContent;
  final DiffType type;

  const DiffLine({
    this.leftLineNum,
    this.rightLineNum,
    this.leftContent,
    this.rightContent,
    required this.type,
  });
}

class DiffResult {
  final String leftTitle;
  final String rightTitle;
  final List<DiffLine> lines;
  final int additions;
  final int deletions;
  final int modifications;

  const DiffResult({
    required this.leftTitle,
    required this.rightTitle,
    required this.lines,
    required this.additions,
    required this.deletions,
    required this.modifications,
  });

  int get totalChanges => additions + deletions + modifications;
}

/// Stored diff data for a diff tab.
class DiffData {
  final String leftTitle;
  final String rightTitle;
  final String leftContent;
  final String rightContent;

  const DiffData({
    required this.leftTitle,
    required this.rightTitle,
    required this.leftContent,
    required this.rightContent,
  });
}
