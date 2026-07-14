/// Shared, deterministic layout rules for generated XLSX tables.
///
/// The workbook writer and structural preview must use the same column and
/// wrapping model. Otherwise a preview could report a safe table while the
/// emitted XML asks Excel for a row height it cannot represent.
abstract final class ArtifactWorkbookLayout {
  static const minimumColumnContentWidth = 10;
  static const maximumColumnContentWidth = 42;
  static const columnPadding = 2.0;
  static const rowLineHeightPoints = 15.0;
  static const maximumRowHeightPoints = 409.5;
  static const maximumMeasuredRows = 80;

  static int get maximumRowLines =>
      (maximumRowHeightPoints / rowLineHeightPoints).floor();

  static double columnWidth(List<List<String>> rows, int columnIndex) {
    var width = minimumColumnContentWidth;
    for (final row in rows.take(maximumMeasuredRows)) {
      if (columnIndex >= row.length) continue;
      final length = row[columnIndex].length;
      if (length > width) width = length;
    }
    return width
            .clamp(minimumColumnContentWidth, maximumColumnContentWidth)
            .toDouble() +
        columnPadding;
  }

  static bool requiresWrap(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim().length >
      maximumColumnContentWidth;

  static int requiredRowLineCount(List<List<String>> rows, List<String> row) {
    var maximum = 1;
    for (var columnIndex = 0; columnIndex < row.length; columnIndex++) {
      final capacity = (columnWidth(rows, columnIndex) - columnPadding)
          .floor()
          .clamp(minimumColumnContentWidth, maximumColumnContentWidth);
      final lineCount = wrappedLineCount(row[columnIndex], capacity);
      if (lineCount > maximum) maximum = lineCount;
    }
    return maximum;
  }

  static int wrappedLineCount(String value, int capacity) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return 1;
    var lineCount = 1;
    var used = 0;
    for (final word in normalized.split(' ')) {
      final required = word.length + (used == 0 ? 0 : 1);
      if (used + required <= capacity) {
        used += required;
        continue;
      }
      if (word.length <= capacity) {
        lineCount += 1;
        used = word.length;
        continue;
      }
      if (used > 0) {
        lineCount += 1;
        used = 0;
      }
      final fullLines = word.length ~/ capacity;
      final remainder = word.length % capacity;
      lineCount += remainder == 0 ? fullLines - 1 : fullLines;
      used = remainder == 0 ? capacity : remainder;
    }
    return lineCount;
  }

  /// Caps emitted XML below Excel's 409.5-point row-height maximum. The
  /// caller must still retain the overflow as a readiness gap rather than
  /// presenting the clipped result as customer-ready.
  static double emittedRowHeightPoints(int requiredLineCount) {
    final safeLines = requiredLineCount.clamp(1, maximumRowLines);
    return safeLines * rowLineHeightPoints;
  }

  static WorkbookTableLayoutRisk assess(List<List<String>> rows) {
    final oversizedRows = <int>[];
    var hasUnbreakableColumnValue = false;
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (requiredRowLineCount(rows, row) > maximumRowLines) {
        // Workbook row numbers are one-based in XLSX and in the user-facing
        // preview, so the persisted review evidence should use the same form.
        oversizedRows.add(rowIndex + 1);
      }
      if (row.any(_hasUnbreakableColumnValue)) {
        hasUnbreakableColumnValue = true;
      }
    }
    return WorkbookTableLayoutRisk(
      rowNumbersExceedingMaximumHeight: oversizedRows,
      hasUnbreakableColumnValue: hasUnbreakableColumnValue,
    );
  }

  static bool _hasUnbreakableColumnValue(String value) => value
      .split(RegExp(r'\s+'))
      .any((token) => token.trim().length > maximumColumnContentWidth);
}

class WorkbookTableLayoutRisk {
  final List<int> rowNumbersExceedingMaximumHeight;
  final bool hasUnbreakableColumnValue;

  const WorkbookTableLayoutRisk({
    required this.rowNumbersExceedingMaximumHeight,
    required this.hasUnbreakableColumnValue,
  });

  bool get hasRowHeightOverflow => rowNumbersExceedingMaximumHeight.isNotEmpty;

  bool get hasOverflow => hasRowHeightOverflow || hasUnbreakableColumnValue;
}
