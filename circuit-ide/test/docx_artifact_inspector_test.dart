import 'package:circuit_ide/models/artifact_document.dart';
import 'package:circuit_ide/services/docx_artifact_inspector.dart';
import 'package:circuit_ide/services/docx_artifact_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DOCX inspector verifies enterprise report structure', () {
    const document = ArtifactDocument(
      title: 'Campus Architecture Review',
      summary:
          'Architecture review for campus switching, wireless, WAN, and lifecycle readiness.',
      sections: [
        ArtifactSection(
          title: 'Findings',
          body:
              'The access layer needs multigig and PoE validation before final model selection.',
          bullets: [
            'Validate uplink capacity.',
            'Confirm AP power requirements.',
          ],
        ),
        ArtifactSection(
          title: 'Recommendations',
          bullets: [
            'Use current portfolio candidates.',
            'Treat EoX replacement PIDs as migration clues only.',
          ],
        ),
      ],
      tables: [
        ArtifactTable(
          title: 'Sizing Inputs',
          rows: [
            ['Site', 'Users', 'WAN'],
            ['HQ', '500', '2 Gbps'],
            ['Branch', '120', '500 Mbps'],
          ],
        ),
      ],
      assumptions: ['Customer will validate final inventory.'],
      citations: ['Customer workshop notes.'],
    );

    final bytes = const DocxArtifactRenderer().render(document);
    final inspection = const DocxArtifactInspector().inspect(bytes);

    expect(inspection.isStructurallyValid, isTrue);
    expect(inspection.hasExpectedReportStructure, isTrue);
    expect(inspection.title, 'Campus Architecture Review');
    expect(inspection.tableCount, greaterThanOrEqualTo(3));
    expect(inspection.bulletCount, greaterThanOrEqualTo(5));
    expect(inspection.headingCount, greaterThanOrEqualTo(6));
    expect(inspection.declaredWordCount, greaterThan(20));
    expect(inspection.declaredParagraphCount, greaterThan(10));
    expect(inspection.hasExecutiveDecisionBrief, isTrue);
    expect(inspection.hasValidationChecklist, isTrue);
    expect(inspection.hasAssumptionsAppendix, isTrue);
    expect(inspection.hasSourcesAppendix, isTrue);
    expect(inspection.hasKeywordsMetadata, isTrue);
  });

  test('DOCX inspector verifies report package without appendices', () {
    const document = ArtifactDocument(
      title: 'Implementation Plan',
      summary: 'Plan for a focused implementation pass.',
      sections: [
        ArtifactSection(
          title: 'Phase 1',
          bullets: ['Build the artifact writer.', 'Verify generated files.'],
        ),
        ArtifactSection(
          title: 'Phase 2',
          body: 'Polish drawer preview and outcome cards.',
        ),
      ],
    );

    final bytes = const DocxArtifactRenderer().render(document);
    final inspection = const DocxArtifactInspector().inspect(bytes);

    expect(inspection.isStructurallyValid, isTrue);
    expect(inspection.hasExpectedReportStructure, isTrue);
    expect(inspection.title, 'Implementation Plan');
    expect(inspection.hasAssumptionsAppendix, isFalse);
    expect(inspection.hasSourcesAppendix, isFalse);
    expect(inspection.tableCount, greaterThanOrEqualTo(2));
    expect(inspection.hasExecutiveDecisionBrief, isTrue);
    expect(inspection.hasValidationChecklist, isTrue);
    expect(inspection.hasCircuitFooter, isTrue);
    expect(inspection.hasEnterpriseStyles, isTrue);
    expect(inspection.hasKeywordsMetadata, isTrue);
  });
}
