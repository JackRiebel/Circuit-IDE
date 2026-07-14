import 'dart:convert';
import 'dart:math';

import '../models/artifact_document.dart';
import '../models/artifact_template.dart';

/// A self-contained semantic HTML rendering of the shared artifact document.
/// It deliberately consumes no assistant prose outside [ArtifactDocument], so
/// web, Markdown, DOCX, PDF, PPTX, and workbook generation start from the
/// same composition blocks.
class HtmlArtifactRenderer {
  const HtmlArtifactRenderer();

  HtmlArtifactRenderResult render(ArtifactDocument document) {
    final title = _escape(document.title);
    final template = const ArtifactTemplateRegistry().fromDocument(document);
    final theme = document.metadata['theme']?.toString().trim() ?? '';
    final language = _documentLanguage(document);
    final renderedTables = [
      ...document.tables.map(
        (table) => _RenderedTable(title: table.title, rows: table.rows),
      ),
      ...document.sourceData.map(
        (table) => _RenderedTable(title: table.title, rows: table.rows),
      ),
    ].where((table) => table.rows.isNotEmpty).toList(growable: false);
    final buffer = StringBuffer()
      ..writeln('<!doctype html>')
      ..writeln('<html lang="${_escape(language)}">')
      ..writeln('<head>')
      ..writeln('<meta charset="utf-8">')
      ..writeln(
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
      )
      ..writeln(
        '<meta name="artifact-theme" content="${_escape(theme.isEmpty ? template.id : theme)}">',
      )
      ..writeln(
        '<meta name="artifact-template" content="${_escape(template.id)}">',
      )
      ..writeln('<title>$title</title>')
      ..writeln(
        '<style>:root{--brand:#${template.primaryColor};--accent:#${template.accentColor}}body{font:16px/1.55 "${_escape(template.fontFamily)}",-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;max-width:960px;margin:0 auto;padding:40px;color:#172033}.brand{display:flex;justify-content:space-between;gap:16px;align-items:center;border-bottom:4px solid var(--brand);padding-bottom:12px;margin-bottom:28px;font-size:.78rem;letter-spacing:.08em;font-weight:700}.confidentiality{color:var(--brand)}h1,h2,h3{line-height:1.2}table{border-collapse:collapse;width:100%;margin:16px 0}th,td{border:1px solid #cbd5e1;padding:8px;text-align:left;vertical-align:top}th{background:color-mix(in srgb,var(--accent) 14%,white)}aside{border-left:4px solid var(--accent);padding:4px 16px;margin:20px 0}footer{margin-top:36px;color:#475569;font-size:.9em}</style>',
      )
      ..writeln('</head><body>')
      ..writeln('<main>')
      ..writeln(
        '<div class="brand"><span>${_escape(template.logoText)}</span><span class="confidentiality">${_escape(template.confidentialityLabel)}</span></div>',
      )
      ..writeln(
        '<header><h1>$title</h1><p>${_escape(document.summary)}</p></header>',
      );
    for (final section in document.sections) {
      buffer.writeln('<section><h2>${_escape(section.title)}</h2>');
      if (section.body.trim().isNotEmpty) {
        buffer.writeln('<p>${_escape(section.body)}</p>');
      }
      _writeList(buffer, section.bullets);
      buffer.writeln('</section>');
    }
    for (final table in document.tables) {
      buffer.writeln('<section><h2>${_escape(table.title)}</h2>');
      _writeTable(buffer, title: table.title, rows: table.rows);
      buffer.writeln('</section>');
    }
    for (final chart in document.charts) {
      buffer.writeln('<section><h2>${_escape(chart.title)}</h2>');
      buffer.writeln('<p>Chart type: ${_escape(chart.type)}</p>');
      _writeList(buffer, chart.signals);
      buffer.writeln('</section>');
    }
    for (final diagram in document.diagrams) {
      buffer.writeln('<section><h2>${_escape(diagram.title)}</h2>');
      buffer.writeln('<p>Diagram source (${_escape(diagram.syntax)})</p>');
      buffer.writeln('<pre><code>${_escape(diagram.source)}</code></pre>');
      buffer.writeln('</section>');
    }
    for (final appendix in document.appendices) {
      buffer.writeln('<section><h2>Appendix: ${_escape(appendix.title)}</h2>');
      if (appendix.body.trim().isNotEmpty) {
        buffer.writeln('<p>${_escape(appendix.body)}</p>');
      }
      _writeList(buffer, appendix.bullets);
      buffer.writeln('</section>');
    }
    for (final source in document.sourceData) {
      buffer.writeln('<section><h2>Source data: ${_escape(source.title)}</h2>');
      _writeTable(buffer, title: source.title, rows: source.rows);
      _writeList(buffer, source.notes);
      buffer.writeln('</section>');
    }
    if (document.assumptions.isNotEmpty) {
      buffer.writeln('<aside><h2>Assumptions</h2>');
      _writeList(buffer, document.assumptions);
      buffer.writeln('</aside>');
    }
    if (document.citations.isNotEmpty) {
      buffer.writeln('<footer><h2>Sources</h2>');
      _writeList(buffer, document.citations);
      buffer.writeln('</footer>');
    }
    buffer.writeln('<footer>${_escape(template.footerText)}</footer>');
    buffer.writeln('</main></body></html>');
    final bytes = utf8.encode(buffer.toString());
    return HtmlArtifactRenderResult(
      bytes: bytes,
      metadata: {
        'htmlHasDocumentTitle': document.title.trim().isNotEmpty,
        'htmlLanguage': language,
        'htmlHasDocumentLanguage': _isLanguageTag(language),
        'htmlHasMainLandmark': true,
        'htmlHasSemanticSections': _hasSemanticSections(document),
        'htmlRenderedTableCount': renderedTables.length,
        'htmlHasTableHeaders': renderedTables.every(_hasTableHeaders),
        'htmlHasTableCaptions': renderedTables.every(_hasTableCaption),
        'htmlHasAccessibleColorContrast': _hasAccessibleTextContrast(template),
        'htmlHasAssumptions': document.assumptions.isNotEmpty,
        'htmlHasSources': document.citations.isNotEmpty,
        'htmlChartCount': document.charts.length,
        'htmlDiagramCount': document.diagrams.length,
        'htmlAppendixCount': document.appendices.length,
        'htmlSourceDataCount': document.sourceData.length,
        'htmlTemplateId': template.id,
        'htmlTemplateVersion': template.version,
        'htmlBrandVisible': true,
        'htmlConfidentialityVisible': true,
        'htmlFooterVisible': true,
        'htmlRenderer': 'artifact_document_v1',
      },
    );
  }

