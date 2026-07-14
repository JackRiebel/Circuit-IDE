class ArtifactDocument {
  final String title;
  final String summary;
  final List<ArtifactSection> sections;
  final List<ArtifactTable> tables;
  final List<ArtifactChart> charts;
  final List<ArtifactDiagram> diagrams;
  final List<ArtifactAppendix> appendices;
  final List<ArtifactSourceData> sourceData;
  final List<String> assumptions;
  final List<String> citations;
  final ArtifactExportMetadata exportMetadata;
  final Map<String, Object?> metadata;

  const ArtifactDocument({
    required this.title,
    required this.summary,
    this.sections = const [],
    this.tables = const [],
    this.charts = const [],
    this.diagrams = const [],
    this.appendices = const [],
    this.sourceData = const [],
    this.assumptions = const [],
    this.citations = const [],
    this.exportMetadata = const ArtifactExportMetadata(),
    this.metadata = const {},
  });

  ArtifactDocument copyWith({
    String? title,
    String? summary,
    List<ArtifactSection>? sections,
    List<ArtifactTable>? tables,
    List<ArtifactChart>? charts,
    List<ArtifactDiagram>? diagrams,
    List<ArtifactAppendix>? appendices,
    List<ArtifactSourceData>? sourceData,
    List<String>? assumptions,
    List<String>? citations,
    ArtifactExportMetadata? exportMetadata,
    Map<String, Object?>? metadata,
  }) {
    return ArtifactDocument(
      title: title ?? this.title,
      summary: summary ?? this.summary,
      sections: sections ?? this.sections,
      tables: tables ?? this.tables,
      charts: charts ?? this.charts,
      diagrams: diagrams ?? this.diagrams,
      appendices: appendices ?? this.appendices,
      sourceData: sourceData ?? this.sourceData,
      assumptions: assumptions ?? this.assumptions,
      citations: citations ?? this.citations,
      exportMetadata: exportMetadata ?? this.exportMetadata,
      metadata: metadata ?? this.metadata,
    );
  }

  bool get hasTables => tables.isNotEmpty;

  List<List<String>> get previewRows {
    if (tables.isEmpty) return const [];
    return tables.first.rows.take(6).toList(growable: false);
  }
}

class ArtifactSection {
  final String title;
  final String body;
  final List<String> bullets;

  const ArtifactSection({
    required this.title,
    this.body = '',
    this.bullets = const [],
  });
}

class ArtifactTable {
  final String title;
  final List<List<String>> rows;

  const ArtifactTable({required this.title, required this.rows});
}

class ArtifactChart {
  final String title;
  final String type;
  final List<String> signals;

  const ArtifactChart({
    required this.title,
    this.type = 'unspecified',
    this.signals = const [],
  });
}

class ArtifactDiagram {
  final String title;
  final String syntax;
  final String source;

  const ArtifactDiagram({
    required this.title,
    required this.source,
    this.syntax = 'mermaid',
  });
}

class ArtifactAppendix {
  final String title;
  final String body;
  final List<String> bullets;

  const ArtifactAppendix({
    required this.title,
    this.body = '',
    this.bullets = const [],
  });
}

class ArtifactSourceData {
  final String title;
  final List<List<String>> rows;
  final List<String> notes;

  const ArtifactSourceData({
    required this.title,
    this.rows = const [],
    this.notes = const [],
  });
}

class ArtifactExportMetadata {
  final List<String> requestedFormats;
  final String? audience;
  final String? checkedDate;
  final Map<String, Object?> fields;

  const ArtifactExportMetadata({
    this.requestedFormats = const [],
    this.audience,
    this.checkedDate,
    this.fields = const {},
  });

  bool get hasData =>
      requestedFormats.isNotEmpty ||
      audience != null ||
      checkedDate != null ||
      fields.isNotEmpty;
}

class ArtifactComposer {
  const ArtifactComposer();

