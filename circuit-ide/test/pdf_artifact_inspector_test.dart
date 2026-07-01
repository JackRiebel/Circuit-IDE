import 'dart:convert';

import 'package:circuit_ide/models/artifact_document.dart';
import 'package:circuit_ide/services/pdf_artifact_inspector.dart';
import 'package:circuit_ide/services/pdf_artifact_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF inspector verifies report chrome metadata and table layout', () {
    const document = ArtifactDocument(
      title: 'Campus Refresh Handoff (Draft)',
      summary: 'Executive handoff for the campus refresh.',
      sections: [
        ArtifactSection(
          title: 'Findings',
          body: 'Access switching needs multigig and PoE validation.',
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

    final bytes = const PdfArtifactRenderer().render(document);
    final inspection = const PdfArtifactInspector().inspect(bytes);
    final text = latin1.decode(bytes, allowInvalid: true);

    expect(inspection.isStructurallyValid, isTrue);
    expect(inspection.hasExpectedReportChrome, isTrue);
    expect(inspection.hasTableGrid, isTrue);
    expect(inspection.hasOutlineCatalog, isTrue);
    expect(inspection.hasOutlineTree, isTrue);
    expect(inspection.hasReportOverviewBookmark, isTrue);
    expect(inspection.hasLeadDecisionBookmark, isTrue);
    expect(inspection.hasExecutiveDecisionBookmark, isTrue);
    expect(inspection.hasValidationBookmark, isTrue);
    expect(inspection.hasLeadDecisionCallout, isTrue);
    expect(inspection.hasExecutiveDecisionBrief, isTrue);
    expect(inspection.hasRecommendationSummary, isTrue);
    expect(inspection.hasRiskRegister, isTrue);
    expect(inspection.hasNextStepActionPlan, isTrue);
    expect(inspection.hasStakeholderReadout, isTrue);
    expect(inspection.hasEvidenceConfidenceMatrix, isTrue);
    expect(inspection.hasApprovalGates, isTrue);
    expect(inspection.hasValidationChecklist, isTrue);
    expect(inspection.hasCustomerHandoffScorecard, isTrue);
    expect(inspection.hasDecisionLog, isTrue);
    expect(inspection.hasDecisionSignOff, isTrue);
    expect(inspection.hasExplicitTableGeometry, isTrue);
    expect(inspection.hasInfoKeywords, isTrue);
    expect(inspection.pageCount, greaterThanOrEqualTo(1));
    expect(inspection.objectCount, greaterThanOrEqualTo(8));
    expect(inspection.title, 'Campus Refresh Handoff (Draft)');
    expect(text, contains('Report Overview'));
    expect(text, contains('/PageMode /UseOutlines'));
    expect(text, contains('/Type /Outlines'));
    expect(text, contains('/Title (Report Overview)'));
    expect(text, contains('/Title (Lead Decision Callout)'));
    expect(text, contains('/Title (Executive Decision Brief)'));
    expect(text, contains('/Title (Validation Checklist)'));
    expect(text, contains('/Title (Decision Sign-Off)'));
    expect(text, contains('Lead Decision Callout'));
    expect(text, contains('Decision ask'));
    expect(text, contains('Handoff status'));
    expect(text, contains('Review path'));
    expect(text, contains('Executive Decision Brief'));
    expect(text, contains('Recommendation Summary'));
    expect(text, contains('Risk & Assumption Register'));
    expect(text, contains('Next-Step Action Plan'));
    expect(text, contains('Stakeholder Readout'));
    expect(text, contains('Evidence Confidence Matrix'));
    expect(text, contains('Approval Gates'));
    expect(text, contains('Document Map'));
    expect(text, contains('Validation Checklist'));
    expect(text, contains('Customer Handoff Scorecard'));
    expect(text, contains('Decision Log'));
    expect(text, contains('Decision Sign-Off'));
    expect(text, contains('Signature / Date'));
    expect(text, contains('Handoff approval'));
    expect(text, contains('Sizing Inputs'));
    expect(text, contains('Page 1 of ${inspection.pageCount}'));

    final metadata = const PdfArtifactRenderer().metadataFor(document);
    expect(metadata['artifact'], 'pdf_report');
    expect(metadata['reportType'], 'Architecture report');
    expect(metadata['audience'], 'Architecture reviewers');
    expect(
      metadata['reportPurpose'],
      'Review findings, risks, and recommendations',
    );
    expect(metadata['handoffStatus'], 'Ready for stakeholder review');
    expect(metadata['decisionOwner'], 'Architecture owner / customer sponsor');
    expect(
      metadata['decisionAsk'],
      'Review findings, confirm assumptions, and approve the recommended architecture path.',
    );
    expect(
      metadata['reviewPath'],
      'Architecture review -> risk validation -> implementation decision',
    );
    expect(metadata['documentQuality'], 'Enterprise PDF handoff report');
    expect(metadata['designPreset'], 'customer_handoff_report');
    expect(
      metadata['layoutSystem'],
      'US Letter, 0.75 inch content frame, Helvetica type scale',
    );
    expect(
      metadata['formFactors'],
      containsAll([
        'Lead decision callout',
        'PDF bookmark outline',
        'Executive decision brief',
        'Recommendation summary',
        'Risk register',
        'Next-step action plan',
        'Evidence confidence matrix',
        'Approval gates',
        'Validation checklist',
        'Customer handoff scorecard',
        'Decision log',
        'Decision sign-off page',
        'Data tables',
        'Assumptions appendix',
        'Sources appendix',
      ]),
    );
    expect(
      metadata['documentParts'],
      containsAll([
        'Executive decision brief',
        'Lead decision callout',
        'Recommendation summary',
        'Risk register',
        'Next-step action plan',
        'Document map',
        'Evidence confidence matrix',
        'Approval gates',
        'Validation checklist',
        'Customer handoff scorecard',
        'Decision log',
        'Decision sign-off',
        'Data tables',
        'Assumptions appendix',
        'Sources appendix',
      ]),
    );
    expect(metadata['documentPartCount'], greaterThanOrEqualTo(11));
    expect(metadata['handoffScore'], 100);
    expect(metadata['handoffReadinessLevel'], 'Customer handoff ready');
    expect(metadata['handoffScorecardItemCount'], 5);
    expect(metadata['decisionLogCount'], 4);
    expect(metadata['decisionSignOffGateCount'], 4);
    expect(metadata['tableCoverage'], '1 table packaged');
    expect(metadata['evidenceCoverage'], '1 source item captured');
    expect(
      metadata['appendixCoverage'],
      '1 assumption, 1 source item in appendices',
    );
    expect(metadata['validationGaps'], isEmpty);
    expect(metadata['validationGapCount'], 0);
    expect(metadata['pageCount'], inspection.pageCount);
    expect(metadata['bookmarkCount'], greaterThanOrEqualTo(3));
    expect(metadata['sectionCount'], 2);
    expect(metadata['reportSectionCount'], greaterThanOrEqualTo(12));
    expect(metadata['tableCount'], 1);
    expect(metadata['assumptionCount'], 1);
    expect(metadata['citationCount'], 1);
    expect(metadata['riskItemCount'], greaterThanOrEqualTo(2));
    expect(metadata['nextStepCount'], greaterThanOrEqualTo(2));
    expect(metadata['evidenceItemCount'], greaterThanOrEqualTo(5));
    expect(metadata['evidenceGapCount'], 0);
    expect(
      metadata['readinessSignals'],
      containsAll([
        'Decision brief',
        'Recommendation summary',
        'Risk register',
        'Next steps',
        'Validation checklist',
        'Customer handoff scorecard',
        'Decision log',
        'Decision sign-off',
        'Data tables',
        'Assumptions',
        'Sources',
      ]),
    );
    expect(metadata['hasOutline'], isTrue);
    expect(metadata['hasLeadDecisionCallout'], isTrue);
    expect(metadata['hasExecutiveDecisionBrief'], isTrue);
    expect(metadata['hasRiskRegister'], isTrue);
    expect(metadata['hasDocumentMap'], isTrue);
    expect(metadata['hasEvidenceConfidenceMatrix'], isTrue);
    expect(metadata['hasApprovalGates'], isTrue);
    expect(metadata['hasValidationChecklist'], isTrue);
    expect(metadata['hasCustomerHandoffScorecard'], isTrue);
    expect(metadata['hasDecisionLog'], isTrue);
    expect(metadata['hasDecisionSignOffPage'], isTrue);
    expect(metadata['hasFooterPageNumbers'], isTrue);
    expect(metadata['hasExplicitTableGeometry'], isTrue);
    expect(metadata['hasAssumptionsAppendix'], isTrue);
    expect(metadata['hasSourcesAppendix'], isTrue);
    expect(metadata['hasCustomerReadyPackage'], isTrue);
    expect(metadata['hasCustomerReadyPdf'], isTrue);
  });

  test('PDF inspector catches multi-page customer handoff reports', () {
    final sections = [
      for (var i = 1; i <= 32; i++)
        ArtifactSection(
          title: 'Workstream $i',
          body:
              'This workstream captures implementation detail, risk, validation criteria, and customer-facing notes for the generated handoff report.',
          bullets: [
            'Confirm owner and date for workstream $i.',
            'Record validation result for workstream $i.',
          ],
        ),
    ];
    final document = ArtifactDocument(
      title: 'Large Customer Handoff Report',
      summary: 'A long report that should paginate into multiple PDF pages.',
      sections: sections,
      tables: const [
        ArtifactTable(
          title: 'Validation Matrix',
          rows: [
            ['Check', 'Owner', 'Status'],
            ['Connectivity', 'Network', 'Ready'],
            ['Power', 'Facilities', 'Review'],
            ['Lifecycle', 'Architecture', 'Review'],
          ],
        ),
      ],
      assumptions: const ['Long reports should preserve footer page numbers.'],
      citations: const ['CircuitCode generated validation evidence.'],
    );

    final bytes = const PdfArtifactRenderer().render(document);
    final inspection = const PdfArtifactInspector().inspect(bytes);
    final text = latin1.decode(bytes, allowInvalid: true);

    expect(inspection.isStructurallyValid, isTrue);
    expect(inspection.hasExpectedReportChrome, isTrue);
    expect(inspection.hasOutlineCatalog, isTrue);
    expect(inspection.hasOutlineTree, isTrue);
    expect(inspection.hasReportOverviewBookmark, isTrue);
    expect(inspection.hasLeadDecisionBookmark, isTrue);
    expect(inspection.hasExecutiveDecisionBookmark, isTrue);
    expect(inspection.hasValidationBookmark, isTrue);
    expect(inspection.hasLeadDecisionCallout, isTrue);
    expect(inspection.hasExecutiveDecisionBrief, isTrue);
    expect(inspection.hasRecommendationSummary, isTrue);
    expect(inspection.hasRiskRegister, isTrue);
    expect(inspection.hasNextStepActionPlan, isTrue);
    expect(inspection.hasStakeholderReadout, isTrue);
    expect(inspection.hasEvidenceConfidenceMatrix, isTrue);
    expect(inspection.hasApprovalGates, isTrue);
    expect(inspection.hasValidationChecklist, isTrue);
    expect(inspection.hasCustomerHandoffScorecard, isTrue);
    expect(inspection.hasDecisionLog, isTrue);
    expect(inspection.hasDecisionSignOff, isTrue);
    expect(inspection.hasExplicitTableGeometry, isTrue);
    expect(inspection.pageCount, greaterThan(1));
    expect(text, contains('Page 1 of ${inspection.pageCount}'));
    expect(
      text,
      contains('Page ${inspection.pageCount} of ${inspection.pageCount}'),
    );
    expect(text, contains('Large Customer Handoff Report'));
    expect(text, contains('Decision Sign-Off'));
  });
}
