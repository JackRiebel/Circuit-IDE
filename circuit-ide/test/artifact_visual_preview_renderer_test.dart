import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/models/artifact_document.dart';
import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/services/artifact_visual_preview_renderer.dart';
import 'package:circuit_ide/services/generated_artifact_writer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const document = ArtifactDocument(
    title: 'Customer Readiness Decision',
    summary: 'A concise decision-ready readiness review.',
    sections: [
      ArtifactSection(
        title: 'Decision',
        bullets: ['Approve the validated rollout path.'],
      ),
      ArtifactSection(
        title: 'Validation',
        bullets: ['Keep the rollback owner on call.'],
      ),
    ],
  );

  test('structural report preview records its non-native review boundary', () {
    final preview = const ArtifactVisualPreviewRenderer().render(
      kind: GeneratedArtifactKind.docx,
      document: document,
      previewRows: const [
        ['Section', 'Items'],
        ['Decision', '1'],
      ],
      unitCount: 2,
    );

    expect(
      preview.metadata['artifactVisualPreviewRenderer'],
      'artifact_document_structural_v1',
    );
    expect(preview.metadata['artifactVisualPreviewReviewMode'], 'structural');
    expect(preview.metadata['artifactVisualPreviewIsNativeRender'], isFalse);
    expect(preview.metadata['artifactVisualPreviewHasOverflow'], isFalse);
    final svg = utf8.decode(preview.bytes);
    expect(svg, contains('Word report structural review'));
    expect(svg, contains('native review required'));
  });

  testWidgets(
    'Word PDF and Excel structural previews have stable visual references',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 420));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const renderer = ArtifactVisualPreviewRenderer();
      const cases = [
        (GeneratedArtifactKind.docx, 'word'),
        (GeneratedArtifactKind.pdf, 'pdf'),
        (GeneratedArtifactKind.excel, 'excel'),
      ];

      for (final (kind, goldenName) in cases) {
        final preview = renderer.render(
          kind: kind,
          document: document,
          previewRows: const [
            ['Gate', 'Status'],
            ['Architecture', 'Ready'],
            ['Verification', 'Passed'],
          ],
          unitCount: 2,
          workbookSheets: kind == GeneratedArtifactKind.excel
              ? const [
                  ArtifactVisualPreviewSheet(
                    name: 'Readiness',
                    rows: [
                      ['Gate', 'Status'],
                      ['Architecture', 'Ready'],
                      ['Verification', 'Passed'],
                    ],
                  ),
                ]
              : const [],
        );
        expect(
          preview.metadata['artifactVisualPreviewHasOverflow'],
          isFalse,
          reason: goldenName,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox.expand(
                child: SvgPicture.string(
                  String.fromCharCodes(preview.bytes),
                  key: ValueKey('artifact-structural-$goldenName'),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byKey(ValueKey('artifact-structural-$goldenName')),
          matchesGoldenFile('goldens/artifact_structural_$goldenName.png'),
        );
      }
    },
  );

  test('structural report preview retains content across review pages', () {
    const longDocument = ArtifactDocument(
      title: 'Long-form customer readiness report',
      summary: 'Executive summary remains in the persisted review surface.',
      sections: [
        ArtifactSection(title: 'Decision', bullets: ['Approve the rollout.']),
        ArtifactSection(title: 'Validation', bullets: ['Run the smoke test.']),
        ArtifactSection(title: 'Risks', bullets: ['Keep rollback ready.']),
        ArtifactSection(
          title: 'Handoff',
          bullets: ['Keep this final review item visible.'],
        ),
      ],
    );
    final preview = const ArtifactVisualPreviewRenderer().render(
      kind: GeneratedArtifactKind.pdf,
      document: longDocument,
      previewRows: const [
        ['Section', 'Items'],
        ['Decision', '1'],
      ],
      unitCount: 2,
    );

    expect(preview.metadata['artifactVisualPreviewReviewPageCount'], 2);
    final svg = utf8.decode(preview.bytes);
    expect(svg, contains('PDF report structural review · page 1 of 2'));
    expect(svg, contains('PDF report structural review · page 2 of 2'));
    expect(svg, contains('Keep this final review item visible.'));
  });

  test('workbook preview identifies values wider than generated columns', () {
    final preview = const ArtifactVisualPreviewRenderer().render(
      kind: GeneratedArtifactKind.excel,
      document: document,
      previewRows: const [
        ['Gate', 'Decision detail'],
        [
          'Readiness',
          'averylongunbreakableworkbookcellvaluethatexceedsthegeneratedcolumnwidthcap',
        ],
      ],
      unitCount: 1,
    );

    expect(preview.metadata['artifactVisualPreviewHasTableOverflow'], isTrue);
    expect(preview.metadata['artifactVisualPreviewHasOverflow'], isTrue);
    expect(
      String.fromCharCodes(preview.bytes),
      contains('Generated column width may clip table values'),
    );
  });

  test('workbook preview localizes rows beyond Excel height limits', () {
    final tallValue = List<String>.filled(
      31,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    ).join(' ');
    final preview = const ArtifactVisualPreviewRenderer().render(
      kind: GeneratedArtifactKind.excel,
      document: document,
      previewRows: [
        ['Evidence', 'Decision detail'],
        ['Height check', tallValue],
      ],
      unitCount: 1,
      workbookSheets: [
        ArtifactVisualPreviewSheet(
          name: 'Height review',
          rows: [
            ['Evidence', 'Decision detail'],
            ['Height check', tallValue],
          ],
        ),
      ],
    );

    expect(preview.metadata['artifactVisualPreviewHasTableOverflow'], isTrue);
    expect(
      preview.metadata['artifactVisualPreviewHasRowHeightOverflow'],
      isTrue,
    );
    expect(
      preview.metadata['artifactVisualPreviewRowHeightOverflowSheetNames'],
      ['Height review'],
    );
    expect(
      preview.metadata['artifactVisualPreviewColumnOverflowSheetNames'],
      isEmpty,
    );
    expect(preview.metadata['artifactVisualPreviewOverflowRowNumbersBySheet'], {
      'Height review': [2],
    });
    expect(
      String.fromCharCodes(preview.bytes),
      contains('Generated row height exceeds the supported Excel limit'),
    );
  });

  test(
    'workbook preview reviews every generated sheet and localizes overflow',
    () {
      final preview = const ArtifactVisualPreviewRenderer().render(
        kind: GeneratedArtifactKind.excel,
        document: document,
        previewRows: const [
          ['Gate', 'Status'],
          ['Readiness', 'Ready'],
        ],
        unitCount: 2,
        workbookSheets: const [
          ArtifactVisualPreviewSheet(
            name: 'Overview',
            rows: [
              ['Gate', 'Status'],
              ['Readiness', 'Ready'],
            ],
          ),
          ArtifactVisualPreviewSheet(
            name: 'Risks',
            rows: [
              ['Risk', 'Detail'],
              [
                'Overflow',
                'averylongunbreakableworkbookcellvaluethatexceedsthegeneratedcolumnwidthcap',
              ],
            ],
          ),
        ],
      );

      expect(preview.metadata['artifactVisualPreviewSheetCount'], 2);
      expect(preview.metadata['artifactVisualPreviewReviewPageCount'], 2);
      expect(preview.metadata['artifactVisualPreviewOverflowSheetNames'], [
        'Risks',
      ]);
      final svg = utf8.decode(preview.bytes);
      expect(svg, contains('Sheet 1 of 2 · Overview'));
      expect(svg, contains('Sheet 2 of 2 · Risks'));
      expect(svg, contains('Generated column width may clip table values'));
    },
  );

  test(
    'writer persists review sidecars for Word, PDF, and Excel artifacts',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-artifact-preview-',
      );
      addTearDown(() => root.delete(recursive: true));
      const content = '''
# Customer Readiness

## Decision

- Approve the validated rollout path.

## Validation

- Keep the rollback owner on call.

## Evidence

- All preflight checks passed.

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
      const cases = [
        (GeneratedArtifactKind.docx, 'Create a Word customer readiness report'),
        (GeneratedArtifactKind.pdf, 'Create a PDF customer readiness report'),
        (
          GeneratedArtifactKind.excel,
          'Create an Excel customer readiness workbook',
        ),
      ];

      for (final (kind, prompt) in cases) {
        final artifact = await const GeneratedArtifactWriter()
            .writeStructuredArtifact(
              rootPath: root.path,
              prompt: prompt,
              content: content,
              targetKind: kind,
              turnId: 'preview-${kind.name}',
              threadId: 'thread-preview',
              requestId: 'request-preview',
            );

        expect(artifact, isNotNull, reason: kind.name);
        expect(
          artifact!.metadata['artifactVisualPreviewRenderer'],
          'artifact_document_structural_v1',
          reason: kind.name,
        );
        expect(
          artifact.metadata['artifactVisualPreviewHasOverflow'],
          isFalse,
          reason: kind.name,
        );
        expect(artifact.metadata['visualPreviewFormat'], 'svg');
        final sidecar = File(artifact.metadata['visualPreviewPath']! as String);
        expect(await sidecar.exists(), isTrue, reason: kind.name);
        expect(
          await sidecar.readAsString(),
          contains('Structural sidecar'),
          reason: kind.name,
        );
        expect(
          artifact.metadata['qualityGaps'],
          isNot(contains('structural visual preview is missing')),
        );
      }
    },
  );

  test(
    'writer blocks an Excel readiness result with a clipped cell risk',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-artifact-preview-overflow-',
      );
      addTearDown(() => root.delete(recursive: true));
      final artifact = await const GeneratedArtifactWriter()
          .writeStructuredArtifact(
            rootPath: root.path,
            prompt: 'Create an Excel decision workbook',
            targetKind: GeneratedArtifactKind.excel,
            turnId: 'preview-overflow',
            threadId: 'thread-preview',
            requestId: 'request-preview',
            content: '''
