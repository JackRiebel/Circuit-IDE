import '../models/artifact_document.dart';

class ImplementationPlanArtifactBuilder {
  const ImplementationPlanArtifactBuilder();

  bool matches(String prompt) {
    final normalized = prompt.toLowerCase();
    return RegExp(
      r'\b(implementation plan|deployment plan|migration plan|project plan|rollout plan|execution plan|build plan|implementation roadmap|delivery plan|release plan)\b',
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
        title: 'Implementation Overview',
        patterns: const ['overview', 'summary', 'implementation overview'],
        fallbackBody: document.summary,
      ),
      _section(
        document,
        title: 'Scope And Success Criteria',
        patterns: const ['scope', 'success criteria', 'goals', 'objectives'],
        fallbackBody:
            'Define the implementation boundary, target outcome, non-goals, and success criteria before execution starts.',
      ),
      _section(
        document,
        title: 'Workstreams And Deliverables',
        patterns: const [
          'workstreams',
          'deliverables',
          'key changes',
          'planned work',
          'files',
          'artifacts',
        ],
        fallbackBody:
            'Break the work into reviewable batches, planned files or artifacts, and expected user-facing outcomes.',
      ),
      _section(
        document,
        title: 'Implementation Phases',
        patterns: const ['phases', 'phase', 'roadmap', 'sequence', 'timeline'],
        fallbackBody:
            'Run the implementation in inspect, build, verify, and handoff phases with a review checkpoint between risky changes.',
      ),
      _section(
        document,
        title: 'Dependencies And Inputs',
        patterns: const [
          'dependencies',
          'inputs',
          'requirements',
          'prerequisites',
          'data needed',
        ],
        fallbackBody:
            'Confirm required source data, stakeholder decisions, environment access, and technical dependencies before committing to the plan.',
      ),
      _section(
        document,
        title: 'Verification Plan',
        patterns: const [
          'verification',
          'validation',
          'checks',
          'test plan',
          'acceptance',
        ],
        fallbackBody:
            'Define the commands, inspections, artifact reviews, and acceptance checks that prove the implementation is complete.',
      ),
      _section(
        document,
        title: 'Rollback And Recovery',
        patterns: const ['rollback', 'restore', 'recovery', 'checkpoint'],
        fallbackBody:
            'Capture checkpoint, restore, and fallback steps for every applied batch or generated deliverable.',
      ),
      _section(
        document,
        title: 'Risks And Assumptions',
        patterns: const ['risks', 'risk', 'assumptions', 'unknowns'],
        fallbackBody:
            'Track the assumptions, blockers, and risks that must be validated before customer handoff.',
        fallbackBullets: document.assumptions,
      ),
      _section(
        document,
        title: 'Approval And Handoff Gates',
        patterns: const ['approval', 'handoff', 'gates', 'review'],
        fallbackBody:
            'Use explicit review gates for plan approval, patch review, verification evidence, and final handoff.',
      ),
      _section(
        document,
        title: 'Sources / Evidence',
        patterns: const ['sources', 'evidence', 'citations', 'references'],
        fallbackBody:
            'Attach the source material, requirements, screenshots, citations, or customer inputs used to create the plan.',
        fallbackBullets: document.citations,
      ),
    ];
    final tables = [
      ..._planTables(document: document, sections: sections),
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
        'artifactTemplate': 'implementation_plan',
        'sourcePrompt': prompt,
        'implementationPlanTables': tables.length,
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
    if (cleaned.isEmpty) return 'Implementation Plan';
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

  List<ArtifactTable> _planTables({
    required ArtifactDocument document,
    required List<ArtifactSection> sections,
  }) {
    return [
      ArtifactTable(
        title: 'Implementation Decision Brief',
        rows: [
          const ['Decision Area', 'Plan Position', 'Review Gate', 'Owner'],
          [
            'Scope',
            _firstMeaningful(sections, const ['scope', 'overview']) ??
                'Scope requires stakeholder confirmation.',
            'Plan approval',
            'Product / Technical owner',
          ],
          [
            'Delivery approach',
            _firstMeaningful(sections, const ['phase', 'roadmap']) ??
                'Run work in reviewable implementation batches.',
            'Batch review',
            'Implementation lead',
          ],
          [
            'Verification',
            _firstMeaningful(sections, const ['verification', 'validation']) ??
                'Capture evidence before handoff.',
            'Verification review',
            'QA / Reviewer',
          ],
          [
            'Handoff',
            'Summarize changes, artifacts, evidence, risks, and next steps.',
            'Final approval',
            'Account / Delivery owner',
          ],
        ],
      ),
      ArtifactTable(
        title: 'Phase Execution Plan',
        rows: [
          const ['Phase', 'Purpose', 'Outputs', 'Exit Criteria'],
          ..._phaseRows(sections),
        ],
      ),
      ArtifactTable(
        title: 'Workstream And Artifact Matrix',
        rows: [
          const [
            'Workstream',
            'Deliverable / File',
            'Change Type',
            'Review Need',
          ],
          ..._workstreamRows(sections, document),
        ],
      ),
      ArtifactTable(
        title: 'Dependency Register',
        rows: [
          const ['Dependency', 'Why Needed', 'Risk If Missing', 'Owner'],
          ..._dependencyRows(sections),
        ],
      ),
      ArtifactTable(
        title: 'Verification Checklist',
        rows: [
          const ['Check', 'Method', 'Evidence', 'Pass Criteria'],
          ..._verificationRows(sections, document),
        ],
      ),
      ArtifactTable(
        title: 'Rollback And Risk Register',
        rows: [
          const [
            'Risk / Failure Mode',
            'Impact',
            'Mitigation',
            'Recovery Step',
          ],
          ..._riskRows(sections, document),
        ],
      ),
      const ArtifactTable(
        title: 'Approval Gates',
        rows: [
          ['Gate', 'Required Evidence', 'Decision', 'Owner'],
          [
            'Plan approved',
            'Scope, assumptions, dependencies, and phases reviewed.',
            'Approve / revise / reject',
            'User or project owner',
          ],
          [
            'Patch or artifact reviewed',
            'Prepared files, generated artifacts, and diffs inspected.',
            'Apply / revise',
            'Reviewer',
          ],
          [
            'Verification complete',
            'Checks run or clear manual validation evidence captured.',
            'Accept / continue',
            'QA / technical owner',
          ],
          [
            'Customer handoff ready',
            'Outcome summary, open risks, and next steps documented.',
            'Deliver / hold',
            'Delivery owner',
          ],
        ],
      ),
    ];
  }

  List<List<String>> _phaseRows(List<ArtifactSection> sections) {
    final bullets = _bulletsFor(sections, const [
      'implementation phases',
      'phases',
      'roadmap',
      'sequence',
    ]);
    final defaults = [
      'Inspect current state and confirm scope.',
      'Prepare implementation batch or generated artifact.',
      'Review planned changes and approval gates.',
      'Apply, verify, summarize, and hand off.',
    ];
    final source = bullets.isEmpty ? defaults : bullets.take(8).toList();
    return [
      for (var i = 0; i < source.length; i++)
        [
          'Phase ${i + 1}',
          source[i],
          i == 0
              ? 'Context snapshot and confirmed requirements'
              : i == source.length - 1
              ? 'Outcome summary and handoff package'
              : 'Reviewable work product',
          'Owner confirms the phase output is accepted.',
        ],
    ];
  }

  List<List<String>> _workstreamRows(
    List<ArtifactSection> sections,
    ArtifactDocument document,
  ) {
    final planned = [
      ..._bulletsFor(sections, const [
        'workstreams and deliverables',
        'workstreams',
        'deliverables',
        'planned files',
        'files',
        'artifacts',
      ]),
      for (final table in document.tables.take(4)) table.title,
    ].where((item) => item.trim().isNotEmpty).toList(growable: false);
    final items = planned.isEmpty
        ? const [
            'Implementation deliverable',
            'Generated customer artifact',
            'Verification evidence',
          ]
        : planned.take(10);
    return [
      for (final item in items)
        [
          _workstreamFor(item),
          item,
          _changeTypeFor(item),
          _reviewNeedFor(item),
        ],
    ];
  }

  List<List<String>> _dependencyRows(List<ArtifactSection> sections) {
    final dependencies = _bulletsFor(sections, const [
      'dependencies and inputs',
      'dependencies',
      'inputs',
      'requirements',
      'prerequisites',
    ]);
    final items = dependencies.isEmpty
        ? const [
            'Source requirements and customer constraints',
            'Workspace access and artifact output location',
            'Approval owner and verification criteria',
          ]
        : dependencies.take(8);
    return [
      for (final item in items)
        [
          item,
          'Needed to avoid speculative implementation work.',
          'Scope drift, rework, or unsupported claims.',
          'Project owner',
        ],
    ];
  }

  List<List<String>> _verificationRows(
    List<ArtifactSection> sections,
    ArtifactDocument document,
  ) {
    final checks = _bulletsFor(sections, const [
      'verification plan',
      'verification',
      'validation',
      'checks',
      'test plan',
    ]);
    final items = checks.isEmpty
        ? [
            'Generated file exists and opens/parses.',
            if (document.tables.isNotEmpty)
              'Structured tables preserve headers and row counts.',
            'Artifact card and drawer metadata render correctly.',
            'Outcome summary names what changed or was created.',
          ]
        : checks.take(10).toList();
    return [
      for (final item in items)
        [
          item,
          _methodFor(item),
          'Screenshot, command output, inspector result, or reviewer sign-off.',
          'No blocker remains for the stated outcome.',
        ],
    ];
  }

  List<List<String>> _riskRows(
    List<ArtifactSection> sections,
    ArtifactDocument document,
  ) {
    final risks = [
      ..._bulletsFor(sections, const [
        'risks and assumptions',
        'risks',
        'risk',
        'rollback',
        'recovery',
      ]),
      ...document.assumptions,
    ];
    final items = risks.isEmpty
        ? const [
            'Incomplete requirements',
            'Generated output may need customer-specific review',
            'Verification evidence may be missing',
          ]
        : risks.take(8);
    return [
      for (final risk in items)
        [
          risk,
          _impactFor(risk),
          'Review with owner before final handoff.',
          _recoveryFor(risk),
        ],
    ];
  }

  List<String> _bulletsFor(List<ArtifactSection> sections, List<String> names) {
    final values = <String>[];
    for (final section in sections) {
      final title = section.title.toLowerCase();
      if (!names.any(title.contains)) continue;
      values.addAll(section.bullets);
      if (values.isEmpty && section.body.trim().isNotEmpty) {
        values.addAll(_sentences(section.body).take(4));
      }
    }
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  String? _firstMeaningful(List<ArtifactSection> sections, List<String> names) {
    final bullets = _bulletsFor(sections, names);
    if (bullets.isNotEmpty) return bullets.first;
    for (final section in sections) {
      final title = section.title.toLowerCase();
      if (!names.any(title.contains)) continue;
      final body = section.body.trim();
      if (body.isNotEmpty) {
        final sentences = _sentences(body).toList(growable: false);
        return sentences.isEmpty ? body : sentences.first;
      }
    }
    return null;
  }

  Iterable<String> _sentences(String body) {
    return body
        .replaceAll('\n', ' ')
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
  }

  String _workstreamFor(String item) {
    final normalized = item.toLowerCase();
    if (normalized.contains('file') ||
        normalized.contains('.dart') ||
        normalized.contains('.ts') ||
        normalized.contains('.md')) {
      return 'File changes';
    }
    if (normalized.contains('artifact') ||
        normalized.contains('deck') ||
        normalized.contains('report')) {
      return 'Artifact output';
    }
    if (normalized.contains('test') || normalized.contains('verify')) {
      return 'Verification';
    }
    return 'Implementation';
  }

  String _changeTypeFor(String item) {
    final normalized = item.toLowerCase();
    if (normalized.contains('create') || normalized.contains('new')) {
      return 'Create';
    }
    if (normalized.contains('update') ||
        normalized.contains('edit') ||
        normalized.contains('change')) {
      return 'Update';
    }
    if (normalized.contains('review') || normalized.contains('verify')) {
      return 'Validate';
    }
    return 'Plan / implement';
  }

  String _reviewNeedFor(String item) {
    final normalized = item.toLowerCase();
    if (normalized.contains('customer') ||
        normalized.contains('source') ||
        normalized.contains('evidence')) {
      return 'Customer/evidence review';
    }
    if (normalized.contains('command') || normalized.contains('test')) {
      return 'Command approval and result review';
    }
    return 'Patch or artifact review';
  }

  String _methodFor(String item) {
    final normalized = item.toLowerCase();
    if (normalized.contains('test') || normalized.contains('command')) {
      return 'Run approved check';
    }
    if (normalized.contains('file') ||
        normalized.contains('artifact') ||
        normalized.contains('opens')) {
      return 'Inspect generated file';
    }
    if (normalized.contains('table') || normalized.contains('data')) {
      return 'Compare source rows and output preview';
    }
    return 'Manual review';
  }

  String _impactFor(String risk) {
    final normalized = risk.toLowerCase();
    if (normalized.contains('source') || normalized.contains('evidence')) {
      return 'Unsupported customer-facing claim.';
    }
    if (normalized.contains('scope') || normalized.contains('requirement')) {
      return 'Implementation may solve the wrong problem.';
    }
    if (normalized.contains('test') || normalized.contains('verify')) {
      return 'Completion cannot be trusted.';
    }
    return 'Potential rework or handoff delay.';
  }

  String _recoveryFor(String risk) {
    final normalized = risk.toLowerCase();
    if (normalized.contains('checkpoint') || normalized.contains('rollback')) {
      return 'Restore checkpoint or rerun from last accepted batch.';
    }
    if (normalized.contains('source') || normalized.contains('evidence')) {
      return 'Qualify, cite, or remove the unsupported claim.';
    }
    return 'Pause, revise plan, and resume with owner approval.';
  }
}
