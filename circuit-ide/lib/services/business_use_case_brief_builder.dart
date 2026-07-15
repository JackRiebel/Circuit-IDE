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
        title: 'Buying Triggers And Timing',
        patterns: const [
          'buying triggers',
          'trigger',
          'timing',
          'budget',
          'initiative',
          'event',
        ],
        fallbackBody:
            'Identify the business events, renewal windows, risk deadlines, or executive initiatives that make this use case urgent now.',
      ),
      _section(
        document,
        title: 'Value Metrics And ROI',
        patterns: const [
          'value metrics',
          'roi metrics',
          'kpi',
          'metrics',
          'measurement',
        ],
        fallbackBody:
            'Define baseline metrics, target improvement, owner, and evidence needed before quoting ROI.',
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
        title: 'Account Motion Plan',
        patterns: const [
          'account motion',
          'sales motion',
          'go to market',
          'next meeting',
          'customer motion',
        ],
        fallbackBody:
            'Use discovery with the Executive sponsor + workflow owner, solution alignment, and an evidence-backed proposal. The proof artifact should include an Evidence pack, value metrics plan, and implementation roadmap before asking for pilot approval. The 30 / 60 / 90 Day Action Plan should start with Validated priority use cases.',
      ),
      _section(
        document,
        title: 'Objection And Risk Handling',
        patterns: const [
          'objection',
          'objections',
          'risks',
          'risk handling',
          'concerns',
          'blockers',
        ],
        fallbackBody:
            'Capture the risks, objections, unsupported claims, and proof needed before the business case is customer-ready.',
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
    final businessTables = _businessBriefTables(
      prompt: prompt,
      document: document,
      sections: sections,
    );
    final readinessRows = _tableRows(
      businessTables,
      'Business Case Readiness Scorecard',
    ).skip(1).toList(growable: false);
    final handoffRows = _tableRows(
      businessTables,
      'Customer Handoff Matrix',
    ).skip(1).toList(growable: false);
    final useCaseRows = _tableRows(
      businessTables,
      'Use Case Prioritization Matrix',
    ).skip(1).toList(growable: false);
    final valueMetricRows = _tableRows(
      businessTables,
      'Value Metrics Plan',
    ).skip(1).toList(growable: false);
    final tables = [...businessTables, ...document.tables];

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
        'businessUseCaseCount': useCaseRows.length,
        'businessValueMetricCount': valueMetricRows.length,
        'hasBusinessCaseReadinessScorecard': readinessRows.isNotEmpty,
        'businessCaseReadinessScorecardCount': readinessRows.length,
        'businessCaseReviewReadyCount': _readinessCount(
          readinessRows,
          'Review ready',
        ),
        'businessCaseDiscoveryReadyCount': _readinessCount(
          readinessRows,
          'Discovery ready',
        ),
        'businessCaseNeedsEvidenceCount': _readinessCount(
          readinessRows,
          'Evidence needed',
        ),
        'businessCaseExecutiveReadiness': _businessCaseExecutiveReadiness(
          readinessRows,
        ),
        'businessCaseHandoffGateCount': handoffRows.length,
        'businessCaseHandoffReadyCount': _handoffReadyCount(handoffRows),
        'businessCaseCustomerHandoffMatrix': _stringRows(handoffRows),
        'hasBusinessCaseCustomerHandoffMatrix': handoffRows.isNotEmpty,
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
        title: 'Executive Decision Snapshot',
        rows: [
          const [
            'Decision area',
            'Current signal',
            'Business value',
            'Required proof',
          ],
          ..._executiveDecisionRows(sections),
        ],
      ),
      ArtifactTable(
        title: 'Business Case Readiness Scorecard',
        rows: [
          const [
            'Use case',
            'Business value signal',
            'Feasibility posture',
            'Evidence confidence',
            'Stakeholder owner',
            'Overall readiness',
            'Next decision gate',
          ],
          ..._businessCaseReadinessRows(document, sections),
        ],
      ),
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
        title: 'Value Metrics Plan',
        rows: [
          const [
            'Use case',
            'KPI / value metric',
            'Baseline needed',
            'Target hypothesis',
            'Evidence owner',
          ],
          ..._valueMetricRows(sections),
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
        title: 'Account Motion Plan',
        rows: [
          const [
            'Motion',
            'Primary buyer',
            'Proof artifact',
            'Next meeting ask',
          ],
          ..._accountMotionRows(sections),
        ],
      ),
      ArtifactTable(
        title: 'Objection And Risk Handling',
        rows: [
          const [
            'Objection / risk',
            'Why it matters',
            'Mitigation',
            'Evidence',
          ],
          ..._objectionRows(sections),
        ],
      ),
      ArtifactTable(
        title: '30 / 60 / 90 Day Action Plan',
        rows: [
          const ['Window', 'Action', 'Owner', 'Output'],
          ..._actionPlanRows(sections),
        ],
      ),
      ArtifactTable(
        title: 'Customer Handoff Matrix',
        rows: [
          const [
            'Gate',
            'Customer-facing requirement',
            'Current signal',
            'Status',
            'Owner action',
            'Handoff rule',
          ],
          ..._customerHandoffRows(document, sections),
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

  List<List<String>> _executiveDecisionRows(List<ArtifactSection> sections) {
    final pains = _bulletsFor(sections, const [
      'pain',
      'signals',
      'challenges',
      'current state',
    ]);
    final useCases = _bulletsFor(sections, const [
      'priority use cases',
      'use cases',
      'opportunities',
    ]);
    final values = _bulletsFor(sections, const [
      'value',
      'impact',
      'roi',
      'benefits',
      'outcomes',
    ]);
    return [
      [
        'Business priority',
        pains.isEmpty ? 'Needs customer discovery' : _shorten(pains.first, 120),
        values.isEmpty
            ? 'Potential value is not yet quantified.'
            : _shorten(values.first, 120),
        'Executive sponsor, success metric, baseline, and checked source evidence.',
      ],
      [
        'Recommended use case',
        useCases.isEmpty
            ? 'Use case shortlist not confirmed'
            : _shorten(useCases.first, 120),
        'Frames the first customer conversation around a concrete business outcome.',
        'Customer confirmation that the use case maps to funded priority and owned workflow.',
      ],
      [
        'Decision readiness',
        'Needs evidence-backed value and feasibility scoring',
        'Prevents a generic pitch from becoming an unsupported recommendation.',
        'Evidence pack, stakeholder owner, implementation dependency list, and next-meeting ask.',
      ],
    ];
  }

  List<List<String>> _businessCaseReadinessRows(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
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
    final valueSignals = _bulletsFor(sections, const [
      'value',
      'impact',
      'roi',
      'benefits',
      'outcomes',
    ]);
    final candidates = useCases.isEmpty
        ? const ['Define a customer-validated business use case.']
        : useCases.take(8);
    final rows = <List<String>>[];
    var index = 0;
    for (final useCase in candidates) {
      rows.add([
        useCase,
        _businessValueSignal(
          useCase: useCase,
          pain: pains.isEmpty ? '' : pains[index % pains.length],
          value: valueSignals.isEmpty
              ? ''
              : valueSignals[index % valueSignals.length],
        ),
        _businessFeasibilityPosture(useCase),
        document.citations.isEmpty
            ? 'Low - source evidence missing'
            : 'Medium - source evidence present; verify freshness and fit',
        _personaFor(useCase),
        _businessReadinessStatus(
          hasSources: document.citations.isNotEmpty,
          useCase: useCase,
        ),
        _businessNextGate(
          hasSources: document.citations.isNotEmpty,
          useCase: useCase,
        ),
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

  List<List<String>> _valueMetricRows(List<ArtifactSection> sections) {
    final useCases = _bulletsFor(sections, const [
      'priority use cases',
      'use cases',
      'opportunities',
    ]);
    final candidates = useCases.isEmpty
        ? const ['Customer-validated use case']
        : useCases.take(8);
    return [
      for (final useCase in candidates)
        [
          useCase,
          _successMetric(useCase),
          'Current baseline, source system, measurement window, and owner.',
          _targetHypothesis(useCase),
          _personaFor(useCase),
        ],
    ];
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

  List<List<String>> _accountMotionRows(List<ArtifactSection> sections) {
    final useCases = _bulletsFor(sections, const [
      'priority use cases',
      'use cases',
      'opportunities',
    ]);
    final nextSteps = _bulletsFor(sections, const [
      'next steps',
      'action plan',
      'follow up',
      'implementation',
    ]);
    final primaryUseCase = useCases.isEmpty
        ? 'priority business use case'
        : _shorten(useCases.first, 90);
    return [
      [
        'Discovery',
        'Executive sponsor + workflow owner',
        'Business value hypothesis and discovery question list',
        nextSteps.isEmpty
            ? 'Confirm decision owner, metric, data source, and next working session.'
            : _shorten(nextSteps.first, 120),
      ],
      [
        'Solution alignment',
        _personaFor(primaryUseCase),
        'Solution map tied to $primaryUseCase',
        'Review target architecture, customer inputs, and feasibility risks.',
      ],
      [
        'Evidence-backed proposal',
        'Buying committee',
        'Evidence pack, value metrics plan, and implementation roadmap',
        'Approve pilot scope, success criteria, and stakeholder operating model.',
      ],
    ];
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

  List<List<String>> _objectionRows(List<ArtifactSection> sections) {
    final risks = _bulletsFor(sections, const [
      'risk',
      'risks',
      'objection',
      'objections',
      'assumptions',
      'unknowns',
      'dependencies',
    ]);
    final candidates = risks.isEmpty
        ? const [
            'Business impact, data quality, stakeholder ownership, and implementation feasibility are not fully validated.',
          ]
        : risks.take(8);
    return [
      for (final risk in candidates)
        [
          risk,
          'Unresolved risk can weaken executive confidence or slow approval.',
          'Convert into a discovery question, proof artifact, owner, and decision gate.',
          'Customer confirmation, source citation, baseline data, or technical feasibility note.',
        ],
    ];
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

  List<List<String>> _customerHandoffRows(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
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
    final values = _bulletsFor(sections, const [
      'value',
      'impact',
      'roi',
      'benefits',
      'outcomes',
    ]);
    final stakeholders = _bulletsFor(sections, const [
      'stakeholders',
      'personas',
      'workflow',
      'workflows',
      'buying committee',
    ]);
    final nextSteps = _bulletsFor(sections, const [
      'next steps',
      'action plan',
      'follow up',
      'implementation',
    ]);
    final hasSources = document.citations.isNotEmpty;
    final hasAssumptions = document.assumptions.isNotEmpty;
    final hasUseCases = useCases.isNotEmpty;
    final hasPainSignals = pains.isNotEmpty;
    final hasValueSignals = values.isNotEmpty;
    final hasStakeholders = stakeholders.isNotEmpty;
    final hasNextSteps = nextSteps.isNotEmpty;
    return [
      [
        'Sourced company and industry evidence',
        'Every external business claim has a cited source and checked date.',
        hasSources
            ? 'Source evidence attached'
            : 'No cited source evidence attached',
        hasSources ? 'Ready' : 'Blocked',
        'Attach public/company/customer sources with checked dates.',
        'Do not customer-share unsupported market, company, or value claims.',
      ],
      [
        'Customer-specific use cases',
        'Brief names concrete use cases tied to this customer or industry context.',
        hasUseCases
            ? '${useCases.length} use cases captured'
            : 'No use case shortlist',
        hasUseCases ? 'Ready' : 'Blocked',
        'Confirm priority use cases with the business sponsor and workflow owner.',
        'Generic use cases must be reframed around the customer before handoff.',
      ],
      [
        'Pain and trigger validation',
        'Business pains, buying triggers, or operational signals are explicit.',
        hasPainSignals
            ? '${pains.length} pain/signals captured'
            : 'Pain signals missing',
        hasPainSignals ? 'Ready' : 'Needs discovery',
        'Validate pains, timing, and trigger events with customer stakeholders.',
        'Do not position a recommendation without a current business trigger.',
      ],
      [
        'Value metric and baseline',
        'Each priority use case has a measurable KPI, baseline, owner, or target hypothesis.',
        hasValueSignals
            ? '${values.length} value signals captured'
            : 'Value metrics need baseline',
        hasValueSignals ? 'Needs validation' : 'Blocked',
        'Collect baseline KPI, measurement owner, and target improvement.',
        'ROI/value claims stay advisory until baseline evidence is attached.',
      ],
      [
        'Stakeholder owner and workflow',
        'Decision owner, workflow owner, and technical owner are clear enough for next-step discovery.',
        hasStakeholders
            ? 'Stakeholder/workflow section present'
            : 'Stakeholder ownership needs discovery',
        hasStakeholders ? 'Ready' : 'Needs discovery',
        'Name executive sponsor, workflow owner, technical owner, and approval path.',
        'No pilot ask without accountable owner and workflow fit.',
      ],
      [
        'Evidence pack and next ask',
        'Brief closes with next action, proof artifact, assumptions, and open evidence gaps.',
        hasNextSteps || hasAssumptions
            ? 'Next action / assumptions captured'
            : 'Next action not explicit',
        hasNextSteps ? 'Ready' : 'Needs discovery',
        'Attach evidence pack, discovery questions, assumptions, and next meeting ask.',
        'Customer handoff must make the next decision and proof requirement obvious.',
      ],
    ];
  }

  List<List<String>> _tableRows(List<ArtifactTable> tables, String title) {
    for (final table in tables) {
      if (table.title == title) return table.rows;
    }
    return const [];
  }

  int _readinessCount(List<List<String>> rows, String needle) {
    final normalizedNeedle = needle.toLowerCase();
    return rows.where((row) {
      return row.any((cell) => cell.toLowerCase().contains(normalizedNeedle));
    }).length;
  }

  int _handoffReadyCount(List<List<String>> rows) {
    return rows.where((row) {
      return row.length > 3 && row[3].toLowerCase().contains('ready');
    }).length;
  }

  List<String> _stringRows(List<List<String>> rows) {
    return rows
        .where((row) => row.any((cell) => cell.trim().isNotEmpty))
        .map((row) => row.map((cell) => cell.trim()).join(': '))
        .toList(growable: false);
  }

  String _businessCaseExecutiveReadiness(List<List<String>> rows) {
    if (rows.isEmpty) return 'Needs discovery - no scored use cases';
    final reviewReady = _readinessCount(rows, 'Review ready');
    final discoveryReady = _readinessCount(rows, 'Discovery ready');
    final evidenceNeeded = _readinessCount(rows, 'Evidence needed');
    if (reviewReady == rows.length) {
      return 'Review ready - every use case has evidence and owner posture';
    }
    if (reviewReady > 0 || discoveryReady > 0) {
      return 'Discovery ready - validate evidence gaps before executive handoff';
    }
    if (evidenceNeeded > 0) {
      return 'Evidence needed - attach sources and customer baselines';
    }
    return 'Needs discovery - scorecard requires customer confirmation';
  }

  String _businessValueSignal({
    required String useCase,
    required String pain,
    required String value,
  }) {
    final combined = '$useCase $pain $value'.toLowerCase();
    if (RegExp(
      r'\b(revenue|margin|cost|downtime|risk|security|compliance|shipment|production|outage|incident)\b',
    ).hasMatch(combined)) {
      return 'High - directly tied to financial, risk, or operational impact';
    }
    if (RegExp(
      r'\b(efficiency|visibility|automation|time|adoption)\b',
    ).hasMatch(combined)) {
      return 'Medium - measurable operational improvement likely';
    }
    return 'Unproven - quantify value before customer-facing use';
  }

  String _businessFeasibilityPosture(String useCase) {
    final lower = useCase.toLowerCase();
    if (RegExp(
      r'\b(data|integration|telemetry|automation|ai|workflow)\b',
    ).hasMatch(lower)) {
      return 'Medium - confirm data ownership, integrations, and workflow adoption';
    }
    if (RegExp(
      r'\b(network|wan|security|access|connectivity|wireless)\b',
    ).hasMatch(lower)) {
      return 'Medium/High - validate current environment and rollout scope';
    }
    return 'Medium - validate owner, scope, and delivery complexity';
  }

  String _businessReadinessStatus({
    required bool hasSources,
    required String useCase,
  }) {
    if (!hasSources) return 'Evidence needed before executive handoff';
    final lower = useCase.toLowerCase();
    if (RegExp(
      r'\b(downtime|maintenance|risk|security|production|revenue|cost)\b',
    ).hasMatch(lower)) {
      return 'Review ready after baseline confirmation';
    }
    return 'Discovery ready with sourced context';
  }

  String _businessNextGate({
    required bool hasSources,
    required String useCase,
  }) {
    if (!hasSources) {
      return 'Attach public/customer source evidence and checked dates.';
    }
    return 'Confirm baseline KPI, accountable owner, decision timeline, and proof artifact for ${_shorten(useCase, 56)}.';
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

  String _targetHypothesis(String useCase) {
    final lower = useCase.toLowerCase();
    if (lower.contains('downtime') || lower.contains('maintenance')) {
      return 'Reduce unplanned downtime exposure and improve maintenance response.';
    }
    if (lower.contains('security') || lower.contains('incident')) {
      return 'Improve incident response speed, control coverage, and audit readiness.';
    }
    if (lower.contains('network') ||
        lower.contains('wan') ||
        lower.contains('connectivity')) {
      return 'Improve site availability, failover confidence, and operational visibility.';
    }
    return 'Improve measurable business execution once baseline and owner are confirmed.';
  }

  String _shorten(String value, int maxLength) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength - 1).trim()}...';
  }
}
