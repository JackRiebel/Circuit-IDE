import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/artifact_document.dart';
import '../models/generated_artifact.dart';
import 'architecture_review_pack_builder.dart';
import 'business_use_case_brief_builder.dart';
import 'chart_artifact_renderer.dart';
import 'diagram_artifact_renderer.dart';
import 'docx_artifact_renderer.dart';
import 'evidence_pack_builder.dart';
import 'lifecycle_eox_workbook_builder.dart';
import 'pdf_artifact_renderer.dart';
import 'powerpoint_artifact_renderer.dart';
import 'product_comparison_workbook_builder.dart';
import 'solution_sizing_workbook_builder.dart';

class GeneratedArtifactWriter {
  final ArtifactComposer composer;
  final PowerPointArtifactRenderer powerPointRenderer;
  final DocxArtifactRenderer docxRenderer;
  final PdfArtifactRenderer pdfRenderer;
  final DiagramArtifactRenderer diagramRenderer;
  final ChartArtifactRenderer chartRenderer;
  final LifecycleEoxWorkbookBuilder lifecycleEoxBuilder;
  final ProductComparisonWorkbookBuilder productComparisonBuilder;
  final SolutionSizingWorkbookBuilder solutionSizingBuilder;
  final ArchitectureReviewPackBuilder architectureReviewBuilder;
  final BusinessUseCaseBriefBuilder businessUseCaseBuilder;
  final EvidencePackBuilder evidencePackBuilder;

  const GeneratedArtifactWriter({
    this.composer = const ArtifactComposer(),
    this.powerPointRenderer = const PowerPointArtifactRenderer(),
    this.docxRenderer = const DocxArtifactRenderer(),
    this.pdfRenderer = const PdfArtifactRenderer(),
    this.diagramRenderer = const DiagramArtifactRenderer(),
    this.chartRenderer = const ChartArtifactRenderer(),
    this.lifecycleEoxBuilder = const LifecycleEoxWorkbookBuilder(),
    this.productComparisonBuilder = const ProductComparisonWorkbookBuilder(),
    this.solutionSizingBuilder = const SolutionSizingWorkbookBuilder(),
    this.architectureReviewBuilder = const ArchitectureReviewPackBuilder(),
    this.businessUseCaseBuilder = const BusinessUseCaseBriefBuilder(),
    this.evidencePackBuilder = const EvidencePackBuilder(),
  });

  Future<GeneratedArtifact?> writeFromAssistantOutput({
    required String rootPath,
    required String prompt,
    required String content,
    required String turnId,
    required String? threadId,
    required String? requestId,
  }) async {
    final requestedKind = detectGeneratedArtifactKind(prompt);
    if (requestedKind == null || content.trim().isEmpty) return null;
    final root = p.normalize(rootPath);
    final outputDir = Directory(p.join(root, 'outputs'));
    if (!p.isWithin(root, outputDir.path) && outputDir.path != root) {
      return null;
    }
    await outputDir.create(recursive: true);

    final baseName = _safeBaseName(prompt);
    final now = DateTime.now();
    final resolved = _resolveOutput(
      requestedKind: requestedKind,
      prompt: prompt,
      content: content,
      document: composer.fromAssistantOutput(prompt: prompt, content: content),
    );
    if (resolved == null) return null;

    final fileName = '$baseName.${resolved.extension}';
    final filePath = p.join(outputDir.path, fileName);
    final normalizedFilePath = p.normalize(filePath);
    if (!p.isWithin(root, normalizedFilePath)) return null;
    final file = File(normalizedFilePath);
    await file.writeAsBytes(resolved.bytes);
    final size = await file.length();
    return GeneratedArtifact(
      id: turnId,
      kind: resolved.kind,
      status: resolved.status,
      fileName: fileName,
      filePath: normalizedFilePath,
      summary: resolved.summary,
      byteSize: size,
      previewRows: resolved.previewRows,
      sheetCount: resolved.sheetCount,
      threadId: threadId,
      requestId: requestId,
      createdAt: now,
    );
  }

