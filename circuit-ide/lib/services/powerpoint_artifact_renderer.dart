import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/artifact_document.dart';

class PowerPointArtifactRenderer {
  const PowerPointArtifactRenderer();

  int slideCountFor(ArtifactDocument document) {
    return _slidesFor(document).take(24).length;
  }

  List<List<String>> previewRowsFor(ArtifactDocument document) {
    final slides = _slidesFor(document).take(24).toList(growable: false);
    return [
      ['Slide', 'Type', 'Title'],
      for (var i = 0; i < slides.length; i++)
        ['${i + 1}', slides[i].kind.label, slides[i].title],
    ];
  }

  Uint8List render(ArtifactDocument document) {
    final slides = _slidesFor(document).take(24).toList(growable: false);
    final theme = _DeckTheme.forDocument(document);
    final files = <_PptxFile>[
      _PptxFile('[Content_Types].xml', _bytes(_contentTypes(slides.length))),
      _PptxFile('_rels/.rels', _bytes(_rootRels())),
      _PptxFile('docProps/app.xml', _bytes(_appXml(slides.length))),
      _PptxFile('docProps/core.xml', _bytes(_coreXml(document.title))),
      _PptxFile('ppt/presentation.xml', _bytes(_presentation(slides.length))),
      _PptxFile(
        'ppt/_rels/presentation.xml.rels',
        _bytes(_presentationRels(slides.length)),
      ),
      _PptxFile('ppt/slideMasters/slideMaster1.xml', _bytes(_slideMaster())),
      _PptxFile(
        'ppt/slideMasters/_rels/slideMaster1.xml.rels',
        _bytes(_slideMasterRels()),
      ),
      _PptxFile('ppt/notesMasters/notesMaster1.xml', _bytes(_notesMaster())),
      _PptxFile(
        'ppt/notesMasters/_rels/notesMaster1.xml.rels',
        _bytes(_notesMasterRels()),
      ),
      _PptxFile('ppt/slideLayouts/slideLayout1.xml', _bytes(_slideLayout())),
      _PptxFile(
        'ppt/slideLayouts/_rels/slideLayout1.xml.rels',
        _bytes(_slideLayoutRels()),
      ),
      _PptxFile('ppt/theme/theme1.xml', _bytes(_theme())),
      for (var i = 0; i < slides.length; i++)
        _PptxFile(
          'ppt/slides/slide${i + 1}.xml',
          _bytes(
            _slide(
              slides[i],
              theme: theme,
              slideNumber: i + 1,
              totalSlides: slides.length,
            ),
          ),
        ),
      for (var i = 0; i < slides.length; i++)
        _PptxFile(
          'ppt/slides/_rels/slide${i + 1}.xml.rels',
          _bytes(_slideRels(i + 1)),
        ),
      for (var i = 0; i < slides.length; i++)
        _PptxFile(
          'ppt/notesSlides/notesSlide${i + 1}.xml',
          _bytes(_notesSlide(slides[i], slideNumber: i + 1)),
        ),
      for (var i = 0; i < slides.length; i++)
        _PptxFile(
          'ppt/notesSlides/_rels/notesSlide${i + 1}.xml.rels',
          _bytes(_notesSlideRels(i + 1)),
        ),
    ];
    return _zip(files);
  }

  List<_DeckSlide> _slidesFor(ArtifactDocument document) {
    final sections = document.sections.take(10).toList(growable: false);
    final slides = <_DeckSlide>[
      _DeckSlide(
        title: document.title,
        eyebrow: 'CircuitCode deliverable',
        kind: _DeckSlideKind.title,
        bullets: [
          if (document.summary.isNotEmpty) document.summary,
          if (document.tables.isNotEmpty)
            '${document.tables.length} table artifact${document.tables.length == 1 ? '' : 's'} included',
          if (document.citations.isNotEmpty)
            '${document.citations.length} source item${document.citations.length == 1 ? '' : 's'} captured',
        ],
      ),
      _DeckSlide(
        title: 'Agenda',
        eyebrow: 'Deck structure',
        kind: _DeckSlideKind.agenda,
        bullets: [
          if (document.summary.isNotEmpty) 'Executive summary',
          for (final section in sections.take(7)) section.title,
          if (document.tables.isNotEmpty) 'Data tables and supporting detail',
          if (document.assumptions.isNotEmpty || document.citations.isNotEmpty)
            'Assumptions and sources',
        ],
      ),
      _decisionSnapshot(document, sections),
      _executiveRecommendation(document, sections),
      if (document.summary.isNotEmpty)
        _DeckSlide(
          title: 'Executive Summary',
          eyebrow: 'Summary',
          kind: _DeckSlideKind.content,
          bullets: _sentences(document.summary).take(5).toList(growable: false),
        ),
      _keyTakeaways(document, sections),
      _implementationRoadmap(document, sections),
    ];
    for (final section in sections) {
      final bullets = [
        ...section.bullets,
        if (section.bullets.isEmpty && section.body.isNotEmpty)
          ..._sentences(section.body).take(5),
      ];
      slides
        ..add(_sectionDivider(section, bullets))
        ..add(
          _DeckSlide(
            title: _contentTitle(section.title),
            eyebrow: _contentEyebrow(section.title),
            kind: _sectionKind(section.title),
            bullets: _recommendationBullets(section.title, bullets),
          ),
        );
    }
    if (document.tables.isNotEmpty) {
      slides.add(_dataSnapshot(document));
      for (final table in document.tables.take(4)) {
        slides.add(
          _DeckSlide(
            title: table.title,
            eyebrow: 'Data table',
            kind: _DeckSlideKind.table,
            bullets: _tableBullets(table).take(4).toList(growable: false),
            tableRows: table.rows.take(7).toList(growable: false),
          ),
        );
      }
    }
    slides.add(_assumptionsAndSources(document));
    slides.add(_appendixHandoff(document));
    return slides;
  }

