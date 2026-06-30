import '../models/artifact_document.dart';

class BusinessUseCaseBriefBuilder {
  const BusinessUseCaseBriefBuilder();

  bool matches(String prompt) {
    final normalized = prompt.toLowerCase();
    return RegExp(
      r'\b(business case|business use cases?|use case brief|company research|market research|industry research|executive brief|customer brief|account plan|sales play|value proposition|roi analysis|case study)\b',
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
        title: 'Executive Summary',
        patterns: const ['executive summary', 'summary', 'overview'],
        fallbackBody: document.summary,
      ),
      _section(
        document,
        title: 'Company / Industry Context',
        patterns: const [
          'company context',
          'industry context',
          'market context',
          'company',
          'industry',
          'context',
        ],
        fallbackBody:
            'Capture the customer profile, operating environment, and industry signals that shape the use cases.',
      ),
      _section(
        document,
        title: 'Pain Points And Signals',
        patterns: const [
          'pain points',
          'business pain',
          'signals',
          'challenges',
          'problems',
          'current state',
        ],
        fallbackBody:
            'List the operational, technical, and business signals that justify the proposed initiatives.',
      ),
      _section(
        document,
        title: 'Priority Use Cases',
        patterns: const [
          'priority use cases',
          'use cases',
          'business use cases',
          'opportunities',
        ],
        fallbackBody:
            'Prioritize the use cases by customer value, feasibility, and urgency.',
      ),
      _section(
        document,
        title: 'Recommended Solutions',
        patterns: const [
          'recommended solutions',
          'recommendations',
          'solution',
          'architecture',
          'approach',
        ],
        fallbackBody:
            'Map each use case to the recommended solution motion, products, services, or implementation approach.',
      ),
      _section(
        document,
        title: 'Value And Impact',
        patterns: const [
          'value and impact',
          'impact',
          'value',
          'roi',
          'benefits',
          'outcomes',
        ],
        fallbackBody:
            'Describe expected business impact, measurable outcomes, and any ROI assumptions that need validation.',
      ),
      _section(
        document,
        title: 'Next Steps',
        patterns: const [
          'next steps',
          'action plan',
          'follow up',
          'implementation',
        ],
        fallbackBody:
            'Define the discovery, validation, and stakeholder alignment steps needed before implementation.',
      ),
      _section(
        document,
        title: 'Assumptions',
        patterns: const ['assumptions', 'unknowns', 'dependencies'],
        fallbackBullets: document.assumptions,
        fallbackBody:
            'Validate these assumptions with the customer before treating the recommendations as final.',
      ),
      _section(
        document,
        title: 'Sources / Evidence',
        patterns: const ['sources', 'evidence', 'citations', 'references'],
        fallbackBullets: document.citations,
        fallbackBody:
            'Attach public research, customer-provided data, checked dates, and confidence notes for every material claim.',
      ),
    ];

    return ArtifactDocument(
      title: _title(document.title, prompt),
      summary: document.summary,
      sections: sections,
      tables: document.tables,
      assumptions: document.assumptions,
      citations: document.citations,
      metadata: {
        ...document.metadata,
        'artifactTemplate': 'business_use_case_brief',
        'sourcePrompt': prompt,
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
    if (cleaned.isEmpty) return 'Business Use Case Brief';
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
}
