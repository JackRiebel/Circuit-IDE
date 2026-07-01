import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/artifact_document.dart';

class PdfArtifactRenderer {
  const PdfArtifactRenderer();

  List<List<String>> previewRowsFor(
    ArtifactDocument document, {
    int pageCount = 0,
  }) {
    final outlineEntries = _outlineEntries(document);
    return [
      ['Section', 'Type', 'Items'],
      if (pageCount > 0) ['0', 'Pages', '$pageCount'],
      ['0', 'PDF Bookmarks', '${outlineEntries.length}'],
      ['1', 'Lead Decision Callout', '4'],
      ['2', 'Executive Decision Brief', '5'],
      ['3', 'Recommendation Summary', '4'],
      [
        '4',
        'Risk & Assumption Register',
        '${_riskRegisterRows(document).length}',
      ],
      ['5', 'Next-Step Action Plan', '${_nextStepRows(document).length}'],
      ['6', 'Executive Summary', document.summary.trim().isEmpty ? '0' : '1'],
      for (var i = 0; i < document.sections.length; i++)
        [
          '${i + 7}',
          document.sections[i].title,
          '${document.sections[i].bullets.length + (document.sections[i].body.trim().isEmpty ? 0 : 1)}',
        ],
      if (document.tables.isNotEmpty)
        [
          '${document.sections.length + 7}',
          'Data Tables',
          '${document.tables.length}',
        ],
      ['${document.sections.length + 8}', 'Stakeholder Readout', '4'],
      [
        '${document.sections.length + 9}',
        'Evidence Confidence Matrix',
        '${_evidenceConfidenceRows(document).length}',
      ],
      ['${document.sections.length + 10}', 'Approval Gates', '4'],
      ['${document.sections.length + 11}', 'Validation Checklist', '6'],
      [
        '${document.sections.length + 12}',
        'Customer Handoff Scorecard',
        '${_handoffScorecardRows(document).length}',
      ],
      [
        '${document.sections.length + 13}',
        'Decision Log',
        '${_decisionLogRows(document).length}',
      ],
      [
        '${document.sections.length + 14}',
        'Decision Sign-Off',
        '${_decisionSignOffRows(document).length - 1} gates',
      ],
      if (document.assumptions.isNotEmpty)
        [
          '${document.sections.length + 15}',
          'Assumptions',
          '${document.assumptions.length}',
        ],
      if (document.citations.isNotEmpty)
        [
          '${document.sections.length + 16}',
          'Sources / Evidence',
          '${document.citations.length}',
        ],
    ];
  }

  Map<String, Object?> metadataFor(ArtifactDocument document) {
    final pages = _paginate(_itemsFor(document));
    final outlineEntries = _outlineEntries(document);
    final previewRows = previewRowsFor(document, pageCount: pages.length);
    final readinessSignals = _readinessSignals(document);
    final validationGaps = _validationGapsFor(document);
    final documentParts = _documentPartsFor(document);
    final scorecardRows = _handoffScorecardRows(document).skip(1).toList();
    final handoffScore = _handoffScoreFor(scorecardRows);
    return {
      'generator': 'CircuitCode',
      'artifact': 'pdf_report',
      'reportType': _reportTypeFor(document),
      'audience': _audienceFor(document),
      'reportPurpose': _reportPurposeFor(document),
      'handoffStatus': _handoffStatus(document),
      'handoffScore': handoffScore,
      'handoffReadinessLevel': _handoffReadinessLevelFor(handoffScore),
      'decisionOwner': _decisionOwner(document),
      'decisionAsk': _decisionAskFor(document),
      'reviewPath': _reviewPathFor(document),
      'documentParts': documentParts,
      'documentPartCount': documentParts.length,
      'documentQuality': 'Enterprise PDF handoff report',
      'designPreset': 'customer_handoff_report',
      'layoutSystem':
          'US Letter, 0.75 inch content frame, Helvetica type scale',
      'formFactors': [
        'Lead decision callout',
        'PDF bookmark outline',
        'Executive decision brief',
        'Recommendation summary',
        'Risk register',
        'Next-step action plan',
        'Evidence confidence matrix',
        'Approval gates',
        'Validation checklist',
        'Customer handoff scorecard',
        'Decision log',
        'Decision sign-off page',
        if (document.tables.isNotEmpty) 'Data tables',
        if (document.assumptions.isNotEmpty) 'Assumptions appendix',
        if (document.citations.isNotEmpty) 'Sources appendix',
      ],
      'tableCoverage': document.tables.isEmpty
          ? 'No supporting tables'
          : '${document.tables.length} table${document.tables.length == 1 ? '' : 's'} packaged',
      'evidenceCoverage': document.citations.isEmpty
          ? 'No citations attached'
          : '${document.citations.length} source item${document.citations.length == 1 ? '' : 's'} captured',
      'appendixCoverage': _appendixCoverageFor(document),
      'validationGaps': validationGaps,
      'validationGapCount': validationGaps.length,
      'pageCount': pages.length,
      'bookmarkCount': outlineEntries.length,
      'sectionCount': document.sections.length,
      'reportSectionCount': previewRows.isEmpty ? 0 : previewRows.length - 1,
      'tableCount': document.tables.length,
      'assumptionCount': document.assumptions.length,
      'citationCount': document.citations.length,
      'riskItemCount': _riskRegisterRows(document).length,
      'nextStepCount': _nextStepRows(document).length,
      'evidenceItemCount': _evidenceConfidenceRows(document).length,
      'evidenceGapCount': _evidenceGapCount(document),
      'handoffScorecardItemCount': scorecardRows.length,
      'decisionLogCount': _decisionLogRows(document).length - 1,
      'decisionSignOffGateCount': _decisionSignOffRows(document).length - 1,
      'approvalGateCount': _approvalGateRows(document).length,
      'readinessSignals': readinessSignals,
      'readinessSignalCount': readinessSignals.length,
      'hasOutline': outlineEntries.isNotEmpty,
      'hasLeadDecisionCallout': true,
      'hasExecutiveDecisionBrief': true,
      'hasRecommendationSummary': true,
      'hasRiskRegister': true,
      'hasNextStepActionPlan': true,
      'hasDocumentMap': true,
      'hasEvidenceConfidenceMatrix': true,
      'hasApprovalGates': true,
      'hasValidationChecklist': true,
      'hasCustomerHandoffScorecard': true,
      'hasDecisionLog': true,
      'hasDecisionSignOffPage': true,
      'hasFooterPageNumbers': true,
      'hasExplicitTableGeometry': true,
      'hasAssumptionsAppendix': document.assumptions.isNotEmpty,
      'hasSourcesAppendix': document.citations.isNotEmpty,
      'hasCustomerReadyPackage': _hasCustomerReadyPackage(document),
      'hasCustomerReadyPdf':
          _hasCustomerReadyPackage(document) && validationGaps.isEmpty,
    };
  }

