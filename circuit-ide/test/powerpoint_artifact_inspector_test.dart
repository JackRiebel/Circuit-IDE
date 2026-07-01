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
        'Readout',
        'Delivery Brief',
        'Decision',
        'Decision Matrix',
        'Stakeholders',
        'Takeaways',
        'Section',
        'Roadmap',
        'Close',
        'Table',
        'Appendix',
        'Sources',
      ]),
    );
    expect(inspection.hasExecutiveRecommendation, isTrue);
    expect(inspection.hasDecisionMatrix, isTrue);
    expect(inspection.hasAgendaLayout, isTrue);
    expect(inspection.hasDeliveryBrief, isTrue);
    expect(inspection.hasRecommendationCards, isTrue);
    expect(inspection.hasEnterpriseBrandPill, isTrue);
    expect(inspection.hasSectionDividerLayout, isTrue);
    expect(inspection.hasRoadmapTimeline, isTrue);
    expect(inspection.hasClosingDecisionAsk, isTrue);
    expect(inspection.hasAssumptionsSourcesSlide, isTrue);
    expect(inspection.hasAppendix, isTrue);
    expect(inspection.hasSlideNumbers, isTrue);
    expect(inspection.hasSpeakerNotes, isTrue);
    expect(inspection.hasCustomProperties, isTrue);
    expect(inspection.hasNarrativeManifest, isTrue);
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
    expect(metadata['presentationQuality'], 'Enterprise structured deck');
    expect(metadata['visualSystem'], 'Dark enterprise presentation system');
    expect(metadata['audience'], 'Customer stakeholders');
    expect(metadata['deckPurpose'], 'Support a decision');
    expect(metadata['deliveryReadinessScore'], greaterThanOrEqualTo(90));
    expect(metadata['deliveryReadinessLevel'], 'Customer handoff ready');
    expect(
      metadata['deckReviewPriority'],
      'Low - ready for stakeholder review',
    );
    expect(
      metadata['deliveryReadinessDrivers'],
      containsAll([
        'Executive delivery brief included',
        'Decision matrix included',
        'Stakeholder ownership lanes included',
        '1 supporting table included',
        '1 assumption captured',
        '1 source item captured',
      ]),
    );
    expect(
      metadata['audienceHandoffNotes'],
      contains(contains('Audience: Customer stakeholders.')),
    );
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
    expect(
      metadata['evidenceConfidence'],
      'High - sources and assumptions captured',
    );
    expect(metadata['deckReviewChecklistCount'], 7);
    expect(
      metadata['deckReviewChecklist'],
      containsAll([
        'Confirm deck title, audience, and decision ask match the customer conversation.',
        'Review readout framing for account-specific phrasing.',
        'Validate decision matrix signals, risk posture, and next actions.',
        'Review table slides for sensitive data, stale values, and column readability.',
        'Confirm assumptions with the accountable owner.',
        'Check sources and dates before sharing externally.',
      ]),
    );
    expect(metadata['deckHandoffActionCount'], 4);
    expect(
      metadata['deckHandoffActions'],
      containsAll([
        'Send deck to internal reviewer with the source artifact attached.',
        'Capture stakeholder owner, due date, and approval status.',
        'Keep cited sources with the handoff package.',
      ]),
    );
    expect(metadata['presentationRiskFlags'], isEmpty);
    expect(metadata['agendaItems'], contains('Current State'));
    expect(
      metadata['slideFamilies'],
      containsAll([
        'Opening',
        'Agenda',
        'Readout framing',
        'Executive delivery brief',
        'Decision snapshot',
        'Decision matrix',
        'Stakeholder alignment',
        'Recommendations',
        'Roadmap',
        'Data tables',
        'Assumptions/sources',
        'Appendix',
      ]),
    );
    expect(
      metadata['slidePreview'],
      containsAll([
        contains('1. Title: Customer Architecture Proposal'),
        contains('2. Agenda: Decision Flow'),
        contains('Decision Snapshot'),
      ]),
    );
    expect(metadata['slidePreviewCount'], greaterThanOrEqualTo(10));
    expect(metadata['validationGapCount'], 0);
    expect(metadata['tableSlideCount'], 1);
    expect(metadata['sectionDividerCount'], 2);
    expect(
      metadata['layoutFeatures'],
      containsAll([
        'Branded title slide',
        'Numbered agenda',
        'Audience-facing readout framing',
        'Executive delivery brief',
        'Section divider slides',
        'Decision matrix',
        'Stakeholder alignment lanes',
        'Recommendation cards',
        'Roadmap timeline',
        'Closing decision ask',
        'Speaker notes',
      ]),
    );
    expect(metadata['decisionMatrixSlideCount'], 1);
    expect(metadata['stakeholderAlignmentSlideCount'], 1);
    expect(metadata['closingDecisionSlideCount'], 1);
    expect(metadata['recommendationSlideCount'], greaterThanOrEqualTo(2));
    expect(metadata['assumptionCount'], 1);
    expect(metadata['citationCount'], 1);
    expect(
      metadata['readinessSignals'],
      containsAll([
        'Agenda',
        'Readout framing',
        'Delivery brief',
        'Decision snapshot',
        'Decision matrix',
        'Stakeholder alignment',
        'Recommendation slides',
        'Roadmap',
        'Closing ask',
        'Table slides',
        'Assumptions/sources',
        'Speaker notes',
      ]),
    );
    expect(metadata['readinessSignalCount'], 12);
    expect(metadata['hasAgenda'], isTrue);
    expect(metadata['hasPresenterTalkTrack'], isTrue);
    expect(metadata['presenterTalkTrackSlideCount'], 1);
    expect(metadata['hasDeliveryBrief'], isTrue);
    expect(metadata['deliveryBriefSlideCount'], 1);
    expect(metadata['presenterBrief'], isA<String>());
    expect(metadata['hasDecisionSnapshot'], isTrue);
    expect(metadata['hasDecisionMatrix'], isTrue);
    expect(metadata['hasStakeholderAlignment'], isTrue);
    expect(metadata['hasSectionDividers'], isTrue);
    expect(metadata['hasSectionDividerLayout'], isTrue);
    expect(metadata['hasEnterpriseBrandPill'], isTrue);
    expect(metadata['hasRecommendation'], isTrue);
    expect(metadata['hasClosingDecisionAsk'], isTrue);
    expect(metadata['hasRoadmap'], isTrue);
    expect(metadata['hasTableSlides'], isTrue);
    expect(metadata['hasSourcesSlide'], isTrue);
    expect(metadata['hasDataSnapshot'], isTrue);
    expect(metadata['hasAppendixHandoff'], isTrue);
    expect(metadata['hasSpeakerNotes'], isTrue);
    expect(metadata['speakerNoteCount'], inspection.slideCount);
    expect(metadata['hasNarrativeManifest'], isTrue);
    expect(metadata['hasCustomerFacingVisibleSlides'], isTrue);
    expect(
      metadata['presenterGuidanceLocation'],
      'Speaker notes and readout framing metadata',
    );
    expect(metadata['hasCustomerReadyStructure'], isTrue);
    expect(metadata['hasCustomerReadyDeck'], isTrue);
  });

  test('PowerPoint metadata flags deck handoff gaps', () {
    const document = ArtifactDocument(
      title: 'Draft Customer Deck',
      summary: 'Draft deck with no supporting evidence yet.',
      sections: [
        ArtifactSection(
          title: 'Recommendation',
          bullets: ['Proceed after stakeholders validate scope.'],
        ),
      ],
    );

    final metadata = const PowerPointArtifactRenderer().metadataFor(document);

    expect(
      metadata['evidenceConfidence'],
      'Low - sources and assumptions need validation',
    );
    expect(
      metadata['deckReviewChecklist'],
      containsAll([
        'Attach supporting data or explain why no data table is required.',
        'Capture assumptions before treating the deck as final.',
        'Attach sources or mark the deck as unsourced draft.',
      ]),
    );
    expect(
      metadata['deckHandoffActions'],
      contains('Add cited evidence before external handoff.'),
    );
    expect(
      metadata['presentationRiskFlags'],
      containsAll([
        'No cited sources attached',
        'No assumptions captured',
        'No supporting data tables',
      ]),
    );
    expect(metadata['deliveryReadinessScore'], lessThan(90));
    expect(metadata['deliveryReadinessLevel'], isNot('Customer handoff ready'));
    expect(
      metadata['deckReviewPriority'],
      isNot('Low - ready for stakeholder review'),
    );
    expect(metadata['hasCustomerReadyDeck'], isFalse);
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
    expect(inspection.hasDeliveryBrief, isTrue);
    expect(inspection.hasExecutiveRecommendation, isTrue);
    expect(inspection.hasDecisionMatrix, isTrue);
    expect(inspection.hasRecommendationCards, isTrue);
    expect(inspection.hasEnterpriseBrandPill, isTrue);
    expect(inspection.hasKeyTakeaways, isTrue);
    expect(inspection.hasImplementationRoadmap, isTrue);
    expect(inspection.hasRoadmapTimeline, isTrue);
    expect(inspection.hasClosingDecisionAsk, isTrue);
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
    expect(inspection.hasDeliveryBrief, isTrue);
    expect(inspection.hasDecisionMatrix, isTrue);
    expect(inspection.hasAgendaLayout, isTrue);
    expect(inspection.hasRecommendationCards, isTrue);
    expect(inspection.hasEnterpriseBrandPill, isTrue);
    expect(inspection.hasRoadmapTimeline, isTrue);
    expect(inspection.hasClosingDecisionAsk, isTrue);
    expect(inspection.hasAssumptionsSourcesSlide, isTrue);
    expect(inspection.hasSpeakerNotes, isTrue);
  });
}
