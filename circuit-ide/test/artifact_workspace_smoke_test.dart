import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/services/generated_artifact_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('artifact workspace smoke', () {
    test(
      'creates parseable core deliverables with persisted metadata',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'circuit-artifact-smoke-',
        );
        addTearDown(() => root.delete(recursive: true));

        const cases = <_ArtifactSmokeCase>[
          _ArtifactSmokeCase(
            name: 'excel workbook',
            prompt: 'create an Excel workbook from this inventory',
            content: '''
| Product | Count | Notes |
| --- | ---: | --- |
| C9300 | 6 | Access switching |
| CW9176 | 90 | Wi-Fi 7 APs |
''',
            kind: GeneratedArtifactKind.excel,
            extension: '.xlsx',
            packageNeedles: ['xl/workbook.xml', 'xl/worksheets/sheet1.xml'],
          ),
          _ArtifactSmokeCase(
            name: 'PowerPoint deck',
            prompt: 'create a PowerPoint deck for this architecture proposal',
            content: '''
# Campus Refresh Proposal

Executive summary for the customer.

## Current State
- Aging wireless estate
- Access switching needs PoE validation

## Recommendations
- Validate Wi-Fi 7 power requirements
- Standardize access switching

## Assumptions
- Counts require final customer validation.
''',
            kind: GeneratedArtifactKind.powerPoint,
            extension: '.pptx',
            packageNeedles: ['ppt/presentation.xml', 'ppt/slides/slide1.xml'],
          ),
          _ArtifactSmokeCase(
            name: 'Word report',
            prompt: 'create a customer proposal report',
            content: '''
# Customer Proposal Report

Executive handoff summary.

## Findings
- WAN and PoE inputs need validation.

## Recommendations
- Confirm lifecycle and sizing assumptions.

## Sources
- Workshop notes
''',
            kind: GeneratedArtifactKind.docx,
            extension: '.docx',
            packageNeedles: ['word/document.xml', 'word/styles.xml'],
          ),
          _ArtifactSmokeCase(
            name: 'PDF report',
            prompt: 'create a PDF customer handoff report',
            content: '''
# Customer Handoff Report

Executive-ready final report.

## Findings
- Topology needs redundancy review.

## Recommendations
- Validate WAN handoff speeds.

## Assumptions
- Customer counts are current.
''',
            kind: GeneratedArtifactKind.pdf,
            extension: '.pdf',
            textNeedles: ['/Type /Catalog', 'Customer Handoff Report'],
          ),
          _ArtifactSmokeCase(
            name: 'diagram',
            prompt: 'create a topology diagram for HQ and two branches',
            content: '''
# WAN Topology

```mermaid
graph LR
  HQ[HQ] -->|Dual WAN| BR1[Branch 1]
  HQ -->|Dual WAN| BR2[Branch 2]
```
''',
            kind: GeneratedArtifactKind.diagram,
            extension: '.svg',
            textNeedles: ['<svg', 'WAN Topology', 'Branch 1'],
          ),
          _ArtifactSmokeCase(
            name: 'chart',
            prompt: 'create a chart pack for PoE budget risk',
            content: '''
# PoE Budget

| Site | Required Watts | Budget Watts |
| --- | ---: | ---: |
| MDF | 7200 | 9600 |
| IDF 1 | 5100 | 7400 |
''',
            kind: GeneratedArtifactKind.chart,
            extension: '.svg',
            textNeedles: ['<svg', 'PoE Budget', 'MDF'],
          ),
          _ArtifactSmokeCase(
            name: 'JSON artifact',
            prompt: 'create a JSON file',
            content: '''
```json
{"customer":"Acme","sites":3}
```
''',
            kind: GeneratedArtifactKind.json,
            extension: '.json',
            textNeedles: ['"customer": "Acme"', '"sites": 3'],
          ),
        ];

        for (final smokeCase in cases) {
          final artifact = await const GeneratedArtifactWriter()
              .writeFromAssistantOutput(
                rootPath: root.path,
                prompt: smokeCase.prompt,
                content: smokeCase.content,
                turnId: 'turn-${smokeCase.name.replaceAll(' ', '-')}',
                threadId: 'thread-smoke',
                requestId: 'request-smoke',
              );

          expect(artifact, isNotNull, reason: smokeCase.name);
          expect(artifact!.kind, smokeCase.kind, reason: smokeCase.name);
          expect(artifact.fileName, endsWith(smokeCase.extension));
          expect(artifact.summary.trim(), isNotEmpty);
          expect(artifact.byteSize, greaterThan(0));
          expect(artifact.threadId, 'thread-smoke');
          expect(artifact.requestId, 'request-smoke');

          final file = File(artifact.filePath);
          expect(file.existsSync(), isTrue, reason: smokeCase.name);
          expect(
            file.path.startsWith(
              '${root.path}${Platform.pathSeparator}outputs',
            ),
            isTrue,
            reason: smokeCase.name,
          );

          final bytes = file.readAsBytesSync();
          if (smokeCase.packageNeedles.isNotEmpty) {
            expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
            final packageText = String.fromCharCodes(bytes);
            for (final needle in smokeCase.packageNeedles) {
              expect(packageText, contains(needle), reason: smokeCase.name);
            }
          }
          if (smokeCase.textNeedles.isNotEmpty) {
            final text = utf8.decode(bytes, allowMalformed: true);
            for (final needle in smokeCase.textNeedles) {
              expect(text, contains(needle), reason: smokeCase.name);
            }
          }

          final sourceArtifact = artifact.toSourceArtifact();
          final restored = GeneratedArtifact.fromSourceArtifact(sourceArtifact);
          expect(restored, isNotNull, reason: smokeCase.name);
          expect(restored!.kind, artifact.kind, reason: smokeCase.name);
          expect(restored.filePath, artifact.filePath, reason: smokeCase.name);
          expect(restored.previewRows, artifact.previewRows);
          expect(restored.sheetCount, artifact.sheetCount);
        }
      },
    );
  });
}

class _ArtifactSmokeCase {
  final String name;
  final String prompt;
  final String content;
  final GeneratedArtifactKind kind;
  final String extension;
  final List<String> packageNeedles;
  final List<String> textNeedles;

  const _ArtifactSmokeCase({
    required this.name,
    required this.prompt,
    required this.content,
    required this.kind,
    required this.extension,
    this.packageNeedles = const [],
    this.textNeedles = const [],
  });
}
