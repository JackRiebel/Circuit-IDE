import '../models/artifact_document.dart';
import 'workbook_table.dart';

class ProductComparisonWorkbookBuilder {
  const ProductComparisonWorkbookBuilder();

  bool matches(String prompt) {
    final normalized = prompt.toLowerCase();
    return RegExp(
      r'\b(product comparison|comparison matrix|model comparison|compare (?:these |the )?(?:products?|models?|switches?|routers?|firewalls?|aps?)|side[- ]by[- ]side|fit score|shortlist)\b',
    ).hasMatch(normalized);
  }

  List<WorkbookTable> build({
    required String prompt,
    required String content,
    required ArtifactDocument document,
  }) {
    final comparisonRows = _comparisonRows(
      prompt: prompt,
      content: content,
      document: document,
    );
    final candidates = comparisonRows
        .map(_ComparisonCandidate.fromRow)
        .toList(growable: false);
    final requirementRows = _requirementRows('$prompt\n$content');
    return [
      WorkbookTable(
        name: 'Comparison Matrix',
        rows: [
          const [
            'Product / Model',
            'Positioning',
            'Key capabilities',
            'Constraints / caveats',
            'Lifecycle / risk',
            'Fit score',
            'Recommendation',
          ],
          ...comparisonRows,
        ],
      ),
      WorkbookTable(
        name: 'Decision Summary',
        rows: [
          const [
            'Decision Area',
            'Best current answer',
            'Evidence needed before customer handoff',
            'Confidence',
          ],
          ..._decisionRows(candidates),
        ],
      ),
      const WorkbookTable(
        name: 'Fit Scoring',
        rows: [
          ['Criterion', 'Weight', 'How to score', 'Notes'],
          [
            'Requirement fit',
            '30%',
            '0-5 based on must-have capability alignment',
            'Treat missing hard requirements as disqualifying.',
          ],
          [
            'Scale / performance',
            '20%',
            '0-5 based on throughput, users, ports, and uplinks',
            'Use enabled services, not datasheet peak-only claims.',
          ],
          [
            'Power / physical fit',
            '15%',
            '0-5 based on PoE/UPOE, multigig, rack, and power needs',
            'Important for Wi-Fi 6E/7 and high-density access.',
          ],
          [
            'Lifecycle confidence',
            '15%',
            '0-5 based on current portfolio and support runway',
            'EoX replacement PIDs are hints, not final recommendations.',
          ],
          [
            'Operational simplicity',
            '10%',
            '0-5 based on manageability, licensing, and standardization',
            'Prefer lower operational burden when fit is otherwise similar.',
          ],
          [
            'Cost / commercial fit',
            '10%',
            '0-5 based on budget, licensing, and availability',
            'Validate pricing with current partner/customer context.',
          ],
        ],
      ),
      WorkbookTable(
        name: 'Requirements',
        rows: [
          const ['Requirement', 'Detected value', 'Why it matters'],
          ...requirementRows,
        ],
      ),
      WorkbookTable(
        name: 'Requirement Gates',
        rows: [
          const [
            'Gate',
            'Detected requirement',
            'Pass criteria',
            'Failure impact',
          ],
          ..._gateRows(requirementRows),
        ],
      ),
      WorkbookTable(
        name: 'Scored Shortlist',
        rows: [
          const [
            'Rank',
            'Product / Model',
            'Fit score',
            'Recommendation',
            'Primary caution',
          ],
          ..._shortlistRows(candidates),
        ],
      ),
      WorkbookTable(
        name: 'Alternatives',
        rows: [
          const [
            'Alternative',
            'Reason to consider',
            'Reason to reject / caveat',
          ],
          ..._alternativeRows(document, content),
        ],
      ),
      WorkbookTable(
        name: 'Replacement Cautions',
        rows: [
          const ['Topic', 'Rule', 'Why it matters', 'Required validation'],
          ..._replacementCautionRows('$prompt\n$content'),
        ],
      ),
      const WorkbookTable(
        name: 'Validation Checklist',
        rows: [
          ['Check', 'Required evidence', 'Status'],
          [
            'Capability facts',
            'Current datasheet or official portfolio source for ports, PoE, uplinks, throughput, HA, and licensing',
            'Needs validation',
          ],
          [
            'Lifecycle / LDOS',
            'Official Cisco EoX/API or official lifecycle source with checked date',
            'Needs validation',
          ],
          [
            'Wi-Fi 7 / UPOE fit',
            'AP power draw, switch PoE budget, mGig access need, and uplink headroom',
            'Needs validation',
          ],
          [
            'Operational model',
            'Cloud-managed vs controller/DNA operations, licensing, support model, and customer standards',
            'Needs validation',
          ],
          [
            'Rejected alternatives',
            'Document why lower-fit or stale migration candidates fail requirements',
            'Needs validation',
          ],
        ],
      ),
      const WorkbookTable(
        name: 'Sources Needed',
        rows: [
          ['Source Type', 'Needed For', 'Status'],
          [
            'Official datasheet',
            'Capability facts, power, uplinks, throughput, port speeds, scale, and licensing',
            'Required',
          ],
          [
            'Cisco EoX / lifecycle',
            'LDOS/EoL/EoS dates and support-risk status',
            'Required',
          ],
          [
            'Customer requirements',
            'Must-have constraints, growth, operational model, budget, and standards',
            'Required',
          ],
          [
            'Commercial context',
            'Availability, pricing, licensing, support, and lead-time considerations',
            'Recommended',
          ],
        ],
      ),
      WorkbookTable(
        name: 'Assumptions',
        rows: [
          const ['Assumption', 'Impact'],
          ..._assumptionRows(document),
        ],
      ),
      ..._sourceTables(document),
    ];
  }

