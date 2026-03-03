import 'dart:math' as math;

import '../models/diff_models.dart';

/// LCS-based diff engine for line-level comparison.
class DiffEngine {
  /// Compute a diff between two strings.
  static DiffResult diff({
    required String leftContent,
    required String rightContent,
    String leftTitle = 'Original',
    String rightTitle = 'Modified',
  }) {
    final leftLines = leftContent.split('\n');
    final rightLines = rightContent.split('\n');

    // Compute LCS table
    final lcs = _computeLcs(leftLines, rightLines);

    // Backtrack to produce diff lines
    final diffLines = <DiffLine>[];
    int i = leftLines.length;
    int j = rightLines.length;

    final result = <DiffLine>[];

    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && leftLines[i - 1] == rightLines[j - 1]) {
        result.add(DiffLine(
          leftLineNum: i,
          rightLineNum: j,
          leftContent: leftLines[i - 1],
          rightContent: rightLines[j - 1],
          type: DiffType.unchanged,
        ));
        i--;
        j--;
      } else if (j > 0 && (i == 0 || lcs[i][j - 1] >= lcs[i - 1][j])) {
        result.add(DiffLine(
          rightLineNum: j,
          rightContent: rightLines[j - 1],
          type: DiffType.added,
        ));
        j--;
      } else if (i > 0) {
        result.add(DiffLine(
          leftLineNum: i,
          leftContent: leftLines[i - 1],
          type: DiffType.removed,
        ));
        i--;
      }
    }

    // Reverse since we built it backwards
    final reversed = result.reversed.toList();

    // Post-process: merge adjacent remove+add pairs into modifications
    int additions = 0;
    int deletions = 0;
    int modifications = 0;

    int idx = 0;
    while (idx < reversed.length) {
      final line = reversed[idx];
      // Check for adjacent remove+add pair (modification)
      if (line.type == DiffType.removed &&
          idx + 1 < reversed.length &&
          reversed[idx + 1].type == DiffType.added) {
        diffLines.add(DiffLine(
          leftLineNum: line.leftLineNum,
          rightLineNum: reversed[idx + 1].rightLineNum,
          leftContent: line.leftContent,
          rightContent: reversed[idx + 1].rightContent,
          type: DiffType.modified,
        ));
        modifications++;
        idx += 2;
      } else {
        diffLines.add(line);
        if (line.type == DiffType.added) additions++;
        if (line.type == DiffType.removed) deletions++;
        idx++;
      }
    }

    return DiffResult(
      leftTitle: leftTitle,
      rightTitle: rightTitle,
      lines: diffLines,
      additions: additions,
      deletions: deletions,
      modifications: modifications,
    );
  }

  /// Compute LCS length table using dynamic programming.
  static List<List<int>> _computeLcs(
    List<String> left,
    List<String> right,
  ) {
    final m = left.length;
    final n = right.length;
    final table = List.generate(m + 1, (_) => List.filled(n + 1, 0));

    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (left[i - 1] == right[j - 1]) {
          table[i][j] = table[i - 1][j - 1] + 1;
        } else {
          table[i][j] = math.max(table[i - 1][j], table[i][j - 1]);
        }
      }
    }

    return table;
  }
}
