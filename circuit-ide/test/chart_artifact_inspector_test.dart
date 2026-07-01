import 'package:circuit_ide/models/artifact_document.dart';
import 'package:circuit_ide/services/chart_artifact_inspector.dart';
import 'package:circuit_ide/services/chart_artifact_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chart inspector verifies single chart SVG structure', () {
    const document = ArtifactDocument(
      title: 'PoE Budget Risk',
      summary: 'PoE budget chart for campus access switching.',
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
    expect(inspection.hasPoeSignal, isTrue);
    expect(inspection.noteCount, greaterThanOrEqualTo(1));
  });

  test('chart inspector verifies enterprise multi-panel chart packs', () {
    const document = ArtifactDocument(
      title: 'Enterprise Sizing Chart Pack',
      summary:
          'Enterprise charts covering PoE, WAN, lifecycle, and product fit.',
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
      ],
    );

    final result = const ChartArtifactRenderer().render(document);
    final inspection = const ChartArtifactInspector().inspect(result.bytes);

    expect(inspection.isStructurallyValid, isTrue);
    expect(inspection.hasEnterpriseChartPackStructure, isTrue);
    expect(inspection.chartCount, 4);
    expect(inspection.pointCount, 8);
    expect(inspection.hasChartSummaryPanel, isTrue);
    expect(inspection.hasRiskLegend, isTrue);
    expect(inspection.highRiskCount, greaterThanOrEqualTo(1));
    expect(inspection.mediumRiskCount, greaterThanOrEqualTo(2));
    expect(inspection.lowRiskCount, greaterThanOrEqualTo(2));
    expect(inspection.hasPoeSignal, isTrue);
    expect(inspection.hasWanSignal, isTrue);
    expect(inspection.hasLifecycleSignal, isTrue);
    expect(inspection.hasComparisonSignal, isTrue);
    expect(
      inspection.chartKinds,
      containsAll(['poe', 'wan', 'lifecycle', 'comparison']),
    );
    expect(
      inspection.chartTitles,
      containsAll([
        'PoE Budget',
        'WAN Capacity',
        'Lifecycle Risk',
        'Product Comparison',
      ]),
    );
  });
}
