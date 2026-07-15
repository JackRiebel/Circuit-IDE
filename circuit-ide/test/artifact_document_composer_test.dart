import 'dart:io';

import 'package:circuit_ide/models/artifact_document.dart';
import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/services/generated_artifact_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ArtifactComposer extracts enterprise artifact block types', () {
    final document = const ArtifactComposer().fromAssistantOutput(
      prompt: 'create a PowerPoint deck and PDF report from this topology plan',
      content: '''
# Campus Refresh Handoff

Audience: Cisco SE leadership
Checked date: 2026-07-02

## Summary
- Build a customer handoff package.

## PoE Timeline Chart
- Show AP growth across three years.
- Compare required watts against switch budget.

## Source Data
| Site | APs | PoE Watts |
| --- | --- | --- |
| MDF | 30 | 1800 |
| IDF 1 | 20 | 1200 |

## Diagram
```mermaid
graph TD
  WAN --> Firewall
  Firewall --> Core
```

## Appendix A: Assumptions
- AP draw is estimated until site survey.

## Sources
- Internal design worksheet - checked 2026-07-02
''',
    );

    expect(document.title, 'Campus Refresh Handoff');
    expect(document.charts, hasLength(1));
    expect(document.charts.single.title, 'PoE Timeline Chart');
    expect(document.charts.single.type, 'timeline');
    expect(document.diagrams, hasLength(1));
    expect(document.diagrams.single.syntax, 'mermaid');
    expect(document.diagrams.single.source, contains('graph TD'));
    expect(document.appendices, hasLength(1));
    expect(document.appendices.single.title, 'Appendix A: Assumptions');
    expect(document.sourceData, hasLength(1));
    expect(document.sourceData.single.title, 'Source Data');
    expect(document.sourceData.single.rows, hasLength(3));
    expect(document.citations.single, contains('Internal design worksheet'));
    expect(
      document.exportMetadata.requestedFormats,
      containsAll(['pptx', 'pdf']),
    );
    expect(document.exportMetadata.audience, 'Cisco SE leadership');
    expect(document.exportMetadata.checkedDate, '2026-07-02');
  });

  test(
    'GeneratedArtifactWriter surfaces artifact block counts in metadata',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
      addTearDown(() => root.delete(recursive: true));

      final artifact = await const GeneratedArtifactWriter()
          .writeStructuredArtifact(
            rootPath: root.path,
            prompt: 'create a PDF report from this structured evidence',
            content: '''
# Topology Evidence Report

Audience: customer architecture review

## Topology Chart
- Compare branch counts by site.

## Source Data
| Site | Switches |
| --- | --- |
| MDF | 6 |
| IDF | 4 |

## Topology Diagram
```mermaid
graph LR
  Branch --> WAN
```

## Appendix: Raw Notes
- Workshop notes are incomplete.
''',
            targetKind: GeneratedArtifactKind.pdf,
            turnId: 'turn-artifact-blocks',
            threadId: 'thread-artifact-blocks',
            requestId: 'request-artifact-blocks',
          );

      expect(artifact, isNotNull);
      expect(artifact!.kind, GeneratedArtifactKind.pdf);
      expect(artifact.metadata['artifactChartCount'], 1);
      expect(artifact.metadata['artifactDiagramCount'], 1);
      expect(artifact.metadata['artifactAppendixCount'], 1);
      expect(artifact.metadata['artifactSourceDataCount'], 1);
      expect(
        artifact.metadata['artifactExportMetadata'],
        isA<Map<String, Object?>>(),
      );
      final exportMetadata =
          artifact.metadata['artifactExportMetadata'] as Map<String, Object?>;
      expect(exportMetadata['requestedFormats'], contains('pdf'));
      expect(exportMetadata['audience'], 'customer architecture review');
    },
  );
}