  List<List<String>> _comparisonRows({
    required String prompt,
    required String content,
    required ArtifactDocument document,
  }) {
    for (final table in document.tables) {
      final rows = _comparisonRowsFromTable(table);
      if (rows.isNotEmpty) return rows;
    }
    final products = _productNames('$prompt\n$content');
    if (products.isEmpty) {
      return const [
        [
          'TBD',
          'Candidate product or model to be confirmed',
          'Add sourced capability facts before recommendation',
          'Unknown until portfolio/datasheet facts are added',
          'Needs lifecycle validation',
          'TBD',
          'Do not recommend until requirements and sources are confirmed.',
        ],
      ];
    }
    return products
        .take(24)
        .map(
          (product) => [
            product,
            'Candidate',
            'Add sourced capabilities for throughput, ports, power, licensing, and HA.',
            'Validate hard requirements and current portfolio fit.',
            'Needs lifecycle validation',
            'TBD',
            'Review against requirements before final recommendation.',
          ],
        )
        .toList(growable: false);
  }

  List<List<String>> _comparisonRowsFromTable(ArtifactTable table) {
    if (table.rows.length < 2) return const [];
    final header = table.rows.first.map((cell) => cell.toLowerCase()).toList();
    final modelIndex = _firstHeaderIndex(header, const [
      'product',
      'model',
      'pid',
      'sku',
      'part',
    ]);
    if (modelIndex == null) return const [];
    final positioningIndex = _firstHeaderIndex(header, const [
      'positioning',
      'use case',
      'role',
      'best for',
    ]);
    final capabilityIndexes = _headerIndexes(header, const [
      'capability',
      'capabilities',
      'poe',
      'upoe',
      'uplink',
      'throughput',
      'ports',
      'wifi',
      'stack',
      'ha',
      'license',
    ]);
    final caveatIndexes = _headerIndexes(header, const [
      'constraint',
      'constraints',
      'caveat',
      'caveats',
      'limits',
      'limitations',
      'risk',
      'cons',
    ]);
    final lifecycleIndex = _firstHeaderIndex(header, const [
      'lifecycle',
      'ldos',
      'eol',
      'eos',
      'support',
    ]);
    final fitIndex = _firstHeaderIndex(header, const [
      'fit',
      'score',
      'rating',
    ]);
    final recommendationIndex = _firstHeaderIndex(header, const [
      'recommend',
      'recommendation',
      'decision',
      'verdict',
    ]);

    final rows = <List<String>>[];
    for (final sourceRow in table.rows.skip(1)) {
      if (modelIndex >= sourceRow.length) continue;
      final product = sourceRow[modelIndex].trim();
      if (product.isEmpty) continue;
      rows.add([
        product,
        _cell(sourceRow, positioningIndex) ?? 'Candidate',
        _joinCells(sourceRow, capabilityIndexes) ??
            'Add sourced capability facts.',
        _joinCells(sourceRow, caveatIndexes) ?? 'Validate hard requirements.',
        _cell(sourceRow, lifecycleIndex) ?? 'Needs lifecycle validation',
        _cell(sourceRow, fitIndex) ?? 'TBD',
        _cell(sourceRow, recommendationIndex) ?? 'Review',
      ]);
    }
    return rows.take(48).toList(growable: false);
  }