  _DeckSlide _executiveRecommendation(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    final recommendation = _firstMatchingBullet(sections, [
      'recommend',
      'solution',
      'architecture',
      'proposal',
    ]);
    final validation = _firstMatchingBullet(sections, [
      'validate',
      'verify',
      'evidence',
      'source',
    ]);
    final next = _firstMatchingBullet(sections, ['next', 'phase', 'action']);
    return _DeckSlide(
      title: 'Executive Recommendation',
      eyebrow: 'Decision-ready guidance',
      kind: _DeckSlideKind.recommendation,
      bullets: [
        recommendation == null
            ? 'Recommendation: Align on the preferred path, then turn this deck into a reviewed implementation artifact.'
            : 'Recommendation: $recommendation',
        if (document.summary.isNotEmpty)
          'Business context: ${_truncate(document.summary, 150)}',
        validation == null
            ? 'Validation: Confirm source data, stakeholder assumptions, and approval criteria before execution.'
            : 'Validation: $validation',
        next == null
            ? 'Next action: Assign owners, confirm timeline, and approve the first implementation batch.'
            : 'Next action: $next',
      ],
    );
  }

  _DeckSlide _keyTakeaways(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    final recommendation = _firstMatchingBullet(sections, [
      'recommend',
      'solution',
      'architecture',
    ]);
    final risk = _firstMatchingBullet(sections, ['risk', 'caveat', 'concern']);
    final next = _firstMatchingBullet(sections, ['next', 'phase', 'action']);
    return _DeckSlide(
      title: 'Key Takeaways',
      eyebrow: 'Executive highlights',
      kind: _DeckSlideKind.takeaways,
      bullets: [
        if (document.summary.isNotEmpty)
          'Outcome: ${_truncate(document.summary, 150)}',
        if (recommendation != null)
          'Recommendation: ${_truncate(recommendation, 145)}',
        if (risk != null) 'Watch item: ${_truncate(risk, 145)}',
        if (next != null) 'Next action: ${_truncate(next, 145)}',
        if (document.tables.isNotEmpty)
          'Data: ${document.tables.length} supporting table${document.tables.length == 1 ? '' : 's'} packaged with the deck.',
      ],
    );
  }

  _DeckSlide _decisionSnapshot(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    final recommendation = _firstMatchingBullet(sections, [
      'recommend',
      'solution',
      'architecture',
    ]);
    final risk = _firstMatchingBullet(sections, ['risk', 'caveat', 'concern']);
    final next = _firstMatchingBullet(sections, ['next', 'phase', 'action']);
    return _DeckSlide(
      title: 'Decision Snapshot',
      eyebrow: 'Executive readout',
      kind: _DeckSlideKind.snapshot,
      bullets: [
        recommendation == null
            ? 'Recommendation: Review the proposed approach and confirm the desired implementation path.'
            : 'Recommendation: $recommendation',
        risk == null
            ? 'Risk: Validate assumptions, source data, and implementation constraints before final approval.'
            : 'Risk: $risk',
        next == null
            ? 'Next step: Align on scope, owners, and verification criteria.'
            : 'Next step: $next',
        if (document.tables.isNotEmpty)
          'Evidence: ${document.tables.length} structured data table${document.tables.length == 1 ? '' : 's'} included.',
      ],
    );
  }

  _DeckSlide _dataSnapshot(ArtifactDocument document) {
    return _DeckSlide(
      title: 'Data Snapshot',
      eyebrow: 'Supporting detail',
      kind: _DeckSlideKind.dataSnapshot,
      bullets: [
        for (final table in document.tables.take(6))
          '${table.title}: ${math.max(0, table.rows.length - 1)} row${table.rows.length == 2 ? '' : 's'} across ${table.rows.isEmpty ? 0 : table.rows.first.length} column${table.rows.isNotEmpty && table.rows.first.length == 1 ? '' : 's'}',
        if (document.tables.length > 6)
          '${document.tables.length - 6} additional table${document.tables.length - 6 == 1 ? '' : 's'} available in the source artifact.',
      ],
    );
  }