  void _writeList(StringBuffer buffer, List<String> values) {
    if (values.isEmpty) return;
    buffer.writeln('<ul>');
    for (final value in values) {
      buffer.writeln('<li>${_escape(value)}</li>');
    }
    buffer.writeln('</ul>');
  }

  void _writeTable(
    StringBuffer buffer, {
    required String title,
    required List<List<String>> rows,
  }) {
    if (rows.isEmpty) return;
    buffer.writeln('<table>');
    buffer.writeln('<caption>${_escape(title)}</caption>');
    final header = rows.first;
    buffer.writeln(
      '<thead><tr>${header.map((cell) => '<th scope="col">${_escape(cell)}</th>').join()}</tr></thead>',
    );
    if (rows.length > 1) {
      buffer.writeln('<tbody>');
      for (final row in rows.skip(1)) {
        buffer.writeln(
          '<tr>${row.map((cell) => '<td>${_escape(cell)}</td>').join()}</tr>',
        );
      }
      buffer.writeln('</tbody>');
    }
    buffer.writeln('</table>');
  }

  String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  String _documentLanguage(ArtifactDocument document) {
    final requested =
        document.metadata['htmlLanguage']?.toString().trim() ??
        document.metadata['language']?.toString().trim() ??
        '';
    return _isLanguageTag(requested) ? requested.replaceAll('_', '-') : 'en';
  }

  bool _hasSemanticSections(ArtifactDocument document) =>
      document.sections.isNotEmpty ||
      document.tables.any((table) => table.rows.isNotEmpty) ||
      document.charts.isNotEmpty ||
      document.diagrams.isNotEmpty ||
      document.appendices.isNotEmpty ||
      document.sourceData.any((table) => table.rows.isNotEmpty);

  bool _hasTableHeaders(_RenderedTable table) =>
      table.rows.first.every((cell) => cell.trim().isNotEmpty);

  bool _hasTableCaption(_RenderedTable table) => table.title.trim().isNotEmpty;

  bool _hasAccessibleTextContrast(ArtifactTemplate template) {
    final foreground = _relativeLuminance(template.primaryColor);
    if (foreground == null) return false;
    final contrast = (1.0 + 0.05) / (foreground + 0.05);
    return contrast >= 4.5;
  }

  double? _relativeLuminance(String hex) {
    final normalized = hex.replaceFirst('#', '').trim();
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) return null;
    final channels = <int>[
      int.parse(normalized.substring(0, 2), radix: 16),
      int.parse(normalized.substring(2, 4), radix: 16),
      int.parse(normalized.substring(4, 6), radix: 16),
    ];
    final linear = channels
        .map((channel) {
          final value = channel / 255;
          return value <= 0.04045
              ? value / 12.92
              : pow((value + 0.055) / 1.055, 2.4);
        })
        .toList(growable: false);
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
  }

  bool _isLanguageTag(String value) =>
      RegExp(r'^[A-Za-z]{2,3}(?:[-_][A-Za-z0-9]{2,8})*$').hasMatch(value);
}

class _RenderedTable {
  final String title;
  final List<List<String>> rows;

  const _RenderedTable({required this.title, required this.rows});
}

class HtmlArtifactRenderResult {
  final List<int> bytes;
  final Map<String, Object?> metadata;

  const HtmlArtifactRenderResult({required this.bytes, required this.metadata});
}
