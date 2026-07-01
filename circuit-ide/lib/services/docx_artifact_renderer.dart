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
      ['${document.sections.length + 7}', 'Validation Checklist', '5'],
      if (document.assumptions.isNotEmpty)
        [
          '${document.sections.length + 8}',
          'Assumptions',
          '${document.assumptions.length}',
        ],
      if (document.citations.isNotEmpty)
        [
          '${document.sections.length + 9}',
          'Sources / Evidence',
          '${document.citations.length}',
        ],
    ];
  }

  Uint8List render(ArtifactDocument document) {
    final files = <_DocxFile>[
      _DocxFile('[Content_Types].xml', _bytes(_contentTypes())),
      _DocxFile('_rels/.rels', _bytes(_rootRels())),
      _DocxFile('docProps/app.xml', _bytes(_appXml(document))),
      _DocxFile('docProps/core.xml', _bytes(_coreXml(document))),
      _DocxFile('word/document.xml', _bytes(_documentXml(document))),
      _DocxFile('word/styles.xml', _bytes(_stylesXml())),
      _DocxFile('word/numbering.xml', _bytes(_numberingXml())),
      _DocxFile('word/settings.xml', _bytes(_settingsXml())),
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
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>'
        '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>'
        '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>'
        '</Types>';
  }

  String _rootRels() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
        '</Relationships>';
  }

  String _documentRelsXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
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
    return 8 +
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
        '<w:style w:type="paragraph" w:styleId="Footer"><w:name w:val="Footer"/><w:basedOn w:val="Normal"/><w:rPr><w:color w:val="64748B"/><w:sz w:val="18"/></w:rPr></w:style>'
        '</w:styles>';
  }

  String _documentXml(ArtifactDocument document) {
    final body = StringBuffer()
      ..write(_paragraph(document.title, style: 'Title'))
      ..write(_paragraph('CircuitCode generated report', style: 'Subtitle'))
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
    for (final table in document.tables.take(6)) {
      body
        ..write(_paragraph(table.title, style: 'Heading2'))
        ..write(_table(table));
    }
    body
      ..write(_paragraph('Validation Checklist', style: 'Heading1'))
      ..write(_validationChecklistTable(document));
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
        '<w:sectPr><w:footerReference w:type="default" r:id="rIdFooter1"/><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1080" w:right="1080" w:bottom="1080" w:left="1080" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
        '</w:body></w:document>';
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
      ['Validation Checklist', 'Quality and handoff readiness checks.'],
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
    return '<w:tr>${[for (var i = 0; i < widths.length; i++) _tableCell(i < row.length ? row[i] : '', widths[i], isHeader)].join()}</w:tr>';
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
