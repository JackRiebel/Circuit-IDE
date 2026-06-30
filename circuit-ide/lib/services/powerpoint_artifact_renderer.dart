import 'dart:convert';
import 'dart:typed_data';

import '../models/artifact_document.dart';

class PowerPointArtifactRenderer {
  const PowerPointArtifactRenderer();

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
    final slides = <_DeckSlide>[
      _DeckSlide(
        title: document.title,
        bullets: [
          if (document.summary.isNotEmpty) document.summary,
          if (document.tables.isNotEmpty)
            '${document.tables.length} table artifact${document.tables.length == 1 ? '' : 's'} included',
          if (document.citations.isNotEmpty)
            '${document.citations.length} source item${document.citations.length == 1 ? '' : 's'} captured',
        ],
      ),
    ];
    for (final section in document.sections) {
      final bullets = [
        ...section.bullets,
        if (section.bullets.isEmpty && section.body.isNotEmpty)
          ..._sentences(section.body).take(5),
      ];
      slides.add(_DeckSlide(title: section.title, bullets: bullets));
    }
    if (document.tables.isNotEmpty) {
      for (final table in document.tables.take(4)) {
        slides.add(
          _DeckSlide(
            title: table.title,
            bullets: _tableBullets(table).take(7).toList(growable: false),
          ),
        );
      }
    }
    if (document.assumptions.isNotEmpty) {
      slides.add(
        _DeckSlide(title: 'Assumptions', bullets: document.assumptions),
      );
    }
    if (document.citations.isNotEmpty) {
      slides.add(_DeckSlide(title: 'Sources', bullets: document.citations));
    }
    return slides;
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
    final bullets = slide.bullets
        .where((bullet) => bullet.trim().isNotEmpty)
        .take(8)
        .map(
          (bullet) =>
              '<a:p><a:r><a:rPr lang="en-US" sz="2200"/><a:t>${_xml(bullet)}</a:t></a:r></a:p>',
        )
        .join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
        '${_textBox(id: 2, name: 'Title', x: 600000, y: 420000, w: 11000000, h: 720000, text: _xml(slide.title), size: 3200, bold: true)}'
        '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Body"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="760000" y="1400000"/><a:ext cx="10680000" cy="4700000"/></a:xfrm></p:spPr>'
        '<p:txBody><a:bodyPr wrap="square"/><a:lstStyle/>$bullets</p:txBody></p:sp>'
        '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>';
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
  }) {
    return '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="$name"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$w" cy="$h"/></a:xfrm></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US" sz="$size"${bold ? ' b="1"' : ''}/><a:t>$text</a:t></a:r></a:p></p:txBody></p:sp>';
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
  final List<String> bullets;

  const _DeckSlide({required this.title, required this.bullets});
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
