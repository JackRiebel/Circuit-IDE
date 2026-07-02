import 'dart:convert';
import 'dart:typed_data';

import '../models/artifact_document.dart';

class DocxArtifactRenderer {
  const DocxArtifactRenderer();

  List<List<String>> previewRowsFor(ArtifactDocument document) {
    return [
      ['Section', 'Type', 'Items'],
      ['1', 'Executive Decision Brief', '5'],
      ['2', 'Recommendation Summary', '4'],
      [
        '3',
        'Risk & Assumption Register',
        '${_riskRegisterRows(document).length}',
      ],
      ['4', 'Next-Step Action Plan', '${_nextStepRows(document).length}'],
      ['5', 'Executive Summary', document.summary.trim().isEmpty ? '0' : '1'],
      for (var i = 0; i < document.sections.length; i++)
        [
          '${i + 6}',
          document.sections[i].title,
          '${document.sections[i].bullets.length + (document.sections[i].body.trim().isEmpty ? 0 : 1)}',
        ],
      if (document.tables.isNotEmpty)
        [
          '${document.sections.length + 6}',
          'Data Tables',
          '${document.tables.length}',
        ],
      ['${document.sections.length + 7}', 'Stakeholder Readout', '4'],
      [
        '${document.sections.length + 8}',
        'Evidence Confidence Matrix',
        '${_evidenceConfidenceRows(document).length}',
      ],
      ['${document.sections.length + 9}', 'Approval Gates', '4'],
      ['${document.sections.length + 10}', 'Validation Checklist', '5'],
      [
        '${document.sections.length + 11}',
        'Customer Handoff Scorecard',
        '${_handoffScorecardRows(document).length}',
      ],
      [
        '${document.sections.length + 12}',
        'Customer Handoff Readiness Matrix',
        '${_customerHandoffReadinessRows(document).length}',
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
    final previewRows = previewRowsFor(document);
    final readinessSignals = _readinessSignals(document);
    final validationGaps = _validationGapsFor(document);
    final documentParts = _documentPartsFor(document);
    final scorecardRows = _handoffScorecardRows(document).skip(1).toList();
    final handoffReadinessRows = _customerHandoffReadinessRows(
      document,
    ).skip(1).toList();
    final handoffScore = _handoffScoreFor(scorecardRows);
    final reviewChecklist = _reportReviewChecklistFor(document, validationGaps);
    final handoffActions = _reportHandoffActionsFor(document);
    final accessibilitySignals = _accessibilitySignalsFor(document);
    final visualVerificationChecklist = _visualVerificationChecklistFor(
      document,
    );
    final reportEvidencePolicy = _reportEvidencePolicyFor(document);
    final publishingMetadata = _publishingMetadataFor(document);
    final externalHandoffManifest = _externalHandoffManifestFor(
      document,
      handoffScore: handoffScore,
      validationGaps: validationGaps,
    );
    return {
      'generator': 'CircuitCode',
      'artifact': 'word_report',
      'qualityManifestVersion': '1.0',
      'reportType': _reportTypeFor(document),
      'audience': _audienceFor(document),
      'reportPurpose': _reportPurposeFor(document),
      'handoffStatus': _handoffStatus(document),
      'handoffScore': handoffScore,
      'handoffReadinessLevel': _handoffReadinessLevelFor(handoffScore),
      'customerHandoffGateStatus': _customerHandoffGateStatusFor(
        document,
        validationGaps,
      ),
      'customerHandoffGateRows': handoffReadinessRows,
      'customerHandoffGateCount': handoffReadinessRows.length,
      'decisionOwner': _decisionOwner(document),
      'decisionAsk': _decisionAskFor(document),
      'reviewPath': _reviewPathFor(document),
      'documentParts': documentParts,
      'documentPartCount': documentParts.length,
      'documentQuality': 'Enterprise structured report',
      'designPreset': 'standard_business_brief',
      'layoutSystem': 'US Letter, 1 inch margins, Aptos type scale',
      'formFactors': [
        'Lead decision callout',
        'Table of contents',
        'Executive decision brief',
        'Recommendation summary',
        'Risk register',
        'Next-step action plan',
        'Evidence confidence matrix',
        'Approval gates',
        'Validation checklist',
        'Customer handoff scorecard',
        'Customer handoff readiness matrix',
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
      'evidenceConfidence': _evidenceConfidenceFor(document),
      'reportReviewChecklist': reviewChecklist,
      'reportReviewChecklistCount': reviewChecklist.length,
      'reportHandoffActions': handoffActions,
      'reportHandoffActionCount': handoffActions.length,
      'accessibilitySignals': accessibilitySignals,
      'accessibilitySignalCount': accessibilitySignals.length,
      'visualVerificationChecklist': visualVerificationChecklist,
      'visualVerificationChecklistCount': visualVerificationChecklist.length,
      'reportEvidencePolicy': reportEvidencePolicy,
      'reportEvidencePolicyCount': reportEvidencePolicy.length,
      'publishingMetadata': publishingMetadata,
      'publishingMetadataCount': publishingMetadata.length,
      'externalHandoffManifest': externalHandoffManifest,
      'externalHandoffManifestCount': externalHandoffManifest.length,
      'hasExternalHandoffManifest': externalHandoffManifest.isNotEmpty,
      'reportRiskFlags': _reportRiskFlagsFor(document, validationGaps),
      'appendixCoverage': _appendixCoverageFor(document),
      'validationGaps': validationGaps,
      'validationGapCount': validationGaps.length,
      'sectionCount': document.sections.length,
      'reportSectionCount': previewRows.isEmpty ? 0 : previewRows.length - 1,
      'tableCount': document.tables.length,
      'assumptionCount': document.assumptions.length,
      'citationCount': document.citations.length,
      'wordCount': _wordCount(document),
      'paragraphCount': _paragraphCount(document),
      'riskItemCount': _riskRegisterRows(document).length,
      'nextStepCount': _nextStepRows(document).length,
      'evidenceItemCount': _evidenceConfidenceRows(document).length,
      'evidenceGapCount': _evidenceGapCount(document),
      'handoffScorecardItemCount': scorecardRows.length,
      'hasCustomerHandoffReadinessMatrix': true,
      'decisionLogCount': _decisionLogRows(document).length - 1,
      'decisionSignOffGateCount': _decisionSignOffRows(document).length - 1,
      'approvalGateCount': 4,
      'readinessSignals': readinessSignals,
      'readinessSignalCount': readinessSignals.length,
      'hasLeadDecisionCallout': true,
      'hasExecutiveDecisionBrief': true,
      'hasTableOfContents': true,
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
      'hasExplicitTableGeometry': true,
      'hasRepeatingTableHeaders': true,
      'hasReportQualityManifest': true,
      'hasPublishingMetadata': true,
      'hasAccessibilitySignals': true,
      'hasVisualVerificationChecklist': true,
      'hasReportEvidencePolicy': true,
      'hasAssumptionsAppendix': document.assumptions.isNotEmpty,
      'hasSourcesAppendix': document.citations.isNotEmpty,
      'hasCustomerReadyPackage': _hasCustomerReadyPackage(document),
      'hasCustomerReadyReport':
          _hasCustomerReadyPackage(document) && validationGaps.isEmpty,
    };
  }

  Uint8List render(ArtifactDocument document) {
    final files = <_DocxFile>[
      _DocxFile('[Content_Types].xml', _bytes(_contentTypes())),
      _DocxFile('_rels/.rels', _bytes(_rootRels())),
      _DocxFile('docProps/app.xml', _bytes(_appXml(document))),
      _DocxFile('docProps/core.xml', _bytes(_coreXml(document))),
      _DocxFile('docProps/custom.xml', _bytes(_customXml(document))),
      _DocxFile('word/document.xml', _bytes(_documentXml(document))),
      _DocxFile('word/styles.xml', _bytes(_stylesXml())),
      _DocxFile('word/numbering.xml', _bytes(_numberingXml())),
      _DocxFile('word/settings.xml', _bytes(_settingsXml())),
      _DocxFile('word/header1.xml', _bytes(_headerXml(document))),
      _DocxFile('word/footer1.xml', _bytes(_footerXml())),
      _DocxFile('word/_rels/document.xml.rels', _bytes(_documentRelsXml())),
    ];
    return _zip(files);
  }

  Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

  String _contentTypes() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '<Override PartName="/docProps/custom.xml" ContentType="application/vnd.openxmlformats-officedocument.custom-properties+xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>'
        '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>'
        '<Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>'
        '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>'
        '</Types>';
  }

  String _rootRels() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
        '<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/custom-properties" Target="docProps/custom.xml"/>'
        '</Relationships>';
  }

  String _documentRelsXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rIdHeader1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>'
        '<Relationship Id="rIdFooter1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>'
        '</Relationships>';
  }

