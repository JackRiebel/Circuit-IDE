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
    final fullContent = '$prompt\n$content';
    final requirementRows = _requirementRows(fullContent);
    final profile = _ComparisonProfile.from(
      candidates: candidates,
      requirements: requirementRows,
      content: fullContent,
    );
    final customerHandoffRows = _comparisonCustomerHandoffRows(profile);
    return [
      WorkbookTable(
        name: 'Executive Decision',
        rows: [
          const [
            'Decision Signal',
            'Current Answer',
            'Why It Matters',
            'Next Action',
          ],
          ..._executiveDecisionRows(profile),
        ],
      ),
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
          ..._decisionRows(profile),
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
          ..._gateRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'Hard Gate Evaluation',
        rows: [
          const [
            'Product / Model',
            'Hard gate',
            'Detected requirement',
            'Gate status',
            'Evidence / rejection rule',
          ],
          ..._hardGateRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'Must-Have Compliance',
        rows: [
          const [
            'Product / Model',
            'Passed gates',
            'At-risk gates',
            'Needs validation',
            'Compliance Score',
            'Recommendation Posture',
            'Next Evidence',
          ],
          ..._mustHaveComplianceRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'Source Confidence',
        rows: [
          const [
            'Product / Model',
            'Capability Evidence',
            'Lifecycle Evidence',
            'Commercial Evidence',
            'Confidence',
          ],
          ..._sourceConfidenceRows(profile),
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
        name: 'Migration Suitability',
        rows: [
          const [
            'Product / Model',
            'Role in Migration',
            'Accept If',
            'Reject If',
            'Current Suitability',
          ],
          ..._migrationSuitabilityRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'Lifecycle Runway',
        rows: [
          const [
            'Product / Model',
            'Lifecycle Signal',
            'Support Runway Question',
            'Customer Risk',
            'Validation Owner',
          ],
          ..._lifecycleRunwayRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'Alternatives',
        rows: [
          const [
            'Alternative',
            'Reason to consider',
            'Reason to reject / caveat',
            'What would change the decision',
          ],
          ..._alternativeRows(document, content),
          ..._rejectedAlternativeRows(candidates),
        ],
      ),
      WorkbookTable(
        name: 'Replacement Cautions',
        rows: [
          const ['Topic', 'Rule', 'Why it matters', 'Required validation'],
          ..._replacementCautionRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'Implementation Impact',
        rows: [
          const [
            'Decision Area',
            'Operational Impact',
            'Deployment Dependency',
            'Risk If Wrong',
          ],
          ..._implementationImpactRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'Customer Talking Points',
        rows: [
          const ['Topic', 'Customer-facing language', 'Do not overclaim'],
          ..._talkingPointRows(profile),
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
        name: 'Evidence Policy',
        rows: [
          const ['Policy', 'Current Signal', 'Owner Action'],
          ..._comparisonEvidencePolicyRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'Visual QA',
        rows: [
          const ['Check', 'Why It Matters', 'Status'],
          ..._comparisonVisualVerificationRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'Publishing Readiness',
        rows: [
          const ['Gate', 'Requirement', 'Status'],
          ..._comparisonPublishingRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'Customer Handoff Matrix',
        rows: [
          const ['Gate', 'Signal', 'Status', 'Owner Action', 'Ready'],
          ...customerHandoffRows,
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

  Map<String, Object?> metadataFor(List<WorkbookTable> tables) {
    final executiveRows = _rowsFor(
      tables,
      'Executive Decision',
    ).skip(1).toList(growable: false);
    final comparisonRows = _rowsFor(
      tables,
      'Comparison Matrix',
    ).skip(1).toList(growable: false);
    final requirementRows = _rowsFor(
      tables,
      'Requirements',
    ).skip(1).toList(growable: false);
    final hardGateRows = _rowsFor(
      tables,
      'Hard Gate Evaluation',
    ).skip(1).toList(growable: false);
    final mustHaveRows = _rowsFor(
      tables,
      'Must-Have Compliance',
    ).skip(1).toList(growable: false);
    final sourceConfidenceRows = _rowsFor(
      tables,
      'Source Confidence',
    ).skip(1).toList(growable: false);
    final shortlistRows = _rowsFor(
      tables,
      'Scored Shortlist',
    ).skip(1).toList(growable: false);
    final validationRows = _rowsFor(
      tables,
      'Validation Checklist',
    ).skip(1).toList(growable: false);
    final evidencePolicyRows = _rowsFor(
      tables,
      'Evidence Policy',
    ).skip(1).toList(growable: false);
    final visualQaRows = _rowsFor(
      tables,
      'Visual QA',
    ).skip(1).toList(growable: false);
    final publishingRows = _rowsFor(
      tables,
      'Publishing Readiness',
    ).skip(1).toList(growable: false);
    final customerHandoffRows = _rowsFor(
      tables,
      'Customer Handoff Matrix',
    ).skip(1).toList(growable: false);
    final customerHandoffReadyCount = _comparisonCustomerHandoffReadyCount(
      customerHandoffRows,
    );
    final sourceSheetCount = tables
        .where((table) => table.name.toLowerCase().startsWith('source '))
        .length;
    final atRiskGateCount = hardGateRows.where((row) {
      return row.any((cell) => cell.toLowerCase().contains('at risk'));
    }).length;
    final needsValidationGateCount = hardGateRows.where((row) {
      return row.any((cell) => cell.toLowerCase().contains('needs validation'));
    }).length;
    final hasSourceEvidence =
        sourceSheetCount > 0 ||
        sourceConfidenceRows.any((row) {
          return row.any((cell) {
            final normalized = cell.toLowerCase();
            return normalized.contains('source') ||
                normalized.contains('datasheet') ||
                normalized.contains('portfolio');
          });
        });
    final readinessLevel = _comparisonReadinessLevel(
      candidateCount: comparisonRows.length,
      atRiskGateCount: atRiskGateCount,
      needsValidationGateCount: needsValidationGateCount,
      hasSourceEvidence: hasSourceEvidence,
    );
    return {
      'artifact': 'product_comparison_matrix',
      'workbookKind': 'product_comparison',
      'sheetCount': tables.length,
      'sourceSheetCount': sourceSheetCount,
      'candidateCount': comparisonRows.length,
      'requirementCount': requirementRows.length,
      'hardGateEvaluationCount': hardGateRows.length,
      'atRiskGateCount': atRiskGateCount,
      'needsValidationGateCount': needsValidationGateCount,
      'mustHaveComplianceCount': mustHaveRows.length,
      'mustHaveEligibleCandidateCount': _mustHavePostureCount(
        mustHaveRows,
        'Eligible',
      ),
      'mustHaveBlockedCandidateCount': _mustHavePostureCount(
        mustHaveRows,
        'Blocked',
      ),
      'mustHaveNeedsValidationCandidateCount': _mustHavePostureCount(
        mustHaveRows,
        'Needs validation',
      ),
      'mustHaveComplianceSummary': _mustHaveComplianceSummary(mustHaveRows),
      'sourceConfidenceCount': sourceConfidenceRows.length,
      'shortlistCount': shortlistRows.length,
      'validationCheckCount': validationRows.length,
      'comparisonReadinessLevel': readinessLevel,
      'comparisonHandoffStatus': _comparisonHandoffStatus(readinessLevel),
      'comparisonDecisionPosture':
          'Advisory only - validate hard gates and source evidence before final recommendation',
      'recommendedCandidate': _executiveValue(
        executiveRows,
        'Recommended primary candidate',
      ),
      'runnerUpCandidate': _executiveValue(executiveRows, 'Runner-up'),
      'requirementPressure': _executiveValue(
        executiveRows,
        'Hard-gate pressure',
      ),
      'evidenceQuality': _executiveValue(executiveRows, 'Evidence quality'),
      'replacementCaveat': _executiveValue(executiveRows, 'Replacement caveat'),
      'comparisonQualityManifestVersion': '1.0',
      'comparisonEvidencePolicy': _stringRows(evidencePolicyRows),
      'comparisonEvidencePolicyCount': evidencePolicyRows.length,
      'comparisonVisualVerificationChecklist': _stringRows(visualQaRows),
      'comparisonVisualVerificationChecklistCount': visualQaRows.length,
      'comparisonPublishingMetadata': _stringRows(publishingRows),
      'comparisonPublishingMetadataCount': publishingRows.length,
      'comparisonCustomerHandoffMatrix': _comparisonCustomerHandoffMetadata(
        customerHandoffRows,
      ),
      'comparisonCustomerHandoffGateCount': customerHandoffRows.length,
      'comparisonCustomerHandoffReadyCount': customerHandoffReadyCount,
      'hasComparisonQualityManifest': true,
      'hasMustHaveComplianceScorecard': mustHaveRows.isNotEmpty,
      'hasComparisonEvidencePolicy': evidencePolicyRows.isNotEmpty,
      'hasComparisonVisualVerificationChecklist': visualQaRows.isNotEmpty,
      'hasComparisonPublishingMetadata': publishingRows.isNotEmpty,
      'hasComparisonCustomerHandoffMatrix': customerHandoffRows.isNotEmpty,
      'hasSourceEvidence': hasSourceEvidence,
    };
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

  List<List<String>> _executiveDecisionRows(_ComparisonProfile profile) {
    final best = profile.best;
    final runnerUp = profile.runnerUp;
    return [
      [
        'Recommended primary candidate',
        best == null
            ? 'No candidate with enough structured facts yet'
            : best.product,
        'The top candidate anchors the shortlist, but still needs source-backed hard-gate validation.',
        best == null
            ? 'Add candidate products and capability facts.'
            : 'Validate ${best.product} against hard gates, lifecycle, licensing, and customer constraints.',
      ],
      [
        'Runner-up / fallback',
        runnerUp == null ? 'No structured runner-up yet' : runnerUp.product,
        'Fallback path protects the recommendation if the top candidate fails power, port, lifecycle, or commercial gates.',
        runnerUp == null
            ? 'Add at least one credible alternative.'
            : 'Document why ${runnerUp.product} is lower-ranked or when it should supersede the primary choice.',
      ],
      [
        'Hard-gate pressure',
        profile.requirementPressure,
        'Wi-Fi 7, UPOE, mGig, HA, and lifecycle signals can disqualify products even when fit score looks good.',
        'Close every hard-gate row before presenting a final customer recommendation.',
      ],
      [
        'Evidence quality',
        profile.evidenceQuality,
        'Enterprise recommendations need official/current capability and lifecycle evidence.',
        'Attach datasheets, lifecycle source, checked date, and customer requirement evidence.',
      ],
      [
        'Replacement caveat',
        profile.hasMigrationSignal
            ? 'Migration/replacement language detected'
            : 'No explicit migration PID signal',
        'EoX replacement PID is a migration clue, not final product selection.',
        'Compare hinted models against current portfolio candidates and current requirements.',
      ],
    ];
  }

  List<List<String>> _decisionRows(_ComparisonProfile profile) {
    final ranked = profile.ranked;
    final best = profile.best;
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
      [
        'Source confidence',
        profile.evidenceQuality,
        'Capability, lifecycle, and commercial facts should be source-backed before customer handoff',
        profile.hasSourceEvidence ? 'Medium' : 'Low',
      ],
    ];
  }

  List<List<String>> _gateRows(_ComparisonProfile profile) {
    String detected(String requirement) {
      for (final row in profile.requirements) {
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
      [
        'Licensing / operations',
        profile.hasOperationalSignal
            ? 'Operational model signal detected'
            : 'TBD',
        'Management model, licensing, support, and operating standard fit the customer',
        'Reject candidates that require an operating model or licensing tier the customer will not adopt',
      ],
    ];
  }

  List<List<String>> _hardGateRows(_ComparisonProfile profile) {
    final rows = <List<String>>[];
    final targetCandidates = profile.candidates.isEmpty
        ? const [
            _ComparisonCandidate(
              product: 'TBD',
              capabilities: 'Add sourced capability facts.',
              constraints: 'Validate hard requirements.',
              lifecycle: 'Needs lifecycle validation',
              fitScore: 'TBD',
              recommendation: 'Review',
            ),
          ]
        : profile.candidates.take(12);
    for (final candidate in targetCandidates) {
      rows.addAll([
        [
          candidate.product,
          'Power / UPOE',
          profile.requiresHighPower ? 'Wi-Fi 7 / UPOE / 802.3bt signal' : 'TBD',
          profile.requiresHighPower
              ? candidate.supportsHighPower
                    ? 'Review pass'
                    : 'At risk'
              : 'Needs input',
          profile.requiresHighPower
              ? 'Reject if sourced data does not prove required UPOE/UPOE+ power budget.'
              : 'Collect AP power class before final recommendation.',
        ],
        [
          candidate.product,
          'Multigig access',
          profile.requiresMultiGig ? 'mGig / high-speed access signal' : 'TBD',
          profile.requiresMultiGig
              ? candidate.supportsMultiGig
                    ? 'Review pass'
                    : 'At risk'
              : 'Needs input',
          profile.requiresMultiGig
              ? 'Reject if AP/client access speed requires 2.5/5/10G and candidate lacks it.'
              : 'Collect AP access speed before final recommendation.',
        ],
        [
          candidate.product,
          'Lifecycle runway',
          profile.hasLifecycleConcern
              ? 'Lifecycle/EoX concern detected'
              : 'TBD',
          candidate.lifecycleNeedsValidation
              ? 'Needs validation'
              : 'Review pass',
          'Reject stale suggestedMigrationPid or migration candidates when newer current models better fit requirements.',
        ],
        [
          candidate.product,
          'Operational / licensing fit',
          profile.hasOperationalSignal
              ? 'Management/licensing/support signal'
              : 'TBD',
          candidate.hasOperationalEvidence ? 'Review pass' : 'Needs validation',
          'Reject if required license, support tier, or operating model conflicts with customer standards.',
        ],
      ]);
    }
    return rows;
  }

  List<List<String>> _mustHaveComplianceRows(_ComparisonProfile profile) {
    final rowsByProduct = <String, List<List<String>>>{};
    for (final row in _hardGateRows(profile)) {
      if (row.isEmpty) continue;
      rowsByProduct.putIfAbsent(row.first, () => <List<String>>[]).add(row);
    }
    return rowsByProduct.entries
        .map((entry) {
          final rows = entry.value;
          final passed = rows.where(_isGatePass).length;
          final atRisk = rows.where(_isGateAtRisk).length;
          final needsValidation = rows.where(_isGateNeedsValidation).length;
          final total = rows.length;
          final score = total == 0 ? 0 : ((passed / total) * 100).round();
          return [
            entry.key,
            '$passed of $total',
            '$atRisk',
            '$needsValidation',
            '$score%',
            _mustHavePosture(
              atRiskGateCount: atRisk,
              needsValidationGateCount: needsValidation,
            ),
            _mustHaveNextEvidence(rows),
          ];
        })
        .toList(growable: false);
  }

  static bool _isGatePass(List<String> row) {
    return row.length > 3 && row[3].toLowerCase().contains('review pass');
  }

  static bool _isGateAtRisk(List<String> row) {
    return row.length > 3 && row[3].toLowerCase().contains('at risk');
  }

  static bool _isGateNeedsValidation(List<String> row) {
    if (row.length <= 3) return false;
    final status = row[3].toLowerCase();
    return status.contains('needs validation') ||
        status.contains('needs input');
  }

  static String _mustHavePosture({
    required int atRiskGateCount,
    required int needsValidationGateCount,
  }) {
    if (atRiskGateCount > 0) {
      return 'Blocked until hard gates pass';
    }
    if (needsValidationGateCount > 0) {
      return 'Needs validation before recommendation';
    }
    return 'Eligible for shortlist review';
  }

  static String _mustHaveNextEvidence(List<List<String>> rows) {
    final atRiskGates = rows
        .where(_isGateAtRisk)
        .map((row) => row.length > 1 ? row[1] : 'hard gate')
        .toList(growable: false);
    if (atRiskGates.isNotEmpty) {
      return 'Attach official evidence for ${atRiskGates.join(', ')}.';
    }
    final needsValidationGates = rows
        .where(_isGateNeedsValidation)
        .map((row) => row.length > 1 ? row[1] : 'hard gate')
        .toList(growable: false);
    if (needsValidationGates.isNotEmpty) {
      return 'Validate ${needsValidationGates.join(', ')} before customer handoff.';
    }
    return 'Confirm current datasheet and lifecycle evidence before final handoff.';
  }

  List<List<String>> _sourceConfidenceRows(_ComparisonProfile profile) {
    final candidates = profile.candidates.isEmpty
        ? const [
            _ComparisonCandidate(
              product: 'TBD',
              capabilities: 'Add sourced capability facts.',
              constraints: 'Validate hard requirements.',
              lifecycle: 'Needs lifecycle validation',
              fitScore: 'TBD',
              recommendation: 'Review',
            ),
          ]
        : profile.candidates.take(24);
    return candidates
        .map(
          (candidate) => [
            candidate.product,
            candidate.hasCapabilityEvidence
                ? 'Capability facts present, still verify source'
                : 'Needs official datasheet / portfolio facts',
            candidate.lifecycleNeedsValidation
                ? 'Needs official lifecycle source'
                : 'Lifecycle signal present, verify checked date',
            candidate.hasCommercialEvidence
                ? 'Commercial/availability signal present'
                : 'Needs pricing, availability, licensing, support validation',
            candidate.sourceConfidence,
          ],
        )
        .toList(growable: false);
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

  List<List<String>> _migrationSuitabilityRows(_ComparisonProfile profile) {
    final candidates = profile.candidates.isEmpty
        ? const [
            _ComparisonCandidate(
              product: 'TBD',
              capabilities: 'Add sourced capability facts.',
              constraints: 'Validate hard requirements.',
              lifecycle: 'Needs lifecycle validation',
              fitScore: 'TBD',
              recommendation: 'Review',
            ),
          ]
        : profile.candidates.take(24);
    return candidates
        .map(
          (candidate) => [
            candidate.product,
            profile.hasMigrationSignal
                ? 'Current candidate or suggestedMigrationPid comparator'
                : 'Current portfolio candidate',
            'All hard gates pass with sourced capability, lifecycle, licensing, and customer requirement evidence.',
            profile.requiresHighPower
                ? 'Fails UPOE/UPOE+, mGig, power budget, lifecycle runway, or operational fit.'
                : 'Fails sourced capability, lifecycle runway, support, or customer operating model.',
            candidate.migrationSuitability(profile),
          ],
        )
        .toList(growable: false);
  }

  List<List<String>> _lifecycleRunwayRows(_ComparisonProfile profile) {
    final candidates = profile.candidates.isEmpty
        ? const [
            _ComparisonCandidate(
              product: 'TBD',
              capabilities: 'Add sourced capability facts.',
              constraints: 'Validate hard requirements.',
              lifecycle: 'Needs lifecycle validation',
              fitScore: 'TBD',
              recommendation: 'Review',
            ),
          ]
        : profile.candidates.take(24);
    return candidates
        .map(
          (candidate) => [
            candidate.product,
            candidate.lifecycle,
            'Does official lifecycle/support runway meet the customer planning horizon?',
            candidate.lifecycleNeedsValidation
                ? 'Could recommend stale or unsupported platform'
                : 'Validate runway and current portfolio anyway',
            'Account team / architecture reviewer',
          ],
        )
        .toList(growable: false);
  }

  List<List<String>> _replacementCautionRows(_ComparisonProfile profile) {
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
        profile.hasMigrationSignal
            ? 'EoX language detected; superseding current models must be considered'
            : 'Always compare against current available model families',
        'Portfolio drift can make older migration guidance stale',
        'Use current datasheets/catalog facts and checked date',
      ],
    ];
  }

  List<List<String>> _implementationImpactRows(_ComparisonProfile profile) {
    return [
      [
        'Access layer',
        profile.requiresHighPower
            ? 'May require UPOE/UPOE+, mGig access, higher PoE budgets, and uplink review.'
            : 'Depends on AP/client density, PoE class, access speed, and closet distribution.',
        'AP model, per-closet counts, power budget, and access port requirements.',
        'Access switch is selected by port count only and fails AP requirements.',
      ],
      [
        'WAN / security',
        profile.requiresThroughput
            ? 'Throughput and security services can change platform family or license tier.'
            : 'WAN/security sizing remains dependent on service mix and HA mode.',
        'Enabled services, inspected throughput, circuit mix, failover behavior.',
        'Platform meets carrier rate but fails with inspection or HA enabled.',
      ],
      [
        'Operations',
        profile.hasOperationalSignal
            ? 'Operating model is part of the comparison.'
            : 'Operating model still needs to be captured.',
        'Cloud/controller/DNA operations, licensing, support, and customer standards.',
        'Recommendation is technically valid but operationally rejected.',
      ],
      [
        'Lifecycle / migration',
        profile.hasMigrationSignal
            ? 'Migration hints must be compared against current portfolio candidates.'
            : 'Lifecycle still needs official checked-date validation.',
        'Official lifecycle source, current catalog, support runway, customer timeline.',
        'Customer receives a stale recommendation or short support runway.',
      ],
    ];
  }

  List<List<String>> _talkingPointRows(_ComparisonProfile profile) {
    final best = profile.best;
    return [
      [
        'Recommendation framing',
        best == null
            ? 'We need source-backed candidate facts before naming a primary recommendation.'
            : '${best.product} is the current shortlist leader, pending sourced hard-gate validation.',
        'Do not present fit score as final approval without datasheet, lifecycle, and customer requirement evidence.',
      ],
      [
        'Replacement PID caveat',
        'Lifecycle replacement PIDs are migration hints; final choice must satisfy current requirements.',
        'Do not treat EoX replacement PID as the final best model.',
      ],
      [
        'Wi-Fi 7 / UPOE caveat',
        profile.requiresHighPower
            ? 'Because Wi-Fi 7/UPOE is in scope, power budget and mGig access are hard gates.'
            : 'AP model and power draw still need validation before final access switching selection.',
        'Do not recommend access switching without AP power and port-speed facts.',
      ],
      [
        'Customer ask',
        'Ask the customer to confirm must-have constraints, operating model, lifecycle horizon, and commercial limits.',
        'Do not assume budget, licensing, or operational preferences from product tables alone.',
      ],
    ];
  }

  List<List<String>> _comparisonEvidencePolicyRows(_ComparisonProfile profile) {
    return [
      [
        'Comparison matrix is advisory until source evidence is attached.',
        profile.hasSourceEvidence
            ? 'Source evidence signal detected'
            : 'Official sources still required',
        'Attach current datasheets, lifecycle evidence, checked dates, and customer requirements before final recommendation.',
      ],
      [
        'Do not treat EoX replacement PIDs as final model choice.',
        profile.hasMigrationSignal
            ? 'Migration or replacement signal detected'
            : 'No replacement signal detected',
        'Use replacement PIDs as suggestedMigrationPid clues only, then compare against current portfolio candidates.',
      ],
      [
        'Hard gates override fit score.',
        profile.requirementPressure,
        'Reject candidates that fail UPOE, mGig, WAN/security throughput, lifecycle, or operational requirements even if the score looks high.',
      ],
      [
        'Rejected alternatives need explicit reasons.',
        profile.ranked.length > 1
            ? '${profile.ranked.length - 1} alternative candidate${profile.ranked.length == 2 ? '' : 's'} available'
            : 'Alternatives need capture',
        'Document why each lower-fit or stale migration candidate fails or when it should supersede the primary choice.',
      ],
    ];
  }

  List<List<String>> _comparisonVisualVerificationRows(
    _ComparisonProfile profile,
  ) {
    return [
      [
        'Open workbook and confirm all comparison sheets are visible.',
        'Reviewers need the executive decision, matrix, hard gates, source confidence, alternatives, and assumptions.',
        'Required',
      ],
      [
        'Verify header rows are frozen/readable and columns fit product names.',
        'Model names, constraints, lifecycle notes, and recommendation text are easy to clip.',
        'Required',
      ],
      [
        'Review Hard Gate Evaluation for At risk and Needs validation rows.',
        'The workbook should prevent fit-score-only recommendations.',
        profile.requiresHighPower || profile.requiresMultiGig
            ? 'High priority'
            : 'Required',
      ],
      [
        'Review Must-Have Compliance before recommending a model.',
        'The scorecard rolls hard gates into a per-candidate posture so blocked candidates do not survive on fit score alone.',
        profile.requiresHighPower || profile.requiresMultiGig
            ? 'High priority'
            : 'Required',
      ],
      [
        'Check Replacement Cautions before external handoff.',
        'Migration hints and EoX replacement PIDs can be stale or electrically wrong for newer requirements.',
        profile.hasMigrationSignal ? 'High priority' : 'Required',
      ],
      [
        'Confirm Sources Needed and Evidence Policy before sharing.',
        'Product recommendations need current capability, lifecycle, commercial, and customer requirement evidence.',
        'Required',
      ],
    ];
  }

  List<List<String>> _comparisonPublishingRows(_ComparisonProfile profile) {
    return [
      [
        'External handoff',
        'Primary candidate, rejected alternatives, hard gates, and source gaps are reviewed.',
        'Owner approval required',
      ],
      [
        'Decision posture',
        profile.evidenceQuality,
        profile.hasSourceEvidence
            ? 'Validate checked dates'
            : 'Source evidence required',
      ],
      [
        'Hard gates',
        profile.requirementPressure,
        'Close before BOM or customer recommendation',
      ],
      [
        'Lifecycle caveat',
        profile.hasLifecycleConcern
            ? 'Lifecycle/EoX signal detected'
            : 'Lifecycle source still required',
        'Official lifecycle validation required',
      ],
      [
        'Alternatives',
        profile.runnerUp == null
            ? 'Runner-up and reject reasons need capture'
            : '${profile.runnerUp!.product} captured as comparison alternative',
        'Document supersession conditions',
      ],
    ];
  }

  List<List<String>> _comparisonCustomerHandoffRows(
    _ComparisonProfile profile,
  ) {
    final hasCandidateSet = profile.candidates.length >= 2;
    final hardGatesReady =
        !profile.requiresHighPower &&
        !profile.requiresMultiGig &&
        !profile.requiresThroughput;
    final alternativesReady = profile.runnerUp != null;
    final replacementReady =
        !profile.hasMigrationSignal && !profile.hasLifecycleConcern;
    final recommendationReady =
        profile.hasSourceEvidence &&
        hasCandidateSet &&
        hardGatesReady &&
        replacementReady &&
        profile.best != null;

    String readyText(bool ready) => ready ? 'Ready' : 'Needs review';

    return [
      [
        'Source evidence',
        profile.hasSourceEvidence
            ? 'Source or datasheet signal captured'
            : 'Official source evidence missing',
        profile.hasSourceEvidence ? 'Ready' : 'Needs evidence',
        profile.hasSourceEvidence
            ? 'Confirm checked dates and authoritative source links.'
            : 'Attach official datasheets, lifecycle records, portfolio facts, and checked dates.',
        readyText(profile.hasSourceEvidence),
      ],
      [
        'Candidate set',
        hasCandidateSet
            ? '${profile.candidates.length} candidates captured'
            : 'Comparison needs at least two candidates',
        hasCandidateSet ? 'Ready' : 'Needs candidates',
        hasCandidateSet
            ? 'Confirm candidate roles and shortlist completeness.'
            : 'Add primary candidate, runner-up, and relevant alternatives.',
        readyText(hasCandidateSet),
      ],
      [
        'Hard-gate fit',
        hardGatesReady
            ? 'No hard-gate pressure detected'
            : profile.requirementPressure,
        hardGatesReady ? 'Ready' : 'Needs validation',
        hardGatesReady
            ? 'Confirm no hidden power, throughput, lifecycle, or licensing gates.'
            : 'Validate power/UPOE, mGig, throughput, lifecycle, licensing, and support gates before recommendation.',
        readyText(hardGatesReady),
      ],
      [
        'Rejected alternatives',
        alternativesReady
            ? 'Runner-up and alternatives captured'
            : 'Rejected-alternative evidence missing',
        alternativesReady ? 'Ready' : 'Needs rejection reasons',
        alternativesReady
            ? 'Review reject/reconsider rules for each non-selected model.'
            : 'Document why each lower-fit or stale migration candidate fails.',
        readyText(alternativesReady),
      ],
      [
        'Replacement caveats',
        replacementReady
            ? 'No migration/EoX caveat detected'
            : 'Migration/EoX signal requires caveat',
        replacementReady ? 'Ready' : 'Needs lifecycle validation',
        replacementReady
            ? 'Confirm current portfolio fit still governs final selection.'
            : 'Treat EoX replacement PID as a migration hint only; compare against current portfolio candidates.',
        readyText(replacementReady),
      ],
      [
        'Recommendation boundary',
        recommendationReady
            ? 'Evidence and hard gates support external recommendation'
            : 'Advisory only before final recommendation',
        recommendationReady ? 'Ready' : 'Needs review',
        recommendationReady
            ? 'Proceed to reviewer/customer handoff.'
            : 'Close source, hard-gate, and lifecycle caveats before presenting as final model choice.',
        readyText(recommendationReady),
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
        rows.add([
          section.title,
          bullet,
          'Review against requirements.',
          'Reconsider only with sourced capability, lifecycle, or requirement-fit evidence.',
        ]);
      }
      if (section.bullets.isEmpty && section.body.trim().isNotEmpty) {
        rows.add([
          section.title,
          _shorten(section.body.trim(), 180),
          'Review against requirements.',
          'Reconsider only with sourced capability, lifecycle, or requirement-fit evidence.',
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
            'Reconsider only if sourced facts prove hard-gate compliance and stronger lifecycle/current-portfolio fit.',
          ],
        )
        .toList(growable: false);
  }

  List<List<String>> _rejectedAlternativeRows(
    List<_ComparisonCandidate> candidates,
  ) {
    final ranked = [...candidates]
      ..sort((a, b) => b.numericFit.compareTo(a.numericFit));
    final alternatives = ranked.skip(1).take(12).toList(growable: false);
    if (alternatives.isEmpty) {
      return const [
        [
          'TBD',
          'No structured alternative candidates',
          'No alternate candidates were structured enough to reject.',
          'Add source-backed candidate facts and requirement gates.',
        ],
      ];
    }
    return alternatives
        .map(
          (candidate) => [
            candidate.product,
            'Ranked lower than the primary shortlist',
            candidate.primaryCaution,
            'Reconsider only if sourced facts prove hard-gate compliance and stronger lifecycle/current-portfolio fit.',
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

  List<List<String>> _rowsFor(List<WorkbookTable> tables, String name) {
    for (final table in tables) {
      if (table.name == name) return table.rows;
    }
    return const [];
  }

  List<String> _stringRows(List<List<String>> rows) {
    return rows
        .where((row) => row.any((cell) => cell.trim().isNotEmpty))
        .map((row) => row.where((cell) => cell.trim().isNotEmpty).join(': '))
        .toList(growable: false);
  }

  int _mustHavePostureCount(List<List<String>> rows, String posture) {
    final normalizedPosture = posture.toLowerCase();
    return rows.where((row) {
      return row.any((cell) => cell.toLowerCase().contains(normalizedPosture));
    }).length;
  }

  String _mustHaveComplianceSummary(List<List<String>> rows) {
    if (rows.isEmpty) return 'No candidate scorecard rows available';
    final eligible = _mustHavePostureCount(rows, 'Eligible');
    final blocked = _mustHavePostureCount(rows, 'Blocked');
    final needsValidation = _mustHavePostureCount(rows, 'Needs validation');
    return '$eligible eligible, $needsValidation need validation, $blocked blocked candidate${rows.length == 1 ? '' : 's'}';
  }

  int _comparisonCustomerHandoffReadyCount(List<List<String>> rows) {
    return rows.where((row) {
      if (row.length < 5) return false;
      return row[4].toLowerCase().contains('ready');
    }).length;
  }

  List<Map<String, Object?>> _comparisonCustomerHandoffMetadata(
    List<List<String>> rows,
  ) {
    return rows
        .where((row) => row.length >= 5)
        .map(
          (row) => {
            'gate': row[0],
            'signal': row[1],
            'status': row[2],
            'ownerAction': row[3],
            'ready': row[4].toLowerCase().contains('ready'),
          },
        )
        .toList(growable: false);
  }

  String _executiveValue(List<List<String>> rows, String signal) {
    final normalizedSignal = signal.toLowerCase();
    for (final row in rows) {
      if (row.isEmpty) continue;
      if (!row.first.toLowerCase().contains(normalizedSignal)) continue;
      if (row.length < 2) return '';
      return row[1];
    }
    return '';
  }

  String _comparisonReadinessLevel({
    required int candidateCount,
    required int atRiskGateCount,
    required int needsValidationGateCount,
    required bool hasSourceEvidence,
  }) {
    if (candidateCount == 0) return 'Draft - candidate facts required';
    if (!hasSourceEvidence) return 'Draft - source evidence required';
    if (atRiskGateCount > 0) {
      return 'Requirements review required';
    }
    if (needsValidationGateCount > 0) {
      return 'Internal review required';
    }
    return 'Stakeholder review ready';
  }

  String _comparisonHandoffStatus(String readinessLevel) {
    if (readinessLevel.startsWith('Stakeholder')) {
      return 'Comparison package ready for reviewer approval';
    }
    if (readinessLevel.startsWith('Internal')) {
      return 'Comparison package needs validation review';
    }
    if (readinessLevel.startsWith('Requirements')) {
      return 'Comparison package has hard-gate risk';
    }
    return 'Comparison package needs source-backed candidate data';
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

class _ComparisonProfile {
  final List<_ComparisonCandidate> candidates;
  final List<List<String>> requirements;
  final String content;
  final bool requiresHighPower;
  final bool requiresMultiGig;
  final bool requiresThroughput;
  final bool hasLifecycleConcern;
  final bool hasMigrationSignal;
  final bool hasOperationalSignal;
  final bool hasSourceEvidence;

  const _ComparisonProfile({
    required this.candidates,
    required this.requirements,
    required this.content,
    required this.requiresHighPower,
    required this.requiresMultiGig,
    required this.requiresThroughput,
    required this.hasLifecycleConcern,
    required this.hasMigrationSignal,
    required this.hasOperationalSignal,
    required this.hasSourceEvidence,
  });

  factory _ComparisonProfile.from({
    required List<_ComparisonCandidate> candidates,
    required List<List<String>> requirements,
    required String content,
  }) {
    bool has(RegExp pattern) => pattern.hasMatch(content);
    return _ComparisonProfile(
      candidates: candidates,
      requirements: requirements,
      content: content,
      requiresHighPower: has(
        RegExp(
          r'\b(wi[- ]?fi\s*7|upoe\+?|802\.3bt|class\s*[68]|60w|90w)\b',
          caseSensitive: false,
        ),
      ),
      requiresMultiGig: has(
        RegExp(
          r'\b(multigig|mGig|2\.5g|5g|10g(?:base)?(?: access)?|10gig|wi[- ]?fi\s*7)\b',
          caseSensitive: false,
        ),
      ),
      requiresThroughput: has(
        RegExp(
          r'\b(throughput|wan|sd-?wan|inspection|gbps|mbps|firewall|security services?)\b',
          caseSensitive: false,
        ),
      ),
      hasLifecycleConcern: has(
        RegExp(
          r'\b(eox|eol|eos|ldos|lifecycle|migration|replacement pid|verify ldos)\b',
          caseSensitive: false,
        ),
      ),
      hasMigrationSignal: has(
        RegExp(
          r'\b(eox|replacement pid|migration pid|migration|suggestedmigrationpid)\b',
          caseSensitive: false,
        ),
      ),
      hasOperationalSignal: has(
        RegExp(
          r'\b(license|licensing|support|cloud-managed|controller|dna|dashboard|operations?|standardization)\b',
          caseSensitive: false,
        ),
      ),
      hasSourceEvidence: has(
        RegExp(
          r'\b(datasheet|source|official|cisco|portfolio|catalog|checked|eox/api)\b',
          caseSensitive: false,
        ),
      ),
    );
  }

  List<_ComparisonCandidate> get ranked {
    return [...candidates]
      ..sort((a, b) => b.numericFit.compareTo(a.numericFit));
  }

  _ComparisonCandidate? get best => ranked.isEmpty ? null : ranked.first;

  _ComparisonCandidate? get runnerUp {
    final values = ranked;
    return values.length < 2 ? null : values[1];
  }

  String get requirementPressure {
    final signals = <String>[
      if (requiresHighPower) 'UPOE/high-power AP',
      if (requiresMultiGig) 'mGig access',
      if (requiresThroughput) 'throughput/WAN',
      if (hasLifecycleConcern) 'lifecycle runway',
      if (hasOperationalSignal) 'operations/licensing',
    ];
    if (signals.isEmpty) return 'Low - requirements still need discovery';
    return signals.join(', ');
  }

  String get evidenceQuality {
    if (hasSourceEvidence &&
        candidates.any((candidate) => candidate.hasCapabilityEvidence)) {
      return 'Medium - source signals present, still needs checked-date validation';
    }
    if (hasSourceEvidence) {
      return 'Low/Medium - source language present but capability rows need validation';
    }
    return 'Low - official source evidence still required';
  }
}

class _ComparisonCandidate {
  final String product;
  final String capabilities;
  final String constraints;
  final String lifecycle;
  final String fitScore;
  final String recommendation;

  const _ComparisonCandidate({
    required this.product,
    required this.capabilities,
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
      capabilities: cell(2, 'Add sourced capability facts.'),
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

  bool get supportsHighPower {
    final text = '$product $capabilities $constraints'.toLowerCase();
    return RegExp(
      r'\b(upoe\+?|802\.3bt|class\s*[68]|60w|90w|high power)\b',
    ).hasMatch(text);
  }

  bool get supportsMultiGig {
    final text = '$product $capabilities $constraints'.toLowerCase();
    return RegExp(
      r'\b(multigig|mgig|2\.5g|5g|10g|25g|40g|100g)\b',
    ).hasMatch(text);
  }

  bool get lifecycleNeedsValidation {
    final text = '$lifecycle $constraints $recommendation'.toLowerCase();
    return RegExp(
      r'\b(verify|ldos|eol|eos|eox|lifecycle|support|migration|stale)\b',
    ).hasMatch(text);
  }

  bool get hasCapabilityEvidence {
    final text = '$capabilities $constraints'.toLowerCase();
    return RegExp(
      r'\b(upoe|poe|mgig|multigig|uplink|throughput|ports?|stack|ha|10g|25g|40g|100g|license|licensing)\b',
    ).hasMatch(text);
  }

  bool get hasOperationalEvidence {
    final text = '$capabilities $constraints $recommendation'.toLowerCase();
    return RegExp(
      r'\b(license|licensing|cloud|dashboard|controller|dna|support|operations?|standard)\b',
    ).hasMatch(text);
  }

  bool get hasCommercialEvidence {
    final text = '$constraints $recommendation'.toLowerCase();
    return RegExp(
      r'\b(price|pricing|cost|commercial|availability|lead[- ]?time|licens|support)\b',
    ).hasMatch(text);
  }

  String get sourceConfidence {
    var score = 0;
    if (hasCapabilityEvidence) score++;
    if (!lifecycleNeedsValidation) score++;
    if (hasOperationalEvidence || hasCommercialEvidence) score++;
    return switch (score) {
      >= 3 => 'Medium',
      2 => 'Low/Medium',
      _ => 'Low',
    };
  }

  String migrationSuitability(_ComparisonProfile profile) {
    if (profile.requiresHighPower && !supportsHighPower) {
      return 'At risk - high-power AP gate not proven';
    }
    if (profile.requiresMultiGig && !supportsMultiGig) {
      return 'At risk - mGig gate not proven';
    }
    if (lifecycleNeedsValidation) {
      return 'Conditional - lifecycle/source validation required';
    }
    return 'Candidate for shortlist, pending official source validation';
  }
}
