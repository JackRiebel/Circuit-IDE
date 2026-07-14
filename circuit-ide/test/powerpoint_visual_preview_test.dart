import 'dart:io';

import 'package:circuit_ide/models/artifact_document.dart';
import 'package:circuit_ide/models/artifact_template.dart';
import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/services/generated_artifact_writer.dart';
import 'package:circuit_ide/services/powerpoint_artifact_renderer.dart';
import 'package:circuit_ide/services/powerpoint_visual_preview_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const document = ArtifactDocument(
    title: 'Customer Readiness Decision',
    summary: 'A decision-ready readiness review.',
    sections: [
      ArtifactSection(
        title: 'Decision',
        bullets: [
          'Approve the validated rollout path.',
          'Keep the rollback owner on call.',
        ],
      ),
      ArtifactSection(
        title: 'Evidence',
        bullets: ['All preflight checks passed.'],
      ),
    ],
    metadata: {
      'artifactBrandTemplate': {
        'id': 'customer-briefing',
        'version': '1.0',
        'label': 'Customer briefing',
        'organizationName': 'Customer briefing',
        'logoText': 'CUSTOMER BRIEFING',
        'primaryColor': '0F3D56',
        'accentColor': '0E7490',
        'fontFamily': 'Aptos Display',
        'footerText': 'Customer briefing · Prepared by CircuitCode',
        'confidentialityLabel': 'CONFIDENTIAL',
        'layout': 'executive-light',
      },
    },
  );

  testWidgets('PowerPoint preview has a stable review surface', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 450));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final preview = const PowerPointVisualPreviewRenderer().render(document);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: SvgPicture.string(
              String.fromCharCodes(preview.bytes),
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(SvgPicture),
      matchesGoldenFile('goldens/powerpoint_customer_briefing_preview.png'),
    );
  });

  test('deck preview covers every generated slide in package order', () {
    final preview = const PowerPointVisualPreviewRenderer().renderDeck(
      document,
    );
    final expectedSlides = const PowerPointArtifactRenderer().slideCountFor(
      document,
    );
    final svg = String.fromCharCodes(preview.bytes);

    expect(
      preview.metadata['pptxVisualPreviewRenderer'],
      'artifact_document_multislide_v2',
    );
    expect(
      preview.metadata['pptxVisualPreviewReviewMode'],
      'structural_multi_slide',
    );
    expect(preview.metadata['pptxVisualPreviewSlideCount'], expectedSlides);
    expect(preview.metadata['pptxVisualPreviewFirstSlideOnly'], isFalse);
    expect(svg, contains('slide 1 of $expectedSlides'));
    expect(svg, contains('slide $expectedSlides of $expectedSlides'));
    expect(svg, contains('Decision Flow'));
  });

  test(
    'PowerPoint artifact persists an inspectable visual preview sidecar',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-ppt-preview-',
      );
      addTearDown(() => root.delete(recursive: true));
      final artifact = await const GeneratedArtifactWriter()
          .writeStructuredArtifact(
            rootPath: root.path,
            prompt: 'Create a PowerPoint customer readiness deck',
            content: '''
# Customer Readiness Decision

## Decision
- Approve the validated rollout path.
- Keep the rollback owner on call.
''',
            targetKind: GeneratedArtifactKind.powerPoint,
            templateId: ArtifactTemplateRegistry.customerBriefing.id,
            turnId: 'ppt-preview',
            threadId: 'thread',
            requestId: 'request',
          );

      expect(artifact, isNotNull);
      expect(
        artifact!.metadata['pptxVisualPreviewRenderer'],
        'artifact_document_multislide_v2',
      );
      expect(
        artifact.metadata['pptxVisualPreviewReviewMode'],
        'structural_multi_slide',
      );
      expect(artifact.metadata['pptxVisualPreviewFirstSlideOnly'], isFalse);
      expect(
        artifact.metadata['pptxVisualPreviewSlideCount'],
        artifact.sheetCount,
      );
      expect(
        artifact.metadata['pptxVisualPreviewOverflowSlideNumbers'],
        isEmpty,
      );
      expect(artifact.metadata['pptxVisualPreviewHasTitleOverflow'], isFalse);
      expect(artifact.metadata['pptxVisualPreviewHasContentOverflow'], isFalse);
      final previewPath = artifact.metadata['visualPreviewPath'] as String?;
      expect(previewPath, isNotNull);
      expect(artifact.metadata['visualPreviewFormat'], 'svg');
      final preview = File(previewPath!);
      expect(await preview.exists(), isTrue);
      final svg = await preview.readAsString();
      expect(svg, contains('CUSTOMER BRIEFING'));
      expect(svg, contains('CONFIDENTIAL'));
      expect(svg, contains('Customer briefing'));
      expect(svg, contains('Structural review · slide 1 of'));
    },
  );

  test('PowerPoint visual overflow blocks customer-ready quality', () async {
    final root = await Directory.systemTemp.createTemp('circuit-ppt-overflow-');
    addTearDown(() => root.delete(recursive: true));
    const title =
        'A deliberately long PowerPoint decision title that exceeds the bounded first-slide review frame';
    final artifact = await const GeneratedArtifactWriter()
        .writeStructuredArtifact(
          rootPath: root.path,
          prompt: 'Create a PowerPoint customer readiness deck',
          content:
              '''
# $title

## Decision
- First decision point has an intentionally overlong explanation that exceeds the bounded 150-character renderer frame and must remain visible to visual QA rather than being silently truncated in the persisted deck review sidecar for customer-facing publication.
- Second decision point.
- Third decision point.
- Fourth decision point.
- Fifth decision point.
- Sixth decision point.
''',
          targetKind: GeneratedArtifactKind.powerPoint,
          turnId: 'ppt-overflow',
          threadId: 'thread',
          requestId: 'request',
        );

    expect(artifact, isNotNull);
    expect(artifact!.metadata['pptxVisualPreviewHasTitleOverflow'], isTrue);
    expect(artifact.metadata['pptxVisualPreviewHasContentOverflow'], isTrue);
    expect(
      artifact.metadata['pptxVisualPreviewOverflowSlideNumbers'],
      isNotEmpty,
    );
    expect(
      artifact.metadata['qualityGaps'],
      contains('PowerPoint visual preview title overflows its review frame'),
    );
    expect(
      artifact.metadata['qualityGaps'],
      contains('PowerPoint visual preview content overflows its review frame'),
    );
    expect(artifact.metadata['hasCustomerReadyArtifact'], isFalse);
  });
}
