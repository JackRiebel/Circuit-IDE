import 'dart:convert';

import '../models/artifact_document.dart';
import '../models/artifact_template.dart';
import '../models/generated_artifact.dart';
import 'artifact_workbook_layout.dart';

/// A deterministic, durable structural review surface for native artifacts.
///
/// This is deliberately not represented as a Word, PDF, or Excel rendering.
/// Native renderers vary by OS and are still covered by the macOS Quick Look
/// smoke test. The sidecar gives every generated deliverable a reviewable
/// geometry record in environments where those native renderers are not
/// available, and catches values the generator would otherwise clip.
class ArtifactVisualPreviewRenderer {
  static const _documentReviewLineLimit = 7;
  static const _documentReviewPageHeight = 840;
  static const _workbookReviewRowLimit = 7;
  static const _workbookReviewPageHeight = 840;

  const ArtifactVisualPreviewRenderer();

  ArtifactVisualPreview render({
    required GeneratedArtifactKind kind,
    required ArtifactDocument document,
    required List<List<String>> previewRows,
    required int unitCount,
    List<ArtifactVisualPreviewSheet> workbookSheets = const [],
  }) {
    final template = const ArtifactTemplateRegistry().fromDocument(document);
    final isWorkbook = kind == GeneratedArtifactKind.excel;
    final effectiveWorkbookSheets = isWorkbook
        ? workbookSheets.isEmpty
              ? [ArtifactVisualPreviewSheet(name: 'Sheet 1', rows: previewRows)]
              : workbookSheets
        : const <ArtifactVisualPreviewSheet>[];
    final structuralRows = isWorkbook
        ? effectiveWorkbookSheets
              .expand((sheet) => sheet.rows)
              .toList(growable: false)
        : previewRows;
    final contentLines = _contentLines(document);
    final maxColumns = _maxColumnCount(structuralRows);
    final titleOverflow = _normalizedLength(document.title) > 76;
    final contentOverflow =
        !isWorkbook &&
        contentLines.any((line) => _normalizedLength(line) > 112);
    final documentReviewPages = isWorkbook
        ? const <List<String>>[]
        : _documentReviewPages(contentLines);
    final workbookRisks = {
      for (final sheet in effectiveWorkbookSheets)
        sheet.name: ArtifactWorkbookLayout.assess(sheet.rows),
    };
    // The XLSX writer caps generated columns and row heights. Keep the same
    // calculation here so the sidecar flags both an unbreakable wide value and
    // a wrapped row that exceeds Excel's representable height.
    final columnOverflowSheetNames = isWorkbook
        ? effectiveWorkbookSheets
              .where(
                (sheet) =>
                    _sheetHasColumnOverflow(sheet, workbookRisks[sheet.name]!),
              )
              .map((sheet) => sheet.name)
              .toList(growable: false)
        : const <String>[];
    final rowHeightOverflowSheetNames = isWorkbook
        ? effectiveWorkbookSheets
              .where((sheet) => workbookRisks[sheet.name]!.hasRowHeightOverflow)
              .map((sheet) => sheet.name)
              .toList(growable: false)
        : const <String>[];
    final overflowingSheetNames = isWorkbook
        ? effectiveWorkbookSheets
              .where(
                (sheet) =>
                    columnOverflowSheetNames.contains(sheet.name) ||
                    rowHeightOverflowSheetNames.contains(sheet.name),
              )
              .map((sheet) => sheet.name)
              .toList(growable: false)
        : const <String>[];
    final rowNumbersExceedingMaximumHeight = isWorkbook
        ? {
            for (final sheet in effectiveWorkbookSheets)
              if (workbookRisks[sheet.name]!.hasRowHeightOverflow)
                sheet.name:
                    workbookRisks[sheet.name]!.rowNumbersExceedingMaximumHeight,
          }
        : const <String, List<int>>{};
    final tableOverflow = overflowingSheetNames.isNotEmpty;
    final overflow = titleOverflow || contentOverflow || tableOverflow;
    final reviewLabel = _reviewLabel(kind);
    final bytes = utf8.encode(
      isWorkbook
          ? _workbookSvg(
              template: template,
              document: document,
              sheets: effectiveWorkbookSheets,
              titleOverflow: titleOverflow,
              columnOverflowSheetNames: columnOverflowSheetNames,
              rowHeightOverflowSheetNames: rowHeightOverflowSheetNames,
              unitCount: unitCount,
            )
          : _documentSvg(
              template: template,
              document: document,
              reviewLabel: reviewLabel,
              reviewPages: documentReviewPages,
              titleOverflow: titleOverflow,
              unitCount: unitCount,
            ),
    );
    return ArtifactVisualPreview(
      bytes: bytes,
      metadata: {
        'artifactVisualPreviewRenderer': 'artifact_document_structural_v1',
        'artifactVisualPreviewKind': kind.name,
        'artifactVisualPreviewReviewMode': 'structural',
        'artifactVisualPreviewIsNativeRender': false,
        'artifactVisualPreviewHasTitleOverflow': titleOverflow,
        'artifactVisualPreviewHasContentOverflow': contentOverflow,
        'artifactVisualPreviewHasTableOverflow': tableOverflow,
        'artifactVisualPreviewHasRowHeightOverflow':
            rowHeightOverflowSheetNames.isNotEmpty,
        'artifactVisualPreviewHasOverflow': overflow,
        'artifactVisualPreviewTextLineCount': contentLines.length,
        'artifactVisualPreviewTableRowCount': structuralRows.length,
        'artifactVisualPreviewTableColumnCount': maxColumns,
        'artifactVisualPreviewUnitCount': unitCount,
        'artifactVisualPreviewReviewPageCount': isWorkbook
            ? effectiveWorkbookSheets.length
            : documentReviewPages.length,
        'artifactVisualPreviewSheetCount': isWorkbook
            ? effectiveWorkbookSheets.length
            : 0,
        'artifactVisualPreviewOverflowSheetNames': overflowingSheetNames,
        'artifactVisualPreviewColumnOverflowSheetNames':
            columnOverflowSheetNames,
        'artifactVisualPreviewRowHeightOverflowSheetNames':
            rowHeightOverflowSheetNames,
        'artifactVisualPreviewOverflowRowNumbersBySheet':
            rowNumbersExceedingMaximumHeight,
      },
    );
  }

