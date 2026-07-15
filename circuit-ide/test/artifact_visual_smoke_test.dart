import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:circuit_ide/models/artifact_template.dart';
import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/services/generated_artifact_writer.dart';
import 'package:circuit_ide/services/powerpoint_artifact_inspector.dart';
import 'package:circuit_ide/services/workbook_artifact_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

/// macOS Quick Look is the operating-system rendering path used when a
/// customer opens generated Word, PDF, and workbook deliverables. This
/// complements the format inspectors: a valid package that cannot produce a
/// real preview is not a releasable artifact.
void main() {
  test(
    'macOS Quick Look renders every shipped template for Word PDF and Excel deliverables',
    () async {
      if (!Platform.isMacOS) return;
      final root = await Directory.systemTemp.createTemp(
        'circuit-artifact-visual-smoke-',
      );
      addTearDown(() => root.delete(recursive: true));
      final previews = Directory(
        '${root.path}${Platform.pathSeparator}previews',
      );
      await previews.create();
      const cases = [
        _VisualArtifactCase(
          kind: GeneratedArtifactKind.docx,
          prompt: 'Create a Word customer readiness report',
        ),
        _VisualArtifactCase(
          kind: GeneratedArtifactKind.pdf,
          prompt: 'Create a PDF customer readiness report',
        ),
        _VisualArtifactCase(
          kind: GeneratedArtifactKind.excel,
          prompt: 'Create an Excel customer readiness workbook',
        ),
      ];
      const content = '''
# Customer Readiness

## Decision

- Approve the validated rollout path.

## Readiness Matrix

| Gate | Status | Owner |
| --- | --- | --- |
| Architecture | Ready | Engineering |
| Verification | Passed | QA |

## Assumptions

- Customer inventory remains current.

## Sources

- https://example.test/readiness
''';

      final templates = const ArtifactTemplateRegistry().templates;
      for (
        var templateIndex = 0;
        templateIndex < templates.length;
        templateIndex++
      ) {
        final template = templates[templateIndex];
        for (final smokeCase in cases) {
          final label = '${template.id}/${smokeCase.kind.name}';
          final artifact = await const GeneratedArtifactWriter()
              .writeStructuredArtifact(
                rootPath: root.path,
                prompt: smokeCase.prompt,
                content: content,
                targetKind: smokeCase.kind,
                turnId: 'visual-${template.id}-${smokeCase.kind.name}',
                threadId: 'thread-visual-${template.id}',
                requestId: 'request-visual-${template.id}',
                artifactVersion: templateIndex + 1,
                templateId: template.id,
              );
          expect(artifact, isNotNull, reason: label);
          expect(
            artifact!.generationRecipe?.templateId,
            template.id,
            reason: label,
          );
          final render = await _runBounded('/usr/bin/qlmanage', [
            '-t',
            '-s',
            '1024',
            '-o',
            previews.path,
            artifact.filePath,
          ]);
          expect(
            render.exitCode,
            0,
            reason:
                '$label: ${render.timedOut ? 'Quick Look timed out' : render.stderr}',
          );
          final matchingPreviews = await previews
              .list()
              .where((entry) => entry is File && entry.path.endsWith('.png'))
              .cast<File>()
              .where((file) => file.path.contains(artifact.fileName))
              .toList();
          expect(matchingPreviews, isNotEmpty, reason: label);
          final image = matchingPreviews.last;
          final bytes = await image.readAsBytes();
          expect(bytes.length, greaterThan(1024), reason: label);
          expect(_isPng(bytes), isTrue, reason: label);
          final dimensions = await _runBounded('/usr/bin/sips', [
            '-g',
            'pixelWidth',
            '-g',
            'pixelHeight',
            image.path,
          ]);
          expect(dimensions.exitCode, 0, reason: label);
          final size = _previewDimensions(dimensions.stdout);
          expect(size.$1, greaterThan(120), reason: label);
          expect(size.$2, greaterThan(120), reason: label);
          final visual = await _inspectPreviewPixels(bytes);
          expect(
            visual.distinctSamples,
            greaterThan(8),
            reason: '$label: Quick Look produced a near-uniform preview.',
          );
          expect(
            visual.nonWhiteSamples,
            greaterThan(12),
            reason: '$label: Quick Look preview is visually blank.',
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'an Office-compatible renderer produces nonblank Excel workbook pages',
    () async {
      final officeRenderer = _officeRendererPath();
      final pdfRasterizer = _pdfRasterizerPath();
      final pdfTextExtractor = _pdfTextExtractorPath();
      if (officeRenderer == null ||
          pdfRasterizer == null ||
          pdfTextExtractor == null) {
        fail(
          'Set CIRCUIT_SOFFICE_PATH, CIRCUIT_PDFTOPPM_PATH, and CIRCUIT_PDFTOTEXT_PATH to executable renderer binaries before running the Excel visual-render probe.',
        );
      }
      final root = await Directory.systemTemp.createTemp(
        'circuit-excel-visual-smoke-',
      );
      addTearDown(() => root.delete(recursive: true));
      final rendered = Directory(
        '${root.path}${Platform.pathSeparator}rendered',
      );
      final profile = Directory(
        '${root.path}${Platform.pathSeparator}office-profile',
      );
      await rendered.create();
      await profile.create();
      final artifact = await const GeneratedArtifactWriter()
          .writeFromAssistantOutput(
            rootPath: root.path,
            prompt:
                'create a solution sizing workbook for 500 users, 90 APs, 6 switches, 2 Gbps WAN, and Wi-Fi 7 UPOE',
            content: '''
# Campus Solution Sizing

## Recommendations

- Validate Wi-Fi 7 AP UPOE requirements before selecting access switches.
- Size WAN against inspection throughput, not just carrier link speed.
- EXCEL_RENDER_SENTINEL must remain visible in the customer-facing export.

| Site | Users | APs | WAN |
| --- | ---: | ---: | --- |
| HQ | 300 | 50 | 2 Gbps |
| Branch | 200 | 40 | 1 Gbps |

## Assumptions

- Customer wants 25% growth headroom.
- Lifecycle and LDOS dates still need validation.
''',
            turnId: 'visual-excel',
            threadId: 'thread-visual',
            requestId: 'request-visual',
          );
      expect(artifact, isNotNull);
      expect(artifact!.kind, GeneratedArtifactKind.excel);
      final workbook = const WorkbookArtifactInspector().inspect(
        await File(artifact.filePath).readAsBytes(),
      );
      expect(workbook.hasEnterpriseWorkbookStructure, isTrue);
      expect(
        workbook.sheetNames.length,
        greaterThanOrEqualTo(10),
        reason: 'The fixture must exercise a multi-sheet customer workbook.',
      );
      final conversion = await _runBounded(officeRenderer, [
        '--headless',
        '--nologo',
        '--nolockcheck',
        '--nodefault',
        '--nofirststartwizard',
        '-env:UserInstallation=${profile.uri}',
        '--convert-to',
        'pdf:calc_pdf_Export',
        '--outdir',
        rendered.path,
        artifact.filePath,
      ], timeout: const Duration(seconds: 45));
      expect(
        conversion.exitCode,
        0,
        reason: conversion.timedOut
            ? 'The Office-compatible Excel render timed out.'
            : conversion.stderr,
      );
      final pdfs = await rendered
          .list()
          .where((entry) => entry is File && entry.path.endsWith('.pdf'))
          .cast<File>()
          .toList();
      expect(pdfs, hasLength(1));
      final pagePrefix = '${rendered.path}${Platform.pathSeparator}excel-page';
      final raster = await _runBounded(pdfRasterizer, [
        '-png',
        '-r',
        '144',
        pdfs.single.path,
        pagePrefix,
      ], timeout: const Duration(seconds: 45));
      expect(
        raster.exitCode,
        0,
        reason: raster.timedOut
            ? 'The converted Excel PDF rasterization timed out.'
            : raster.stderr,
      );
      final renderedPages =
          await rendered
                .list()
                .where((entry) => entry is File && entry.path.endsWith('.png'))
                .cast<File>()
                .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      expect(
        renderedPages.length,
        greaterThanOrEqualTo(workbook.sheetNames.length),
        reason:
            'The Office-compatible PDF must include at least one render for every workbook sheet.',
      );
      await _expectNonblankRenderedPages(
        renderedPages,
        minimumDistinctSamples: 4,
      );
      await _expectRenderedPdfText(pdfs.single, const [
        'EXCEL_RENDER_SENTINEL',
      ], extractor: pdfTextExtractor);
    },
    skip: !Platform.isMacOS
        ? 'Requires macOS rendering tools.'
        : _officeRendererPath() == null ||
              _pdfRasterizerPath() == null ||
              _pdfTextExtractorPath() == null
        ? 'Set CIRCUIT_SOFFICE_PATH, CIRCUIT_PDFTOPPM_PATH, and CIRCUIT_PDFTOTEXT_PATH to run the multi-sheet Office-compatible Excel renderer.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'an Office-compatible renderer produces nonblank Word document pages',
    () async {
      final officeRenderer = _officeRendererPath();
      final pdfRasterizer = _pdfRasterizerPath();
      final pdfTextExtractor = _pdfTextExtractorPath();
      if (officeRenderer == null ||
          pdfRasterizer == null ||
          pdfTextExtractor == null) {
        fail(
          'Set CIRCUIT_SOFFICE_PATH, CIRCUIT_PDFTOPPM_PATH, and CIRCUIT_PDFTOTEXT_PATH to executable renderer binaries before running the Word visual-render probe.',
        );
      }
      final root = await Directory.systemTemp.createTemp(
        'circuit-word-visual-smoke-',
      );
      addTearDown(() => root.delete(recursive: true));
      final rendered = Directory(
        '${root.path}${Platform.pathSeparator}rendered',
      );
      final profile = Directory(
        '${root.path}${Platform.pathSeparator}office-profile',
      );
      await rendered.create();
      await profile.create();
      final content = StringBuffer()
        ..writeln('# Customer Readiness')
        ..writeln()
        ..writeln('## Decision')
        ..writeln()
        ..writeln('- Approve the validated rollout path.');
      for (var section = 1; section <= 10; section++) {
        content
          ..writeln()
          ..writeln('## Evidence group $section')
          ..writeln()
          ..writeln('| Gate | Status | Owner |')
          ..writeln('| --- | --- | --- |')
          ..writeln('| Architecture | Ready | Engineering |')
          ..writeln('| Verification | Passed | QA |')
          ..writeln()
          ..writeln(
            '- The customer inventory and validation evidence remain current.',
          )
          ..writeln('- The reviewed rollout path has an accountable owner.');
      }
      content.writeln('- WORD_RENDER_SENTINEL_10 must survive the final page.');
      final artifact = await const GeneratedArtifactWriter()
          .writeStructuredArtifact(
            rootPath: root.path,
            prompt: 'Create a Word customer readiness report',
            content: content.toString(),
            targetKind: GeneratedArtifactKind.docx,
            turnId: 'visual-word',
            threadId: 'thread-visual',
            requestId: 'request-visual',
          );
      expect(artifact, isNotNull);
      final conversion = await _runBounded(officeRenderer, [
        '--headless',
        '--nologo',
        '--nolockcheck',
        '--nodefault',
        '--nofirststartwizard',
        '-env:UserInstallation=${profile.uri}',
        '--convert-to',
        'pdf:writer_pdf_Export',
        '--outdir',
        rendered.path,
        artifact!.filePath,
      ], timeout: const Duration(seconds: 45));
      expect(
        conversion.exitCode,
        0,
        reason: conversion.timedOut
            ? 'The Office-compatible Word render timed out.'
            : conversion.stderr,
      );
      final pdfs = await rendered
          .list()
          .where((entry) => entry is File && entry.path.endsWith('.pdf'))
          .cast<File>()
          .toList();
      expect(pdfs, hasLength(1));
      final pagePrefix = '${rendered.path}${Platform.pathSeparator}word-page';
      final raster = await _runBounded(pdfRasterizer, [
        '-png',
        '-r',
        '144',
        pdfs.single.path,
        pagePrefix,
      ], timeout: const Duration(seconds: 45));
      expect(
        raster.exitCode,
        0,
        reason: raster.timedOut
            ? 'The converted Word PDF rasterization timed out.'
            : raster.stderr,
      );
      final renderedPages =
          await rendered
                .list()
                .where((entry) => entry is File && entry.path.endsWith('.png'))
                .cast<File>()
                .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      expect(
        renderedPages.length,
        greaterThanOrEqualTo(2),
        reason: 'The Word fixture should exercise more than its first page.',
      );
      await _expectNonblankRenderedPages(renderedPages);
      await _expectRenderedPdfText(pdfs.single, const [
        'WORD_RENDER_SENTINEL_10',
      ], extractor: pdfTextExtractor);
      await _expectRenderedPdfText(
        pdfs.single,
        const [
          'The customer inventory and validation evidence remain current.',
        ],
        extractor: pdfTextExtractor,
        page: renderedPages.length,
      );
    },
    skip: !Platform.isMacOS
        ? 'Requires macOS rendering tools.'
        : _officeRendererPath() == null ||
              _pdfRasterizerPath() == null ||
              _pdfTextExtractorPath() == null
        ? 'Set CIRCUIT_SOFFICE_PATH, CIRCUIT_PDFTOPPM_PATH, and CIRCUIT_PDFTOTEXT_PATH to run the full-document Office-compatible Word renderer.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'an Office-compatible renderer validates every shipped Word and Excel template',
    () async {
      final officeRenderer = _officeRendererPath();
      final pdfRasterizer = _pdfRasterizerPath();
      final pdfTextExtractor = _pdfTextExtractorPath();
      if (officeRenderer == null ||
          pdfRasterizer == null ||
          pdfTextExtractor == null) {
        fail(
          'Set CIRCUIT_SOFFICE_PATH, CIRCUIT_PDFTOPPM_PATH, and CIRCUIT_PDFTOTEXT_PATH to executable renderer binaries before running the Word/Excel template matrix.',
        );
      }
      final root = await Directory.systemTemp.createTemp(
        'circuit-office-template-matrix-',
      );
      addTearDown(() => root.delete(recursive: true));
      const cases = [
        _OfficeTemplateCase(
          kind: GeneratedArtifactKind.docx,
          prompt: 'Create a Word customer readiness report',
          converter: 'pdf:writer_pdf_Export',
          sentinel: 'OFFICE_TEMPLATE_WORD_SENTINEL',
          minimumPages: 2,
        ),
        _OfficeTemplateCase(
          kind: GeneratedArtifactKind.excel,
          prompt:
              'create a solution sizing workbook for 500 users, 90 APs, 6 switches, 2 Gbps WAN, and Wi-Fi 7 UPOE',
          converter: 'pdf:calc_pdf_Export',
          sentinel: 'OFFICE_TEMPLATE_EXCEL_SENTINEL',
          minimumPages: 10,
        ),
      ];
      final content = StringBuffer()
        ..writeln('# Customer Readiness')
        ..writeln()
        ..writeln('## Decision')
        ..writeln()
        ..writeln('- Approve the validated rollout path.');
      for (var section = 1; section <= 10; section++) {
        content
          ..writeln()
          ..writeln('## Evidence group $section')
          ..writeln()
          ..writeln('| Gate | Status | Owner |')
          ..writeln('| --- | --- | --- |')
          ..writeln('| Architecture | Ready | Engineering |')
          ..writeln('| Verification | Passed | QA |')
          ..writeln()
          ..writeln(
            '- The customer inventory and validation evidence remain current.',
          )
          ..writeln('- The reviewed rollout path has an accountable owner.');
      }
      content
        ..writeln('OFFICE_TEMPLATE_WORD_SENTINEL')
        ..writeln('OFFICE_TEMPLATE_EXCEL_SENTINEL');
      const excelContent = '''
# Campus Solution Sizing

## Recommendations

- Validate Wi-Fi 7 AP UPOE requirements before selecting access switches.
- OFFICE_TEMPLATE_EXCEL_SENTINEL must remain visible in the customer-facing export.

| Site | Users | APs | WAN |
| --- | ---: | ---: | --- |
| HQ | 300 | 50 | 2 Gbps |
| Branch | 200 | 40 | 1 Gbps |

## Assumptions

- Customer wants 25% growth headroom.
- Lifecycle and LDOS dates still need validation.
''';

      final templates = const ArtifactTemplateRegistry().templates;
      for (
        var templateIndex = 0;
        templateIndex < templates.length;
        templateIndex++
      ) {
        final template = templates[templateIndex];
        for (final smokeCase in cases) {
          final label = '${template.id}/${smokeCase.kind.name}';
          final rendered = Directory(
            '${root.path}${Platform.pathSeparator}rendered-${template.id}-${smokeCase.kind.name}',
          );
          final profile = Directory(
            '${root.path}${Platform.pathSeparator}office-profile-${template.id}-${smokeCase.kind.name}',
          );
          await rendered.create();
          await profile.create();
          final caseContent = smokeCase.kind == GeneratedArtifactKind.excel
              ? excelContent
              : content.toString();
          final artifact = smokeCase.kind == GeneratedArtifactKind.excel
              ? await const GeneratedArtifactWriter().writeFromAssistantOutput(
                  rootPath: root.path,
                  prompt: smokeCase.prompt,
                  content: caseContent,
                  turnId: 'office-${template.id}-${smokeCase.kind.name}',
                  threadId: 'thread-office-${template.id}',
                  requestId: 'request-office-${template.id}',
                  artifactVersion: templateIndex + 1,
                  templateId: template.id,
                )
              : await const GeneratedArtifactWriter().writeStructuredArtifact(
                  rootPath: root.path,
                  prompt: smokeCase.prompt,
                  content: caseContent,
                  targetKind: smokeCase.kind,
                  turnId: 'office-${template.id}-${smokeCase.kind.name}',
                  threadId: 'thread-office-${template.id}',
                  requestId: 'request-office-${template.id}',
                  artifactVersion: templateIndex + 1,
                  templateId: template.id,
                );
          expect(artifact, isNotNull, reason: label);
          expect(
            artifact!.generationRecipe?.templateId,
            template.id,
            reason: label,
          );
          if (smokeCase.kind == GeneratedArtifactKind.excel) {
            final workbook = const WorkbookArtifactInspector().inspect(
              await File(artifact.filePath).readAsBytes(),
            );
            expect(
              workbook.sheetNames.length,
              greaterThanOrEqualTo(10),
              reason:
                  '$label: the fixture must retain its multi-sheet workbook.',
            );
          }
          final conversion = await _runBounded(officeRenderer, [
            '--headless',
            '--nologo',
            '--nolockcheck',
            '--nodefault',
            '--nofirststartwizard',
            '-env:UserInstallation=${profile.uri}',
            '--convert-to',
            smokeCase.converter,
            '--outdir',
            rendered.path,
            artifact.filePath,
          ], timeout: const Duration(seconds: 45));
          expect(
            conversion.exitCode,
            0,
            reason: conversion.timedOut
                ? '$label: Office conversion timed out.'
                : '$label: ${conversion.stderr}',
          );
          final pdfs = await rendered
              .list()
              .where((entry) => entry is File && entry.path.endsWith('.pdf'))
              .cast<File>()
              .toList();
          expect(pdfs, hasLength(1), reason: label);
          final pagePrefix =
              '${rendered.path}${Platform.pathSeparator}page-${template.id}';
          final raster = await _runBounded(pdfRasterizer, [
            '-png',
            '-r',
            '144',
            pdfs.single.path,
            pagePrefix,
          ], timeout: const Duration(seconds: 45));
          expect(
            raster.exitCode,
            0,
            reason: raster.timedOut
                ? '$label: PDF rasterization timed out.'
                : '$label: ${raster.stderr}',
          );
          final renderedPages =
              await rendered
                    .list()
                    .where(
                      (entry) => entry is File && entry.path.endsWith('.png'),
                    )
                    .cast<File>()
                    .toList()
                ..sort((a, b) => a.path.compareTo(b.path));
          expect(
            renderedPages.length,
            greaterThanOrEqualTo(smokeCase.minimumPages),
            reason: '$label: required rendered pages were missing.',
          );
          await _expectNonblankRenderedPages(
            renderedPages,
            minimumDistinctSamples:
                smokeCase.kind == GeneratedArtifactKind.excel ? 4 : 8,
          );
          await _expectRenderedPdfText(pdfs.single, [
            smokeCase.sentinel,
          ], extractor: pdfTextExtractor);
        }
      }
    },
    skip: !Platform.isMacOS
        ? 'Requires macOS rendering tools.'
        : _officeRendererPath() == null ||
              _pdfRasterizerPath() == null ||
              _pdfTextExtractorPath() == null
        ? 'Set CIRCUIT_SOFFICE_PATH, CIRCUIT_PDFTOPPM_PATH, and CIRCUIT_PDFTOTEXT_PATH to run the Word/Excel template matrix.'
        : false,
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'Poppler rasterizes every generated PDF page and preserves final customer evidence',
    () async {
      final pdfRasterizer = _pdfRasterizerPath();
      final pdfTextExtractor = _pdfTextExtractorPath();
      if (pdfRasterizer == null || pdfTextExtractor == null) {
        fail(
          'Set CIRCUIT_PDFTOPPM_PATH and CIRCUIT_PDFTOTEXT_PATH to executable Poppler binaries before running the multi-page PDF render probe.',
        );
      }
      final root = await Directory.systemTemp.createTemp(
        'circuit-pdf-visual-smoke-',
      );
      addTearDown(() => root.delete(recursive: true));
      final rendered = Directory(
        '${root.path}${Platform.pathSeparator}rendered',
      );
      await rendered.create();
      final content = StringBuffer()
        ..writeln('# Customer Readiness')
        ..writeln()
        ..writeln('## Decision')
        ..writeln()
        ..writeln('- Approve the validated rollout path.');
      for (var section = 1; section <= 10; section++) {
        content
          ..writeln()
          ..writeln('## Evidence group $section')
          ..writeln()
          ..writeln('| Gate | Status | Owner |')
          ..writeln('| --- | --- | --- |')
          ..writeln('| Architecture | Ready | Engineering |')
          ..writeln('| Verification | Passed | QA |')
          ..writeln()
          ..writeln(
            '- The customer inventory and validation evidence remain current.',
          )
          ..writeln('- The reviewed rollout path has an accountable owner.');
      }
      final artifact = await const GeneratedArtifactWriter()
          .writeStructuredArtifact(
            rootPath: root.path,
            prompt: 'Create a PDF customer readiness report',
            content: content.toString(),
            targetKind: GeneratedArtifactKind.pdf,
            turnId: 'visual-pdf',
            threadId: 'thread-visual',
            requestId: 'request-visual',
          );
      expect(artifact, isNotNull);
      final pdfArtifact = artifact!;
      expect(pdfArtifact.kind, GeneratedArtifactKind.pdf);
      final pagePrefix = '${rendered.path}${Platform.pathSeparator}pdf-page';
      final raster = await _runBounded(pdfRasterizer, [
        '-png',
        '-r',
        '144',
        pdfArtifact.filePath,
        pagePrefix,
      ], timeout: const Duration(seconds: 45));
      expect(
        raster.exitCode,
        0,
        reason: raster.timedOut
            ? 'The generated PDF rasterization timed out.'
            : raster.stderr,
      );
      final renderedPages =
          await rendered
                .list()
                .where((entry) => entry is File && entry.path.endsWith('.png'))
                .cast<File>()
                .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      expect(
        renderedPages.length,
        greaterThanOrEqualTo(2),
        reason: 'The PDF fixture must exercise more than its first page.',
      );
      await _expectNonblankRenderedPages(renderedPages);
      await _expectRenderedPdfText(
        File(pdfArtifact.filePath),
        const [
          'The customer inventory and validation evidence remain current.',
        ],
        extractor: pdfTextExtractor,
        page: renderedPages.length,
      );
    },
    skip: !Platform.isMacOS
        ? 'Requires macOS rendering tools.'
        : _pdfRasterizerPath() == null || _pdfTextExtractorPath() == null
        ? 'Set CIRCUIT_PDFTOPPM_PATH and CIRCUIT_PDFTOTEXT_PATH to run the full generated-PDF renderer.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'an Office-compatible renderer produces nonblank PowerPoint slide previews for every shipped template',
    () async {
      final officeRenderer = _officeRendererPath();
      final pdfRasterizer = _pdfRasterizerPath();
      final pdfTextExtractor = _pdfTextExtractorPath();
      if (officeRenderer == null ||
          pdfRasterizer == null ||
          pdfTextExtractor == null) {
        fail(
          'Set CIRCUIT_SOFFICE_PATH, CIRCUIT_PDFTOPPM_PATH, and CIRCUIT_PDFTOTEXT_PATH to executable renderer binaries before running the PowerPoint visual-render probe.',
        );
      }
      final root = await Directory.systemTemp.createTemp(
        'circuit-powerpoint-visual-smoke-',
      );
      addTearDown(() => root.delete(recursive: true));
      const content = '''
# PPTX_RENDER_SENTINEL Customer Readiness

## Decision

- Approve the validated rollout path.

## Readiness Matrix

| Gate | Status | Owner |
| --- | --- | --- |
| Architecture | Ready | Engineering |
| Verification | Passed | QA |

## Assumptions

- Customer inventory remains current.

## Sources

- https://example.test/readiness
''';
      final templates = const ArtifactTemplateRegistry().templates;
      for (
        var templateIndex = 0;
        templateIndex < templates.length;
        templateIndex++
      ) {
        final template = templates[templateIndex];
        final label = 'PowerPoint/${template.id}';
        final rendered = Directory(
          '${root.path}${Platform.pathSeparator}rendered-${template.id}',
        );
        final profile = Directory(
          '${root.path}${Platform.pathSeparator}office-profile-${template.id}',
        );
        await rendered.create();
        await profile.create();
        final artifact = await const GeneratedArtifactWriter()
            .writeStructuredArtifact(
              rootPath: root.path,
              prompt: 'Create a PowerPoint customer readiness deck',
              content: content,
              targetKind: GeneratedArtifactKind.powerPoint,
              turnId: 'visual-powerpoint-${template.id}',
              threadId: 'thread-visual-${template.id}',
              requestId: 'request-visual-${template.id}',
              artifactVersion: templateIndex + 1,
              templateId: template.id,
            );
        expect(artifact, isNotNull, reason: label);
        expect(
          artifact!.generationRecipe?.templateId,
          template.id,
          reason: label,
        );
        final conversion = await _runBounded(officeRenderer, [
          '--headless',
          '--nologo',
          '--nolockcheck',
          '--nodefault',
          '--nofirststartwizard',
          '-env:UserInstallation=${profile.uri}',
          '--convert-to',
          'pdf:impress_pdf_Export',
          '--outdir',
          rendered.path,
          artifact.filePath,
        ], timeout: const Duration(seconds: 45));
        expect(
          conversion.exitCode,
          0,
          reason: conversion.timedOut
              ? '$label: the Office-compatible PowerPoint render timed out.'
              : '$label: ${conversion.stderr}',
        );
        final pdfs = await rendered
            .list()
            .where((entry) => entry is File && entry.path.endsWith('.pdf'))
            .cast<File>()
            .toList();
        expect(pdfs, hasLength(1), reason: label);
        final inspection = const PowerPointArtifactInspector().inspect(
          await File(artifact.filePath).readAsBytes(),
        );
        expect(inspection.slideCount, greaterThan(0), reason: label);
        final pagePrefix =
            '${rendered.path}${Platform.pathSeparator}slide-${template.id}';
        final raster = await _runBounded(pdfRasterizer, [
          '-png',
          '-r',
          '144',
          pdfs.single.path,
          pagePrefix,
        ], timeout: const Duration(seconds: 45));
        expect(
          raster.exitCode,
          0,
          reason: raster.timedOut
              ? '$label: the converted PowerPoint PDF rasterization timed out.'
              : '$label: ${raster.stderr}',
        );
        final renderedPages =
            await rendered
                  .list()
                  .where(
                    (entry) => entry is File && entry.path.endsWith('.png'),
                  )
                  .cast<File>()
                  .toList()
              ..sort((a, b) => a.path.compareTo(b.path));
        expect(
          renderedPages,
          hasLength(inspection.slideCount),
          reason:
              '$label: the Office-compatible PDF page count must match the inspected PowerPoint slide count.',
        );
        await _expectNonblankRenderedPages(renderedPages);
        await _expectRenderedPdfText(
          pdfs.single,
          const ['PPTX_RENDER_SENTINEL'],
          extractor: pdfTextExtractor,
          page: 1,
        );
        final previews = Directory(
          '${root.path}${Platform.pathSeparator}previews-${template.id}',
        );
        await previews.create();
        final preview = await _renderQuickLookPreview(pdfs.single, previews);
        final visual = await _inspectPreviewPixels(await preview.readAsBytes());
        expect(visual.distinctSamples, greaterThan(8), reason: label);
        expect(visual.nonWhiteSamples, greaterThan(12), reason: label);
      }
    },
    skip: !Platform.isMacOS
        ? 'Requires macOS rendering tools.'
        : _officeRendererPath() == null ||
              _pdfRasterizerPath() == null ||
              _pdfTextExtractorPath() == null
        ? 'Set CIRCUIT_SOFFICE_PATH, CIRCUIT_PDFTOPPM_PATH, and CIRCUIT_PDFTOTEXT_PATH to run the full-deck Office-compatible PowerPoint renderer.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'an Office-compatible renderer rejects truncated Word Excel and PowerPoint packages',
    () async {
      final officeRenderer = _officeRendererPath();
      final pdfRasterizer = _pdfRasterizerPath();
      if (officeRenderer == null || pdfRasterizer == null) {
        fail(
          'Set CIRCUIT_SOFFICE_PATH and CIRCUIT_PDFTOPPM_PATH to executable renderer binaries before running the corrupt-package render probe.',
        );
      }
      final root = await Directory.systemTemp.createTemp(
        'circuit-office-corrupt-visual-smoke-',
      );
      addTearDown(() => root.delete(recursive: true));
      const cases = [
        (
          kind: GeneratedArtifactKind.docx,
          extension: 'docx',
          converter: 'pdf:writer_pdf_Export',
        ),
        (
          kind: GeneratedArtifactKind.excel,
          extension: 'xlsx',
          converter: 'pdf:calc_pdf_Export',
        ),
        (
          kind: GeneratedArtifactKind.powerPoint,
          extension: 'pptx',
          converter: 'pdf:impress_pdf_Export',
        ),
      ];
      const content = '''
# Customer Readiness

## Decision

- Approve the validated rollout path.

## Evidence

| Gate | Status | Owner |
| --- | --- | --- |
| Architecture | Ready | Engineering |
| Verification | Passed | QA |
''';

      for (final corruptionCase in cases) {
        final artifact = await const GeneratedArtifactWriter()
            .writeStructuredArtifact(
              rootPath: root.path,
              prompt:
                  'Create a ${corruptionCase.extension} customer readiness deliverable',
              content: content,
              targetKind: corruptionCase.kind,
              turnId: 'corrupt-${corruptionCase.extension}',
              threadId: 'thread-corrupt-visual',
              requestId: 'request-corrupt-visual',
            );
        expect(artifact, isNotNull, reason: corruptionCase.extension);
        final sourceBytes = await File(artifact!.filePath).readAsBytes();
        expect(
          sourceBytes.length,
          greaterThan(64),
          reason: '${corruptionCase.extension} fixture must be a real package.',
        );
        final corrupted = File(
          '${root.path}${Platform.pathSeparator}truncated.${corruptionCase.extension}',
        );
        await corrupted.writeAsBytes(
          sourceBytes.sublist(0, sourceBytes.length ~/ 2),
          flush: true,
        );
        final rendered = Directory(
          '${root.path}${Platform.pathSeparator}rendered-${corruptionCase.extension}',
        );
        final profile = Directory(
          '${root.path}${Platform.pathSeparator}office-profile-${corruptionCase.extension}',
        );
        await rendered.create();
        await profile.create();
        final conversion = await _runBounded(officeRenderer, [
          '--headless',
          '--nologo',
          '--nolockcheck',
          '--nodefault',
          '--nofirststartwizard',
          '-env:UserInstallation=${profile.uri}',
          '--convert-to',
          corruptionCase.converter,
          '--outdir',
          rendered.path,
          corrupted.path,
        ], timeout: const Duration(seconds: 45));
        final pdfs = await rendered
            .list()
            .where((entry) => entry is File && entry.path.endsWith('.pdf'))
            .cast<File>()
            .toList();
        expect(
          pdfs,
          isEmpty,
          reason:
              '${corruptionCase.extension}: a truncated package must not produce a PDF render (exit ${conversion.exitCode}; ${conversion.stderr.trim()}).',
        );
      }
    },
    skip: !Platform.isMacOS
        ? 'Requires macOS rendering tools.'
        : _officeRendererPath() == null || _pdfRasterizerPath() == null
        ? 'Set CIRCUIT_SOFFICE_PATH and CIRCUIT_PDFTOPPM_PATH to run the corrupt Office-package renderer probe.'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _expectNonblankRenderedPages(
  List<File> pages, {
  int minimumDistinctSamples = 8,
}) async {
  for (final page in pages) {
    final pageBytes = await page.readAsBytes();
    expect(pageBytes.length, greaterThan(1024), reason: page.path);
    expect(_isPng(pageBytes), isTrue, reason: page.path);
    final pageVisual = await _inspectPreviewPixels(pageBytes);
    expect(
      pageVisual.distinctSamples,
      greaterThan(minimumDistinctSamples),
      reason: page.path,
    );
    expect(pageVisual.nonWhiteSamples, greaterThan(12), reason: page.path);
  }
}

Future<_BoundedProcessResult> _runBounded(
  String executable,
  List<String> arguments, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final process = await Process.start(executable, arguments);
  final stdout = process.stdout.transform(utf8.decoder).join();
  final stderr = process.stderr.transform(utf8.decoder).join();
  try {
    final exitCode = await process.exitCode.timeout(timeout);
    return _BoundedProcessResult(
      exitCode: exitCode,
      stdout: await stdout,
      stderr: await stderr,
    );
  } on TimeoutException {
    process.kill(ProcessSignal.sigterm);
    return _BoundedProcessResult(
      exitCode: -1,
      stdout: await stdout,
      stderr: await stderr,
      timedOut: true,
    );
  }
}

Future<File> _renderQuickLookPreview(File input, Directory previews) async {
  final render = await _runBounded('/usr/bin/qlmanage', [
    '-t',
    '-s',
    '1024',
    '-o',
    previews.path,
    input.path,
  ]);
  expect(render.exitCode, 0, reason: render.stderr);
  final fileName = input.uri.pathSegments.last;
  final matchingPreviews = await previews
      .list()
      .where((entry) => entry is File && entry.path.endsWith('.png'))
      .cast<File>()
      .where((file) => file.path.contains(fileName))
      .toList();
  expect(matchingPreviews, isNotEmpty, reason: input.path);
  final image = matchingPreviews.last;
  final bytes = await image.readAsBytes();
  expect(bytes.length, greaterThan(1024), reason: input.path);
  expect(_isPng(bytes), isTrue, reason: input.path);
  final dimensions = await _runBounded('/usr/bin/sips', [
    '-g',
    'pixelWidth',
    '-g',
    'pixelHeight',
    image.path,
  ]);
  expect(dimensions.exitCode, 0, reason: input.path);
  final size = _previewDimensions(dimensions.stdout);
  expect(size.$1, greaterThan(120), reason: input.path);
  expect(size.$2, greaterThan(120), reason: input.path);
  return image;
}

String? _officeRendererPath() {
  return _configuredOrCommonExecutable(
    environmentKey: 'CIRCUIT_SOFFICE_PATH',
    commonPaths: const [
      '/Applications/LibreOffice.app/Contents/MacOS/soffice',
      '/Applications/LibreOfficeDev.app/Contents/MacOS/soffice',
      '/opt/homebrew/bin/soffice',
      '/usr/local/bin/soffice',
    ],
  );
}

String? _pdfRasterizerPath() {
  return _configuredOrCommonExecutable(
    environmentKey: 'CIRCUIT_PDFTOPPM_PATH',
    commonPaths: const [
      '/opt/homebrew/bin/pdftoppm',
      '/usr/local/bin/pdftoppm',
      '/usr/bin/pdftoppm',
    ],
  );
}

String? _pdfTextExtractorPath() {
  final rasterizer = _pdfRasterizerPath();
  final alongsideRasterizer = rasterizer == null
      ? null
      : '${File(rasterizer).parent.path}${Platform.pathSeparator}pdftotext';
  return _configuredOrCommonExecutable(
    environmentKey: 'CIRCUIT_PDFTOTEXT_PATH',
    commonPaths: [
      ?alongsideRasterizer,
      '/opt/homebrew/bin/pdftotext',
      '/usr/local/bin/pdftotext',
      '/usr/bin/pdftotext',
    ],
  );
}

Future<void> _expectRenderedPdfText(
  File pdf,
  Iterable<String> expected, {
  required String extractor,
  int? page,
}) async {
  final result = await _runBounded(extractor, [
    '-layout',
    '-nopgbrk',
    if (page != null) ...['-f', '$page', '-l', '$page'],
    pdf.path,
    '-',
  ]);
  expect(
    result.exitCode,
    0,
    reason: 'Could not extract rendered PDF text: ${result.stderr}',
  );
  final rendered = _normalizeRenderedText(result.stdout);
  for (final requiredText in expected) {
    expect(
      rendered,
      contains(_normalizeRenderedText(requiredText)),
      reason:
          'The Office-compatible PDF render dropped required visible content "$requiredText".',
    );
  }
}

String _normalizeRenderedText(String value) =>
    value.replaceAll(RegExp(r'\s+'), '');

String? _configuredOrCommonExecutable({
  required String environmentKey,
  required List<String> commonPaths,
}) {
  final configured = Platform.environment[environmentKey]?.trim();
  if (configured != null && configured.isNotEmpty) {
    return File(configured).existsSync() ? configured : null;
  }
  for (final candidate in commonPaths) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

bool _isPng(Uint8List bytes) {
  const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  return bytes.length >= pngSignature.length &&
      List.generate(
        pngSignature.length,
        (index) => bytes[index] == pngSignature[index],
      ).every((matches) => matches);
}

(int, int) _previewDimensions(String output) {
  final width =
      RegExp(r'pixelWidth:\s*(\d+)').firstMatch(output)?.group(1) ?? '0';
  final height =
      RegExp(r'pixelHeight:\s*(\d+)').firstMatch(output)?.group(1) ?? '0';
  return (int.tryParse(width) ?? 0, int.tryParse(height) ?? 0);
}

Future<_PreviewPixelMetrics> _inspectPreviewPixels(Uint8List bytes) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    image = frame.image;
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (pixels == null) {
      return const _PreviewPixelMetrics(distinctSamples: 0, nonWhiteSamples: 0);
    }
    final data = pixels.buffer.asUint8List();
    final pixelCount = image.width * image.height;
    final stride = (pixelCount / 4096).ceil().clamp(1, pixelCount);
    final colors = <int>{};
    var nonWhiteSamples = 0;
    for (var pixel = 0; pixel < pixelCount; pixel += stride) {
      final offset = pixel * 4;
      final red = data[offset];
      final green = data[offset + 1];
      final blue = data[offset + 2];
      final alpha = data[offset + 3];
      colors.add((red << 24) | (green << 16) | (blue << 8) | alpha);
      if (alpha > 16 && (red < 242 || green < 242 || blue < 242)) {
        nonWhiteSamples++;
      }
    }
    return _PreviewPixelMetrics(
      distinctSamples: colors.length,
      nonWhiteSamples: nonWhiteSamples,
    );
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

class _VisualArtifactCase {
  final GeneratedArtifactKind kind;
  final String prompt;

  const _VisualArtifactCase({required this.kind, required this.prompt});
}

class _OfficeTemplateCase {
  final GeneratedArtifactKind kind;
  final String prompt;
  final String converter;
  final String sentinel;
  final int minimumPages;

  const _OfficeTemplateCase({
    required this.kind,
    required this.prompt,
    required this.converter,
    required this.sentinel,
    required this.minimumPages,
  });
}

class _PreviewPixelMetrics {
  final int distinctSamples;
  final int nonWhiteSamples;

  const _PreviewPixelMetrics({
    required this.distinctSamples,
    required this.nonWhiteSamples,
  });
}

class _BoundedProcessResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;

  const _BoundedProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
  });
}