  List<List<String>> _requirementRows(String content) {
    final rows = <List<String>>[];
    void add(String requirement, String? value, String impact) {
      if (value == null || value.trim().isEmpty) return;
      rows.add([requirement, value.trim(), impact]);
    }

    add(
      'Wi-Fi generation',
      _first(
        content,
        RegExp(r'\b(wi[- ]?fi\s*(?:6e|7|6|5))\b', caseSensitive: false),
      ),
      'Can drive multigig access and UPOE/UPOE+ requirements.',
    );
    add(
      'PoE / UPOE',
      _first(
        content,
        RegExp(
          r'\b(upoe\+?|poe\+?\+?|power budget|watts?)\b',
          caseSensitive: false,
        ),
      ),
      'Power class can reject otherwise valid access switches.',
    );
    add(
      'Uplinks / bandwidth',
      _first(
        content,
        RegExp(
          r'\b(\d+(?:\.\d+)?\s*(?:g|gbps|m|mbps|gig|gigs))\b',
          caseSensitive: false,
        ),
      ),
      'Use actual service mix and oversubscription targets.',
    );
    add(
      'High availability',
      _first(
        content,
        RegExp(
          r'\b(ha|high availability|redundant|warm spare|stack(?:ing)?)\b',
          caseSensitive: false,
        ),
      ),
      'Impacts platform family, licensing, and physical design.',
    );
    add(
      'Lifecycle',
      _first(
        content,
        RegExp(
          r'\b(ldos|eol|eos|lifecycle|end of (?:life|support|sale))\b',
          caseSensitive: false,
        ),
      ),
      'Validate support runway before final recommendation.',
    );
    if (rows.isEmpty) {
      rows.addAll(const [
        [
          'Must-have capabilities',
          'TBD',
          'Collect throughput, ports, power, HA, licensing, and lifecycle requirements.',
        ],
        [
          'Current portfolio facts',
          'TBD',
          'Use sourced datasheet/portfolio facts before final recommendation.',
        ],
      ]);
    }
    return rows;
  }

  List<List<String>> _decisionRows(List<_ComparisonCandidate> candidates) {
    final ranked = [...candidates]
      ..sort((a, b) => b.numericFit.compareTo(a.numericFit));
    final best = ranked.isEmpty ? null : ranked.first;
    final rejected = ranked
        .skip(1)
        .take(3)
        .map((candidate) {
          return '${candidate.product}: ${candidate.primaryCaution}';
        })
        .join(' | ');
    return [
      [
        'Primary shortlist',
        best == null
            ? 'No candidate with enough structured data yet'
            : '${best.product} (${best.fitScore})',
        'Sourced capability facts, lifecycle status, and customer must-have requirements',
        best?.confidence ?? 'Low',
      ],
      [
        'Rejected / caution list',
        rejected.isEmpty ? 'Not enough alternatives to rank yet' : rejected,
        'Explicit rejection reasons for alternatives that fail power, port, WAN, lifecycle, or operational fit',
        ranked.length > 1 ? 'Medium' : 'Low',
      ],
      [
        'Replacement guidance',
        'Treat EoX replacement PIDs as suggestedMigrationPid hints only',
        'Validate newest current portfolio candidates against Wi-Fi 7, UPOE, mGig, uplinks, licensing, and lifecycle',
        'High',
      ],
    ];
  }