  String _appXml(ArtifactDocument document) {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
        '<Application>CircuitCode</Application>'
        '<Company>CircuitCode</Company>'
        '<Words>${_wordCount(document)}</Words>'
        '<Paragraphs>${_paragraphCount(document)}</Paragraphs>'
        '</Properties>';
  }

  String _customXml(ArtifactDocument document) {
    final handoffScore = _handoffScoreFor(
      _handoffScorecardRows(document).skip(1).toList(),
    );
    final properties = <String, String>{
      'CircuitReportQualityManifest':
          'Design preset, table geometry, decision brief, evidence matrix, validation checklist, approval gates, handoff scorecard.',
      'CircuitReportType': _reportTypeFor(document),
      'CircuitDecisionAsk': _decisionAskFor(document),
      'CircuitReviewPath': _reviewPathFor(document),
      'CircuitHandoffReadiness': _handoffReadinessLevelFor(handoffScore),
      'CircuitCustomerHandoffReadiness': _customerHandoffReadinessRows(
        document,
      ).map((row) => row.join(' / ')).join(' | '),
      'CircuitEvidenceConfidence': _evidenceConfidenceFor(document),
      'CircuitDocumentParts': _documentPartsFor(document).join(', '),
      'CircuitAccessibilityPolicy':
          'Real Word headings, real numbering, explicit table geometry, repeating table headers, header/footer markers.',
      'CircuitVisualVerification': _visualVerificationChecklistFor(
        document,
      ).join('; '),
      'CircuitReportEvidencePolicy': _reportEvidencePolicyFor(
        document,
      ).join('; '),
      'CircuitExternalHandoffManifest': _externalHandoffManifestFor(
        document,
        handoffScore: handoffScore,
        validationGaps: _validationGapsFor(document),
      ).join(' | '),
      'CircuitPublishingStatus': _handoffStatus(document),
    };
    var pid = 2;
    final entries = properties.entries
        .map(
          (entry) =>
              '<property fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" pid="${pid++}" name="${_xml(entry.key)}"><vt:lpwstr>${_xml(entry.value)}</vt:lpwstr></property>',
        )
        .join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/custom-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
        '$entries'
        '</Properties>';
  }

  String _coreXml(ArtifactDocument document) {
    final now = DateTime.now().toUtc().toIso8601String();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:title>${_xml(document.title)}</dc:title>'
        '<dc:creator>CircuitCode</dc:creator>'
        '<dc:description>Enterprise report artifact generated by CircuitCode.</dc:description>'
        '<cp:keywords>${_xml(_keywords(document).join(', '))}</cp:keywords>'
        '<cp:lastModifiedBy>CircuitCode</cp:lastModifiedBy>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">$now</dcterms:created>'
        '<dcterms:modified xsi:type="dcterms:W3CDTF">$now</dcterms:modified>'
        '</cp:coreProperties>';
  }