# Readiness Matrix

## Decision

- Approve the validated rollout path.

| Gate | Decision detail |
| --- | --- |
| Readiness | averylongunbreakableworkbookcellvaluethatexceedsthegeneratedcolumnwidthcap |
''',
          );

      expect(artifact, isNotNull);
      expect(
        artifact!.metadata['artifactVisualPreviewHasTableOverflow'],
        isTrue,
      );
      expect(
        artifact.metadata['qualityGaps'],
        contains(
          'Excel workbook structural preview table may clip generated values',
        ),
      );
      expect(artifact.metadata['workbookWrapTextEnabled'], isTrue);
      expect(artifact.metadata['workbookRowHeightsAdjusted'], isTrue);
      final package = utf8.decode(
        await File(artifact.filePath).readAsBytes(),
        allowMalformed: true,
      );
      expect(package, contains('customHeight="1"'));
      expect(artifact.metadata['hasCustomerReadyArtifact'], isFalse);
    },
  );

  test(
    'writer caps unsafe Excel row heights and records the readiness gap',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-artifact-preview-height-overflow-',
      );
      addTearDown(() => root.delete(recursive: true));
      final tallValue = List<String>.filled(
        31,
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ).join(' ');
      final artifact = await const GeneratedArtifactWriter()
          .writeStructuredArtifact(
            rootPath: root.path,
            prompt: 'Create an Excel decision workbook',
            targetKind: GeneratedArtifactKind.excel,
            turnId: 'preview-height-overflow',
            threadId: 'thread-preview',
            requestId: 'request-preview',
            content:
                '''