  List<List<String>> _gateRows(List<List<String>> requirements) {
    String detected(String requirement) {
      for (final row in requirements) {
        if (row.isNotEmpty &&
            row.first.toLowerCase().contains(requirement.toLowerCase())) {
          return row.length > 1 ? row[1] : 'Detected';
        }
      }
      return 'TBD';
    }

    return [
      [
        'Wi-Fi generation',
        detected('Wi-Fi generation'),
        'Candidate supports required AP generation, access speed, and power class',
        'Reject access switch or AP recommendation if Wi-Fi generation drives unsupported mGig/UPOE need',
      ],
      [
        'PoE / UPOE',
        detected('PoE / UPOE'),
        'Per-switch and per-site power budget covers APs plus reserve',
        'Reject otherwise valid switches that cannot power the target AP mix',
      ],
      [
        'Uplinks / bandwidth',
        detected('Uplinks / bandwidth'),
        'Uplinks and throughput meet demand with inspection/HA overhead',
        'Reject candidates that meet nominal ports but bottleneck uplink or security throughput',
      ],
      [
        'Lifecycle',
        detected('Lifecycle'),
        'Current lifecycle and support runway are acceptable for the customer horizon',
        'Reject stale migration hints when newer current models better fit requirements',
      ],
    ];
  }

  List<List<String>> _shortlistRows(List<_ComparisonCandidate> candidates) {
    final ranked = [...candidates]
      ..sort((a, b) => b.numericFit.compareTo(a.numericFit));
    if (ranked.isEmpty) {
      return const [
        [
          '1',
          'TBD',
          'TBD',
          'Collect model candidates and sourced facts.',
          'No products detected.',
        ],
      ];
    }
    return [
      for (var index = 0; index < ranked.length && index < 12; index++)
        [
          '${index + 1}',
          ranked[index].product,
          ranked[index].fitScore,
          ranked[index].recommendation,
          ranked[index].primaryCaution,
        ],
    ];
  }

  List<List<String>> _replacementCautionRows(String content) {
    final mentionsEox = RegExp(
      r'\b(eox|eol|eos|ldos|replacement pid|migration)\b',
      caseSensitive: false,
    ).hasMatch(content);
    return [
      [
        'EoX replacement PID',
        'Use as suggestedMigrationPid, not final recommendation',
        'Replacement PIDs often point to the next released model and may miss newer requirements',
        'Compare against current portfolio and hard requirements before recommending',
      ],
      [
        'Wi-Fi 7 / UPOE',
        'Validate power and mGig requirements independently',
        'A lifecycle replacement can be electrically or operationally wrong for newer APs',
        'Check AP draw, UPOE/UPOE+ budget, 2.5/5/10G access, and uplink headroom',
      ],
      [
        'Current portfolio',
        mentionsEox
            ? 'EoX language detected; superseding current models must be considered'
            : 'Always compare against current available model families',
        'Portfolio drift can make older migration guidance stale',
        'Use current datasheets/catalog facts and checked date',
      ],
    ];
  }

  List<List<String>> _alternativeRows(
    ArtifactDocument document,
    String content,
  ) {
    final rows = <List<String>>[];
    for (final section in document.sections) {
      final title = section.title.toLowerCase();
      if (!title.contains('alternative') &&
          !title.contains('reject') &&
          !title.contains('caveat')) {
        continue;
      }
      for (final bullet in section.bullets) {
        rows.add([section.title, bullet, 'Review against requirements.']);
      }
      if (section.bullets.isEmpty && section.body.trim().isNotEmpty) {
        rows.add([
          section.title,
          _shorten(section.body.trim(), 180),
          'Review against requirements.',
        ]);
      }
    }
    if (rows.isNotEmpty) return rows.take(24).toList(growable: false);
    final products = _productNames(content);
    return products
        .skip(1)
        .take(12)
        .map(
          (product) => [
            product,
            'Candidate alternative',
            'Reject only with sourced capability, lifecycle, or requirement-fit evidence.',
          ],
        )
        .toList(growable: false);
  }

  List<List<String>> _assumptionRows(ArtifactDocument document) {
    if (document.assumptions.isNotEmpty) {
      return document.assumptions
          .take(20)
          .map((assumption) => [assumption, 'Validate before recommendation.'])
          .toList(growable: false);
    }
    return const [
      [
        'EoX replacement PIDs are migration hints, not final model recommendations.',
        'Current portfolio and requirement fit must override stale migration hints.',
      ],
      [
        'Capability facts should be source-backed before final recommendation.',
        'Prevents unsupported product claims in customer-facing outputs.',
      ],
    ];
  }