  Uint8List render(ArtifactDocument document) {
    final pages = _paginate(_itemsFor(document));
    final outlineEntries = _outlineEntries(document);
    final objects = <int, List<int>>{};
    final pageIds = <int>[];
    objects[3] = _bytes(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    );
    objects[4] = _bytes(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>',
    );
    objects[5] = _bytes('<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>');
    objects[6] = _bytes(
      '<< /Title (${_pdfText(document.title)}) /Author (CircuitCode) '
      '/Subject (${_pdfText('Enterprise customer handoff report')}) '
      '/Keywords (${_pdfText(_keywords(document).join(', '))}) '
      '/Creator (CircuitCode) /Producer (CircuitCode Artifact Renderer) >>',
    );

    for (var i = 0; i < pages.length; i++) {
      final pageId = 7 + (i * 2);
      final contentId = pageId + 1;
      pageIds.add(pageId);
      final stream = _contentStream(
        pages[i],
        document: document,
        pageNumber: i + 1,
        pageCount: pages.length,
      );
      objects[contentId] = _bytes(
        '<< /Length ${utf8.encode(stream).length} >>\nstream\n$stream\nendstream',
      );
      objects[pageId] = _bytes(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Resources << /Font << /F1 3 0 R /F2 4 0 R /F3 5 0 R >> >> '
        '/Contents $contentId 0 R >>',
      );
    }
    final outlineRootId = 7 + (pages.length * 2);
    final firstOutlineItemId = outlineRootId + 1;
    final outlineIds = <int>[];
    for (var i = 0; i < outlineEntries.length; i++) {
      outlineIds.add(firstOutlineItemId + i);
    }
    objects[1] = _bytes(
      '<< /Type /Catalog /Pages 2 0 R /Outlines $outlineRootId 0 R /PageMode /UseOutlines >>',
    );
    objects[2] = _bytes(
      '<< /Type /Pages /Kids [${pageIds.map((id) => '$id 0 R').join(' ')}] /Count ${pageIds.length} >>',
    );
    objects[outlineRootId] = _bytes(
      outlineIds.isEmpty
          ? '<< /Type /Outlines /Count 0 >>'
          : '<< /Type /Outlines /First ${outlineIds.first} 0 R /Last ${outlineIds.last} 0 R /Count ${outlineIds.length} >>',
    );
    for (var i = 0; i < outlineEntries.length; i++) {
      final entry = outlineEntries[i];
      final id = outlineIds[i];
      final previous = i == 0 ? '' : ' /Prev ${outlineIds[i - 1]} 0 R';
      final next = i == outlineIds.length - 1
          ? ''
          : ' /Next ${outlineIds[i + 1]} 0 R';
      final pageId = _pageIdForOutlineEntry(entry.title, pages, pageIds);
      objects[id] = _bytes(
        '<< /Title (${_pdfText(entry.title)}) /Parent $outlineRootId 0 R$previous$next /Dest [$pageId 0 R /FitH 744] >>',
      );
    }

    final output = BytesBuilder(copy: false);
    output.add(_bytes('%PDF-1.4\n%\u00e2\u00e3\u00cf\u00d3\n'));
    final offsets = <int, int>{};
    final maxObjectId = objects.keys.reduce((a, b) => a > b ? a : b);
    for (var id = 1; id <= maxObjectId; id++) {
      final object = objects[id];
      if (object == null) continue;
      offsets[id] = output.length;
      output
        ..add(_bytes('$id 0 obj\n'))
        ..add(object)
        ..add(_bytes('\nendobj\n'));
    }
    final xrefOffset = output.length;
    output.add(_bytes('xref\n0 ${maxObjectId + 1}\n'));
    output.add(_bytes('0000000000 65535 f \n'));
    for (var id = 1; id <= maxObjectId; id++) {
      final offset = offsets[id] ?? 0;
      output.add(_bytes('${offset.toString().padLeft(10, '0')} 00000 n \n'));
    }
    output.add(
      _bytes(
        'trailer\n<< /Size ${maxObjectId + 1} /Root 1 0 R /Info 6 0 R >>\nstartxref\n$xrefOffset\n%%EOF\n',
      ),
    );
    return output.toBytes();
  }

