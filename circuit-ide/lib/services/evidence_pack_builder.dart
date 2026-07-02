import 'dart:convert';

import '../models/artifact_document.dart';

class EvidencePackBuilder {
  const EvidencePackBuilder();

  bool matches(String prompt) {
    final normalized = prompt.toLowerCase();
    return RegExp(
      r'\b(evidence pack|citation pack|source pack|sources report|source report|evidence review|fact check|fact-check|source validation|claim validation|unsupported claims?|checked dates?|confidence notes?|visual evidence|screenshot evidence|screenshot review|screen capture evidence|ui evidence|ux evidence|image evidence|visual qa evidence)\b',
    ).hasMatch(normalized);
  }

  ArtifactDocument build({
    required String prompt,
    required String content,
    required ArtifactDocument document,
  }) {
    final sourceBullets = _sourceBullets(document, content);
    final unsupportedBullets = _unsupportedBullets(document, content);
    final visualEvidenceBullets = _visualEvidenceBullets(document, content);
    final visualEvidenceIntakeRows = _visualEvidenceIntakeRows(
      visualEvidenceBullets,
    );
    final visualEvidenceSidecarCount = visualEvidenceBullets
        .where(_hasSidecarOrDescription)
        .length;
    final visualEvidenceMetadataOnlyCount =
        visualEvidenceBullets.length - visualEvidenceSidecarCount;
    final visualEvidenceReliability = _visualEvidenceReliabilityStatus(
      visualEvidenceBullets,
    );
    final customerHandoffRows = _evidenceHandoffRows(
      sourceBullets: sourceBullets,
      unsupportedBullets: unsupportedBullets,
      assumptions: document.assumptions,
      visualEvidenceBullets: visualEvidenceBullets,
      visualEvidenceReliability: visualEvidenceReliability,
    );
    final sections = <ArtifactSection>[
      _section(
        document,
        title: 'Executive Evidence Decision',
        patterns: const [
          'executive evidence decision',
          'decision',
          'handoff decision',
        ],
        fallbackBody:
            'Use this pack to decide which claims are customer-ready, which claims need qualification, and which claims must be removed or refreshed before handoff.',
        fallbackBullets: _executiveDecisionBullets(
          sourceBullets: sourceBullets,
          unsupportedBullets: unsupportedBullets,
          assumptions: document.assumptions,
        ),
      ),
      _section(
        document,
        title: 'Evidence Summary',
        patterns: const ['evidence summary', 'summary', 'overview'],
        fallbackBody: document.summary,
      ),
      _section(
        document,
        title: 'Claim Register',
        patterns: const ['claim register', 'claims', 'validated claims'],
        fallbackBody:
            'List each material claim, the supporting source, checked date, confidence, and any caveats.',
      ),
      _section(
        document,
        title: 'Claim Disposition Workflow',
        patterns: const [
          'claim disposition',
          'disposition workflow',
          'customer-safe wording',
        ],
        fallbackBody:
            'Classify each claim before customer handoff so unsupported, inferred, stale, or source-light statements are rewritten, qualified, or removed.',
      ),
      _section(
        document,
        title: 'Source Inventory',
        patterns: const [
          'source inventory',
          'sources',
          'citations',
          'references',
        ],
        fallbackBody:
            'Authoritative sources, URLs, checked dates, and source notes used for this output.',
        fallbackBullets: sourceBullets,
      ),
      _section(
        document,
        title: 'Visual Evidence Register',
        patterns: const [
          'visual evidence',
          'screenshot',
          'screen capture',
          'ui evidence',
          'ux evidence',
          'image evidence',
          'visual qa',
        ],
        fallbackBody:
            'Screenshot and image evidence is tracked as metadata-only unless OCR/vision analysis is enabled or the user provides a description of the visual details.',
        fallbackBullets: visualEvidenceBullets,
      ),
      _section(
        document,
        title: 'Citation Quality Rules',
        patterns: const [
          'citation quality',
          'source quality',
          'evidence rules',
        ],
        fallbackBody:
            'Classify each citation by authority, freshness, scope fit, and whether the claim wording is directly supported or only inferred.',
        fallbackBullets: const [
          'Official/vendor/customer sources should be preferred for lifecycle, capability, pricing, and recommendation claims.',
          'Checked dates are required for lifecycle, support, product capability, regulatory, pricing, and market-timing claims.',
          'Indirect or inferred evidence must be labeled before customer-facing use.',
        ],
      ),
      _section(
        document,
        title: 'Checked Dates',
        patterns: const ['checked dates', 'checked date', 'freshness'],
        fallbackBody:
            'Record when each source was checked and whether the information is time-sensitive.',
      ),
      _section(
        document,
        title: 'Assumptions And Unknowns',
        patterns: const ['assumptions', 'unknowns', 'open questions'],
        fallbackBody:
            'Assumptions and missing inputs that should be validated before customer-facing use.',
        fallbackBullets: document.assumptions,
      ),
      _section(
        document,
        title: 'Confidence And Risk',
        patterns: const ['confidence', 'risk', 'confidence and risk'],
        fallbackBody:
            'Summarize confidence levels and risks created by stale, missing, or indirect evidence.',
      ),
      _section(
        document,
        title: 'Unsupported Claims / Follow-Up',
        patterns: const [
          'unsupported claims',
          'follow-up',
          'follow up',
          'needs validation',
        ],
        fallbackBody:
            'Claims without enough support should be verified or removed before final handoff.',
        fallbackBullets: unsupportedBullets,
      ),
      _section(
        document,
        title: 'Customer-Ready Claim Gates',
        patterns: const [
          'customer-ready claim gates',
          'customer ready claim gates',
          'claim gates',
        ],
        fallbackBody:
            'A claim is customer-ready only when source authority, checked date, unsupported-claim disposition, and assumption separation gates are satisfied.',
        fallbackBullets:
            _customerReadyGateRows(
                  sourceBullets: sourceBullets,
                  unsupportedBullets: unsupportedBullets,
                  assumptions: document.assumptions,
                )
                .skip(1)
                .map((row) => '${row[0]}: ${row[2]}. ${row[3]}')
                .toList(growable: false),
      ),
      _section(
        document,
        title: 'Customer Follow-Up Checklist',
        patterns: const [
          'customer follow-up',
          'follow-up checklist',
          'follow up checklist',
        ],
        fallbackBody:
            'Use these questions to close evidence gaps, confirm assumptions, and decide which claims can be used in the final customer artifact.',
        fallbackBullets: _followUpRows(unsupportedBullets, document.assumptions)
            .skip(1)
            .map((row) => '${row[0]} Owner: ${row[1]}.')
            .toList(growable: false),
      ),
    ];
    final tables = [
      ..._evidencePackTables(
        sourceBullets: sourceBullets,
        unsupportedBullets: unsupportedBullets,
        visualEvidenceBullets: visualEvidenceBullets,
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
      citations: sourceBullets,
      metadata: {
        ...document.metadata,
        'artifactTemplate': 'evidence_pack',
        'sourcePrompt': prompt,
        'sourceCount': sourceBullets.length,
        'unsupportedClaimCount': unsupportedBullets.length,
        'visualEvidenceCount': visualEvidenceBullets.length,
        'visualEvidenceAttachmentCount': _visualEvidenceAttachmentCount(
          visualEvidenceIntakeRows,
        ),
        'visualEvidenceDimensionCount': visualEvidenceIntakeRows
            .where(
              (row) =>
                  row[3] != 'Not detected' &&
                  (row[1] != 'Unknown' || row[2] != 'Unknown'),
            )
            .length,
        'visualEvidenceSidecarCount': visualEvidenceSidecarCount,
        'visualEvidenceMetadataOnlyCount': visualEvidenceMetadataOnlyCount,
        'visualEvidenceFormatCoverage': _visualEvidenceFormatCoverage(
          visualEvidenceIntakeRows,
          visualEvidenceBullets,
        ),
        'hasVisualEvidenceRegister': true,
        'visualEvidenceReliability': visualEvidenceReliability,
        'visualEvidenceRequiresVisionReview':
            visualEvidenceReliability ==
            'metadata_only_until_vision_or_user_description',
        'visualEvidencePolicy':
            'Do not infer pixel-level screenshot details unless OCR/vision or a user-provided visual description is present.',
        'visualEvidenceReviewAction': visualEvidenceSidecarCount > 0
            ? 'Validate OCR/description sidecar accuracy before customer-facing visual claims.'
            : 'Add OCR, vision analysis, or a user-provided visual description before making pixel-level screenshot claims.',
        'evidencePackTables': tables.length,
        'hasClaimDispositionRegister': true,
        'claimDispositionCount': _claimDispositionRows(
          sourceBullets,
          unsupportedBullets,
          sections,
        ).length,
        'evidenceCustomerHandoffGateCount': customerHandoffRows.length,
        'evidenceCustomerHandoffReadyCount': _handoffReadyCount(
          customerHandoffRows,
        ),
        'evidenceCustomerHandoffMatrix': _stringRows(customerHandoffRows),
        'hasEvidenceCustomerHandoffMatrix': customerHandoffRows.isNotEmpty,
      },
    );
  }

  String toJsonString(ArtifactDocument document) {
    final encoded = {
      'title': document.title,
      'summary': document.summary,
      'sections': [
        for (final section in document.sections)
          {
            'title': section.title,
            'body': section.body,
            'bullets': section.bullets,
          },
      ],
      'tables': [
        for (final table in document.tables)
          {'title': table.title, 'rows': table.rows},
      ],
      'assumptions': document.assumptions,
      'sources': document.citations,
      'metadata': document.metadata,
    };
    return const JsonEncoder.withIndent('  ').convert(encoded);
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
    if (cleaned.isEmpty) return 'Evidence Pack';
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

  List<String> _sourceBullets(ArtifactDocument document, String content) {
    final values = <String>[...document.citations, ..._urlMatches(content)];
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .take(20)
        .toList(growable: false);
  }

  List<String> _unsupportedBullets(ArtifactDocument document, String content) {
    final section = _matchingSection(document.sections, const [
      'unsupported',
      'needs validation',
      'unknown',
      'follow-up',
      'follow up',
    ]);
    if (section != null && section.bullets.isNotEmpty) return section.bullets;
    final lines = content
        .split('\n')
        .map((line) => line.trim())
        .where(
          (line) =>
              line.toLowerCase().contains('unsupported') ||
              line.toLowerCase().contains('needs validation') ||
              line.toLowerCase().contains('unknown'),
        )
        .map((line) => line.replaceFirst(RegExp(r'^[-*]\s*'), ''))
        .where((line) => line.isNotEmpty)
        .take(10)
        .toList(growable: false);
    return lines;
  }

  List<String> _visualEvidenceBullets(
    ArtifactDocument document,
    String content,
  ) {
    final section = _matchingSection(document.sections, const [
      'visual evidence',
      'screenshot',
      'screen capture',
      'ui evidence',
      'ux evidence',
      'image evidence',
      'visual qa',
    ]);
    if (section != null && section.bullets.isNotEmpty) {
      return {
        ...section.bullets,
        ..._visualEvidenceAttachmentBlockLines(content),
      }.take(20).toList(growable: false);
    }
    final attachmentBlockLines = _visualEvidenceAttachmentBlockLines(content);
    final lines = content
        .split('\n')
        .map((line) => line.trim())
        .where((line) {
          final normalized = line.toLowerCase();
          return normalized.contains('screenshot') ||
              normalized.contains('screen capture') ||
              normalized.contains('visual evidence') ||
              normalized.contains('ui evidence') ||
              normalized.contains('ux evidence') ||
              normalized.contains('image evidence') ||
              normalized.contains('visual qa');
        })
        .map((line) => line.replaceFirst(RegExp(r'^[-*]\s*'), ''))
        .where((line) => line.isNotEmpty)
        .toSet()
        .followedBy(attachmentBlockLines)
        .toSet()
        .take(20)
        .toList(growable: false);
    return lines;
  }

  List<String> _visualEvidenceAttachmentBlockLines(String content) {
    final lines = content.split('\n').map((line) => line.trim()).toList();
    final result = <String>[];
    var insideVisualBlock = false;
    var remainingLines = 0;
    for (final line in lines) {
      if (line.isEmpty) {
        if (insideVisualBlock) {
          insideVisualBlock = false;
          remainingLines = 0;
        }
        continue;
      }
      final cleanedLine = _cleanBullet(line);
      final normalized = cleanedLine.toLowerCase();
      if (normalized.contains('image attachment for visual-evidence review')) {
        insideVisualBlock = true;
        remainingLines = 14;
        result.add(cleanedLine);
        continue;
      }
      if (!insideVisualBlock) continue;
      final capturesVisualFact =
          normalized.startsWith('file:') ||
          normalized.startsWith('format:') ||
          normalized.startsWith('size:') ||
          normalized.startsWith('dimensions:') ||
          normalized.startsWith('ocr status:') ||
          normalized.startsWith('ocr/description sidecar status:') ||
          normalized.startsWith('vision model status:') ||
          normalized.startsWith('attached visual text:') ||
          normalized.startsWith('visual evidence status:') ||
          normalized.startsWith('visual analysis contract:') ||
          normalized.startsWith('safe use:') ||
          normalized.startsWith('recommended artifact role:');
      if (capturesVisualFact) {
        result.add(cleanedLine);
      }
      remainingLines--;
      if (remainingLines <= 0 ||
          normalized.startsWith('recommended artifact role:')) {
        insideVisualBlock = false;
        remainingLines = 0;
      }
    }
    return result.toSet().take(20).toList(growable: false);
  }

  Iterable<String> _urlMatches(String content) {
    return RegExp(r'https?://[^\s\])>]+')
        .allMatches(content)
        .map((match) => match.group(0) ?? '')
        .where((value) => value.isNotEmpty);
  }

  List<ArtifactTable> _evidencePackTables({
    required List<String> sourceBullets,
    required List<String> unsupportedBullets,
    required List<String> visualEvidenceBullets,
    required ArtifactDocument document,
    required List<ArtifactSection> sections,
  }) {
    return [
      ArtifactTable(
        title: 'Executive Evidence Decision',
        rows: [
          const [
            'Decision Area',
            'Status',
            'Why it matters',
            'Required action',
          ],
          ..._executiveEvidenceDecisionRows(
            sourceBullets: sourceBullets,
            unsupportedBullets: unsupportedBullets,
            assumptions: document.assumptions,
          ),
        ],
      ),
      ArtifactTable(
        title: 'Claim To Source Matrix',
        rows: [
          const [
            'Claim',
            'Supporting source',
            'Checked date',
            'Confidence',
            'Caveat / validation need',
          ],
          ..._claimRows(sourceBullets, sections),
        ],
      ),
      ArtifactTable(
        title: 'Claim Disposition Register',
        rows: [
          const [
            'Claim',
            'Disposition',
            'Customer-safe wording',
            'Owner',
            'Next action',
          ],
          ..._claimDispositionRows(sourceBullets, unsupportedBullets, sections),
        ],
      ),
      ArtifactTable(
        title: 'Citation Authority Register',
        rows: [
          const [
            'Source',
            'Authority tier',
            'Scope fit',
            'Customer-ready use',
            'Caveat',
          ],
          ..._citationAuthorityRows(sourceBullets),
        ],
      ),
      ArtifactTable(
        title: 'Visual Evidence Register',
        rows: [
          const [
            'Evidence item',
            'Reliability',
            'Safe use',
            'Required follow-up',
          ],
          ..._visualEvidenceRows(visualEvidenceBullets),
        ],
      ),
      ArtifactTable(
        title: 'Visual Evidence Intake Register',
        rows: [
          const [
            'Evidence item',
            'Format',
            'Size',
            'Dimensions',
            'OCR / sidecar',
            'Pixel-input readiness',
          ],
          ..._visualEvidenceIntakeRows(visualEvidenceBullets),
        ],
      ),
      ArtifactTable(
        title: 'Source Freshness Register',
        rows: [
          const [
            'Source',
            'URL / reference',
            'Checked date',
            'Freshness risk',
            'Owner action',
          ],
          ..._sourceRows(sourceBullets),
        ],
      ),
      ArtifactTable(
        title: 'Unsupported Claim Triage',
        rows: [
          const ['Claim', 'Risk', 'Required evidence', 'Disposition'],
          ..._unsupportedRows(unsupportedBullets),
        ],
      ),
      ArtifactTable(
        title: 'Evidence Confidence Scorecard',
        rows: [
          const ['Area', 'Status', 'Confidence', 'Notes'],
          ..._confidenceRows(
            sourceBullets: sourceBullets,
            unsupportedBullets: unsupportedBullets,
            assumptions: document.assumptions,
          ),
        ],
      ),
      ArtifactTable(
        title: 'Customer-Ready Claim Gates',
        rows: [
          const ['Gate', 'Pass condition', 'Current status', 'Failure action'],
          ..._customerReadyGateRows(
            sourceBullets: sourceBullets,
            unsupportedBullets: unsupportedBullets,
            assumptions: document.assumptions,
          ),
        ],
      ),
      ArtifactTable(
        title: 'Customer Follow-Up Checklist',
        rows: [
          const ['Question', 'Owner', 'Needed before final?'],
          ..._followUpRows(unsupportedBullets, document.assumptions),
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
          ..._evidenceHandoffRows(
            sourceBullets: sourceBullets,
            unsupportedBullets: unsupportedBullets,
            assumptions: document.assumptions,
            visualEvidenceBullets: visualEvidenceBullets,
            visualEvidenceReliability: _visualEvidenceReliabilityStatus(
              visualEvidenceBullets,
            ),
          ),
        ],
      ),
    ];
  }

  List<String> _executiveDecisionBullets({
    required List<String> sourceBullets,
    required List<String> unsupportedBullets,
    required List<String> assumptions,
  }) {
    return [
      sourceBullets.isEmpty
          ? 'Not customer-ready: no cited sources are attached.'
          : 'Evidence coverage is available, but source authority and checked dates still need final review.',
      unsupportedBullets.isEmpty
          ? 'No unsupported claims were explicitly flagged.'
          : '${unsupportedBullets.length} unsupported claim${unsupportedBullets.length == 1 ? '' : 's'} require verification, qualification, or removal.',
      assumptions.isEmpty
          ? 'No assumptions were captured; add explicit assumptions if the output relies on inferred context.'
          : '${assumptions.length} assumption${assumptions.length == 1 ? '' : 's'} must be confirmed by the customer or account team.',
    ];
  }

  List<List<String>> _executiveEvidenceDecisionRows({
    required List<String> sourceBullets,
    required List<String> unsupportedBullets,
    required List<String> assumptions,
  }) {
    return [
      [
        'Source coverage',
        sourceBullets.isEmpty ? 'Blocked' : 'Review ready',
        'Claims need traceable support before customer handoff.',
        sourceBullets.isEmpty
            ? 'Add authoritative citations and checked dates.'
            : 'Review authority tier and freshness before final use.',
      ],
      [
        'Unsupported claims',
        unsupportedBullets.isEmpty ? 'No explicit gaps' : 'Action required',
        'Unsupported claims create customer trust and recommendation risk.',
        unsupportedBullets.isEmpty
            ? 'Continue screening for implicit unsupported claims.'
            : 'Verify, qualify, rewrite, or remove each unsupported claim.',
      ],
      [
        'Assumptions',
        assumptions.isEmpty ? 'Missing / implicit' : 'Captured',
        'Assumptions must be separated from sourced facts.',
        assumptions.isEmpty
            ? 'Add assumptions and owner confirmation path.'
            : 'Confirm assumptions with customer or account team.',
      ],
      const [
        'Customer handoff',
        'Conditional',
        'Final artifacts should not overstate evidence.',
        'Use qualified language until all gates pass.',
      ],
    ];
  }

  List<List<String>> _claimRows(
    List<String> sourceBullets,
    List<ArtifactSection> sections,
  ) {
    final claims = _bulletsFor(sections, const [
      'claim register',
      'claims',
      'validated claims',
    ]);
    final rows = <List<String>>[];
    final candidates = claims.isEmpty
        ? const ['Material claim requires source mapping.']
        : claims.take(12);
    var index = 0;
    for (final claim in candidates) {
      final source = sourceBullets.isEmpty
          ? 'Missing cited source'
          : sourceBullets[index % sourceBullets.length];
      rows.add([
        claim,
        _sourceLabel(source),
        _checkedDate(source),
        _confidenceFor(claim, source),
        _caveatFor(claim, source),
      ]);
      index++;
    }
    return rows;
  }

  List<List<String>> _claimDispositionRows(
    List<String> sourceBullets,
    List<String> unsupportedBullets,
    List<ArtifactSection> sections,
  ) {
    final claims = _bulletsFor(sections, const [
      'claim register',
      'claims',
      'validated claims',
    ]);
    final candidates = claims.isEmpty
        ? const ['Material claim requires source mapping.']
        : claims.take(12);
    final rows = <List<String>>[];
    var index = 0;
    for (final claim in candidates) {
      final source = sourceBullets.isEmpty
          ? 'Missing cited source'
          : sourceBullets[index % sourceBullets.length];
      final disposition = _claimDisposition(
        claim: claim,
        source: source,
        unsupportedBullets: unsupportedBullets,
      );
      rows.add([
        claim,
        disposition,
        _customerSafeWording(claim, disposition),
        _claimOwner(claim, source, disposition),
        _claimNextAction(claim, source, disposition),
      ]);
      index++;
    }
    return rows;
  }

  List<List<String>> _sourceRows(List<String> sourceBullets) {
    if (sourceBullets.isEmpty) {
      return const [
        [
          'No source supplied',
          'Missing',
          'Not checked',
          'High',
          'Add authoritative source and checked date.',
        ],
      ];
    }
    return sourceBullets
        .take(20)
        .map((source) {
          return [
            _sourceLabel(source),
            _sourceUrl(source),
            _checkedDate(source),
            _freshnessRisk(source),
            _ownerAction(source),
          ];
        })
        .toList(growable: false);
  }

  List<List<String>> _citationAuthorityRows(List<String> sourceBullets) {
    if (sourceBullets.isEmpty) {
      return const [
        [
          'No source supplied',
          'Missing',
          'No evidence scope',
          'Do not use externally',
          'Attach source before making the claim.',
        ],
      ];
    }
    return sourceBullets
        .take(20)
        .map((source) {
          return [
            _sourceLabel(source),
            _authorityTier(source),
            _scopeFit(source),
            _customerReadyUse(source),
            _authorityCaveat(source),
          ];
        })
        .toList(growable: false);
  }

  List<List<String>> _visualEvidenceRows(List<String> visualEvidenceBullets) {
    if (visualEvidenceBullets.isEmpty) {
      return const [
        [
          'No screenshot or image evidence detected',
          'Missing',
          'Do not claim visual findings from unseen pixels.',
          'Attach screenshots with /screenshot and add a short description, or enable OCR/vision analysis.',
        ],
      ];
    }
    return visualEvidenceBullets
        .take(20)
        .map((item) {
          return [
            _cleanBullet(item),
            _visualEvidenceReliability(item),
            _visualEvidenceSafeUse(item),
            _visualEvidenceFollowUp(item),
          ];
        })
        .toList(growable: false);
  }

  List<List<String>> _visualEvidenceIntakeRows(
    List<String> visualEvidenceBullets,
  ) {
    if (visualEvidenceBullets.isEmpty) {
      return const [
        [
          'No screenshot or image evidence detected',
          'Missing',
          'Unknown',
          'Not detected',
          'Missing',
          'Attach screenshot plus OCR/vision or user description.',
        ],
      ];
    }

    final rows = <List<String>>[];
    var current = _VisualEvidenceIntakeRow.empty();

    void flush() {
      if (!current.hasSignal) return;
      rows.add(current.toRow());
      current = _VisualEvidenceIntakeRow.empty();
    }

    for (final raw in visualEvidenceBullets) {
      final item = _cleanBullet(raw);
      final normalized = item.toLowerCase();
      if (normalized.contains('image attachment for visual-evidence review')) {
        flush();
        current.item = 'Screenshot/image attachment';
        current.hasSignal = true;
        continue;
      }
      if (normalized.startsWith('file:')) {
        current.item = item.substring('file:'.length).trim();
        current.hasSignal = true;
        continue;
      }
      if (normalized.startsWith('format:')) {
        current.format = item.substring('format:'.length).trim();
        current.hasSignal = true;
        continue;
      }
      if (normalized.startsWith('size:')) {
        current.size = item.substring('size:'.length).trim();
        current.hasSignal = true;
        continue;
      }
      if (normalized.startsWith('dimensions:')) {
        current.dimensions = item.substring('dimensions:'.length).trim();
        current.hasSignal = true;
        continue;
      }
      if (normalized.startsWith('ocr status:') ||
          normalized.startsWith('ocr/description sidecar status:')) {
        current.ocr = item.substring(item.indexOf(':') + 1).trim();
        current.hasSignal = true;
        continue;
      }
      if (normalized.startsWith('vision model status:')) {
        current.pixelReadiness = item.substring(item.indexOf(':') + 1).trim();
        current.hasSignal = true;
        continue;
      }
      if (normalized.startsWith('attached visual text:')) {
        current.ocr = 'Sidecar text attached';
        current.hasSignal = true;
        continue;
      }
      if (normalized.contains('screenshot') ||
          normalized.contains('screen capture') ||
          normalized.contains('visual evidence') ||
          normalized.contains('image evidence')) {
        flush();
        rows.add([
          item,
          'Unknown',
          'Unknown',
          _dimensionHint(item),
          _hasSidecarOrDescription(item)
              ? 'OCR/description present'
              : 'Not attached',
          _hasSidecarOrDescription(item)
              ? 'Validate sidecar before pixel-level claims.'
              : 'Metadata-only; do not infer pixel details.',
        ]);
      }
    }
    flush();

    if (rows.isEmpty) {
      return visualEvidenceBullets
          .take(12)
          .map(
            (item) => [
              _cleanBullet(item),
              'Unknown',
              'Unknown',
              _dimensionHint(item),
              _hasSidecarOrDescription(item)
                  ? 'OCR/description present'
                  : 'Not attached',
              _hasSidecarOrDescription(item)
                  ? 'Validate sidecar before pixel-level claims.'
                  : 'Metadata-only; do not infer pixel details.',
            ],
          )
          .toList(growable: false);
    }
    return rows.take(20).toList(growable: false);
  }

  String _visualEvidenceFormatCoverage(
    List<List<String>> rows,
    List<String> visualEvidenceBullets,
  ) {
    final formats = {
      ...rows
          .map((row) => row.length > 1 ? row[1].trim() : '')
          .where((value) => value.isNotEmpty && value != 'Unknown'),
      ...visualEvidenceBullets
          .map(_cleanBullet)
          .where((value) => value.toLowerCase().startsWith('format:'))
          .map((value) => value.substring(value.indexOf(':') + 1).trim())
          .where((value) => value.isNotEmpty),
    }.toList()..sort();
    if (formats.isEmpty) return 'unknown';
    return formats.join(', ');
  }

  int _visualEvidenceAttachmentCount(List<List<String>> rows) {
    return rows.where((row) {
      final format = row.length > 1 ? row[1] : 'Unknown';
      final size = row.length > 2 ? row[2] : 'Unknown';
      return format != 'Unknown' || size != 'Unknown';
    }).length;
  }

  String _dimensionHint(String item) {
    final match = RegExp(
      r'(\d{3,5})\s*[x×]\s*(\d{3,5})',
      caseSensitive: false,
    ).firstMatch(item);
    if (match == null) return 'Not detected';
    return '${match.group(1)} x ${match.group(2)}px';
  }

  String _visualEvidenceReliabilityStatus(List<String> items) {
    if (items.any(_hasSidecarOrDescription)) {
      return 'metadata_plus_ocr_or_user_description';
    }
    return 'metadata_only_until_vision_or_user_description';
  }

  String _visualEvidenceReliability(String item) {
    if (_hasSidecarOrDescription(item)) {
      return 'Metadata plus OCR/description sidecar; still not raw pixel inspection.';
    }
    return 'Metadata-only until OCR/vision or user description confirms details.';
  }

  String _visualEvidenceSafeUse(String item) {
    if (_hasSidecarOrDescription(item)) {
      return 'Use sidecar text as extracted/user-provided evidence and cite the image as visual context.';
    }
    return 'Reference as a visual appendix item, not as inspected pixel evidence.';
  }

  String _visualEvidenceFollowUp(String item) {
    if (_hasSidecarOrDescription(item)) {
      return 'Validate sidecar accuracy before customer-facing visual claims.';
    }
    return 'Confirm UI text, layout, and visual defects before customer-facing claims.';
  }

  bool _hasSidecarOrDescription(String item) {
    final normalized = item.toLowerCase();
    if (normalized.contains('not extracted') ||
        normalized.contains('not attached') ||
        normalized.contains('missing') ||
        normalized.contains('ask for') ||
        normalized.contains('requires') ||
        normalized.contains('require ') ||
        normalized.contains('required') ||
        normalized.contains('metadata-only')) {
      return false;
    }
    return normalized.contains('ocr') ||
        normalized.contains('sidecar') ||
        normalized.contains('attached visual text') ||
        normalized.contains('user-provided description') ||
        normalized.contains('visual description') ||
        normalized.contains('description:');
  }

  List<List<String>> _unsupportedRows(List<String> unsupportedBullets) {
    if (unsupportedBullets.isEmpty) {
      return const [
        [
          'No unsupported claims identified',
          'Low',
          'Maintain citation hygiene.',
          'Ready for review.',
        ],
      ];
    }
    return unsupportedBullets
        .take(12)
        .map((claim) {
          return [
            _cleanBullet(claim),
            'Medium until supported or removed.',
            'Official source, customer data, checked date, or SME confirmation.',
            'Verify, qualify, or remove before customer handoff.',
          ];
        })
        .toList(growable: false);
  }

  List<List<String>> _confidenceRows({
    required List<String> sourceBullets,
    required List<String> unsupportedBullets,
    required List<String> assumptions,
  }) {
    return [
      [
        'Source coverage',
        sourceBullets.isEmpty ? 'Missing sources' : 'Sources attached',
        sourceBullets.isEmpty ? 'Low' : 'Medium',
        sourceBullets.isEmpty
            ? 'Add official or customer-provided evidence.'
            : 'Verify freshness and source authority before final use.',
      ],
      [
        'Unsupported claims',
        unsupportedBullets.isEmpty ? 'None flagged' : 'Follow-up required',
        unsupportedBullets.isEmpty ? 'Medium' : 'Low',
        unsupportedBullets.isEmpty
            ? 'Continue checking claims against source material.'
            : 'Resolve each unsupported claim before customer handoff.',
      ],
      [
        'Assumptions',
        assumptions.isEmpty
            ? 'No assumptions captured'
            : 'Assumptions captured',
        assumptions.isEmpty ? 'Medium' : 'Low until confirmed',
        assumptions.isEmpty
            ? 'Add assumptions if scope or source freshness is uncertain.'
            : 'Confirm assumptions with customer or account team.',
      ],
    ];
  }

  List<List<String>> _followUpRows(
    List<String> unsupportedBullets,
    List<String> assumptions,
  ) {
    final rows = <List<String>>[
      const [
        'Which claims require official source validation before customer use?',
        'Evidence reviewer',
        'Yes',
      ],
      const [
        'Are all checked dates current enough for the decision window?',
        'Account team',
        'Yes',
      ],
      const [
        'Which assumptions need customer confirmation?',
        'Customer sponsor',
        'Yes',
      ],
    ];
    for (final claim in unsupportedBullets.take(3)) {
      rows.add([
        'What evidence supports "${_shorten(_cleanBullet(claim), 80)}"?',
        'Research owner',
        'Yes',
      ]);
    }
    for (final assumption in assumptions.take(3)) {
      rows.add([
        'Can the customer confirm "${_shorten(_cleanBullet(assumption), 80)}"?',
        'Customer / account team',
        'Yes',
      ]);
    }
    return rows;
  }

  List<List<String>> _customerReadyGateRows({
    required List<String> sourceBullets,
    required List<String> unsupportedBullets,
    required List<String> assumptions,
  }) {
    return [
      [
        'Source authority',
        'Official, customer-provided, or clearly reliable source attached.',
        sourceBullets.any((source) => _authorityTier(source) == 'Official')
            ? 'Pass with final refresh'
            : sourceBullets.isEmpty
            ? 'Blocked'
            : 'Review required',
        'Replace weak sources or label the claim as inferred.',
      ],
      [
        'Checked date',
        'Every time-sensitive source includes a checked date.',
        sourceBullets.isNotEmpty &&
                sourceBullets.every(
                  (source) => _checkedDate(source) != 'Not provided',
                )
            ? 'Pass'
            : 'Needs dates',
        'Add checked date before final recommendation.',
      ],
      [
        'Unsupported claims',
        'No material unsupported claim remains unhandled.',
        unsupportedBullets.isEmpty ? 'Pass' : 'Blocked',
        'Verify, qualify, rewrite, or remove flagged claims.',
      ],
      [
        'Assumption separation',
        'Assumptions are explicit and not phrased as sourced facts.',
        assumptions.isEmpty ? 'Review required' : 'Pass with confirmation',
        'Add or confirm assumptions with the customer/account team.',
      ],
    ];
  }

  List<List<String>> _evidenceHandoffRows({
    required List<String> sourceBullets,
    required List<String> unsupportedBullets,
    required List<String> assumptions,
    required List<String> visualEvidenceBullets,
    required String visualEvidenceReliability,
  }) {
    final hasSources = sourceBullets.isNotEmpty;
    final hasCheckedDates =
        hasSources &&
        sourceBullets.every((source) => _checkedDate(source) != 'Not provided');
    final hasOfficialOrReliableSource = sourceBullets.any((source) {
      final tier = _authorityTier(source);
      return tier == 'Official' || tier == 'Reliable';
    });
    final hasVisualEvidence = visualEvidenceBullets.isNotEmpty;
    final visualRequiresReview =
        hasVisualEvidence &&
        visualEvidenceReliability ==
            'metadata_only_until_vision_or_user_description';
    return [
      [
        'Source authority',
        'Customer-facing claims are backed by official, customer-provided, or clearly reliable evidence.',
        hasSources
            ? hasOfficialOrReliableSource
                  ? 'Authoritative source signal attached'
                  : 'Sources attached but authority needs review'
            : 'No cited sources attached',
        hasSources && hasOfficialOrReliableSource ? 'Ready' : 'Blocked',
        'Attach official/customer/reliable source evidence for each material claim.',
        'Do not publish material claims without traceable source authority.',
      ],
      [
        'Checked-date traceability',
        'Every time-sensitive claim has a visible checked date and refresh owner.',
        hasCheckedDates
            ? 'Checked dates present'
            : hasSources
            ? 'Some checked dates missing'
            : 'No source dates available',
        hasCheckedDates ? 'Ready' : 'Needs review',
        'Add checked date, freshness window, and accountable evidence owner.',
        'Lifecycle, pricing, capability, market, and support claims require checked dates.',
      ],
      [
        'Unsupported-claim disposition',
        'Unsupported claims are verified, qualified, rewritten, or removed before customer handoff.',
        unsupportedBullets.isEmpty
            ? 'No unsupported claims explicitly flagged'
            : '${unsupportedBullets.length} unsupported claim${unsupportedBullets.length == 1 ? '' : 's'} flagged',
        unsupportedBullets.isEmpty ? 'Ready' : 'Blocked',
        'Resolve every flagged claim and update customer-safe wording.',
        'Unsupported claims cannot remain in final customer artifacts.',
      ],
      [
        'Assumption separation',
        'Assumptions and unknowns are separated from validated evidence and owner-reviewable.',
        assumptions.isEmpty
            ? 'No assumptions captured'
            : '${assumptions.length} assumption${assumptions.length == 1 ? '' : 's'} captured',
        assumptions.isEmpty ? 'Needs review' : 'Ready',
        'Confirm assumptions with the account team or customer sponsor.',
        'Do not present assumptions as sourced facts.',
      ],
      [
        'Visual evidence reliability',
        'Screenshot/image claims include OCR, vision output, or user-provided visual description when pixel-level details matter.',
        hasVisualEvidence
            ? visualRequiresReview
                  ? 'Metadata-only visual evidence'
                  : 'Visual text / description attached'
            : 'No visual evidence attached',
        hasVisualEvidence
            ? visualRequiresReview
                  ? 'Needs review'
                  : 'Ready'
            : 'Not applicable',
        hasVisualEvidence
            ? 'Validate OCR/description or add vision review before pixel-level visual claims.'
            : 'Attach screenshots only when visual evidence is needed.',
        'Do not infer UI/pixel details from metadata-only screenshots.',
      ],
      [
        'Final customer-safe wording',
        'The final artifact states confidence, caveats, source limits, and follow-up asks plainly.',
        hasSources && unsupportedBullets.isEmpty
            ? 'Customer-safe claim wording can be drafted'
            : 'Customer-safe wording needs evidence cleanup',
        hasSources && unsupportedBullets.isEmpty ? 'Ready' : 'Needs review',
        'Review final wording for overclaims, stale evidence, and missing caveats.',
        'Final handoff must distinguish validated facts, assumptions, and open evidence gaps.',
      ],
    ];
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
        .map(_cleanBullet)
        .where((value) => value.isNotEmpty)
        .toSet()
        .take(20)
        .toList(growable: false);
  }

  List<String> _sentences(String value) {
    return RegExp(r'[^.!?]+[.!?]?')
        .allMatches(value)
        .map((match) => match.group(0)?.trim() ?? '')
        .where((sentence) => sentence.isNotEmpty)
        .toList(growable: false);
  }

  String _sourceLabel(String source) {
    final cleaned = _cleanBullet(source);
    final withoutUrl = cleaned.replaceAll(RegExp(r'https?://\S+'), '').trim();
    final beforeChecked = withoutUrl
        .split(RegExp(r'\s+[-\u2013\u2014]\s+checked\s+', caseSensitive: false))
        .first
        .trim();
    if (beforeChecked.isEmpty) return _shorten(cleaned, 90);
    return _shorten(beforeChecked, 90);
  }

  String _sourceUrl(String source) {
    return RegExp(
          r'https?://[^\s\])>]+',
        ).firstMatch(source)?.group(0)?.trim() ??
        'No URL captured';
  }

  String _checkedDate(String source) {
    final iso = RegExp(r'\b20\d{2}-\d{2}-\d{2}\b').firstMatch(source);
    if (iso != null) return iso.group(0) ?? 'Not provided';
    final checked = RegExp(
      r'checked\s+([A-Za-z]{3,9}\s+\d{1,2},?\s+20\d{2}|20\d{2})',
      caseSensitive: false,
    ).firstMatch(source);
    return checked?.group(1)?.trim() ?? 'Not provided';
  }

  String _freshnessRisk(String source) {
    final checkedDate = _checkedDate(source);
    if (checkedDate == 'Not provided') return 'High - missing checked date';
    final lower = source.toLowerCase();
    if (lower.contains('api') || lower.contains('official')) {
      return 'Low if rechecked before handoff';
    }
    return 'Medium - verify source freshness';
  }

  String _authorityTier(String source) {
    final lower = source.toLowerCase();
    if (lower.contains('official') ||
        lower.contains('api') ||
        lower.contains('cisco.com') ||
        lower.contains('datasheet') ||
        lower.contains('eox')) {
      return 'Official';
    }
    if (lower.contains('customer') ||
        lower.contains('workshop') ||
        lower.contains('inventory') ||
        lower.contains('account team')) {
      return 'Customer-provided';
    }
    if (lower.contains('analyst') ||
        lower.contains('industry') ||
        lower.contains('report')) {
      return 'Third-party';
    }
    return 'Unclassified';
  }

  String _scopeFit(String source) {
    final lower = source.toLowerCase();
    if (lower.contains('lifecycle') ||
        lower.contains('eox') ||
        lower.contains('ldos') ||
        lower.contains('eol')) {
      return 'Lifecycle timing';
    }
    if (lower.contains('datasheet') ||
        lower.contains('capability') ||
        lower.contains('model') ||
        lower.contains('product')) {
      return 'Product capability';
    }
    if (lower.contains('customer') ||
        lower.contains('workshop') ||
        lower.contains('inventory')) {
      return 'Customer context';
    }
    if (lower.contains('market') || lower.contains('industry')) {
      return 'Market context';
    }
    return 'General support';
  }

  String _customerReadyUse(String source) {
    final tier = _authorityTier(source);
    final hasCheckedDate = _checkedDate(source) != 'Not provided';
    if (tier == 'Official' && hasCheckedDate) {
      return 'Use with checked-date citation';
    }
    if (tier == 'Official') return 'Use only after checked date is added';
    if (tier == 'Customer-provided') {
      return 'Use after sponsor confirmation';
    }
    if (tier == 'Third-party') return 'Use as context, not final proof';
    return 'Do not use until classified';
  }

  String _authorityCaveat(String source) {
    final tier = _authorityTier(source);
    if (_checkedDate(source) == 'Not provided') {
      return 'Missing checked date.';
    }
    return switch (tier) {
      'Official' => 'Refresh before final handoff if time-sensitive.',
      'Customer-provided' => 'Confirm owner, date, and inventory freshness.',
      'Third-party' => 'Use for context; pair with official/customer evidence.',
      _ => 'Validate authority and relevance.',
    };
  }

  String _ownerAction(String source) {
    final lower = source.toLowerCase();
    if (lower.contains('cisco') || lower.contains('official')) {
      return 'Refresh official source before final recommendation.';
    }
    if (lower.contains('customer') || lower.contains('workshop')) {
      return 'Confirm customer-provided evidence with sponsor.';
    }
    return 'Validate authority, date, and relevance.';
  }

  String _confidenceFor(String claim, String source) {
    final lower = '$claim $source'.toLowerCase();
    if (source.contains('Missing cited source')) return 'Low';
    if (lower.contains('official') || lower.contains('api')) return 'Medium';
    if (lower.contains('unsupported') || lower.contains('unknown')) {
      return 'Low';
    }
    return 'Medium';
  }

  String _claimDisposition({
    required String claim,
    required String source,
    required List<String> unsupportedBullets,
  }) {
    final lower = '$claim $source'.toLowerCase();
    if (_matchesUnsupportedClaim(claim, unsupportedBullets)) {
      return 'Remove or qualify before handoff';
    }
    if (source.contains('Missing cited source')) {
      return 'Do not use externally';
    }
    if (_checkedDate(source) == 'Not provided') {
      return 'Use only after checked date is added';
    }
    if (lower.contains('replacement') ||
        lower.contains('recommendation') ||
        lower.contains('best model') ||
        lower.contains('current portfolio')) {
      return 'Use with capability validation';
    }
    return switch (_authorityTier(source)) {
      'Official' => 'Ready after final freshness check',
      'Customer-provided' => 'Use after sponsor confirmation',
      'Third-party' => 'Context only',
      _ => 'Internal review only',
    };
  }

  bool _matchesUnsupportedClaim(String claim, List<String> unsupportedBullets) {
    final normalizedClaim = _cleanBullet(claim).toLowerCase();
    if (normalizedClaim.contains('unsupported') ||
        normalizedClaim.contains('unknown') ||
        normalizedClaim.contains('needs validation')) {
      return true;
    }
    for (final unsupported in unsupportedBullets) {
      final normalizedUnsupported = _cleanBullet(unsupported).toLowerCase();
      if (normalizedUnsupported.isEmpty) continue;
      if (normalizedClaim.contains(normalizedUnsupported) ||
          normalizedUnsupported.contains(normalizedClaim)) {
        return true;
      }
      final claimTerms = normalizedClaim
          .split(RegExp(r'[^a-z0-9]+'))
          .where((term) => term.length > 4)
          .toSet();
      final unsupportedTerms = normalizedUnsupported
          .split(RegExp(r'[^a-z0-9]+'))
          .where((term) => term.length > 4)
          .toSet();
      if (claimTerms.intersection(unsupportedTerms).length >= 3) {
        return true;
      }
    }
    return false;
  }

  String _customerSafeWording(String claim, String disposition) {
    final clean = _shorten(_cleanBullet(claim), 110);
    return switch (disposition) {
      'Ready after final freshness check' =>
        'Use as stated after refreshing the checked date: "$clean"',
      'Use with capability validation' =>
        'Qualify as requirement-dependent until capability and current-portfolio fit are sourced.',
      'Use after sponsor confirmation' =>
        'Phrase as customer-provided context until the sponsor confirms owner and date.',
      'Context only' =>
        'Use only as background context; do not present as final proof.',
      'Use only after checked date is added' =>
        'Add checked date before using this claim externally.',
      'Remove or qualify before handoff' =>
        'Rewrite with caveats or remove until direct evidence is attached.',
      _ =>
        'Keep internal until authority, date, and source scope are validated.',
    };
  }

  String _claimOwner(String claim, String source, String disposition) {
    final lower = '$claim $source $disposition'.toLowerCase();
    if (lower.contains('lifecycle') ||
        lower.contains('eox') ||
        lower.contains('eol') ||
        lower.contains('ldos')) {
      return 'Lifecycle reviewer';
    }
    if (lower.contains('replacement') ||
        lower.contains('recommendation') ||
        lower.contains('model') ||
        lower.contains('portfolio')) {
      return 'Solution architect';
    }
    if (lower.contains('customer-provided') ||
        lower.contains('sponsor') ||
        lower.contains('inventory')) {
      return 'Account team';
    }
    if (lower.contains('third-party') || lower.contains('context only')) {
      return 'Evidence reviewer';
    }
    return 'Evidence owner';
  }

  String _claimNextAction(String claim, String source, String disposition) {
    if (disposition == 'Do not use externally') {
      return 'Attach an authoritative source before customer use.';
    }
    if (disposition == 'Remove or qualify before handoff') {
      return 'Find direct evidence, rewrite with caveats, or remove the claim.';
    }
    if (disposition == 'Use with capability validation') {
      return 'Validate current capability, requirements fit, and lifecycle before recommending.';
    }
    if (_checkedDate(source) == 'Not provided') {
      return 'Add checked date and source freshness note.';
    }
    if (disposition == 'Context only') {
      return 'Pair with official or customer-provided evidence before final handoff.';
    }
    return 'Refresh source, confirm wording, and mark ready for review.';
  }

  String _caveatFor(String claim, String source) {
    final lower = '$claim $source'.toLowerCase();
    if (source.contains('Missing cited source')) {
      return 'Add authoritative evidence before customer use.';
    }
    if (lower.contains('replacement') || lower.contains('recommendation')) {
      return 'Validate current portfolio fit; do not rely on migration hint alone.';
    }
    if (_checkedDate(source) == 'Not provided') {
      return 'Add checked date and freshness note.';
    }
    return 'Verify source freshness and claim wording before final handoff.';
  }

  String _cleanBullet(String value) {
    return value
        .replaceFirst(RegExp(r'^[-*]\s+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _shorten(String value, int maxLength) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength - 1).trim()}...';
  }
}

class _VisualEvidenceIntakeRow {
  String item;
  String format;
  String size;
  String dimensions;
  String ocr;
  String pixelReadiness;
  bool hasSignal;

  _VisualEvidenceIntakeRow({
    required this.item,
    required this.format,
    required this.size,
    required this.dimensions,
    required this.ocr,
    required this.pixelReadiness,
    required this.hasSignal,
  });

  factory _VisualEvidenceIntakeRow.empty() {
    return _VisualEvidenceIntakeRow(
      item: 'Screenshot/image attachment',
      format: 'Unknown',
      size: 'Unknown',
      dimensions: 'Not detected',
      ocr: 'Not attached',
      pixelReadiness: 'Metadata-only; do not infer pixel details.',
      hasSignal: false,
    );
  }

  List<String> toRow() {
    return [
      item.isEmpty ? 'Screenshot/image attachment' : item,
      format.isEmpty ? 'Unknown' : format,
      size.isEmpty ? 'Unknown' : size,
      dimensions.isEmpty ? 'Not detected' : dimensions,
      ocr.isEmpty ? 'Not attached' : ocr,
      pixelReadiness.isEmpty
          ? 'Metadata-only; do not infer pixel details.'
          : pixelReadiness,
    ];
  }
}