  Future<GeneratedArtifact?> writeStructuredArtifact({
    required String rootPath,
    required String prompt,
    required String content,
    required GeneratedArtifactKind targetKind,
    required String turnId,
    required String? threadId,
    required String? requestId,
  }) async {
    if (content.trim().isEmpty) return null;
    final root = p.normalize(rootPath);
    final outputDir = Directory(p.join(root, 'outputs'));
    if (!p.isWithin(root, outputDir.path) && outputDir.path != root) {
      return null;
    }
    await outputDir.create(recursive: true);

    final document = composer.fromAssistantOutput(
      prompt: prompt,
      content: content,
    );
    final resolved = _resolveOutput(
      requestedKind: targetKind,
      prompt: prompt,
      content: content,
      document: document,
    );
    if (resolved == null) return null;

    final baseName = _safeBaseName(prompt);
    final fileName = '$baseName.${resolved.extension}';
    final filePath = p.join(outputDir.path, fileName);
    final normalizedFilePath = p.normalize(filePath);
    if (!p.isWithin(root, normalizedFilePath)) return null;
    final file = File(normalizedFilePath);
    await file.writeAsBytes(resolved.bytes);
    final size = await file.length();
    return GeneratedArtifact(
      id: turnId,
      kind: resolved.kind,
      status: resolved.status,
      fileName: fileName,
      filePath: normalizedFilePath,
      summary: resolved.summary,
      byteSize: size,
      previewRows: resolved.previewRows,
      sheetCount: resolved.sheetCount,
      threadId: threadId,
      requestId: requestId,
      createdAt: DateTime.now(),
    );
  }

