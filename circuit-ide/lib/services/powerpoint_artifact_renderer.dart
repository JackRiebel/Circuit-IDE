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
    final files = <_PptxFile>[
      _PptxFile('[Content_Types].xml', _bytes(_contentTypes(slides.length))),
      _PptxFile('_rels/.rels', _bytes(_rootRels())),
      _PptxFile('docProps/app.xml', _bytes(_appXml())),
      _PptxFile('docProps/core.xml', _bytes(_coreXml())),
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
      _PptxFile('ppt/slideLayouts/slideLayout1.xml', _bytes(_slideLayout())),
      _PptxFile(
        'ppt/slideLayouts/_rels/slideLayout1.xml.rels',
        _bytes(_slideLayoutRels()),
      ),
      _PptxFile('ppt/theme/theme1.xml', _bytes(_theme())),
      for (var i = 0; i < slides.length; i++)
        _PptxFile('ppt/slides/slide${i + 1}.xml', _bytes(_slide(slides[i]))),
      for (var i = 0; i < slides.length; i++)
        _PptxFile(
          'ppt/slides/_rels/slide${i + 1}.xml.rels',
          _bytes(_slideRels()),
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
      if (document.summary.isNotEmpty)
        _DeckSlide(
          title: 'Executive Summary',
          eyebrow: 'Summary',
          kind: _DeckSlideKind.content,
          bullets: _sentences(document.summary).take(5).toList(growable: false),
        ),
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
    if (document.assumptions.isNotEmpty || document.citations.isNotEmpty) {
      slides.add(
        _DeckSlide(
          title: 'Assumptions & Sources',
          eyebrow: 'Evidence and caveats',
          kind: _DeckSlideKind.appendix,
          bullets: [
            ...document.assumptions.map((item) => 'Assumption: $item'),
            ...document.citations.map((item) => 'Source: $item'),
          ],
        ),
      );
    }
    return slides;
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
        '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
        '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
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

  String _appXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
        '<Application>CircuitCode</Application></Properties>';
  }

  String _coreXml() {
    final now = DateTime.now().toUtc().toIso8601String();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:creator>CircuitCode</dc:creator>'
        '<cp:lastModifiedBy>CircuitCode</cp:lastModifiedBy>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">$now</dcterms:created>'
        '<dcterms:modified xsi:type="dcterms:W3CDTF">$now</dcterms:modified>'
        '</cp:coreProperties>';
  }

  String _presentation(int count) {
    final ids = List.generate(
      count,
      (i) => '<p:sldId id="${256 + i}" r:id="rId${i + 2}"/>',
    ).join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
        '<p:sldIdLst>$ids</p:sldIdLst><p:sldSz cx="12192000" cy="6858000" type="screen16x9"/>'
        '<p:notesSz cx="6858000" cy="9144000"/></p:presentation>';
  }

  String _presentationRels(int count) {
    final slides = List.generate(
      count,
      (i) =>
          '<Relationship Id="rId${i + 2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide${i + 1}.xml"/>',
    ).join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>'
        '$slides</Relationships>';
  }

  String _slide(_DeckSlide slide) {
    final titleSize = slide.kind == _DeckSlideKind.title ? 4200 : 3200;
    final bodyY = slide.kind == _DeckSlideKind.title ? 2050000 : 1720000;
    final accent = _accentFor(slide.kind);
    final background = _backgroundFor(slide.kind);
    final body = slide.tableRows.isNotEmpty
        ? _tableSlideBody(slide, bodyY: bodyY, accent: accent)
        : _bulletSlideBody(slide, bodyY: bodyY);
    final panelColor =
        slide.kind == _DeckSlideKind.title ||
            slide.kind == _DeckSlideKind.sectionDivider
        ? background
        : '202020';
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
        '${_textBox(id: 7, name: 'Slide type', x: 9700000, y: 340000, w: 1700000, h: 280000, text: _xml(slide.kind.label), size: 1000, bold: true, color: '8A8F98')}'
        '${_textBox(id: 5, name: 'Title', x: 600000, y: 680000, w: 10800000, h: 900000, text: _xml(slide.title), size: titleSize, bold: true)}'
        '$body'
        '${_textBox(id: 90, name: 'Footer', x: 600000, y: 6420000, w: 7600000, h: 260000, text: 'CircuitCode - Generated artifact', size: 1000, bold: false, color: '8A8F98')}'
        '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>';
  }

  String _bulletSlideBody(_DeckSlide slide, {required int bodyY}) {
    final bullets = slide.bullets
        .where((bullet) => bullet.trim().isNotEmpty)
        .take(slide.kind == _DeckSlideKind.title ? 5 : 8)
        .toList(growable: false);
    if (slide.kind == _DeckSlideKind.snapshot ||
        slide.kind == _DeckSlideKind.dataSnapshot) {
      return _tileSlideBody(slide, bullets: bullets, bodyY: bodyY);
    }
    final body = bullets
        .map(
          (bullet) =>
              '<a:p><a:r><a:rPr lang="en-US" sz="${slide.kind == _DeckSlideKind.title ? 2300 : 2050}"><a:solidFill><a:srgbClr val="F4F4F5"/></a:solidFill></a:rPr><a:t>${_xml(bullet)}</a:t></a:r></a:p>',
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
  }) {
    final accent = _accentFor(slide.kind);
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
            color: '242424',
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
            color: 'F4F4F5',
          ),
        );
    }
    return parts.join();
  }

  String _tableSlideBody(
    _DeckSlide slide, {
    required int bodyY,
    required String accent,
  }) {
    final rows = slide.tableRows.take(7).toList(growable: false);
    if (rows.isEmpty) return _bulletSlideBody(slide, bodyY: bodyY);
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
            : (rowIndex.isEven ? '242424' : '1D1D1D');
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
              color: rowIndex == 0 ? '111111' : 'F4F4F5',
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
          color: 'C4C7CC',
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

  String _accentFor(_DeckSlideKind kind) {
    return switch (kind) {
      _DeckSlideKind.title => '7FB7B2',
      _DeckSlideKind.agenda => '7A9CC6',
      _DeckSlideKind.snapshot => '78AAA5',
      _DeckSlideKind.dataSnapshot => 'B48EAD',
      _DeckSlideKind.sectionDivider => 'C7A77B',
      _DeckSlideKind.recommendation => 'A7C080',
      _DeckSlideKind.table => 'B48EAD',
      _DeckSlideKind.appendix => '8A8F98',
      _DeckSlideKind.content => '7FB7B2',
    };
  }

  String _backgroundFor(_DeckSlideKind kind) {
    return switch (kind) {
      _DeckSlideKind.title || _DeckSlideKind.sectionDivider => '111111',
      _DeckSlideKind.snapshot => '121715',
      _ => '161616',
    };
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

  String _slideRels() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
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
  sectionDivider,
  content,
  recommendation,
  table,
  appendix;

  String get label {
    return switch (this) {
      _DeckSlideKind.title => 'Title',
      _DeckSlideKind.agenda => 'Agenda',
      _DeckSlideKind.snapshot => 'Decision',
      _DeckSlideKind.dataSnapshot => 'Data',
      _DeckSlideKind.sectionDivider => 'Section',
      _DeckSlideKind.content => 'Content',
      _DeckSlideKind.recommendation => 'Recommendation',
      _DeckSlideKind.table => 'Table',
      _DeckSlideKind.appendix => 'Appendix',
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
