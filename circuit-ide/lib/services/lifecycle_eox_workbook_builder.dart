import '../models/artifact_document.dart';
import 'workbook_table.dart';

class LifecycleEoxWorkbookBuilder {
  const LifecycleEoxWorkbookBuilder();

  bool matches(String prompt) {
    final normalized = prompt.toLowerCase();
    return RegExp(
      r'\b(eox|eol|eos|ldos|last date of support|end of (?:life|sale|support)|lifecycle (?:report|matrix|review|status)|replacement pid|migration pid|support risk)\b',
    ).hasMatch(normalized);
  }

  List<WorkbookTable> build({
    required String prompt,
    required String content,
    required ArtifactDocument document,
  }) {
    final records = _lifecycleRows(
      prompt: prompt,
      content: content,
      document: document,
    );
    final lifecycleRecords = records
        .map(_LifecycleRecord.fromRow)
        .toList(growable: false);
    return [
      WorkbookTable(
        name: 'Lifecycle Status',
        rows: [
          const [
            'Product / PID',
            'Lifecycle status',
            'End of sale',
            'Last date of support',
            'Risk',
            'Source / evidence',
          ],
          ...records,
        ],
      ),
      WorkbookTable(
        name: 'Urgency Timeline',
        rows: [
          const [
            'Product / PID',
            'Support milestone',
            'Risk tier',
            'Urgency',
            'Recommended action',
          ],
          ..._urgencyRows(lifecycleRecords),
        ],
      ),
      WorkbookTable(
        name: 'Migration Hints',
        rows: [
          const [
            'Current product',
            'EoX migration hint',
            'How to treat it',
            'Required validation',
          ],
          ..._migrationHintRows(document, content),
        ],
      ),
      WorkbookTable(
        name: 'Replacement Evaluation',
        rows: [
          const [
            'Requirement',
            'Why it matters',
            'Validation needed before recommendation',
          ],
          ..._replacementValidationRows('$prompt\n$content'),
        ],
      ),
      WorkbookTable(
        name: 'Decision Gates',
        rows: [
          const [
            'Gate',
            'Pass criteria',
            'Reject / caution trigger',
            'Required evidence',
          ],
          ..._decisionGateRows('$prompt\n$content'),
        ],
      ),
      WorkbookTable(
        name: 'Source Quality',
        rows: [
          const [
            'Evidence item',
            'Authority level',
            'Required fields',
            'Status',
          ],
          ..._sourceQualityRows(lifecycleRecords),
        ],
      ),
      WorkbookTable(
        name: 'WiFi7 UPOE Readiness',
        rows: [
          const [
            'Requirement',
            'Why it matters',
            'Replacement validation',
            'Status',
          ],
          ..._wifi7ReadinessRows('$prompt\n$content'),
        ],
      ),
      WorkbookTable(
        name: 'Risk Register',
        rows: [
          const ['Risk', 'Impact', 'Mitigation'],
          ..._riskRows(document, content),
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

  List<List<String>> _lifecycleRows({
    required String prompt,
    required String content,
    required ArtifactDocument document,
  }) {
    for (final table in document.tables) {
      final rows = _lifecycleRowsFromTable(table);
      if (rows.isNotEmpty) return rows;
    }
    final products = _productNames('$prompt\n$content');
    if (products.isEmpty) {
      return const [
        [
          'TBD',
          'Needs lookup',
          'TBD',
          'TBD',
          'Unknown',
          'Use Cisco EoX/API or official Cisco source for lifecycle dates.',
        ],
      ];
    }
    return products
        .take(48)
        .map(
          (product) => [
            product,
            _statusNear(content, product) ?? 'Needs lookup',
            _dateNear(content, product, const [
                  'end of sale',
                  'end-of-sale',
                  'eos',
                ]) ??
                'TBD',
            _dateNear(content, product, const [
                  'last date of support',
                  'ldos',
                  'end of support',
                  'eol',
                ]) ??
                'TBD',
            _riskNear(content, product) ?? 'Review',
            'Lifecycle dates require Cisco EoX/API or official Cisco source.',
          ],
        )
        .toList(growable: false);
  }

  List<List<String>> _lifecycleRowsFromTable(ArtifactTable table) {
    if (table.rows.length < 2) return const [];
    final header = table.rows.first.map((cell) => cell.toLowerCase()).toList();
    final productIndex = _firstHeaderIndex(header, const [
      'product',
      'model',
      'pid',
      'sku',
      'part',
    ]);
    if (productIndex == null) return const [];
    final statusIndex = _firstHeaderIndex(header, const [
      'status',
      'lifecycle',
      'stage',
    ]);
    final eosIndex = _firstHeaderIndex(header, const [
      'end of sale',
      'end-of-sale',
      'eos',
      'sale',
    ]);
    final ldosIndex = _firstHeaderIndex(header, const [
      'ldos',
      'last date',
      'last support',
      'end of support',
      'eol',
    ]);
    final riskIndex = _firstHeaderIndex(header, const ['risk', 'severity']);
    final sourceIndex = _firstHeaderIndex(header, const [
      'source',
      'evidence',
      'url',
      'citation',
    ]);
    final rows = <List<String>>[];
    for (final row in table.rows.skip(1)) {
      if (productIndex >= row.length) continue;
      final product = row[productIndex].trim();
      if (product.isEmpty) continue;
      rows.add([
        product,
        _cell(row, statusIndex) ?? 'Needs lookup',
        _cell(row, eosIndex) ?? 'TBD',
        _cell(row, ldosIndex) ?? 'TBD',
        _cell(row, riskIndex) ?? _riskFromDates(row.join(' ')),
        _cell(row, sourceIndex) ??
            'Use Cisco EoX/API or official Cisco source for lifecycle dates.',
      ]);
    }
    return rows.take(80).toList(growable: false);
  }

  List<List<String>> _migrationHintRows(
    ArtifactDocument document,
    String content,
  ) {
    final rows = <List<String>>[];
    for (final table in document.tables) {
      if (table.rows.length < 2) continue;
      final header = table.rows.first
          .map((cell) => cell.toLowerCase())
          .toList();
      final productIndex = _firstHeaderIndex(header, const [
        'product',
        'model',
        'pid',
        'sku',
        'part',
      ]);
      final replacementIndex = _firstHeaderIndex(header, const [
        'replacement',
        'migration',
        'successor',
      ]);
      if (productIndex == null || replacementIndex == null) continue;
      for (final row in table.rows.skip(1)) {
        if (productIndex >= row.length || replacementIndex >= row.length) {
          continue;
        }
        final product = row[productIndex].trim();
        final replacement = row[replacementIndex].trim();
        if (product.isEmpty || replacement.isEmpty) continue;
        rows.add([
          product,
          replacement,
          'Migration clue only, not final recommendation.',
          'Compare against current portfolio, PoE/UPOE, multigig, uplinks, licensing, HA, and lifecycle runway.',
        ]);
      }
    }
    if (rows.isNotEmpty) return rows.take(48).toList(growable: false);
    final products = _productNames(content);
    return products
        .take(24)
        .map(
          (product) => [
            product,
            'TBD',
            'Migration clue only, not final recommendation.',
            'Validate replacement against current requirements and portfolio data.',
          ],
        )
        .toList(growable: false);
  }

  List<List<String>> _urgencyRows(List<_LifecycleRecord> records) {
    if (records.isEmpty) {
      return const [
        [
          'TBD',
          'Lifecycle dates missing',
          'Unknown',
          'Needs lookup',
          'Fetch official EoX data before prioritizing migration.',
        ],
      ];
    }
    return records
        .map((record) {
          final milestone = record.ldos != 'TBD'
              ? 'LDOS ${record.ldos}'
              : record.endOfSale != 'TBD'
              ? 'End of sale ${record.endOfSale}'
              : 'Lifecycle date TBD';
          return [
            record.product,
            milestone,
            record.risk,
            record.urgency,
            record.action,
          ];
        })
        .toList(growable: false);
  }

  List<List<String>> _replacementValidationRows(String content) {
    final rows = <List<String>>[
      [
        'Current lifecycle dates',
        'Lifecycle dates define support risk and urgency.',
        'Use Cisco EoX/API or official Cisco source; include checked date.',
      ],
      [
        'Current portfolio candidates',
        'EoX migration PID may be stale or incomplete.',
        'Compare migration hint against current model families and datasheets.',
      ],
      [
        'PoE/UPOE budget',
        'Wi-Fi 6E/7 APs and cameras can require higher power classes.',
        'Reject candidates that cannot meet aggregate and per-port power draw.',
      ],
      [
        'Multigig / uplinks',
        'Modern APs and WAN designs can outgrow legacy access/uplink speeds.',
        'Validate access port speed, uplink modules, stacking, and oversubscription.',
      ],
      [
        'Licensing / operations',
        'Equivalent hardware can fail the operational model.',
        'Validate licensing tier, management plane, support coverage, and migration effort.',
      ],
    ];
    if (RegExp(
      r'\b(wi[- ]?fi\s*7|wifi\s*7)\b',
      caseSensitive: false,
    ).hasMatch(content)) {
      rows.add([
        'Wi-Fi 7 readiness',
        'Wi-Fi 7 often changes power, multigig, and uplink needs.',
        'Confirm AP model draw, mGig port count, UPOE/UPOE+, and switch power supplies.',
      ]);
    }
    return rows;
  }

  List<List<String>> _decisionGateRows(String content) {
    final wifi7 = RegExp(
      r'\b(wi[- ]?fi\s*7|wifi\s*7)\b',
      caseSensitive: false,
    ).hasMatch(content);
    final upoe = RegExp(
      r'\b(upoe\+?|802\.3bt|60w|90w)\b',
      caseSensitive: false,
    ).hasMatch(content);
    return [
      [
        'Lifecycle authority',
        'Lifecycle dates come from Cisco EoX/API or official Cisco source with checked date',
        'Unsupported dates, copied reseller pages, or missing checked date',
        'Official Cisco lifecycle source',
      ],
      [
        'Migration hint treatment',
        'Replacement PID is stored as suggestedMigrationPid only',
        'Treating EoX replacement PID as final recommendation',
        'Current portfolio comparison and requirement-fit evidence',
      ],
      [
        'Current portfolio fit',
        'Candidate is compared against current model families and newer options',
        'Newer model satisfies requirements better than migration hint',
        'Datasheets/catalog facts for current candidates',
      ],
      [
        'Power and access speed',
        wifi7 || upoe
            ? 'Wi-Fi 7/UPOE signal detected; validate UPOE/UPOE+ and mGig explicitly'
            : 'Validate AP power draw, PoE budget, access speed, and uplinks',
        'Candidate lacks required per-port power, aggregate power, or mGig access',
        'AP power draw, switch power budget, port speed, and uplink evidence',
      ],
      [
        'Operational fit',
        'Licensing, management plane, support, and migration effort fit the customer',
        'Hardware works but operational model does not match customer standards',
        'Licensing/support plan and customer operations requirements',
      ],
    ];
  }

  List<List<String>> _sourceQualityRows(List<_LifecycleRecord> records) {
    final products = records.isEmpty ? ['TBD'] : records.map((r) => r.product);
    return [
      for (final product in products)
        [
          '$product lifecycle dates',
          'Authoritative',
          'Status, End of Sale, LDOS, source URL/API record, checked date',
          'Needs official Cisco validation',
        ],
      [
        'Replacement suitability',
        'Advisory',
        'Current portfolio candidate, capability facts, rejected alternatives, fit rationale',
        'Needs current portfolio validation',
      ],
      [
        'Customer requirements',
        'Customer supplied',
        'Wi-Fi generation, AP power, port speed, WAN/security throughput, HA, licensing, growth',
        'Needs customer confirmation',
      ],
    ];
  }

  List<List<String>> _wifi7ReadinessRows(String content) {
    final wifi7Detected = RegExp(
      r'\b(wi[- ]?fi\s*7|wifi\s*7)\b',
      caseSensitive: false,
    ).hasMatch(content);
    return [
      [
        'Wi-Fi 7 AP support',
        'Wi-Fi 7 can change port speed and power assumptions',
        'Confirm replacement switch supports required AP model and mGig access',
        wifi7Detected ? 'Detected' : 'Needs input',
      ],
      [
        'UPOE / UPOE+ budget',
        'Modern APs can require higher per-port and aggregate power',
        'Validate per-port power class, total power supplies, and reserve budget',
        RegExp(
              r'\b(upoe\+?|802\.3bt|60w|90w)\b',
              caseSensitive: false,
            ).hasMatch(content)
            ? 'Detected'
            : 'Needs input',
      ],
      [
        'Uplink headroom',
        'mGig AP access can oversubscribe legacy uplinks',
        'Validate 10G/25G/40G/100G uplinks, stacking, and oversubscription',
        'Needs validation',
      ],
      [
        'Lifecycle runway',
        'A technically compatible replacement still needs support runway',
        'Compare current candidates by lifecycle, support, licensing, and availability',
        'Needs validation',
      ],
    ];
  }

  List<List<String>> _riskRows(ArtifactDocument document, String content) {
    final rows = <List<String>>[];
    for (final section in document.sections) {
      final title = section.title.toLowerCase();
      if (!title.contains('risk') &&
          !title.contains('finding') &&
          !title.contains('caveat')) {
        continue;
      }
      for (final bullet in section.bullets) {
        rows.add([
          bullet,
          'Review',
          'Assign owner and validate with source evidence.',
        ]);
      }
      if (section.bullets.isEmpty && section.body.trim().isNotEmpty) {
        rows.add([
          _shorten(section.body.trim(), 180),
          'Review',
          'Assign owner and validate with source evidence.',
        ]);
      }
    }
    if (rows.isNotEmpty) return rows.take(30).toList(growable: false);
    final highRiskProducts = _productNames(content).take(12);
    return [
      for (final product in highRiskProducts)
        [
          '$product lifecycle or replacement suitability is not fully validated.',
          'Potential support or design risk',
          'Check official EoX dates and compare current portfolio candidates.',
        ],
      if (highRiskProducts.isEmpty)
        const [
          'Lifecycle data is incomplete.',
          'Potential unsupported recommendation',
          'Add official lifecycle sources before customer-facing handoff.',
        ],
    ];
  }

  List<List<String>> _assumptionRows(ArtifactDocument document) {
    if (document.assumptions.isNotEmpty) {
      return document.assumptions
          .take(20)
          .map(
            (assumption) => [
              assumption,
              'Validate before final recommendation.',
            ],
          )
          .toList(growable: false);
    }
    return const [
      [
        'Cisco EoX data is authoritative for lifecycle dates only.',
        'Do not treat replacement PIDs as final recommendations.',
      ],
      [
        'Replacement recommendations require current portfolio and requirement validation.',
        'Newer platforms or Wi-Fi 7/UPOE needs can supersede EoX migration hints.',
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

  String? _cell(List<String> row, int? index) {
    if (index == null || index >= row.length) return null;
    final value = row[index].trim();
    return value.isEmpty ? null : value;
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

  String? _statusNear(String content, String product) {
    final nearby = _nearbyText(content, product);
    if (nearby == null) return null;
    final status = RegExp(
      r'\b(announced|end[- ]of[- ]sale|end[- ]of[- ]support|supported|active|obsolete|retired)\b',
      caseSensitive: false,
    ).firstMatch(nearby);
    return status?.group(1);
  }

  String? _dateNear(String content, String product, List<String> labels) {
    final nearby = _nearbyText(content, product);
    if (nearby == null) return null;
    final labelPattern = labels.map(RegExp.escape).join('|');
    final labeled = RegExp(
      '(?:$labelPattern)\\D{0,24}([0-9]{1,2}[-/ ][A-Za-z]{3,9}[-/ ][0-9]{2,4}|[A-Za-z]{3,9}\\s+[0-9]{1,2},?\\s+[0-9]{4}|[0-9]{4}-[0-9]{2}-[0-9]{2})',
      caseSensitive: false,
    ).firstMatch(nearby);
    if (labeled != null) return labeled.group(1);
    final anyDate = RegExp(
      r'\b([0-9]{1,2}[-/ ][A-Za-z]{3,9}[-/ ][0-9]{2,4}|[A-Za-z]{3,9}\s+[0-9]{1,2},?\s+[0-9]{4}|[0-9]{4}-[0-9]{2}-[0-9]{2})\b',
      caseSensitive: false,
    ).firstMatch(nearby);
    return anyDate?.group(1);
  }

  String? _riskNear(String content, String product) {
    final nearby = _nearbyText(content, product);
    if (nearby == null) return null;
    return _riskFromDates(nearby);
  }

  String _riskFromDates(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('unsupported') ||
        lower.contains('obsolete') ||
        lower.contains('expired') ||
        lower.contains('end of support')) {
      return 'High';
    }
    if (lower.contains('ldos') ||
        lower.contains('eol') ||
        lower.contains('end of sale')) {
      return 'Medium';
    }
    return 'Review';
  }

  String? _nearbyText(String content, String product) {
    final index = content.toLowerCase().indexOf(product.toLowerCase());
    if (index < 0) return null;
    final start = (index - 160).clamp(0, content.length).toInt();
    final end = (index + product.length + 240).clamp(0, content.length).toInt();
    return content.substring(start, end);
  }

  String _shorten(String value, int maxLength) {
    final singleLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.length <= maxLength) return singleLine;
    return '${singleLine.substring(0, maxLength - 1).trim()}...';
  }
}

class _LifecycleRecord {
  final String product;
  final String status;
  final String endOfSale;
  final String ldos;
  final String risk;

  const _LifecycleRecord({
    required this.product,
    required this.status,
    required this.endOfSale,
    required this.ldos,
    required this.risk,
  });

  factory _LifecycleRecord.fromRow(List<String> row) {
    String cell(int index, String fallback) {
      if (index >= row.length) return fallback;
      final value = row[index].trim();
      return value.isEmpty ? fallback : value;
    }

    return _LifecycleRecord(
      product: cell(0, 'TBD'),
      status: cell(1, 'Needs lookup'),
      endOfSale: cell(2, 'TBD'),
      ldos: cell(3, 'TBD'),
      risk: cell(4, 'Review'),
    );
  }

  String get urgency {
    final lower = '$status $risk $ldos'.toLowerCase();
    if (lower.contains('high') ||
        lower.contains('end of support') ||
        lower.contains('unsupported')) {
      return 'Immediate review';
    }
    if (lower.contains('review') ||
        lower.contains('medium') ||
        lower.contains('tbd')) {
      return 'Validate dates';
    }
    return 'Monitor';
  }

  String get action {
    final lower = '$status $risk'.toLowerCase();
    if (lower.contains('high') ||
        lower.contains('end of support') ||
        lower.contains('unsupported')) {
      return 'Build migration plan and compare current portfolio candidates.';
    }
    if (lower.contains('active')) {
      return 'Confirm checked date and support runway; no final replacement without requirement fit.';
    }
    return 'Validate official lifecycle data and replacement suitability.';
  }
}
