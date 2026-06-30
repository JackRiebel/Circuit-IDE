import 'dart:convert';
import 'dart:typed_data';

import '../models/artifact_document.dart';

class PdfArtifactRenderer {
  const PdfArtifactRenderer();

  Uint8List render(ArtifactDocument document) {
    final pages = _paginate(_linesFor(document));
    final objects = <int, List<int>>{};
    final pageIds = <int>[];
    objects[1] = _bytes('<< /Type /Catalog /Pages 2 0 R >>');
    objects[3] = _bytes(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    );
    objects[4] = _bytes(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>',
    );

    for (var i = 0; i < pages.length; i++) {
      final pageId = 5 + (i * 2);
      final contentId = pageId + 1;
      pageIds.add(pageId);
      final stream = _contentStream(pages[i], pageNumber: i + 1);
      objects[contentId] = _bytes(
        '<< /Length ${utf8.encode(stream).length} >>\nstream\n$stream\nendstream',
      );
      objects[pageId] = _bytes(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> '
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
        'trailer\n<< /Size ${maxObjectId + 1} /Root 1 0 R >>\nstartxref\n$xrefOffset\n%%EOF\n',
      ),
    );
    return output.toBytes();
  }

  List<_PdfLine> _linesFor(ArtifactDocument document) {
    final lines = <_PdfLine>[
      _PdfLine(document.title, size: 24, bold: true, gapAfter: 14),
      if (document.summary.trim().isNotEmpty)
        _PdfLine(document.summary, size: 11, gapAfter: 16),
    ];
    for (final section in document.sections) {
      lines.add(_PdfLine(section.title, size: 16, bold: true, gapBefore: 10));
      for (final paragraph in _paragraphs(section.body).take(6)) {
        lines.add(_PdfLine(paragraph, size: 10.5));
      }
      for (final bullet in section.bullets.take(12)) {
        lines.add(_PdfLine('- $bullet', size: 10.5, indent: 18));
      }
    }
    for (final table in document.tables.take(6)) {
      lines.add(_PdfLine(table.title, size: 14, bold: true, gapBefore: 12));
      for (final row in table.rows.take(18)) {
        lines.add(
          _PdfLine(row.take(6).join('   |   '), size: 9.5, monoLike: true),
        );
      }
    }
    if (document.assumptions.isNotEmpty) {
      lines.add(
        const _PdfLine('Assumptions', size: 14, bold: true, gapBefore: 12),
      );
      for (final assumption in document.assumptions) {
        lines.add(_PdfLine('- $assumption', size: 10.5, indent: 18));
      }
    }
    if (document.citations.isNotEmpty) {
      lines.add(const _PdfLine('Sources', size: 14, bold: true, gapBefore: 12));
      for (final citation in document.citations) {
        lines.add(_PdfLine('- $citation', size: 10.5, indent: 18));
      }
    }
    return lines;
  }

  Iterable<String> _paragraphs(String body) {
    return body
        .split(RegExp(r'\n\s*\n'))
        .map((paragraph) => paragraph.replaceAll('\n', ' ').trim())
        .where((paragraph) => paragraph.isNotEmpty);
  }

  List<List<_PdfLine>> _paginate(List<_PdfLine> source) {
    final pages = <List<_PdfLine>>[];
    var page = <_PdfLine>[];
    var y = 724.0;
    for (final line in source) {
      final wrapped = _wrap(line);
      for (var i = 0; i < wrapped.length; i++) {
        final current = i == 0 ? wrapped[i] : wrapped[i].copyWith(gapBefore: 0);
        y -= current.gapBefore;
        if (y < 72) {
          pages.add(page);
          page = <_PdfLine>[];
          y = 724;
        }
        page.add(current.copyWith(y: y));
        y -= current.lineHeight + current.gapAfter;
      }
    }
    if (page.isNotEmpty) pages.add(page);
    return pages.isEmpty ? [[]] : pages;
  }

  List<_PdfLine> _wrap(_PdfLine line) {
    final maxChars = ((88 - (line.indent / 5)) * (10.5 / line.size))
        .clamp(34, 110)
        .floor();
    if (line.text.length <= maxChars) return [line];
    final words = line.text.split(RegExp(r'\s+'));
    final wrapped = <_PdfLine>[];
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

  String _contentStream(List<_PdfLine> lines, {required int pageNumber}) {
    final buffer = StringBuffer()
      ..writeln('0.96 0.96 0.95 rg 0 0 612 792 re f')
      ..writeln('0.22 0.55 0.52 rg 0 0 8 792 re f')
      ..writeln('0.08 0.08 0.08 rg');
    for (final line in lines) {
      final font = line.bold ? 'F2' : 'F1';
      final x = 54 + line.indent;
      buffer.writeln(
        'BT /$font ${line.size.toStringAsFixed(1)} Tf 0.08 0.08 0.08 rg '
        '$x ${line.y.toStringAsFixed(1)} Td (${_pdfText(line.text)}) Tj ET',
      );
    }
    buffer.writeln(
      'BT /F1 8 Tf 0.45 0.45 0.45 rg 520 34 Td (${_pdfText('Page $pageNumber')}) Tj ET',
    );
    return buffer.toString();
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
}

class _PdfLine {
  final String text;
  final double size;
  final bool bold;
  final bool monoLike;
  final double indent;
  final double gapBefore;
  final double gapAfter;
  final double y;

  const _PdfLine(
    this.text, {
    required this.size,
    this.bold = false,
    this.monoLike = false,
    this.indent = 0,
    this.gapBefore = 3,
    this.gapAfter = 3,
    this.y = 0,
  });

  double get lineHeight => size + 5;

  _PdfLine copyWith({String? text, double? gapBefore, double? y}) {
    return _PdfLine(
      text ?? this.text,
      size: size,
      bold: bold,
      monoLike: monoLike,
      indent: indent,
      gapBefore: gapBefore ?? this.gapBefore,
      gapAfter: gapAfter,
      y: y ?? this.y,
    );
  }
}