  _DeckSlide _implementationRoadmap(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    final roadmapBullets = <String>[];
    for (final section in sections) {
      final title = section.title.toLowerCase();
      if (!title.contains('next') &&
          !title.contains('phase') &&
          !title.contains('roadmap') &&
          !title.contains('implement') &&
          !title.contains('verification')) {
        continue;
      }
      roadmapBullets.addAll(section.bullets);
      if (roadmapBullets.isEmpty && section.body.trim().isNotEmpty) {
        roadmapBullets.addAll(_sentences(section.body).take(4));
      }
    }
    if (roadmapBullets.isEmpty) {
      roadmapBullets.addAll([
        'Confirm stakeholder goals, scope, owners, and approval path.',
        if (document.tables.isNotEmpty)
          'Validate source data from ${document.tables.length} supporting table${document.tables.length == 1 ? '' : 's'}.',
        'Finalize recommendations, assumptions, risks, and success criteria.',
        'Run implementation or handoff review and capture verification evidence.',
      ]);
    }
    return _DeckSlide(
      title: 'Implementation Roadmap',
      eyebrow: 'Action plan',
      kind: _DeckSlideKind.roadmap,
      bullets: roadmapBullets.take(6).toList(growable: false),
    );
  }

  _DeckSlide _assumptionsAndSources(ArtifactDocument document) {
    final bullets = <String>[
      if (document.assumptions.isEmpty)
        'Assumption: Customer requirements, constraints, and implementation timeline require final confirmation.',
      for (final item in document.assumptions.take(5)) 'Assumption: $item',
      if (document.citations.isEmpty)
        'Source: No external citations were attached; treat this as a draft until evidence is added.',
      for (final item in document.citations.take(5)) 'Source: $item',
    ];
    return _DeckSlide(
      title: 'Assumptions & Sources',
      eyebrow: 'Evidence handoff',
      kind: _DeckSlideKind.sources,
      bullets: bullets,
    );
  }

  _DeckSlide _appendixHandoff(ArtifactDocument document) {
    final artifactTypes = <String>[
      if (document.tables.isNotEmpty)
        '${document.tables.length} data table${document.tables.length == 1 ? '' : 's'}',
      if (document.assumptions.isNotEmpty)
        '${document.assumptions.length} assumption${document.assumptions.length == 1 ? '' : 's'}',
      if (document.citations.isNotEmpty)
        '${document.citations.length} source item${document.citations.length == 1 ? '' : 's'}',
    ];
    return _DeckSlide(
      title: 'Appendix: Handoff Checklist',
      eyebrow: 'Review package',
      kind: _DeckSlideKind.appendix,
      bullets: [
        'Review scope: Confirm title, executive summary, recommendations, risks, and next actions with the account team.',
        if (artifactTypes.isEmpty)
          'Supporting material: Attach source data, citations, and customer assumptions before final delivery.'
        else
          'Supporting material: ${artifactTypes.join(', ')} included in this generated artifact.',
        'Customer readiness: Validate terminology, product names, dates, and stakeholder-specific language.',
        'Approval path: Capture owner, due date, and success criteria before converting this into an implementation packet.',
      ],
    );
  }

  String? _firstMatchingBullet(
    List<ArtifactSection> sections,
    List<String> terms,
  ) {
    for (final section in sections) {
      final title = section.title.toLowerCase();
      final titleMatches = terms.any(title.contains);
      final candidates = [
        ...section.bullets,
        ..._sentences(section.body).take(3),
      ];
      if (titleMatches && candidates.isNotEmpty) return candidates.first;
      for (final candidate in candidates) {
        final normalized = candidate.toLowerCase();
        if (terms.any(normalized.contains)) return candidate;
      }
    }
    return null;
  }

  String _sectionEyebrow(String title) {
    final normalized = title.toLowerCase();
    if (normalized.contains('recommend')) return 'Recommendation';
    if (normalized.contains('risk')) return 'Risk review';
    if (normalized.contains('next')) return 'Next steps';
    if (normalized.contains('summary')) return 'Executive summary';
    return 'Section';
  }

  _DeckSlide _sectionDivider(ArtifactSection section, List<String> bullets) {
    return _DeckSlide(
      title: section.title,
      eyebrow: _sectionEyebrow(section.title),
      kind: _DeckSlideKind.sectionDivider,
      bullets: bullets.take(2).toList(growable: false),
    );
  }

  String _contentTitle(String title) {
    final normalized = title.toLowerCase();
    if (normalized.contains('recommend')) return 'Recommendations';
    if (normalized.contains('next')) return 'Next Steps';
    return title;
  }

  String _contentEyebrow(String title) {
    final normalized = title.toLowerCase();
    if (normalized.contains('recommend')) return 'Recommendation slide';
    if (normalized.contains('next')) return 'Action plan';
    if (normalized.contains('risk')) return 'Risk detail';
    return 'Key points';
  }

  _DeckSlideKind _sectionKind(String title) {
    final normalized = title.toLowerCase();
    if (normalized.contains('recommend') ||
        normalized.contains('next') ||
        normalized.contains('decision')) {
      return _DeckSlideKind.recommendation;
    }
    return _DeckSlideKind.content;
  }

