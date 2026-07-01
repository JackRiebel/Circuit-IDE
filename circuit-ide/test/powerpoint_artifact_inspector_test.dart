import 'package:circuit_ide/models/artifact_document.dart';
import 'package:circuit_ide/services/powerpoint_artifact_inspector.dart';
import 'package:circuit_ide/services/powerpoint_artifact_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PowerPoint inspector verifies enterprise deck structure', () {
    const document = ArtifactDocument(
      title: 'Customer Architecture Proposal',
      summary: 'Executive-ready customer proposal for a campus refresh.',
      sections: [
        ArtifactSection(
          title: 'Current State',
          bullets: [
            'Three branch sites',
            'Dual WAN at each site',
            'Centralized security policy',
          ],
        ),
        ArtifactSection(
          title: 'Recommended Architecture',
          bullets: [
            'Use resilient edge pairs',
            'Standardize access switching',
            'Validate PoE budgets',
          ],
        ),
      ],
      tables: [
        ArtifactTable(
          title: 'Site Sizing',
          rows: [
            ['Site', 'Users', 'WAN'],
            ['HQ', '500', 'Dual 2 Gbps'],
            ['Branch', '120', 'Dual 500 Mbps'],
          ],
        ),
      ],
      assumptions: ['Customer will validate final user counts.'],
      citations: ['Customer workshop notes.'],
    );

    final bytes = const PowerPointArtifactRenderer().render(document);
    final inspection = const PowerPointArtifactInspector().inspect(bytes);

    expect(inspection.isStructurallyValid, isTrue);
    expect(inspection.hasExpectedDeckStructure, isTrue);
    expect(inspection.title, 'Customer Architecture Proposal');
    expect(inspection.slideCount, greaterThanOrEqualTo(10));
    expect(
      inspection.slideTypes,
      containsAll([
        'Title',
        'Agenda',
        'Decision',
        'Takeaways',
        'Section',
        'Roadmap',
        'Table',
        'Appendix',
        'Sources',
      ]),
    );
    expect(inspection.hasExecutiveRecommendation, isTrue);
    expect(inspection.hasAssumptionsSourcesSlide, isTrue);
    expect(inspection.hasAppendix, isTrue);
    expect(inspection.hasSlideNumbers, isTrue);
    expect(inspection.usesDarkTheme, isTrue);
  });

  test('PowerPoint inspector tracks declared slide count metadata', () {
    const document = ArtifactDocument(
      title: 'Brief Deck',
      summary: 'Short deck with a table and source note.',
      sections: [
        ArtifactSection(
          title: 'Recommendation',
          bullets: ['Proceed with the validated design.'],
        ),
      ],
      tables: [
        ArtifactTable(
          title: 'Decision Inputs',
          rows: [
            ['Input', 'Value'],
            ['Users', '500'],
          ],
        ),
      ],
      citations: ['Workshop notes.'],
    );

    const renderer = PowerPointArtifactRenderer();
    final bytes = renderer.render(document);
    final inspection = const PowerPointArtifactInspector().inspect(bytes);

    expect(inspection.isStructurallyValid, isTrue);
    expect(inspection.declaredSlideCount, renderer.slideCountFor(document));
    expect(inspection.slideCount, inspection.declaredSlideCount);
    expect(inspection.hasEnterpriseStyling, isTrue);
    expect(inspection.hasCircuitFooter, isTrue);
    expect(inspection.hasExecutiveRecommendation, isTrue);
    expect(inspection.hasKeyTakeaways, isTrue);
    expect(inspection.hasImplementationRoadmap, isTrue);
    expect(inspection.hasAssumptionsSourcesSlide, isTrue);
    expect(inspection.hasAppendix, isTrue);
    expect(inspection.hasSlideNumbers, isTrue);
  });

  test('PowerPoint renderer supports customer-facing light theme metadata', () {
    const document = ArtifactDocument(
      title: 'Light Theme Customer Deck',
      summary: 'Customer-facing deck with light theme styling.',
      sections: [
        ArtifactSection(
          title: 'Recommendation',
          bullets: ['Use the recommended design after source validation.'],
        ),
      ],
      metadata: {'prompt': 'create a light theme PowerPoint deck'},
    );

    final bytes = const PowerPointArtifactRenderer().render(document);
    final inspection = const PowerPointArtifactInspector().inspect(bytes);

    expect(inspection.isStructurallyValid, isTrue);
    expect(inspection.hasExpectedDeckStructure, isFalse);
    expect(inspection.usesLightTheme, isTrue);
    expect(inspection.hasExecutiveRecommendation, isTrue);
    expect(inspection.hasAssumptionsSourcesSlide, isTrue);
  });
}
