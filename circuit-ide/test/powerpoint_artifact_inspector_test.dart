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
    expect(inspection.hasAgendaLayout, isTrue);
    expect(inspection.hasRecommendationCards, isTrue);
    expect(inspection.hasRoadmapTimeline, isTrue);
    expect(inspection.hasAssumptionsSourcesSlide, isTrue);
    expect(inspection.hasAppendix, isTrue);
    expect(inspection.hasSlideNumbers, isTrue);
    expect(inspection.hasSpeakerNotes, isTrue);
    expect(inspection.notesSlideCount, inspection.slideCount);
    expect(inspection.usesDarkTheme, isTrue);

    final metadata = const PowerPointArtifactRenderer().metadataFor(document);
    expect(metadata['slideCount'], inspection.slideCount);
    expect(metadata['deckType'], 'Customer proposal deck');
    expect(metadata['handoffStatus'], 'Ready for stakeholder review');
    expect(
      metadata['decisionAsk'],
      'Review the recommendation, confirm assumptions, and approve the next implementation step.',
    );
    expect(metadata['theme'], 'Dark');
    expect(metadata['audience'], 'Customer stakeholders');
    expect(metadata['deckPurpose'], 'Support a decision');
    expect(
      metadata['narrativeArc'],
      'Context -> evidence -> implication -> next step',
    );
    expect(
      metadata['communicationJob'],
      contains('Customer stakeholders should support a decision because'),
    );
    expect(metadata['tableCount'], 1);
    expect(metadata['tableCoverage'], '1 table packaged');
    expect(metadata['sourceCoverage'], '1 source item captured');
    expect(metadata['agendaItems'], contains('Current State'));
    expect(
      metadata['slideFamilies'],
      containsAll([
        'Opening',
        'Agenda',
        'Decision snapshot',
        'Recommendations',
        'Roadmap',
        'Data tables',
        'Assumptions/sources',
        'Appendix',
      ]),
    );
    expect(metadata['validationGapCount'], 0);
    expect(metadata['tableSlideCount'], 1);
    expect(metadata['sectionDividerCount'], 2);
    expect(metadata['recommendationSlideCount'], greaterThanOrEqualTo(2));
    expect(metadata['assumptionCount'], 1);
    expect(metadata['citationCount'], 1);
    expect(
      metadata['readinessSignals'],
      containsAll([
        'Agenda',
        'Decision snapshot',
        'Recommendation slides',
        'Roadmap',
        'Table slides',
        'Assumptions/sources',
        'Speaker notes',
      ]),
    );
    expect(metadata['readinessSignalCount'], 7);
    expect(metadata['hasAgenda'], isTrue);
    expect(metadata['hasDecisionSnapshot'], isTrue);
    expect(metadata['hasSectionDividers'], isTrue);
    expect(metadata['hasRecommendation'], isTrue);
    expect(metadata['hasRoadmap'], isTrue);
    expect(metadata['hasTableSlides'], isTrue);
    expect(metadata['hasSourcesSlide'], isTrue);
    expect(metadata['hasSpeakerNotes'], isTrue);
    expect(metadata['hasCustomerReadyStructure'], isTrue);
    expect(metadata['hasCustomerReadyDeck'], isTrue);
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
    expect(inspection.hasAgendaLayout, isTrue);
    expect(inspection.hasExecutiveRecommendation, isTrue);
    expect(inspection.hasRecommendationCards, isTrue);
    expect(inspection.hasKeyTakeaways, isTrue);
    expect(inspection.hasImplementationRoadmap, isTrue);
    expect(inspection.hasRoadmapTimeline, isTrue);
    expect(inspection.hasAssumptionsSourcesSlide, isTrue);
    expect(inspection.hasAppendix, isTrue);
    expect(inspection.hasSlideNumbers, isTrue);
    expect(inspection.hasSpeakerNotes, isTrue);
    expect(inspection.notesSlideCount, inspection.slideCount);
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
    expect(inspection.hasAgendaLayout, isTrue);
    expect(inspection.hasRecommendationCards, isTrue);
    expect(inspection.hasRoadmapTimeline, isTrue);
    expect(inspection.hasAssumptionsSourcesSlide, isTrue);
    expect(inspection.hasSpeakerNotes, isTrue);
  });
}