  _ResolvedArtifact? _resolveOutput({
    required GeneratedArtifactKind requestedKind,
    required String prompt,
    required String content,
    required ArtifactDocument document,
  }) {
    var documentForOutput = document;
    if (businessUseCaseBuilder.matches(prompt) &&
        (requestedKind == GeneratedArtifactKind.docx ||
            requestedKind == GeneratedArtifactKind.pdf ||
            requestedKind == GeneratedArtifactKind.powerPoint)) {
      documentForOutput = businessUseCaseBuilder.build(
        prompt: prompt,
        content: content,
        document: documentForOutput,
      );
    }
    if (architectureReviewBuilder.matches(prompt) &&
        (requestedKind == GeneratedArtifactKind.docx ||
            requestedKind == GeneratedArtifactKind.pdf ||
            requestedKind == GeneratedArtifactKind.powerPoint)) {
      documentForOutput = architectureReviewBuilder.build(
        prompt: prompt,
        content: content,
        document: documentForOutput,
      );
    }
    if (evidencePackBuilder.matches(prompt) &&
        (requestedKind == GeneratedArtifactKind.docx ||
            requestedKind == GeneratedArtifactKind.pdf ||
            requestedKind == GeneratedArtifactKind.powerPoint ||
            requestedKind == GeneratedArtifactKind.json)) {
      documentForOutput = evidencePackBuilder.build(
        prompt: prompt,
        content: content,
        document: documentForOutput,
      );
    }

    if (requestedKind == GeneratedArtifactKind.powerPoint) {
      final slideCount = powerPointRenderer.slideCountFor(documentForOutput);
      final bytes = powerPointRenderer.render(documentForOutput);
      final architectureReview = architectureReviewBuilder.matches(prompt);
      return _ResolvedArtifact(
        kind: GeneratedArtifactKind.powerPoint,
        status: GeneratedArtifactStatus.ready,
        extension: 'pptx',
        bytes: bytes,
        summary: architectureReview
            ? 'Created an architecture review PowerPoint deck with $slideCount slides, findings, risks, recommendations, validation, assumptions, and sources.'
            : 'Created a PowerPoint deck with $slideCount slides from the response structure.',
        previewRows: powerPointRenderer.previewRowsFor(documentForOutput),
        sheetCount: slideCount,
      );
    }

    if (requestedKind == GeneratedArtifactKind.docx) {
      final bytes = docxRenderer.render(documentForOutput);
      final businessUseCase = businessUseCaseBuilder.matches(prompt);
      final architectureReview = architectureReviewBuilder.matches(prompt);
      final evidencePack = evidencePackBuilder.matches(prompt);
      return _ResolvedArtifact(
        kind: GeneratedArtifactKind.docx,
        status: GeneratedArtifactStatus.ready,
        extension: 'docx',
        bytes: bytes,
        summary: businessUseCase
            ? 'Created a business use case brief with executive summary, prioritized use cases, solution mapping, stakeholder discovery, value metrics, next steps, assumptions, and sources.'
            : architectureReview
            ? 'Created an architecture review pack with findings matrix, risk register, recommendation roadmap, validation checklist, decisions, assumptions, and sources.'
            : evidencePack
            ? 'Created an evidence pack with claim-to-source matrix, source freshness register, unsupported-claim triage, confidence scorecard, assumptions, and follow-up checklist.'
            : 'Created a Word report with ${documentForOutput.sections.length} sections from the response structure.',
        previewRows: docxRenderer.previewRowsFor(documentForOutput),
        sheetCount: documentForOutput.sections.length,
      );
    }

    if (requestedKind == GeneratedArtifactKind.pdf) {
      final bytes = pdfRenderer.render(documentForOutput);
      final pageCount = _pdfPageCount(bytes);
      final architectureReview = architectureReviewBuilder.matches(prompt);
      return _ResolvedArtifact(
        kind: GeneratedArtifactKind.pdf,
        status: GeneratedArtifactStatus.ready,
        extension: 'pdf',
        bytes: bytes,
        summary: architectureReview
            ? 'Created an architecture review PDF with findings, risks, recommendations, validation, assumptions, and sources.'
            : 'Created a PDF report with ${documentForOutput.sections.length} sections from the response structure.',
        previewRows: pdfRenderer.previewRowsFor(
          documentForOutput,
          pageCount: pageCount,
        ),
        sheetCount: pageCount,
      );
    }

    if (requestedKind == GeneratedArtifactKind.diagram) {
      final diagram = diagramRenderer.render(
        document: document,
        content: content,
      );
      return _ResolvedArtifact(
        kind: GeneratedArtifactKind.diagram,
        status: GeneratedArtifactStatus.ready,
        extension: 'svg',
        bytes: diagram.bytes,
        summary:
            'Created an SVG topology diagram with ${diagram.nodeCount} nodes and ${diagram.edgeCount} links.',
        previewRows: diagram.previewRows,
      );
    }

    if (requestedKind == GeneratedArtifactKind.chart) {
      final chart = chartRenderer.render(document);
      final signalSummary = chart.signals.isEmpty
          ? ''
          : ' covering ${chart.signals.join(', ')}';
      return _ResolvedArtifact(
        kind: GeneratedArtifactKind.chart,
        status: GeneratedArtifactStatus.ready,
        extension: 'svg',
        bytes: chart.bytes,
        summary: chart.chartCount == 1
            ? 'Created an SVG chart artifact from the response data.'
            : 'Created an SVG chart pack with ${chart.chartCount} charts$signalSummary.',
        previewRows: chart.previewRows,
        sheetCount: chart.chartCount,
      );
    }

    if (requestedKind == GeneratedArtifactKind.excel ||
        requestedKind == GeneratedArtifactKind.csv) {
      final lifecycleEox =
          requestedKind == GeneratedArtifactKind.excel &&
          lifecycleEoxBuilder.matches(prompt);
      final productComparison =
          requestedKind == GeneratedArtifactKind.excel &&
          productComparisonBuilder.matches(prompt);
      final sizingWorkbook =
          requestedKind == GeneratedArtifactKind.excel &&
          solutionSizingBuilder.matches(prompt);
      final tables = lifecycleEox
          ? lifecycleEoxBuilder
                .build(prompt: prompt, content: content, document: document)
                .map((table) => _TableData(name: table.name, rows: table.rows))
                .toList(growable: false)
          : productComparison
          ? productComparisonBuilder
                .build(prompt: prompt, content: content, document: document)
                .map((table) => _TableData(name: table.name, rows: table.rows))
                .toList(growable: false)
          : sizingWorkbook
          ? solutionSizingBuilder
                .build(prompt: prompt, content: content, document: document)
                .map((table) => _TableData(name: table.name, rows: table.rows))
                .toList(growable: false)
          : _extractTables(content);
      if (tables.isNotEmpty && requestedKind == GeneratedArtifactKind.excel) {
        final workbook = _xlsxBytes(tables);
        return _ResolvedArtifact(
          kind: GeneratedArtifactKind.excel,
          status: GeneratedArtifactStatus.ready,
          extension: 'xlsx',
          bytes: workbook,
          summary: lifecycleEox
              ? 'Created a Lifecycle / EoX workbook with lifecycle status, official date evidence, migration hints, replacement suitability, risks, assumptions, and source sheets.'
              : productComparison
              ? 'Created a product comparison matrix with fit scoring, requirements, alternatives, assumptions, and source sheets.'
              : sizingWorkbook
              ? 'Created a solution sizing workbook with requirements, inputs, recommendations, validation, and assumptions sheets.'
              : tables.length == 1
              ? 'Created an Excel workbook with formatted headers and frozen first row.'
              : 'Created an Excel workbook with ${tables.length} sheets, formatted headers, and frozen first rows.',
          previewRows: tables.first.rows.take(6).toList(growable: false),
          sheetCount: tables.length,
        );
      }
      if (tables.isNotEmpty) {
        final csv = _tableToCsv(tables.first);
        return _ResolvedArtifact(
          kind: GeneratedArtifactKind.csv,
          status: requestedKind == GeneratedArtifactKind.excel
              ? GeneratedArtifactStatus.fallback
              : GeneratedArtifactStatus.ready,
          extension: 'csv',
          bytes: utf8.encode(csv),
          summary: requestedKind == GeneratedArtifactKind.excel
              ? 'Excel workbook creation was unavailable, so a CSV artifact was created.'
              : 'Created a CSV artifact.',
          previewRows: tables.first.rows.take(6).toList(growable: false),
          sheetCount: 1,
        );
      }
      return _ResolvedArtifact(
        kind: GeneratedArtifactKind.markdown,
        status: GeneratedArtifactStatus.fallback,
        extension: 'md',
        bytes: utf8.encode(content.trim()),
        summary:
            'Could not find a clean table, so the response was saved as Markdown.',
      );
    }

    if (requestedKind == GeneratedArtifactKind.json) {
      if (evidencePackBuilder.matches(prompt)) {
        final jsonText = evidencePackBuilder.toJsonString(documentForOutput);
        return _ResolvedArtifact(
          kind: GeneratedArtifactKind.json,
          status: GeneratedArtifactStatus.ready,
          extension: 'json',
          bytes: utf8.encode(jsonText),
          summary:
              'Created a structured JSON evidence pack with sources, assumptions, claims, confidence, and follow-up sections.',
        );
      }
      final jsonText = _extractJson(content);
      return _ResolvedArtifact(
        kind: GeneratedArtifactKind.json,
        status: jsonText == null
            ? GeneratedArtifactStatus.fallback
            : GeneratedArtifactStatus.ready,
        extension: jsonText == null ? 'md' : 'json',
        bytes: utf8.encode(jsonText ?? content.trim()),
        summary: jsonText == null
            ? 'Could not isolate valid JSON, so the response was saved as Markdown.'
            : 'Created a JSON artifact.',
      );
    }

    return _ResolvedArtifact(
      kind: requestedKind,
      status: GeneratedArtifactStatus.ready,
      extension: 'md',
      bytes: utf8.encode(content.trim()),
      summary: 'Created a Markdown artifact.',
    );
  }