  ArtifactDocument fromAssistantOutput({
    required String prompt,
    required String content,
  }) {
    final cleanContent = content.trim();
    final title = _titleFromMarkdown(cleanContent) ?? _titleFromPrompt(prompt);
    final tables = _extractTables(cleanContent);
    final sections = _extractSections(cleanContent);
    final assumptions = _extractFirstListAfterAnyHeading(cleanContent, const [
      'assumptions',
      'unknowns',
      'caveats',
      'dependencies',
    ]);
    final citations = _extractFirstListAfterAnyHeading(cleanContent, const [
      'sources',
      'citations',
      'references',
      'evidence',
    ]);
    final charts = _extractCharts(sections, tables);
    final diagrams = _extractDiagrams(cleanContent);
    final appendices = _extractAppendices(sections);
    final sourceData = _extractSourceData(sections, tables);
    final exportMetadata = _extractExportMetadata(
      prompt: prompt,
      content: cleanContent,
    );
    return ArtifactDocument(
      title: title,
      summary: _summaryFromContent(cleanContent),
      sections: sections.isEmpty
          ? [ArtifactSection(title: title, body: cleanContent)]
          : sections,
      tables: tables,
      charts: charts,
      diagrams: diagrams,
      appendices: appendices,
      sourceData: sourceData,
      assumptions: assumptions,
      citations: citations,
      exportMetadata: exportMetadata,
      metadata: {
        'prompt': prompt,
        'artifactBlockCounts': {
          'sections': sections.length,
          'tables': tables.length,
          'charts': charts.length,
          'diagrams': diagrams.length,
          'appendices': appendices.length,
          'sourceData': sourceData.length,
          'assumptions': assumptions.length,
          'citations': citations.length,
        },
        if (exportMetadata.hasData)
          'exportMetadata': {
            'requestedFormats': exportMetadata.requestedFormats,
            if (exportMetadata.audience != null)
              'audience': exportMetadata.audience,
            if (exportMetadata.checkedDate != null)
              'checkedDate': exportMetadata.checkedDate,
            ...exportMetadata.fields,
          },
      },
    );
  }

  String _titleFromPrompt(String prompt) {
    final normalized = prompt
        .replaceAll(
          RegExp(
            r'\b(create|make|generate|build|export|save)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return 'Generated artifact';
    return normalized.length > 72
        ? normalized.substring(0, 72).trim()
        : normalized;
  }

  String? _titleFromMarkdown(String content) {
    final heading = RegExp(
      r'^\s*#\s+(.+)$',
      multiLine: true,
    ).firstMatch(content);
    return heading?.group(1)?.trim();
  }

  String _summaryFromContent(String content) {
    final lines = content
        .split('\n')
        .map((line) => line.trim())
        .where(
          (line) =>
              line.isNotEmpty && !line.startsWith('|') && !line.startsWith('#'),
        )
        .toList();
    if (lines.isEmpty) return 'Created from Circuit response content.';
    final summary = lines.take(2).join(' ');
    return summary.length > 220 ? '${summary.substring(0, 217)}...' : summary;
  }

  List<ArtifactSection> _extractSections(String content) {
    final sections = <ArtifactSection>[];
    final matches = RegExp(
      r'^\s{0,3}#{1,3}\s+(.+)$',
      multiLine: true,
    ).allMatches(content).toList();
    if (matches.isEmpty) return sections;
    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      final nextStart = i + 1 < matches.length
          ? matches[i + 1].start
          : content.length;
      final title = match.group(1)?.trim() ?? 'Section ${i + 1}';
      final body = content.substring(match.end, nextStart).trim();
      sections.add(
        ArtifactSection(
          title: title,
          body: _stripTables(body),
          bullets: _extractBullets(body),
        ),
      );
    }
    return sections;
  }

  String _stripTables(String value) {
    return value
        .split('\n')
        .where((line) => !(line.contains('|') && _tableCells(line).length >= 2))
        .join('\n')
        .trim();
  }

  List<String> _extractBullets(String value) {
    return value
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('- ') || line.startsWith('* '))
        .map((line) => line.substring(2).trim())
        .where((line) => line.isNotEmpty)
        .take(8)
        .toList(growable: false);
  }