  List<_PdfItem> _itemsFor(ArtifactDocument document) {
    final items = <_PdfItem>[
      _PdfText(document.title, size: 25, bold: true, gapAfter: 11),
      const _PdfText(
        'CircuitCode customer handoff report',
        size: 10,
        color: _PdfColor.muted,
        gapAfter: 18,
      ),
      const _PdfText(
        'Report Overview',
        size: 15,
        bold: true,
        gapBefore: 6,
        gapAfter: 6,
      ),
      _PdfText(
        'Sections: ${document.sections.length}   Tables: ${document.tables.length}   Assumptions: ${document.assumptions.length}   Sources: ${document.citations.length}',
        size: 10.2,
        color: _PdfColor.muted,
        gapAfter: 8,
      ),
      const _PdfText(
        'Lead Decision Callout',
        size: 15,
        bold: true,
        gapBefore: 8,
        gapAfter: 6,
      ),
      _PdfTable(_leadDecisionCalloutRows(document)),
      const _PdfText(
        'Executive Decision Brief',
        size: 15,
        bold: true,
        gapBefore: 8,
        gapAfter: 6,
      ),
      _PdfTable(_executiveDecisionBriefRows(document)),
      const _PdfText(
        'Document Map',
        size: 15,
        bold: true,
        gapBefore: 6,
        gapAfter: 6,
      ),
      for (final item in _documentMap(document).take(12))
        _PdfText('- $item', size: 9.8, indent: 14, gapAfter: 1),
      const _PdfText(
        'Recommendation Summary',
        size: 15,
        bold: true,
        gapBefore: 8,
        gapAfter: 6,
      ),
      _PdfTable(_recommendationSummaryRows(document)),
      const _PdfText(
        'Risk & Assumption Register',
        size: 15,
        bold: true,
        gapBefore: 8,
        gapAfter: 6,
      ),
      _PdfTable(_riskRegisterRows(document)),
      const _PdfText(
        'Next-Step Action Plan',
        size: 15,
        bold: true,
        gapBefore: 8,
        gapAfter: 6,
      ),
      _PdfTable(_nextStepRows(document)),
      const _PdfText(
        'Executive Summary',
        size: 16,
        bold: true,
        gapBefore: 6,
        gapAfter: 7,
      ),
      if (document.summary.trim().isNotEmpty)
        _PdfText(document.summary, size: 10.5, gapAfter: 12),
    ];
    for (final section in document.sections) {
      items.add(
        _PdfText(
          section.title,
          size: 15,
          bold: true,
          gapBefore: 12,
          gapAfter: 6,
        ),
      );
      for (final paragraph in _paragraphs(section.body).take(6)) {
        items.add(_PdfText(paragraph, size: 10.3));
      }
      for (final bullet in section.bullets.take(12)) {
        items.add(_PdfText('- $bullet', size: 10.3, indent: 16, gapAfter: 2));
      }
    }
    for (final table in document.tables.take(6)) {
      items
        ..add(
          _PdfText(
            table.title,
            size: 13.5,
            bold: true,
            gapBefore: 12,
            gapAfter: 6,
          ),
        )
        ..add(_PdfTable(table.rows.take(16).toList(growable: false)));
    }
    items
      ..add(
        const _PdfText(
          'Stakeholder Readout',
          size: 13.5,
          bold: true,
          gapBefore: 12,
          gapAfter: 6,
        ),
      )
      ..add(_PdfTable(_stakeholderReadoutRows(document)))
      ..add(
        const _PdfText(
          'Evidence Confidence Matrix',
          size: 13.5,
          bold: true,
          gapBefore: 12,
          gapAfter: 6,
        ),
      )
      ..add(_PdfTable(_evidenceConfidenceRows(document)))
      ..add(
        const _PdfText(
          'Approval Gates',
          size: 13.5,
          bold: true,
          gapBefore: 12,
          gapAfter: 6,
        ),
      )
      ..add(_PdfTable(_approvalGateRows(document)))
      ..add(
        const _PdfText(
          'Validation Checklist',
          size: 13.5,
          bold: true,
          gapBefore: 12,
          gapAfter: 6,
        ),
      )
      ..add(_PdfTable(_validationChecklistRows(document)))
      ..add(
        const _PdfText(
          'Customer Handoff Scorecard',
          size: 13.5,
          bold: true,
          gapBefore: 12,
          gapAfter: 6,
        ),
      )
      ..add(_PdfTable(_handoffScorecardRows(document)))
      ..add(
        const _PdfText(
          'Decision Log',
          size: 13.5,
          bold: true,
          gapBefore: 12,
          gapAfter: 6,
        ),
      )
      ..add(_PdfTable(_decisionLogRows(document)))
      ..add(
        const _PdfText(
          'Decision Sign-Off',
          size: 13.5,
          bold: true,
          gapBefore: 12,
          gapAfter: 6,
        ),
      )
      ..add(_PdfTable(_decisionSignOffRows(document)));
    if (document.assumptions.isNotEmpty) {
      items.add(
        const _PdfText(
          'Assumptions',
          size: 13.5,
          bold: true,
          gapBefore: 12,
          gapAfter: 6,
        ),
      );
      for (final assumption in document.assumptions) {
        items.add(_PdfText('- $assumption', size: 10.3, indent: 16));
      }
    }
    if (document.citations.isNotEmpty) {
      items.add(
        const _PdfText(
          'Sources / Evidence',
          size: 13.5,
          bold: true,
          gapBefore: 12,
          gapAfter: 6,
        ),
      );
      for (final citation in document.citations) {
        items.add(_PdfText('- $citation', size: 9.8, indent: 16));
      }
    }
    return items;
  }

  List<_PdfOutlineEntry> _outlineEntries(ArtifactDocument document) {
    final entries = <_PdfOutlineEntry>[
      const _PdfOutlineEntry('Report Overview'),
      const _PdfOutlineEntry('Lead Decision Callout'),
      const _PdfOutlineEntry('Executive Decision Brief'),
      const _PdfOutlineEntry('Recommendation Summary'),
      const _PdfOutlineEntry('Risk & Assumption Register'),
      const _PdfOutlineEntry('Next-Step Action Plan'),
      const _PdfOutlineEntry('Executive Summary'),
      for (final section in document.sections.take(8))
        _PdfOutlineEntry(section.title),
      if (document.tables.isNotEmpty) const _PdfOutlineEntry('Data Tables'),
      const _PdfOutlineEntry('Stakeholder Readout'),
      const _PdfOutlineEntry('Evidence Confidence Matrix'),
      const _PdfOutlineEntry('Approval Gates'),
      const _PdfOutlineEntry('Validation Checklist'),
      const _PdfOutlineEntry('Customer Handoff Scorecard'),
      const _PdfOutlineEntry('Decision Log'),
      const _PdfOutlineEntry('Decision Sign-Off'),
      if (document.assumptions.isNotEmpty)
        const _PdfOutlineEntry('Assumptions'),
      if (document.citations.isNotEmpty)
        const _PdfOutlineEntry('Sources / Evidence'),
    ];
    final seen = <String>{};
    return [
      for (final entry in entries)
        if (seen.add(entry.title.toLowerCase())) entry,
    ];
  }