  List<_TableData> _extractTables(String content) {
    final tables = _markdownTables(content);
    if (tables.isEmpty) return const [];
    final parsed = <_TableData>[];
    for (var i = 0; i < tables.length; i++) {
      final rows = <List<String>>[];
      for (final line in tables[i]) {
        final cells = _tableCells(line);
        if (cells.isEmpty) continue;
        if (cells.every((cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell))) {
          continue;
        }
        rows.add(cells);
      }
      if (rows.length >= 2) {
        parsed.add(_TableData(name: 'Sheet ${i + 1}', rows: rows));
      }
    }
    parsed.sort((a, b) => b.rows.length.compareTo(a.rows.length));
    return parsed;
  }

  String _tableToCsv(_TableData table) {
    return table.rows.map((row) => row.map(_csvCell).join(',')).join('\n');
  }

  List<List<String>> _markdownTables(String content) {
    final tables = <List<String>>[];
    var current = <String>[];
    for (final raw in const LineSplitter().convert(content)) {
      final line = raw.trim();
      final looksLikeRow = line.contains('|') && _tableCells(line).length >= 2;
      if (looksLikeRow) {
        current.add(line);
        continue;
      }
      if (current.length >= 2) tables.add(current);
      current = <String>[];
    }
    if (current.length >= 2) tables.add(current);
    return tables;
  }

