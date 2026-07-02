import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/services/artifact_type_registry.dart';
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
      'release prompts create Excel and PowerPoint artifacts with drawer metadata',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'circuit-artifact-release-smoke-',
        );
        addTearDown(() => root.delete(recursive: true));

        const cases = <_ReleaseArtifactSmokeCase>[
          _ReleaseArtifactSmokeCase(
            name: 'exact Excel file prompt',
            prompt: 'Create an Excel file from this inventory table.',
            content: '''
| Product SKU | Qty | Site | Notes |
| --- | ---: | --- | --- |
| C9300-48P | 6 | Campus | Access switching |
| CW9176I | 90 | Campus | Wi-Fi 7 APs |
| MX250 | 2 | Edge | Warm spare pair |
''',
            kind: GeneratedArtifactKind.excel,
            extension: '.xlsx',
            descriptorId: 'excel_workbook',
            descriptorLabel: 'Excel Workbook',
            previewSurface: 'Workbook preview',
            packageNeedles: ['xl/workbook.xml', 'xl/worksheets/sheet1.xml'],
          ),
          _ReleaseArtifactSmokeCase(
            name: 'exact PowerPoint deck prompt',
            prompt: 'Create a PowerPoint deck from this architecture brief.',
            content: '''
# Campus Refresh Executive Deck

Short executive summary for the customer.

## Goals
- Validate Wi-Fi 7 PoE and multigig access requirements.
- Summarize architecture risks and recommendations.

## Recommendations
- Use current portfolio validation before selecting replacement models.
- Confirm WAN, HA, and lifecycle assumptions before customer handoff.

## Assumptions
- Inventory counts are customer-provided and require final validation.

## Sources
- Customer workshop notes - checked 2026-07-01.
''',
            kind: GeneratedArtifactKind.powerPoint,
            extension: '.pptx',
            descriptorId: 'powerpoint_deck',
            descriptorLabel: 'PowerPoint Deck',
            previewSurface: 'Slide outline',
            packageNeedles: ['ppt/presentation.xml', 'ppt/slides/slide1.xml'],
          ),
        ];

        for (final smokeCase in cases) {
          final artifact = await const GeneratedArtifactWriter()
              .writeFromAssistantOutput(
                rootPath: root.path,
                prompt: smokeCase.prompt,
                content: smokeCase.content,
                turnId: 'turn-release-${smokeCase.kind.name}',
                threadId: 'thread-release-smoke',
                requestId: 'request-release-smoke',
              );

          expect(artifact, isNotNull, reason: smokeCase.name);
          expect(artifact!.kind, smokeCase.kind, reason: smokeCase.name);
          expect(artifact.status, GeneratedArtifactStatus.ready);
          expect(artifact.fileName, endsWith(smokeCase.extension));
          expect(artifact.summary, isNot(contains('| Product SKU |')));
          expect(artifact.summary, isNot(contains('```')));
          expect(artifact.previewRows, isNotEmpty, reason: smokeCase.name);
          expect(
            artifact.metadata['artifactDescriptorId'],
            smokeCase.descriptorId,
          );
          expect(
            artifact.metadata['artifactDescriptorLabel'],
            smokeCase.descriptorLabel,
          );
          expect(
            artifact.metadata['artifactPreviewSurface'],
            smokeCase.previewSurface,
          );
          expect(
            artifact.metadata['artifactDrawerActions'],
            containsAll(['Open', 'Reveal in Finder', 'Copy path', 'Review']),
            reason: smokeCase.name,
          );
          expect(
            artifact.metadata['artifactProducedKind'],
            smokeCase.kind.name,
          );

          final file = File(artifact.filePath);
          expect(file.existsSync(), isTrue, reason: smokeCase.name);
          expect(
            file.path.startsWith(
              '${root.path}${Platform.pathSeparator}outputs',
            ),
            isTrue,
            reason: smokeCase.name,
          );
          final packageText = String.fromCharCodes(file.readAsBytesSync());
          for (final needle in smokeCase.packageNeedles) {
            expect(packageText, contains(needle), reason: smokeCase.name);
          }

          final sourceArtifact = artifact.toSourceArtifact();
          expect(sourceArtifact.title, artifact.fileName);
          expect(sourceArtifact.subtitle, contains(artifact.typeLabel));
          expect(sourceArtifact.filePath, artifact.filePath);
          final restored = GeneratedArtifact.fromSourceArtifact(sourceArtifact);
          expect(restored, isNotNull, reason: smokeCase.name);
          expect(
            restored!.metadata['artifactDescriptorId'],
            smokeCase.descriptorId,
          );
          expect(
            restored.metadata['artifactPreviewSurface'],
            smokeCase.previewSurface,
          );
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
              GeneratedArtifactKind.pdf,
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
              GeneratedArtifactKind.powerPoint,
              GeneratedArtifactKind.pdf,
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
              GeneratedArtifactKind.powerPoint,
              GeneratedArtifactKind.pdf,
            ],
          ),
          _ArtifactPackageSmokeCase(
            name: 'chart package',
            prompt: 'create a chart package for PoE budget risk',
            expectedLabel: 'chart package',
            expectedKinds: [
              GeneratedArtifactKind.markdown,
              GeneratedArtifactKind.chart,
              GeneratedArtifactKind.powerPoint,
              GeneratedArtifactKind.pdf,
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
              GeneratedArtifactKind.powerPoint,
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
              GeneratedArtifactKind.powerPoint,
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
              GeneratedArtifactKind.powerPoint,
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
              GeneratedArtifactKind.powerPoint,
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
            expect(package.artifacts[2].fileName, endsWith('.pptx'));
            expect(
              package.artifacts[3].metadata['hasVisualEvidenceRegister'],
              isTrue,
            );
            expect(
              package.artifacts[4].metadata['hasVisualEvidenceRegister'],
              isTrue,
            );
            expect(package.artifacts[4].fileName, endsWith('.pdf'));
          }
        }
      },
    );

    test(
      'every priority registry descriptor has an executable generation route',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'circuit-artifact-registry-smoke-',
        );
        addTearDown(() => root.delete(recursive: true));
        const registry = ArtifactTypeRegistry();
        const packageWriter = GeneratedArtifactPackageWriter();
        const cases = <_PriorityDescriptorSmokeCase>[
          _PriorityDescriptorSmokeCase(
            descriptorId: 'powerpoint_deck',
            prompt: 'create a PowerPoint deck for this customer proposal',
            expectedTargets: [GeneratedArtifactKind.powerPoint],
          ),
          _PriorityDescriptorSmokeCase(
            descriptorId: 'docx_report',
            prompt: 'create a customer proposal report',
            expectedTargets: [GeneratedArtifactKind.docx],
          ),
          _PriorityDescriptorSmokeCase(
            descriptorId: 'pdf_report',
            prompt: 'create a final customer handoff PDF',
            expectedTargets: [GeneratedArtifactKind.pdf],
          ),
          _PriorityDescriptorSmokeCase(
            descriptorId: 'excel_workbook',
            prompt: 'create an Excel workbook from this inventory',
            expectedTargets: [GeneratedArtifactKind.excel],
          ),
          _PriorityDescriptorSmokeCase(
            descriptorId: 'csv_dataset',
            prompt: 'create a CSV dataset export from this table',
            expectedTargets: [GeneratedArtifactKind.csv],
          ),
          _PriorityDescriptorSmokeCase(
            descriptorId: 'network_topology_diagram',
            prompt: 'create a network topology package for this Cisco campus',
            expectedTargets: [
              GeneratedArtifactKind.diagram,
              GeneratedArtifactKind.powerPoint,
              GeneratedArtifactKind.pdf,
            ],
          ),
          _PriorityDescriptorSmokeCase(
            descriptorId: 'architecture_review_pack',
            prompt: 'create an architecture review package for this design',
            expectedTargets: [
              GeneratedArtifactKind.docx,
              GeneratedArtifactKind.powerPoint,
              GeneratedArtifactKind.pdf,
            ],
          ),
          _PriorityDescriptorSmokeCase(
            descriptorId: 'solution_sizing_workbook',
            prompt: 'create a solution sizing package for 500 users and 90 APs',
            expectedTargets: [
              GeneratedArtifactKind.excel,
              GeneratedArtifactKind.chart,
              GeneratedArtifactKind.powerPoint,
              GeneratedArtifactKind.pdf,
            ],
          ),
          _PriorityDescriptorSmokeCase(
            descriptorId: 'lifecycle_eox_report',
            prompt: 'create an LDOS lifecycle report package',
            expectedTargets: [
              GeneratedArtifactKind.excel,
              GeneratedArtifactKind.powerPoint,
              GeneratedArtifactKind.pdf,
              GeneratedArtifactKind.json,
            ],
          ),
          _PriorityDescriptorSmokeCase(
            descriptorId: 'product_comparison_matrix',
            prompt: 'create a product comparison package for C9300 and MS355',
            expectedTargets: [
              GeneratedArtifactKind.excel,
              GeneratedArtifactKind.chart,
              GeneratedArtifactKind.powerPoint,
              GeneratedArtifactKind.pdf,
            ],
          ),
          _PriorityDescriptorSmokeCase(
            descriptorId: 'business_use_case_brief',
            prompt: 'create a business case package for this customer',
            expectedTargets: [
              GeneratedArtifactKind.docx,
              GeneratedArtifactKind.powerPoint,
              GeneratedArtifactKind.chart,
              GeneratedArtifactKind.pdf,
            ],
          ),
          _PriorityDescriptorSmokeCase(
            descriptorId: 'implementation_plan',
            prompt: 'create an implementation plan package for this project',
            expectedTargets: [
              GeneratedArtifactKind.docx,
              GeneratedArtifactKind.powerPoint,
              GeneratedArtifactKind.pdf,
            ],
          ),
          _PriorityDescriptorSmokeCase(
            descriptorId: 'change_summary_diff_report',
            prompt: 'create a post-work change summary package',
            expectedTargets: [
              GeneratedArtifactKind.docx,
              GeneratedArtifactKind.powerPoint,
              GeneratedArtifactKind.pdf,
            ],
          ),
          _PriorityDescriptorSmokeCase(
            descriptorId: 'chart_pack',
            prompt: 'create a chart pack for PoE budget risk',
            expectedTargets: [
              GeneratedArtifactKind.chart,
              GeneratedArtifactKind.powerPoint,
              GeneratedArtifactKind.pdf,
            ],
          ),
          _PriorityDescriptorSmokeCase(
            descriptorId: 'evidence_pack',
            prompt: 'create a final evidence pack for customer handoff',
            expectedTargets: [
              GeneratedArtifactKind.docx,
              GeneratedArtifactKind.powerPoint,
              GeneratedArtifactKind.json,
              GeneratedArtifactKind.pdf,
            ],
          ),
        ];

        expect(cases.map((entry) => entry.descriptorId).toSet().length, 15);

        for (final smokeCase in cases) {
          final route = registry.routeForPrompt(smokeCase.prompt);
          expect(
            route.descriptor?.id,
            smokeCase.descriptorId,
            reason: smokeCase.descriptorId,
          );
          expect(
            route.targetKinds,
            smokeCase.expectedTargets,
            reason: smokeCase.descriptorId,
          );

          final package = await packageWriter.writePackageFromAssistantOutput(
            rootPath: root.path,
            prompt: smokeCase.prompt,
            content: _enterprisePackageContent,
            turnId: 'turn-${smokeCase.descriptorId}',
            threadId: 'thread-registry-smoke',
            requestId: 'request-registry-smoke',
          );

          expect(package, isNotNull, reason: smokeCase.descriptorId);
          final expectedKinds = smokeCase.expectedTargets.length > 1
              ? [GeneratedArtifactKind.markdown, ...smokeCase.expectedTargets]
              : smokeCase.expectedTargets;
          expect(
            package!.artifacts.map((artifact) => artifact.kind).toList(),
            expectedKinds,
            reason: smokeCase.descriptorId,
          );
          for (final artifact in package.artifacts) {
            expect(
              File(artifact.filePath).existsSync(),
              isTrue,
              reason: '${smokeCase.descriptorId}: ${artifact.fileName}',
            );
            expect(
              artifact.filePath.startsWith(
                '${root.path}${Platform.pathSeparator}outputs',
              ),
              isTrue,
              reason: '${smokeCase.descriptorId}: ${artifact.fileName}',
            );
            expect(
              artifact.summary.trim(),
              isNotEmpty,
              reason: '${smokeCase.descriptorId}: ${artifact.fileName}',
            );
            expect(
              GeneratedArtifact.fromSourceArtifact(artifact.toSourceArtifact()),
              isNotNull,
              reason: '${smokeCase.descriptorId}: ${artifact.fileName}',
            );
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

class _ReleaseArtifactSmokeCase {
  final String name;
  final String prompt;
  final String content;
  final GeneratedArtifactKind kind;
  final String extension;
  final String descriptorId;
  final String descriptorLabel;
  final String previewSurface;
  final List<String> packageNeedles;

  const _ReleaseArtifactSmokeCase({
    required this.name,
    required this.prompt,
    required this.content,
    required this.kind,
    required this.extension,
    required this.descriptorId,
    required this.descriptorLabel,
    required this.previewSurface,
    required this.packageNeedles,
  });
}

class _PriorityDescriptorSmokeCase {
  final String descriptorId;
  final String prompt;
  final List<GeneratedArtifactKind> expectedTargets;

  const _PriorityDescriptorSmokeCase({
    required this.descriptorId,
    required this.prompt,
    required this.expectedTargets,
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
