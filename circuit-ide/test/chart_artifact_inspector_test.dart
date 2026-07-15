import 'package:circuit_ide/models/artifact_document.dart';
import 'package:circuit_ide/services/chart_artifact_inspector.dart';
import 'package:circuit_ide/services/chart_artifact_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chart inspector verifies single chart SVG structure', () {
    const document = ArtifactDocument(
      title: 'PoE Budget Risk',
      summary: 'PoE budget chart for campus access switching.',
      assumptions: ['AP draw is estimated until site survey validation.'],
      tables: [
        ArtifactTable(
          title: 'PoE Budget',
          rows: [
            ['Site', 'Watts Required', 'PoE Budget'],
            ['MDF', '7200', '9600'],
            ['IDF 1', '5100', '7400'],
            ['IDF 2', '6800', '7400'],
          ],
        ),
      ],
    );

    final result = const ChartArtifactRenderer().render(document);
    final inspection = const ChartArtifactInspector().inspect(result.bytes);

    expect(inspection.isStructurallyValid, isTrue);
    expect(inspection.title, 'PoE Budget Risk');
    expect(inspection.chartCount, 1);
    expect(inspection.pointCount, 3);
    expect(inspection.containsKind('poe'), isTrue);
    expect(inspection.chartTitles, contains('PoE Budget'));
    expect(inspection.hasChartSummaryPanel, isTrue);
    expect(inspection.hasExecutiveInsights, isTrue);
    expect(inspection.hasValidationGates, isTrue);
    expect(inspection.hasRecommendedActions, isTrue);
    expect(inspection.hasDecisionMatrix, isTrue);
    expect(inspection.hasDataQualityPanel, isTrue);
    expect(inspection.hasThresholdGuidance, isTrue);
    expect(inspection.hasChartQualityManifest, isTrue);
    expect(inspection.hasChartQualityGate, isTrue);
    expect(inspection.hasChartEvidencePolicy, isTrue);
    expect(inspection.hasChartVisualVerificationChecklist, isTrue);
    expect(inspection.hasChartHandoffReadinessMatrix, isTrue);
    expect(inspection.hasPoeSignal, isTrue);
    expect(inspection.noteCount, greaterThanOrEqualTo(1));
    expect(inspection.insightCount, greaterThanOrEqualTo(3));
    expect(inspection.validationGateCount, 4);
    expect(inspection.recommendedActionCount, greaterThanOrEqualTo(1));
    expect(inspection.decisionActionCount, greaterThanOrEqualTo(1));
    expect(inspection.criticalDecisionCount, 0);
    expect(inspection.dataQualityItemCount, 4);
    expect(inspection.thresholdGuidanceCount, greaterThanOrEqualTo(2));
    expect(inspection.chartQualityChecklistCount, greaterThanOrEqualTo(8));
    expect(inspection.chartEvidencePolicyCount, greaterThanOrEqualTo(3));
    expect(
      inspection.chartVisualVerificationChecklistCount,
      greaterThanOrEqualTo(3),
    );
    expect(inspection.chartHandoffReadinessGateCount, 6);
    expect(inspection.chartHandoffReadinessReadyCount, 3);
    expect(inspection.chartQualityStatus, isNotEmpty);
    expect(inspection.sourceTableCount, 1);
    expect(inspection.citationCount, 0);
    expect(inspection.assumptionCount, 1);
    expect(inspection.hasSourceEvidence, isFalse);
    expect(inspection.hasAssumptions, isTrue);
    expect(result.metadata['artifact'], 'chart_pack');
    expect(result.metadata['chartPackType'], 'Capacity planning chart pack');
    expect(
      result.metadata['decisionPurpose'],
      'Capacity validation and sizing support',
    );
    expect(result.metadata['chartCount'], 1);
    expect(result.metadata['pointCount'], 3);
    expect(result.metadata['hasPoe'], isTrue);
    expect(result.metadata['chartFamilies'], contains('PoE Budget'));
    expect(result.metadata['readinessSignals'], contains('Source data'));
    expect(result.metadata['validationGateCount'], 4);
    expect(result.metadata['validationGapCount'], greaterThanOrEqualTo(1));
    expect(result.metadata['recommendedActionCount'], greaterThanOrEqualTo(1));
    expect(result.metadata['hasDecisionMatrix'], isTrue);
    expect(result.metadata['decisionActionCount'], greaterThanOrEqualTo(1));
    expect(result.metadata['criticalDecisionCount'], 0);
    expect(result.metadata['decisionOwners'], contains('Network architect'));
    expect(result.metadata['hasDataQualityPanel'], isTrue);
    expect(result.metadata['hasSourceProvenancePanel'], isTrue);
    expect(result.metadata['hasThresholdGuidance'], isTrue);
    expect(result.metadata['sourceTableCount'], 1);
    expect(result.metadata['citationCount'], 0);
    expect(result.metadata['assumptionCount'], 1);
    expect(result.metadata['hasChartHandoffReadinessMatrix'], isTrue);
    expect(result.metadata['chartHandoffReadinessGateCount'], 6);
    expect(result.metadata['chartHandoffReadinessReadyCount'], 3);
    final handoffMatrix =
        (result.metadata['chartHandoffReadinessMatrix'] as List).cast<Map>();
    expect(
      handoffMatrix.map((gate) => gate['gate']),
      containsAll([
        'Source evidence',
        'Assumptions',
        'Data quality',
        'Thresholds',
        'Decision ownership',
        'Publishing gate',
      ]),
    );
    final svg = String.fromCharCodes(result.bytes);
    expect(svg, contains('Customer handoff readiness'));
    expect(svg, contains('id="chart-handoff-readiness"'));
  });

  test('chart inspector verifies enterprise multi-panel chart packs', () {
    const document = ArtifactDocument(
      title: 'Enterprise Sizing Chart Pack',
      summary:
          'Enterprise charts covering PoE, WAN, lifecycle, product fit, cost, and roadmap.',
      assumptions: [
        'PoE and WAN values are planning estimates pending site validation.',
        'Lifecycle dates require official source confirmation before handoff.',
      ],
      citations: [
        'Cisco portfolio datasheet checked 2026-06-30',
        'Customer inventory export checked 2026-06-30',
      ],
      tables: [
        ArtifactTable(
          title: 'PoE Budget',
          rows: [
            ['Site', 'Watts Required', 'PoE Budget', 'Risk'],
            ['MDF', '7200', '9600', 'Medium'],
            ['IDF 1', '5100', '7400', 'Low'],
          ],
        ),
        ArtifactTable(
          title: 'WAN Capacity',
          rows: [
            ['Site', 'Mbps Required', 'WAN Mbps', 'Headroom'],
            ['HQ', '1800', '2500', '700'],
            ['Branch 1', '600', '1000', '400'],
          ],
        ),
        ArtifactTable(
          title: 'Lifecycle Risk',
          rows: [
            ['Product', 'Lifecycle Status', 'LDOS', 'Risk'],
            ['AIR-AP2802I', 'End of Support', '2026', 'High'],
            ['C9300-48P', 'Active', '2029', 'Review'],
          ],
        ),
        ArtifactTable(
          title: 'Product Comparison',
          rows: [
            ['Model', 'Fit Score', 'Uplinks', 'Recommendation'],
            ['C9300X-48HX', '5', '25G', 'Best UPOE access fit'],
            ['C9400', '3', '100G', 'Use for chassis sites'],
          ],
        ),
        ArtifactTable(
          title: 'Cost Plan',
          rows: [
            ['Option', 'TCO', 'License Cost', 'Risk'],
            ['Cloud-managed access', '240000', '48000', 'Low'],
            ['Campus refresh', '310000', '62000', 'Review'],
          ],
        ),
        ArtifactTable(
          title: 'Deployment Roadmap',
          rows: [
            ['Phase', 'Priority Score', 'Duration Weeks'],
            ['Discovery', '5', '2'],
            ['Pilot', '4', '4'],
            ['Rollout', '3', '8'],
          ],
        ),
      ],
    );

    final result = const ChartArtifactRenderer().render(document);
    final inspection = const ChartArtifactInspector().inspect(result.bytes);

    expect(inspection.isStructurallyValid, isTrue);
    expect(inspection.hasEnterpriseChartPackStructure, isTrue);
    expect(inspection.chartCount, 6);
    expect(inspection.pointCount, 13);
    expect(inspection.hasChartSummaryPanel, isTrue);
    expect(inspection.hasRiskLegend, isTrue);
    expect(inspection.hasExecutiveInsights, isTrue);
    expect(inspection.hasValidationGates, isTrue);
    expect(inspection.hasRecommendedActions, isTrue);
    expect(inspection.hasDecisionMatrix, isTrue);
    expect(inspection.hasDataQualityPanel, isTrue);
    expect(inspection.hasThresholdGuidance, isTrue);
    expect(inspection.hasChartHandoffReadinessMatrix, isTrue);
    expect(inspection.insightCount, greaterThanOrEqualTo(3));
    expect(inspection.validationGateCount, 4);
    expect(inspection.recommendedActionCount, greaterThanOrEqualTo(4));
    expect(inspection.decisionActionCount, greaterThanOrEqualTo(5));
    expect(inspection.criticalDecisionCount, greaterThanOrEqualTo(3));
    expect(inspection.dataQualityItemCount, 4);
    expect(inspection.thresholdGuidanceCount, greaterThanOrEqualTo(4));
    expect(inspection.chartHandoffReadinessGateCount, 6);
    expect(inspection.chartHandoffReadinessReadyCount, 4);
    expect(inspection.highRiskCount, greaterThanOrEqualTo(1));
    expect(inspection.mediumRiskCount, greaterThanOrEqualTo(2));
    expect(inspection.lowRiskCount, greaterThanOrEqualTo(2));
    expect(inspection.hasPoeSignal, isTrue);
    expect(inspection.hasWanSignal, isTrue);
    expect(inspection.hasLifecycleSignal, isTrue);
    expect(inspection.hasComparisonSignal, isTrue);
    expect(inspection.hasCostSignal, isTrue);
    expect(inspection.hasRoadmapSignal, isTrue);
    expect(inspection.sourceTableCount, 6);
    expect(inspection.citationCount, 2);
    expect(inspection.assumptionCount, 2);
    expect(inspection.hasSourceEvidence, isTrue);
    expect(inspection.hasAssumptions, isTrue);
    expect(
      inspection.chartKinds,
      containsAll(['poe', 'wan', 'lifecycle', 'comparison', 'cost', 'roadmap']),
    );
    expect(
      inspection.chartTitles,
      containsAll([
        'PoE Budget',
        'WAN Capacity',
        'Lifecycle Risk',
        'Product Comparison',
        'Cost Plan',
        'Deployment Roadmap',
      ]),
    );
    expect(result.metadata['chartCount'], 6);
    expect(result.metadata['pointCount'], 13);
    expect(result.metadata['chartPackType'], 'Enterprise readiness chart pack');
    expect(
      result.metadata['handoffStatus'],
      'Review required - high risk signals',
    );
    expect(
      result.metadata['decisionPurpose'],
      'Capacity and lifecycle decision support',
    );
    expect(
      result.metadata['chartReadinessLevel'],
      'Needs owner review before handoff',
    );
    expect(result.metadata['riskPosture'], 'High risk - owner review required');
    expect(result.metadata['chartReadinessScore'], lessThan(100));
    expect(result.metadata['chartQualityManifestVersion'], '1.0');
    expect(result.metadata['hasChartQualityManifest'], isTrue);
    expect(result.metadata['hasChartQualityGate'], isTrue);
    expect(result.metadata['hasChartEvidencePolicy'], isTrue);
    expect(result.metadata['hasChartVisualVerificationChecklist'], isTrue);
    expect(result.metadata['hasChartDecisionReadinessGate'], isTrue);
    expect(result.metadata['hasChartHandoffReadinessMatrix'], isTrue);
    expect(result.metadata['chartHandoffReadinessGateCount'], 6);
    expect(result.metadata['chartHandoffReadinessReadyCount'], 4);
    expect(result.metadata['chartQualityChecklistCount'], greaterThan(7));
    expect(result.metadata['chartEvidencePolicyCount'], greaterThan(2));
    expect(
      result.metadata['chartVisualVerificationChecklistCount'],
      greaterThan(2),
    );
    expect(
      result.metadata['chartEvidencePolicy'],
      contains(
        'Charts are decision support, not source evidence by themselves',
      ),
    );
    expect(result.metadata['highRiskCount'], greaterThanOrEqualTo(1));
    expect(result.metadata['mediumRiskCount'], greaterThanOrEqualTo(2));
    expect(result.metadata['lowRiskCount'], greaterThanOrEqualTo(2));
    expect(result.metadata['hasPoe'], isTrue);
    expect(result.metadata['hasWan'], isTrue);
    expect(result.metadata['hasLifecycle'], isTrue);
    expect(result.metadata['hasComparison'], isTrue);
    expect(result.metadata['hasCost'], isTrue);
    expect(result.metadata['hasRoadmap'], isTrue);
    expect(result.metadata['hasDataQualityPanel'], isTrue);
    expect(result.metadata['hasDecisionMatrix'], isTrue);
    expect(result.metadata['hasSourceProvenancePanel'], isTrue);
    expect(result.metadata['hasThresholdGuidance'], isTrue);
    expect(result.metadata['sourceTableCount'], 6);
    expect(result.metadata['citationCount'], 2);
    expect(result.metadata['assumptionCount'], 2);
    expect(result.metadata['dataQualityItemCount'], 4);
    expect(result.metadata['decisionActionCount'], greaterThanOrEqualTo(5));
    expect(result.metadata['criticalDecisionCount'], greaterThanOrEqualTo(3));
    expect(result.metadata['decisionQuestionCount'], greaterThanOrEqualTo(4));
    expect(result.metadata['handoffChecklistCount'], greaterThanOrEqualTo(5));
    expect(result.metadata['reviewerNextStepCount'], greaterThanOrEqualTo(4));
    expect(
      result.metadata['decisionQuestions'],
      anyElement(contains('PoE/UPOE reserve')),
    );
    expect(
      result.metadata['handoffChecklist'],
      anyElement(contains('current source data')),
    );
    expect(
      result.metadata['reviewerNextSteps'],
      anyElement(contains('Assign owners')),
    );
    expect(
      result.metadata['decisionOwners'],
      containsAll([
        'Executive / technical owner',
        'Network architect',
        'Lifecycle owner',
        'SE / account team',
        'Project owner',
      ]),
    );
    expect(result.metadata['thresholdGuidanceCount'], greaterThanOrEqualTo(4));
    expect(
      result.metadata['signals'],
      containsAll(['PoE/UPOE', 'WAN capacity', 'Lifecycle']),
    );
    expect(
      result.metadata['chartFamilies'],
      containsAll(['PoE Budget', 'WAN Capacity', 'Lifecycle Risk']),
    );
    expect(
      result.metadata['readinessSignals'],
      containsAll(['Source data', 'Risk labels', 'Capacity signals']),
    );
    expect(result.metadata['validationGapCount'], 0);
    expect(result.metadata['hasCustomerReadyChartPack'], isFalse);
    final svg = String.fromCharCodes(result.bytes);
    expect(svg, contains('Decision readiness'));
    expect(svg, contains('Customer handoff readiness'));
    expect(svg, contains('id="chart-handoff-readiness"'));
    expect(svg, contains('&quot;chartHandoffReadinessMatrix&quot;:'));
    expect(svg, contains('&quot;chartHandoffReadinessGateCount&quot;:6'));
  });
}
