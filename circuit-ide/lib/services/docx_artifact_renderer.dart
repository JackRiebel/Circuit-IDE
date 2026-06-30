import 'dart:convert';
import 'dart:typed_data';

import '../models/artifact_document.dart';

class DocxArtifactRenderer {
  const DocxArtifactRenderer();

  Uint8List render(ArtifactDocument document) {
    final files = <_DocxFile>[
      _DocxFile('[Content_Types].xml', _bytes(_contentTypes())),
      _DocxFile('_rels/.rels', _bytes(_rootRels())),
      _DocxFile('docProps/app.xml', _bytes(_appXml())),
      _DocxFile('docProps/core.xml', _bytes(_coreXml())),
      _DocxFile('word/document.xml', _bytes(_documentXml(document))),
      _DocxFile('word/styles.xml', _bytes(_stylesXml())),
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
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>';
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
        '<dc:title>${_xml('CircuitCode Report')}</dc:title>'
        '<dc:creator>CircuitCode</dc:creator>'
        '<cp:lastModifiedBy>CircuitCode</cp:lastModifiedBy>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">$now</dcterms:created>'
        '<dcterms:modified xsi:type="dcterms:W3CDTF">$now</dcterms:modified>'
        '</cp:coreProperties>';
  }

  String _stylesXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/><w:rPr><w:rFonts w:ascii="Aptos" w:hAnsi="Aptos"/><w:sz w:val="22"/></w:rPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:qFormat/><w:rPr><w:b/><w:color w:val="111111"/><w:sz w:val="42"/></w:rPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:qFormat/><w:rPr><w:b/><w:color w:val="111111"/><w:sz w:val="30"/></w:rPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:qFormat/><w:rPr><w:b/><w:color w:val="334155"/><w:sz w:val="25"/></w:rPr></w:style>'
        '</w:styles>';
  }

  String _documentXml(ArtifactDocument document) {
    final body = StringBuffer()
      ..write(_paragraph(document.title, style: 'Title'))
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
    if (document.assumptions.isNotEmpty) {
      body.write(_paragraph('Assumptions', style: 'Heading1'));
      for (final assumption in document.assumptions) {
        body.write(_bulletParagraph(assumption));
      }
    }
    if (document.citations.isNotEmpty) {
      body.write(_paragraph('Sources', style: 'Heading1'));
      for (final citation in document.citations) {
        body.write(_bulletParagraph(citation));
      }
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>$body'
        '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1080" w:right="1080" w:bottom="1080" w:left="1080" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
        '</w:body></w:document>';
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
    return '<w:p><w:pPr><w:ind w:left="360" w:hanging="180"/></w:pPr><w:r><w:t xml:space="preserve">• ${_xml(text.trim())}</w:t></w:r></w:p>';
  }

  String _table(ArtifactTable table) {
    final rows = table.rows.take(24).map(_tableRow).join();
    return '<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblBorders><w:top w:val="single" w:sz="4" w:color="D9DEE7"/><w:left w:val="single" w:sz="4" w:color="D9DEE7"/><w:bottom w:val="single" w:sz="4" w:color="D9DEE7"/><w:right w:val="single" w:sz="4" w:color="D9DEE7"/><w:insideH w:val="single" w:sz="4" w:color="E5E7EB"/><w:insideV w:val="single" w:sz="4" w:color="E5E7EB"/></w:tblBorders></w:tblPr>$rows</w:tbl>';
  }

  String _tableRow(List<String> row) {
    return '<w:tr>${row.take(8).map(_tableCell).join()}</w:tr>';
  }

  String _tableCell(String value) {
    return '<w:tc><w:tcPr><w:tcW w:w="2400" w:type="dxa"/></w:tcPr>${_paragraph(value, style: 'Normal')}</w:tc>';
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