  List<String> _tableCells(String line) {
    var trimmed = line.trim();
    if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
    if (trimmed.endsWith('|')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed
        .split('|')
        .map((cell) => cell.trim())
        .where((cell) => cell.isNotEmpty)
        .toList();
  }

  String _csvCell(String value) {
    final normalized = value.replaceAll('\n', ' ').trim();
    final escaped = normalized.replaceAll('"', '""');
    if (escaped.contains(',') ||
        escaped.contains('"') ||
        escaped.contains('|')) {
      return '"$escaped"';
    }
    return escaped;
  }

  Uint8List _xlsxBytes(List<_TableData> tables) {
    final workbookTables = tables.take(12).toList(growable: false);
    final files = <_ZipFileEntry>[
      _ZipFileEntry(
        '[Content_Types].xml',
        _utf8Bytes(_contentTypesXml(workbookTables.length)),
      ),
      _ZipFileEntry('_rels/.rels', _utf8Bytes(_rootRelsXml())),
      _ZipFileEntry('docProps/app.xml', _utf8Bytes(_appXml())),
      _ZipFileEntry('docProps/core.xml', _utf8Bytes(_coreXml())),
      _ZipFileEntry(
        'xl/workbook.xml',
        _utf8Bytes(_workbookXml(workbookTables)),
      ),
      _ZipFileEntry(
        'xl/_rels/workbook.xml.rels',
        _utf8Bytes(_workbookRelsXml(workbookTables.length)),
      ),
      _ZipFileEntry('xl/styles.xml', _utf8Bytes(_stylesXml())),
      for (var i = 0; i < workbookTables.length; i++)
        _ZipFileEntry(
          'xl/worksheets/sheet${i + 1}.xml',
          _utf8Bytes(_worksheetXml(workbookTables[i])),
        ),
    ];
    return _zip(files);
  }

  Uint8List _utf8Bytes(String value) => Uint8List.fromList(utf8.encode(value));

  String _contentTypesXml(int sheetCount) {
    final sheets = List.generate(
      sheetCount,
      (index) =>
          '<Override PartName="/xl/worksheets/sheet${index + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
    ).join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
        '$sheets</Types>';
  }

  String _rootRelsXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
        '</Relationships>';
  }