  int _pageIdForOutlineEntry(
    String title,
    List<List<_PlacedPdfItem>> pages,
    List<int> pageIds,
  ) {
    for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final page = pages[pageIndex];
      final hasTitle = page.any((placed) {
        final item = placed.item;
        return item is _PdfText && item.text.trim() == title;
      });
      if (hasTitle) return pageIds[pageIndex];
    }
    return pageIds.first;
  }

  List<String> _documentMap(ArtifactDocument document) {
    return [
      'Executive Decision Brief - decision and handoff guidance',
      'Recommendation Summary - recommended path and dependencies',
      'Risk & Assumption Register - risks, caveats, and evidence gaps',
      'Next-Step Action Plan - owners, validation, and expected outputs',
      'Executive Summary - decision-ready overview',
      for (final section in document.sections)
        '${section.title} - ${section.bullets.isNotEmpty ? '${section.bullets.length} key point${section.bullets.length == 1 ? '' : 's'}' : 'narrative section'}',
      if (document.tables.isNotEmpty)
        'Data Tables - ${document.tables.length} structured table${document.tables.length == 1 ? '' : 's'}',
      'Stakeholder Readout - audience and owner-specific handoff needs',
      'Evidence Confidence Matrix - evidence status, confidence, and gaps',
      'Approval Gates - final review checkpoints before handoff',
      'Validation Checklist - quality and handoff readiness checks',
      'Customer Handoff Scorecard - readiness score, status signals, and owner follow-up',
      'Decision Log - decision, owner, evidence, and next-action record',
      'Decision Sign-Off - final approval fields, signature owners, and dates',
      if (document.assumptions.isNotEmpty)
        'Assumptions - ${document.assumptions.length} captured caveat${document.assumptions.length == 1 ? '' : 's'}',
      if (document.citations.isNotEmpty)
        'Sources / Evidence - ${document.citations.length} source item${document.citations.length == 1 ? '' : 's'}',
    ];
  }

  List<List<String>> _executiveDecisionBriefRows(ArtifactDocument document) {
    final recommendation = _firstMatchingBullet(document, [
      'recommend',
      'next',
      'implement',
      'should',
      'use',
    ]);
    final risk = _firstMatchingBullet(document, [
      'risk',
      'block',
      'gap',
      'unknown',
      'validate',
      'confirm',
    ]);
    return [
      ['Decision Area', 'Brief'],
      ['Primary outcome', _firstSentence(document.summary)],
      [
        'Recommendation focus',
        recommendation ?? _sectionTitleFallback(document),
      ],
      [
        'Evidence included',
        document.citations.isEmpty
            ? 'No cited source evidence included yet.'
            : '${document.citations.length} source item${document.citations.length == 1 ? '' : 's'} included.',
      ],
      [
        'Open risks',
        risk ??
            (document.assumptions.isEmpty
                ? 'No explicit risks or assumptions were provided.'
                : document.assumptions.first),
      ],
      ['Required follow-up', _followUpGuidance(document)],
    ];
  }

  List<List<String>> _leadDecisionCalloutRows(ArtifactDocument document) {
    return [
      ['Decision Field', 'Customer Handoff Detail'],
      ['Decision ask', _decisionAskFor(document)],
      ['Owner', _decisionOwner(document)],
      ['Handoff status', _handoffStatus(document)],
      ['Review path', _reviewPathFor(document)],
    ];
  }

  List<List<String>> _recommendationSummaryRows(ArtifactDocument document) {
    final recommendation = _firstMatchingBullet(document, [
      'recommend',
      'solution',
      'architecture',
      'proposal',
      'should',
    ]);
    final rationale = _firstMatchingBullet(document, [
      'because',
      'rationale',
      'value',
      'impact',
      'benefit',
    ]);
    final dependency = _firstMatchingBullet(document, [
      'depend',
      'require',
      'prereq',
      'license',
      'source',
      'data',
    ]);
    return [
      ['Field', 'Recommendation Detail'],
      [
        'Recommended path',
        recommendation ??
            'Use this PDF as a review artifact, then confirm the preferred implementation path with stakeholders.',
      ],
      [
        'Rationale',
        rationale ??
            'Validate the recommendation against customer goals, constraints, source data, and implementation risk.',
      ],
      [
        'Dependencies',
        dependency ??
            'Confirm source evidence, ownership, timeline, access, licensing, and acceptance criteria.',
      ],
      ['Decision owner', _decisionOwner(document)],
    ];
  }

  List<List<String>> _riskRegisterRows(ArtifactDocument document) {
    final rows = <List<String>>[
      ['Item', 'Type', 'Impact', 'Mitigation / Evidence Needed'],
    ];
    final riskBullets = _matchingBullets(document, [
      'risk',
      'block',
      'gap',
      'unknown',
      'constraint',
      'unsupported',
    ]);
    for (final risk in riskBullets.take(4)) {
      rows.add([
        _truncate(risk, 90),
        'Risk',
        'Can affect decision confidence or implementation readiness.',
        'Validate with owner, source data, or technical evidence.',
      ]);
    }
    for (final assumption in document.assumptions.take(4)) {
      rows.add([
        _truncate(assumption, 90),
        'Assumption',
        'If incorrect, the recommendation may need revision.',
        'Confirm with customer or authoritative source before handoff.',
      ]);
    }
    if (document.citations.isEmpty) {
      rows.add([
        'No cited evidence included',
        'Evidence gap',
        'Limits confidence for final customer handoff.',
        'Attach source URLs, checked dates, or workshop evidence.',
      ]);
    }
    if (rows.length == 1) {
      rows.add([
        'No explicit risks were provided',
        'Review item',
        'Unknown risks may still exist.',
        'Run stakeholder review and capture assumptions before final approval.',
      ]);
    }
    return rows;
  }

  List<List<String>> _nextStepRows(ArtifactDocument document) {
    final explicit = _matchingBullets(document, [
      'next',
      'phase',
      'action',
      'implement',
      'validate',
      'verify',
      'confirm',
    ]).take(5).toList(growable: false);
    final actions = explicit.isEmpty
        ? [
            'Review the recommendation with stakeholders.',
            'Confirm assumptions, source evidence, and acceptance criteria.',
            if (document.tables.isNotEmpty)
              'Validate the ${document.tables.length} supporting data table${document.tables.length == 1 ? '' : 's'}.',
            'Approve or revise the implementation path.',
          ]
        : explicit;
    return [
      ['Step', 'Action', 'Owner', 'Expected Output'],
      for (var i = 0; i < actions.length; i++)
        [
          '${i + 1}',
          _truncate(actions[i], 110),
          i == 0 ? 'Project owner' : 'Assigned stakeholder',
          i == actions.length - 1
              ? 'Decision-ready handoff or implementation request'
              : 'Validated input for the next step',
        ],
    ];
  }

  List<List<String>> _stakeholderReadoutRows(ArtifactDocument document) {
    return [
      ['Audience', 'What They Need From This Report'],
      [
        'Executive sponsor',
        'Business outcome, decision required, risk posture, and investment rationale.',
      ],
      [
        _decisionOwner(document),
        'Technical feasibility, implementation path, evidence quality, and validation gates.',
      ],
      [
        'Implementation owner',
        'Approved scope, dependencies, next steps, owners, and acceptance criteria.',
      ],
      [
        'Evidence reviewer',
        document.citations.isEmpty
            ? 'Source evidence must be attached before final customer handoff.'
            : 'Review ${document.citations.length} source item${document.citations.length == 1 ? '' : 's'} and confirm freshness.',
      ],
    ];
  }

  List<List<String>> _evidenceConfidenceRows(ArtifactDocument document) {
    final recommendation = _firstMatchingBullet(document, [
      'recommend',
      'solution',
      'architecture',
      'proposal',
      'should',
    ]);
    final rows = <List<String>>[
      ['Evidence Area', 'Current Signal', 'Confidence', 'Required Validation'],
      [
        'Executive summary',
        document.summary.trim().isEmpty ? 'Missing' : 'Included',
        document.summary.trim().isEmpty ? 'Low' : 'Medium',
        document.summary.trim().isEmpty
            ? 'Add a concise customer-facing summary.'
            : 'Confirm language with the business owner.',
      ],
      [
        'Recommendations',
        recommendation ?? 'No explicit recommendation detected',
        recommendation == null ? 'Low' : 'Medium',
        'Validate against requirements, constraints, and customer priorities.',
      ],
      [
        'Assumptions',
        document.assumptions.isEmpty
            ? 'No explicit assumptions listed'
            : '${document.assumptions.length} assumption${document.assumptions.length == 1 ? '' : 's'} listed',
        document.assumptions.isEmpty ? 'Low' : 'Medium',
        'Confirm assumptions with the accountable stakeholder.',
      ],
      [
        'Sources / citations',
        document.citations.isEmpty
            ? 'No cited evidence included'
            : '${document.citations.length} source item${document.citations.length == 1 ? '' : 's'} included',
        document.citations.isEmpty ? 'Low' : 'Medium',
        'Verify freshness, authority, and citation relevance.',
      ],
    ];
    if (document.tables.isNotEmpty) {
      rows.add([
        'Structured data',
        '${document.tables.length} table${document.tables.length == 1 ? '' : 's'} included',
        'Medium',
        'Validate source data, units, dates, and row completeness.',
      ]);
    }
    return rows;
  }

  List<List<String>> _approvalGateRows(ArtifactDocument document) {
    return [
      ['Gate', 'Required Evidence', 'Suggested Owner', 'Status'],
      [
        'Scope approval',
        'Confirmed goals, constraints, exclusions, and success criteria.',
        _decisionOwner(document),
        document.sections.isEmpty ? 'Needs input' : 'Ready for review',
      ],
      [
        'Evidence approval',
        'Source-backed claims, checked dates, and unresolved gaps.',
        'Evidence reviewer',
        document.citations.isEmpty ? 'Needs sources' : 'Ready for review',
      ],
      [
        'Risk approval',
        'Known risks, assumptions, mitigations, and owner acceptance.',
        'Project owner',
        document.assumptions.isEmpty ? 'Needs assumptions' : 'Ready for review',
      ],
      [
        'Implementation approval',
        'Approved next steps, owner, timeline, and verification plan.',
        'Implementation owner',
        _nextStepRows(document).length <= 1 ? 'Needs plan' : 'Ready',
      ],
    ];
  }

  List<List<String>> _validationChecklistRows(ArtifactDocument document) {
    return [
      ['Check', 'Status'],
      [
        'Executive summary',
        document.summary.trim().isEmpty ? 'Missing' : 'Included',
      ],
      [
        'Structured sections',
        document.sections.isEmpty
            ? 'Missing'
            : '${document.sections.length} section${document.sections.length == 1 ? '' : 's'}',
      ],
      [
        'Data tables',
        document.tables.isEmpty
            ? 'No structured tables included'
            : '${document.tables.length} table${document.tables.length == 1 ? '' : 's'}',
      ],
      [
        'Assumptions',
        document.assumptions.isEmpty
            ? 'No assumptions listed'
            : '${document.assumptions.length} assumption${document.assumptions.length == 1 ? '' : 's'} listed',
      ],
      [
        'Evidence / citations',
        document.citations.isEmpty
            ? 'No cited evidence included'
            : '${document.citations.length} source item${document.citations.length == 1 ? '' : 's'} included',
      ],
      ['Handoff readiness', _handoffStatus(document)],
    ];
  }

  List<List<String>> _handoffScorecardRows(ArtifactDocument document) {
    return [
      ['Area', 'Status', 'Score', 'Required Follow-Up'],
      [
        'Narrative',
        document.summary.trim().isEmpty ? 'Missing' : 'Ready for review',
        document.summary.trim().isEmpty ? '0' : '20',
        document.summary.trim().isEmpty
            ? 'Add executive summary.'
            : 'Confirm wording with stakeholder.',
      ],
      [
        'Structured content',
        document.sections.isEmpty
            ? 'Missing'
            : '${document.sections.length} section${document.sections.length == 1 ? '' : 's'}',
        document.sections.isEmpty ? '0' : '20',
        document.sections.isEmpty
            ? 'Add report sections.'
            : 'Confirm section order and owner.',
      ],
      [
        'Evidence',
        document.citations.isEmpty
            ? 'Needs sources'
            : '${document.citations.length} source item${document.citations.length == 1 ? '' : 's'}',
        document.citations.isEmpty ? '0' : '20',
        document.citations.isEmpty
            ? 'Attach citations/source evidence.'
            : 'Verify freshness and authority.',
      ],
      [
        'Assumptions',
        document.assumptions.isEmpty
            ? 'Needs assumptions'
            : '${document.assumptions.length} assumption${document.assumptions.length == 1 ? '' : 's'}',
        document.assumptions.isEmpty ? '0' : '20',
        document.assumptions.isEmpty
            ? 'Capture unknowns and owner confirmation.'
            : 'Confirm assumptions with accountable owner.',
      ],
      [
        'Data support',
        document.tables.isEmpty
            ? 'No structured tables'
            : '${document.tables.length} table${document.tables.length == 1 ? '' : 's'}',
        document.tables.isEmpty ? '10' : '20',
        document.tables.isEmpty
            ? 'Attach source data if needed.'
            : 'Validate source data, units, and dates.',
      ],
    ];
  }

  List<List<String>> _decisionLogRows(ArtifactDocument document) {
    final recommendation = _firstMatchingBullet(document, [
      'recommend',
      'solution',
      'architecture',
      'proposal',
      'should',
    ]);
    final risk = _firstMatchingBullet(document, [
      'risk',
      'block',
      'gap',
      'unknown',
      'validate',
      'confirm',
    ]);
    final next = _firstMatchingBullet(document, [
      'next',
      'phase',
      'action',
      'implement',
      'verify',
      'confirm',
    ]);
    return [
      ['Decision', 'Owner', 'Evidence Signal', 'Next Action'],
      [
        'Approve report direction',
        _decisionOwner(document),
        recommendation ?? _firstSentence(document.summary),
        _decisionAskFor(document),
      ],
      [
        'Validate evidence',
        'Evidence reviewer',
        document.citations.isEmpty
            ? 'No cited evidence included'
            : '${document.citations.length} source item${document.citations.length == 1 ? '' : 's'} attached',
        document.citations.isEmpty
            ? 'Attach source evidence before final handoff.'
            : 'Check freshness and source authority.',
      ],
      [
        'Resolve assumptions',
        'Project owner',
        document.assumptions.isEmpty
            ? 'No explicit assumptions listed'
            : '${document.assumptions.length} assumption${document.assumptions.length == 1 ? '' : 's'} documented',
        document.assumptions.isEmpty
            ? 'Capture assumptions and unknowns.'
            : 'Confirm assumptions with accountable stakeholder.',
      ],
      [
        'Move to execution',
        'Implementation owner',
        risk ?? 'No explicit blocking risk detected',
        next ?? 'Assign owner, date, and verification criteria.',
      ],
    ];
  }

  List<List<String>> _decisionSignOffRows(ArtifactDocument document) {
    return [
      ['Approval Field', 'Owner', 'Sign-Off Status', 'Signature / Date'],
      [
        'Decision owner approval',
        _decisionOwner(document),
        _handoffStatus(document),
        'Signature: __________   Date: __________',
      ],
      [
        'Evidence approval',
        'Evidence reviewer',
        document.citations.isEmpty
            ? 'Needs source evidence'
            : 'Ready for evidence sign-off',
        'Signature: __________   Date: __________',
      ],
      [
        'Risk / assumption approval',
        'Project owner',
        document.assumptions.isEmpty
            ? 'Needs assumption review'
            : 'Ready for risk sign-off',
        'Signature: __________   Date: __________',
      ],
      [
        'Handoff approval',
        'Implementation owner',
        _nextStepRows(document).length <= 1
            ? 'Needs next-step owner'
            : 'Ready for handoff approval',
        'Signature: __________   Date: __________',
      ],
    ];
  }

  int _handoffScoreFor(List<List<String>> rows) {
    var total = 0;
    for (final row in rows) {
      if (row.length < 3) continue;
      total += int.tryParse(row[2]) ?? 0;
    }
    return total.clamp(0, 100);
  }

  String _handoffReadinessLevelFor(int score) {
    if (score >= 90) return 'Customer handoff ready';
    if (score >= 70) return 'Review-ready draft';
    if (score >= 45) return 'Needs evidence before handoff';
    return 'Needs more content';
  }

  List<String> _keywords(ArtifactDocument document) {
    final keywords = <String>{
      'artifact',
      'report',
      'CircuitCode',
      'enterprise',
      'PDF',
    };
    final combined = [
      document.title,
      document.summary,
      for (final section in document.sections) section.title,
    ].join(' ').toLowerCase();
    if (combined.contains('architecture')) keywords.add('architecture');
    if (combined.contains('business')) keywords.add('business');
    if (combined.contains('implementation')) keywords.add('implementation');
    if (combined.contains('evidence')) keywords.add('evidence');
    if (combined.contains('lifecycle')) keywords.add('lifecycle');
    if (combined.contains('sizing')) keywords.add('sizing');
    return keywords.toList(growable: false);
  }

  String _firstSentence(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'No executive summary was provided.';
    final match = RegExp(r'^(.+?[.!?])(?:\s|$)').firstMatch(trimmed);
    return (match?.group(1) ?? trimmed).trim();
  }

  String? _firstMatchingBullet(ArtifactDocument document, List<String> terms) {
    final matches = _matchingBullets(document, terms);
    return matches.isEmpty ? null : matches.first;
  }

  List<String> _matchingBullets(ArtifactDocument document, List<String> terms) {
    final loweredTerms = terms.map((term) => term.toLowerCase()).toList();
    final matches = <String>[];
    for (final section in document.sections) {
      final titleMatches = loweredTerms.any(
        section.title.toLowerCase().contains,
      );
      for (final bullet in section.bullets) {
        final normalized = bullet.toLowerCase();
        if (titleMatches || loweredTerms.any(normalized.contains)) {
          matches.add(bullet);
        }
      }
      for (final paragraph in _paragraphs(section.body).take(3)) {
        final normalized = paragraph.toLowerCase();
        if (titleMatches || loweredTerms.any(normalized.contains)) {
          matches.add(paragraph);
        }
      }
    }
    return matches;
  }

  String _sectionTitleFallback(ArtifactDocument document) {
    if (document.sections.isEmpty) return 'No recommendation section provided.';
    return 'Review ${document.sections.first.title}.';
  }

  String _followUpGuidance(ArtifactDocument document) {
    final explicitNextStep = _firstMatchingBullet(document, [
      'next',
      'follow',
      'workshop',
      'validate',
      'confirm',
    ]);
    if (explicitNextStep != null) return explicitNextStep;
    if (document.assumptions.isNotEmpty) {
      return 'Validate assumptions with the customer before final handoff.';
    }
    if (document.citations.isEmpty) {
      return 'Add source evidence before using this as a final customer handoff.';
    }
    return 'Review with stakeholders and confirm final action owners.';
  }

  String _decisionOwner(ArtifactDocument document) {
    final reportType = _reportTypeFor(document);
    if (reportType == 'Architecture report') {
      return 'Architecture owner / customer sponsor';
    }
    if (reportType == 'Business use case brief') return 'Business sponsor';
    if (reportType == 'Evidence pack') return 'Evidence reviewer';
    if (reportType == 'Implementation plan') return 'Implementation owner';
    final combined = [
      document.title,
      document.summary,
      for (final section in document.sections) section.title,
    ].join(' ').toLowerCase();
    if (combined.contains('architecture')) {
      return 'Architecture owner / customer sponsor';
    }
    if (combined.contains('business')) return 'Business sponsor';
    if (combined.contains('evidence')) return 'Evidence reviewer';
    if (combined.contains('implementation')) return 'Implementation owner';
    return 'Customer stakeholder';
  }

  String _reportTypeFor(ArtifactDocument document) {
    final combined = [
      document.title,
      document.summary,
      for (final section in document.sections) section.title,
      '${document.metadata['prompt'] ?? ''}',
    ].join(' ').toLowerCase();
    if (combined.contains('business') || combined.contains('use case')) {
      return 'Business use case brief';
    }
    if (combined.contains('evidence') || combined.contains('claim')) {
      return 'Evidence pack';
    }
    if (combined.contains('architecture') || combined.contains('review')) {
      return 'Architecture report';
    }
    if (combined.contains('findings') && combined.contains('recommendations')) {
      return 'Architecture report';
    }
    if (combined.contains('campus') && combined.contains('handoff')) {
      return 'Architecture report';
    }
    if (combined.contains('implementation') || combined.contains('plan')) {
      return 'Implementation plan';
    }
    if (combined.contains('change') || combined.contains('diff')) {
      return 'Change summary report';
    }
    return 'Enterprise report';
  }

  String _audienceFor(ArtifactDocument document) {
    final combined = [
      document.title,
      document.summary,
      for (final section in document.sections) section.title,
      '${document.metadata['prompt'] ?? ''}',
    ].join(' ').toLowerCase();
    if (combined.contains('architecture') || combined.contains('technical')) {
      return 'Architecture reviewers';
    }
    if (combined.contains('findings') && combined.contains('recommendations')) {
      return 'Architecture reviewers';
    }
    if (combined.contains('campus') && combined.contains('handoff')) {
      return 'Architecture reviewers';
    }
    if (combined.contains('customer') ||
        combined.contains('proposal') ||
        combined.contains('client')) {
      return 'Customer stakeholders';
    }
    if (combined.contains('executive') || combined.contains('leadership')) {
      return 'Executive stakeholders';
    }
    if (combined.contains('business') || combined.contains('use case')) {
      return 'Business stakeholders';
    }
    if (combined.contains('evidence')) return 'Evidence reviewers';
    return 'Project stakeholders';
  }

  String _reportPurposeFor(ArtifactDocument document) {
    final type = _reportTypeFor(document);
    return switch (type) {
      'Business use case brief' => 'Align business value and next actions',
      'Evidence pack' => 'Validate claims and source confidence',
      'Implementation plan' => 'Guide execution and verification',
      'Architecture report' => 'Review findings, risks, and recommendations',
      'Change summary report' => 'Document completed changes and evidence',
      _ => 'Inform stakeholder review',
    };
  }

  List<String> _readinessSignals(ArtifactDocument document) {
    return [
      'Decision brief',
      'Recommendation summary',
      'Risk register',
      'Next steps',
      'Validation checklist',
      'Customer handoff scorecard',
      'Decision log',
      'Decision sign-off',
      if (document.tables.isNotEmpty) 'Data tables',
      if (document.assumptions.isNotEmpty) 'Assumptions',
      if (document.citations.isNotEmpty) 'Sources',
      if (document.citations.isEmpty) 'Evidence gaps',
    ];
  }

  List<String> _documentPartsFor(ArtifactDocument document) {
    return [
      'Executive decision brief',
      'Lead decision callout',
      'Recommendation summary',
      'Risk register',
      'Next-step action plan',
      'Document map',
      'Evidence confidence matrix',
      'Approval gates',
      'Validation checklist',
      'Customer handoff scorecard',
      'Decision log',
      'Decision sign-off',
      if (document.tables.isNotEmpty) 'Data tables',
      if (document.assumptions.isNotEmpty) 'Assumptions appendix',
      if (document.citations.isNotEmpty) 'Sources appendix',
    ];
  }

  List<String> _validationGapsFor(ArtifactDocument document) {
    return [
      if (document.summary.trim().isEmpty) 'Executive summary missing',
      if (document.sections.isEmpty) 'Report sections missing',
      if (document.assumptions.isEmpty) 'Assumptions need confirmation',
      if (document.citations.isEmpty) 'Sources need validation',
    ];
  }

  String _appendixCoverageFor(ArtifactDocument document) {
    final parts = [
      if (document.assumptions.isNotEmpty)
        '${document.assumptions.length} assumption${document.assumptions.length == 1 ? '' : 's'}',
      if (document.citations.isNotEmpty)
        '${document.citations.length} source item${document.citations.length == 1 ? '' : 's'}',
    ];
    if (parts.isEmpty) return 'No appendices attached';
    return '${parts.join(', ')} in appendices';
  }

  int _evidenceGapCount(ArtifactDocument document) {
    var gaps = 0;
    if (document.summary.trim().isEmpty) gaps++;
    if (document.sections.isEmpty) gaps++;
    if (document.assumptions.isEmpty) gaps++;
    if (document.citations.isEmpty) gaps++;
    return gaps;
  }

  bool _hasCustomerReadyPackage(ArtifactDocument document) {
    return document.summary.trim().isNotEmpty &&
        document.sections.isNotEmpty &&
        document.assumptions.isNotEmpty &&
        document.citations.isNotEmpty;
  }

  String _decisionAskFor(ArtifactDocument document) {
    final explicit = _firstMatchingBullet(document, [
      'approve',
      'decision',
      'next',
      'action',
    ]);
    if (explicit != null) return _truncate(explicit, 140);
    return switch (_reportTypeFor(document)) {
      'Business use case brief' =>
        'Confirm priority use cases, expected value, and account-team next steps.',
      'Evidence pack' =>
        'Review source authority, freshness, confidence, and unsupported claims.',
      'Implementation plan' =>
        'Approve scope, owners, verification gates, and the next implementation step.',
      'Architecture report' =>
        'Review findings, confirm assumptions, and approve the recommended architecture path.',
      'Change summary report' =>
        'Review changed files, verification evidence, and any remaining follow-up.',
      _ =>
        'Review the PDF, confirm assumptions, and approve the next stakeholder action.',
    };
  }

  String _reviewPathFor(ArtifactDocument document) {
    return switch (_reportTypeFor(document)) {
      'Business use case brief' =>
        'Executive sponsor review -> account-team discovery -> value validation',
      'Evidence pack' =>
        'Claim review -> source freshness check -> confidence sign-off',
      'Implementation plan' =>
        'Scope review -> owner assignment -> verification approval',
      'Architecture report' =>
        'Architecture review -> risk validation -> implementation decision',
      'Change summary report' =>
        'Diff review -> verification evidence -> closeout approval',
      _ => 'Stakeholder review -> evidence validation -> final handoff',
    };
  }

  String _handoffStatus(ArtifactDocument document) {
    if (document.summary.trim().isEmpty || document.sections.isEmpty) {
      return 'Needs more narrative before handoff';
    }
    if (document.citations.isEmpty || document.assumptions.isEmpty) {
      return 'Draft - validate assumptions and evidence';
    }
    return 'Ready for stakeholder review';
  }

  Iterable<String> _paragraphs(String body) {
    return body
        .split(RegExp(r'\n\s*\n'))
        .map((paragraph) => paragraph.replaceAll('\n', ' ').trim())
        .where((paragraph) => paragraph.isNotEmpty);
  }

  List<List<_PlacedPdfItem>> _paginate(List<_PdfItem> source) {
    final pages = <List<_PlacedPdfItem>>[];
    var page = <_PlacedPdfItem>[];
    var y = 716.0;
    for (final item in source) {
      final parts = item is _PdfText ? _wrap(item) : [item];
      for (final part in parts) {
        final candidate = part.copyWith(
          gapBefore: identical(part, parts.first) ? null : 0,
        );
        final needed =
            candidate.gapBefore + candidate.height + candidate.gapAfter;
        if (y - needed < 76 && page.isNotEmpty) {
          pages.add(page);
          page = <_PlacedPdfItem>[];
          y = 716;
        }
        y -= candidate.gapBefore;
        page.add(_PlacedPdfItem(candidate, y));
        y -= candidate.height + candidate.gapAfter;
      }
    }
    if (page.isNotEmpty) pages.add(page);
    return pages.isEmpty ? [[]] : pages;
  }

  List<_PdfText> _wrap(_PdfText line) {
    final maxChars = ((91 - (line.indent / 5)) * (10.5 / line.size))
        .clamp(34, 116)
        .floor();
    if (line.text.length <= maxChars) return [line];
    final words = line.text.split(RegExp(r'\s+'));
    final wrapped = <_PdfText>[];
    var current = '';
    for (final word in words) {
      final candidate = current.isEmpty ? word : '$current $word';
      if (candidate.length > maxChars && current.isNotEmpty) {
        wrapped.add(line.copyWith(text: current));
        current = word;
      } else {
        current = candidate;
      }
    }
    if (current.isNotEmpty) wrapped.add(line.copyWith(text: current));
    return wrapped;
  }

  String _contentStream(
    List<_PlacedPdfItem> items, {
    required ArtifactDocument document,
    required int pageNumber,
    required int pageCount,
  }) {
    final buffer = StringBuffer()
      ..writeln('0.98 0.98 0.97 rg 0 0 612 792 re f')
      ..writeln('0.20 0.56 0.53 rg 0 0 8 792 re f')
      ..writeln('0.12 0.12 0.12 rg');
    _drawHeader(buffer, document, pageNumber);
    for (final placed in items) {
      final item = placed.item;
      if (item is _PdfText) {
        _drawText(buffer, item, placed.y);
      } else if (item is _PdfTable) {
        _drawTable(buffer, item, placed.y);
      }
    }
    _drawFooter(buffer, pageNumber, pageCount);
    return buffer.toString();
  }

  void _drawHeader(StringBuffer buffer, ArtifactDocument document, int page) {
    buffer
      ..writeln('0.92 0.93 0.92 rg 54 744 504 1 re f')
      ..writeln(
        'BT /F1 8 Tf 0.35 0.37 0.40 rg 54 758 Td (${_pdfText('CircuitCode generated artifact')}) Tj ET',
      );
    if (page > 1) {
      buffer.writeln(
        'BT /F2 8 Tf 0.35 0.37 0.40 rg 378 758 Td (${_pdfText(_truncate(document.title, 44))}) Tj ET',
      );
    }
  }

  void _drawFooter(StringBuffer buffer, int pageNumber, int pageCount) {
    buffer
      ..writeln('0.90 0.91 0.91 rg 54 52 504 1 re f')
      ..writeln(
        'BT /F1 8 Tf 0.43 0.45 0.48 rg 54 34 Td (${_pdfText('CircuitCode - Generated artifact')}) Tj ET',
      )
      ..writeln(
        'BT /F1 8 Tf 0.43 0.45 0.48 rg 500 34 Td (${_pdfText('Page $pageNumber of $pageCount')}) Tj ET',
      );
  }

  void _drawText(StringBuffer buffer, _PdfText line, double y) {
    final font = line.bold
        ? 'F2'
        : line.mono
        ? 'F3'
        : 'F1';
    final color = switch (line.color) {
      _PdfColor.body => '0.10 0.11 0.13',
      _PdfColor.muted => '0.42 0.45 0.50',
    };
    final x = 54 + line.indent;
    buffer.writeln(
      'BT /$font ${line.size.toStringAsFixed(1)} Tf $color rg '
      '$x ${y.toStringAsFixed(1)} Td (${_pdfText(line.text)}) Tj ET',
    );
  }

  void _drawTable(StringBuffer buffer, _PdfTable table, double y) {
    if (table.rows.isEmpty) return;
    final columnCount = table.columnCount;
    final widths = table.columnWidths;
    const rowHeight = 22.0;
    var currentY = y;
    for (var rowIndex = 0; rowIndex < table.rows.length; rowIndex++) {
      final row = table.rows[rowIndex];
      var x = 54.0;
      for (var column = 0; column < columnCount; column++) {
        final width = widths[column];
        final fill = rowIndex == 0
            ? '0.88 0.91 0.92'
            : rowIndex.isEven
            ? '0.97 0.97 0.96'
            : '1 1 1';
        buffer
          ..writeln(
            '$fill rg ${x.toStringAsFixed(1)} ${(currentY - rowHeight + 4).toStringAsFixed(1)} ${width.toStringAsFixed(1)} $rowHeight re f',
          )
          ..writeln(
            '0.78 0.81 0.84 RG ${x.toStringAsFixed(1)} ${(currentY - rowHeight + 4).toStringAsFixed(1)} ${width.toStringAsFixed(1)} $rowHeight re S',
          );
        final text = column < row.length ? row[column] : '';
        buffer.writeln(
          'BT /${rowIndex == 0 ? 'F2' : 'F1'} 8.2 Tf 0.11 0.12 0.14 rg '
          '${(x + 5).toStringAsFixed(1)} ${(currentY - 10).toStringAsFixed(1)} Td (${_pdfText(_truncate(text, (width / 5.2).floor()))}) Tj ET',
        );
        x += width;
      }
      currentY -= rowHeight;
    }
  }

  Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

  String _pdfText(String value) {
    return value
        .replaceAll('\\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)')
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ');
  }

  String _truncate(String value, int max) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (max < 6 || normalized.length <= max) return normalized;
    return '${normalized.substring(0, max - 3)}...';
  }
}

