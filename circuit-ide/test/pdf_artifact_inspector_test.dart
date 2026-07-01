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
    expect(inspection.hasExecutiveDecisionBookmark, isTrue);
    expect(inspection.hasValidationBookmark, isTrue);
    expect(inspection.hasExecutiveDecisionBrief, isTrue);
    expect(inspection.hasRecommendationSummary, isTrue);
    expect(inspection.hasRiskRegister, isTrue);
    expect(inspection.hasNextStepActionPlan, isTrue);
    expect(inspection.hasStakeholderReadout, isTrue);
    expect(inspection.hasEvidenceConfidenceMatrix, isTrue);
    expect(inspection.hasApprovalGates, isTrue);
    expect(inspection.hasValidationChecklist, isTrue);
    expect(inspection.hasInfoKeywords, isTrue);
    expect(inspection.pageCount, greaterThanOrEqualTo(1));
    expect(inspection.objectCount, greaterThanOrEqualTo(8));
    expect(inspection.title, 'Campus Refresh Handoff (Draft)');
    expect(text, contains('Report Overview'));
    expect(text, contains('/PageMode /UseOutlines'));
    expect(text, contains('/Type /Outlines'));
    expect(text, contains('/Title (Report Overview)'));
    expect(text, contains('/Title (Executive Decision Brief)'));
    expect(text, contains('/Title (Validation Checklist)'));
    expect(text, contains('Executive Decision Brief'));
    expect(text, contains('Recommendation Summary'));
    expect(text, contains('Risk & Assumption Register'));
    expect(text, contains('Next-Step Action Plan'));
    expect(text, contains('Stakeholder Readout'));
    expect(text, contains('Evidence Confidence Matrix'));
    expect(text, contains('Approval Gates'));
    expect(text, contains('Document Map'));
    expect(text, contains('Validation Checklist'));
    expect(text, contains('Sizing Inputs'));
    expect(text, contains('Page 1 of ${inspection.pageCount}'));

    final metadata = const PdfArtifactRenderer().metadataFor(document);
    expect(metadata['artifact'], 'pdf_report');
    expect(metadata['pageCount'], inspection.pageCount);
    expect(metadata['bookmarkCount'], greaterThanOrEqualTo(3));
    expect(metadata['sectionCount'], 2);
    expect(metadata['tableCount'], 1);
    expect(metadata['assumptionCount'], 1);
    expect(metadata['citationCount'], 1);
    expect(metadata['hasOutline'], isTrue);
    expect(metadata['hasExecutiveDecisionBrief'], isTrue);
    expect(metadata['hasRiskRegister'], isTrue);
    expect(metadata['hasValidationChecklist'], isTrue);
    expect(metadata['hasAssumptionsAppendix'], isTrue);
    expect(metadata['hasSourcesAppendix'], isTrue);
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
    expect(inspection.hasExecutiveDecisionBookmark, isTrue);
    expect(inspection.hasValidationBookmark, isTrue);
    expect(inspection.hasExecutiveDecisionBrief, isTrue);
    expect(inspection.hasRecommendationSummary, isTrue);
    expect(inspection.hasRiskRegister, isTrue);
    expect(inspection.hasNextStepActionPlan, isTrue);
    expect(inspection.hasStakeholderReadout, isTrue);
    expect(inspection.hasEvidenceConfidenceMatrix, isTrue);
    expect(inspection.hasApprovalGates, isTrue);
    expect(inspection.hasValidationChecklist, isTrue);
    expect(inspection.pageCount, greaterThan(1));
    expect(text, contains('Page 1 of ${inspection.pageCount}'));
    expect(
      text,
      contains('Page ${inspection.pageCount} of ${inspection.pageCount}'),
    );
    expect(text, contains('Large Customer Handoff Report'));
  });
}
