import 'package:circuit_ide/models/artifact_document.dart';
import 'package:circuit_ide/services/diagram_artifact_inspector.dart';
import 'package:circuit_ide/services/diagram_artifact_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diagram inspector verifies basic Mermaid SVG structure', () {
    const document = ArtifactDocument(
      title: 'Branch WAN Topology',
      summary: 'Branch network diagram.',
      assumptions: ['Branches use redundant WAN links.'],
    );
    final result = const DiagramArtifactRenderer().render(
      document: document,
      content: '''
```mermaid
graph LR
  HQ[Headquarters] -->|dual WAN| BR1[Branch 1]
  HQ -->|dual WAN| BR2[Branch 2]
```
''',
    );

    final inspection = const DiagramArtifactInspector().inspect(result.bytes);

    expect(inspection.isStructurallyValid, isTrue);
    expect(inspection.title, 'Branch WAN Topology');
    expect(inspection.nodeCount, 3);
    expect(inspection.edgeCount, 2);
    expect(inspection.tierCount, greaterThanOrEqualTo(1));
    expect(inspection.assumptionCount, 1);
    expect(inspection.hasLogicalTopologyGuidance, isTrue);
    expect(inspection.hasTopologySummaryPanel, isTrue);
    expect(inspection.hasInventoryPanel, isTrue);
    expect(inspection.hasDesignZones, isTrue);
    expect(inspection.hasLinkSchedule, isTrue);
    expect(inspection.hasReadinessScorecard, isTrue);
    expect(inspection.hasDesignAdvisoryPanel, isTrue);
    expect(inspection.hasCapacityPanel, isTrue);
    expect(inspection.hasValidationChecklist, isTrue);
    expect(inspection.designZoneCount, greaterThanOrEqualTo(1));
    expect(inspection.linkScheduleCount, 2);
    expect(inspection.readinessItemCount, 4);
    expect(inspection.advisoryCount, greaterThanOrEqualTo(2));
    expect(inspection.hasLifecycleReplacementCaveat, isTrue);
    expect(inspection.capacityItemCount, 4);
  });

  test(
    'diagram inspector verifies enterprise topology tiers and device tokens',
    () {
      const document = ArtifactDocument(
        title: 'Cisco Campus Topology',
        summary: 'Enterprise campus topology.',
        assumptions: [
          'Validate PoE budget before final model selection.',
          'Validate WAN handoff speeds at every branch.',
        ],
      );
      final result = const DiagramArtifactRenderer().render(
        document: document,
        content: '''
Customer has 3 branches, dual WAN, warm spare MX250 firewalls, 1 MDF with C9500 core switches,
3 IDFs with C9300-48P UPOE access switches, 90 CW9176 Wi-Fi 7 APs, and client devices.
''',
      );

      final inspection = const DiagramArtifactInspector().inspect(result.bytes);
      final svg = String.fromCharCodes(result.bytes);

      expect(inspection.isStructurallyValid, isTrue);
      expect(inspection.hasEnterpriseTopologyStructure, isTrue);
      expect(inspection.hasDesignZones, isTrue);
      expect(inspection.hasLinkSchedule, isTrue);
      expect(inspection.hasReadinessScorecard, isTrue);
      expect(inspection.hasDesignAdvisoryPanel, isTrue);
      expect(inspection.hasCapacityPanel, isTrue);
      expect(inspection.nodeCount, greaterThanOrEqualTo(6));
      expect(inspection.edgeCount, greaterThanOrEqualTo(5));
      expect(
        inspection.tierLabels,
        containsAll([
          'Sites',
          'WAN / Cloud',
          'Security Edge',
          'MDF / Core',
          'IDF / Access',
          'Wireless / Clients',
        ]),
      );
      expect(inspection.containsDeviceToken('MX250'), isTrue);
      expect(inspection.containsDeviceToken('C9500'), isTrue);
      expect(inspection.containsDeviceToken('C9300'), isTrue);
      expect(inspection.containsDeviceToken('CW9176'), isTrue);
      expect(inspection.assumptionCount, 2);
      expect(inspection.designZoneCount, greaterThanOrEqualTo(6));
      expect(inspection.linkScheduleCount, greaterThanOrEqualTo(5));
      expect(inspection.readinessItemCount, 4);
      expect(inspection.siteCount, 4);
      expect(inspection.mdfCount, 1);
      expect(inspection.idfCount, 3);
      expect(inspection.firewallCount, 2);
      expect(inspection.coreSwitchCount, 1);
      expect(inspection.accessSwitchCount, 3);
      expect(inspection.switchCount, greaterThanOrEqualTo(4));
      expect(inspection.apCount, 90);
      expect(inspection.accessPortCount, 144);
      expect(inspection.estimatedApPowerWatts, 2700);
      expect(inspection.apPortLoadPercent, 63);
      expect(inspection.hasDualWan, isTrue);
      expect(inspection.hasWarmSpare, isTrue);
      expect(inspection.hasPoe, isTrue);
      expect(inspection.hasUpoe, isTrue);
      expect(inspection.hasMultigig, isFalse);
      expect(inspection.hasWifi7, isTrue);
      expect(inspection.advisoryCount, greaterThanOrEqualTo(3));
      expect(inspection.hasLifecycleReplacementCaveat, isTrue);
      expect(inspection.hasWifi7PowerAdvisory, isTrue);
      expect(result.metadata['hasDesignAdvisoryPanel'], isTrue);
      expect(result.metadata['hasLifecycleReplacementCaveat'], isTrue);
      expect(result.metadata['hasWifi7PowerAdvisory'], isTrue);
      expect(result.metadata['advisoryCount'], greaterThanOrEqualTo(3));
      expect(
        result.previewRows.expand((row) => row),
        contains('Wi-Fi 7 / PoE'),
      );
      expect(svg, contains('Architecture advisories'));
      expect(svg, contains('EoX replacement PIDs'));
      expect(svg, contains('Wi-Fi 7 APs require explicit UPOE'));
    },
  );

  test('diagram inspector verifies larger campus inventory counts', () {
    const document = ArtifactDocument(
      title: 'Large Campus Topology',
      summary: 'Large campus topology with explicit MDF and IDF counts.',
      assumptions: ['Validate uplink oversubscription and AP placement.'],
    );
    final result = const DiagramArtifactRenderer().render(
      document: document,
      content: '''
Build a topology for 1 MDF with 6 C9500 core switches, 3 IDFs with 6 C9300-48P UPOE switches,
warm spare MX250 firewalls, dual WAN, all 48 ports UPOE with 10gig speed, and 90 CW9176 Wi-Fi 7 APs.
''',
    );

    final inspection = const DiagramArtifactInspector().inspect(result.bytes);
    final svg = String.fromCharCodes(result.bytes);

    expect(inspection.hasEnterpriseTopologyStructure, isTrue);
    expect(inspection.hasInventoryPanel, isTrue);
    expect(inspection.siteCount, 1);
    expect(inspection.mdfCount, 1);
    expect(inspection.idfCount, 3);
    expect(inspection.firewallCount, 2);
    expect(inspection.coreSwitchCount, 6);
    expect(inspection.accessSwitchCount, 6);
    expect(inspection.switchCount, 12);
    expect(inspection.apCount, 90);
    expect(inspection.accessPortCount, 288);
    expect(inspection.estimatedApPowerWatts, 2700);
    expect(inspection.apPortLoadPercent, 31);
    expect(inspection.hasDualWan, isTrue);
    expect(inspection.hasWarmSpare, isTrue);
    expect(inspection.hasPoe, isTrue);
    expect(inspection.hasUpoe, isTrue);
    expect(inspection.hasMultigig, isTrue);
    expect(inspection.hasWifi7, isTrue);
    expect(inspection.hasDesignAdvisoryPanel, isTrue);
    expect(inspection.hasLifecycleReplacementCaveat, isTrue);
    expect(inspection.hasWifi7PowerAdvisory, isTrue);
    expect(inspection.advisoryCount, greaterThanOrEqualTo(3));
    expect(svg, contains('Inventory'));
    expect(svg, contains('Design zones'));
    expect(svg, contains('Architecture advisories'));
    expect(svg, contains('Link schedule'));
    expect(svg, contains('Readiness scorecard'));
    expect(svg, contains('Capacity checks'));
    expect(svg, contains('MDF 1'));
    expect(svg, contains('IDF 3'));
    expect(svg, contains('Core 6'));
    expect(svg, contains('Access 6'));
    expect(svg, contains('Requirements: Dual WAN'));
    expect(svg, contains('mGig/10G'));
    expect(svg, contains('2700W est.'));
    expect(svg, contains('90/288 AP ports'));
  });
}