  String _appXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
        'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
        '<Application>CircuitCode</Application></Properties>';
  }

  String _coreXml() {
    final now = DateTime.now().toUtc().toIso8601String();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:dcmitype="http://purl.org/dc/dcmitype/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:creator>CircuitCode</dc:creator>'
        '<cp:lastModifiedBy>CircuitCode</cp:lastModifiedBy>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">$now</dcterms:created>'
        '<dcterms:modified xsi:type="dcterms:W3CDTF">$now</dcterms:modified>'
        '</cp:coreProperties>';
  }

  String _workbookXml(List<_TableData> tables) {
    final sheets = [
      for (var i = 0; i < tables.length; i++)
        '<sheet name="${_xmlAttr(_sheetName(tables[i].name, i))}" sheetId="${i + 1}" r:id="rId${i + 1}"/>',
    ].join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets>$sheets</sheets></workbook>';
  }

  String _workbookRelsXml(int sheetCount) {
    final buffer = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
    );
    for (var i = 0; i < sheetCount; i++) {
      buffer.write(
        '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>',
      );
    }
    buffer.write(
      '<Relationship Id="rId${sheetCount + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>',
    );
    buffer.write('</Relationships>');
    return buffer.toString();
  }

  String _stylesXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="2"><font><sz val="11"/><name val="Aptos"/></font><font><b/><sz val="11"/><name val="Aptos"/></font></fonts>'
        '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFE7EEF2"/><bgColor indexed="64"/></patternFill></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/></cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '</styleSheet>';
  }

  String _worksheetXml(_TableData table) {
    final maxColumns = table.rows.fold<int>(
      0,
      (max, row) => row.length > max ? row.length : max,
    );
    final columns = [
      for (var i = 0; i < maxColumns; i++)
        '<col min="${i + 1}" max="${i + 1}" width="${_columnWidth(table, i).toStringAsFixed(1)}" customWidth="1"/>',
    ].join();
    final rows = <String>[];
    for (var rowIndex = 0; rowIndex < table.rows.length; rowIndex++) {
      final row = table.rows[rowIndex];
      final cells = <String>[];
      for (var columnIndex = 0; columnIndex < row.length; columnIndex++) {
        cells.add(
          _cellXml(
            row[columnIndex],
            rowIndex: rowIndex,
            columnIndex: columnIndex,
            header: rowIndex == 0,
          ),
        );
      }
      rows.add('<row r="${rowIndex + 1}">${cells.join()}</row>');
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
        '<cols>$columns</cols><sheetData>${rows.join()}</sheetData>'
        '<autoFilter ref="A1:${_columnName(maxColumns - 1)}${table.rows.length}"/>'
        '</worksheet>';
  }

  String _cellXml(
    String value, {
    required int rowIndex,
    required int columnIndex,
    required bool header,
  }) {
    final ref = '${_columnName(columnIndex)}${rowIndex + 1}';
    final style = header ? ' s="1"' : '';
    final numeric = _numericValue(value);
    if (!header && numeric != null) {
      return '<c r="$ref"$style><v>$numeric</v></c>';
    }
    return '<c r="$ref" t="inlineStr"$style><is><t>${_xmlText(value)}</t></is></c>';
  }

  String? _numericValue(String value) {
    final normalized = value.trim().replaceAll(',', '');
    if (normalized.isEmpty) return null;
    if (!RegExp(r'^-?\d+(\.\d+)?%?$').hasMatch(normalized)) return null;
    if (normalized.endsWith('%')) {
      final parsed = double.tryParse(
        normalized.substring(0, normalized.length - 1),
      );
      if (parsed == null) return null;
      return (parsed / 100).toString();
    }
    return double.tryParse(normalized)?.toString();
  }

  double _columnWidth(_TableData table, int columnIndex) {
    var width = 10;
    for (final row in table.rows.take(80)) {
      if (columnIndex >= row.length) continue;
      final length = row[columnIndex].length;
      if (length > width) width = length;
    }
    return width.clamp(10, 42).toDouble() + 2;
  }

  String _columnName(int zeroBasedIndex) {
    var index = zeroBasedIndex;
    final chars = <String>[];
    do {
      chars.insert(0, String.fromCharCode(65 + (index % 26)));
      index = (index ~/ 26) - 1;
    } while (index >= 0);
    return chars.join();
  }

  String _sheetName(String raw, int index) {
    final sanitized = raw
        .replaceAll(RegExp(r'[\[\]\*:/\\?]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final fallback = 'Sheet ${index + 1}';
    final name = sanitized.isEmpty ? fallback : sanitized;
    return name.length > 31 ? name.substring(0, 31) : name;
  }

  String _xmlText(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  String _xmlAttr(String value) {
    return _xmlText(value).replaceAll('"', '&quot;');
  }

  String? _extractJson(String content) {
    final fenced = RegExp(
      r'```json\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(content);
    final candidate = fenced?.group(1)?.trim() ?? content.trim();
    try {
      final decoded = jsonDecode(candidate);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return null;
    }
  }

  String _safeBaseName(String prompt) {
    final words = prompt
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s_-]'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 2)
        .take(6)
        .toList();
    final base = words.isEmpty ? 'generated-artifact' : words.join('-');
    return base.length > 48 ? base.substring(0, 48) : base;
  }

  int _pdfPageCount(List<int> bytes) {
    final text = latin1.decode(bytes, allowInvalid: true);
    final count = RegExp(r'/Type /Page\b').allMatches(text).length;
    return count <= 0 ? 1 : count;
  }
}

class _ResolvedArtifact {
  final GeneratedArtifactKind kind;
  final GeneratedArtifactStatus status;
  final String extension;
  final List<int> bytes;
  final String summary;
  final List<List<String>> previewRows;
  final int sheetCount;

  const _ResolvedArtifact({
    required this.kind,
    required this.status,
    required this.extension,
    required this.bytes,
    required this.summary,
    this.previewRows = const [],
    this.sheetCount = 0,
  });
}

class _TableData {
  final String name;
  final List<List<String>> rows;

  const _TableData({required this.name, required this.rows});
}

class _ZipFileEntry {
  final String path;
  final Uint8List bytes;

  const _ZipFileEntry(this.path, this.bytes);
}

Uint8List _zip(List<_ZipFileEntry> files) {
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
      if ((crc & 1) == 1) {
        crc = (crc >> 1) ^ 0xedb88320;
      } else {
        crc >>= 1;
      }
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
