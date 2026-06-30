import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/artifact_document.dart';

class PdfArtifactRenderer {
  const PdfArtifactRenderer();

  Uint8List render(ArtifactDocument document) {
    final pages = _paginate(_itemsFor(document));
    final objects = <int, List<int>>{};
    final pageIds = <int>[];
    objects[1] = _bytes('<< /Type /Catalog /Pages 2 0 R >>');
    objects[3] = _bytes(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    );
    objects[4] = _bytes(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>',
    );
    objects[5] = _bytes('<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>');
    objects[6] = _bytes(
      '<< /Title (${_pdfText(document.title)}) /Author (CircuitCode) '
      '/Creator (CircuitCode) /Producer (CircuitCode Artifact Renderer) >>',
    );

    for (var i = 0; i < pages.length; i++) {
      final pageId = 7 + (i * 2);
      final contentId = pageId + 1;
      pageIds.add(pageId);
      final stream = _contentStream(
        pages[i],
        document: document,
        pageNumber: i + 1,
        pageCount: pages.length,
      );
      objects[contentId] = _bytes(
        '<< /Length ${utf8.encode(stream).length} >>\nstream\n$stream\nendstream',
      );
      objects[pageId] = _bytes(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Resources << /Font << /F1 3 0 R /F2 4 0 R /F3 5 0 R >> >> '
        '/Contents $contentId 0 R >>',
      );
    }
    objects[2] = _bytes(
      '<< /Type /Pages /Kids [${pageIds.map((id) => '$id 0 R').join(' ')}] /Count ${pageIds.length} >>',
    );

    final output = BytesBuilder(copy: false);
    output.add(_bytes('%PDF-1.4\n%\u00e2\u00e3\u00cf\u00d3\n'));
    final offsets = <int, int>{};
    final maxObjectId = objects.keys.reduce((a, b) => a > b ? a : b);
    for (var id = 1; id <= maxObjectId; id++) {
      final object = objects[id];
      if (object == null) continue;
      offsets[id] = output.length;
      output
        ..add(_bytes('$id 0 obj\n'))
        ..add(object)
        ..add(_bytes('\nendobj\n'));
    }
    final xrefOffset = output.length;
    output.add(_bytes('xref\n0 ${maxObjectId + 1}\n'));
    output.add(_bytes('0000000000 65535 f \n'));
    for (var id = 1; id <= maxObjectId; id++) {
      final offset = offsets[id] ?? 0;
      output.add(_bytes('${offset.toString().padLeft(10, '0')} 00000 n \n'));
    }
    output.add(
      _bytes(
        'trailer\n<< /Size ${maxObjectId + 1} /Root 1 0 R /Info 6 0 R >>\nstartxref\n$xrefOffset\n%%EOF\n',
      ),
    );
    return output.toBytes();
  }

  List<_PdfItem> _itemsFor(ArtifactDocument document) {
    final items = <_PdfItem>[
      _PdfText(document.title, size: 25, bold: true, gapAfter: 11),
      const _PdfText(
        'CircuitCode customer handoff report',
        size: 10,
        color: _PdfColor.muted,
        gapAfter: 18,
      ),
      const _PdfText(
        'Executive Summary',
        size: 16,
        bold: true,
        gapBefore: 6,
        gapAfter: 7,
      ),
      if (document.summary.trim().isNotEmpty)
        _PdfText(document.summary, size: 10.5, gapAfter: 12),
    ];
    for (final section in document.sections) {
      items.add(
        _PdfText(
          section.title,
          size: 15,
          bold: true,
          gapBefore: 12,
          gapAfter: 6,
        ),
      );
      for (final paragraph in _paragraphs(section.body).take(6)) {
        items.add(_PdfText(paragraph, size: 10.3));
      }
      for (final bullet in section.bullets.take(12)) {
        items.add(_PdfText('- $bullet', size: 10.3, indent: 16, gapAfter: 2));
      }
    }
    for (final table in document.tables.take(6)) {
      items
        ..add(
          _PdfText(
            table.title,
            size: 13.5,
            bold: true,
            gapBefore: 12,
            gapAfter: 6,
          ),
        )
        ..add(_PdfTable(table.rows.take(16).toList(growable: false)));
    }
    if (document.assumptions.isNotEmpty) {
      items.add(
        const _PdfText(
          'Assumptions',
          size: 13.5,
          bold: true,
          gapBefore: 12,
          gapAfter: 6,
        ),
      );
      for (final assumption in document.assumptions) {
        items.add(_PdfText('- $assumption', size: 10.3, indent: 16));
      }
    }
    if (document.citations.isNotEmpty) {
      items.add(
        const _PdfText(
          'Sources / Evidence',
          size: 13.5,
          bold: true,
          gapBefore: 12,
          gapAfter: 6,
        ),
      );
      for (final citation in document.citations) {
        items.add(_PdfText('- $citation', size: 9.8, indent: 16));
      }
    }
    return items;
  }