  List<String> _extractListAfterHeading(String content, String headingName) {
    final heading = RegExp(
      '^\\s{0,3}#{1,4}\\s+$headingName\\b.*\$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(content);
    if (heading == null) return const [];
    final tail = content.substring(heading.end);
    final nextHeading = RegExp(
      r'^\s{0,3}#{1,4}\s+',
      multiLine: true,
    ).firstMatch(tail);
    final block = nextHeading == null
        ? tail
        : tail.substring(0, nextHeading.start);
    return _extractBullets(block);
  }

  List<String> _extractFirstListAfterAnyHeading(
    String content,
    List<String> headingNames,
  ) {
    for (final heading in headingNames) {
      final result = _extractListAfterHeading(content, heading);
      if (result.isNotEmpty) return result;
    }
    return const [];
  }

  List<ArtifactChart> _extractCharts(
    List<ArtifactSection> sections,
    List<ArtifactTable> tables,
  ) {
    final charts = <ArtifactChart>[];
    for (final section in sections) {
      final normalized = section.title.toLowerCase();
      if (!_looksLikeChartTitle(normalized)) continue;
      charts.add(
        ArtifactChart(
          title: section.title,
          type: _chartTypeFor('${section.title}\n${section.body}'),
          signals: section.bullets.isNotEmpty
              ? section.bullets
              : _firstSentences(section.body, limit: 4),
        ),
      );
    }
    for (final table in tables) {
      final normalized = table.title.toLowerCase();
      if (!_looksLikeChartTitle(normalized)) continue;
      charts.add(
        ArtifactChart(
          title: table.title,
          type: _chartTypeFor(table.title),
          signals: table.rows
              .skip(1)
              .take(4)
              .map((row) => row.join(' | '))
              .toList(),
        ),
      );
    }
    return charts;
  }

  bool _looksLikeChartTitle(String value) {
    return value.contains('chart') ||
        value.contains('graph') ||
        value.contains('timeline') ||
        value.contains('trend') ||
        value.contains('scorecard') ||
        value.contains('roadmap view');
  }

  String _chartTypeFor(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('timeline')) return 'timeline';
    if (normalized.contains('bar')) return 'bar';
    if (normalized.contains('line') || normalized.contains('trend')) {
      return 'line';
    }
    if (normalized.contains('pie') || normalized.contains('donut')) {
      return 'pie';
    }
    if (normalized.contains('score')) return 'scorecard';
    return 'unspecified';
  }

  List<ArtifactDiagram> _extractDiagrams(String content) {
    final diagrams = <ArtifactDiagram>[];
    final fenced = RegExp(
      r'```([a-zA-Z0-9_-]+)?\s*\n([\s\S]*?)```',
      multiLine: true,
    ).allMatches(content);
    for (final match in fenced) {
      final syntax = (match.group(1) ?? '').trim().toLowerCase();
      final source = (match.group(2) ?? '').trim();
      if (source.isEmpty) continue;
      final looksLikeDiagram =
          syntax == 'mermaid' ||
          syntax == 'plantuml' ||
          syntax == 'dot' ||
          syntax == 'graphviz' ||
          RegExp(
            r'\b(graph\s+(TD|LR|BT|RL)|sequenceDiagram|flowchart|digraph)\b',
            caseSensitive: false,
          ).hasMatch(source);
      if (!looksLikeDiagram) continue;
      diagrams.add(
        ArtifactDiagram(
          title: 'Diagram ${diagrams.length + 1}',
          syntax: syntax.isEmpty ? 'mermaid' : syntax,
          source: source,
        ),
      );
    }
    return diagrams;
  }

  List<ArtifactAppendix> _extractAppendices(List<ArtifactSection> sections) {
    return sections
        .where((section) {
          final normalized = section.title.toLowerCase();
          return normalized.contains('appendix') ||
              normalized.contains('supporting material') ||
              normalized.contains('raw notes') ||
              normalized.contains('source notes');
        })
        .map(
          (section) => ArtifactAppendix(
            title: section.title,
            body: section.body,
            bullets: section.bullets,
          ),
        )
        .toList(growable: false);
  }