  List<String> _recommendationBullets(String title, List<String> bullets) {
    final normalized = title.toLowerCase();
    if (!normalized.contains('recommend') && !normalized.contains('next')) {
      return bullets;
    }
    return [
      for (final bullet in bullets.take(7))
        bullet.toLowerCase().startsWith('recommend') ||
                bullet.toLowerCase().startsWith('next')
            ? bullet
            : 'Recommendation: $bullet',
    ];
  }

  Iterable<String> _sentences(String body) {
    return body
        .replaceAll('\n', ' ')
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
  }

  List<String> _tableBullets(ArtifactTable table) {
    if (table.rows.isEmpty) return const [];
    final headers = table.rows.first;
    return [
      for (final row in table.rows.skip(1).take(8))
        [
          for (var i = 0; i < row.length && i < headers.length; i++)
            '${headers[i]}: ${row[i]}',
        ].join(' | '),
    ];
  }

  Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

  String _contentTypes(int count) {
    final slides = List.generate(
      count,
      (i) =>
          '<Override PartName="/ppt/slides/slide${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>',
    ).join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
        '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
        '<Override PartName="/ppt/notesMasters/notesMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml"/>'
        '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
        '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
        '${List.generate(count, (i) => '<Override PartName="/ppt/notesSlides/notesSlide${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml"/>').join()}'
        '$slides</Types>';
  }

