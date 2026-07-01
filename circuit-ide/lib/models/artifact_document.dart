class ArtifactDocument {
  final String title;
  final String summary;
  final List<ArtifactSection> sections;
  final List<ArtifactTable> tables;
  final List<String> assumptions;
  final List<String> citations;
  final Map<String, Object?> metadata;

  const ArtifactDocument({
    required this.title,
    required this.summary,
    this.sections = const [],
    this.tables = const [],
    this.assumptions = const [],
    this.citations = const [],
    this.metadata = const {},
  });

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
    return ArtifactDocument(
      title: title,
      summary: _summaryFromContent(cleanContent),
      sections: sections.isEmpty
          ? [ArtifactSection(title: title, body: cleanContent)]
          : sections,
      tables: tables,
      assumptions: _extractListAfterHeading(cleanContent, 'assumptions'),
      citations: _extractListAfterHeading(cleanContent, 'sources'),
      metadata: {'prompt': prompt},
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