# Readiness Matrix

## Decision

- Approve the validated rollout path.

| Gate | Decision detail |
| --- | --- |
| Readiness | $tallValue |
''',
          );

      expect(artifact, isNotNull);
      expect(
        artifact!.metadata['artifactVisualPreviewHasRowHeightOverflow'],
        isTrue,
      );
      expect(
        artifact.metadata['qualityGaps'],
        contains(
          'Excel workbook structural preview has a row beyond the supported Excel height',
        ),
      );
      expect(artifact.metadata['hasCustomerReadyArtifact'], isFalse);
      final package = utf8.decode(
        await File(artifact.filePath).readAsBytes(),
        allowMalformed: true,
      );
      expect(package, contains('ht="405.0" customHeight="1"'));
      expect(package, isNot(contains('ht="465.0" customHeight="1"')));
    },
  );

  test('writer exposes workbook sheet truncation as a readiness gap', () async {
    final root = await Directory.systemTemp.createTemp(
      'circuit-artifact-sheet-limit-',
    );
    addTearDown(() => root.delete(recursive: true));
    final tables = List.generate(
      49,
      (index) =>
          '''
## Table ${index + 1}

| Gate | Status |
| --- | --- |
| Check ${index + 1} | Ready |
''',
    ).join('\n');

    final artifact = await const GeneratedArtifactWriter()
        .writeStructuredArtifact(
          rootPath: root.path,
          prompt: 'Create an Excel workbook with every check table',
          content: tables,
          targetKind: GeneratedArtifactKind.excel,
          turnId: 'preview-sheet-limit',
          threadId: 'thread-preview',
          requestId: 'request-preview',
        );

    expect(artifact, isNotNull);
    expect(artifact!.sheetCount, 48);
    expect(artifact.metadata['workbookInputSheetCount'], 49);
    expect(artifact.metadata['workbookPackagedSheetCount'], 48);
    expect(artifact.metadata['workbookSheetsTruncated'], isTrue);
    expect(artifact.metadata['artifactVisualPreviewSheetCount'], 48);
    expect(
      artifact.metadata['qualityGaps'],
      contains('Workbook input exceeds the generated sheet limit'),
    );
    expect(artifact.metadata['hasCustomerReadyArtifact'], isFalse);
  });
}