  String _rootRels() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
        '</Relationships>';
  }

  String _appXml(int slideCount) {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
        '<Application>CircuitCode</Application>'
        '<PresentationFormat>On-screen Show (16:9)</PresentationFormat>'
        '<Slides>$slideCount</Slides>'
        '<Company>CircuitCode</Company>'
        '</Properties>';
  }

  String _coreXml(String title) {
    final now = DateTime.now().toUtc().toIso8601String();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:title>${_xml(title)}</dc:title>'
        '<dc:creator>CircuitCode</dc:creator>'
        '<dc:description>Enterprise presentation artifact generated by CircuitCode.</dc:description>'
        '<cp:lastModifiedBy>CircuitCode</cp:lastModifiedBy>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">$now</dcterms:created>'
        '<dcterms:modified xsi:type="dcterms:W3CDTF">$now</dcterms:modified>'
        '</cp:coreProperties>';
  }

  String _presentation(int count) {
    final ids = List.generate(
      count,
      (i) => '<p:sldId id="${256 + i}" r:id="rId${i + 3}"/>',
    ).join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
        '<p:notesMasterIdLst><p:notesMasterId r:id="rId2"/></p:notesMasterIdLst>'
        '<p:sldIdLst>$ids</p:sldIdLst><p:sldSz cx="12192000" cy="6858000" type="screen16x9"/>'
        '<p:notesSz cx="6858000" cy="9144000"/></p:presentation>';
  }

  String _presentationRels(int count) {
    final slides = List.generate(
      count,
      (i) =>
          '<Relationship Id="rId${i + 3}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide${i + 1}.xml"/>',
    ).join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster" Target="notesMasters/notesMaster1.xml"/>'
        '$slides</Relationships>';
  }

  String _slide(
    _DeckSlide slide, {
    required _DeckTheme theme,
    required int slideNumber,
    required int totalSlides,
  }) {
    final titleSize = slide.kind == _DeckSlideKind.title ? 5000 : 3500;
    final bodyY = slide.kind == _DeckSlideKind.title ? 2050000 : 1720000;
    final accent = theme.accentFor(slide.kind);
    final background = theme.backgroundFor(slide.kind);
    final body = slide.tableRows.isNotEmpty
        ? _tableSlideBody(slide, bodyY: bodyY, accent: accent, theme: theme)
        : _bulletSlideBody(slide, bodyY: bodyY, theme: theme);
    final panelColor =
        slide.kind == _DeckSlideKind.title ||
            slide.kind == _DeckSlideKind.sectionDivider
        ? background
        : theme.panel;
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
        '${_shape(id: 2, name: 'Background', x: 0, y: 0, w: 12192000, h: 6858000, color: background)}'
        '${_shape(id: 3, name: 'Accent', x: 0, y: 0, w: 145000, h: 6858000, color: accent)}'
        '${_shape(id: 8, name: 'Content panel', x: 540000, y: 1640000, w: 11100000, h: 4550000, color: panelColor)}'
        '${_shape(id: 9, name: 'Header rule', x: 600000, y: 1510000, w: 2600000, h: 28000, color: accent)}'
        '${_textBox(id: 4, name: 'Eyebrow', x: 600000, y: 320000, w: 6500000, h: 320000, text: _xml(slide.eyebrow), size: 1200, bold: true, color: accent)}'
        '${_textBox(id: 7, name: 'Slide type', x: 9700000, y: 340000, w: 1700000, h: 280000, text: _xml(slide.kind.label), size: 1000, bold: true, color: theme.mutedText)}'
        '${_textBox(id: 5, name: 'Title', x: 600000, y: 680000, w: 10800000, h: 900000, text: _xml(slide.title), size: titleSize, bold: true)}'
        '$body'
        '${_textBox(id: 90, name: 'Footer', x: 600000, y: 6420000, w: 7600000, h: 260000, text: 'CircuitCode - Generated artifact - ${theme.label} theme', size: 1000, bold: false, color: theme.mutedText)}'
        '${_textBox(id: 91, name: 'Slide number', x: 10450000, y: 6420000, w: 1200000, h: 260000, text: 'Slide $slideNumber of $totalSlides', size: 1000, bold: false, color: theme.mutedText)}'
        '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>';
  }

  String _bulletSlideBody(
    _DeckSlide slide, {
    required int bodyY,
    required _DeckTheme theme,
  }) {
    final bullets = slide.bullets
        .where((bullet) => bullet.trim().isNotEmpty)
        .take(slide.kind == _DeckSlideKind.title ? 5 : 8)
        .toList(growable: false);
    if (slide.kind == _DeckSlideKind.snapshot ||
        slide.kind == _DeckSlideKind.dataSnapshot) {
      return _tileSlideBody(
        slide,
        bullets: bullets,
        bodyY: bodyY,
        theme: theme,
      );
    }
    if (slide.kind == _DeckSlideKind.agenda) {
      return _agendaSlideBody(
        slide,
        bullets: bullets,
        bodyY: bodyY,
        theme: theme,
      );
    }
    if (slide.kind == _DeckSlideKind.recommendation) {
      return _recommendationSlideBody(
        slide,
        bullets: bullets,
        bodyY: bodyY,
        theme: theme,
      );
    }
    if (slide.kind == _DeckSlideKind.roadmap) {
      return _roadmapSlideBody(
        slide,
        bullets: bullets,
        bodyY: bodyY,
        theme: theme,
      );
    }
    final body = bullets
        .map(
          (bullet) =>
              '<a:p><a:r><a:rPr lang="en-US" sz="${slide.kind == _DeckSlideKind.title ? 2400 : 2050}"><a:solidFill><a:srgbClr val="${theme.bodyText}"/></a:solidFill></a:rPr><a:t>${_xml(bullet)}</a:t></a:r></a:p>',
        )
        .join();
    return '<p:sp><p:nvSpPr><p:cNvPr id="6" name="Body"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="760000" y="$bodyY"/><a:ext cx="10680000" cy="4300000"/></a:xfrm></p:spPr>'
        '<p:txBody><a:bodyPr wrap="square"/><a:lstStyle/>$body</p:txBody></p:sp>';
  }

  String _tileSlideBody(
    _DeckSlide slide, {
    required List<String> bullets,
    required int bodyY,
    required _DeckTheme theme,
  }) {
    final accent = theme.accentFor(slide.kind);
    final parts = <String>[];
    const x = 760000;
    const tileWidth = 5000000;
    const tileHeight = 880000;
    var id = 120;
    for (var i = 0; i < bullets.take(4).length; i++) {
      final bullet = bullets[i];
      final tileX = x + ((i % 2) * 5360000);
      final tileY = bodyY + ((i ~/ 2) * 1120000);
      final label = i == 0
          ? '01'
          : i == 1
          ? '02'
          : i == 2
          ? '03'
          : '04';
      parts
        ..add(
          _shape(
            id: id++,
            name: 'Insight tile',
            x: tileX,
            y: tileY,
            w: tileWidth,
            h: tileHeight,
            color: theme.tile,
          ),
        )
        ..add(
          _textBox(
            id: id++,
            name: 'Insight number',
            x: tileX + 160000,
            y: tileY + 120000,
            w: 420000,
            h: 250000,
            text: label,
            size: 1200,
            bold: true,
            color: accent,
          ),
        )
        ..add(
          _textBox(
            id: id++,
            name: 'Insight text',
            x: tileX + 620000,
            y: tileY + 120000,
            w: tileWidth - 820000,
            h: tileHeight - 180000,
            text: _xml(_truncate(bullet, 150)),
            size: 1350,
            bold: false,
            color: theme.bodyText,
          ),
        );
    }
    return parts.join();
  }

  String _agendaSlideBody(
    _DeckSlide slide, {
    required List<String> bullets,
    required int bodyY,
    required _DeckTheme theme,
  }) {
    final parts = <String>[];
    const x = 760000;
    const rowWidth = 10380000;
    const rowHeight = 430000;
    var id = 170;
    for (var i = 0; i < bullets.take(7).length; i++) {
      final y = bodyY + (i * 520000);
      final number = '${i + 1}'.padLeft(2, '0');
      parts
        ..add(
          _shape(
            id: id++,
            name: 'Agenda step',
            x: x,
            y: y,
            w: rowWidth,
            h: rowHeight,
            color: i.isEven ? theme.tile : theme.panel,
          ),
        )
        ..add(
          _shape(
            id: id++,
            name: 'Agenda number rail',
            x: x,
            y: y,
            w: 520000,
            h: rowHeight,
            color: theme.accentFor(slide.kind),
          ),
        )
        ..add(
          _textBox(
            id: id++,
            name: 'Agenda number',
            x: x + 130000,
            y: y + 94000,
            w: 320000,
            h: 220000,
            text: number,
            size: 1400,
            bold: true,
            color: theme.headerText,
          ),
        )
        ..add(
          _textBox(
            id: id++,
            name: 'Agenda item',
            x: x + 700000,
            y: y + 90000,
            w: rowWidth - 900000,
            h: 260000,
            text: _xml(_truncate(bullets[i], 95)),
            size: 1550,
            bold: true,
            color: theme.bodyText,
          ),
        );
    }
    return parts.join();
  }

  String _recommendationSlideBody(
    _DeckSlide slide, {
    required List<String> bullets,
    required int bodyY,
    required _DeckTheme theme,
  }) {
    final labels = ['Decision', 'Rationale', 'Validation', 'Next action'];
    final parts = <String>[];
    const x = 760000;
    const cardWidth = 5000000;
    const cardHeight = 1100000;
    var id = 220;
    for (var i = 0; i < bullets.take(4).length; i++) {
      final cardX = x + ((i % 2) * 5360000);
      final cardY = bodyY + ((i ~/ 2) * 1360000);
      parts
        ..add(
          _shape(
            id: id++,
            name: 'Recommendation card',
            x: cardX,
            y: cardY,
            w: cardWidth,
            h: cardHeight,
            color: theme.tile,
          ),
        )
        ..add(
          _shape(
            id: id++,
            name: 'Recommendation card accent',
            x: cardX,
            y: cardY,
            w: 90000,
            h: cardHeight,
            color: theme.accentFor(slide.kind),
          ),
        )
        ..add(
          _textBox(
            id: id++,
            name: 'Recommendation label',
            x: cardX + 210000,
            y: cardY + 130000,
            w: cardWidth - 420000,
            h: 220000,
            text: labels[i],
            size: 1250,
            bold: true,
            color: theme.accentFor(slide.kind),
          ),
        )
        ..add(
          _textBox(
            id: id++,
            name: 'Recommendation text',
            x: cardX + 210000,
            y: cardY + 420000,
            w: cardWidth - 460000,
            h: 520000,
            text: _xml(_truncate(_stripLeadLabel(bullets[i]), 150)),
            size: 1350,
            bold: false,
            color: theme.bodyText,
          ),
        );
    }
    return parts.join();
  }

  String _roadmapSlideBody(
    _DeckSlide slide, {
    required List<String> bullets,
    required int bodyY,
    required _DeckTheme theme,
  }) {
    final steps = bullets.take(5).toList(growable: false);
    final parts = <String>[];
    const x = 860000;
    const y = 2850000;
    const stepWidth = 1900000;
    var id = 270;
    if (steps.length > 1) {
      parts.add(
        _shape(
          id: id++,
          name: 'Roadmap timeline',
          x: x + 420000,
          y: y + 280000,
          w: ((steps.length - 1) * stepWidth),
          h: 28000,
          color: theme.accentFor(slide.kind),
        ),
      );
    }
    for (var i = 0; i < steps.length; i++) {
      final stepX = x + (i * stepWidth);
      parts
        ..add(
          _shape(
            id: id++,
            name: 'Roadmap phase marker',
            x: stepX + 300000,
            y: y + 120000,
            w: 370000,
            h: 370000,
            color: theme.accentFor(slide.kind),
          ),
        )
        ..add(
          _textBox(
            id: id++,
            name: 'Roadmap phase number',
            x: stepX + 390000,
            y: y + 218000,
            w: 190000,
            h: 160000,
            text: '${i + 1}',
            size: 1200,
            bold: true,
            color: theme.headerText,
          ),
        )
        ..add(
          _textBox(
            id: id++,
            name: 'Roadmap phase text',
            x: stepX,
            y: y + 700000,
            w: stepWidth - 140000,
            h: 920000,
            text: _xml(_truncate(steps[i], 95)),
            size: 1250,
            bold: false,
            color: theme.bodyText,
          ),
        );
    }
    if (steps.isEmpty) {
      return _bulletSlideBody(slide, bodyY: bodyY, theme: theme);
    }
    return parts.join();
  }

  String _tableSlideBody(
    _DeckSlide slide, {
    required int bodyY,
    required String accent,
    required _DeckTheme theme,
  }) {
    final rows = slide.tableRows.take(7).toList(growable: false);
    if (rows.isEmpty) {
      return _bulletSlideBody(slide, bodyY: bodyY, theme: theme);
    }
    final columnCount = rows
        .fold<int>(0, (max, row) => row.length > max ? row.length : max)
        .clamp(1, 5);
    const x = 760000;
    final width = 10680000 ~/ columnCount;
    const height = 430000;
    final parts = <String>[];
    var id = 20;
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      for (var columnIndex = 0; columnIndex < columnCount; columnIndex++) {
        final value = columnIndex < row.length ? row[columnIndex] : '';
        final cellX = x + (columnIndex * width);
        final cellY = bodyY + (rowIndex * height);
        final fill = rowIndex == 0
            ? accent
            : (rowIndex.isEven ? theme.tile : theme.panel);
        parts
          ..add(
            _shape(
              id: id++,
              name: 'Table cell',
              x: cellX,
              y: cellY,
              w: width - 10000,
              h: height - 10000,
              color: fill,
            ),
          )
          ..add(
            _textBox(
              id: id++,
              name: 'Table text',
              x: cellX + 90000,
              y: cellY + 60000,
              w: width - 180000,
              h: height - 90000,
              text: _xml(_truncate(value, rowIndex == 0 ? 32 : 42)),
              size: rowIndex == 0 ? 1200 : 1100,
              bold: rowIndex == 0,
              color: rowIndex == 0 ? theme.headerText : theme.bodyText,
            ),
          );
      }
    }
    if (slide.bullets.isNotEmpty) {
      parts.add(
        _textBox(
          id: id++,
          name: 'Table note',
          x: 760000,
          y: bodyY + (rows.length * height) + 160000,
          w: 10680000,
          h: 360000,
          text: _xml(_truncate(slide.bullets.first, 140)),
          size: 1200,
          bold: false,
          color: theme.secondaryText,
        ),
      );
    }
    return parts.join();
  }

  String _truncate(String value, int max) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= max) return normalized;
    return '${normalized.substring(0, max - 3)}...';
  }

  String _stripLeadLabel(String value) {
    return value.replaceFirst(
      RegExp(
        r'^\s*(recommendation|validation|next action|next step|risk):\s*',
        caseSensitive: false,
      ),
      '',
    );
  }

  String _shape({
    required int id,
    required String name,
    required int x,
    required int y,
    required int w,
    required int h,
    required String color,
  }) {
    return '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="$name"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$w" cy="$h"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="$color"/></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr></p:sp>';
  }

  String _textBox({
    required int id,
    required String name,
    required int x,
    required int y,
    required int w,
    required int h,
    required String text,
    required int size,
    required bool bold,
    String color = 'FFFFFF',
  }) {
    return '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="$name"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$w" cy="$h"/></a:xfrm></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US" sz="$size"${bold ? ' b="1"' : ''}><a:solidFill><a:srgbClr val="$color"/></a:solidFill></a:rPr><a:t>$text</a:t></a:r></a:p></p:txBody></p:sp>';
  }

  String _slideRels(int slideNumber) {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide" Target="../notesSlides/notesSlide$slideNumber.xml"/>'
        '</Relationships>';
  }

  String _notesSlide(_DeckSlide slide, {required int slideNumber}) {
    final notes = [
      'Presenter notes for ${slide.title}.',
      if (slide.eyebrow.isNotEmpty) 'Context: ${slide.eyebrow}.',
      for (final bullet in slide.bullets.take(5)) 'Talking point: $bullet',
      if (slide.tableRows.isNotEmpty)
        'Data note: This slide includes ${math.max(0, slide.tableRows.length - 1)} supporting row${slide.tableRows.length == 2 ? '' : 's'}.',
    ].join(' ');
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:notes xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Notes Placeholder $slideNumber"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="685800" y="914400"/><a:ext cx="5486400" cy="6858000"/></a:xfrm></p:spPr>'
        '<p:txBody><a:bodyPr wrap="square"/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US" sz="1200"><a:solidFill><a:srgbClr val="111111"/></a:solidFill></a:rPr><a:t>${_xml(_truncate(notes, 900))}</a:t></a:r></a:p></p:txBody></p:sp>'
        '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>';
  }

  String _notesSlideRels(int slideNumber) {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="../slides/slide$slideNumber.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster" Target="../notesMasters/notesMaster1.xml"/>'
        '</Relationships>';
  }

  String _slideMaster() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>'
        '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
        '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>';
  }

  String _slideMasterRels() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>'
        '</Relationships>';
  }

  String _notesMaster() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:notesMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="CircuitCode Notes Master"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="457200" y="457200"/><a:ext cx="5943600" cy="365760"/></a:xfrm></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US" sz="1100"><a:t>CircuitCode speaker notes</a:t></a:r></a:p></p:txBody></p:sp>'
        '</p:spTree></p:cSld><p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/></p:notesMaster>';
  }

  String _notesMasterRels() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>'
        '</Relationships>';
  }

  String _slideLayout() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank">'
        '<p:cSld name="Blank"><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld></p:sldLayout>';
  }

  String _slideLayoutRels() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>'
        '</Relationships>';
  }

  String _theme() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Circuit">'
        '<a:themeElements><a:clrScheme name="Circuit"><a:dk1><a:srgbClr val="111111"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="1F2933"/></a:dk2><a:lt2><a:srgbClr val="F3F4F6"/></a:lt2><a:accent1><a:srgbClr val="7FB7B2"/></a:accent1><a:accent2><a:srgbClr val="7A9CC6"/></a:accent2><a:accent3><a:srgbClr val="C7A77B"/></a:accent3><a:accent4><a:srgbClr val="A7C080"/></a:accent4><a:accent5><a:srgbClr val="D08770"/></a:accent5><a:accent6><a:srgbClr val="B48EAD"/></a:accent6><a:hlink><a:srgbClr val="3B82F6"/></a:hlink><a:folHlink><a:srgbClr val="7C3AED"/></a:folHlink></a:clrScheme><a:fontScheme name="Circuit"><a:majorFont><a:latin typeface="Aptos Display"/></a:majorFont><a:minorFont><a:latin typeface="Aptos"/></a:minorFont></a:fontScheme><a:fmtScheme name="Circuit"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>';
  }

  String _xml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }
}

