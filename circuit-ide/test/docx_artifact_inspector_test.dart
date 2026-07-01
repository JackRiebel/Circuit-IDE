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
    final packageText = String.fromCharCodes(bytes);

    expect(inspection.isStructurallyValid, isTrue);
    expect(inspection.hasExpectedReportStructure, isTrue);
    expect(inspection.title, 'Campus Architecture Review');
    expect(inspection.tableCount, greaterThanOrEqualTo(3));
    expect(inspection.bulletCount, greaterThanOrEqualTo(5));
    expect(inspection.headingCount, greaterThanOrEqualTo(6));
    expect(inspection.declaredWordCount, greaterThan(20));
    expect(inspection.declaredParagraphCount, greaterThan(10));
    expect(inspection.hasLeadDecisionCallout, isTrue);
    expect(inspection.hasExecutiveDecisionBrief, isTrue);
    expect(inspection.hasTableOfContents, isTrue);
    expect(inspection.hasRecommendationSummary, isTrue);
    expect(inspection.hasRiskRegister, isTrue);
    expect(inspection.hasNextStepActionPlan, isTrue);
    expect(inspection.hasValidationChecklist, isTrue);
    expect(inspection.hasCustomerHandoffScorecard, isTrue);
    expect(inspection.hasDecisionLog, isTrue);
    expect(inspection.hasDecisionSignOff, isTrue);
    expect(inspection.hasAssumptionsAppendix, isTrue);
    expect(inspection.hasSourcesAppendix, isTrue);
    expect(inspection.hasCircuitHeader, isTrue);
    expect(inspection.hasExplicitTableGeometry, isTrue);
    expect(inspection.hasRepeatingTableHeaders, isTrue);
    expect(inspection.hasKeywordsMetadata, isTrue);
    expect(inspection.hasCustomProperties, isTrue);
    expect(inspection.hasReportQualityManifest, isTrue);
    expect(inspection.hasAccessibilityManifest, isTrue);
    expect(inspection.hasExternalHandoffManifest, isTrue);
    expect(packageText, contains('docProps/custom.xml'));
    expect(packageText, contains('CircuitReportQualityManifest'));
    expect(packageText, contains('CircuitAccessibilityPolicy'));
    expect(packageText, contains('CircuitDecisionAsk'));
    expect(packageText, contains('CircuitReviewPath'));
    expect(packageText, contains('CircuitHandoffReadiness'));
    expect(packageText, contains('CircuitExternalHandoffManifest'));
    expect(
      packageText,
      contains('Review owner: Architecture owner / customer sponsor'),
    );
    expect(
      packageText,
      contains('Publishing gate: ready for stakeholder approval'),
    );

    final metadata = const DocxArtifactRenderer().metadataFor(document);
    expect(metadata['artifact'], 'word_report');
    expect(metadata['qualityManifestVersion'], '1.0');
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
    expect(metadata['documentQuality'], 'Enterprise structured report');
    expect(metadata['designPreset'], 'standard_business_brief');
    expect(
      metadata['layoutSystem'],
      'US Letter, 1 inch margins, Aptos type scale',
    );
    expect(
      metadata['formFactors'],
      containsAll([
        'Lead decision callout',
        'Table of contents',
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
      metadata['evidenceConfidence'],
      'High - sources and assumptions captured',
    );
    expect(
      metadata['reportReviewChecklist'],
      containsAll([
        'Confirm report title, audience, decision owner, and decision ask.',
        'Review executive decision brief and recommendation summary for customer-specific language.',
        'Validate risk register, next-step action plan, and approval gates.',
        'Review data tables for stale values, sensitive data, and source alignment.',
        'Confirm assumptions with the accountable owner.',
        'Check source authority, freshness, and cited facts.',
      ]),
    );
    expect(metadata['reportReviewChecklistCount'], 6);
    expect(
      metadata['accessibilitySignals'],
      containsAll([
        'Real Word headings',
        'Real numbering for bullets',
        'Explicit table geometry',
        'Repeating table headers',
        'Header and footer package markers',
        'Source appendix included',
        'Assumption appendix included',
      ]),
    );
    expect(metadata['accessibilitySignalCount'], 7);
    expect(
      metadata['visualVerificationChecklist'],
      containsAll([
        'Open the DOCX in Word and verify headings, tables, appendices, header/footer, and sign-off sections render without clipping.',
        'Confirm table headers repeat and columns remain readable in print layout.',
        'Verify executive decision brief, recommendation summary, risk register, approval gates, and sign-off page appear in order.',
        'Confirm sources appendix is included with checked dates and source labels.',
        'Confirm assumptions appendix is explicit and owner-reviewable.',
      ]),
    );
    expect(metadata['visualVerificationChecklistCount'], 5);
    expect(metadata['hasVisualVerificationChecklist'], isTrue);
    expect(
      metadata['reportEvidencePolicy'],
      containsAll([
        'Report narrative is guidance; source appendices and source artifacts are the evidence record.',
        'Customer handoff requires checked sources, assumptions, decision owner, and approval gate.',
        'Use cited sources as the evidence register for external review.',
        'Review assumptions with the accountable owner before stakeholder handoff.',
      ]),
    );
    expect(metadata['reportEvidencePolicyCount'], 4);
    expect(metadata['hasReportEvidencePolicy'], isTrue);
    expect(
      metadata['publishingMetadata'],
      containsAll([
        'Report type: Architecture report',
        'Review path: Architecture review -> risk validation -> implementation decision',
        'Handoff readiness: Customer handoff ready',
        'Evidence confidence: High - sources and assumptions captured',
        'Publishing status: Ready for stakeholder review',
      ]),
    );
    expect(metadata['publishingMetadataCount'], 6);
    expect(metadata['hasExternalHandoffManifest'], isTrue);
    expect(metadata['externalHandoffManifestCount'], 9);
    expect(
      metadata['externalHandoffManifest'],
      containsAll([
        'Review owner: Architecture owner / customer sponsor',
        'Report type: Architecture report',
        'Review path: Architecture review -> risk validation -> implementation decision',
        'Handoff readiness: Customer handoff ready',
        'Evidence status: High - sources and assumptions captured',
        'Publishing gate: ready for stakeholder approval',
        'Source package: 1 source item attached',
        'Assumption package: 1 assumption captured',
      ]),
    );
    expect(
      metadata['reportHandoffActions'],
      containsAll([
        'Send report to internal reviewer with source artifacts attached.',
        'Capture owner, due date, approval gates, and follow-up actions.',
        'Keep cited sources with the handoff package.',
      ]),
    );
    expect(metadata['reportHandoffActionCount'], 4);
    expect(metadata['reportRiskFlags'], isEmpty);
    expect(
      metadata['appendixCoverage'],
      '1 assumption, 1 source item in appendices',
    );
    expect(metadata['validationGaps'], isEmpty);
    expect(metadata['validationGapCount'], 0);
    expect(metadata['sectionCount'], 2);
    expect(metadata['reportSectionCount'], greaterThanOrEqualTo(12));
    expect(metadata['tableCount'], 1);
    expect(metadata['assumptionCount'], 1);
    expect(metadata['citationCount'], 1);
    expect(metadata['wordCount'], inspection.declaredWordCount);
    expect(metadata['paragraphCount'], inspection.declaredParagraphCount);
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
    expect(metadata['hasExecutiveDecisionBrief'], isTrue);
    expect(metadata['hasLeadDecisionCallout'], isTrue);
    expect(metadata['hasTableOfContents'], isTrue);
    expect(metadata['hasRiskRegister'], isTrue);
    expect(metadata['hasDocumentMap'], isTrue);
    expect(metadata['hasEvidenceConfidenceMatrix'], isTrue);
    expect(metadata['hasApprovalGates'], isTrue);
    expect(metadata['hasValidationChecklist'], isTrue);
    expect(metadata['hasCustomerHandoffScorecard'], isTrue);
    expect(metadata['hasDecisionLog'], isTrue);
    expect(metadata['hasDecisionSignOffPage'], isTrue);
    expect(metadata['hasExplicitTableGeometry'], isTrue);
    expect(metadata['hasRepeatingTableHeaders'], isTrue);
    expect(metadata['hasReportQualityManifest'], isTrue);
    expect(metadata['hasPublishingMetadata'], isTrue);
    expect(metadata['hasAccessibilitySignals'], isTrue);
    expect(metadata['hasAssumptionsAppendix'], isTrue);
    expect(metadata['hasSourcesAppendix'], isTrue);
    expect(metadata['hasCustomerReadyPackage'], isTrue);
    expect(metadata['hasCustomerReadyReport'], isTrue);
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
    expect(inspection.hasTableOfContents, isTrue);
    expect(inspection.hasRecommendationSummary, isTrue);
    expect(inspection.hasRiskRegister, isTrue);
    expect(inspection.hasNextStepActionPlan, isTrue);
    expect(inspection.hasValidationChecklist, isTrue);
    expect(inspection.hasCustomerHandoffScorecard, isTrue);
    expect(inspection.hasDecisionLog, isTrue);
    expect(inspection.hasDecisionSignOff, isTrue);
    expect(inspection.hasCircuitHeader, isTrue);
    expect(inspection.hasCircuitFooter, isTrue);
    expect(inspection.hasEnterpriseStyles, isTrue);
    expect(inspection.hasLeadDecisionCallout, isTrue);
    expect(inspection.hasExplicitTableGeometry, isTrue);
    expect(inspection.hasRepeatingTableHeaders, isTrue);
    expect(inspection.hasKeywordsMetadata, isTrue);
    expect(inspection.hasCustomProperties, isTrue);
    expect(inspection.hasReportQualityManifest, isTrue);
    expect(inspection.hasAccessibilityManifest, isTrue);
    expect(inspection.hasExternalHandoffManifest, isTrue);

    final metadata = const DocxArtifactRenderer().metadataFor(document);
    expect(metadata['reportType'], 'Implementation plan');
    expect(
      metadata['handoffStatus'],
      'Draft - validate assumptions and evidence',
    );
    expect(metadata['evidenceGapCount'], 2);
    expect(metadata['handoffScore'], 50);
    expect(metadata['handoffReadinessLevel'], 'Needs evidence before handoff');
    expect(metadata['readinessSignals'], contains('Evidence gaps'));
    expect(
      metadata['evidenceConfidence'],
      'Low - sources and assumptions need validation',
    );
    expect(
      metadata['reportReviewChecklist'],
      containsAll([
        'Capture assumptions before customer handoff.',
        'Attach sources or mark the report as an unsourced draft.',
        'Resolve 2 validation gaps before stakeholder handoff.',
      ]),
    );
    expect(
      metadata['reportHandoffActions'],
      contains('Add cited evidence before external handoff.'),
    );
    expect(
      metadata['reportRiskFlags'],
      containsAll([
        'No cited sources attached',
        'No assumptions captured',
        'No supporting data tables',
      ]),
    );
    expect(metadata['hasCustomerReadyPackage'], isFalse);
    expect(metadata['hasCustomerReadyReport'], isFalse);
    expect(
      metadata['validationGaps'],
      containsAll(['Assumptions need confirmation', 'Sources need validation']),
    );
    expect(metadata['validationGapCount'], 2);
    expect(metadata['appendixCoverage'], 'No appendices attached');
    expect(metadata['hasLeadDecisionCallout'], isTrue);
    expect(metadata['hasExplicitTableGeometry'], isTrue);
    expect(metadata['hasRepeatingTableHeaders'], isTrue);
    expect(metadata['hasReportQualityManifest'], isTrue);
    expect(metadata['hasPublishingMetadata'], isTrue);
    expect(metadata['hasAccessibilitySignals'], isTrue);
    expect(metadata['hasExternalHandoffManifest'], isTrue);
    expect(
      metadata['externalHandoffManifest'],
      containsAll([
        'Review owner: Implementation owner',
        'Report type: Implementation plan',
        'Handoff readiness: Needs evidence before handoff',
        'Evidence status: Low - sources and assumptions need validation',
        'Publishing gate: resolve 2 validation gaps',
        'Source package: sources missing',
        'Assumption package: assumptions missing',
      ]),
    );
    expect(
      metadata['formFactors'],
      containsAll([
        'Lead decision callout',
        'Table of contents',
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
      ]),
    );
  });

  test('DOCX report records evidence gaps and next-step actions', () {
    const document = ArtifactDocument(
      title: 'Business Use Case Brief',
      summary: 'Business brief for customer automation opportunities.',
      sections: [
        ArtifactSection(
          title: 'Recommended Use Cases',
          bullets: [
            'Recommend prioritizing lifecycle automation first.',
            'Validate data quality before customer handoff.',
          ],
        ),
        ArtifactSection(
          title: 'Risks',
          bullets: [
            'Risk: Source data may be incomplete.',
            'Next action: confirm executive sponsor and success metrics.',
          ],
        ),
      ],
    );

    final bytes = const DocxArtifactRenderer().render(document);
    final inspection = const DocxArtifactInspector().inspect(bytes);
    final packageText = String.fromCharCodes(bytes);

    expect(inspection.isStructurallyValid, isTrue);
    expect(inspection.hasExpectedReportStructure, isTrue);
    expect(inspection.hasTableOfContents, isTrue);
    expect(inspection.hasRiskRegister, isTrue);
    expect(inspection.hasNextStepActionPlan, isTrue);
    expect(inspection.hasCustomProperties, isTrue);
    expect(inspection.hasReportQualityManifest, isTrue);
    expect(inspection.hasAccessibilityManifest, isTrue);
    expect(packageText, contains('No cited evidence included'));
    expect(packageText, contains('Evidence gap'));
    expect(packageText, contains('Decision owner'));
    expect(packageText, contains('Decision ask'));
    expect(packageText, contains('Review path'));
    expect(packageText, contains('Next-Step Action Plan'));
    expect(packageText, contains('Customer Handoff Scorecard'));
    expect(packageText, contains('Decision Log'));
    expect(packageText, contains('Decision Sign-Off'));
    expect(packageText, contains('Signature / Date'));
    expect(packageText, contains('Handoff approval'));
    expect(packageText, contains('Needs sources'));
    expect(packageText, contains('No cited evidence included'));
    expect(packageText, contains('CircuitCode report package'));
    expect(packageText, contains('Table of Contents'));
    expect(packageText, contains('CalloutLabel'));
    expect(packageText, contains('<w:tblHeader/>'));
    expect(packageText, contains('CircuitReportQualityManifest'));
    expect(packageText, contains('CircuitAccessibilityPolicy'));
  });
}