  Iterable<String> _paragraphs(String body) {
    return body
        .split(RegExp(r'\n\s*\n'))
        .map((paragraph) => paragraph.replaceAll('\n', ' ').trim())
        .where((paragraph) => paragraph.isNotEmpty);
  }

  List<List<_PlacedPdfItem>> _paginate(List<_PdfItem> source) {
    final pages = <List<_PlacedPdfItem>>[];
    var page = <_PlacedPdfItem>[];
    var y = 716.0;
    for (final item in source) {
      final parts = item is _PdfText ? _wrap(item) : [item];
      for (final part in parts) {
        final candidate = part.copyWith(
          gapBefore: identical(part, parts.first) ? null : 0,
        );
        final needed =
            candidate.gapBefore + candidate.height + candidate.gapAfter;
        if (y - needed < 76 && page.isNotEmpty) {
          pages.add(page);
          page = <_PlacedPdfItem>[];
          y = 716;
        }
        y -= candidate.gapBefore;
        page.add(_PlacedPdfItem(candidate, y));
        y -= candidate.height + candidate.gapAfter;
      }
    }
    if (page.isNotEmpty) pages.add(page);
    return pages.isEmpty ? [[]] : pages;
  }

  List<_PdfText> _wrap(_PdfText line) {
    final maxChars = ((91 - (line.indent / 5)) * (10.5 / line.size))
        .clamp(34, 116)
        .floor();
    if (line.text.length <= maxChars) return [line];
    final words = line.text.split(RegExp(r'\s+'));
    final wrapped = <_PdfText>[];
    var current = '';
    for (final word in words) {
      final candidate = current.isEmpty ? word : '$current $word';
      if (candidate.length > maxChars && current.isNotEmpty) {
        wrapped.add(line.copyWith(text: current));
        current = word;
      } else {
        current = candidate;
      }
    }
    if (current.isNotEmpty) wrapped.add(line.copyWith(text: current));
    return wrapped;
  }

  String _contentStream(
    List<_PlacedPdfItem> items, {
    required ArtifactDocument document,
    required int pageNumber,
    required int pageCount,
  }) {
    final buffer = StringBuffer()
      ..writeln('0.98 0.98 0.97 rg 0 0 612 792 re f')
      ..writeln('0.20 0.56 0.53 rg 0 0 8 792 re f')
      ..writeln('0.12 0.12 0.12 rg');
    _drawHeader(buffer, document, pageNumber);
    for (final placed in items) {
      final item = placed.item;
      if (item is _PdfText) {
        _drawText(buffer, item, placed.y);
      } else if (item is _PdfTable) {
        _drawTable(buffer, item, placed.y);
      }
    }
    _drawFooter(buffer, pageNumber, pageCount);
    return buffer.toString();
  }

  void _drawHeader(StringBuffer buffer, ArtifactDocument document, int page) {
    buffer
      ..writeln('0.92 0.93 0.92 rg 54 744 504 1 re f')
      ..writeln(
        'BT /F1 8 Tf 0.35 0.37 0.40 rg 54 758 Td (${_pdfText('CircuitCode generated artifact')}) Tj ET',
      );
    if (page > 1) {
      buffer.writeln(
        'BT /F2 8 Tf 0.35 0.37 0.40 rg 378 758 Td (${_pdfText(_truncate(document.title, 44))}) Tj ET',
      );
    }
  }

  void _drawFooter(StringBuffer buffer, int pageNumber, int pageCount) {
    buffer
      ..writeln('0.90 0.91 0.91 rg 54 52 504 1 re f')
      ..writeln(
        'BT /F1 8 Tf 0.43 0.45 0.48 rg 54 34 Td (${_pdfText('CircuitCode - Generated artifact')}) Tj ET',
      )
      ..writeln(
        'BT /F1 8 Tf 0.43 0.45 0.48 rg 500 34 Td (${_pdfText('Page $pageNumber of $pageCount')}) Tj ET',
      );
  }