class _DeckSlide {
  final String title;
  final String eyebrow;
  final _DeckSlideKind kind;
  final List<String> bullets;
  final List<List<String>> tableRows;

  const _DeckSlide({
    required this.title,
    required this.eyebrow,
    required this.kind,
    required this.bullets,
    this.tableRows = const [],
  });
}

enum _DeckSlideKind {
  title,
  agenda,
  snapshot,
  dataSnapshot,
  takeaways,
  sectionDivider,
  content,
  recommendation,
  roadmap,
  table,
  appendix,
  sources;

  String get label {
    return switch (this) {
      _DeckSlideKind.title => 'Title',
      _DeckSlideKind.agenda => 'Agenda',
      _DeckSlideKind.snapshot => 'Decision',
      _DeckSlideKind.dataSnapshot => 'Data',
      _DeckSlideKind.takeaways => 'Takeaways',
      _DeckSlideKind.sectionDivider => 'Section',
      _DeckSlideKind.content => 'Content',
      _DeckSlideKind.recommendation => 'Recommendation',
      _DeckSlideKind.roadmap => 'Roadmap',
      _DeckSlideKind.table => 'Table',
      _DeckSlideKind.appendix => 'Appendix',
      _DeckSlideKind.sources => 'Sources',
    };
  }
}

