import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/models/artifact_document.dart';
import 'package:circuit_ide/models/artifact_template.dart';
import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/services/generated_artifact_exporter.dart';
import 'package:circuit_ide/services/generated_artifact_writer.dart';
import 'package:circuit_ide/services/html_artifact_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const content = '''
# Deployment Readiness

This document describes the validated rollout path.

## Scope

- Validate the production route.
- Record the rollback owner.

## Readiness matrix

| Gate | Status |
| --- | --- |
| Tests | Passed |
| Rollback | Documented |

## Assumptions

- Production credentials are configured.

## Sources

- https://example.test/release-evidence
''';

  test(
    'HTML renderer preserves shared document structure and escapes content',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-html-');
      addTearDown(() => root.delete(recursive: true));

      final artifact = await const GeneratedArtifactWriter()
          .writeFromAssistantOutput(
            rootPath: root.path,
            prompt: 'Create an HTML deployment readiness document',
            content: content.replaceFirst('validated', 'validated <safely>'),
            turnId: 'html-turn',
            threadId: 'thread',
            requestId: 'request',
          );

      expect(artifact, isNotNull);
      expect(artifact!.kind, GeneratedArtifactKind.html);
      expect(artifact.fileName, endsWith('.html'));
      expect(artifact.metadata['htmlRenderer'], 'artifact_document_v1');
      expect(artifact.metadata['htmlHasDocumentTitle'], isTrue);
      expect(artifact.metadata['htmlHasDocumentLanguage'], isTrue);
      expect(artifact.metadata['htmlHasMainLandmark'], isTrue);
      expect(artifact.metadata['htmlHasSemanticSections'], isTrue);
      expect(artifact.metadata['htmlHasTableHeaders'], isTrue);
      expect(artifact.metadata['htmlHasTableCaptions'], isTrue);
      expect(artifact.metadata['htmlHasAccessibleColorContrast'], isTrue);
      expect(artifact.metadata['accessibilityStatus'], 'Checks passed');
      final text = await File(artifact.filePath).readAsString();
      expect(text, contains('<main>'));
      expect(text, contains('<html lang="en">'));
      expect(text, contains('<section><h2>Scope</h2>'));
      expect(text, contains('<caption>Readiness matrix</caption>'));
      expect(text, contains('<th scope="col">Gate</th>'));
      expect(text, contains('validated &lt;safely&gt;'));
      expect(text, contains('<h2>Assumptions</h2>'));
      expect(text, contains('<h2>Sources</h2>'));
    },
  );

  test('HTML is a supported regeneration/export target', () async {
    final root = await Directory.systemTemp.createTemp('circuit-html-export-');
    addTearDown(() => root.delete(recursive: true));
    final artifact = await const GeneratedArtifactWriter()
        .writeStructuredArtifact(
          rootPath: root.path,
          prompt: 'Create a Markdown deployment readiness document',
          content: content,
          targetKind: GeneratedArtifactKind.markdown,
          turnId: 'markdown-turn',
          threadId: 'thread',
          requestId: 'request',
        );

    expect(artifact, isNotNull);
    expect(artifact!.canRegenerate, isTrue);
    final exported = await const GeneratedArtifactExporter().export(
      artifact: artifact,
      targetKind: GeneratedArtifactKind.html,
    );
    expect(exported, isNotNull);
    expect(exported!.kind, GeneratedArtifactKind.html);
    expect(await File(exported.filePath).exists(), isTrue);
  });

  test('HTML renderer composes every reusable artifact block', () {
    final rendered = const HtmlArtifactRenderer().render(
      const ArtifactDocument(
        title: 'Full composition',
        summary: 'Shared composition coverage.',
        metadata: {'theme': 'customer-blue'},
        sections: [ArtifactSection(title: 'Section', body: 'Body')],
        tables: [
          ArtifactTable(
            title: 'Table',
            rows: [
              ['Name', 'Value'],
              ['A', '1'],
            ],
          ),
        ],
        charts: [
          ArtifactChart(title: 'Capacity', type: 'bar', signals: ['PoE']),
        ],
        diagrams: [
          ArtifactDiagram(title: 'Topology', source: 'graph TD; A-->B'),
        ],
        appendices: [ArtifactAppendix(title: 'Method', body: 'Method body')],
        sourceData: [
          ArtifactSourceData(
            title: 'Inventory',
            rows: [
              ['Device'],
              ['Switch'],
            ],
          ),
        ],
        assumptions: ['Validated input'],
        citations: ['https://example.test/source'],
      ),
    );
    final html = String.fromCharCodes(rendered.bytes);

    expect(html, contains('artifact-theme" content="customer-blue'));
    expect(html, contains('<caption>Table</caption>'));
    expect(html, contains('<caption>Inventory</caption>'));
    expect(html, contains('Chart type: bar'));
    expect(html, contains('graph TD; A--&gt;B'));
    expect(html, contains('Appendix: Method'));
    expect(html, contains('Source data: Inventory'));
    expect(rendered.metadata['htmlChartCount'], 1);
    expect(rendered.metadata['htmlDiagramCount'], 1);
    expect(rendered.metadata['htmlAppendixCount'], 1);
    expect(rendered.metadata['htmlSourceDataCount'], 1);
  });

  test(
    'HTML renderer honors a valid document language and rejects empty headers',
    () {
      final spanish = const HtmlArtifactRenderer().render(
        const ArtifactDocument(
          title: 'Resumen',
          summary: 'Una entrega accesible.',
          metadata: {'htmlLanguage': 'es-MX'},
          tables: [
            ArtifactTable(
              title: 'Inventario',
              rows: [
                ['Modelo', 'Cantidad'],
                ['C9300', '2'],
              ],
            ),
          ],
        ),
      );
      final invalidHeaders = const HtmlArtifactRenderer().render(
        const ArtifactDocument(
          title: 'Incomplete table',
          summary: 'Header validation fixture.',
          tables: [
            ArtifactTable(
              title: 'Inventory',
              rows: [
                ['Model', ''],
                ['C9300', '2'],
              ],
            ),
          ],
        ),
      );

      expect(
        String.fromCharCodes(spanish.bytes),
        contains('<html lang="es-MX">'),
      );
      expect(spanish.metadata['htmlLanguage'], 'es-MX');
      expect(spanish.metadata['htmlHasDocumentLanguage'], isTrue);
      expect(invalidHeaders.metadata['htmlHasTableHeaders'], isFalse);
    },
  );

  test(
    'HTML renderer makes insufficient template text contrast a quality gap',
    () {
      final rendered = const HtmlArtifactRenderer().render(
        const ArtifactDocument(
          title: 'Low contrast fixture',
          summary: 'The template must not claim accessibility.',
          metadata: {
            'artifactBrandTemplate': {
              'id': 'low-contrast',
              'version': '1.0',
              'label': 'Low contrast',
              'organizationName': 'CircuitCode',
              'logoText': 'CircuitCode',
              'primaryColor': 'FFFFFF',
              'accentColor': '3B82F6',
              'fontFamily': 'Aptos',
              'footerText': 'Generated artifact',
              'confidentialityLabel': 'INTERNAL',
              'layout': 'executive-light',
            },
          },
        ),
      );

      expect(rendered.metadata['htmlHasAccessibleColorContrast'], isFalse);
    },
  );

  test(
    'named templates are durable and visibly reach native renderers',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-template-');
      addTearDown(() => root.delete(recursive: true));
      const kinds = [
        GeneratedArtifactKind.html,
        GeneratedArtifactKind.docx,
        GeneratedArtifactKind.pdf,
        GeneratedArtifactKind.powerPoint,
        GeneratedArtifactKind.excel,
        GeneratedArtifactKind.markdown,
      ];
      final artifacts = <GeneratedArtifactKind, GeneratedArtifact>{};
      for (final kind in kinds) {
        final artifact = await const GeneratedArtifactWriter()
            .writeStructuredArtifact(
              rootPath: root.path,
              prompt: 'Create a ${kind.name} customer readiness deliverable',
              content: content,
              targetKind: kind,
              templateId: ArtifactTemplateRegistry.customerBriefing.id,
              turnId: 'template-${kind.name}',
              threadId: 'thread',
              requestId: 'request',
            );
        expect(artifact, isNotNull);
        artifacts[kind] = artifact!;
        final metadata = artifact.metadata['artifactBrandTemplate'];
        expect(metadata, isA<Map>());
        expect((metadata as Map)['id'], 'customer-briefing');
        expect(artifact.generationRecipe?.templateId, 'customer-briefing');
        expect(artifact.generationRecipe?.templateVersion, '1.0');
      }

      final html = await File(
        artifacts[GeneratedArtifactKind.html]!.filePath,
      ).readAsString();
      expect(html, contains('CUSTOMER BRIEFING'));
      expect(html, contains('CONFIDENTIAL'));
      expect(html, contains('#0F3D56'));
      expect(html, contains('Prepared by CircuitCode'));

      final docx = latin1.decode(
        await File(
          artifacts[GeneratedArtifactKind.docx]!.filePath,
        ).readAsBytes(),
        allowInvalid: true,
      );
      expect(docx, contains('CUSTOMER BRIEFING'));
      expect(docx, contains('0F3D56'));

      final pdf = latin1.decode(
        await File(
          artifacts[GeneratedArtifactKind.pdf]!.filePath,
        ).readAsBytes(),
        allowInvalid: true,
      );
      expect(pdf, contains('CUSTOMER BRIEFING'));
      expect(pdf, contains('Customer briefing'));

      final deck = latin1.decode(
        await File(
          artifacts[GeneratedArtifactKind.powerPoint]!.filePath,
        ).readAsBytes(),
        allowInvalid: true,
      );
      expect(deck, contains('CUSTOMER BRIEFING'));
      expect(deck, contains('0E7490'));

      final workbook = latin1.decode(
        await File(
          artifacts[GeneratedArtifactKind.excel]!.filePath,
        ).readAsBytes(),
        allowInvalid: true,
      );
      expect(workbook, contains('Aptos Display'));
      expect(workbook, contains('FF0F3D56'));
      expect(workbook, contains('<dc:creator>CircuitCode</dc:creator>'));
      expect(workbook, contains('<Company>Customer briefing</Company>'));

      final markdown = await File(
        artifacts[GeneratedArtifactKind.markdown]!.filePath,
      ).readAsString();
      expect(markdown, contains('CUSTOMER BRIEFING · CONFIDENTIAL'));
      expect(markdown, contains('Customer briefing · Prepared by CircuitCode'));
    },
  );

  test(
    'one composition fixture remains structurally aligned across six formats',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-cross-format-',
      );
      addTearDown(() => root.delete(recursive: true));
      const kinds = [
        GeneratedArtifactKind.powerPoint,
        GeneratedArtifactKind.docx,
        GeneratedArtifactKind.pdf,
        GeneratedArtifactKind.excel,
        GeneratedArtifactKind.markdown,
        GeneratedArtifactKind.html,
      ];
      final artifacts = <GeneratedArtifact>[];
      for (final kind in kinds) {
        final artifact = await const GeneratedArtifactWriter()
            .writeStructuredArtifact(
              rootPath: root.path,
              prompt: 'Create a ${kind.name} deployment readiness deliverable',
              content: content,
              targetKind: kind,
              turnId: 'cross-${kind.name}',
              threadId: 'thread',
              requestId: 'request',
            );
        expect(artifact, isNotNull);
        artifacts.add(artifact!);
      }

      final first = artifacts.first.metadata;
      for (final artifact in artifacts) {
        expect(await File(artifact.filePath).exists(), isTrue);
        expect(artifact.byteSize, greaterThan(0));
        expect(
          artifact.metadata['artifactSectionCount'],
          first['artifactSectionCount'],
        );
        expect(
          artifact.metadata['artifactTableCount'],
          first['artifactTableCount'],
        );
        expect(
          artifact.metadata['artifactAppendixCount'],
          first['artifactAppendixCount'],
        );
        expect(
          artifact.metadata['artifactSourceDataCount'],
          first['artifactSourceDataCount'],
        );
      }
      final deck = artifacts.firstWhere(
        (artifact) => artifact.kind == GeneratedArtifactKind.powerPoint,
      );
      final docx = artifacts.firstWhere(
        (artifact) => artifact.kind == GeneratedArtifactKind.docx,
      );
      final pdf = artifacts.firstWhere(
        (artifact) => artifact.kind == GeneratedArtifactKind.pdf,
      );
      final excel = artifacts.firstWhere(
        (artifact) => artifact.kind == GeneratedArtifactKind.excel,
      );
      expect(deck.metadata['pptxStructuralValid'], isTrue);
      expect(docx.metadata['docxStructuralValid'], isTrue);
      expect(pdf.metadata['pdfStructuralValid'], isTrue);
      expect(excel.previewRows, hasLength(greaterThanOrEqualTo(2)));
    },
  );
}
