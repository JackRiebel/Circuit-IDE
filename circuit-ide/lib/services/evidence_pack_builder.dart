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
    final tables = [
      ..._evidencePackTables(
        sourceBullets: sourceBullets,
        unsupportedBullets: unsupportedBullets,
        document: document,
        sections: sections,
      ),
      ...document.tables,
    ];

    return ArtifactDocument(
      title: _title(document.title, prompt),
      summary: document.summary,
      sections: sections,
      tables: tables,
      assumptions: document.assumptions,
      citations: sourceBullets,
      metadata: {
        ...document.metadata,
        'artifactTemplate': 'evidence_pack',
        'sourcePrompt': prompt,
        'sourceCount': sourceBullets.length,
        'unsupportedClaimCount': unsupportedBullets.length,
        'evidencePackTables': tables.length,
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

  List<ArtifactTable> _evidencePackTables({
    required List<String> sourceBullets,
    required List<String> unsupportedBullets,
    required ArtifactDocument document,
    required List<ArtifactSection> sections,
  }) {
    return [
      ArtifactTable(
        title: 'Claim To Source Matrix',
        rows: [
          const [
            'Claim',
            'Supporting source',
            'Checked date',
            'Confidence',
            'Caveat / validation need',
          ],
          ..._claimRows(sourceBullets, sections),
        ],
      ),
      ArtifactTable(
        title: 'Source Freshness Register',
        rows: [
          const [
            'Source',
            'URL / reference',
            'Checked date',
            'Freshness risk',
            'Owner action',
          ],
          ..._sourceRows(sourceBullets),
        ],
      ),
      ArtifactTable(
        title: 'Unsupported Claim Triage',
        rows: [
          const ['Claim', 'Risk', 'Required evidence', 'Disposition'],
          ..._unsupportedRows(unsupportedBullets),
        ],
      ),
      ArtifactTable(
        title: 'Evidence Confidence Scorecard',
        rows: [
          const ['Area', 'Status', 'Confidence', 'Notes'],
          ..._confidenceRows(
            sourceBullets: sourceBullets,
            unsupportedBullets: unsupportedBullets,
            assumptions: document.assumptions,
          ),
        ],
      ),
      ArtifactTable(
        title: 'Customer Follow-Up Checklist',
        rows: [
          const ['Question', 'Owner', 'Needed before final?'],
          ..._followUpRows(unsupportedBullets, document.assumptions),
        ],
      ),
    ];
  }

  List<List<String>> _claimRows(
    List<String> sourceBullets,
    List<ArtifactSection> sections,
  ) {
    final claims = _bulletsFor(sections, const [
      'claim register',
      'claims',
      'validated claims',
    ]);
    final rows = <List<String>>[];
    final candidates = claims.isEmpty
        ? const ['Material claim requires source mapping.']
        : claims.take(12);
    var index = 0;
    for (final claim in candidates) {
      final source = sourceBullets.isEmpty
          ? 'Missing cited source'
          : sourceBullets[index % sourceBullets.length];
      rows.add([
        claim,
        _sourceLabel(source),
        _checkedDate(source),
        _confidenceFor(claim, source),
        _caveatFor(claim, source),
      ]);
      index++;
    }
    return rows;
  }

  List<List<String>> _sourceRows(List<String> sourceBullets) {
    if (sourceBullets.isEmpty) {
      return const [
        [
          'No source supplied',
          'Missing',
          'Not checked',
          'High',
          'Add authoritative source and checked date.',
        ],
      ];
    }
    return sourceBullets
        .take(20)
        .map((source) {
          return [
            _sourceLabel(source),
            _sourceUrl(source),
            _checkedDate(source),
            _freshnessRisk(source),
            _ownerAction(source),
          ];
        })
        .toList(growable: false);
  }

  List<List<String>> _unsupportedRows(List<String> unsupportedBullets) {
    if (unsupportedBullets.isEmpty) {
      return const [
        [
          'No unsupported claims identified',
          'Low',
          'Maintain citation hygiene.',
          'Ready for review.',
        ],
      ];
    }
    return unsupportedBullets
        .take(12)
        .map((claim) {
          return [
            _cleanBullet(claim),
            'Medium until supported or removed.',
            'Official source, customer data, checked date, or SME confirmation.',
            'Verify, qualify, or remove before customer handoff.',
          ];
        })
        .toList(growable: false);
  }

  List<List<String>> _confidenceRows({
    required List<String> sourceBullets,
    required List<String> unsupportedBullets,
    required List<String> assumptions,
  }) {
    return [
      [
        'Source coverage',
        sourceBullets.isEmpty ? 'Missing sources' : 'Sources attached',
        sourceBullets.isEmpty ? 'Low' : 'Medium',
        sourceBullets.isEmpty
            ? 'Add official or customer-provided evidence.'
            : 'Verify freshness and source authority before final use.',
      ],
      [
        'Unsupported claims',
        unsupportedBullets.isEmpty ? 'None flagged' : 'Follow-up required',
        unsupportedBullets.isEmpty ? 'Medium' : 'Low',
        unsupportedBullets.isEmpty
            ? 'Continue checking claims against source material.'
            : 'Resolve each unsupported claim before customer handoff.',
      ],
      [
        'Assumptions',
        assumptions.isEmpty
            ? 'No assumptions captured'
            : 'Assumptions captured',
        assumptions.isEmpty ? 'Medium' : 'Low until confirmed',
        assumptions.isEmpty
            ? 'Add assumptions if scope or source freshness is uncertain.'
            : 'Confirm assumptions with customer or account team.',
      ],
    ];
  }

  List<List<String>> _followUpRows(
    List<String> unsupportedBullets,
    List<String> assumptions,
  ) {
    final rows = <List<String>>[
      const [
        'Which claims require official source validation before customer use?',
        'Evidence reviewer',
        'Yes',
      ],
      const [
        'Are all checked dates current enough for the decision window?',
        'Account team',
        'Yes',
      ],
      const [
        'Which assumptions need customer confirmation?',
        'Customer sponsor',
        'Yes',
      ],
    ];
    for (final claim in unsupportedBullets.take(3)) {
      rows.add([
        'What evidence supports "${_shorten(_cleanBullet(claim), 80)}"?',
        'Research owner',
        'Yes',
      ]);
    }
    for (final assumption in assumptions.take(3)) {
      rows.add([
        'Can the customer confirm "${_shorten(_cleanBullet(assumption), 80)}"?',
        'Customer / account team',
        'Yes',
      ]);
    }
    return rows;
  }

  List<String> _bulletsFor(List<ArtifactSection> sections, List<String> terms) {
    final normalizedTerms = terms.map((term) => term.toLowerCase()).toList();
    final values = <String>[];
    for (final section in sections) {
      final title = section.title.toLowerCase();
      if (!normalizedTerms.any(title.contains)) continue;
      values.addAll(section.bullets);
      if (section.body.trim().isNotEmpty) {
        values.addAll(_sentences(section.body).take(4));
      }
    }
    return values
        .map(_cleanBullet)
        .where((value) => value.isNotEmpty)
        .toSet()
        .take(20)
        .toList(growable: false);
  }

  List<String> _sentences(String value) {
    return RegExp(r'[^.!?]+[.!?]?')
        .allMatches(value)
        .map((match) => match.group(0)?.trim() ?? '')
        .where((sentence) => sentence.isNotEmpty)
        .toList(growable: false);
  }

  String _sourceLabel(String source) {
    final cleaned = _cleanBullet(source);
    final withoutUrl = cleaned.replaceAll(RegExp(r'https?://\S+'), '').trim();
    final beforeChecked = withoutUrl
        .split(RegExp(r'\s+[-\u2013\u2014]\s+checked\s+', caseSensitive: false))
        .first
        .trim();
    if (beforeChecked.isEmpty) return _shorten(cleaned, 90);
    return _shorten(beforeChecked, 90);
  }

  String _sourceUrl(String source) {
    return RegExp(
          r'https?://[^\s\])>]+',
        ).firstMatch(source)?.group(0)?.trim() ??
        'No URL captured';
  }

  String _checkedDate(String source) {
    final iso = RegExp(r'\b20\d{2}-\d{2}-\d{2}\b').firstMatch(source);
    if (iso != null) return iso.group(0) ?? 'Not provided';
    final checked = RegExp(
      r'checked\s+([A-Za-z]{3,9}\s+\d{1,2},?\s+20\d{2}|20\d{2})',
      caseSensitive: false,
    ).firstMatch(source);
    return checked?.group(1)?.trim() ?? 'Not provided';
  }

  String _freshnessRisk(String source) {
    final checkedDate = _checkedDate(source);
    if (checkedDate == 'Not provided') return 'High - missing checked date';
    final lower = source.toLowerCase();
    if (lower.contains('api') || lower.contains('official')) {
      return 'Low if rechecked before handoff';
    }
    return 'Medium - verify source freshness';
  }

  String _ownerAction(String source) {
    final lower = source.toLowerCase();
    if (lower.contains('cisco') || lower.contains('official')) {
      return 'Refresh official source before final recommendation.';
    }
    if (lower.contains('customer') || lower.contains('workshop')) {
      return 'Confirm customer-provided evidence with sponsor.';
    }
    return 'Validate authority, date, and relevance.';
  }

  String _confidenceFor(String claim, String source) {
    final lower = '$claim $source'.toLowerCase();
    if (source.contains('Missing cited source')) return 'Low';
    if (lower.contains('official') || lower.contains('api')) return 'Medium';
    if (lower.contains('unsupported') || lower.contains('unknown')) {
      return 'Low';
    }
    return 'Medium';
  }

  String _caveatFor(String claim, String source) {
    final lower = '$claim $source'.toLowerCase();
    if (source.contains('Missing cited source')) {
      return 'Add authoritative evidence before customer use.';
    }
    if (lower.contains('replacement') || lower.contains('recommendation')) {
      return 'Validate current portfolio fit; do not rely on migration hint alone.';
    }
    if (_checkedDate(source) == 'Not provided') {
      return 'Add checked date and freshness note.';
    }
    return 'Verify source freshness and claim wording before final handoff.';
  }

  String _cleanBullet(String value) {
    return value
        .replaceFirst(RegExp(r'^[-*]\s+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _shorten(String value, int maxLength) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength - 1).trim()}...';
  }
}