  List<ArtifactSourceData> _extractSourceData(
    List<ArtifactSection> sections,
    List<ArtifactTable> tables,
  ) {
    final sourceData = <ArtifactSourceData>[];
    for (final table in tables) {
      final normalized = table.title.toLowerCase();
      if (normalized.contains('source data') ||
          normalized.contains('raw data') ||
          normalized.contains('dataset') ||
          normalized.contains('inventory')) {
        sourceData.add(
          ArtifactSourceData(title: table.title, rows: table.rows),
        );
      }
    }
    for (final section in sections) {
      final normalized = section.title.toLowerCase();
      if (!(normalized.contains('source data') ||
          normalized.contains('raw data') ||
          normalized.contains('dataset'))) {
        continue;
      }
      if (sourceData.any((entry) => entry.title == section.title)) continue;
      sourceData.add(
        ArtifactSourceData(title: section.title, notes: section.bullets),
      );
    }
    return sourceData;
  }

  ArtifactExportMetadata _extractExportMetadata({
    required String prompt,
    required String content,
  }) {
    final combined = '$prompt\n$content';
    final normalized = combined.toLowerCase();
    final requestedFormats = <String>[
      if (RegExp(r'\b(pptx|powerpoint|deck|slides?)\b').hasMatch(normalized))
        'pptx',
      if (RegExp(r'\b(docx|word document|word report)\b').hasMatch(normalized))
        'docx',
      if (RegExp(r'\b(pdf)\b').hasMatch(normalized)) 'pdf',
      if (RegExp(r'\b(xlsx|excel|workbook)\b').hasMatch(normalized)) 'xlsx',
      if (RegExp(r'\b(csv)\b').hasMatch(normalized)) 'csv',
      if (RegExp(r'\b(json)\b').hasMatch(normalized)) 'json',
      if (RegExp(r'\b(markdown|md)\b').hasMatch(normalized)) 'md',
      if (RegExp(r'\b(svg|diagram|topology)\b').hasMatch(normalized)) 'svg',
    ];
    return ArtifactExportMetadata(
      requestedFormats: requestedFormats.toSet().toList(growable: false),
      audience: _fieldValue(content, const ['audience', 'target audience']),
      checkedDate: _fieldValue(content, const ['checked date', 'checked']),
    );
  }

  String? _fieldValue(String content, List<String> labels) {
    for (final label in labels) {
      final match = RegExp(
        '^\\s*(?:[-*]\\s*)?$label\\s*:\\s*(.+)\$',
        caseSensitive: false,
        multiLine: true,
      ).firstMatch(content);
      final value = match?.group(1)?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  List<String> _firstSentences(String value, {required int limit}) {
    return value
        .split(RegExp(r'(?<=[.!?])\s+|\n+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .take(limit)
        .toList(growable: false);
  }

  List<ArtifactTable> _extractTables(String content) {
    final tables = <ArtifactTable>[];
    var current = <String>[];
    String? currentTitle;
    String? pendingTitle;
    for (final raw in content.split('\n')) {
      final line = raw.trim();
      final heading = RegExp(r'^\s{0,3}#{1,4}\s+(.+)$').firstMatch(raw);
      if (heading != null) {
        _flushTable(current, tables, currentTitle);
        current = <String>[];
        currentTitle = null;
        pendingTitle = heading.group(1)?.trim();
        continue;
      }
      final looksLikeRow = line.contains('|') && _tableCells(line).length >= 2;
      if (looksLikeRow) {
        currentTitle ??= pendingTitle;
        current.add(line);
        continue;
      }
      _flushTable(current, tables, currentTitle);
      current = <String>[];
      currentTitle = null;
    }
    _flushTable(current, tables, currentTitle);
    return tables;
  }

  void _flushTable(
    List<String> current,
    List<ArtifactTable> tables,
    String? title,
  ) {
    if (current.length < 2) return;
    final rows = <List<String>>[];
    for (final line in current) {
      final cells = _tableCells(line);
      if (cells.every((cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell))) {
        continue;
      }
      if (cells.isNotEmpty) rows.add(cells);
    }
    if (rows.length >= 2) {
      tables.add(
        ArtifactTable(
          title: title?.trim().isNotEmpty == true
              ? title!.trim()
              : 'Table ${tables.length + 1}',
          rows: rows,
        ),
      );
    }
  }

  List<String> _tableCells(String line) {
    var trimmed = line.trim();
    if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
    if (trimmed.endsWith('|')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed
        .split('|')
        .map((cell) => cell.trim())
        .where((cell) => cell.isNotEmpty)
        .toList();
  }
}
