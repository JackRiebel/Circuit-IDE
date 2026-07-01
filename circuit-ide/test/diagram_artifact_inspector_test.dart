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

      expect(inspection.isStructurallyValid, isTrue);
      expect(inspection.hasEnterpriseTopologyStructure, isTrue);
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
    },
  );
}