  List<WorkbookTable> _sourceTables(ArtifactDocument document) {
    final tables = <WorkbookTable>[];
    for (var i = 0; i < document.tables.length && i < 4; i++) {
      final table = document.tables[i];
      if (table.rows.length < 2) continue;
      tables.add(WorkbookTable(name: 'Source ${i + 1}', rows: table.rows));
    }
    return tables;
  }

  int? _firstHeaderIndex(List<String> header, List<String> terms) {
    for (var i = 0; i < header.length; i++) {
      if (terms.any((term) => header[i].contains(term))) return i;
    }
    return null;
  }

  List<int> _headerIndexes(List<String> header, List<String> terms) {
    final indexes = <int>[];
    for (var i = 0; i < header.length; i++) {
      if (terms.any((term) => header[i].contains(term))) indexes.add(i);
    }
    return indexes;
  }

  String? _cell(List<String> row, int? index) {
    if (index == null || index >= row.length) return null;
    final value = row[index].trim();
    return value.isEmpty ? null : value;
  }

  String? _joinCells(List<String> row, List<int> indexes) {
    final values = indexes
        .where((index) => index < row.length)
        .map((index) => row[index].trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    if (values.isEmpty) return null;
    return values.join(' | ');
  }

  List<String> _productNames(String content) {
    final matches = <String>{};
    for (final match in RegExp(
      r'\b(?:C\d{3,5}[A-Z0-9-]*|CW\d{4}[A-Z0-9-]*|AIR-[A-Z0-9-]+|MR\d{2,4}[A-Z0-9-]*|MS\d{2,4}[A-Z0-9-]*|MX\d{2,4}[A-Z0-9-]*|ISR\d{3,5}[A-Z0-9-]*|ASR\d{3,5}[A-Z0-9-]*|NCS\d{3,5}[A-Z0-9-]*|Catalyst\s+\d{4}[A-Z0-9-]*|Meraki\s+[A-Z]{2}\d{2,4})\b',
      caseSensitive: false,
    ).allMatches(content)) {
      matches.add(match.group(0)!.replaceAll(RegExp(r'\s+'), ' ').trim());
    }
    return matches.toList(growable: false);
  }

  String? _first(String content, RegExp pattern) {
    final match = pattern.firstMatch(content);
    if (match == null) return null;
    return match.group(1) ?? match.group(0);
  }

  String _shorten(String value, int maxLength) {
    final singleLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.length <= maxLength) return singleLine;
    return '${singleLine.substring(0, maxLength - 1).trim()}...';
  }
}

class _ComparisonCandidate {
  final String product;
  final String constraints;
  final String lifecycle;
  final String fitScore;
  final String recommendation;

  const _ComparisonCandidate({
    required this.product,
    required this.constraints,
    required this.lifecycle,
    required this.fitScore,
    required this.recommendation,
  });

  factory _ComparisonCandidate.fromRow(List<String> row) {
    String cell(int index, String fallback) {
      if (index >= row.length) return fallback;
      final value = row[index].trim();
      return value.isEmpty ? fallback : value;
    }

    return _ComparisonCandidate(
      product: cell(0, 'TBD'),
      constraints: cell(3, 'Validate hard requirements.'),
      lifecycle: cell(4, 'Needs lifecycle validation'),
      fitScore: cell(5, 'TBD'),
      recommendation: cell(6, 'Review'),
    );
  }

  double get numericFit {
    final match = RegExp(r'\d+(?:\.\d+)?').firstMatch(fitScore);
    return double.tryParse(match?.group(0) ?? '') ?? 0;
  }

  String get confidence {
    if (numericFit >= 4) return 'Medium';
    if (numericFit > 0) return 'Low';
    return 'Low';
  }

  String get primaryCaution {
    final lifecycleText = lifecycle.toLowerCase();
    if (lifecycleText.contains('ldos') ||
        lifecycleText.contains('eol') ||
        lifecycleText.contains('eos') ||
        lifecycleText.contains('verify')) {
      return lifecycle;
    }
    return constraints;
  }
}