  void _drawText(StringBuffer buffer, _PdfText line, double y) {
    final font = line.bold
        ? 'F2'
        : line.mono
        ? 'F3'
        : 'F1';
    final color = switch (line.color) {
      _PdfColor.body => '0.10 0.11 0.13',
      _PdfColor.muted => '0.42 0.45 0.50',
    };
    final x = 54 + line.indent;
    buffer.writeln(
      'BT /$font ${line.size.toStringAsFixed(1)} Tf $color rg '
      '$x ${y.toStringAsFixed(1)} Td (${_pdfText(line.text)}) Tj ET',
    );
  }

  void _drawTable(StringBuffer buffer, _PdfTable table, double y) {
    if (table.rows.isEmpty) return;
    final columnCount = table.columnCount;
    final widths = table.columnWidths;
    const rowHeight = 22.0;
    var currentY = y;
    for (var rowIndex = 0; rowIndex < table.rows.length; rowIndex++) {
      final row = table.rows[rowIndex];
      var x = 54.0;
      for (var column = 0; column < columnCount; column++) {
        final width = widths[column];
        final fill = rowIndex == 0
            ? '0.88 0.91 0.92'
            : rowIndex.isEven
            ? '0.97 0.97 0.96'
            : '1 1 1';
        buffer
          ..writeln(
            '$fill rg ${x.toStringAsFixed(1)} ${(currentY - rowHeight + 4).toStringAsFixed(1)} ${width.toStringAsFixed(1)} $rowHeight re f',
          )
          ..writeln(
            '0.78 0.81 0.84 RG ${x.toStringAsFixed(1)} ${(currentY - rowHeight + 4).toStringAsFixed(1)} ${width.toStringAsFixed(1)} $rowHeight re S',
          );
        final text = column < row.length ? row[column] : '';
        buffer.writeln(
          'BT /${rowIndex == 0 ? 'F2' : 'F1'} 8.2 Tf 0.11 0.12 0.14 rg '
          '${(x + 5).toStringAsFixed(1)} ${(currentY - 10).toStringAsFixed(1)} Td (${_pdfText(_truncate(text, (width / 5.2).floor()))}) Tj ET',
        );
        x += width;
      }
      currentY -= rowHeight;
    }
  }

  Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

  String _pdfText(String value) {
    return value
        .replaceAll('\\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)')
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ');
  }

  String _truncate(String value, int max) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (max < 6 || normalized.length <= max) return normalized;
    return '${normalized.substring(0, max - 3)}...';
  }
}

enum _PdfColor { body, muted }

abstract class _PdfItem {
  double get gapBefore;
  double get gapAfter;
  double get height;

  _PdfItem copyWith({double? gapBefore});
}

class _PdfText implements _PdfItem {
  final String text;
  final double size;
  final bool bold;
  final bool mono;
  final double indent;
  @override
  final double gapBefore;
  @override
  final double gapAfter;
  final _PdfColor color;

  const _PdfText(
    this.text, {
    required this.size,
    this.bold = false,
    this.mono = false,
    this.indent = 0,
    this.gapBefore = 3,
    this.gapAfter = 3,
    this.color = _PdfColor.body,
  });

  @override
  double get height => size + 5;

  @override
  _PdfText copyWith({String? text, double? gapBefore}) {
    return _PdfText(
      text ?? this.text,
      size: size,
      bold: bold,
      mono: mono,
      indent: indent,
      gapBefore: gapBefore ?? this.gapBefore,
      gapAfter: gapAfter,
      color: color,
    );
  }
}

class _PdfTable implements _PdfItem {
  final List<List<String>> rows;

  const _PdfTable(this.rows);

  int get columnCount => rows
      .fold<int>(0, (max, row) => row.length > max ? row.length : max)
      .clamp(1, 6);

  List<double> get columnWidths {
    final weights = List<int>.filled(columnCount, 4);
    for (final row in rows.take(10)) {
      for (var i = 0; i < columnCount; i++) {
        final value = i < row.length ? row[i] : '';
        weights[i] += value.length.clamp(1, 34);
      }
    }
    final total = math.max(
      1,
      weights.fold<int>(0, (sum, value) => sum + value),
    );
    var remaining = 504.0;
    final widths = <double>[];
    for (var i = 0; i < columnCount; i++) {
      final width = i == columnCount - 1
          ? remaining
          : ((504 * weights[i]) / total).clamp(58.0, 182.0);
      widths.add(width);
      remaining -= width;
    }
    return widths;
  }

  @override
  double get gapBefore => 2;

  @override
  double get gapAfter => 9;

  @override
  double get height => rows.length * 22.0;

  @override
  _PdfTable copyWith({double? gapBefore}) => this;
}

class _PlacedPdfItem {
  final _PdfItem item;
  final double y;

  const _PlacedPdfItem(this.item, this.y);
}