  int _wordCount(ArtifactDocument document) {
    final text = [
      document.title,
      document.summary,
      for (final section in document.sections) ...[
        section.title,
        section.body,
        ...section.bullets,
      ],
      for (final table in document.tables)
        for (final row in table.rows) ...row,
      ...document.assumptions,
      ...document.citations,
    ].join(' ');
    return RegExp(r'\b[\w-]+\b').allMatches(text).length;
  }

  int _paragraphCount(ArtifactDocument document) {
    return 12 +
        document.sections.length +
        document.sections.fold<int>(
          0,
          (sum, section) =>
              sum + _paragraphs(section.body).length + section.bullets.length,
        ) +
        document.tables.length +
        document.assumptions.length +
        document.citations.length;
  }

  String _stylesXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:after="160" w:line="276" w:lineRule="auto"/></w:pPr><w:rPr><w:rFonts w:ascii="Aptos" w:hAnsi="Aptos"/><w:color w:val="1F2937"/><w:sz w:val="22"/></w:rPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:before="0" w:after="180"/></w:pPr><w:rPr><w:b/><w:color w:val="111111"/><w:sz w:val="44"/></w:rPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:after="360"/></w:pPr><w:rPr><w:color w:val="475569"/><w:sz w:val="24"/></w:rPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:before="420" w:after="180"/><w:keepNext/></w:pPr><w:rPr><w:b/><w:color w:val="111111"/><w:sz w:val="30"/></w:rPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:before="260" w:after="140"/><w:keepNext/></w:pPr><w:rPr><w:b/><w:color w:val="334155"/><w:sz w:val="25"/></w:rPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="Caption"><w:name w:val="Caption"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="60" w:after="120"/></w:pPr><w:rPr><w:color w:val="64748B"/><w:sz w:val="19"/></w:rPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="CalloutLabel"><w:name w:val="Callout Label"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="60"/></w:pPr><w:rPr><w:b/><w:color w:val="0F766E"/><w:sz w:val="20"/></w:rPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="Footer"><w:name w:val="Footer"/><w:basedOn w:val="Normal"/><w:rPr><w:color w:val="64748B"/><w:sz w:val="18"/></w:rPr></w:style>'
        '</w:styles>';
  }

  String _documentXml(ArtifactDocument document) {
    final body = StringBuffer()
      ..write(_paragraph(document.title, style: 'Title'))
      ..write(_paragraph('CircuitCode generated report', style: 'Subtitle'))
      ..write(_leadDecisionCallout(document))
      ..write(_tableOfContentsBlock(document))
      ..write(_paragraph('Report Overview', style: 'Heading1'))
      ..write(_reportOverviewTable(document))
      ..write(_paragraph('Executive Decision Brief', style: 'Heading1'))
      ..write(_executiveDecisionBriefTable(document))
      ..write(_paragraph('Recommendation Summary', style: 'Heading1'))
      ..write(_recommendationSummaryTable(document))
      ..write(_paragraph('Risk & Assumption Register', style: 'Heading1'))
      ..write(_riskRegisterTable(document))
      ..write(_paragraph('Next-Step Action Plan', style: 'Heading1'))
      ..write(_nextStepActionTable(document))
      ..write(_paragraph('Document Map', style: 'Heading1'))
      ..write(_documentMapTable(document))
      ..write(_paragraph('Executive Summary', style: 'Heading1'))
      ..write(_paragraph(document.summary, style: 'Normal'));
    for (final section in document.sections) {
      body.write(_paragraph(section.title, style: 'Heading1'));
      if (section.body.trim().isNotEmpty) {
        for (final paragraph in _paragraphs(section.body).take(6)) {
          body.write(_paragraph(paragraph, style: 'Normal'));
        }
      }
      for (final bullet in section.bullets.take(10)) {
        body.write(_bulletParagraph(bullet));
      }
    }
    for (final table in document.tables) {
      body
        ..write(_paragraph(table.title, style: 'Heading2'))
        ..write(_table(table));
    }
    body
      ..write(_paragraph('Stakeholder Readout', style: 'Heading1'))
      ..write(_stakeholderReadoutTable(document))
      ..write(_paragraph('Evidence Confidence Matrix', style: 'Heading1'))
      ..write(_evidenceConfidenceTable(document))
      ..write(_paragraph('Approval Gates', style: 'Heading1'))
      ..write(_approvalGatesTable(document))
      ..write(_paragraph('Validation Checklist', style: 'Heading1'))
      ..write(_validationChecklistTable(document))
      ..write(_paragraph('Customer Handoff Scorecard', style: 'Heading1'))
      ..write(_handoffScorecardTable(document))
      ..write(
        _paragraph('Customer Handoff Readiness Matrix', style: 'Heading1'),
      )
      ..write(_customerHandoffReadinessTable(document))
      ..write(_paragraph('Decision Log', style: 'Heading1'))
      ..write(_decisionLogTable(document))
      ..write(_paragraph('Decision Sign-Off', style: 'Heading1'))
      ..write(_decisionSignOffTable(document));
    if (document.assumptions.isNotEmpty) {
      body.write(_paragraph('Appendix A: Assumptions', style: 'Heading1'));
      for (final assumption in document.assumptions) {
        body.write(_bulletParagraph(assumption));
      }
    }
    if (document.citations.isNotEmpty) {
      body.write(
        _paragraph('Appendix B: Sources / Evidence', style: 'Heading1'),
      );
      for (final citation in document.citations) {
        body.write(_bulletParagraph(citation));
      }
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<w:body>$body'
        '<w:sectPr><w:headerReference w:type="default" r:id="rIdHeader1"/><w:footerReference w:type="default" r:id="rIdFooter1"/><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1080" w:right="1080" w:bottom="1080" w:left="1080" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
        '</w:body></w:document>';
  }

  String _leadDecisionCallout(ArtifactDocument document) {
    final rows = [
      ['Decision ask', _decisionAskFor(document)],
      ['Owner', _decisionOwner(document)],
      ['Handoff status', _handoffStatus(document)],
      ['Review path', _reviewPathFor(document)],
    ];
    return '<w:tbl><w:tblPr><w:tblW w:w="9120" w:type="dxa"/><w:tblInd w:w="120" w:type="dxa"/><w:tblBorders><w:top w:val="single" w:sz="8" w:color="5EEAD4"/><w:left w:val="single" w:sz="8" w:color="5EEAD4"/><w:bottom w:val="single" w:sz="8" w:color="CCFBF1"/><w:right w:val="single" w:sz="8" w:color="CCFBF1"/><w:insideH w:val="single" w:sz="4" w:color="CCFBF1"/><w:insideV w:val="single" w:sz="4" w:color="CCFBF1"/></w:tblBorders><w:tblCellMar><w:top w:w="120" w:type="dxa"/><w:left w:w="180" w:type="dxa"/><w:bottom w:w="120" w:type="dxa"/><w:right w:w="180" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid><w:gridCol w:w="2160"/><w:gridCol w:w="6960"/></w:tblGrid>${rows.map((row) => _calloutRow(row[0], row[1])).join()}</w:tbl>';
  }

  String _calloutRow(String label, String value) {
    return '<w:tr>'
        '<w:tc><w:tcPr><w:tcW w:w="2160" w:type="dxa"/><w:vAlign w:val="center"/><w:shd w:fill="CCFBF1"/></w:tcPr><w:p><w:pPr><w:pStyle w:val="CalloutLabel"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="0F766E"/><w:sz w:val="20"/></w:rPr><w:t xml:space="preserve">${_xml(label)}</w:t></w:r></w:p></w:tc>'
        '<w:tc><w:tcPr><w:tcW w:w="6960" w:type="dxa"/><w:vAlign w:val="center"/><w:shd w:fill="F0FDFA"/></w:tcPr><w:p><w:pPr><w:spacing w:after="60"/></w:pPr><w:r><w:rPr><w:color w:val="134E4A"/><w:sz w:val="21"/></w:rPr><w:t xml:space="preserve">${_xml(value)}</w:t></w:r></w:p></w:tc>'
        '</w:tr>';
  }

  String _tableOfContentsBlock(ArtifactDocument document) {
    final entries = [
      'Report Overview',
      'Executive Decision Brief',
      'Recommendation Summary',
      'Risk & Assumption Register',
      'Next-Step Action Plan',
      'Document Map',
      'Executive Summary',
      for (final section in document.sections.take(8)) section.title,
      if (document.tables.isNotEmpty) 'Data Tables',
      'Stakeholder Readout',
      'Evidence Confidence Matrix',
      'Approval Gates',
      'Validation Checklist',
      'Customer Handoff Scorecard',
      'Customer Handoff Readiness Matrix',
      'Decision Log',
      'Decision Sign-Off',
      if (document.assumptions.isNotEmpty) 'Appendix A: Assumptions',
      if (document.citations.isNotEmpty) 'Appendix B: Sources / Evidence',
    ];
    return '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Table of Contents</w:t></w:r></w:p>'
        '<w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText xml:space="preserve">TOC \\o "1-2" \\h \\z \\u</w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>Update fields in Word to refresh page numbers.</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>'
        '<w:tbl><w:tblPr><w:tblW w:w="9120" w:type="dxa"/><w:tblInd w:w="120" w:type="dxa"/><w:tblBorders><w:top w:val="single" w:sz="4" w:color="E2E8F0"/><w:left w:val="single" w:sz="4" w:color="E2E8F0"/><w:bottom w:val="single" w:sz="4" w:color="E2E8F0"/><w:right w:val="single" w:sz="4" w:color="E2E8F0"/><w:insideH w:val="single" w:sz="4" w:color="F1F5F9"/></w:tblBorders><w:tblCellMar><w:top w:w="80" w:type="dxa"/><w:left w:w="120" w:type="dxa"/><w:bottom w:w="80" w:type="dxa"/><w:right w:w="120" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid><w:gridCol w:w="960"/><w:gridCol w:w="8160"/></w:tblGrid>'
        '${[
          for (var i = 0; i < entries.length; i++) _tableRow(['${i + 1}', entries[i]], [960, 8160], i == 0),
        ].join()}'
        '</w:tbl>';
  }

  String _reportOverviewTable(ArtifactDocument document) {
    return _table(
      ArtifactTable(
        title: 'Report Overview',
        rows: [
          ['Detail', 'Value'],
          ['Generated by', 'CircuitCode'],
          ['Sections', '${document.sections.length}'],
          ['Data tables', '${document.tables.length}'],
          ['Assumptions', '${document.assumptions.length}'],
          ['Sources / evidence', '${document.citations.length}'],
          ['Customer handoff status', _handoffStatus(document)],
        ],
      ),
    );
  }

  String _documentMapTable(ArtifactDocument document) {
    final rows = <List<String>>[
      ['Section', 'Purpose'],
      ['Executive Decision Brief', 'Decision and handoff guidance.'],
      [
        'Recommendation Summary',
        'Recommended path, rationale, dependencies, and decision owner.',
      ],
      [
        'Risk & Assumption Register',
        'Known risks, assumptions, evidence gaps, and mitigation guidance.',
      ],
      [
        'Next-Step Action Plan',
        'Immediate action items, owners, validation gates, and expected outputs.',
      ],
      ['Executive Summary', 'Decision-ready summary of the artifact.'],
      for (final section in document.sections.take(12))
        [
          section.title,
          section.bullets.isNotEmpty
              ? '${section.bullets.length} key point${section.bullets.length == 1 ? '' : 's'}'
              : 'Narrative section',
        ],
      if (document.tables.isNotEmpty)
        [
          'Data Tables',
          '${document.tables.length} structured table${document.tables.length == 1 ? '' : 's'}',
        ],
      [
        'Stakeholder Readout',
        'Audience, decision owner, business value, and technical owner summary.',
      ],
      [
        'Evidence Confidence Matrix',
        'Evidence status, confidence, gaps, and verification guidance.',
      ],
      [
        'Approval Gates',
        'Decision gates required before customer handoff or implementation.',
      ],
      ['Validation Checklist', 'Quality and handoff readiness checks.'],
      [
        'Customer Handoff Scorecard',
        'Handoff readiness score, status signals, and owner follow-up.',
      ],
      [
        'Customer Handoff Readiness Matrix',
        'External handoff gates, signals, status, and owner actions.',
      ],
      [
        'Decision Log',
        'Decision, owner, evidence, and next-action record for review.',
      ],
      [
        'Decision Sign-Off',
        'Final approval fields, signature owners, status, and dates.',
      ],
      if (document.assumptions.isNotEmpty)
        [
          'Appendix A: Assumptions',
          '${document.assumptions.length} assumption${document.assumptions.length == 1 ? '' : 's'}',
        ],
      if (document.citations.isNotEmpty)
        [
          'Appendix B: Sources / Evidence',
          '${document.citations.length} source item${document.citations.length == 1 ? '' : 's'}',
        ],
    ];
    return _table(ArtifactTable(title: 'Document Map', rows: rows));
  }

  String _executiveDecisionBriefTable(ArtifactDocument document) {
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
    return _table(
      ArtifactTable(
        title: 'Executive Decision Brief',
        rows: [
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
        ],
      ),
    );
  }

  String _recommendationSummaryTable(ArtifactDocument document) {
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
    return _table(
      ArtifactTable(
        title: 'Recommendation Summary',
        rows: [
          ['Field', 'Recommendation Detail'],
          [
            'Recommended path',
            recommendation ??
                'Use this report as a review artifact, then confirm the preferred implementation path with stakeholders.',
          ],
          [
            'Rationale',
            rationale ??
                'The recommendation should be validated against customer goals, constraints, source data, and implementation risk.',
          ],
          [
            'Dependencies',
            dependency ??
                'Confirm source evidence, ownership, timeline, access, licensing, and acceptance criteria.',
          ],
          ['Decision owner', _decisionOwner(document)],
        ],
      ),
    );
  }

  String _riskRegisterTable(ArtifactDocument document) {
    return _table(
      ArtifactTable(
        title: 'Risk & Assumption Register',
        rows: _riskRegisterRows(document),
      ),
    );
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

  String _nextStepActionTable(ArtifactDocument document) {
    return _table(
      ArtifactTable(
        title: 'Next-Step Action Plan',
        rows: _nextStepRows(document),
      ),
    );
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

  String _validationChecklistTable(ArtifactDocument document) {
    return _table(
      ArtifactTable(
        title: 'Validation Checklist',
        rows: [
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
        ],
      ),
    );
  }

  String _stakeholderReadoutTable(ArtifactDocument document) {
    return _table(
      ArtifactTable(
        title: 'Stakeholder Readout',
        rows: [
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
        ],
      ),
    );
  }

  String _evidenceConfidenceTable(ArtifactDocument document) {
    return _table(
      ArtifactTable(
        title: 'Evidence Confidence Matrix',
        rows: _evidenceConfidenceRows(document),
      ),
    );
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

  String _approvalGatesTable(ArtifactDocument document) {
    return _table(
      ArtifactTable(
        title: 'Approval Gates',
        rows: [
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
            document.assumptions.isEmpty
                ? 'Needs assumptions'
                : 'Ready for review',
          ],
          [
            'Implementation approval',
            'Approved next steps, owner, timeline, and verification plan.',
            'Implementation owner',
            _nextStepRows(document).length <= 1 ? 'Needs plan' : 'Ready',
          ],
        ],
      ),
    );
  }

  String _handoffScorecardTable(ArtifactDocument document) {
    return _table(
      ArtifactTable(
        title: 'Customer Handoff Scorecard',
        rows: _handoffScorecardRows(document),
      ),
    );
  }

  String _customerHandoffReadinessTable(ArtifactDocument document) {
    return _table(
      ArtifactTable(
        title: 'Customer Handoff Readiness Matrix',
        rows: _customerHandoffReadinessRows(document),
      ),
    );
  }

  List<List<String>> _customerHandoffReadinessRows(ArtifactDocument document) {
    return [
      ['Gate', 'Signal', 'Status', 'Owner Action'],
      [
        'Evidence package',
        document.citations.isEmpty
            ? 'No cited sources attached'
            : '${document.citations.length} source item${document.citations.length == 1 ? '' : 's'} attached',
        document.citations.isEmpty ? 'Needs evidence' : 'Ready',
        document.citations.isEmpty
            ? 'Attach source evidence before external handoff.'
            : 'Keep cited sources with the handoff package.',
      ],
      [
        'Assumptions',
        document.assumptions.isEmpty
            ? 'No assumptions captured'
            : '${document.assumptions.length} assumption${document.assumptions.length == 1 ? '' : 's'} captured',
        document.assumptions.isEmpty ? 'Needs owner review' : 'Ready',
        document.assumptions.isEmpty
            ? 'Capture unknowns and accountable owner confirmation.'
            : 'Review assumptions with the accountable owner.',
      ],
      [
        'Data support',
        document.tables.isEmpty
            ? 'No structured supporting tables'
            : '${document.tables.length} supporting table${document.tables.length == 1 ? '' : 's'} packaged',
        document.tables.isEmpty ? 'Needs support' : 'Ready',
        document.tables.isEmpty
            ? 'Attach source data or state why no table is required.'
            : 'Validate units, dates, and sensitive data before sharing.',
      ],
      [
        'Decision ask',
        _decisionAskFor(document),
        'Ready',
        'Confirm this is the decision the stakeholder is expected to make.',
      ],
      [
        'Sign-off owner',
        _decisionOwner(document),
        _validationGapsFor(document).isEmpty
            ? 'Ready'
            : 'Resolve ${_validationGapsFor(document).length} gap${_validationGapsFor(document).length == 1 ? '' : 's'}',
        _validationGapsFor(document).isEmpty
            ? 'Collect approval signature and date.'
            : 'Resolve validation gaps before customer approval.',
      ],
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

  String _decisionLogTable(ArtifactDocument document) {
    return _table(
      ArtifactTable(title: 'Decision Log', rows: _decisionLogRows(document)),
    );
  }

  String _decisionSignOffTable(ArtifactDocument document) {
    return _table(
      ArtifactTable(
        title: 'Decision Sign-Off',
        rows: _decisionSignOffRows(document),
      ),
    );
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

  String _customerHandoffGateStatusFor(
    ArtifactDocument document,
    List<String> validationGaps,
  ) {
    if (validationGaps.isEmpty && document.tables.isNotEmpty) {
      return 'Ready for stakeholder approval';
    }
    if (validationGaps.isEmpty) {
      return 'Ready with optional data support';
    }
    return 'Resolve ${validationGaps.length} validation gap${validationGaps.length == 1 ? '' : 's'} before handoff';
  }

  List<String> _keywords(ArtifactDocument document) {
    final keywords = <String>{
      'artifact',
      'report',
      'CircuitCode',
      'enterprise',
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
    if (combined.contains('implementation') || combined.contains('plan')) {
      return 'Implementation plan';
    }
    if (combined.contains('architecture') || combined.contains('review')) {
      return 'Architecture report';
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
    if (combined.contains('customer') ||
        combined.contains('proposal') ||
        combined.contains('client')) {
      return 'Customer stakeholders';
    }
    if (combined.contains('executive') || combined.contains('leadership')) {
      return 'Executive stakeholders';
    }
    if (combined.contains('architecture') || combined.contains('technical')) {
      return 'Architecture reviewers';
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
      'Customer handoff readiness matrix',
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
      'Recommendation summary',
      'Risk register',
      'Next-step action plan',
      'Document map',
      'Evidence confidence matrix',
      'Approval gates',
      'Validation checklist',
      'Customer handoff scorecard',
      'Customer handoff readiness matrix',
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

  String _evidenceConfidenceFor(ArtifactDocument document) {
    if (document.citations.isNotEmpty && document.assumptions.isNotEmpty) {
      return 'High - sources and assumptions captured';
    }
    if (document.citations.isNotEmpty) {
      return 'Medium - sources captured, assumptions need owner review';
    }
    if (document.assumptions.isNotEmpty) {
      return 'Medium - assumptions captured, sources need validation';
    }
    return 'Low - sources and assumptions need validation';
  }

  List<String> _reportReviewChecklistFor(
    ArtifactDocument document,
    List<String> validationGaps,
  ) {
    return [
      'Confirm report title, audience, decision owner, and decision ask.',
      'Review executive decision brief and recommendation summary for customer-specific language.',
      'Validate risk register, next-step action plan, and approval gates.',
      if (document.tables.isNotEmpty)
        'Review data tables for stale values, sensitive data, and source alignment.'
      else
        'Attach supporting data or state why no data table is required.',
      if (document.assumptions.isNotEmpty)
        'Confirm assumptions with the accountable owner.'
      else
        'Capture assumptions before customer handoff.',
      if (document.citations.isNotEmpty)
        'Check source authority, freshness, and cited facts.'
      else
        'Attach sources or mark the report as an unsourced draft.',
      if (validationGaps.isNotEmpty)
        'Resolve ${validationGaps.length} validation gap${validationGaps.length == 1 ? '' : 's'} before stakeholder handoff.',
    ];
  }

  List<String> _reportHandoffActionsFor(ArtifactDocument document) {
    return [
      'Send report to internal reviewer with source artifacts attached.',
      'Walk through the decision ask: ${_decisionAskFor(document)}',
      'Capture owner, due date, approval gates, and follow-up actions.',
      if (document.citations.isNotEmpty)
        'Keep cited sources with the handoff package.'
      else
        'Add cited evidence before external handoff.',
    ];
  }

  List<String> _accessibilitySignalsFor(ArtifactDocument document) {
    return [
      'Real Word headings',
      'Real numbering for bullets',
      'Explicit table geometry',
      'Repeating table headers',
      'Header and footer package markers',
      if (document.citations.isNotEmpty) 'Source appendix included',
      if (document.assumptions.isNotEmpty) 'Assumption appendix included',
    ];
  }

  List<String> _visualVerificationChecklistFor(ArtifactDocument document) {
    return [
      'Open the DOCX in Word and verify headings, tables, appendices, header/footer, and sign-off sections render without clipping.',
      'Confirm table headers repeat and columns remain readable in print layout.',
      'Verify executive decision brief, recommendation summary, risk register, approval gates, and sign-off page appear in order.',
      if (document.citations.isNotEmpty)
        'Confirm sources appendix is included with checked dates and source labels.'
      else
        'Mark the report as an unsourced draft until source artifacts are attached.',
      if (document.assumptions.isNotEmpty)
        'Confirm assumptions appendix is explicit and owner-reviewable.'
      else
        'Capture assumptions before external handoff.',
    ];
  }

  List<String> _reportEvidencePolicyFor(ArtifactDocument document) {
    return [
      'Report narrative is guidance; source appendices and source artifacts are the evidence record.',
      'Customer handoff requires checked sources, assumptions, decision owner, and approval gate.',
      if (document.citations.isNotEmpty)
        'Use cited sources as the evidence register for external review.'
      else
        'Do not represent unsupported claims as validated facts until sources are attached.',
      if (document.assumptions.isNotEmpty)
        'Review assumptions with the accountable owner before stakeholder handoff.'
      else
        'Capture assumptions and unknowns before treating the report as customer-ready.',
    ];
  }

  List<String> _publishingMetadataFor(ArtifactDocument document) {
    final handoffScore = _handoffScoreFor(
      _handoffScorecardRows(document).skip(1).toList(),
    );
    return [
      'Report type: ${_reportTypeFor(document)}',
      'Decision ask: ${_decisionAskFor(document)}',
      'Review path: ${_reviewPathFor(document)}',
      'Handoff readiness: ${_handoffReadinessLevelFor(handoffScore)}',
      'Evidence confidence: ${_evidenceConfidenceFor(document)}',
      'Publishing status: ${_handoffStatus(document)}',
    ];
  }

  List<String> _externalHandoffManifestFor(
    ArtifactDocument document, {
    required int handoffScore,
    required List<String> validationGaps,
  }) {
    final publishingGate = validationGaps.isEmpty
        ? 'ready for stakeholder approval'
        : 'resolve ${validationGaps.length} validation gap${validationGaps.length == 1 ? '' : 's'}';
    return [
      'Review owner: ${_decisionOwner(document)}',
      'Report type: ${_reportTypeFor(document)}',
      'Review path: ${_reviewPathFor(document)}',
      'Handoff readiness: ${_handoffReadinessLevelFor(handoffScore)}',
      'Evidence status: ${_evidenceConfidenceFor(document)}',
      'Publishing gate: $publishingGate',
      'Decision ask: ${_decisionAskFor(document)}',
      'Source package: ${document.citations.isEmpty ? 'sources missing' : '${document.citations.length} source item${document.citations.length == 1 ? '' : 's'} attached'}',
      'Assumption package: ${document.assumptions.isEmpty ? 'assumptions missing' : '${document.assumptions.length} assumption${document.assumptions.length == 1 ? '' : 's'} captured'}',
    ];
  }

  List<String> _reportRiskFlagsFor(
    ArtifactDocument document,
    List<String> validationGaps,
  ) {
    return [
      if (document.summary.trim().isEmpty) 'Missing executive summary',
      if (document.sections.isEmpty) 'Missing report sections',
      if (document.citations.isEmpty) 'No cited sources attached',
      if (document.assumptions.isEmpty) 'No assumptions captured',
      if (document.tables.isEmpty) 'No supporting data tables',
      for (final gap in validationGaps.take(3)) gap,
    ];
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
        'Review the report, confirm assumptions, and approve the next stakeholder action.',
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
      _ => 'Stakeholder review -> evidence validation -> next-step approval',
    };
  }

  String _truncate(String value, int maxLength) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength - 3).trim()}...';
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

  String _numberingXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="singleLevel"/>'
        '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="&#8226;"/><w:lvlJc w:val="left"/>'
        '<w:pPr><w:tabs><w:tab w:val="num" w:pos="720"/></w:tabs><w:ind w:left="720" w:hanging="360"/></w:pPr>'
        '<w:rPr><w:rFonts w:ascii="Symbol" w:hAnsi="Symbol" w:hint="default"/></w:rPr></w:lvl></w:abstractNum>'
        '<w:num w:numId="1"><w:abstractNumId w:val="1"/></w:num>'
        '</w:numbering>';
  }

  String _settingsXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:zoom w:percent="100"/><w:defaultTabStop w:val="720"/><w:doNotTrackMoves/><w:doNotTrackFormatting/>'
        '</w:settings>';
  }

  String _footerXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:p><w:pPr><w:pStyle w:val="Footer"/></w:pPr><w:r><w:t>CircuitCode - Generated artifact</w:t></w:r></w:p>'
        '</w:ftr>';
  }

  String _headerXml(ArtifactDocument document) {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:p><w:pPr><w:pStyle w:val="Footer"/><w:pBdr><w:bottom w:val="single" w:sz="4" w:space="1" w:color="CBD5E1"/></w:pBdr></w:pPr>'
        '<w:r><w:rPr><w:b/><w:color w:val="334155"/></w:rPr><w:t>${_xml(_truncate(document.title, 72))}</w:t></w:r>'
        '<w:r><w:rPr><w:color w:val="64748B"/></w:rPr><w:t xml:space="preserve">  |  CircuitCode report package</w:t></w:r>'
        '</w:p></w:hdr>';
  }

  Iterable<String> _paragraphs(String body) {
    return body
        .split(RegExp(r'\n\s*\n'))
        .map((paragraph) => paragraph.replaceAll('\n', ' ').trim())
        .where((paragraph) => paragraph.isNotEmpty);
  }

  String _paragraph(String text, {required String style}) {
    if (text.trim().isEmpty) return '';
    return '<w:p><w:pPr><w:pStyle w:val="$style"/></w:pPr><w:r><w:t xml:space="preserve">${_xml(text.trim())}</w:t></w:r></w:p>';
  }

  String _bulletParagraph(String text) {
    if (text.trim().isEmpty) return '';
    return '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr><w:spacing w:after="90"/></w:pPr><w:r><w:t xml:space="preserve">${_xml(text.trim())}</w:t></w:r></w:p>';
  }

  String _table(ArtifactTable table) {
    final rows = table.rows.take(24).toList(growable: false);
    if (rows.isEmpty) return '';
    final widths = _columnWidths(rows);
    final grid = widths.map((width) => '<w:gridCol w:w="$width"/>').join();
    final renderedRows = [
      for (var i = 0; i < rows.length; i++) _tableRow(rows[i], widths, i == 0),
    ].join();
    return '<w:tbl><w:tblPr><w:tblW w:w="9120" w:type="dxa"/><w:tblInd w:w="120" w:type="dxa"/><w:tblLook w:firstRow="1" w:lastRow="0" w:firstColumn="0" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/><w:tblBorders><w:top w:val="single" w:sz="4" w:color="CBD5E1"/><w:left w:val="single" w:sz="4" w:color="CBD5E1"/><w:bottom w:val="single" w:sz="4" w:color="CBD5E1"/><w:right w:val="single" w:sz="4" w:color="CBD5E1"/><w:insideH w:val="single" w:sz="4" w:color="E2E8F0"/><w:insideV w:val="single" w:sz="4" w:color="E2E8F0"/></w:tblBorders><w:tblCellMar><w:top w:w="100" w:type="dxa"/><w:left w:w="120" w:type="dxa"/><w:bottom w:w="100" w:type="dxa"/><w:right w:w="120" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid>$grid</w:tblGrid>$renderedRows</w:tbl>';
  }

  List<int> _columnWidths(List<List<String>> rows) {
    final columnCount = rows
        .fold<int>(0, (max, row) => row.length > max ? row.length : max)
        .clamp(1, 8);
    final weights = List<int>.filled(columnCount, 4);
    for (final row in rows.take(12)) {
      for (var i = 0; i < columnCount; i++) {
        final value = i < row.length ? row[i] : '';
        weights[i] = weights[i] + value.trim().length.clamp(1, 36);
      }
    }
    final total = weights.fold<int>(0, (sum, value) => sum + value);
    var remaining = 9120;
    final widths = <int>[];
    for (var i = 0; i < columnCount; i++) {
      final width = i == columnCount - 1
          ? remaining
          : ((9120 * weights[i]) / total).round().clamp(900, 3600);
      widths.add(width);
      remaining -= width;
    }
    if (widths.isNotEmpty && widths.last < 900) {
      final deficit = 900 - widths.last;
      widths[widths.length - 1] = 900;
      widths[0] = (widths.first - deficit).clamp(900, 3600);
    }
    return widths;
  }

  String _tableRow(List<String> row, List<int> widths, bool isHeader) {
    return '<w:tr>${isHeader ? '<w:trPr><w:tblHeader/></w:trPr>' : ''}${[for (var i = 0; i < widths.length; i++) _tableCell(i < row.length ? row[i] : '', widths[i], isHeader)].join()}</w:tr>';
  }

  String _tableCell(String value, int width, bool isHeader) {
    final fill = isHeader ? '<w:shd w:fill="E2E8F0"/>' : '';
    final run = isHeader ? '<w:b/>' : '';
    return '<w:tc><w:tcPr><w:tcW w:w="$width" w:type="dxa"/><w:vAlign w:val="center"/>$fill</w:tcPr><w:p><w:pPr><w:spacing w:after="60"/></w:pPr><w:r><w:rPr>$run<w:sz w:val="20"/></w:rPr><w:t xml:space="preserve">${_xml(value.trim())}</w:t></w:r></w:p></w:tc>';
  }

  String _xml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }
}

class _DocxFile {
  final String path;
  final Uint8List bytes;

  const _DocxFile(this.path, this.bytes);
}

Uint8List _zip(List<_DocxFile> files) {
  final output = BytesBuilder(copy: false);
  final centralDirectory = BytesBuilder(copy: false);
  var offset = 0;
  for (final file in files) {
    final nameBytes = utf8.encode(file.path);
    final crc = _crc32(file.bytes);
    final local = BytesBuilder(copy: false)
      ..add(_uint32(0x04034b50))
      ..add(_uint16(20))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint32(crc))
      ..add(_uint32(file.bytes.length))
      ..add(_uint32(file.bytes.length))
      ..add(_uint16(nameBytes.length))
      ..add(_uint16(0))
      ..add(nameBytes);
    final localBytes = local.toBytes();
    output
      ..add(localBytes)
      ..add(file.bytes);
    centralDirectory
      ..add(_uint32(0x02014b50))
      ..add(_uint16(20))
      ..add(_uint16(20))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint32(crc))
      ..add(_uint32(file.bytes.length))
      ..add(_uint32(file.bytes.length))
      ..add(_uint16(nameBytes.length))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint32(0))
      ..add(_uint32(offset))
      ..add(nameBytes);
    offset += localBytes.length + file.bytes.length;
  }
  final centralBytes = centralDirectory.toBytes();
  output
    ..add(centralBytes)
    ..add(_uint32(0x06054b50))
    ..add(_uint16(0))
    ..add(_uint16(0))
    ..add(_uint16(files.length))
    ..add(_uint16(files.length))
    ..add(_uint32(centralBytes.length))
    ..add(_uint32(offset))
    ..add(_uint16(0));
  return output.toBytes();
}

List<int> _uint16(int value) => [value & 0xff, (value >> 8) & 0xff];

List<int> _uint32(int value) => [
  value & 0xff,
  (value >> 8) & 0xff,
  (value >> 16) & 0xff,
  (value >> 24) & 0xff,
];

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
