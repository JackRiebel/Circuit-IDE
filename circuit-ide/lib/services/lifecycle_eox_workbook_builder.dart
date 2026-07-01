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
    final fullContent = '$prompt\n$content';
    final profile = _LifecycleProfile(
      records: lifecycleRecords,
      content: fullContent,
      checkedDate: _checkedDate(fullContent),
    );
    return [
      WorkbookTable(
        name: 'Executive Risk',
        rows: [
          const [
            'Decision Signal',
            'Current Answer',
            'Why It Matters',
            'Next Action',
          ],
          ..._executiveRiskRows(profile),
        ],
      ),
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
          ..._replacementValidationRows(fullContent),
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
          ..._decisionGateRows(fullContent),
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
        name: 'Official Date Evidence',
        rows: [
          const [
            'Product / PID',
            'Lifecycle source status',
            'Checked date',
            'Missing evidence',
            'Customer-ready action',
          ],
          ..._officialDateEvidenceRows(lifecycleRecords, fullContent),
        ],
      ),
      WorkbookTable(
        name: 'Date Authority',
        rows: [
          const [
            'Evidence Area',
            'Authority',
            'Current Status',
            'Customer-Ready Requirement',
            'Gap',
          ],
          ..._dateAuthorityRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'Support Runway',
        rows: [
          const [
            'Product / PID',
            'LDOS',
            'Runway State',
            'Customer Risk',
            'Action',
          ],
          ..._supportRunwayRows(lifecycleRecords),
        ],
      ),
      WorkbookTable(
        name: 'Replacement Suitability',
        rows: [
          const [
            'Current product',
            'suggestedMigrationPid',
            'Detected requirement signal',
            'Suitability status',
            'Recommendation caveat',
            'Required next validation',
          ],
          ..._replacementSuitabilityRows(
            document: document,
            content: fullContent,
            records: lifecycleRecords,
          ),
        ],
      ),
      WorkbookTable(
        name: 'Current Portfolio Shortlist',
        rows: [
          const [
            'Current product',
            'Migration hint',
            'Current candidate class',
            'Requirement fit pressure',
            'Supersede rule',
            'Evidence needed',
            'Recommendation posture',
          ],
          ..._currentPortfolioShortlistRows(
            document: document,
            content: fullContent,
            profile: profile,
          ),
        ],
      ),
      WorkbookTable(
        name: 'Migration Decision',
        rows: [
          const [
            'Current Product',
            'Migration Hint',
            'Decision Treatment',
            'Supersede If',
            'Evidence Needed',
          ],
          ..._migrationDecisionRows(document, fullContent, profile),
        ],
      ),
      WorkbookTable(
        name: 'Replacement Readiness',
        rows: [
          const [
            'Replacement Gate',
            'Required Proof',
            'Status',
            'Reject If',
            'Owner',
          ],
          ..._replacementReadinessRows(profile),
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
          ..._wifi7ReadinessRows(fullContent),
        ],
      ),
      WorkbookTable(
        name: 'Customer Actions',
        rows: [
          const ['Action', 'Owner', 'Needed Before', 'Output'],
          ..._customerActionRows(profile),
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
        name: 'Evidence Policy',
        rows: [
          const ['Policy', 'Current Signal', 'Owner Action'],
          ..._lifecycleEvidencePolicyRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'Visual QA',
        rows: [
          const ['Check', 'Why It Matters', 'Status'],
          ..._lifecycleVisualVerificationRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'Publishing Readiness',
        rows: [
          const ['Gate', 'Requirement', 'Status'],
          ..._lifecyclePublishingRows(profile),
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
      'Executive Risk',
    ).skip(1).toList(growable: false);
    final lifecycleRows = _rowsFor(
      tables,
      'Lifecycle Status',
    ).skip(1).toList(growable: false);
    final urgencyRows = _rowsFor(
      tables,
      'Urgency Timeline',
    ).skip(1).toList(growable: false);
    final migrationRows = _rowsFor(
      tables,
      'Migration Hints',
    ).skip(1).toList(growable: false);
    final dateAuthorityRows = _rowsFor(
      tables,
      'Date Authority',
    ).skip(1).toList(growable: false);
    final replacementRows = _rowsFor(
      tables,
      'Replacement Suitability',
    ).skip(1).toList(growable: false);
    final shortlistRows = _rowsFor(
      tables,
      'Current Portfolio Shortlist',
    ).skip(1).toList(growable: false);
    final customerActionRows = _rowsFor(
      tables,
      'Customer Actions',
    ).skip(1).toList(growable: false);
    final riskRows = _rowsFor(
      tables,
      'Risk Register',
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
    final sourceSheetCount = tables
        .where((table) => table.name.toLowerCase().startsWith('source '))
        .length;
    final highRiskCount = lifecycleRows.where((row) {
      final joined = row.join(' ').toLowerCase();
      return joined.contains('high') ||
          joined.contains('unsupported') ||
          joined.contains('end of support');
    }).length;
    final unknownDateCount = lifecycleRows.where((row) {
      return row.any((cell) => cell.trim().toUpperCase() == 'TBD');
    }).length;
    final migrationHintCount = migrationRows.where((row) {
      return row.any((cell) {
        final normalized = cell.toLowerCase();
        return normalized.contains('replacement') ||
            normalized.contains('migration') ||
            normalized.contains('suggestedmigrationpid');
      });
    }).length;
    final hasOfficialSource = dateAuthorityRows.any((row) {
      final joined = row.join(' ').toLowerCase();
      return joined.contains('cisco eox') ||
          joined.contains('official cisco') ||
          joined.contains('official lifecycle');
    });
    final hasCheckedDate = dateAuthorityRows.any((row) {
      return row.join(' ').toLowerCase().contains('checked date');
    });
    final readinessLevel = _lifecycleReadinessLevel(
      highRiskCount: highRiskCount,
      unknownDateCount: unknownDateCount,
      hasOfficialSource: hasOfficialSource,
      hasCheckedDate: hasCheckedDate,
    );
    return {
      'artifact': 'lifecycle_eox_workbook',
      'workbookKind': 'lifecycle_eox',
      'sheetCount': tables.length,
      'sourceSheetCount': sourceSheetCount,
      'lifecycleRecordCount': lifecycleRows.length,
      'highRiskLifecycleCount': highRiskCount,
      'unknownLifecycleDateCount': unknownDateCount,
      'urgencyItemCount': urgencyRows.length,
      'migrationHintCount': migrationHintCount,
      'replacementSuitabilityCount': replacementRows.length,
      'currentPortfolioCandidateCount': shortlistRows.length,
      'customerActionCount': customerActionRows.length,
      'lifecycleRiskCount': riskRows.length,
      'lifecycleReadinessLevel': readinessLevel,
      'lifecycleHandoffStatus': _lifecycleHandoffStatus(readinessLevel),
      'lifecycleDecisionPosture':
          'Lifecycle dates are authoritative only when sourced; replacement PIDs remain migration hints until current-fit validation closes.',
      'highestLifecycleRisk': _executiveValue(
        executiveRows,
        'Highest lifecycle risk',
      ),
      'dateAuthority': _executiveValue(
        executiveRows,
        'Lifecycle date authority',
      ),
      'checkedDateStatus': _executiveValue(
        executiveRows,
        'Checked date requirement',
      ),
      'migrationPosture': _executiveValue(
        executiveRows,
        'Migration recommendation posture',
        column: 2,
      ),
      'modernRequirementPressure': _executiveValue(
        executiveRows,
        'Current requirement pressure',
      ),
      'hasOfficialLifecycleSource': hasOfficialSource,
      'hasCheckedDateEvidence': hasCheckedDate,
      'lifecycleQualityManifestVersion': '1.0',
      'lifecycleEvidencePolicy': _stringRows(evidencePolicyRows),
      'lifecycleEvidencePolicyCount': evidencePolicyRows.length,
      'lifecycleVisualVerificationChecklist': _stringRows(visualQaRows),
      'lifecycleVisualVerificationChecklistCount': visualQaRows.length,
      'lifecyclePublishingMetadata': _stringRows(publishingRows),
      'lifecyclePublishingMetadataCount': publishingRows.length,
      'hasLifecycleQualityManifest': true,
      'hasLifecycleEvidencePolicy': evidencePolicyRows.isNotEmpty,
      'hasLifecycleVisualVerificationChecklist': visualQaRows.isNotEmpty,
      'hasLifecyclePublishingMetadata': publishingRows.isNotEmpty,
    };
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

  List<List<String>> _executiveRiskRows(_LifecycleProfile profile) {
    return [
      [
        'Highest lifecycle risk',
        profile.highestRisk,
        'This determines whether the customer needs monitoring, date validation, or immediate migration planning.',
        profile.highestRisk == 'High'
            ? 'Prioritize migration plan and support-risk communication.'
            : 'Validate official lifecycle evidence before making replacement claims.',
      ],
      [
        'Lifecycle date authority',
        profile.hasCiscoSource
            ? 'Official Cisco source signal present'
            : 'Official Cisco source not proven',
        'Lifecycle dates are customer-facing only when backed by Cisco EoX/API or official Cisco evidence.',
        profile.hasCiscoSource
            ? 'Attach URL/API record and checked date to the customer handoff.'
            : 'Fetch Cisco EoX/API records before presenting dates.',
      ],
      [
        'Checked date requirement',
        profile.checkedDate ?? 'Missing checked date',
        'Lifecycle data goes stale; checked date makes the report auditable.',
        profile.checkedDate == null
            ? 'Add checked date for every lifecycle lookup.'
            : 'Keep checked date visible in handoff materials.',
      ],
      [
        'Migration recommendation posture',
        profile.hasMigrationSignal
            ? 'Migration hints detected'
            : 'No structured migration hints',
        'Cisco EoX replacement PID is a migration clue only, not the best-current-model decision.',
        'Do not treat migration hint as final recommendation; compare current portfolio candidates.',
      ],
      [
        'Current requirement pressure',
        _replacementRequirementSignal(profile.content),
        'Wi-Fi 7, UPOE, mGig, uplinks, licensing, and lifecycle runway can supersede old migration hints.',
        'Run readiness gates before recommending a replacement model.',
      ],
    ];
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

  List<List<String>> _dateAuthorityRows(_LifecycleProfile profile) {
    final checked = profile.checkedDate ?? 'Missing checked date';
    return [
      [
        'Official lifecycle dates',
        'Cisco EoX/API or official Cisco source',
        profile.hasCiscoSource
            ? 'Cisco source signal detected'
            : 'Needs authoritative source',
        'Status, End of Sale, LDOS, source URL/API record, checked date',
        profile.hasCiscoSource
            ? 'Confirm exact URL/API record'
            : 'Missing Cisco authoritative evidence',
      ],
      [
        'Checked date',
        'Report metadata / source review date',
        checked,
        'A visible date for when lifecycle evidence was checked',
        profile.checkedDate == null ? 'Missing checked date' : 'None detected',
      ],
      [
        'Replacement suitability facts',
        'Current portfolio datasheets / official catalog',
        profile.hasMigrationSignal
            ? 'Migration hint exists; suitability unproven'
            : 'Needs current shortlist',
        'Current candidates, rejected alternatives, fit rationale, lifecycle runway',
        'Needs current portfolio comparison',
      ],
      [
        'Customer requirements',
        'Customer supplied and design validated',
        _replacementRequirementSignal(profile.content),
        'Wi-Fi generation, AP power draw, mGig ports, uplinks, HA, licensing, growth',
        profile.hasModernRequirementSignal
            ? 'Convert signals into numeric design requirements'
            : 'Needs discovery',
      ],
    ];
  }

  List<List<String>> _supportRunwayRows(List<_LifecycleRecord> records) {
    final targetRecords = records.isEmpty
        ? const [
            _LifecycleRecord(
              product: 'TBD',
              status: 'Needs lookup',
              endOfSale: 'TBD',
              ldos: 'TBD',
              risk: 'Unknown',
              source: 'Use Cisco EoX/API or official Cisco source.',
            ),
          ]
        : records.take(48);
    return [
      for (final record in targetRecords)
        [
          record.product,
          record.ldos,
          record.runwayState,
          record.customerRisk,
          record.action,
        ],
    ];
  }

  List<List<String>> _officialDateEvidenceRows(
    List<_LifecycleRecord> records,
    String content,
  ) {
    final checkedDate = _checkedDate(content) ?? 'Missing checked date';
    final targetRecords = records.isEmpty
        ? const [
            _LifecycleRecord(
              product: 'TBD',
              status: 'Needs lookup',
              endOfSale: 'TBD',
              ldos: 'TBD',
              risk: 'Unknown',
              source: 'Use Cisco EoX/API or official Cisco source.',
            ),
          ]
        : records.take(48);
    return [
      for (final record in targetRecords)
        [
          record.product,
          record.sourceAuthority,
          checkedDate,
          record.missingEvidence(checkedDate),
          record.customerReadyAction(checkedDate),
        ],
    ];
  }

  List<List<String>> _replacementSuitabilityRows({
    required ArtifactDocument document,
    required String content,
    required List<_LifecycleRecord> records,
  }) {
    final migrationRows = _migrationHintRows(document, content);
    final recordByProduct = {
      for (final record in records) record.product.toLowerCase(): record,
    };
    final requirementSignal = _replacementRequirementSignal(content);
    if (migrationRows.isEmpty) {
      return const [
        [
          'TBD',
          'TBD',
          'Current requirements not structured yet',
          'Needs candidate shortlist',
          'Do not recommend a migration target until current portfolio facts prove fit.',
          'Add current portfolio candidates, lifecycle dates, and requirement gates.',
        ],
      ];
    }
    return migrationRows
        .take(48)
        .map((row) {
          final product = row.isNotEmpty ? row[0] : 'TBD';
          final hint = row.length > 1 ? row[1] : 'TBD';
          final record = recordByProduct[product.toLowerCase()];
          final lifecycleRisk = record?.risk ?? 'Review';
          return [
            product,
            hint,
            requirementSignal,
            hint == 'TBD'
                ? 'Needs current candidate'
                : 'Migration hint only; suitability unproven',
            hint == 'TBD'
                ? 'Do not recommend until a current model is sourced and compared.'
                : 'Do not recommend $hint unless sourced facts prove current portfolio, Wi-Fi 7/UPOE, mGig, uplink, licensing, and lifecycle fit.',
            'Compare against newest current model families; document rejected alternatives and lifecycle runway. Current risk: $lifecycleRisk.',
          ];
        })
        .toList(growable: false);
  }

  List<List<String>> _currentPortfolioShortlistRows({
    required ArtifactDocument document,
    required String content,
    required _LifecycleProfile profile,
  }) {
    final migrationRows = _migrationHintRows(document, content);
    final rows = migrationRows.isEmpty
        ? const [
            ['TBD', 'TBD'],
          ]
        : migrationRows.take(48);
    return [
      for (final row in rows)
        ..._portfolioRowsFor(
          product: row.isNotEmpty ? row[0] : 'TBD',
          migrationHint: row.length > 1 ? row[1] : 'TBD',
          profile: profile,
        ),
    ];
  }

  List<List<String>> _portfolioRowsFor({
    required String product,
    required String migrationHint,
    required _LifecycleProfile profile,
  }) {
    final requirementPressure = _replacementRequirementSignal(profile.content);
    final classes = {
      _candidateClassFor(product, profile),
      if (migrationHint != 'TBD') 'EoX suggestedMigrationPid comparator',
      'Newest current portfolio candidate',
    }.toList(growable: false);
    return [
      for (final candidateClass in classes)
        [
          product,
          migrationHint,
          candidateClass,
          requirementPressure,
          candidateClass == 'EoX suggestedMigrationPid comparator'
              ? 'Supersede if a current candidate has better requirement fit or longer lifecycle runway.'
              : 'Prefer only when sourced facts satisfy requirements better than migration hint and alternatives.',
          _portfolioEvidenceNeeded(candidateClass, profile),
          candidateClass == 'EoX suggestedMigrationPid comparator'
              ? 'Migration clue only; not final recommendation.'
              : 'Candidate shortlist item; needs sourced capability and lifecycle evidence.',
        ],
    ];
  }

  String _candidateClassFor(String product, _LifecycleProfile profile) {
    final normalized = product.toLowerCase();
    if (normalized.contains('air-ap') ||
        normalized.contains('cw') ||
        normalized.contains('mr')) {
      return profile.hasWifi7
          ? 'Current Wi-Fi 7 AP family'
          : 'Current wireless AP family';
    }
    if (normalized.contains('c93') ||
        normalized.contains('c94') ||
        normalized.contains('c95') ||
        normalized.contains('ms')) {
      return profile.hasWifi7 || profile.hasHighPower || profile.hasMultiGig
          ? 'Current UPOE/mGig access switching family'
          : 'Current campus switching family';
    }
    if (normalized.contains('mx') ||
        normalized.contains('isr') ||
        normalized.contains('asr')) {
      return 'Current edge/WAN platform family';
    }
    return 'Current portfolio candidate family';
  }

  String _portfolioEvidenceNeeded(
    String candidateClass,
    _LifecycleProfile profile,
  ) {
    final evidence = <String>[
      'Official datasheet/catalog capability facts',
      'Candidate lifecycle runway and checked date',
    ];
    if (profile.hasWifi7 || candidateClass.toLowerCase().contains('wi-fi 7')) {
      evidence.add('Wi-Fi 7 support and AP model fit');
    }
    if (profile.hasHighPower || candidateClass.toLowerCase().contains('upoe')) {
      evidence.add('UPOE/UPOE+ per-port and aggregate budget');
    }
    if (profile.hasMultiGig || candidateClass.toLowerCase().contains('mgig')) {
      evidence.add('mGig access, uplinks, and oversubscription');
    }
    evidence.add('Rejected alternatives and final fit rationale');
    return evidence.join('; ');
  }

  List<List<String>> _migrationDecisionRows(
    ArtifactDocument document,
    String content,
    _LifecycleProfile profile,
  ) {
    final migrationRows = _migrationHintRows(document, content);
    if (migrationRows.isEmpty) {
      return const [
        [
          'TBD',
          'TBD',
          'No final recommendation',
          'Any current candidate better satisfies requirements or has longer runway',
          'Current portfolio candidates, datasheets, lifecycle dates, and customer requirements',
        ],
      ];
    }
    return migrationRows
        .take(48)
        .map(
          (row) => [
            row[0],
            row.length > 1 ? row[1] : 'TBD',
            'suggestedMigrationPid only; not final recommendation',
            profile.hasModernRequirementSignal
                ? 'Supersede if newer model better satisfies Wi-Fi 7, UPOE, mGig, uplinks, licensing, or lifecycle runway.'
                : 'Supersede if current portfolio comparison proves better fit or longer support runway.',
            'Official datasheets/catalog facts, lifecycle runway, rejected alternatives, and fit score.',
          ],
        )
        .toList(growable: false);
  }

  List<List<String>> _replacementReadinessRows(_LifecycleProfile profile) {
    return [
      [
        'Lifecycle runway',
        'Candidate has support runway suitable for the customer lifecycle',
        profile.hasCiscoSource
            ? 'Needs candidate LDOS comparison'
            : 'Needs official dates',
        'Candidate is near EoS/EoL or has shorter runway than alternatives',
        'SE / lifecycle owner',
      ],
      [
        'Wi-Fi generation fit',
        'Candidate supports target AP generation and operational model',
        profile.hasWifi7
            ? 'Wi-Fi 7 requirement detected'
            : 'Needs AP generation confirmation',
        'Candidate does not support the intended AP generation or management plane',
        'Wireless architect',
      ],
      [
        'UPOE / UPOE+ budget',
        'Per-port and aggregate power meet AP draw with reserve',
        profile.hasHighPower
            ? 'Power requirement detected'
            : 'Needs power draw input',
        'Insufficient per-port power, aggregate budget, or redundant PSU capacity',
        'Switching architect',
      ],
      [
        'mGig and uplinks',
        'Access ports and uplinks avoid bottlenecks for modern APs/WAN',
        profile.hasMultiGig
            ? 'mGig/high-speed signal detected'
            : 'Needs access/uplink target',
        'No mGig where required or uplinks oversubscribe design targets',
        'Network architect',
      ],
      [
        'Licensing and operations',
        'License tier, management plane, support contract, and migration effort fit',
        'Needs customer operations validation',
        'Hardware fits technically but fails licensing/support/operations constraints',
        'Customer operations owner',
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

  List<List<String>> _customerActionRows(_LifecycleProfile profile) {
    return [
      [
        'Customer-ready action plan',
        'SE / account team',
        'Before customer handoff',
        'Summarize lifecycle risk, migration posture, and required validations.',
      ],
      [
        'Pull official EoX evidence',
        'Lifecycle owner',
        'Before presenting dates',
        profile.checkedDate == null
            ? 'Cisco EoX/API records with source URLs and checked date.'
            : 'Cisco EoX/API records with source URLs; checked date ${profile.checkedDate}.',
      ],
      [
        'Build current portfolio shortlist',
        'Architecture owner',
        'Before final replacement recommendation',
        'Candidate models, fit scores, rejected alternatives, lifecycle runway.',
      ],
      [
        'Validate Wi-Fi 7/UPOE/mGig gates',
        'Wireless and switching owners',
        'Before BOM recommendation',
        'AP draw, port speed, power supplies, uplinks, stacking, HA, and growth headroom.',
      ],
      [
        'Document recommendation caveats',
        'Evidence reviewer',
        'Before executive/customer share',
        'Clear distinction between lifecycle dates, migration hints, and final model selection.',
      ],
    ];
  }

  List<List<String>> _lifecycleEvidencePolicyRows(_LifecycleProfile profile) {
    return [
      [
        'Lifecycle dates require Cisco EoX/API or official Cisco evidence.',
        profile.hasCiscoSource
            ? 'Cisco lifecycle source signal detected'
            : 'Official lifecycle source missing',
        'Attach source URL/API record, checked date, and product-specific lifecycle fields before customer handoff.',
      ],
      [
        'Replacement PIDs are migration hints only.',
        profile.hasMigrationSignal
            ? 'Migration or replacement hint detected'
            : 'No migration hint detected',
        'Compare suggestedMigrationPid against current portfolio, Wi-Fi 7, UPOE, mGig, uplink, licensing, and lifecycle runway requirements.',
      ],
      [
        'Modern requirements can supersede EoX migration hints.',
        profile.hasModernRequirementSignal
            ? _replacementRequirementSignal(profile.content)
            : 'Modern requirement signal still needs discovery',
        'Reject or re-rank candidates that fail power, access speed, HA, licensing, or runway gates.',
      ],
      [
        'Customer-facing lifecycle claims need checked dates.',
        profile.checkedDate == null
            ? 'Checked date missing'
            : 'Checked date ${profile.checkedDate}',
        'Record when evidence was checked and refresh stale or incomplete records before external use.',
      ],
    ];
  }

  List<List<String>> _lifecycleVisualVerificationRows(
    _LifecycleProfile profile,
  ) {
    return [
      [
        'Open workbook and confirm all lifecycle sheets are visible.',
        'Reviewers need executive risk, lifecycle status, dates, source quality, replacement suitability, actions, and assumptions.',
        'Required',
      ],
      [
        'Verify lifecycle date columns and checked-date fields are readable.',
        'LDOS/EoS/EoL and checked-date evidence are the core authority of the artifact.',
        profile.checkedDate == null ? 'High priority' : 'Required',
      ],
      [
        'Review Replacement Suitability and Migration Decision before sharing.',
        'EoX suggestedMigrationPid can be stale or incomplete for Wi-Fi 7/UPOE/mGig needs.',
        profile.hasMigrationSignal ? 'High priority' : 'Required',
      ],
      [
        'Confirm Current Portfolio Shortlist includes supersede rules.',
        'The workbook should show why newer candidates may beat old migration hints.',
        profile.hasModernRequirementSignal ? 'High priority' : 'Required',
      ],
      [
        'Check Evidence Policy and Publishing Readiness before external handoff.',
        'The artifact must distinguish lifecycle date authority from replacement recommendation suitability.',
        'Required',
      ],
    ];
  }

  List<List<String>> _lifecyclePublishingRows(_LifecycleProfile profile) {
    final readiness = _lifecycleReadinessLevel(
      highRiskCount: profile.records.where((record) {
        final joined = '${record.status} ${record.risk}'.toLowerCase();
        return joined.contains('high') ||
            joined.contains('unsupported') ||
            joined.contains('end of support');
      }).length,
      unknownDateCount: profile.records.where((record) {
        return record.endOfSale == 'TBD' || record.ldos == 'TBD';
      }).length,
      hasOfficialSource: profile.hasCiscoSource,
      hasCheckedDate: profile.checkedDate != null,
    );
    return [
      [
        'External handoff',
        'Official lifecycle source, checked date, replacement caveats, and current-fit validation are reviewed.',
        readiness.contains('Ready') ? 'Review' : 'Owner approval required',
      ],
      [
        'Decision posture',
        'Lifecycle dates inform support risk; final model choice requires current portfolio and requirement matching.',
        'Advisory',
      ],
      [
        'Date authority',
        'Cisco EoX/API or official Cisco lifecycle source is attached for every customer-facing date.',
        profile.hasCiscoSource ? 'Detected' : 'Missing',
      ],
      [
        'Replacement caveat',
        'EoX replacement PID is labeled suggestedMigrationPid and not final recommendation.',
        profile.hasMigrationSignal ? 'Required' : 'Monitor',
      ],
      [
        'Modern requirements',
        'Wi-Fi 7, UPOE, mGig, uplink, licensing, and HA gates are validated before BOM or model recommendation.',
        profile.hasModernRequirementSignal ? 'Required' : 'Needs discovery',
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

  List<List<String>> _rowsFor(List<WorkbookTable> tables, String name) {
    for (final table in tables) {
      if (table.name == name) return table.rows;
    }
    return const [];
  }

  List<String> _stringRows(List<List<String>> rows) {
    return rows
        .where((row) => row.any((cell) => cell.trim().isNotEmpty))
        .map((row) => row.map((cell) => cell.trim()).join(': '))
        .toList(growable: false);
  }

  String _executiveValue(
    List<List<String>> rows,
    String signal, {
    int column = 1,
  }) {
    final normalizedSignal = signal.toLowerCase();
    for (final row in rows) {
      if (row.isEmpty) continue;
      if (row.first.toLowerCase() != normalizedSignal) continue;
      if (row.length > column && row[column].trim().isNotEmpty) {
        return row[column].trim();
      }
    }
    return '';
  }

  String _lifecycleReadinessLevel({
    required int highRiskCount,
    required int unknownDateCount,
    required bool hasOfficialSource,
    required bool hasCheckedDate,
  }) {
    if (!hasOfficialSource || !hasCheckedDate || unknownDateCount > 0) {
      return highRiskCount > 0
          ? 'High risk - source validation required'
          : 'Evidence review required';
    }
    if (highRiskCount > 0) return 'Ready for risk review';
    return 'Ready for lifecycle review';
  }

  String _lifecycleHandoffStatus(String readinessLevel) {
    if (readinessLevel.contains('High risk')) {
      return 'Lifecycle risk review workbook';
    }
    if (readinessLevel.contains('Evidence')) {
      return 'Evidence review workbook';
    }
    return 'Lifecycle review workbook';
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

  String? _checkedDate(String content) {
    final labeled = RegExp(
      r'\b(?:checked|checked date|as of|verified)\D{0,24}([0-9]{1,2}[-/ ][A-Za-z]{3,9}[-/ ][0-9]{2,4}|[A-Za-z]{3,9}\s+[0-9]{1,2},?\s+[0-9]{4}|[0-9]{4}-[0-9]{2}-[0-9]{2})',
      caseSensitive: false,
    ).firstMatch(content);
    if (labeled != null) return labeled.group(1);
    return null;
  }

  String _replacementRequirementSignal(String content) {
    final signals = <String>[];
    if (RegExp(
      r'\b(wi[- ]?fi\s*7|wifi\s*7)\b',
      caseSensitive: false,
    ).hasMatch(content)) {
      signals.add('Wi-Fi 7');
    }
    if (RegExp(
      r'\b(upoe\+?|802\.3bt|60w|90w)\b',
      caseSensitive: false,
    ).hasMatch(content)) {
      signals.add('UPOE / 802.3bt');
    }
    if (RegExp(
      r'\b(multigig|mgig|2\.5g|5g|10g|10gig)\b',
      caseSensitive: false,
    ).hasMatch(content)) {
      signals.add('mGig / high-speed access');
    }
    if (RegExp(
      r'\b(current portfolio|newer model|replacement|migration)\b',
      caseSensitive: false,
    ).hasMatch(content)) {
      signals.add('current portfolio comparison');
    }
    return signals.isEmpty ? 'Requirements need discovery' : signals.join(', ');
  }
}

class _LifecycleRecord {
  final String product;
  final String status;
  final String endOfSale;
  final String ldos;
  final String risk;
  final String source;

  const _LifecycleRecord({
    required this.product,
    required this.status,
    required this.endOfSale,
    required this.ldos,
    required this.risk,
    required this.source,
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
      source: cell(5, 'Use Cisco EoX/API or official Cisco source.'),
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

  String get runwayState {
    final lower = '$status $risk $ldos'.toLowerCase();
    if (ldos == 'TBD') return 'Unknown runway';
    if (lower.contains('high') ||
        lower.contains('unsupported') ||
        lower.contains('end of support')) {
      return 'Support runway at risk';
    }
    if (lower.contains('medium') ||
        lower.contains('review') ||
        lower.contains('end of sale')) {
      return 'Runway requires validation';
    }
    return 'Monitor runway';
  }

  String get customerRisk {
    final lower = '$status $risk'.toLowerCase();
    if (lower.contains('high') ||
        lower.contains('unsupported') ||
        lower.contains('end of support')) {
      return 'Potential unsupported hardware, renewal exposure, and migration urgency.';
    }
    if (ldos == 'TBD' || endOfSale == 'TBD') {
      return 'Missing lifecycle dates can create false confidence in the recommendation.';
    }
    return 'No immediate lifecycle risk proven; continue monitoring and validate replacement separately.';
  }

  String get sourceAuthority {
    final lower = source.toLowerCase();
    if (lower.contains('cisco') &&
        (lower.contains('eox') ||
            lower.contains('api') ||
            lower.contains('official'))) {
      return 'Cisco authoritative source named; verify URL/API record.';
    }
    if (lower.contains('cisco')) {
      return 'Cisco source named; confirm it is official lifecycle evidence.';
    }
    return 'Authoritative Cisco EoX/API source required.';
  }

  String missingEvidence(String checkedDate) {
    final missing = <String>[];
    if (endOfSale == 'TBD') missing.add('End of Sale');
    if (ldos == 'TBD') missing.add('LDOS');
    if (!source.toLowerCase().contains('cisco')) {
      missing.add('official Cisco source');
    }
    if (checkedDate == 'Missing checked date') missing.add('checked date');
    return missing.isEmpty ? 'None detected' : missing.join(', ');
  }

  String customerReadyAction(String checkedDate) {
    final hasCheckedDate = checkedDate != 'Missing checked date';
    if (missingEvidence(checkedDate) == 'None detected' && hasCheckedDate) {
      return 'Lifecycle dates are reviewable; still validate replacement suitability separately.';
    }
    return 'Add Cisco EoX/API record, checked date, and source URL before customer handoff.';
  }
}

class _LifecycleProfile {
  final List<_LifecycleRecord> records;
  final String content;
  final String? checkedDate;

  const _LifecycleProfile({
    required this.records,
    required this.content,
    required this.checkedDate,
  });

  bool get hasCiscoSource {
    return records.any(
          (record) => record.source.toLowerCase().contains('cisco'),
        ) ||
        RegExp(
          r'\bcisco\b.*\b(eox|api|official)\b',
          caseSensitive: false,
        ).hasMatch(content);
  }

  bool get hasMigrationSignal {
    return RegExp(
      r'\b(replacement pid|migration pid|successor|replacement|migration hint|suggestedmigrationpid)\b',
      caseSensitive: false,
    ).hasMatch(content);
  }

  bool get hasWifi7 {
    return RegExp(
      r'\b(wi[- ]?fi\s*7|wifi\s*7)\b',
      caseSensitive: false,
    ).hasMatch(content);
  }

  bool get hasHighPower {
    return RegExp(
      r'\b(upoe\+?|802\.3bt|60w|90w|high power)\b',
      caseSensitive: false,
    ).hasMatch(content);
  }

  bool get hasMultiGig {
    return RegExp(
      r'\b(multigig|mgig|2\.5g|5g|10g|10gig)\b',
      caseSensitive: false,
    ).hasMatch(content);
  }

  bool get hasModernRequirementSignal {
    return hasWifi7 || hasHighPower || hasMultiGig;
  }

  String get highestRisk {
    final combined = records
        .map((record) => '${record.status} ${record.risk}')
        .join(' ')
        .toLowerCase();
    if (combined.contains('high') ||
        combined.contains('unsupported') ||
        combined.contains('end of support')) {
      return 'High';
    }
    if (combined.contains('medium') ||
        combined.contains('review') ||
        combined.contains('end of sale') ||
        records.any(
          (record) => record.ldos == 'TBD' || record.endOfSale == 'TBD',
        )) {
      return 'Review';
    }
    return 'Monitor';
  }
}