class _DeckTheme {
  final String label;
  final String canvas;
  final String panel;
  final String tile;
  final String bodyText;
  final String secondaryText;
  final String mutedText;
  final String headerText;

  const _DeckTheme._({
    required this.label,
    required this.canvas,
    required this.panel,
    required this.tile,
    required this.bodyText,
    required this.secondaryText,
    required this.mutedText,
    required this.headerText,
  });

  factory _DeckTheme.forDocument(ArtifactDocument document) {
    final prompt = '${document.metadata['prompt'] ?? ''}'.toLowerCase();
    final explicitTheme = '${document.metadata['theme'] ?? ''}'.toLowerCase();
    final wantsLight =
        explicitTheme.contains('light') ||
        prompt.contains('light theme') ||
        prompt.contains('white background') ||
        prompt.contains('customer-facing light');
    if (wantsLight) {
      return const _DeckTheme._(
        label: 'Light',
        canvas: 'F8FAFC',
        panel: 'FFFFFF',
        tile: 'EEF2F7',
        bodyText: '111827',
        secondaryText: '475569',
        mutedText: '64748B',
        headerText: '111111',
      );
    }
    return const _DeckTheme._(
      label: 'Dark',
      canvas: '161616',
      panel: '202020',
      tile: '242424',
      bodyText: 'F4F4F5',
      secondaryText: 'C4C7CC',
      mutedText: '8A8F98',
      headerText: '111111',
    );
  }

