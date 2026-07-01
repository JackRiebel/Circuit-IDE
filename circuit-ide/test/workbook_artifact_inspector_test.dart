import 'dart:io';

import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/services/generated_artifact_writer.dart';
import 'package:circuit_ide/services/workbook_artifact_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'inspector verifies enterprise solution sizing workbook structure',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-workbook-');
      addTearDown(() => root.delete(recursive: true));

      final artifact = await const GeneratedArtifactWriter()
          .writeFromAssistantOutput(
            rootPath: root.path,
            prompt:
                'create a solution sizing workbook for 500 users, 90 APs, 6 switches, 2 Gbps WAN, and Wi-Fi 7 UPOE',
            content: '''
# Campus Solution Sizing

## Recommendations
- Validate Wi-Fi 7 AP UPOE requirements before selecting access switches.
- Size WAN against inspection throughput, not just carrier link speed.

| Site | Users | APs | WAN |
| --- | ---: | ---: | --- |
| HQ | 300 | 50 | 2 Gbps |
| Branch | 200 | 40 | 1 Gbps |

## Assumptions
- Customer wants 25% growth headroom.
- Lifecycle and LDOS dates still need validation.
''',
            turnId: 'turn-sizing-inspect',
            threadId: 'thread-1',
            requestId: 'request-1',
          );

      expect(artifact, isNotNull);
      expect(artifact!.kind, GeneratedArtifactKind.excel);

      final inspection = const WorkbookArtifactInspector().inspect(
        File(artifact.filePath).readAsBytesSync(),
      );
      expect(inspection.isStructurallyValid, isTrue);
      expect(inspection.hasEnterpriseWorkbookStructure, isTrue);
      expect(
        inspection.hasSheets(const [
          'Requirements',
          'Sizing Inputs',
          'Capacity Model',
          'PoE Budget',
          'WAN Throughput',
          'HA Growth',
          'Recommendations',
          'Validation',
          'Assumptions',
          'Decision Summary',
        ]),
        isTrue,
      );
      expect(inspection.sheetContains('Requirements', '500'), isTrue);
      expect(inspection.sheetContains('Requirements', '90'), isTrue);
      expect(
        inspection.sheetContains('Capacity Model', 'Planning Value'),
        isTrue,
      );
      expect(inspection.sheetContains('PoE Budget', 'Wi-Fi 7/UPOE'), isTrue);
      expect(
        inspection.sheetContains('WAN Throughput', 'inspected throughput'),
        isTrue,
      );
      expect(
        inspection.sheetContains('HA Growth', 'EoX replacement PID'),
        isTrue,
      );
      expect(
        inspection.sheetContains('Decision Summary', 'Access switching'),
        isTrue,
      );
      expect(inspection.sheetContains('Validation', 'PoE/UPOE budget'), isTrue);
      expect(
        inspection.sheetContains('Validation', 'Lifecycle / LDOS'),
        isTrue,
      );
    },
  );

  test('inspector verifies product comparison workbook structure', () async {
    final root = await Directory.systemTemp.createTemp('circuit-workbook-');
    addTearDown(() => root.delete(recursive: true));

    final artifact = await const GeneratedArtifactWriter().writeFromAssistantOutput(
      rootPath: root.path,
      prompt:
          'create a product comparison matrix comparing C9300-48P, C9400, and Meraki MS355 for Wi-Fi 7 UPOE access',
      content: '''
# Access Switching Product Comparison

| Model | Positioning | PoE | Uplinks | Lifecycle | Fit Score | Recommendation |
| --- | --- | --- | --- | --- | ---: | --- |
| C9300-48P | Standard campus access | UPOE options | 10G/25G modular | Verify LDOS | 4 | Good default if power budget fits |
| C9400 | Modular campus access | High power chassis | 40G/100G options | Verify current supervisor | 3 | Use for chassis requirements |
| Meraki MS355 | Cloud-managed access | UPOE models | 10G/40G options | Verify dashboard/licensing | 4 | Good fit for Meraki operations |

## Alternatives
- Older EoX migration PID: reject if it lacks multigig or UPOE for Wi-Fi 7.

## Assumptions
- Customer requires Wi-Fi 7 AP power headroom.
- Final recommendation needs sourced datasheet validation.
''',
      turnId: 'turn-comparison-inspect',
      threadId: 'thread-1',
      requestId: 'request-1',
    );

    expect(artifact, isNotNull);
    expect(artifact!.kind, GeneratedArtifactKind.excel);

    final inspection = const WorkbookArtifactInspector().inspect(
      File(artifact.filePath).readAsBytesSync(),
    );
    expect(inspection.isStructurallyValid, isTrue);
    expect(inspection.hasEnterpriseWorkbookStructure, isTrue);
    expect(
      inspection.hasSheets(const [
        'Comparison Matrix',
        'Decision Summary',
        'Fit Scoring',
        'Requirements',
        'Requirement Gates',
        'Scored Shortlist',
        'Alternatives',
        'Replacement Cautions',
        'Validation Checklist',
        'Sources Needed',
        'Assumptions',
      ]),
      isTrue,
    );
    expect(inspection.sheetContains('Comparison Matrix', 'C9300-48P'), isTrue);
    expect(
      inspection.sheetContains('Comparison Matrix', 'Meraki MS355'),
      isTrue,
    );
    expect(
      inspection.sheetContains('Fit Scoring', 'Lifecycle confidence'),
      isTrue,
    );
    expect(
      inspection.sheetContains('Decision Summary', 'suggestedMigrationPid'),
      isTrue,
    );
    expect(
      inspection.sheetContains('Requirement Gates', 'Reject stale migration'),
      isTrue,
    );
    expect(inspection.sheetContains('Scored Shortlist', 'C9300-48P'), isTrue);
    expect(
      inspection.sheetContains('Replacement Cautions', 'suggestedMigrationPid'),
      isTrue,
    );
    expect(
      inspection.sheetContains('Validation Checklist', 'Capability facts'),
      isTrue,
    );
    expect(
      inspection.sheetContains('Sources Needed', 'Official datasheet'),
      isTrue,
    );
    expect(inspection.sheetContains('Requirements', 'Wi-Fi 7'), isTrue);
  });

  test('inspector verifies lifecycle EoX workbook structure', () async {
    final root = await Directory.systemTemp.createTemp('circuit-workbook-');
    addTearDown(() => root.delete(recursive: true));

    final artifact = await const GeneratedArtifactWriter().writeFromAssistantOutput(
      rootPath: root.path,
      prompt:
          'create a Lifecycle EoX report for C9300-48P and AIR-AP2802I with replacement PIDs for Wi-Fi 7 UPOE refresh',
      content: '''
# Lifecycle / EoX Review

| Product | Lifecycle Status | End of Sale | LDOS | Risk | Replacement PID | Source |
| --- | --- | --- | --- | --- | --- | --- |
| C9300-48P | Active | TBD | TBD | Review | C9300X-48HX | Cisco EoX/API required |
| AIR-AP2802I | End of Support | 31-Oct-2021 | 31-Oct-2026 | High | CW9176I | Cisco EoX/API required |

## Risks
- AIR-AP2802I replacement must validate Wi-Fi 7 power, multigig, and UPOE switch budgets.
- EoX replacement PID is a migration clue only.

## Assumptions
- Lifecycle dates require official Cisco validation and checked dates.
''',
      turnId: 'turn-lifecycle-inspect',
      threadId: 'thread-1',
      requestId: 'request-1',
    );

    expect(artifact, isNotNull);
    expect(artifact!.kind, GeneratedArtifactKind.excel);

    final inspection = const WorkbookArtifactInspector().inspect(
      File(artifact.filePath).readAsBytesSync(),
    );
    expect(inspection.isStructurallyValid, isTrue);
    expect(inspection.hasEnterpriseWorkbookStructure, isTrue);
    expect(
      inspection.hasSheets(const [
        'Lifecycle Status',
        'Urgency Timeline',
        'Migration Hints',
        'Replacement Evaluation',
        'Decision Gates',
        'Source Quality',
        'WiFi7 UPOE Readiness',
        'Risk Register',
        'Assumptions',
      ]),
      isTrue,
    );
    expect(inspection.sheetContains('Lifecycle Status', 'AIR-AP2802I'), isTrue);
    expect(
      inspection.sheetContains('Migration Hints', 'migration clue'),
      isTrue,
    );
    expect(
      inspection.sheetContains('Urgency Timeline', 'Immediate review'),
      isTrue,
    );
    expect(
      inspection.sheetContains('Replacement Evaluation', 'Wi-Fi 7'),
      isTrue,
    );
    expect(
      inspection.sheetContains('Replacement Evaluation', 'PoE/UPOE'),
      isTrue,
    );
    expect(
      inspection.sheetContains('Decision Gates', 'suggestedMigrationPid'),
      isTrue,
    );
    expect(inspection.sheetContains('Source Quality', 'checked date'), isTrue);
    expect(
      inspection.sheetContains('WiFi7 UPOE Readiness', 'UPOE / UPOE+ budget'),
      isTrue,
    );
    expect(
      inspection.sheetContains('Risk Register', 'replacement must validate'),
      isTrue,
    );
  });
}
