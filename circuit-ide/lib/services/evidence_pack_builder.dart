import 'dart:convert';

import '../models/artifact_document.dart';

class EvidencePackBuilder {
  const EvidencePackBuilder();

  bool matches(String prompt) {
    final normalized = prompt.toLowerCase();
    return RegExp(
      r'\b(evidence pack|citation pack|source pack|sources report|source report|evidence review|fact check|fact-check|source validation|claim validation|unsupported claims?|checked dates?|confidence notes?)\b',
    ).hasMatch(normalized);
  }

  ArtifactDocument build({
    required String prompt,
    required String content,
    required ArtifactDocument document,
  }) {
    final sourceBullets = _sourceBullets(document, content);
    final unsupportedBullets = _unsupportedBullets(document, content);
    final sections = <ArtifactSection>[
      _section(
        document,
        title: 'Evidence Summary',
        patterns: const ['evidence summary', 'summary', 'overview'],
        fallbackBody: document.summary,
      ),
      _section(
        document,
        title: 'Claim Register',
        patterns: const ['claim register', 'claims', 'validated claims'],
        fallbackBody:
            'List each material claim, the supporting source, checked date, confidence, and any caveats.',
      ),
      _section(
        document,
        title: 'Source Inventory',
        patterns: const [
          'source inventory',
          'sources',
          'citations',
          'references',
        ],
        fallbackBody:
            'Authoritative sources, URLs, checked dates, and source notes used for this output.',
        fallbackBullets: sourceBullets,
      ),
      _section(
        document,
        title: 'Checked Dates',
        patterns: const ['checked dates', 'checked date', 'freshness'],
        fallbackBody:
            'Record when each source was checked and whether the information is time-sensitive.',
      ),
      _section(
        document,
        title: 'Assumptions And Unknowns',
        patterns: const ['assumptions', 'unknowns', 'open questions'],
        fallbackBody:
            'Assumptions and missing inputs that should be validated before customer-facing use.',
        fallbackBullets: document.assumptions,
      ),
      _section(
        document,
        title: 'Confidence And Risk',
        patterns: const ['confidence', 'risk', 'confidence and risk'],
        fallbackBody:
            'Summarize confidence levels and risks created by stale, missing, or indirect evidence.',
      ),
      _section(
        document,
        title: 'Unsupported Claims / Follow-Up',
        patterns: const [
          'unsupported claims',
          'follow-up',
          'follow up',
          'needs validation',
        ],
        fallbackBody:
            'Claims without enough support should be verified or removed before final handoff.',
        fallbackBullets: unsupportedBullets,
      ),
    ];

    return ArtifactDocument(
      title: _title(document.title, prompt),
      summary: document.summary,
      sections: sections,
      tables: document.tables,
      assumptions: document.assumptions,
      citations: sourceBullets,
      metadata: {
        ...document.metadata,
        'artifactTemplate': 'evidence_pack',
        'sourcePrompt': prompt,
      },
    );
  }

  String toJsonString(ArtifactDocument document) {
    final encoded = {
      'title': document.title,
      'summary': document.summary,
      'sections': [
        for (final section in document.sections)
          {
            'title': section.title,
            'body': section.body,
            'bullets': section.bullets,
          },
      ],
      'tables': [
        for (final table in document.tables)
          {'title': table.title, 'rows': table.rows},
      ],
      'assumptions': document.assumptions,
      'sources': document.citations,
      'metadata': document.metadata,
    };
    return const JsonEncoder.withIndent('  ').convert(encoded);
  }

  String _title(String currentTitle, String prompt) {
    final title = currentTitle.trim();
    if (title.isNotEmpty && title != 'Generated artifact') return title;
    final cleaned = prompt
        .replaceAll(
          RegExp(
            r'\b(create|make|generate|build|export|save|write)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'Evidence Pack';
    return cleaned.length > 72 ? cleaned.substring(0, 72).trim() : cleaned;
  }

  ArtifactSection _section(
    ArtifactDocument document, {
    required String title,
    required List<String> patterns,
    required String fallbackBody,
    List<String> fallbackBullets = const [],
  }) {
    final existing = _matchingSection(document.sections, patterns);
    if (existing != null) {
      return ArtifactSection(
        title: title,
        body: existing.body,
        bullets: existing.bullets.isEmpty ? fallbackBullets : existing.bullets,
      );
    }
    return ArtifactSection(
      title: title,
      body: fallbackBody,
      bullets: fallbackBullets,
    );
  }

  ArtifactSection? _matchingSection(
    List<ArtifactSection> sections,
    List<String> patterns,
  ) {
    for (final section in sections) {
      final normalized = section.title.toLowerCase();
      if (patterns.any(normalized.contains)) return section;
    }
    return null;
  }

  List<String> _sourceBullets(ArtifactDocument document, String content) {
    final values = <String>[...document.citations, ..._urlMatches(content)];
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .take(20)
        .toList(growable: false);
  }

  List<String> _unsupportedBullets(ArtifactDocument document, String content) {
    final section = _matchingSection(document.sections, const [
      'unsupported',
      'needs validation',
      'unknown',
      'follow-up',
      'follow up',
    ]);
    if (section != null && section.bullets.isNotEmpty) return section.bullets;
    final lines = content
        .split('\n')
        .map((line) => line.trim())
        .where(
          (line) =>
              line.toLowerCase().contains('unsupported') ||
              line.toLowerCase().contains('needs validation') ||
              line.toLowerCase().contains('unknown'),
        )
        .map((line) => line.replaceFirst(RegExp(r'^[-*]\s*'), ''))
        .where((line) => line.isNotEmpty)
        .take(10)
        .toList(growable: false);
    return lines;
  }

  Iterable<String> _urlMatches(String content) {
    return RegExp(r'https?://[^\s\])>]+')
        .allMatches(content)
        .map((match) => match.group(0) ?? '')
        .where((value) => value.isNotEmpty);
  }
}