  String accentFor(_DeckSlideKind kind) {
    return switch (kind) {
      _DeckSlideKind.title => '7FB7B2',
      _DeckSlideKind.agenda => '7A9CC6',
      _DeckSlideKind.snapshot => '78AAA5',
      _DeckSlideKind.dataSnapshot => 'B48EAD',
      _DeckSlideKind.takeaways => '7FB7B2',
      _DeckSlideKind.sectionDivider => 'C7A77B',
      _DeckSlideKind.recommendation => 'A7C080',
      _DeckSlideKind.roadmap => 'A7C080',
      _DeckSlideKind.table => 'B48EAD',
      _DeckSlideKind.appendix => '8A8F98',
      _DeckSlideKind.sources => '7A9CC6',
      _DeckSlideKind.content => '7FB7B2',
    };
  }

  String backgroundFor(_DeckSlideKind kind) {
    if (label == 'Light') {
      return switch (kind) {
        _DeckSlideKind.title || _DeckSlideKind.sectionDivider => 'F8FAFC',
        _DeckSlideKind.snapshot ||
        _DeckSlideKind.takeaways ||
        _DeckSlideKind.roadmap => 'F1F5F9',
        _ => canvas,
      };
    }
    return switch (kind) {
      _DeckSlideKind.title || _DeckSlideKind.sectionDivider => '111111',
      _DeckSlideKind.snapshot ||
      _DeckSlideKind.takeaways ||
      _DeckSlideKind.roadmap => '121715',
      _ => canvas,
    };
  }
}

class _PptxFile {
  final String path;
  final Uint8List bytes;

  const _PptxFile(this.path, this.bytes);
}

Uint8List _zip(List<_PptxFile> files) {
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