enum _PdfColor { body, muted }

abstract class _PdfItem {
  double get gapBefore;
  double get gapAfter;
  double get height;

  _PdfItem copyWith({double? gapBefore});
}

class _PdfText implements _PdfItem {
  final String text;
  final double size;
  final bool bold;
  final bool mono;
  final double indent;
  @override
  final double gapBefore;
  @override
  final double gapAfter;
  final _PdfColor color;

  const _PdfText(
    this.text, {
    required this.size,
    this.bold = false,
    this.mono = false,
    this.indent = 0,
    this.gapBefore = 3,
    this.gapAfter = 3,
    this.color = _PdfColor.body,
  });

  @override
  double get height => size + 5;

  @override
  _PdfText copyWith({String? text, double? gapBefore}) {
    return _PdfText(
      text ?? this.text,
      size: size,
      bold: bold,
      mono: mono,
      indent: indent,
      gapBefore: gapBefore ?? this.gapBefore,
      gapAfter: gapAfter,
      color: color,
    );
  }
}

class _PdfTable implements _PdfItem {
  final List<List<String>> rows;

  const _PdfTable(this.rows);

  int get columnCount => rows
      .fold<int>(0, (max, row) => row.length > max ? row.length : max)
      .clamp(1, 6);

  List<double> get columnWidths {
    final weights = List<int>.filled(columnCount, 4);
    for (final row in rows.take(10)) {
      for (var i = 0; i < columnCount; i++) {
        final value = i < row.length ? row[i] : '';
        weights[i] += value.length.clamp(1, 34);
      }
    }
    final total = math.max(
      1,
      weights.fold<int>(0, (sum, value) => sum + value),
    );
    var remaining = 504.0;
    final widths = <double>[];
    for (var i = 0; i < columnCount; i++) {
      final width = i == columnCount - 1
          ? remaining
          : ((504 * weights[i]) / total).clamp(58.0, 182.0);
      widths.add(width);
      remaining -= width;
    }
    return widths;
  }

  @override
  double get gapBefore => 2;

  @override
  double get gapAfter => 9;

  @override
  double get height => rows.length * 22.0;

  @override
  _PdfTable copyWith({double? gapBefore}) => this;
}

class _PlacedPdfItem {
  final _PdfItem item;
  final double y;

  const _PlacedPdfItem(this.item, this.y);
}

class _PdfOutlineEntry {
  final String title;

  const _PdfOutlineEntry(this.title);
}
