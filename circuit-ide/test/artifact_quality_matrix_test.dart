import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/services/generated_artifact_writer.dart';
import 'package:flutter_test/flutter_test.dart';

const _content = '''
# Customer Readiness Evidence

This review records a decision, supporting data, and a dated source.

## Decision

- Approve the validated rollout path.
- Keep the rollback owner available during deployment.

## Readiness Matrix

| Gate | Status | Owner |
| --- | --- | --- |
| Architecture | Ready | Engineering |
| Verification | Passed | Quality |

## Network Topology

```mermaid
flowchart LR
  HQ[Headquarters] -->|Dual WAN| Branch[Branch]
```

## Assumptions

- Customer inventory remains current as of the checked date.

## Sources

- https://example.test/customer-readiness checked 2026-07-13
''';

void main() {
  test(
    'every generated artifact kind publishes one passing five-dimension quality matrix',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-artifact-quality-matrix-',
      );
      addTearDown(() => root.delete(recursive: true));
      const cases = <_MatrixCase>[
        _MatrixCase(
          GeneratedArtifactKind.excel,
          'Create an Excel readiness workbook',
        ),
        _MatrixCase(
          GeneratedArtifactKind.csv,
          'Create a CSV readiness dataset',
        ),
        _MatrixCase(
          GeneratedArtifactKind.markdown,
          'Create a Markdown readiness document',
        ),
        _MatrixCase(
          GeneratedArtifactKind.html,
          'Create an HTML readiness document',
        ),
        _MatrixCase(GeneratedArtifactKind.json, 'Create a JSON evidence pack'),
        _MatrixCase(GeneratedArtifactKind.pdf, 'Create a PDF readiness report'),
        _MatrixCase(
          GeneratedArtifactKind.powerPoint,
          'Create a PowerPoint readiness deck',
          content: '''
# Customer Readiness

## Decision

Approve the validated rollout path and keep the rollback owner available.

## Assumptions

Customer inventory remains current.

## Sources

- https://example.test/customer-readiness checked 2026-07-13
''',
        ),
        _MatrixCase(
          GeneratedArtifactKind.docx,
          'Create a Word readiness report',
        ),
        _MatrixCase(GeneratedArtifactKind.diagram, 'Create a topology diagram'),
        _MatrixCase(
          GeneratedArtifactKind.chart,
          'Create a readiness chart pack',
        ),
        _MatrixCase(
          GeneratedArtifactKind.report,
          'Create a customer readiness report',
        ),
      ];
      final reportRows = <Map<String, Object?>>[];

      for (final matrixCase in cases) {
        final artifact = await const GeneratedArtifactWriter()
            .writeStructuredArtifact(
              rootPath: root.path,
              prompt: matrixCase.prompt,
              content: matrixCase.content ?? _content,
              targetKind: matrixCase.kind,
              turnId: 'matrix-${matrixCase.kind.name}',
              threadId: 'thread-matrix',
              requestId: 'request-matrix',
            );

        expect(artifact, isNotNull, reason: matrixCase.kind.name);
        expect(artifact!.kind, matrixCase.kind, reason: matrixCase.kind.name);
        expect(await File(artifact.filePath).exists(), isTrue);
        expect(
          artifact.metadata['artifactQualityMatrixVersion'],
          '1.0',
          reason: matrixCase.kind.name,
        );
        expect(
          artifact.metadata['artifactQualityMatrixKind'],
          matrixCase.kind.name,
          reason: matrixCase.kind.name,
        );
        expect(
          artifact.metadata['artifactQualityMatrixGateCount'],
          5,
          reason: matrixCase.kind.name,
        );
        expect(
          artifact.metadata['artifactQualityMatrixPassed'],
          isTrue,
          reason:
              '${matrixCase.kind.name}: ${artifact.metadata['artifactQualityMatrixGaps']}',
        );
        final matrix = artifact.metadata['artifactQualityMatrix'] as List;
        expect(matrix, hasLength(5), reason: matrixCase.kind.name);
        for (final entry in matrix.cast<Map>()) {
          expect(entry['passed'], isTrue, reason: matrixCase.kind.name);
        }
        final sidecar = File(artifact.metadata['visualPreviewPath']! as String);
        expect(await sidecar.exists(), isTrue, reason: matrixCase.kind.name);
        expect(artifact.metadata['visualPreviewFormat'], 'svg');
        reportRows.add({
          'kind': matrixCase.kind.name,
          'passed': artifact.metadata['artifactQualityMatrixPassed'],
          'dimensions': matrix
              .cast<Map>()
              .map((entry) => entry['dimension'])
              .toList(growable: false),
        });
      }

      final report = {
        'schemaVersion': 1,
        'registeredKindCount': GeneratedArtifactKind.values.length,
        'evaluatedKindCount': reportRows.length,
        'matrixDimensions': const [
          'Structural validity',
          'Visual review',
          'Content completeness',
          'Source and citation provenance',
          'Accessibility',
        ],
        'allPassed': reportRows.every((row) => row['passed'] == true),
        'kinds': reportRows,
      };
      await _writeReportIfRequested(report);
      // Intentionally contains no prompt, path, customer data, or output body.
      // CI and the local wrapper can collect this one machine-readable line.
      // ignore: avoid_print
      print('ARTIFACT_QUALITY_MATRIX=${jsonEncode(report)}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('matrix makes source and visual overflow gaps release-visible', () async {
    final root = await Directory.systemTemp.createTemp(
      'circuit-artifact-quality-gap-',
    );
    addTearDown(() => root.delete(recursive: true));
    const title =
        'A deliberately overlong customer readiness decision title that exceeds the persisted document review frame';
    final artifact = await const GeneratedArtifactWriter()
        .writeStructuredArtifact(
          rootPath: root.path,
          prompt: 'Create a Word readiness report',
          content:
              '''
# $title

## Decision

- Approve the rollout after the remaining evidence review.

## Assumptions

- Customer inventory is awaiting confirmation.
''',
          targetKind: GeneratedArtifactKind.docx,
          turnId: 'matrix-gap',
          threadId: 'thread-matrix',
          requestId: 'request-matrix',
        );

    expect(artifact, isNotNull);
    expect(artifact!.metadata['artifactQualityMatrixPassed'], isFalse);
    expect(
      artifact.metadata['artifactQualityMatrixGaps'],
      containsAll(['Visual review', 'Source and citation provenance']),
    );
  });
}

Future<void> _writeReportIfRequested(Map<String, Object?> report) async {
  final path = Platform.environment['ARTIFACT_QUALITY_MATRIX_REPORT']?.trim();
  if (path == null || path.isEmpty) return;
  final destination = File(path);
  await destination.parent.create(recursive: true);
  final temporary = File('${destination.path}.tmp');
  await temporary.writeAsString(jsonEncode(report), flush: true);
  await temporary.rename(destination.path);
}

class _MatrixCase {
  final GeneratedArtifactKind kind;
  final String prompt;
  final String? content;

  const _MatrixCase(this.kind, this.prompt, {this.content});
}
