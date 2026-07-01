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
        title: 'Stakeholders And Workflows',
        patterns: const [
          'stakeholders',
          'personas',
          'workflow',
          'workflows',
          'users',
          'buying committee',
        ],
        fallbackBody:
            'Identify business sponsors, technical owners, operators, and the workflows each use case improves.',
      ),
      _section(
        document,
        title: 'Evidence And Confidence',
        patterns: const [
          'evidence',
          'confidence',
          'sources',
          'research',
          'citations',
          'proof',
        ],
        fallbackBullets: document.citations,
        fallbackBody:
            'Document the sources, checked dates, confidence levels, and unsupported claims behind each recommendation.',
      ),
      _section(
        document,
        title: 'Customer Discovery Questions',
        patterns: const [
          'discovery questions',
          'questions',
          'discovery',
          'follow-up questions',
        ],
        fallbackBody:
            'Use these questions to validate business pains, data availability, success metrics, and decision owners.',
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
    final tables = [
      ..._businessBriefTables(
        prompt: prompt,
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
      citations: document.citations,
      metadata: {
        ...document.metadata,
        'artifactTemplate': 'business_use_case_brief',
        'sourcePrompt': prompt,
        'businessBriefTables': tables.length,
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

  List<ArtifactTable> _businessBriefTables({
    required String prompt,
    required ArtifactDocument document,
    required List<ArtifactSection> sections,
  }) {
    return [
      ArtifactTable(
        title: 'Use Case Prioritization Matrix',
        rows: [
          const [
            'Use case',
            'Business pain',
            'Target persona',
            'Value hypothesis',
            'Feasibility',
            'Evidence needed',
            'Next validation',
          ],
          ..._useCaseRows(sections),
        ],
      ),
      ArtifactTable(
        title: 'Solution Mapping',
        rows: [
          const [
            'Use case',
            'Recommended solution motion',
            'Cisco / Circuit angle',
            'Required customer inputs',
            'Success metric',
          ],
          ..._solutionRows(sections),
        ],
      ),
      ArtifactTable(
        title: 'Stakeholder Discovery Map',
        rows: [
          const [
            'Stakeholder / persona',
            'Workflow or decision area',
            'Discovery question',
            'Decision need',
          ],
          ..._stakeholderRows(prompt, sections),
        ],
      ),
      ArtifactTable(
        title: 'Evidence And Confidence Register',
        rows: [
          const [
            'Claim / recommendation',
            'Evidence needed',
            'Source status',
            'Confidence',
          ],
          ..._evidenceRows(document, sections),
        ],
      ),
      ArtifactTable(
        title: '30 / 60 / 90 Day Action Plan',
        rows: [
          const ['Window', 'Action', 'Owner', 'Output'],
          ..._actionPlanRows(sections),
        ],
      ),
    ];
  }

  List<List<String>> _useCaseRows(List<ArtifactSection> sections) {
    final useCases = _bulletsFor(sections, const [
      'priority use cases',
      'use cases',
      'opportunities',
    ]);
    final pains = _bulletsFor(sections, const [
      'pain',
      'signals',
      'challenges',
      'current state',
    ]);
    final rows = <List<String>>[];
    final candidates = useCases.isEmpty
        ? const ['Define priority use cases with the customer.']
        : useCases.take(8);
    var index = 0;
    for (final useCase in candidates) {
      final pain = pains.isEmpty
          ? 'Business pain needs validation.'
          : pains[index % pains.length];
      rows.add([
        useCase,
        pain,
        _personaFor(useCase),
        _valueHypothesis(useCase, pain),
        'Medium until data owners and integration effort are validated.',
        'Customer data, public research, source date, and stakeholder confirmation.',
        'Run discovery workshop and score value, feasibility, and urgency.',
      ]);
      index++;
    }
    return rows;
  }

  List<List<String>> _solutionRows(List<ArtifactSection> sections) {
    final useCases = _bulletsFor(sections, const [
      'priority use cases',
      'use cases',
      'opportunities',
    ]);
    final solutions = _bulletsFor(sections, const [
      'recommended solutions',
      'recommendations',
      'solution',
      'architecture',
      'approach',
    ]);
    final rows = <List<String>>[];
    final candidates = useCases.isEmpty
        ? const ['Customer-validated use case']
        : useCases.take(8);
    var index = 0;
    for (final useCase in candidates) {
      final solution = solutions.isEmpty
          ? 'Map to recommended product, service, or implementation motion.'
          : solutions[index % solutions.length];
      rows.add([
        useCase,
        solution,
        _circuitAngle(useCase, solution),
        'Current environment, business KPI, data sources, constraints, and owner.',
        _successMetric(useCase),
      ]);
      index++;
    }
    return rows;
  }

  List<List<String>> _stakeholderRows(
    String prompt,
    List<ArtifactSection> sections,
  ) {
    final combined = [
      prompt,
      for (final section in sections) ...[
        section.title,
        section.body,
        ...section.bullets,
      ],
    ].join(' ').toLowerCase();
    final stakeholders = <List<String>>[
      [
        'Executive sponsor',
        'Business priority and funding',
        'Which outcome is most important this quarter and how will it be measured?',
        'Confirmed business owner and decision criteria.',
      ],
      [
        'Business sponsor and technical owner',
        'Value definition, adoption path, and implementation ownership',
        'Who owns the business case, who owns the technical rollout, and what evidence would make the recommendation decision-ready?',
        'Named accountable owners and shared success criteria.',
      ],
      [
        'IT / network owner',
        'Architecture, integration, and operational readiness',
        'What systems, sites, data sources, and constraints shape implementation?',
        'Feasible technical path and dependency list.',
      ],
      [
        'Security / risk owner',
        'Risk, compliance, and access controls',
        'What controls, audit evidence, and approval gates are required?',
        'Security acceptance criteria.',
      ],
    ];
    if (combined.contains('manufacturing') ||
        combined.contains('plant') ||
        combined.contains('ot')) {
      stakeholders.add([
        'Operations / plant owner',
        'Production workflow and downtime reduction',
        'Which downtime, maintenance, or quality events create the largest business impact?',
        'Prioritized plant workflow and measurable operational target.',
      ]);
    }
    if (combined.contains('sales') || combined.contains('customer')) {
      stakeholders.add([
        'Sales / customer success owner',
        'Adoption, expansion, and customer experience',
        'Which customer moments would improve with better insight or automation?',
        'Validated customer-facing value story.',
      ]);
    }
    return stakeholders;
  }

  List<List<String>> _evidenceRows(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    final recommendations = _bulletsFor(sections, const [
      'recommended solutions',
      'recommendations',
      'solution',
      'priority use cases',
      'use cases',
    ]);
    final rows = <List<String>>[];
    final claims = recommendations.isEmpty
        ? const ['Business value and use-case priority need evidence.']
        : recommendations.take(10);
    for (final claim in claims) {
      rows.add([
        claim,
        'Public company/industry research, customer workshop notes, data sample, and checked date.',
        document.citations.isEmpty
            ? 'Missing cited source'
            : 'Source-backed; verify freshness and relevance.',
        document.citations.isEmpty ? 'Low' : 'Medium',
      ]);
    }
    if (document.assumptions.isNotEmpty) {
      rows.add([
        'Assumptions require validation',
        document.assumptions.take(3).join(' | '),
        'Customer confirmation needed',
        'Low until confirmed',
      ]);
    }
    return rows;
  }

  List<List<String>> _actionPlanRows(List<ArtifactSection> sections) {
    final nextSteps = _bulletsFor(sections, const [
      'next steps',
      'action plan',
      'follow up',
      'implementation',
    ]);
    final first = nextSteps.isEmpty
        ? 'Run discovery workshop with business, IT, security, and operations stakeholders.'
        : nextSteps.first;
    final second = nextSteps.length > 1
        ? nextSteps[1]
        : 'Collect source data, success metrics, and integration constraints.';
    final third = nextSteps.length > 2
        ? nextSteps[2]
        : 'Convert validated use cases into an implementation plan, deck, or sizing artifact.';
    return [
      [
        '0-30 days',
        first,
        'Account team / sponsor',
        'Validated priority use cases',
      ],
      [
        '31-60 days',
        second,
        'Technical owner',
        'Evidence pack and feasibility notes',
      ],
      [
        '61-90 days',
        third,
        'Project owner',
        'Decision-ready roadmap and next-step proposal',
      ],
    ];
  }

  List<String> _bulletsFor(List<ArtifactSection> sections, List<String> terms) {
    final normalizedTerms = terms.map((term) => term.toLowerCase()).toList();
    final values = <String>[];
    for (final section in sections) {
      final title = section.title.toLowerCase();
      final titleMatches = normalizedTerms.any(title.contains);
      if (!titleMatches) continue;
      values.addAll(section.bullets);
      if (section.body.trim().isNotEmpty) {
        values.addAll(_sentences(section.body).take(4));
      }
    }
    return values
        .map(
          (value) => value
              .replaceFirst(RegExp(r'^[-*]\s+'), '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim(),
        )
        .where((value) => value.isNotEmpty)
        .toSet()
        .take(12)
        .toList(growable: false);
  }

  List<String> _sentences(String value) {
    return RegExp(r'[^.!?]+[.!?]?')
        .allMatches(value)
        .map((match) => match.group(0)?.trim() ?? '')
        .where((sentence) => sentence.isNotEmpty)
        .toList(growable: false);
  }

  String _personaFor(String useCase) {
    final lower = useCase.toLowerCase();
    if (lower.contains('maintenance') ||
        lower.contains('production') ||
        lower.contains('plant')) {
      return 'Operations leader / plant manager';
    }
    if (lower.contains('security') || lower.contains('incident')) {
      return 'Security operations leader';
    }
    if (lower.contains('network') ||
        lower.contains('wan') ||
        lower.contains('connectivity')) {
      return 'IT / network operations owner';
    }
    return 'Business sponsor and technical owner';
  }

  String _valueHypothesis(String useCase, String pain) {
    return 'If Circuit helps with ${_shorten(useCase, 70)}, the customer can reduce ${_shorten(pain.toLowerCase(), 70)} and improve measurable execution.';
  }

  String _circuitAngle(String useCase, String solution) {
    final lower = '$useCase $solution'.toLowerCase();
    if (lower.contains('sd-wan') || lower.contains('connectivity')) {
      return 'Network modernization, resiliency, visibility, and operational standardization.';
    }
    if (lower.contains('security') || lower.contains('access')) {
      return 'Secure access, segmentation, monitoring, and evidence-backed risk reduction.';
    }
    if (lower.contains('maintenance') || lower.contains('telemetry')) {
      return 'Telemetry collection, observability, workflow automation, and prioritization.';
    }
    return 'Structured discovery, implementation roadmap, and measurable business outcome tracking.';
  }

  String _successMetric(String useCase) {
    final lower = useCase.toLowerCase();
    if (lower.contains('downtime') || lower.contains('maintenance')) {
      return 'Downtime incidents, mean time to repair, avoided production impact.';
    }
    if (lower.contains('security') || lower.contains('incident')) {
      return 'Incident response time, coverage, policy compliance, audit evidence.';
    }
    if (lower.contains('network') ||
        lower.contains('wan') ||
        lower.contains('connectivity')) {
      return 'Site availability, failover success, app performance, operational tickets.';
    }
    return 'Validated KPI, adoption signal, time saved, revenue/risk impact.';
  }

  String _shorten(String value, int maxLength) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength - 1).trim()}...';
  }
}