  String _documentSvg({
    required ArtifactTemplate template,
    required ArtifactDocument document,
    required String reviewLabel,
    required List<List<String>> reviewPages,
    required bool titleOverflow,
    required int unitCount,
  }) {
    final dark = template.layout == 'executive-dark';
    final background = dark ? '161616' : 'E8ECF2';
    final page = dark ? '202020' : 'FFFFFF';
    final text = dark ? 'F4F4F5' : '172033';
    final muted = dark ? 'C4C7CC' : '64748B';
    final effectiveReviewPages = reviewPages.isEmpty
        ? const <List<String>>[<String>[]]
        : reviewPages;
    final totalHeight = _documentReviewPageHeight * effectiveReviewPages.length;
    final buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="$totalHeight" viewBox="0 0 1200 $totalHeight" role="img" aria-labelledby="title desc">',
      )
      ..writeln(
        '<title id="title">${_escape(template.logoText)} $reviewLabel structural preview</title>',
      )
      ..writeln(
        '<desc id="desc">Structural layout review for ${_escape(document.title)} across ${effectiveReviewPages.length} review ${effectiveReviewPages.length == 1 ? 'page' : 'pages'}. Native rendering is reviewed separately.</desc>',
      );
    for (
      var pageIndex = 0;
      pageIndex < effectiveReviewPages.length;
      pageIndex++
    ) {
      final pageLines = effectiveReviewPages[pageIndex];
      final yOffset = pageIndex * _documentReviewPageHeight;
      final pageContentOverflow = pageLines.any(
        (line) => _normalizedLength(line) > 112,
      );
      final showTitleOverflow = pageIndex == 0 && titleOverflow;
      buffer
        ..writeln(
          '<rect y="$yOffset" width="1200" height="$_documentReviewPageHeight" fill="#$background"/>',
        )
        ..writeln(
          '<rect x="118" y="${yOffset + 48}" width="964" height="744" rx="8" fill="#$page"/>',
        )
        ..writeln(
          '<rect x="118" y="${yOffset + 48}" width="14" height="744" fill="#${template.accentColor}"/>',
        )
        ..writeln(
          '<text x="168" y="${yOffset + 100}" fill="#${template.accentColor}" font-family="${_escape(template.fontFamily)}" font-size="18" font-weight="700" letter-spacing="2">${_escape(template.logoText)}</text>',
        )
        ..writeln(
          '<text x="1032" y="${yOffset + 100}" fill="#${template.accentColor}" font-family="${_escape(template.fontFamily)}" font-size="16" font-weight="700" text-anchor="end">${_escape(template.confidentialityLabel)}</text>',
        )
        ..writeln(
          '<text x="168" y="${yOffset + 156}" fill="#$text" font-family="${_escape(template.fontFamily)}" font-size="34" font-weight="700">${_escape(_truncate(document.title, 76))}</text>',
        )
        ..writeln(
          '<text x="168" y="${yOffset + 194}" fill="#$muted" font-family="${_escape(template.fontFamily)}" font-size="16">$reviewLabel structural review · page ${pageIndex + 1} of ${effectiveReviewPages.length} · $unitCount generated ${unitCount == 1 ? 'unit' : 'units'}</text>',
        )
        ..writeln(
          '<line x1="168" y1="${yOffset + 220}" x2="1032" y2="${yOffset + 220}" stroke="#${template.accentColor}" stroke-width="2"/>',
        );
      var y = yOffset + 270;
      for (final line in pageLines) {
        buffer
          ..writeln(
            '<circle cx="184" cy="${y - 5}" r="5" fill="#${template.accentColor}"/>',
          )
          ..writeln(
            '<text x="204" y="$y" fill="#$text" font-family="${_escape(template.fontFamily)}" font-size="21">${_escape(_truncate(line, 112))}</text>',
          );
        y += 58;
      }
      if (pageLines.isEmpty) {
        buffer.writeln(
          '<text x="168" y="$y" fill="#$muted" font-family="${_escape(template.fontFamily)}" font-size="21">No document sections were available for review.</text>',
        );
      }
      final flags = <String>[
        if (showTitleOverflow) 'Title exceeds review frame',
        if (pageContentOverflow) 'Long content line exceeds review frame',
        if (!showTitleOverflow && !pageContentOverflow)
          'No structural text overflow detected',
      ];
      buffer
        ..writeln(
          '<rect x="168" y="${yOffset + 680}" width="864" height="62" rx="6" fill="#${showTitleOverflow || pageContentOverflow ? 'FEE2E2' : (dark ? '253126' : 'ECFDF3')}"/>',
        )
        ..writeln(
          '<text x="188" y="${yOffset + 706}" fill="#${showTitleOverflow || pageContentOverflow ? '991B1B' : (dark ? '86EFAC' : '166534')}" font-family="${_escape(template.fontFamily)}" font-size="16" font-weight="700">${_escape(flags.join(' · '))}</text>',
        )
        ..writeln(
          '<text x="168" y="${yOffset + 770}" fill="#$muted" font-family="${_escape(template.fontFamily)}" font-size="14">Structural sidecar · page ${pageIndex + 1}/${effectiveReviewPages.length} · native review required</text>',
        );
    }
    buffer.writeln('</svg>');
    return buffer.toString();
  }

  String _workbookSvg({
    required ArtifactTemplate template,
    required ArtifactDocument document,
    required List<ArtifactVisualPreviewSheet> sheets,
    required bool titleOverflow,
    required List<String> columnOverflowSheetNames,
    required List<String> rowHeightOverflowSheetNames,
    required int unitCount,
  }) {
    final dark = template.layout == 'executive-dark';
    final background = dark ? '161616' : 'E8ECF2';
    final sheet = dark ? '202020' : 'FFFFFF';
    final text = dark ? 'F4F4F5' : '172033';
    final muted = dark ? 'C4C7CC' : '64748B';
    final reviewSheets = sheets.isEmpty
        ? const [ArtifactVisualPreviewSheet(name: 'Sheet 1', rows: [])]
        : sheets;
    final totalHeight = _workbookReviewPageHeight * reviewSheets.length;
    final buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="$totalHeight" viewBox="0 0 1200 $totalHeight" role="img" aria-labelledby="title desc">',
      )
      ..writeln(
        '<title id="title">${_escape(template.logoText)} workbook structural preview</title>',
      )
      ..writeln(
        '<desc id="desc">Structural spreadsheet review for ${_escape(document.title)} across ${reviewSheets.length} generated ${reviewSheets.length == 1 ? 'sheet' : 'sheets'}. Native rendering is reviewed separately.</desc>',
      );
    const left = 118.0;
    const top = 204.0;
    const rowHeight = 54.0;
    for (var sheetIndex = 0; sheetIndex < reviewSheets.length; sheetIndex++) {
      final reviewSheet = reviewSheets[sheetIndex];
      final yOffset = sheetIndex * _workbookReviewPageHeight;
      final columnCount = _maxColumnCount(reviewSheet.rows).clamp(1, 8);
      final columnWidth = 930 / columnCount;
      final visibleRows = reviewSheet.rows
          .take(_workbookReviewRowLimit)
          .toList(growable: false);
      final hasColumnOverflow = columnOverflowSheetNames.contains(
        reviewSheet.name,
      );
      final hasRowHeightOverflow = rowHeightOverflowSheetNames.contains(
        reviewSheet.name,
      );
      final sheetLabel = reviewSheet.name.trim().isEmpty
          ? 'Sheet ${sheetIndex + 1}'
          : reviewSheet.name.trim();
      buffer
        ..writeln(
          '<rect y="$yOffset" width="1200" height="$_workbookReviewPageHeight" fill="#$background"/>',
        )
        ..writeln(
          '<rect x="70" y="${yOffset + 58}" width="1060" height="720" rx="8" fill="#$sheet"/>',
        )
        ..writeln(
          '<rect x="70" y="${yOffset + 58}" width="14" height="720" fill="#${template.accentColor}"/>',
        )
        ..writeln(
          '<text x="118" y="${yOffset + 106}" fill="#${template.accentColor}" font-family="${_escape(template.fontFamily)}" font-size="18" font-weight="700" letter-spacing="2">${_escape(template.logoText)}</text>',
        )
        ..writeln(
          '<text x="1082" y="${yOffset + 106}" fill="#$muted" font-family="${_escape(template.fontFamily)}" font-size="16" text-anchor="end">Sheet ${sheetIndex + 1} of ${reviewSheets.length} · ${_escape(sheetLabel)}</text>',
        )
        ..writeln(
          '<text x="118" y="${yOffset + 156}" fill="#$text" font-family="${_escape(template.fontFamily)}" font-size="30" font-weight="700">${_escape(_truncate(document.title, 56))} · ${_escape(_truncate(sheetLabel, 18))}</text>',
        );
      for (var rowIndex = 0; rowIndex < visibleRows.length; rowIndex++) {
        final row = visibleRows[rowIndex];
        for (var columnIndex = 0; columnIndex < columnCount; columnIndex++) {
          final x = left + (columnIndex * columnWidth);
          final y = yOffset + top + (rowIndex * rowHeight);
          final value = columnIndex < row.length ? row[columnIndex] : '';
          final fill = rowIndex == 0
              ? template.accentColor
              : (dark ? '202020' : 'FFFFFF');
          final cellText = rowIndex == 0 ? 'FFFFFF' : text;
          buffer
            ..writeln(
              '<rect x="${x.toStringAsFixed(1)}" y="${y.toStringAsFixed(1)}" width="${columnWidth.toStringAsFixed(1)}" height="$rowHeight" fill="#$fill" stroke="#${dark ? '475569' : 'CBD5E1'}"/>',
            )
            ..writeln(
              '<text x="${(x + 10).toStringAsFixed(1)}" y="${(y + 33).toStringAsFixed(1)}" fill="#$cellText" font-family="${_escape(template.fontFamily)}" font-size="15"${rowIndex == 0 ? ' font-weight="700"' : ''}>${_escape(_truncate(value, 38))}</text>',
            );
        }
      }
      final flags = <String>[
        if (titleOverflow) 'Title exceeds review frame',
        if (hasColumnOverflow) 'Generated column width may clip table values',
        if (hasRowHeightOverflow)
          'Generated row height exceeds the supported Excel limit',
        if (!titleOverflow && !hasColumnOverflow && !hasRowHeightOverflow)
          'No structural table overflow detected',
      ];
      buffer
        ..writeln(
          '<rect x="118" y="${yOffset + 684}" width="964" height="58" rx="6" fill="#${titleOverflow || hasColumnOverflow || hasRowHeightOverflow ? 'FEE2E2' : (dark ? '253126' : 'ECFDF3')}"/>',
        )
        ..writeln(
          '<text x="138" y="${yOffset + 719}" fill="#${titleOverflow || hasColumnOverflow || hasRowHeightOverflow ? '991B1B' : (dark ? '86EFAC' : '166534')}" font-family="${_escape(template.fontFamily)}" font-size="16" font-weight="700">${_escape(flags.join(' · '))}</text>',
        )
        ..writeln(
          '<text x="118" y="${yOffset + 766}" fill="#$muted" font-family="${_escape(template.fontFamily)}" font-size="14">Structural sidecar · $unitCount ${unitCount == 1 ? 'sheet' : 'sheets'} · native review required</text>',
        );
    }
    buffer.writeln('</svg>');
    return buffer.toString();
  }

  int _maxColumnCount(Iterable<List<String>> rows) => rows.fold<int>(
    0,
    (maximum, row) => row.length > maximum ? row.length : maximum,
  );

  bool _sheetHasColumnOverflow(
    ArtifactVisualPreviewSheet sheet,
    WorkbookTableLayoutRisk risk,
  ) => _maxColumnCount(sheet.rows) > 8 || risk.hasUnbreakableColumnValue;

  List<List<String>> _documentReviewPages(List<String> contentLines) {
    if (contentLines.isEmpty) return const [<String>[]];
    return [
      for (
        var start = 0;
        start < contentLines.length;
        start += _documentReviewLineLimit
      )
        contentLines
            .skip(start)
            .take(_documentReviewLineLimit)
            .toList(growable: false),
    ];
  }

  List<String> _contentLines(ArtifactDocument document) {
    final lines = <String>[
      document.summary,
      for (final section in document.sections) ...[
        section.title,
        if (section.body.trim().isNotEmpty) _firstSentence(section.body),
        ...section.bullets,
      ],
    ];
    return lines
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  String _firstSentence(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    final match = RegExp(r'^(.{1,180}?[.!?])(?:\s|$)').firstMatch(normalized);
    return match?.group(1) ?? normalized;
  }

  String _reviewLabel(GeneratedArtifactKind kind) => switch (kind) {
    GeneratedArtifactKind.docx => 'Word report',
    GeneratedArtifactKind.pdf => 'PDF report',
    GeneratedArtifactKind.excel => 'Excel workbook',
    GeneratedArtifactKind.csv => 'CSV dataset',
    GeneratedArtifactKind.markdown => 'Markdown document',
    GeneratedArtifactKind.html => 'HTML document',
    GeneratedArtifactKind.json => 'JSON artifact',
    GeneratedArtifactKind.diagram => 'Topology diagram',
    GeneratedArtifactKind.chart => 'Chart pack',
    GeneratedArtifactKind.powerPoint => 'PowerPoint deck',
    GeneratedArtifactKind.report => 'Report',
  };

  String _truncate(String value, int limit) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= limit
        ? normalized
        : '${normalized.substring(0, limit - 1).trimRight()}…';
  }

  int _normalizedLength(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim().length;

  String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

class ArtifactVisualPreview {
  final List<int> bytes;
  final Map<String, Object?> metadata;

  const ArtifactVisualPreview({required this.bytes, required this.metadata});
}

class ArtifactVisualPreviewSheet {
  final String name;
  final List<List<String>> rows;

  const ArtifactVisualPreviewSheet({required this.name, required this.rows});
}
