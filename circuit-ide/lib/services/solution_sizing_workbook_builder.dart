import '../models/artifact_document.dart';
import 'workbook_table.dart';

class SolutionSizingWorkbookBuilder {
  const SolutionSizingWorkbookBuilder();

  bool matches(String prompt) {
    final normalized = prompt.toLowerCase();
    return RegExp(
      r'\b(solution sizing|sizing workbook|sizing model|sizing matrix|size (?:a |the )?(?:solution|network|campus|branch|datacenter|data center)|poe budget|wan sizing|throughput sizing|client count|ap count)\b',
    ).hasMatch(normalized);
  }

  List<WorkbookTable> build({
    required String prompt,
    required String content,
    required ArtifactDocument document,
  }) {
    final fullContent = '$prompt\n$content';
    final requirements = _requirementRows(fullContent);
    final profile = _SizingProfile.fromRequirements(requirements, fullContent);
    final recommendations = _recommendationRows(document);
    final assumptions = _assumptionRows(document, content);
    final sourceTables = _sourceTables(document);
    return [
      WorkbookTable(
        name: 'Executive Summary',
        rows: [
          const [
            'Executive Signal',
            'Current Value',
            'Sizing Interpretation',
            'Next Action',
          ],
          ..._executiveSummaryRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'Requirements',
        rows: [
          const ['Metric', 'Value', 'Notes'],
          ...requirements,
        ],
      ),
      WorkbookTable(
        name: 'Sizing Inputs',
        rows: [
          const ['Category', 'Input', 'Value', 'Notes'],
          ..._inputRows(requirements),
        ],
      ),
      WorkbookTable(
        name: 'Site Distribution',
        rows: [
          const [
            'Site / Scope',
            'Users',
            'APs',
            'WAN',
            'Estimated AP PoE W',
            'Notes',
          ],
          ..._siteDistributionRows(profile, document),
        ],
      ),
      WorkbookTable(
        name: 'Capacity Model',
        rows: [
          const [
            'Demand Area',
            'Current Input',
            'Planning Headroom',
            'Planning Value',
            'Design Notes',
          ],
          ..._capacityRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'PoE Budget',
        rows: [
          const [
            'Load Type',
            'Quantity',
            'Watts Each',
            'Estimated Watts',
            'Minimum Budget',
            'Notes',
          ],
          ..._poeRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'Closet Power Plan',
        rows: [
          const [
            'Closet / Switch Group',
            'Planning Load',
            'Reserve',
            'Minimum Capability',
            'Validation Needed',
          ],
          ..._closetPowerRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'WAN Throughput',
        rows: [
          const [
            'Traffic Class',
            'Required Mbps',
            'Design Headroom',
            'Recommended Mbps',
            'Notes',
          ],
          ..._wanRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'HA Growth',
        rows: [
          const ['Constraint', 'Design Treatment', 'Status', 'Notes'],
          ..._haGrowthRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'Licensing Support',
        rows: [
          const [
            'Area',
            'Sizing Dependency',
            'Licensing / Support Check',
            'Risk If Missed',
            'Status',
          ],
          ..._licensingSupportRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'Sizing Audit',
        rows: [
          const [
            'Audit Area',
            'Evidence Signal',
            'Readiness',
            'Score',
            'Required Follow-Up',
          ],
          ..._sizingAuditRows(
            profile: profile,
            requirementRows: requirements,
            assumptionRows: assumptions,
            sourceSheetCount: sourceTables.length,
          ),
        ],
      ),
      WorkbookTable(
        name: 'Requirement Gates',
        rows: [
          const [
            'Gate',
            'Requirement Signal',
            'Pass Criteria',
            'Current Status',
            'Sizing Impact',
          ],
          ..._requirementGateRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'Candidate Validation',
        rows: [
          const [
            'Candidate / Area',
            'Must Validate',
            'Why It Matters',
            'Reject If',
            'Status',
          ],
          ..._candidateValidationRows(profile, '$prompt\n$content'),
        ],
      ),
      WorkbookTable(
        name: 'Recommendations',
        rows: [
          const ['Area', 'Recommendation', 'Rationale', 'Status'],
          ...recommendations,
        ],
      ),
      WorkbookTable(
        name: 'Implementation Sequence',
        rows: [
          const ['Phase', 'Workstream', 'Entry Criteria', 'Exit Criteria'],
          ..._implementationSequenceRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'Risk Register',
        rows: [
          const ['Risk', 'Trigger', 'Mitigation', 'Severity', 'Owner'],
          ..._riskRows(profile),
        ],
      ),
      const WorkbookTable(
        name: 'Validation',
        rows: [
          ['Check', 'Why it matters', 'Status'],
          [
            'PoE/UPOE budget',
            'Wi-Fi 6E/7 APs and cameras can exceed older access switch power budgets',
            'Needs validation',
          ],
          [
            'Multigig access ports',
            'Modern APs can require 2.5/5/10G access links',
            'Needs validation',
          ],
          [
            'WAN throughput',
            'Security services, SD-WAN, and inspection reduce usable throughput',
            'Needs validation',
          ],
          [
            'High availability',
            'Core, firewall, WAN, and power design must match outage tolerance',
            'Needs validation',
          ],
          [
            'Lifecycle / LDOS',
            'Recommended models should be checked against current lifecycle data',
            'Needs validation',
          ],
        ],
      ),
      WorkbookTable(
        name: 'Assumptions',
        rows: [
          const ['Assumption', 'Impact'],
          ...assumptions,
        ],
      ),
      WorkbookTable(
        name: 'Decision Summary',
        rows: [
          const ['Area', 'Recommendation', 'Evidence Needed', 'Confidence'],
          ..._decisionRows(profile),
        ],
      ),
      if (sourceTables.isNotEmpty) ...sourceTables,
    ];
  }

  Map<String, Object?> metadataFor(List<WorkbookTable> tables) {
    final requirementRows = _rowsFor(tables, 'Requirements').skip(1).toList();
    final gateRows = _rowsFor(tables, 'Requirement Gates').skip(1).toList();
    final candidateRows = _rowsFor(
      tables,
      'Candidate Validation',
    ).skip(1).toList();
    final recommendationRows = _rowsFor(
      tables,
      'Recommendations',
    ).skip(1).toList();
    final riskRows = _rowsFor(tables, 'Risk Register').skip(1).toList();
    final validationRows = _rowsFor(tables, 'Validation').skip(1).toList();
    final assumptionRows = _rowsFor(tables, 'Assumptions').skip(1).toList();
    final decisionRows = _rowsFor(tables, 'Decision Summary').skip(1).toList();
    final sizingAuditRows = _rowsFor(tables, 'Sizing Audit').skip(1).toList();
    final sourceSheetCount = tables
        .where((table) => table.name.toLowerCase().startsWith('source '))
        .length;
    final sizingAuditScore = _averageAuditScore(sizingAuditRows);
    final sizingAuditReadyCount = sizingAuditRows.where((row) {
      if (row.length < 3) return false;
      return row[2].toLowerCase().contains('ready') ||
          row[2].toLowerCase().contains('captured');
    }).length;
    final hardGateRows = _hardGateRows(
      gateRows: gateRows,
      candidateRows: candidateRows,
      validationRows: validationRows,
    );
    final customerQuestions = _customerQuestionRows(
      requirementRows: requirementRows,
      gateRows: gateRows,
      riskRows: riskRows,
      assumptionRows: assumptionRows,
    );
    final validationRoadmap = _validationRoadmapRows(
      auditRows: sizingAuditRows,
      riskRows: riskRows,
      candidateRows: candidateRows,
    );
    final sizingReadinessLevel = _sizingReadinessLevel(
      sizingAuditScore: sizingAuditScore,
      hardGateCount: hardGateRows.length,
      highRiskCount: _severityCount(riskRows, 'High'),
      sourceSheetCount: sourceSheetCount,
    );

    return {
      'artifact': 'solution_sizing_workbook',
      'workbookKind': 'solution_sizing',
      'sheetCount': tables.length,
      'sourceSheetCount': sourceSheetCount,
      'requirementCount': requirementRows.length,
      'gateCount': gateRows.length,
      'candidateCheckCount': candidateRows.length,
      'recommendationCount': recommendationRows.length,
      'riskCount': riskRows.length,
      'highRiskCount': _severityCount(riskRows, 'High'),
      'mediumRiskCount': _severityCount(riskRows, 'Medium'),
      'validationCheckCount': validationRows.length,
      'assumptionCount': assumptionRows.length,
      'decisionCount': decisionRows.length,
      'sizingAuditCount': sizingAuditRows.length,
      'sizingAuditScore': sizingAuditScore,
      'sizingAuditReadyCount': sizingAuditReadyCount,
      'sizingReadinessLevel': sizingReadinessLevel,
      'sizingHandoffStatus': _sizingHandoffStatus(sizingReadinessLevel),
      'hardGateFailures': hardGateRows,
      'hardGateFailureCount': hardGateRows.length,
      'customerFollowUpQuestions': customerQuestions,
      'customerFollowUpQuestionCount': customerQuestions.length,
      'validationRoadmap': validationRoadmap,
      'validationRoadmapCount': validationRoadmap.length,
      'sizingDecisionPosture': _sizingDecisionPosture(
        hardGateRows.length,
        _severityCount(riskRows, 'High'),
        sourceSheetCount,
      ),
      'hasSizingAudit': _hasSheet(tables, 'Sizing Audit'),
      'hasSourceEvidence': sourceSheetCount > 0,
      'hasAssumptionCoverage': assumptionRows.isNotEmpty,
      'users': _requirementValue(requirementRows, 'Users'),
      'accessPoints': _requirementValue(requirementRows, 'Access points'),
      'switches': _requirementValue(requirementRows, 'Switches'),
      'wan': _requirementValue(requirementRows, 'WAN speed'),
      'poe': _requirementValue(requirementRows, 'PoE'),
      'growth': _requirementValue(requirementRows, 'Growth'),
      'hasPoeBudget': _hasSheet(tables, 'PoE Budget'),
      'hasWanThroughput': _hasSheet(tables, 'WAN Throughput'),
      'hasClosetPower': _hasSheet(tables, 'Closet Power Plan'),
      'hasCandidateValidation': candidateRows.isNotEmpty,
      'hasLifecycleValidation': _containsText(tables, 'lifecycle'),
      'hasHighPowerApSignal':
          _containsText(tables, 'UPOE') ||
          _containsText(tables, 'Wi-Fi 7') ||
          _containsText(tables, '802.3bt'),
      'hasMultigigSignal':
          _containsText(tables, 'mGig') ||
          _containsText(tables, 'multigig') ||
          _containsText(tables, '2.5G') ||
          _containsText(tables, '5G'),
      'hasHaSignal':
          _containsText(tables, 'High availability') ||
          _containsText(tables, 'dual WAN') ||
          _containsText(tables, 'warm spare'),
    };
  }

  List<List<String>> _rowsFor(List<WorkbookTable> tables, String name) {
    for (final table in tables) {
      if (table.name.toLowerCase() == name.toLowerCase()) return table.rows;
    }
    return const [];
  }

  String _requirementValue(List<List<String>> rows, String metric) {
    final needle = metric.toLowerCase();
    for (final row in rows) {
      if (row.length < 2) continue;
      if (row.first.toLowerCase().contains(needle)) return row[1];
    }
    return '';
  }

  int _severityCount(List<List<String>> rows, String severity) {
    final needle = severity.toLowerCase();
    return rows.where((row) {
      if (row.length < 4) return false;
      return row[3].toLowerCase().contains(needle);
    }).length;
  }

  int _averageAuditScore(List<List<String>> rows) {
    final scores = rows
        .where((row) => row.length >= 4)
        .map((row) => int.tryParse(row[3]))
        .whereType<int>()
        .toList(growable: false);
    if (scores.isEmpty) return 0;
    final total = scores.fold<int>(0, (sum, value) => sum + value);
    return (total / scores.length).round();
  }

  List<String> _hardGateRows({
    required List<List<String>> gateRows,
    required List<List<String>> candidateRows,
    required List<List<String>> validationRows,
  }) {
    final failures = <String>[];
    for (final row in gateRows) {
      if (row.length < 4) continue;
      final gate = row[0];
      final status = row[3];
      final normalized = status.toLowerCase();
      if (normalized.contains('needs') ||
          normalized.contains('required') ||
          normalized.contains('validation')) {
        failures.add('$gate: $status');
      }
    }
    if (candidateRows.any((row) {
      if (row.length < 5) return false;
      final status = row[4].toLowerCase();
      return status.contains('unverified') ||
          status.contains('needs') ||
          status.contains('review');
    })) {
      failures.add(
        'Candidate facts: unverified product capability or lifecycle fit',
      );
    }
    if (validationRows.any(
      (row) =>
          row.any((cell) => cell.toLowerCase().contains('needs validation')),
    )) {
      failures.add('Validation checks: open workbook validation items remain');
    }
    return failures.toSet().take(8).toList(growable: false);
  }

  List<String> _customerQuestionRows({
    required List<List<String>> requirementRows,
    required List<List<String>> gateRows,
    required List<List<String>> riskRows,
    required List<List<String>> assumptionRows,
  }) {
    String value(String metric) => _requirementValue(requirementRows, metric);
    final questions = <String>[
      if (value('Users').isEmpty || value('Users') == 'TBD')
        'What are the current and projected user/client counts by site?',
      if (value('Access points').isEmpty || value('Access points') == 'TBD')
        'How many APs are planned by site/closet, and what Wi-Fi generation/power class?',
      if (value('WAN speed').isEmpty || value('WAN speed') == 'TBD')
        'What are primary/secondary WAN speeds, service mix, and inspected-throughput requirements?',
      if (value('Growth').isEmpty || value('Growth') == 'TBD')
        'What growth horizon and headroom target should drive ports, power, WAN, and licensing?',
      if (gateRows.any(
        (row) => row.join(' ').toLowerCase().contains('lifecycle'),
      ))
        'Which lifecycle/support sources and checked dates should govern final model selection?',
      if (riskRows.any(
        (row) => row.join(' ').toLowerCase().contains('wi-fi 7'),
      ))
        'For Wi-Fi 7/high-power APs, what UPOE/UPOE+ and mGig requirements are mandatory?',
      if (assumptionRows.isEmpty)
        'Which assumptions should be accepted, revised, or removed before customer handoff?',
    ];
    if (questions.isEmpty) {
      questions.add(
        'Which open gates must be closed before turning this sizing workbook into a BOM recommendation?',
      );
    }
    return questions.toSet().take(7).toList(growable: false);
  }

  List<String> _validationRoadmapRows({
    required List<List<String>> auditRows,
    required List<List<String>> riskRows,
    required List<List<String>> candidateRows,
  }) {
    final roadmap = <String>[];
    for (final row in auditRows) {
      if (row.length < 5) continue;
      final readiness = row[2].toLowerCase();
      if (readiness.contains('needs')) {
        roadmap.add('${row[0]}: ${row[4]}');
      }
    }
    for (final row in riskRows.where(
      (row) => row.length >= 5 && row[3].toLowerCase().contains('high'),
    )) {
      roadmap.add('${row[0]}: ${row[2]}');
    }
    if (candidateRows.isNotEmpty) {
      roadmap.add(
        'Candidate validation: close datasheet, lifecycle, licensing, PoE, mGig, uplink, and HA fit checks.',
      );
    }
    return roadmap.toSet().take(8).toList(growable: false);
  }

  String _sizingReadinessLevel({
    required int sizingAuditScore,
    required int hardGateCount,
    required int highRiskCount,
    required int sourceSheetCount,
  }) {
    if (hardGateCount == 0 && highRiskCount == 0 && sourceSheetCount > 0) {
      return sizingAuditScore >= 85
          ? 'Customer handoff ready'
          : 'Ready for stakeholder review';
    }
    if (sizingAuditScore >= 70 && sourceSheetCount > 0) {
      return 'Ready for requirements review';
    }
    if (sizingAuditScore >= 50) {
      return 'Needs validation before recommendation';
    }
    return 'Discovery inputs required';
  }

  String _sizingHandoffStatus(String readinessLevel) {
    return switch (readinessLevel) {
      'Customer handoff ready' => 'Customer-ready sizing workbook',
      'Ready for stakeholder review' => 'Stakeholder review candidate',
      'Ready for requirements review' => 'Requirements review workbook',
      'Needs validation before recommendation' => 'Validation required',
      _ => 'Discovery required',
    };
  }

  String _sizingDecisionPosture(
    int hardGateCount,
    int highRiskCount,
    int sourceSheetCount,
  ) {
    if (hardGateCount > 0 || highRiskCount > 0) {
      return 'Advisory only - close hard gates before BOM recommendation';
    }
    if (sourceSheetCount == 0) {
      return 'Advisory only - source evidence missing';
    }
    return 'Decision-ready after stakeholder review';
  }

  bool _hasSheet(List<WorkbookTable> tables, String name) {
    return tables.any(
      (table) => table.name.toLowerCase() == name.toLowerCase(),
    );
  }

  bool _containsText(List<WorkbookTable> tables, String text) {
    final needle = text.toLowerCase();
    for (final table in tables) {
      if (table.name.toLowerCase().contains(needle)) return true;
      for (final row in table.rows) {
        if (row.any((cell) => cell.toLowerCase().contains(needle))) {
          return true;
        }
      }
    }
    return false;
  }

  List<List<String>> _executiveSummaryRows(_SizingProfile profile) {
    return [
      [
        'Demand baseline',
        '${profile.usersText} users, ${profile.accessPointsText} APs, ${profile.switchesText} switches',
        'Use as directional planning input until inventory is validated.',
        'Confirm current and growth-state counts by site and closet.',
      ],
      [
        'PoE / wireless power',
        profile.requiresHighPowerAp
            ? '${profile.wifiGenerationText}; high-power AP signal'
            : profile.wifiGenerationText,
        profile.requiresHighPowerAp
            ? 'UPOE/UPOE+ and per-switch power budgets are hard gates.'
            : 'AP power class is still a final-design dependency.',
        'Collect AP model datasheets and per-IDF AP counts.',
      ],
      [
        'Access speed',
        profile.requiresMultiGig ? 'mGig required signal' : 'TBD',
        profile.requiresMultiGig
            ? 'Access switch candidates must satisfy both PoE and mGig.'
            : 'Do not finalize access models until AP/client port speeds are known.',
        'Validate 2.5G/5G/10G access needs against shortlisted switches.',
      ],
      [
        'WAN / security throughput',
        profile.wanText,
        profile.wanMbps == null
            ? 'WAN sizing is incomplete without bandwidth and service mix.'
            : 'Validate usable inspected throughput, not raw carrier rate.',
        'Capture security services, HA mode, critical apps, and secondary links.',
      ],
      [
        'Decision readiness',
        profile.decisionReadiness,
        'Workbook is ready for requirements review, not final BOM approval.',
        'Close all requirement gates and source-backed candidate checks.',
      ],
    ];
  }

  List<List<String>> _requirementRows(String content) {
    final rows = <List<String>>[];
    void add(String metric, String? value, String notes) {
      if (value == null || value.trim().isEmpty) return;
      rows.add([metric, value.trim(), notes]);
    }

    add(
      'Users / clients',
      _first(
        content,
        RegExp(
          r'(\d[\d,]*)\s+(?:users?|clients?|employees?|end users?)\b',
          caseSensitive: false,
        ),
      ),
      'Extracted from user/client count language.',
    );
    add(
      'Access points',
      _first(
        content,
        RegExp(r'(\d[\d,]*)\s+(?:aps?|access points?)\b', caseSensitive: false),
      ),
      'Validate model, Wi-Fi generation, port speed, and power draw.',
    );
    add(
      'Switches',
      _first(
        content,
        RegExp(
          r'(\d[\d,]*)\s+(?:switches?|access switches?|core switches?)\b',
          caseSensitive: false,
        ),
      ),
      'Validate stacking, uplinks, PoE, and lifecycle.',
    );
    add(
      'WAN speed',
      _first(
        content,
        RegExp(
          r'(\d+(?:\.\d+)?\s*(?:gbps|gigs?|g|mbps|m))\s*(?:wan|internet|circuit|link|links)?\b',
          caseSensitive: false,
        ),
      ),
      'Confirm committed rate, burst, HA links, and inspection throughput.',
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
      'Treat power class as a hard sizing constraint.',
    );
    add(
      'Growth',
      _first(
        content,
        RegExp(
          r'(\d+(?:\.\d+)?\s*%|\d+\s*(?:year|yr)s?)\s*(?:growth|headroom|forecast)?\b',
          caseSensitive: false,
        ),
      ),
      'Use as headroom for port, power, WAN, and licensing sizing.',
    );
    if (rows.isEmpty) {
      rows.addAll(const [
        [
          'Users / clients',
          'TBD',
          'Provide current and projected endpoint counts.',
        ],
        [
          'Access points',
          'TBD',
          'Provide AP model, quantity, Wi-Fi generation, and expected power draw.',
        ],
        [
          'WAN speed',
          'TBD',
          'Provide primary/secondary bandwidth and security service requirements.',
        ],
      ]);
    }
    return rows;
  }

  List<List<String>> _inputRows(List<List<String>> requirements) {
    return requirements
        .map((row) {
          final metric = row[0];
          final category = switch (metric.toLowerCase()) {
            String value when value.contains('wan') => 'WAN',
            String value
                when value.contains('poe') || value.contains('access') =>
              'Access',
            String value when value.contains('switch') => 'Switching',
            String value when value.contains('growth') => 'Planning',
            _ => 'Demand',
          };
          return [category, row[0], row[1], row[2]];
        })
        .toList(growable: false);
  }

  List<List<String>> _siteDistributionRows(
    _SizingProfile profile,
    ArtifactDocument document,
  ) {
    final rows = <List<String>>[];
    for (final table in document.tables) {
      if (table.rows.length < 2) continue;
      final header = table.rows.first
          .map((cell) => cell.toLowerCase())
          .toList();
      final siteIndex = _columnIndex(header, const [
        'site',
        'location',
        'campus',
        'branch',
      ]);
      final usersIndex = _columnIndex(header, const ['users', 'clients']);
      final apIndex = _columnIndex(header, const [
        'aps',
        'access points',
        'ap',
      ]);
      final wanIndex = _columnIndex(header, const [
        'wan',
        'internet',
        'circuit',
      ]);
      if (siteIndex == null && usersIndex == null && apIndex == null) {
        continue;
      }
      for (final row in table.rows.skip(1).take(24)) {
        String valueAt(int? index, String fallback) {
          if (index == null || index >= row.length) return fallback;
          final value = row[index].trim();
          return value.isEmpty ? fallback : value;
        }

        final site = valueAt(siteIndex, 'Site ${rows.length + 1}');
        final users = valueAt(usersIndex, 'TBD');
        final aps = valueAt(apIndex, 'TBD');
        final apCount = _SizingProfile._firstInt(aps);
        final watts = apCount == null
            ? 'TBD'
            : (apCount * profile.apWatts).toString();
        rows.add([
          site,
          users,
          aps,
          valueAt(wanIndex, 'TBD'),
          watts,
          'Validate closet placement, uplinks, power budget, and growth per site.',
        ]);
      }
    }
    if (rows.isNotEmpty) return rows;
    final totalWatts = profile.accessPoints == null
        ? 'TBD'
        : (profile.accessPoints! * profile.apWatts).toString();
    return [
      [
        'Portfolio-level estimate',
        profile.usersText,
        profile.accessPointsText,
        profile.wanText,
        totalWatts,
        'No site table detected; split by MDF/IDF before customer handoff.',
      ],
      [
        'MDF / core',
        'TBD',
        'TBD',
        profile.wanText,
        'TBD',
        'Capture aggregation, firewall, WAN, and redundancy requirements.',
      ],
      [
        'IDF / access closets',
        'TBD',
        'TBD',
        'N/A',
        'TBD',
        'Capture AP/user distribution and available power per closet.',
      ],
    ];
  }

  List<List<String>> _capacityRows(_SizingProfile profile) {
    final growth = profile.growthMultiplier;
    return [
      [
        'Users / clients',
        profile.usersText,
        profile.growthText,
        profile.users == null
            ? 'TBD'
            : (profile.users! * growth).ceil().toString(),
        'Use for endpoint density, authentication, licensing, and support assumptions.',
      ],
      [
        'Access points',
        profile.accessPointsText,
        profile.growthText,
        profile.accessPoints == null
            ? 'TBD'
            : (profile.accessPoints! * growth).ceil().toString(),
        'Validate AP model, Wi-Fi generation, mGig need, and power class.',
      ],
      [
        'Switches',
        profile.switchesText,
        profile.growthText,
        profile.switches == null
            ? 'TBD'
            : (profile.switches! * growth).ceil().toString(),
        'Validate stack size, uplinks, redundancy, and lifecycle status.',
      ],
      [
        'Access ports',
        profile.accessPoints == null
            ? 'TBD'
            : (profile.accessPoints! + ((profile.users ?? 0) / 6))
                  .ceil()
                  .toString(),
        profile.growthText,
        profile.accessPoints == null
            ? 'TBD'
            : ((profile.accessPoints! + ((profile.users ?? 0) / 6)) * growth)
                  .ceil()
                  .toString(),
        'Directional port count for APs plus wired/client support; replace with inventory before final design.',
      ],
    ];
  }

  List<List<String>> _poeRows(_SizingProfile profile) {
    final apCount = profile.accessPoints;
    final apLoad = apCount == null ? null : apCount * profile.apWatts;
    final minimumBudget = apLoad == null
        ? 'TBD'
        : (apLoad * profile.growthMultiplier * 1.2).ceil().toString();
    return [
      [
        'Wireless APs',
        profile.accessPointsText,
        profile.apWatts.toString(),
        apLoad?.toString() ?? 'TBD',
        minimumBudget,
        profile.requiresHighPowerAp
            ? 'Wi-Fi 7/UPOE signal detected; validate switch power budget and mGig ports.'
            : 'Validate AP power class and reserve budget before final switch selection.',
      ],
      [
        'Phones / cameras / IoT',
        'TBD',
        'TBD',
        'TBD',
        'TBD',
        'Add non-AP PoE loads before customer handoff.',
      ],
      [
        'Power reserve',
        'N/A',
        '20%',
        'N/A',
        minimumBudget,
        'Minimum budget includes growth and reserve; confirm per-IDF distribution.',
      ],
    ];
  }

  List<List<String>> _closetPowerRows(_SizingProfile profile) {
    final perSwitchAps =
        profile.accessPoints == null || profile.switches == null
        ? null
        : (profile.accessPoints! / profile.switches!).ceil();
    final perSwitchWatts = perSwitchAps == null
        ? null
        : (perSwitchAps * profile.apWatts * 1.2).ceil();
    final totalWatts = profile.accessPoints == null
        ? null
        : (profile.accessPoints! * profile.apWatts * profile.growthMultiplier)
              .ceil();
    return [
      [
        'Per access switch',
        perSwitchAps == null
            ? 'TBD AP distribution'
            : '$perSwitchAps APs at ${profile.apWatts}W each',
        '20% reserve',
        perSwitchWatts == null ? 'TBD' : '$perSwitchWatts W available PoE',
        'Check per-switch PoE budget, mGig ports, uplinks, and stack power sharing.',
      ],
      [
        'Per IDF closet',
        'TBD non-AP loads plus AP load',
        '20-30% reserve',
        'UPOE/UPOE+ where Wi-Fi 7/high-power APs are present',
        'Add phones, cameras, IoT, badge readers, and future APs.',
      ],
      [
        'Campus total',
        totalWatts == null ? 'TBD' : '$totalWatts W AP planning load',
        profile.growthText,
        'Power budget must exceed planned load with reserve',
        'Validate distribution across closets, not only aggregate total.',
      ],
      [
        'Power redundancy',
        profile.requiresHighAvailability ? 'Required' : 'Customer decision',
        'N+1 / redundant PSU where needed',
        'Match business outage tolerance',
        'Confirm generator/UPS/power shelf constraints before final BOM.',
      ],
    ];
  }

  List<List<String>> _wanRows(_SizingProfile profile) {
    final required = profile.wanMbps;
    final recommended = required == null
        ? 'TBD'
        : (required * profile.growthMultiplier * 1.25).ceil().toString();
    return [
      [
        'Internet / SD-WAN edge',
        required?.round().toString() ?? profile.wanText,
        profile.growthText,
        recommended,
        'Size against inspected throughput and enabled security services, not only carrier line rate.',
      ],
      [
        'Failover / secondary WAN',
        'TBD',
        profile.growthText,
        'TBD',
        'Confirm active/active or active/standby behavior and minimum outage tolerance.',
      ],
      [
        'Cloud / SaaS critical apps',
        'TBD',
        profile.growthText,
        'TBD',
        'Add app-specific requirements for voice, video, backups, and security inspection.',
      ],
    ];
  }

  List<List<String>> _licensingSupportRows(_SizingProfile profile) {
    return [
      [
        'Switching',
        'Access/core feature set, stacking, telemetry, automation',
        'Confirm DNA / Network Advantage needs and support coverage.',
        'Correct hardware but wrong license/support tier.',
        'Needs validation',
      ],
      [
        'Wireless',
        'AP count, controller/cloud management, assurance',
        'Map AP generation and management plane to license requirements.',
        'APs cannot be onboarded or monitored as expected.',
        profile.accessPoints == null ? 'Needs AP count' : 'Review',
      ],
      [
        'WAN / security',
        'Throughput, SD-WAN, firewall inspection, advanced security services',
        'Validate security subscriptions and throughput tiers.',
        'Platform sized to line rate but not licensed for services.',
        profile.wanMbps == null ? 'Needs WAN input' : 'Review',
      ],
      [
        'Lifecycle support',
        'LDOS/EoX/current portfolio fit',
        'Check official lifecycle/support dates and replacement suitability.',
        'Recommendation lands on stale or unsupported model.',
        'Needs official source',
      ],
      [
        'Operations',
        'Monitoring, support workflows, admin ownership',
        'Confirm TAC/support ownership, dashboard access, and escalation model.',
        'Customer cannot operate the recommended architecture.',
        'Customer decision',
      ],
    ];
  }

  List<List<String>> _sizingAuditRows({
    required _SizingProfile profile,
    required List<List<String>> requirementRows,
    required List<List<String>> assumptionRows,
    required int sourceSheetCount,
  }) {
    List<String> row({
      required String area,
      required String signal,
      required bool ready,
      required int score,
      required String action,
    }) {
      return [
        area,
        signal,
        ready ? 'Ready' : 'Needs validation',
        '$score',
        action,
      ];
    }

    final hasCoreDemand =
        profile.users != null &&
        profile.accessPoints != null &&
        profile.switches != null;
    final hasWan = profile.wanMbps != null;
    final hasGrowth = profile.growthPercent != null;
    final hasPowerSignal =
        profile.requiresHighPowerAp ||
        _requirementValue(requirementRows, 'PoE').isNotEmpty;
    final hasSourceEvidence = sourceSheetCount > 0;
    return [
      row(
        area: 'Core demand',
        signal:
            '${profile.usersText} users / ${profile.accessPointsText} APs / ${profile.switchesText} switches',
        ready: hasCoreDemand,
        score: hasCoreDemand ? 100 : 45,
        action: hasCoreDemand
            ? 'Validate counts by site and closet.'
            : 'Capture users, APs, and switch counts before sizing.',
      ),
      row(
        area: 'Power and access',
        signal: profile.requiresHighPowerAp
            ? '${profile.wifiGenerationText}; UPOE/mGig hard gate'
            : profile.wifiGenerationText,
        ready: hasPowerSignal,
        score: profile.requiresHighPowerAp
            ? 90
            : hasPowerSignal
            ? 75
            : 35,
        action: profile.requiresHighPowerAp
            ? 'Validate per-switch UPOE budget, AP draw, mGig ports, and uplinks.'
            : 'Confirm AP generation, PoE class, and access speed requirements.',
      ),
      row(
        area: 'WAN / security',
        signal: profile.wanText,
        ready: hasWan,
        score: hasWan ? 80 : 30,
        action: hasWan
            ? 'Confirm inspected throughput with enabled security services.'
            : 'Capture WAN bandwidth, security services, and failover behavior.',
      ),
      row(
        area: 'Growth and HA',
        signal:
            '${profile.growthText}; ${profile.requiresHighAvailability ? 'HA signal captured' : 'HA decision missing'}',
        ready: hasGrowth && profile.requiresHighAvailability,
        score: hasGrowth && profile.requiresHighAvailability
            ? 90
            : hasGrowth || profile.requiresHighAvailability
            ? 65
            : 35,
        action:
            'Confirm growth horizon, redundancy tier, power redundancy, and outage tolerance.',
      ),
      row(
        area: 'Lifecycle / support',
        signal: 'LDOS/EoX/current portfolio validation required',
        ready: false,
        score: 45,
        action:
            'Use official lifecycle sources; treat EoX replacement PID as a migration hint only.',
      ),
      row(
        area: 'Assumptions',
        signal: assumptionRows.isEmpty
            ? 'No explicit assumptions'
            : '${assumptionRows.length} assumption${assumptionRows.length == 1 ? '' : 's'} listed',
        ready: assumptionRows.isNotEmpty,
        score: assumptionRows.isNotEmpty ? 85 : 35,
        action: assumptionRows.isNotEmpty
            ? 'Review each assumption with the customer owner.'
            : 'Document scope, units, source freshness, and unknowns.',
      ),
      row(
        area: 'Source evidence',
        signal: hasSourceEvidence
            ? '$sourceSheetCount source sheet${sourceSheetCount == 1 ? '' : 's'} attached'
            : 'No source sheets attached',
        ready: hasSourceEvidence,
        score: hasSourceEvidence ? 80 : 25,
        action: hasSourceEvidence
            ? 'Confirm source freshness and authority before final recommendation.'
            : 'Attach inventory, datasheets, lifecycle, and customer source data.',
      ),
      row(
        area: 'Decision readiness',
        signal: profile.decisionReadiness,
        ready: profile.decisionReadiness.startsWith('High'),
        score: profile.decisionReadiness.startsWith('High')
            ? 90
            : profile.decisionReadiness.startsWith('Medium')
            ? 65
            : 35,
        action:
            'Do not produce final BOM until hard gates and source evidence are closed.',
      ),
    ];
  }

  List<List<String>> _haGrowthRows(_SizingProfile profile) {
    return [
      [
        'Growth headroom',
        profile.growthText,
        profile.growthPercent == null ? 'Needs input' : 'Captured',
        'Apply to users, APs, ports, power, WAN, licensing, and support contracts.',
      ],
      [
        'High availability',
        'Dual WAN, redundant core/firewall, power, and stack/chassis strategy',
        'Needs validation',
        'Confirm outage tolerance and which sites require warm spare or active/active design.',
      ],
      [
        'Lifecycle risk',
        'Validate LDOS/EoX and current portfolio fit before final model choice',
        'Needs validation',
        'EoX replacement PID is a migration clue only; verify against Wi-Fi 7, UPOE, mGig, and lifecycle needs.',
      ],
      [
        'Licensing',
        'Map selected architecture to licensing tiers and support coverage',
        'Needs validation',
        'Include DNA/Meraki/security licensing where applicable.',
      ],
    ];
  }

  List<List<String>> _implementationSequenceRows(_SizingProfile profile) {
    return [
      [
        '1. Requirements lock',
        'Confirm users, APs, sites, WAN, growth, HA, and business constraints.',
        'Customer data and site inventory available.',
        'All TBD requirements either captured or explicitly assumed.',
      ],
      [
        '2. Candidate shortlist',
        'Filter products against PoE, mGig, uplinks, lifecycle, licensing, and HA gates.',
        'Requirement Gates sheet reviewed.',
        'Every candidate has pass/fail notes and source gaps.',
      ],
      [
        '3. Site/closet validation',
        'Map AP and user loads to MDF/IDF closets and power domains.',
        profile.accessPoints == null
            ? 'AP count and site distribution collected.'
            : '${profile.accessPointsText} APs validated by location.',
        'Per-closet power, port, uplink, and redundancy needs are known.',
      ],
      [
        '4. Commercial package',
        'Prepare BOM, licensing, support, and implementation sequence.',
        'Candidate shortlist and assumptions approved.',
        'Customer-ready recommendation package with caveats.',
      ],
      [
        '5. Verification',
        'Validate commands/checks, diagrams, lifecycle evidence, and handoff docs.',
        'Artifacts generated and reviewed.',
        'Final workbook is backed by current evidence and known unknowns.',
      ],
    ];
  }

  List<List<String>> _riskRows(_SizingProfile profile) {
    return [
      [
        'Wi-Fi 7 APs exceed switch power budget',
        profile.requiresHighPowerAp
            ? 'High-power AP signal detected'
            : 'AP power unknown',
        'Require UPOE/UPOE+ validation and per-switch power budget check.',
        profile.requiresHighPowerAp ? 'High' : 'Medium',
        'Network architect',
      ],
      [
        'Access ports lack required mGig speed',
        profile.requiresMultiGig
            ? 'mGig signal detected'
            : 'AP generation unknown',
        'Reject candidates without sourced mGig capability where required.',
        profile.requiresMultiGig ? 'High' : 'Medium',
        'Network architect',
      ],
      [
        'WAN platform undersized with services enabled',
        profile.wanMbps == null ? 'WAN input missing' : profile.wanText,
        'Validate inspected throughput with security/SD-WAN services enabled.',
        'High',
        'Security / WAN owner',
      ],
      [
        'Lifecycle or support mismatch',
        'LDOS/EoX not yet sourced',
        'Validate official lifecycle dates and current portfolio alternatives.',
        'Medium',
        'Account team',
      ],
      [
        'False precision from incomplete customer data',
        'TBD rows remain in workbook',
        'Keep assumptions visible and block final BOM until open gates close.',
        'Medium',
        'SE / customer stakeholder',
      ],
    ];
  }

  List<List<String>> _requirementGateRows(_SizingProfile profile) {
    return [
      [
        'Wi-Fi generation',
        profile.wifiGenerationText,
        'AP generation and power class are known before access switch selection.',
        profile.requiresHighPowerAp
            ? 'High-power AP signal detected'
            : 'Needs input',
        profile.requiresHighPowerAp
            ? 'Require UPOE/UPOE+ and likely multigig access validation.'
            : 'Collect AP model/generation before final sizing.',
      ],
      [
        'Access port speed',
        profile.requiresMultiGig ? 'mGig / 2.5G / 5G / 10G signal' : 'TBD',
        'Access switch ports meet AP/client link-speed requirements.',
        profile.requiresMultiGig ? 'mGig validation required' : 'Needs input',
        'Reject candidates that only satisfy PoE but not access port speed.',
      ],
      [
        'Power budget',
        profile.requiresHighPowerAp ? 'UPOE / 802.3bt / 60W+' : 'TBD',
        'Per-switch and per-closet power budgets exceed planned load plus reserve.',
        profile.accessPoints == null
            ? 'Needs AP count'
            : 'Needs datasheet validation',
        'Undersized PoE budgets can invalidate otherwise acceptable switches.',
      ],
      [
        'WAN and security throughput',
        profile.wanText,
        'Firewall/SD-WAN throughput is validated with enabled services.',
        profile.wanMbps == null
            ? 'Needs WAN input'
            : 'Needs platform validation',
        'Do not use raw carrier line rate as inspected throughput.',
      ],
      [
        'High availability',
        profile.requiresHighAvailability ? 'HA signal detected' : 'TBD',
        'Redundancy tier matches outage tolerance and site criticality.',
        profile.requiresHighAvailability
            ? 'HA design required'
            : 'Needs customer decision',
        'Impacts warm spares, dual WAN, redundant core, power, and licensing.',
      ],
      [
        'Lifecycle and support',
        'LDOS/EoX/current portfolio',
        'Lifecycle dates and current portfolio fit are checked from official/current sources.',
        'Needs validation',
        'Treat EoX replacement PID as migration hint only, not final model selection.',
      ],
    ];
  }

  List<List<String>> _candidateValidationRows(
    _SizingProfile profile,
    String content,
  ) {
    final candidates = _candidateNames(content);
    final rows = <List<String>>[
      [
        'Access switch shortlist',
        'PoE/UPOE budget, mGig ports, uplinks, stacking/HA, lifecycle',
        'Wi-Fi 6E/7 and high-density access can fail on power or port-speed even when port count looks sufficient.',
        'No UPOE/802.3bt, insufficient power budget, no required mGig, stale lifecycle.',
        'Needs validation',
      ],
      [
        'Wireless/AP plan',
        'AP count, Wi-Fi generation, power draw, client density, mounting/site constraints',
        'AP requirements drive access switching, PoE reserve, uplinks, and licensing.',
        'AP model/generation/power draw unknown.',
        profile.accessPoints == null ? 'Needs input' : 'Review',
      ],
      [
        'WAN/security edge',
        'Throughput with services enabled, HA mode, circuit mix, SaaS/cloud traffic',
        'Security inspection and SD-WAN features reduce usable throughput.',
        'Only raw WAN speed is known.',
        profile.wanMbps == null ? 'Needs input' : 'Review',
      ],
    ];
    for (final candidate in candidates.take(8)) {
      rows.add([
        candidate,
        'Datasheet capability, lifecycle, licensing, and requirement fit',
        'Candidate must be current and satisfy the actual requirement gates.',
        profile.requiresHighPowerAp
            ? 'Fails Wi-Fi 7/UPOE/mGig/power budget gates.'
            : 'Fails current capability, lifecycle, or licensing gates.',
        'Unverified',
      ]);
    }
    return rows;
  }

  List<List<String>> _recommendationRows(ArtifactDocument document) {
    final rows = <List<String>>[];
    for (final section in document.sections) {
      final sectionName = section.title.toLowerCase();
      if (!sectionName.contains('recommend') &&
          !sectionName.contains('sizing') &&
          !sectionName.contains('architecture')) {
        continue;
      }
      for (final bullet in section.bullets) {
        rows.add([
          section.title,
          bullet,
          'Derived from assistant recommendation section.',
          'Review',
        ]);
      }
      if (section.bullets.isEmpty && section.body.trim().isNotEmpty) {
        rows.add([
          section.title,
          _shorten(section.body.trim(), 180),
          'Derived from assistant recommendation section.',
          'Review',
        ]);
      }
    }
    if (rows.isEmpty) {
      rows.addAll(const [
        [
          'Access',
          'Validate PoE/UPOE and multigig requirements before selecting access switches.',
          'Prevents undersized switch recommendations for Wi-Fi 6E/7 deployments.',
          'Review',
        ],
        [
          'WAN',
          'Size WAN/security throughput against enabled services and HA design.',
          'Nominal link speed is not equal to inspected throughput.',
          'Review',
        ],
      ]);
    }
    return rows.take(24).toList(growable: false);
  }

  List<List<String>> _assumptionRows(
    ArtifactDocument document,
    String content,
  ) {
    final assumptions = document.assumptions.isNotEmpty
        ? document.assumptions
        : _bulletsAfter(content, 'assumptions');
    if (assumptions.isEmpty) {
      return const [
        [
          'Lifecycle data and current portfolio fit must be verified before final model selection.',
          'Avoids treating migration hints as final recommendations.',
        ],
        [
          'Power draw, WAN service mix, and growth targets are placeholders until customer data is confirmed.',
          'Prevents false precision in sizing outputs.',
        ],
      ];
    }
    return assumptions
        .take(20)
        .map((assumption) => [assumption, 'Validate before final design.'])
        .toList(growable: false);
  }

  List<List<String>> _decisionRows(_SizingProfile profile) {
    return [
      [
        'Access switching',
        profile.requiresHighPowerAp
            ? 'Shortlist mGig UPOE/UPOE+ capable access switches.'
            : 'Shortlist access switches after AP power and port speed are confirmed.',
        'AP model, power draw, mGig need, uplink speed, stack/HA, lifecycle.',
        'Medium',
      ],
      [
        'Wireless',
        profile.accessPoints == null
            ? 'Collect AP count and Wi-Fi generation before sizing.'
            : 'Plan around ${profile.accessPointsText} APs with growth headroom.',
        'AP model, density, channel plan, PoE class, expected client mix.',
        profile.accessPoints == null ? 'Low' : 'Medium',
      ],
      [
        'WAN / security edge',
        profile.wanMbps == null
            ? 'Collect primary/secondary WAN and inspection requirements.'
            : 'Validate at least ${profile.wanText} plus security-service headroom.',
        'Firewall/SD-WAN throughput with services enabled, HA mode, circuits.',
        profile.wanMbps == null ? 'Low' : 'Medium',
      ],
      [
        'Customer follow-up',
        'Use this workbook as a requirements and validation artifact, not final bill of materials.',
        'Current datasheets, lifecycle, licensing, site inventory, and customer constraints.',
        'High',
      ],
    ];
  }

  List<String> _candidateNames(String content) {
    final matches = RegExp(
      r'\b(?:C9\d{3}[A-Z0-9-]*|MS\d{3}[A-Z0-9-]*|MR\d{2,3}[A-Z0-9-]*|CW\d{4}[A-Z0-9-]*|MX\d{2,4}[A-Z0-9-]*|AIR-[A-Z0-9-]+)\b',
      caseSensitive: false,
    ).allMatches(content);
    final seen = <String>{};
    final names = <String>[];
    for (final match in matches) {
      final value = (match.group(0) ?? '').toUpperCase();
      if (seen.add(value)) names.add(value);
    }
    return names;
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

  int? _columnIndex(List<String> header, List<String> candidates) {
    for (var i = 0; i < header.length; i++) {
      final cell = header[i];
      if (candidates.any((candidate) => cell.contains(candidate))) return i;
    }
    return null;
  }

  List<String> _bulletsAfter(String content, String headingName) {
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
    return block
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('- ') || line.startsWith('* '))
        .map((line) => line.substring(2).trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
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

class _SizingProfile {
  final int? users;
  final int? accessPoints;
  final int? switches;
  final double? wanMbps;
  final double? growthPercent;
  final bool requiresHighPowerAp;
  final bool requiresMultiGig;
  final bool requiresHighAvailability;
  final String usersText;
  final String accessPointsText;
  final String switchesText;
  final String wanText;
  final String growthText;
  final String wifiGenerationText;

  const _SizingProfile({
    required this.users,
    required this.accessPoints,
    required this.switches,
    required this.wanMbps,
    required this.growthPercent,
    required this.requiresHighPowerAp,
    required this.requiresMultiGig,
    required this.requiresHighAvailability,
    required this.usersText,
    required this.accessPointsText,
    required this.switchesText,
    required this.wanText,
    required this.growthText,
    required this.wifiGenerationText,
  });

  double get growthMultiplier => 1 + ((growthPercent ?? 25) / 100);

  int get apWatts => requiresHighPowerAp ? 60 : 30;

  String get decisionReadiness {
    final captured = [
      users != null,
      accessPoints != null,
      switches != null,
      wanMbps != null,
      growthPercent != null,
      requiresHighPowerAp || wifiGenerationText != 'TBD',
      requiresHighAvailability,
    ].where((value) => value).length;
    if (captured >= 6) return 'High - most sizing signals captured';
    if (captured >= 4) return 'Medium - enough for shortlist validation';
    return 'Low - discovery inputs still required';
  }

  factory _SizingProfile.fromRequirements(
    List<List<String>> requirements,
    String content,
  ) {
    String valueFor(String metric) {
      final normalized = metric.toLowerCase();
      for (final row in requirements) {
        if (row.length < 2) continue;
        if (row.first.toLowerCase().contains(normalized)) return row[1];
      }
      return 'TBD';
    }

    final usersText = valueFor('users');
    final apText = valueFor('access points');
    final switchesText = valueFor('switches');
    final wanText = valueFor('wan');
    final growthText = valueFor('growth');
    final highPower = RegExp(
      r'\b(wi-?fi\s*7|upoe\+?|802\.3bt|class\s*6|class\s*8|60w|90w)\b',
      caseSensitive: false,
    ).hasMatch(content);
    final multiGig = RegExp(
      r'\b(multigig|mGig|2\.5g|5g|10g(?:base)?(?: access)?|10gig)\b',
      caseSensitive: false,
    ).hasMatch(content);
    final highAvailability = RegExp(
      r'\b(ha|high availability|redundan\w+|dual wan|warm spare|active/active|active-active|failover)\b',
      caseSensitive: false,
    ).hasMatch(content);
    final wifiGeneration =
        RegExp(
          r'\b(wi-?fi\s*(?:6e|7)|802\.11(?:ax|be))\b',
          caseSensitive: false,
        ).firstMatch(content)?.group(0) ??
        (highPower ? 'Wi-Fi 7 / high-power AP signal' : 'TBD');
    return _SizingProfile(
      users: _firstInt(usersText),
      accessPoints: _firstInt(apText),
      switches: _firstInt(switchesText),
      wanMbps: _wanMbps(wanText),
      growthPercent: _growthPercent(growthText),
      requiresHighPowerAp: highPower,
      requiresMultiGig: multiGig || highPower,
      requiresHighAvailability: highAvailability,
      usersText: usersText,
      accessPointsText: apText,
      switchesText: switchesText,
      wanText: wanText,
      growthText: growthText == 'TBD' ? '25% default' : growthText,
      wifiGenerationText: wifiGeneration,
    );
  }

  static int? _firstInt(String value) {
    final match = RegExp(r'\d[\d,]*').firstMatch(value);
    if (match == null) return null;
    return int.tryParse((match.group(0) ?? '').replaceAll(',', ''));
  }

  static double? _wanMbps(String value) {
    final match = RegExp(
      r'(\d+(?:\.\d+)?)\s*(gbps|gigs?|g|mbps|m)?',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return null;
    final number = double.tryParse(match.group(1) ?? '');
    if (number == null) return null;
    final unit = (match.group(2) ?? 'mbps').toLowerCase();
    if (unit == 'g' || unit.startsWith('gig') || unit == 'gbps') {
      return number * 1000;
    }
    return number;
  }

  static double? _growthPercent(String value) {
    final percent = RegExp(r'(\d+(?:\.\d+)?)\s*%').firstMatch(value);
    if (percent != null) return double.tryParse(percent.group(1) ?? '');
    return null;
  }
}
