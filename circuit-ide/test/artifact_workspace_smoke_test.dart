import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/services/generated_artifact_package_writer.dart';
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

    test(
      'creates enterprise artifact packages with persisted metadata',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'circuit-artifact-package-smoke-',
        );
        addTearDown(() => root.delete(recursive: true));
        const packageWriter = GeneratedArtifactPackageWriter();
        const cases = <_ArtifactPackageSmokeCase>[
          _ArtifactPackageSmokeCase(
            name: 'topology package',
            prompt: 'create a network topology package for this Cisco campus',
            expectedLabel: 'topology package',
            expectedKinds: [
              GeneratedArtifactKind.markdown,
              GeneratedArtifactKind.diagram,
              GeneratedArtifactKind.powerPoint,
              GeneratedArtifactKind.pdf,
            ],
          ),
          _ArtifactPackageSmokeCase(
            name: 'business use case package',
            prompt: 'create a business case package for this customer',
            expectedLabel: 'business use case package',
            expectedKinds: [
              GeneratedArtifactKind.markdown,
              GeneratedArtifactKind.docx,
              GeneratedArtifactKind.powerPoint,
              GeneratedArtifactKind.chart,
            ],
          ),
          _ArtifactPackageSmokeCase(
            name: 'solution sizing package',
            prompt: 'create a solution sizing package for 500 users and 90 APs',
            expectedLabel: 'solution sizing package',
            expectedKinds: [
              GeneratedArtifactKind.markdown,
              GeneratedArtifactKind.excel,
              GeneratedArtifactKind.chart,
            ],
          ),
          _ArtifactPackageSmokeCase(
            name: 'product comparison package',
            prompt: 'create a product comparison package for C9300 and MS355',
            expectedLabel: 'product comparison package',
            expectedKinds: [
              GeneratedArtifactKind.markdown,
              GeneratedArtifactKind.excel,
              GeneratedArtifactKind.chart,
            ],
          ),
          _ArtifactPackageSmokeCase(
            name: 'lifecycle package',
            prompt:
                'create an LDOS lifecycle review package for this inventory',
            expectedLabel: 'lifecycle review package',
            expectedKinds: [
              GeneratedArtifactKind.markdown,
              GeneratedArtifactKind.excel,
              GeneratedArtifactKind.pdf,
              GeneratedArtifactKind.json,
            ],
          ),
          _ArtifactPackageSmokeCase(
            name: 'evidence package',
            prompt: 'create a final evidence pack for customer handoff',
            expectedLabel: 'evidence pack package',
            expectedKinds: [
              GeneratedArtifactKind.markdown,
              GeneratedArtifactKind.docx,
              GeneratedArtifactKind.json,
              GeneratedArtifactKind.pdf,
            ],
          ),
          _ArtifactPackageSmokeCase(
            name: 'visual evidence package',
            prompt: 'create a visual evidence package from these screenshots',
            expectedLabel: 'evidence pack package',
            content: _visualEvidencePackageContent,
            expectedKinds: [
              GeneratedArtifactKind.markdown,
              GeneratedArtifactKind.docx,
              GeneratedArtifactKind.json,
              GeneratedArtifactKind.pdf,
            ],
          ),
          _ArtifactPackageSmokeCase(
            name: 'architecture review package',
            prompt: 'create an architecture review package for this design',
            expectedLabel: 'architecture review package',
            expectedKinds: [
              GeneratedArtifactKind.markdown,
              GeneratedArtifactKind.docx,
              GeneratedArtifactKind.powerPoint,
              GeneratedArtifactKind.pdf,
            ],
          ),
          _ArtifactPackageSmokeCase(
            name: 'proposal deck and PDF report package',
            prompt: 'create a deck and PDF report for this customer proposal',
            expectedLabel: 'architecture review package',
            expectedKinds: [
              GeneratedArtifactKind.markdown,
              GeneratedArtifactKind.powerPoint,
              GeneratedArtifactKind.pdf,
            ],
          ),
          _ArtifactPackageSmokeCase(
            name: 'implementation plan package',
            prompt: 'create an implementation plan package for this project',
            expectedLabel: 'implementation plan package',
            expectedKinds: [
              GeneratedArtifactKind.markdown,
              GeneratedArtifactKind.docx,
              GeneratedArtifactKind.powerPoint,
              GeneratedArtifactKind.pdf,
            ],
          ),
          _ArtifactPackageSmokeCase(
            name: 'change summary package',
            prompt: 'create a post-work change summary package',
            expectedLabel: 'change summary package',
            expectedKinds: [
              GeneratedArtifactKind.markdown,
              GeneratedArtifactKind.docx,
              GeneratedArtifactKind.pdf,
            ],
          ),
        ];

        for (final smokeCase in cases) {
          final package = await packageWriter.writePackageFromAssistantOutput(
            rootPath: root.path,
            prompt: smokeCase.prompt,
            content: smokeCase.content ?? _enterprisePackageContent,
            turnId: 'turn-${smokeCase.name.replaceAll(' ', '-')}',
            threadId: 'thread-package-smoke',
            requestId: 'request-package-smoke',
          );

          expect(package, isNotNull, reason: smokeCase.name);
          expect(package!.label, smokeCase.expectedLabel);
          expect(
            package.artifacts.map((artifact) => artifact.kind).toList(),
            smokeCase.expectedKinds,
            reason: smokeCase.name,
          );
          expect(package.primary!.kind, GeneratedArtifactKind.markdown);
          expect(
            package.primary!.metadata['packageQualityStatus'],
            isA<String>().having(
              (value) => value,
              'quality status',
              startsWith('Package'),
            ),
            reason: smokeCase.name,
          );
          expect(
            package.primary!.metadata['packageCompletenessStatus'],
            'Complete',
            reason: smokeCase.name,
          );
          expect(
            package.primary!.metadata['artifactCount'],
            smokeCase.expectedKinds.length - 1,
            reason: smokeCase.name,
          );
          expect(
            package.primary!.metadata['hasCompletePackage'],
            isTrue,
            reason: smokeCase.name,
          );
          expect(
            package.primary!.metadata['packageDrawerActions'],
            containsAll(['Open', 'Reveal in Finder', 'Copy path', 'Review']),
            reason: smokeCase.name,
          );

          for (final artifact in package.artifacts) {
            expect(
              artifact.filePath.startsWith(
                '${root.path}${Platform.pathSeparator}outputs',
              ),
              isTrue,
              reason: '${smokeCase.name}: ${artifact.fileName}',
            );
            expect(
              File(artifact.filePath).existsSync(),
              isTrue,
              reason: '${smokeCase.name}: ${artifact.fileName}',
            );
            expect(
              artifact.threadId,
              'thread-package-smoke',
              reason: '${smokeCase.name}: ${artifact.fileName}',
            );
            expect(
              artifact.requestId,
              'request-package-smoke',
              reason: '${smokeCase.name}: ${artifact.fileName}',
            );
            final restored = GeneratedArtifact.fromSourceArtifact(
              artifact.toSourceArtifact(),
            );
            expect(restored, isNotNull);
            expect(restored!.kind, artifact.kind);
            expect(restored.filePath, artifact.filePath);
          }
          if (smokeCase.name == 'visual evidence package') {
            expect(
              package.artifacts[1].metadata['hasVisualEvidenceRegister'],
              isTrue,
            );
            expect(
              package.artifacts[1].metadata['visualEvidenceCount'],
              greaterThanOrEqualTo(2),
            );
            expect(
              package.artifacts[2].metadata['hasVisualEvidenceRegister'],
              isTrue,
            );
            expect(
              package.artifacts[3].metadata['hasVisualEvidenceRegister'],
              isTrue,
            );
            expect(package.artifacts[3].fileName, endsWith('.pdf'));
          }
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

class _ArtifactPackageSmokeCase {
  final String name;
  final String prompt;
  final String expectedLabel;
  final List<GeneratedArtifactKind> expectedKinds;
  final String? content;

  const _ArtifactPackageSmokeCase({
    required this.name,
    required this.prompt,
    required this.expectedLabel,
    required this.expectedKinds,
    this.content,
  });
}

const _visualEvidencePackageContent = '''
# Studio Visual Evidence Package

Evidence captured from UI review screenshots.

## Visual Evidence
- Screenshot: transcript answer is too narrow at 1366x768.
- UX evidence: right drawer source placeholders are visible without real sources.
- Screen capture evidence: plan card remains bounded with action controls visible.

## Sources
- Internal screenshot attachment metadata - checked 2026-07-01.

## Assumptions
- Pixel-level details require OCR/vision or user description before external claims.
''';

const _enterprisePackageContent = '''
# Campus Refresh Workbench Package

Executive summary for a Cisco-focused customer deliverable.

## Current State
- Three sites with mixed access switching.
- Wi-Fi 7 AP rollout requires multigig and UPOE validation.
- Lifecycle risk exists on the older access layer.

## Recommendations
- Validate PoE, uplink, WAN, and lifecycle assumptions before final selection.
- Create phased implementation and verification gates.
- Use source-backed evidence for lifecycle and model recommendations.

| Item | Count | Risk |
| --- | ---: | --- |
| Users | 500 | Medium |
| APs | 90 | High |
| Switches | 6 | Medium |

## Implementation Phases
1. Discovery and evidence collection.
2. Sizing and product comparison.
3. Pilot deployment and validation.
4. Production rollout.

## Sources
- Customer workshop notes - checked 2026-07-01.
- Cisco datasheet references - validation required before customer handoff.

## Assumptions
- Final customer counts may change.
- EoX replacement hints require current portfolio validation.
''';
