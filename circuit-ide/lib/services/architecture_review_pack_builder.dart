import '../models/artifact_document.dart';

class ArchitectureReviewPackBuilder {
  const ArchitectureReviewPackBuilder();

  bool matches(String prompt) {
    final normalized = prompt.toLowerCase();
    return RegExp(
      r'\b(architecture review|design review|review pack|risk review|findings and recommendations|architecture assessment|design assessment|validated design review|technical review|solution review)\b',
    ).hasMatch(normalized);
  }

  ArtifactDocument build({
    required String prompt,
    required String content,
    required ArtifactDocument document,
  }) {
    final sections = <ArtifactSection>[
      _section(
        document,
        title: 'Architecture Review Summary',
        patterns: const ['architecture review', 'summary', 'overview'],
        fallbackBody: document.summary,
      ),
      _section(
        document,
        title: 'Current Architecture Snapshot',
        patterns: const [
          'current architecture',
          'current state',
          'environment',
          'architecture',
          'topology',
        ],
        fallbackBody:
            'Capture the current topology, major components, dependencies, and known operating constraints.',
      ),
      _section(
        document,
        title: 'Design Objectives',
        patterns: const [
          'design objectives',
          'objectives',
          'goals',
          'requirements',
          'success criteria',
        ],
        fallbackBody:
            'Document the business and technical outcomes the architecture must satisfy.',
      ),
      _section(
        document,
        title: 'Key Findings',
        patterns: const ['key findings', 'findings', 'observations', 'gaps'],
        fallbackBody:
            'List validated findings, design gaps, and important observations from the review.',
      ),
      _section(
        document,
        title: 'Risk Register',
        patterns: const [
          'risk register',
          'risks',
          'concerns',
          'issues',
          'caveats',
        ],
        fallbackBody:
            'Prioritize architecture risks by severity, impact, evidence, and mitigation path.',
      ),
      _section(
        document,
        title: 'Recommendations',
        patterns: const [
          'recommendations',
          'recommended',
          'remediation',
          'improvements',
          'solution',
        ],
        fallbackBody:
            'Map each finding and risk to a recommended design action and implementation owner.',
      ),
      _section(
        document,
        title: 'Validation Plan',
        patterns: const [
          'validation',
          'verification',
          'test plan',
          'acceptance',
          'checks',
        ],
        fallbackBody:
            'Define the checks, data, lab tests, design reviews, or customer confirmations needed before approval.',
      ),
      _section(
        document,
        title: 'Decision Log',
        patterns: const ['decision log', 'decisions', 'tradeoffs', 'options'],
        fallbackBody:
            'Track design decisions, alternatives considered, decision owners, and unresolved tradeoffs.',
      ),
      _section(
        document,
        title: 'Assumptions',
        patterns: const ['assumptions', 'unknowns', 'dependencies'],
        fallbackBody:
            'Validate assumptions before treating recommendations as final.',
        fallbackBullets: document.assumptions,
      ),
      _section(
        document,
        title: 'Sources / Evidence',
        patterns: const ['sources', 'evidence', 'citations', 'references'],
        fallbackBody:
            'Attach source material, checked dates, diagrams, configs, workshop notes, or design guides used in the review.',
        fallbackBullets: document.citations,
      ),
    ];
    final tables = [
      ..._reviewTables(document: document, sections: sections),
      ...document.tables,
    ];
    final findingCount = _tableDataRowCount(
      tables,
      'Architecture Findings Matrix',
    );
    final riskCount = _tableDataRowCount(
      tables,
      'Risk And Mitigation Register',
    );
    final validationCount = _tableDataRowCount(tables, 'Validation Checklist');
    return ArtifactDocument(
      title: _title(document.title, prompt),
      summary: document.summary,
      sections: sections,
      tables: tables,
      assumptions: document.assumptions,
      citations: document.citations,
      metadata: {
        ...document.metadata,
        'artifactTemplate': 'architecture_review_pack',
        'sourcePrompt': prompt,
        'architectureReviewTables': tables.length,
        'architectureFindingCount': findingCount,
        'architectureRiskCount': riskCount,
        'architectureValidationCount': validationCount,
      },
    );
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
    if (cleaned.isEmpty) return 'Architecture Review Pack';
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

  int _tableDataRowCount(List<ArtifactTable> tables, String title) {
    for (final table in tables) {
      if (table.title == title) {
        return table.rows.length > 1 ? table.rows.length - 1 : 0;
      }
    }
    return 0;
  }

  List<ArtifactTable> _reviewTables({
    required ArtifactDocument document,
    required List<ArtifactSection> sections,
  }) {
    return [
      ArtifactTable(
        title: 'Architecture Findings Matrix',
        rows: [
          const ['Finding', 'Severity', 'Evidence', 'Impact', 'Recommendation'],
          ..._findingRows(sections),
        ],
      ),
      ArtifactTable(
        title: 'Risk And Mitigation Register',
        rows: [
          const ['Risk', 'Severity', 'Affected area', 'Mitigation', 'Owner'],
          ..._riskRows(sections),
        ],
      ),
      ArtifactTable(
        title: 'Recommendation Roadmap',
        rows: [
          const ['Phase', 'Recommendation', 'Dependency', 'Success signal'],
          ..._roadmapRows(sections),
        ],
      ),
      ArtifactTable(
        title: 'Validation Checklist',
        rows: [
          const ['Validation item', 'Method', 'Owner', 'Exit criteria'],
          ..._validationRows(sections, document),
        ],
      ),
      ArtifactTable(
        title: 'Decision And Assumption Log',
        rows: [
          const ['Item', 'Type', 'Owner', 'Review action'],
          ..._decisionRows(sections, document),
        ],
      ),
    ];
  }

  List<List<String>> _findingRows(List<ArtifactSection> sections) {
    final findings = _bulletsFor(sections, const [
      'key findings',
      'findings',
      'observations',
      'gaps',
    ]);
    final recommendations = _bulletsFor(sections, const [
      'recommendations',
      'recommended',
      'remediation',
      'improvements',
      'solution',
    ]);
    final candidates = findings.isEmpty
        ? const ['Architecture finding needs stakeholder validation.']
        : findings.take(10);
    var index = 0;
    return candidates
        .map((finding) {
          final recommendation = recommendations.isEmpty
              ? 'Define owner, target state, and implementation path.'
              : recommendations[index++ % recommendations.length];
          return [
            finding,
            _severityFor(finding),
            'Workshop notes, diagrams, configs, telemetry, or validated source evidence.',
            _impactFor(finding),
            recommendation,
          ];
        })
        .toList(growable: false);
  }

  List<List<String>> _riskRows(List<ArtifactSection> sections) {
    final risks = _bulletsFor(sections, const [
      'risk register',
      'risks',
      'concerns',
      'issues',
      'caveats',
    ]);
    final candidates = risks.isEmpty
        ? const ['No explicit risks supplied; run stakeholder review.']
        : risks.take(10);
    return candidates
        .map((risk) {
          return [
            risk,
            _severityFor(risk),
            _areaFor(risk),
            _mitigationFor(risk),
            _ownerFor(risk),
          ];
        })
        .toList(growable: false);
  }

  List<List<String>> _roadmapRows(List<ArtifactSection> sections) {
    final recommendations = _bulletsFor(sections, const [
      'recommendations',
      'recommended',
      'remediation',
      'improvements',
      'solution',
    ]);
    final candidates = recommendations.isEmpty
        ? const ['Turn validated findings into prioritized remediation work.']
        : recommendations.take(9);
    final phases = ['Now', 'Next', 'Later'];
    var index = 0;
    return candidates
        .map((recommendation) {
          final phase = phases[index % phases.length];
          index++;
          return [
            phase,
            recommendation,
            'Validated requirement, owner, source evidence, and implementation window.',
            _successSignalFor(recommendation),
          ];
        })
        .toList(growable: false);
  }

  List<List<String>> _validationRows(
    List<ArtifactSection> sections,
    ArtifactDocument document,
  ) {
    final validation = _bulletsFor(sections, const [
      'validation',
      'verification',
      'test plan',
      'acceptance',
      'checks',
    ]);
    final rows = <List<String>>[
      const [
        'Confirm target-state requirements',
        'Stakeholder review',
        'Business / technical owner',
        'Requirements accepted or revised.',
      ],
      const [
        'Validate risks and assumptions',
        'Evidence review',
        'Architecture reviewer',
        'High-risk assumptions have owners.',
      ],
    ];
    for (final item in validation.take(8)) {
      rows.add([
        item,
        _methodFor(item),
        _ownerFor(item),
        'Pass/fail outcome and evidence recorded.',
      ]);
    }
    if (document.citations.isNotEmpty) {
      rows.add([
        'Verify source freshness',
        'Citation check',
        'Evidence reviewer',
        '${document.citations.length} source item${document.citations.length == 1 ? '' : 's'} checked before handoff.',
      ]);
    }
    return rows;
  }

  List<List<String>> _decisionRows(
    List<ArtifactSection> sections,
    ArtifactDocument document,
  ) {
    final decisions = _bulletsFor(sections, const [
      'decision log',
      'decisions',
      'tradeoffs',
      'options',
    ]);
    final rows = <List<String>>[];
    for (final decision in decisions.take(8)) {
      rows.add([
        decision,
        'Decision / tradeoff',
        'Architecture owner',
        'Confirm decision owner, rationale, and revisit trigger.',
      ]);
    }
    for (final assumption in document.assumptions.take(8)) {
      rows.add([
        assumption,
        'Assumption',
        'Customer / account team',
        'Confirm before final recommendation.',
      ]);
    }
    if (rows.isEmpty) {
      rows.add(const [
        'Decision log not supplied',
        'Open item',
        'Architecture owner',
        'Capture decisions and assumptions during review.',
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
        .map(_clean)
        .where((value) => value.isNotEmpty)
        .toSet()
        .take(16)
        .toList(growable: false);
  }

  List<String> _sentences(String value) {
    return RegExp(r'[^.!?]+[.!?]?')
        .allMatches(value)
        .map((match) => match.group(0)?.trim() ?? '')
        .where((sentence) => sentence.isNotEmpty)
        .toList(growable: false);
  }

  String _severityFor(String value) {
    final lower = value.toLowerCase();
    if (RegExp(
      r'\b(critical|outage|security|unsupported|eol|failed)\b',
    ).hasMatch(lower)) {
      return 'High';
    }
    if (RegExp(
      r'\b(risk|gap|validate|confirm|limited|unknown)\b',
    ).hasMatch(lower)) {
      return 'Medium';
    }
    return 'Review';
  }

  String _impactFor(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('security') || lower.contains('access')) {
      return 'Security posture, compliance, segmentation, or incident response can be affected.';
    }
    if (lower.contains('wan') ||
        lower.contains('network') ||
        lower.contains('connectivity')) {
      return 'Availability, application performance, failover, and operations can be affected.';
    }
    if (lower.contains('power') ||
        lower.contains('poe') ||
        lower.contains('uplink')) {
      return 'Capacity, access-layer readiness, and future device support can be affected.';
    }
    return 'Architecture confidence, delivery risk, or customer outcome can be affected.';
  }

  String _areaFor(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('security') || lower.contains('access')) {
      return 'Security';
    }
    if (lower.contains('wan') || lower.contains('connectivity')) return 'WAN';
    if (lower.contains('wireless') ||
        lower.contains('wifi') ||
        lower.contains('wi-fi')) {
      return 'Wireless';
    }
    if (lower.contains('switch') ||
        lower.contains('uplink') ||
        lower.contains('poe')) {
      return 'Campus / access';
    }
    if (lower.contains('cloud') || lower.contains('saas')) return 'Cloud / app';
    return 'Architecture';
  }

  String _mitigationFor(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('security') || lower.contains('access')) {
      return 'Review controls, segmentation, identity, logging, and approval gates.';
    }
    if (lower.contains('capacity') ||
        lower.contains('poe') ||
        lower.contains('uplink')) {
      return 'Validate capacity model, growth assumptions, and bill of materials.';
    }
    if (lower.contains('unsupported') ||
        lower.contains('eol') ||
        lower.contains('lifecycle')) {
      return 'Validate lifecycle dates and replacement suitability from current portfolio facts.';
    }
    return 'Assign owner, capture evidence, validate target state, and define acceptance criteria.';
  }

  String _ownerFor(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('security') || lower.contains('access')) {
      return 'Security owner';
    }
    if (lower.contains('wan') ||
        lower.contains('network') ||
        lower.contains('switch') ||
        lower.contains('wireless')) {
      return 'Network owner';
    }
    if (lower.contains('business') || lower.contains('outcome')) {
      return 'Business sponsor';
    }
    return 'Architecture owner';
  }

  String _methodFor(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('test') || lower.contains('lab')) return 'Lab test';
    if (lower.contains('source') || lower.contains('evidence')) {
      return 'Source review';
    }
    if (lower.contains('config') || lower.contains('telemetry')) {
      return 'Config / telemetry review';
    }
    return 'Stakeholder review';
  }

  String _successSignalFor(String recommendation) {
    final lower = recommendation.toLowerCase();
    if (lower.contains('security') || lower.contains('access')) {
      return 'Approved security controls and measurable risk reduction.';
    }
    if (lower.contains('wan') || lower.contains('connectivity')) {
      return 'Validated availability, failover, and performance targets.';
    }
    if (lower.contains('poe') ||
        lower.contains('uplink') ||
        lower.contains('capacity')) {
      return 'Capacity model accepted with growth headroom.';
    }
    return 'Owner accepts recommendation, evidence, and implementation path.';
  }

  String _clean(String value) {
    return value
        .replaceFirst(RegExp(r'^[-*]\s+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
