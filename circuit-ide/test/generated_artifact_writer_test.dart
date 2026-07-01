import 'dart:io';

import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/services/artifact_type_registry.dart';
import 'package:circuit_ide/services/generated_artifact_exporter.dart';
import 'package:circuit_ide/services/generated_artifact_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'PowerPoint prompt creates a real pptx artifact from structured markdown',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
      addTearDown(() => root.delete(recursive: true));
      final artifact = await const GeneratedArtifactWriter()
          .writeFromAssistantOutput(
            rootPath: root.path,
            prompt: 'create a PowerPoint deck for this customer proposal',
            content: '''
# Customer Architecture Proposal

Short executive summary for the customer.

## Current State
- Three branch sites
- Dual WAN at each site
- Centralized security policy

## Recommended Architecture
- Use resilient edge pairs
- Standardize access switching
- Validate PoE budgets

| Site | Users | WAN |
| --- | ---: | --- |
| HQ | 500 | Dual 2 Gbps |
| Branch | 120 | Dual 500 Mbps |

## Assumptions
- Customer will validate final user counts.

## Sources
- Customer workshop notes
''',
            turnId: 'turn-pptx',
            threadId: 'thread-1',
            requestId: 'request-1',
          );

      expect(artifact, isNotNull);
      expect(artifact!.kind, GeneratedArtifactKind.powerPoint);
      expect(artifact.status, GeneratedArtifactStatus.ready);
      expect(artifact.fileName, endsWith('.pptx'));
      expect(artifact.sheetCount, greaterThanOrEqualTo(8));
      expect(artifact.summary, contains('PowerPoint deck'));
      expect(artifact.previewRows.first, ['Slide', 'Type', 'Title']);
      expect(
        artifact.previewRows.map((row) => row.join(' / ')),
        contains(contains('Decision Snapshot')),
      );
      expect(
        artifact.previewRows.map((row) => row.join(' / ')),
        contains(contains('Data Snapshot')),
      );
      expect(File(artifact.filePath).existsSync(), isTrue);
      final bytes = File(artifact.filePath).readAsBytesSync();
      expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
      final packageText = String.fromCharCodes(bytes);
      expect(packageText, contains('ppt/presentation.xml'));
      expect(packageText, contains('ppt/slides/slide1.xml'));
      expect(packageText, contains('Agenda'));
      expect(packageText, contains('Decision Snapshot'));
      expect(packageText, contains('Key Takeaways'));
      expect(packageText, contains('Executive Summary'));
      expect(packageText, contains('Current State'));
      expect(packageText, contains('Recommended Architecture'));
      expect(packageText, contains('Implementation Roadmap'));
      expect(packageText, contains('Data Snapshot'));
      expect(packageText, contains('Executive readout'));
      expect(packageText, contains('Data table'));
      expect(packageText, contains('Dual 2 Gbps'));
      expect(packageText, contains('Executive Recommendation'));
      expect(packageText, contains('Assumptions &amp; Sources'));
      expect(packageText, contains('Appendix: Handoff Checklist'));
      expect(packageText, contains('Slide 1 of'));
      expect(packageText, contains('Customer workshop notes'));
      expect(packageText, contains('CircuitCode - Generated artifact'));
    },
  );

  test(
    'Excel prompt creates a real xlsx artifact from markdown table',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
      addTearDown(() => root.delete(recursive: true));
      final artifact = await const GeneratedArtifactWriter()
          .writeFromAssistantOutput(
            rootPath: root.path,
            prompt: 'create an Excel file from this',
            content: '''
Here is the data.

| Product | Count |
| --- | ---: |
| C9300 | 6 |
| CW9176 | 90 |
''',
            turnId: 'turn-1',
            threadId: 'thread-1',
            requestId: 'request-1',
          );

      expect(artifact, isNotNull);
      expect(artifact!.kind, GeneratedArtifactKind.excel);
      expect(artifact.status, GeneratedArtifactStatus.ready);
      expect(artifact.fileName, endsWith('.xlsx'));
      expect(File(artifact.filePath).existsSync(), isTrue);
      final bytes = File(artifact.filePath).readAsBytesSync();
      expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
      expect(String.fromCharCodes(bytes), contains('xl/workbook.xml'));
      expect(artifact.previewRows.first, ['Product', 'Count']);
      expect(artifact.sheetCount, 1);
    },
  );

  test('solution sizing prompt creates a multi-sheet sizing workbook', () async {
    final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
    addTearDown(() => root.delete(recursive: true));
    final artifact = await const GeneratedArtifactWriter().writeFromAssistantOutput(
      rootPath: root.path,
      prompt:
          'create a solution sizing workbook for 500 users, 90 APs, 6 switches, and 2 Gbps WAN',
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
      turnId: 'turn-sizing',
      threadId: 'thread-1',
      requestId: 'request-1',
    );

    expect(artifact, isNotNull);
    expect(artifact!.kind, GeneratedArtifactKind.excel);
    expect(artifact.status, GeneratedArtifactStatus.ready);
    expect(artifact.fileName, endsWith('.xlsx'));
    expect(artifact.summary, contains('solution sizing workbook'));
    expect(artifact.sheetCount, greaterThanOrEqualTo(5));
    expect(artifact.previewRows.first, ['Metric', 'Value', 'Notes']);
    final bytes = File(artifact.filePath).readAsBytesSync();
    expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
    final packageText = String.fromCharCodes(bytes);
    expect(packageText, contains('Requirements'));
    expect(packageText, contains('Sizing Inputs'));
    expect(packageText, contains('Capacity Model'));
    expect(packageText, contains('PoE Budget'));
    expect(packageText, contains('WAN Throughput'));
    expect(packageText, contains('HA Growth'));
    expect(packageText, contains('Requirement Gates'));
    expect(packageText, contains('Candidate Validation'));
    expect(packageText, contains('Recommendations'));
    expect(packageText, contains('Validation'));
    expect(packageText, contains('Assumptions'));
    expect(packageText, contains('Decision Summary'));
    expect(packageText, contains('500'));
    expect(packageText, contains('90'));
    expect(packageText, contains('2 Gbps'));
    expect(packageText, contains('inspected throughput'));
    expect(packageText, contains('mGig validation required'));
    expect(packageText, contains('Access switch shortlist'));
  });

  test(
    'product comparison prompt creates a multi-sheet comparison matrix',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
      addTearDown(() => root.delete(recursive: true));
      final artifact = await const GeneratedArtifactWriter()
          .writeFromAssistantOutput(
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
            turnId: 'turn-comparison',
            threadId: 'thread-1',
            requestId: 'request-1',
          );

      expect(artifact, isNotNull);
      expect(artifact!.kind, GeneratedArtifactKind.excel);
      expect(artifact.status, GeneratedArtifactStatus.ready);
      expect(artifact.fileName, endsWith('.xlsx'));
      expect(artifact.summary, contains('product comparison matrix'));
      expect(artifact.sheetCount, greaterThanOrEqualTo(5));
      expect(artifact.previewRows.first, [
        'Product / Model',
        'Positioning',
        'Key capabilities',
        'Constraints / caveats',
        'Lifecycle / risk',
        'Fit score',
        'Recommendation',
      ]);
      final bytes = File(artifact.filePath).readAsBytesSync();
      expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
      final packageText = String.fromCharCodes(bytes);
      expect(packageText, contains('Comparison Matrix'));
      expect(packageText, contains('Decision Summary'));
      expect(packageText, contains('Fit Scoring'));
      expect(packageText, contains('Requirements'));
      expect(packageText, contains('Requirement Gates'));
      expect(packageText, contains('Hard Gate Evaluation'));
      expect(packageText, contains('Scored Shortlist'));
      expect(packageText, contains('Alternatives'));
      expect(packageText, contains('Replacement Cautions'));
      expect(packageText, contains('Validation Checklist'));
      expect(packageText, contains('Sources Needed'));
      expect(packageText, contains('Assumptions'));
      expect(packageText, contains('C9300-48P'));
      expect(packageText, contains('Meraki MS355'));
      expect(packageText, contains('Wi-Fi 7'));
      expect(packageText, contains('UPOE'));
      expect(packageText, contains('suggestedMigrationPid'));
      expect(packageText, contains('Power / UPOE'));
      expect(packageText, contains('Multigig access'));
      expect(packageText, contains('hard-gate compliance'));
      expect(packageText, contains('Official datasheet'));
    },
  );

  test('lifecycle prompt creates a multi-sheet EoX workbook', () async {
    final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
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

Source checked 2026-06-30 from Cisco EoX/API.

## Risks
- AIR-AP2802I replacement must validate Wi-Fi 7 power, multigig, and UPOE switch budgets.
- EoX replacement PID is a migration clue only.

## Assumptions
- Lifecycle dates require official Cisco validation and checked dates.
''',
      turnId: 'turn-lifecycle',
      threadId: 'thread-1',
      requestId: 'request-1',
    );

    expect(artifact, isNotNull);
    expect(artifact!.kind, GeneratedArtifactKind.excel);
    expect(artifact.status, GeneratedArtifactStatus.ready);
    expect(artifact.fileName, endsWith('.xlsx'));
    expect(artifact.summary, contains('Lifecycle / EoX workbook'));
    expect(artifact.sheetCount, greaterThanOrEqualTo(5));
    expect(artifact.previewRows.first, [
      'Product / PID',
      'Lifecycle status',
      'End of sale',
      'Last date of support',
      'Risk',
      'Source / evidence',
    ]);
    final bytes = File(artifact.filePath).readAsBytesSync();
    expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
    final packageText = String.fromCharCodes(bytes);
    expect(packageText, contains('Lifecycle Status'));
    expect(packageText, contains('Urgency Timeline'));
    expect(packageText, contains('Migration Hints'));
    expect(packageText, contains('Replacement Evaluation'));
    expect(packageText, contains('Decision Gates'));
    expect(packageText, contains('Source Quality'));
    expect(packageText, contains('Official Date Evidence'));
    expect(packageText, contains('Replacement Suitability'));
    expect(packageText, contains('WiFi7 UPOE Readiness'));
    expect(packageText, contains('Risk Register'));
    expect(packageText, contains('Assumptions'));
    expect(packageText, contains('C9300-48P'));
    expect(packageText, contains('AIR-AP2802I'));
    expect(packageText, contains('CW9176I'));
    expect(packageText, contains('migration clue only'));
    expect(packageText, contains('suggestedMigrationPid'));
    expect(packageText, contains('checked date'));
    expect(packageText, contains('2026-06-30'));
    expect(packageText, contains('Migration hint only'));
    expect(
      packageText,
      contains('Do not recommend CW9176I unless sourced facts prove'),
    );
    expect(packageText, contains('current portfolio comparison'));
    expect(packageText, contains('Wi-Fi 7'));
    expect(packageText, contains('UPOE'));
  });

  test(
    'DOCX prompt creates a real Word artifact from structured markdown',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
      addTearDown(() => root.delete(recursive: true));
      final artifact = await const GeneratedArtifactWriter()
          .writeFromAssistantOutput(
            rootPath: root.path,
            prompt: 'create a DOCX architecture report',
            content: '''
# Branch Network Architecture Report

Executive summary for a customer handoff.

## Findings
- WAN redundancy is required.
- Access switching needs PoE validation.

## Recommendations
- Standardize branch edge design.
- Create validation checkpoints before deployment.

| Risk | Severity |
| --- | --- |
| PoE budget unknown | Medium |

## Assumptions
- Customer will confirm AP counts.

## Sources
- Customer inventory export
''',
            turnId: 'turn-docx',
            threadId: 'thread-1',
            requestId: 'request-1',
          );

      expect(artifact, isNotNull);
      expect(artifact!.kind, GeneratedArtifactKind.docx);
      expect(artifact.status, GeneratedArtifactStatus.ready);
      expect(artifact.fileName, endsWith('.docx'));
      expect(artifact.sheetCount, greaterThanOrEqualTo(3));
      expect(artifact.previewRows.first, ['Section', 'Type', 'Items']);
      expect(
        artifact.previewRows.map((row) => row.join(' / ')),
        contains(contains('Findings')),
      );
      expect(
        artifact.previewRows.map((row) => row.join(' / ')),
        contains(contains('Sources / Evidence')),
      );
      expect(File(artifact.filePath).existsSync(), isTrue);
      final bytes = File(artifact.filePath).readAsBytesSync();
      expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
      final packageText = String.fromCharCodes(bytes);
      expect(packageText, contains('word/document.xml'));
      expect(packageText, contains('word/styles.xml'));
      expect(packageText, contains('word/numbering.xml'));
      expect(packageText, contains('word/settings.xml'));
      expect(packageText, contains('word/footer1.xml'));
      expect(packageText, contains('Branch Network Architecture Report'));
      expect(packageText, contains('CircuitCode generated report'));
      expect(packageText, contains('Report Overview'));
      expect(packageText, contains('Executive Decision Brief'));
      expect(packageText, contains('Document Map'));
      expect(packageText, contains('Stakeholder Readout'));
      expect(packageText, contains('Evidence Confidence Matrix'));
      expect(packageText, contains('Approval Gates'));
      expect(packageText, contains('Validation Checklist'));
      expect(packageText, contains('<cp:keywords>'));
      expect(packageText, contains('WAN redundancy is required'));
      expect(packageText, contains('PoE budget unknown'));
      expect(packageText, contains('<w:numPr>'));
      expect(packageText, contains('<w:tblGrid>'));
      expect(packageText, contains('<w:tblW w:w="9120" w:type="dxa"/>'));
      expect(packageText, contains('<w:shd w:fill="E2E8F0"/>'));
      expect(packageText, contains('Appendix A: Assumptions'));
      expect(packageText, contains('Appendix B: Sources / Evidence'));
      expect(packageText, contains('CircuitCode - Generated artifact'));
    },
  );

  test(
    'architecture review prompt creates a shaped DOCX review pack',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
      addTearDown(() => root.delete(recursive: true));
      final artifact = await const GeneratedArtifactWriter()
          .writeFromAssistantOutput(
            rootPath: root.path,
            prompt: 'create an architecture review pack for this campus design',
            content: '''
# Campus Architecture Review

Architecture review for a campus refresh with WAN, access, wireless, and security scope.

## Current State
- Dual WAN exists but failover evidence is incomplete.
- Access switching needs PoE and uplink validation.

## Design Objectives
- Improve resiliency across WAN and campus access.
- Support Wi-Fi 7 growth with validated power and uplink budgets.

## Findings
- WAN failover has not been tested with business-critical applications.
- PoE budget could constrain Wi-Fi 7 AP deployment.
- Security segmentation needs confirmation before rollout.

## Risks
- Unknown PoE headroom can delay access-layer readiness.
- Missing failover validation creates availability risk.

## Recommendations
- Run WAN failover testing and capture results.
- Validate PoE, multigig, and uplink capacity before final model choice.
- Confirm segmentation and logging requirements with security owner.

## Validation
- Test WAN failover during a maintenance window.
- Review switch power budgets against AP inventory.
- Confirm security policy and audit evidence.

## Decisions
- Use phased rollout with MDF first, then IDFs.

## Assumptions
- Customer AP count is current.

## Sources
- Workshop notes
''',
            turnId: 'turn-architecture-review',
            threadId: 'thread-1',
            requestId: 'request-1',
          );

      expect(artifact, isNotNull);
      expect(artifact!.kind, GeneratedArtifactKind.docx);
      expect(artifact.status, GeneratedArtifactStatus.ready);
      expect(artifact.fileName, endsWith('.docx'));
      expect(artifact.summary, contains('architecture review pack'));
      expect(artifact.summary, contains('findings matrix'));
      expect(artifact.sheetCount, greaterThanOrEqualTo(10));
      expect(File(artifact.filePath).existsSync(), isTrue);
      final bytes = File(artifact.filePath).readAsBytesSync();
      expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
      final packageText = String.fromCharCodes(bytes);
      expect(packageText, contains('word/document.xml'));
      expect(packageText, contains('Campus Architecture Review'));
      expect(packageText, contains('Architecture Review Summary'));
      expect(packageText, contains('Current Architecture Snapshot'));
      expect(packageText, contains('Design Objectives'));
      expect(packageText, contains('Key Findings'));
      expect(packageText, contains('Risk Register'));
      expect(packageText, contains('Recommendations'));
      expect(packageText, contains('Validation Plan'));
      expect(packageText, contains('Decision Log'));
      expect(packageText, contains('Architecture Findings Matrix'));
      expect(packageText, contains('Risk And Mitigation Register'));
      expect(packageText, contains('Recommendation Roadmap'));
      expect(packageText, contains('Decision And Assumption Log'));
      expect(packageText, contains('Stakeholder Readout'));
      expect(packageText, contains('Evidence Confidence Matrix'));
      expect(packageText, contains('Approval Gates'));
      expect(packageText, contains('WAN failover has not been tested'));
      expect(packageText, contains('Unknown PoE headroom'));
      expect(packageText, contains('Validate PoE, multigig, and uplink'));
      expect(packageText, contains('Business / technical owner'));
      expect(packageText, contains('Workshop notes'));
    },
  );

  test('business case brief prompt creates a shaped DOCX artifact', () async {
    final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
    addTearDown(() => root.delete(recursive: true));
    final artifact = await const GeneratedArtifactWriter()
        .writeFromAssistantOutput(
          rootPath: root.path,
          prompt: 'create a business case brief for Acme Manufacturing',
          content: '''
# Acme Manufacturing Business Use Case Brief

Acme needs an executive-ready brief that connects business signals to prioritized technology use cases.

## Company Context
- 40 facilities across North America
- Legacy WAN and inconsistent plant connectivity

## Pain Points
- Production downtime creates missed shipment risk.
- Security operations are fragmented across plants.

## Priority Use Cases
- Predictive maintenance telemetry for critical equipment.
- Secure branch modernization for plant and office sites.

## Recommended Solutions
- Cisco SD-WAN for resilient plant connectivity.
- Secure access and observability for OT-adjacent workflows.

## Value And Impact
- Reduce downtime exposure.
- Improve incident response and operational visibility.

## Next Steps
- Run a discovery workshop with operations, security, and network owners.

## Assumptions
- Public research must be validated with the account team.

## Sources
- Acme annual report
''',
          turnId: 'turn-business-brief',
          threadId: 'thread-1',
          requestId: 'request-1',
        );

    expect(artifact, isNotNull);
    expect(artifact!.kind, GeneratedArtifactKind.docx);
    expect(artifact.status, GeneratedArtifactStatus.ready);
    expect(artifact.fileName, endsWith('.docx'));
    expect(artifact.summary, contains('business use case brief'));
    expect(artifact.summary, contains('solution mapping'));
    expect(artifact.summary, contains('stakeholder discovery'));
    expect(artifact.sheetCount, greaterThanOrEqualTo(7));
    expect(File(artifact.filePath).existsSync(), isTrue);
    final bytes = File(artifact.filePath).readAsBytesSync();
    expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
    final packageText = String.fromCharCodes(bytes);
    expect(packageText, contains('word/document.xml'));
    expect(packageText, contains('Acme Manufacturing Business Use Case Brief'));
    expect(packageText, contains('Executive Summary'));
    expect(packageText, contains('Executive Decision Brief'));
    expect(packageText, contains('Priority Use Cases'));
    expect(packageText, contains('Stakeholders And Workflows'));
    expect(packageText, contains('Evidence And Confidence'));
    expect(packageText, contains('Customer Discovery Questions'));
    expect(packageText, contains('Value And Impact'));
    expect(packageText, contains('Use Case Prioritization Matrix'));
    expect(packageText, contains('Solution Mapping'));
    expect(packageText, contains('Stakeholder Discovery Map'));
    expect(packageText, contains('Evidence And Confidence Register'));
    expect(packageText, contains('30 / 60 / 90 Day Action Plan'));
    expect(packageText, contains('Stakeholder Readout'));
    expect(packageText, contains('Evidence Confidence Matrix'));
    expect(packageText, contains('Approval Gates'));
    expect(packageText, contains('Predictive maintenance telemetry'));
    expect(packageText, contains('Operations leader / plant manager'));
    expect(packageText, contains('Business sponsor and technical owner'));
    expect(packageText, contains('Source-backed; verify freshness'));
    expect(packageText, contains('Validated priority use cases'));
    expect(packageText, contains('Validation Checklist'));
    expect(packageText, contains('Sources / Evidence'));
    expect(packageText, contains('Acme annual report'));
    expect(packageText, contains('word/footer1.xml'));
    expect(packageText, contains('<w:numPr>'));
  });

  test('evidence pack prompt creates a shaped DOCX artifact', () async {
    final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
    addTearDown(() => root.delete(recursive: true));
    final artifact = await const GeneratedArtifactWriter()
        .writeFromAssistantOutput(
          rootPath: root.path,
          prompt: 'create an evidence pack for Cisco lifecycle recommendations',
          content: '''
# Cisco Lifecycle Evidence Pack

Evidence supporting the lifecycle and replacement recommendation.

## Claims
- AIR-AP2802I is at support risk and needs official date validation.
- Replacement selection must validate Wi-Fi 7, multigig, and UPOE requirements.

## Sources
- Cisco EoX API — checked 2026-06-30 — https://www.cisco.com/c/en/us/products/eos-eol-listing.html
- Cisco Catalyst datasheet — checked 2026-06-30 — https://www.cisco.com/

## Assumptions
- EoX replacement PID is a migration clue, not the final recommendation.

## Confidence
- Lifecycle timing confidence is medium until official Cisco EoX/API data is refreshed.

## Unsupported Claims
- Exact replacement model needs validation against current portfolio facts.
''',
          turnId: 'turn-evidence-pack',
          threadId: 'thread-1',
          requestId: 'request-1',
        );

    expect(artifact, isNotNull);
    expect(artifact!.kind, GeneratedArtifactKind.docx);
    expect(artifact.status, GeneratedArtifactStatus.ready);
    expect(artifact.fileName, endsWith('.docx'));
    expect(artifact.summary, contains('evidence pack'));
    expect(artifact.summary, contains('claim-to-source matrix'));
    expect(artifact.summary, contains('source freshness register'));
    expect(artifact.sheetCount, greaterThanOrEqualTo(6));
    expect(File(artifact.filePath).existsSync(), isTrue);
    final bytes = File(artifact.filePath).readAsBytesSync();
    expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
    final packageText = String.fromCharCodes(bytes);
    expect(packageText, contains('word/document.xml'));
    expect(packageText, contains('Cisco Lifecycle Evidence Pack'));
    expect(packageText, contains('Executive Decision Brief'));
    expect(packageText, contains('Evidence Summary'));
    expect(packageText, contains('Claim Register'));
    expect(packageText, contains('Source Inventory'));
    expect(packageText, contains('Checked Dates'));
    expect(packageText, contains('Confidence And Risk'));
    expect(packageText, contains('Unsupported Claims / Follow-Up'));
    expect(packageText, contains('Claim To Source Matrix'));
    expect(packageText, contains('Source Freshness Register'));
    expect(packageText, contains('Unsupported Claim Triage'));
    expect(packageText, contains('Evidence Confidence Scorecard'));
    expect(packageText, contains('Customer Follow-Up Checklist'));
    expect(packageText, contains('Stakeholder Readout'));
    expect(packageText, contains('Evidence Confidence Matrix'));
    expect(packageText, contains('Approval Gates'));
    expect(packageText, contains('Supporting source'));
    expect(packageText, contains('Freshness risk'));
    expect(packageText, contains('Required evidence'));
    expect(packageText, contains('Validate current portfolio fit'));
    expect(packageText, contains('Exact replacement model needs validation'));
    expect(packageText, contains('Validation Checklist'));
    expect(packageText, contains('https://www.cisco.com/'));
    expect(packageText, contains('word/numbering.xml'));
    expect(packageText, contains('CircuitCode - Generated artifact'));
  });

  test(
    'explicit JSON evidence pack creates structured JSON artifact',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
      addTearDown(() => root.delete(recursive: true));
      final artifact = await const GeneratedArtifactWriter()
          .writeFromAssistantOutput(
            rootPath: root.path,
            prompt: 'create a JSON evidence pack for this lifecycle claim',
            content: '''
# Lifecycle Evidence Pack

## Claims
- Claim needs official validation.

## Sources
- Cisco EoX — checked 2026-06-30 — https://www.cisco.com/

## Assumptions
- Customer inventory is current.
''',
            turnId: 'turn-evidence-json',
            threadId: 'thread-1',
            requestId: 'request-1',
          );

      expect(artifact, isNotNull);
      expect(artifact!.kind, GeneratedArtifactKind.json);
      expect(artifact.status, GeneratedArtifactStatus.ready);
      expect(artifact.fileName, endsWith('.json'));
      expect(artifact.summary, contains('JSON evidence pack'));
      final jsonText = File(artifact.filePath).readAsStringSync();
      expect(jsonText, contains('"artifactTemplate": "evidence_pack"'));
      expect(jsonText, contains('"sourceCount"'));
      expect(jsonText, contains('"Claim To Source Matrix"'));
      expect(jsonText, contains('"Source Freshness Register"'));
      expect(jsonText, contains('"Evidence Confidence Scorecard"'));
      expect(jsonText, contains('"Source Inventory"'));
      expect(jsonText, contains('https://www.cisco.com/'));
    },
  );

  test('PDF prompt creates a real handoff report artifact', () async {
    final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
    addTearDown(() => root.delete(recursive: true));
    final artifact = await const GeneratedArtifactWriter()
        .writeFromAssistantOutput(
          rootPath: root.path,
          prompt: 'create a PDF architecture handoff report',
          content: '''
# Campus Refresh Handoff

Executive-ready summary for a final customer handoff.

## Findings
- Access layer needs multigig validation.
- WAN design needs redundancy confirmation.

## Recommendations
- Confirm growth assumptions.
- Validate power and uplink budgets.

| Area | Status |
| --- | --- |
| Switching | Review |

## Assumptions
- Customer will provide final site counts.

## Sources
- Workshop notes
''',
          turnId: 'turn-pdf',
          threadId: 'thread-1',
          requestId: 'request-1',
        );

    expect(artifact, isNotNull);
    expect(artifact!.kind, GeneratedArtifactKind.pdf);
    expect(artifact.status, GeneratedArtifactStatus.ready);
    expect(artifact.fileName, endsWith('.pdf'));
    expect(artifact.previewRows.first, ['Section', 'Type', 'Items']);
    expect(
      artifact.previewRows.map((row) => row.join(' / ')),
      contains(contains('Pages')),
    );
    expect(
      artifact.previewRows.map((row) => row.join(' / ')),
      contains(contains('Recommendations')),
    );
    expect(File(artifact.filePath).existsSync(), isTrue);
    final bytes = File(artifact.filePath).readAsBytesSync();
    expect(String.fromCharCodes(bytes.take(8).toList()), startsWith('%PDF-1.'));
    final pdfText = String.fromCharCodes(bytes);
    expect(pdfText, contains('/Type /Catalog'));
    expect(pdfText, contains('/Type /Page'));
    expect(pdfText, contains('/Info 6 0 R'));
    expect(pdfText, contains('/Title (Campus Refresh Handoff)'));
    expect(pdfText, contains('CircuitCode customer handoff report'));
    expect(pdfText, contains('Campus Refresh Handoff'));
    expect(pdfText, contains('Report Overview'));
    expect(pdfText, contains('Executive Decision Brief'));
    expect(pdfText, contains('Document Map'));
    expect(pdfText, contains('Validation Checklist'));
    expect(pdfText, contains('/Keywords'));
    expect(pdfText, contains('Access layer needs multigig validation'));
    expect(pdfText, contains('Sources / Evidence'));
    expect(pdfText, contains('Workshop notes'));
    expect(pdfText, contains('CircuitCode - Generated artifact'));
    expect(pdfText, contains('Page 1 of'));
    expect(pdfText, contains(' re S'));
  });

  test('topology prompt creates a real SVG diagram artifact', () async {
    final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
    addTearDown(() => root.delete(recursive: true));
    final artifact = await const GeneratedArtifactWriter()
        .writeFromAssistantOutput(
          rootPath: root.path,
          prompt: 'create a topology diagram for three branches',
          content: '''
# Branch WAN Topology

```mermaid
graph LR
  HQ[Headquarters] -->|dual WAN| BR1[Branch 1]
  HQ -->|dual WAN| BR2[Branch 2]
  HQ -->|dual WAN| BR3[Branch 3]
```

## Assumptions
- Branches use redundant WAN links.
''',
          turnId: 'turn-diagram',
          threadId: 'thread-1',
          requestId: 'request-1',
        );

    expect(artifact, isNotNull);
    expect(artifact!.kind, GeneratedArtifactKind.diagram);
    expect(artifact.status, GeneratedArtifactStatus.ready);
    expect(artifact.fileName, endsWith('.svg'));
    expect(artifact.summary, contains('SVG topology diagram'));
    expect(artifact.previewRows.first, ['From', 'To', 'Label']);
    expect(File(artifact.filePath).existsSync(), isTrue);
    final svg = File(artifact.filePath).readAsStringSync();
    expect(svg, startsWith('<svg'));
    expect(svg, contains('Branch WAN Topology'));
    expect(svg, contains('Headquarters'));
    expect(svg, contains('Branch 1'));
    expect(svg, contains('dual WAN'));
  });

  test('topology prose creates a tiered enterprise network SVG', () async {
    final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
    addTearDown(() => root.delete(recursive: true));
    final artifact = await const GeneratedArtifactWriter()
        .writeFromAssistantOutput(
          rootPath: root.path,
          prompt: 'create a topology diagram for this Cisco campus',
          content: '''
# Cisco Campus Topology

Customer has 3 branches, dual WAN, warm spare MX250 firewalls, 1 MDF with C9500 core switches,
3 IDFs with C9300-48P UPOE access switches, 90 CW9176 Wi-Fi 7 APs, and client devices.

## Assumptions
- Validate PoE budget before final model selection.
- Validate WAN handoff speeds at every branch.
''',
          turnId: 'turn-enterprise-diagram',
          threadId: 'thread-1',
          requestId: 'request-1',
        );

    expect(artifact, isNotNull);
    expect(artifact!.kind, GeneratedArtifactKind.diagram);
    expect(artifact.previewRows.first, ['From', 'To', 'Label']);
    expect(artifact.previewRows.expand((row) => row), contains('WAN / ISP'));
    expect(File(artifact.filePath).existsSync(), isTrue);
    final svg = File(artifact.filePath).readAsStringSync();
    expect(svg, contains('Logical topology'));
    expect(svg, contains('id="topology-summary"'));
    expect(svg, contains('id="topology-inventory"'));
    expect(svg, contains('id="topology-validation"'));
    expect(svg, contains('WAN / Cloud'));
    expect(svg, contains('Security Edge'));
    expect(svg, contains('MDF / Core'));
    expect(svg, contains('IDF / Access'));
    expect(svg, contains('Wireless / Clients'));
    expect(svg, contains('MX250'));
    expect(svg, contains('C9500'));
    expect(svg, contains('C9300'));
    expect(svg, contains('CW9176'));
    expect(svg, contains('Dual WAN + HA'));
    expect(svg, contains('PoE/UPOE'));
    expect(svg, contains('Wi-Fi 7'));
    expect(svg, contains('&quot;siteCount&quot;:4'));
    expect(svg, contains('&quot;idfCount&quot;:3'));
    expect(svg, contains('&quot;accessSwitchCount&quot;:3'));
    expect(svg, contains('&quot;apCount&quot;:90'));
    expect(svg, contains('Assumptions'));
    expect(svg, contains('Validate PoE budget'));
  });

  test(
    'chart prompt creates a real SVG chart artifact from table data',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
      addTearDown(() => root.delete(recursive: true));
      final artifact = await const GeneratedArtifactWriter()
          .writeFromAssistantOutput(
            rootPath: root.path,
            prompt: 'create a chart report for PoE budget risk',
            content: '''
# PoE Budget Risk

| Site | Watts Required | Risk |
| --- | ---: | --- |
| HQ | 7200 | Medium |
| Branch 1 | 2800 | Low |
| Branch 2 | 3900 | Medium |
| Branch 3 | 5100 | High |
''',
            turnId: 'turn-chart',
            threadId: 'thread-1',
            requestId: 'request-1',
          );

      expect(artifact, isNotNull);
      expect(artifact!.kind, GeneratedArtifactKind.chart);
      expect(artifact.status, GeneratedArtifactStatus.ready);
      expect(artifact.fileName, endsWith('.svg'));
      expect(artifact.summary, contains('SVG chart'));
      expect(artifact.previewRows.first, ['Metric', 'Watts Required']);
      expect(artifact.sheetCount, 1);
      expect(File(artifact.filePath).existsSync(), isTrue);
      final svg = File(artifact.filePath).readAsStringSync();
      expect(svg, startsWith('<svg'));
      expect(svg, contains('PoE Budget Risk'));
      expect(svg, contains('Branch 3'));
      expect(svg, contains('5100'));
    },
  );

  test('chart pack prompt creates enterprise multi-signal panels', () async {
    final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
    addTearDown(() => root.delete(recursive: true));
    final artifact = await const GeneratedArtifactWriter().writeFromAssistantOutput(
      rootPath: root.path,
      prompt:
          'create a chart pack for PoE budgets, WAN capacity, lifecycle risk, product comparison, cost, and roadmap',
      content: '''
# Enterprise Sizing Chart Pack

## PoE Budget

| Site | Watts Required | PoE Budget | Risk |
| --- | ---: | ---: | --- |
| MDF | 7200 | 9600 | Medium |
| IDF 1 | 5100 | 7400 | Low |
| IDF 2 | 6800 | 7400 | High |

## WAN Capacity

| Site | Mbps Required | WAN Mbps | Headroom |
| --- | ---: | ---: | ---: |
| HQ | 1800 | 2500 | 700 |
| Branch 1 | 600 | 1000 | 400 |
| Branch 2 | 850 | 1000 | 150 |

## Lifecycle Risk

| Product | Lifecycle Status | LDOS | Risk |
| --- | --- | --- | --- |
| AIR-AP2802I | End of Support | 2026 | High |
| C9300-48P | Active | 2029 | Review |
| CW9176I | Current | 2031 | Low |

## Product Comparison

| Model | Fit Score | Uplinks | Recommendation |
| --- | ---: | --- | --- |
| C9300X-48HX | 5 | 25G | Best UPOE access fit |
| C9400 | 3 | 100G | Use for chassis sites |
| MS355 | 4 | 40G | Cloud-managed fit |

## Cost Plan

| Option | TCO | License Cost | Risk |
| --- | ---: | ---: | --- |
| Campus refresh | 310000 | 62000 | Review |
| Cloud-managed access | 240000 | 48000 | Low |

## Deployment Roadmap

| Phase | Priority Score | Duration Weeks |
| --- | ---: | ---: |
| Discovery | 5 | 2 |
| Pilot | 4 | 4 |
| Rollout | 3 | 8 |
''',
      turnId: 'turn-chart-pack',
      threadId: 'thread-1',
      requestId: 'request-1',
    );

    expect(artifact, isNotNull);
    expect(artifact!.kind, GeneratedArtifactKind.chart);
    expect(artifact.status, GeneratedArtifactStatus.ready);
    expect(artifact.fileName, endsWith('.svg'));
    expect(artifact.summary, contains('chart pack'));
    expect(artifact.summary, contains('PoE/UPOE'));
    expect(artifact.summary, contains('Cost/TCO'));
    expect(artifact.summary, contains('Roadmap'));
    expect(artifact.sheetCount, greaterThanOrEqualTo(6));
    expect(artifact.previewRows.first, ['Chart', 'Signal', 'Data points']);
    expect(
      artifact.previewRows.any(
        (row) =>
            row.length == 3 &&
            row[0] == 'Cost Plan' &&
            row[1] == 'Cost/TCO' &&
            row[2] == '2',
      ),
      isTrue,
    );
    expect(
      artifact.previewRows.any(
        (row) =>
            row.length == 3 &&
            row[0] == 'Deployment Roadmap' &&
            row[1] == 'Roadmap' &&
            row[2] == '3',
      ),
      isTrue,
    );
    final svg = File(artifact.filePath).readAsStringSync();
    expect(svg, contains('PoE Budget'));
    expect(svg, contains('WAN Capacity'));
    expect(svg, contains('Lifecycle'));
    expect(svg, contains('Comparison'));
    expect(svg, contains('Cost/TCO'));
    expect(svg, contains('Roadmap'));
    expect(svg, contains('id="chart-summary"'));
    expect(svg, contains('id="chart-risk-legend"'));
    expect(svg, contains('&quot;highRiskCount&quot;'));
    expect(svg, contains('&quot;hasPoe&quot;'));
    expect(svg, contains('&quot;hasWan&quot;'));
    expect(svg, contains('&quot;hasLifecycle&quot;'));
    expect(svg, contains('&quot;hasCost&quot;'));
    expect(svg, contains('&quot;hasRoadmap&quot;'));
    expect(svg, contains('Compare required load'));
    expect(svg, contains('Compare demand'));
    expect(svg, contains('High=3'));
    expect(svg, contains('validated with current pricing'));
    expect(svg, contains('sequencing signals'));
    expect(svg, contains('C9300X-48HX'));
  });

  test('CSV prompt creates a CSV artifact from markdown table', () async {
    final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
    addTearDown(() => root.delete(recursive: true));
    final artifact = await const GeneratedArtifactWriter()
        .writeFromAssistantOutput(
          rootPath: root.path,
          prompt: 'create a CSV file from this',
          content: '''
| Product | Count |
| --- | ---: |
| C9300 | 6 |
| CW9176 | 90 |
''',
          turnId: 'turn-csv',
          threadId: 'thread-1',
          requestId: 'request-1',
        );

    expect(artifact, isNotNull);
    expect(artifact!.kind, GeneratedArtifactKind.csv);
    expect(artifact.status, GeneratedArtifactStatus.ready);
    expect(artifact.fileName, endsWith('.csv'));
    expect(File(artifact.filePath).readAsStringSync(), contains('C9300,6'));
  });

  test(
    'JSON prompt creates formatted JSON artifact when valid JSON is fenced',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
      addTearDown(() => root.delete(recursive: true));
      final artifact = await const GeneratedArtifactWriter()
          .writeFromAssistantOutput(
            rootPath: root.path,
            prompt: 'generate a JSON file',
            content: '''
```json
{"name":"Circuit","count":2}
```
''',
            turnId: 'turn-json',
            threadId: 'thread-1',
            requestId: 'request-1',
          );

      expect(artifact, isNotNull);
      expect(artifact!.kind, GeneratedArtifactKind.json);
      expect(
        File(artifact.filePath).readAsStringSync(),
        contains('"name": "Circuit"'),
      );
    },
  );

  test('artifact registry exposes the 15 priority artifact descriptors', () {
    const registry = ArtifactTypeRegistry();

    expect(ArtifactTypeRegistry.descriptors, hasLength(15));
    expect(
      registry.descriptorForKind(GeneratedArtifactKind.powerPoint)?.id,
      'powerpoint_deck',
    );
    expect(
      registry.descriptorForPrompt('make a topology diagram')?.id,
      'network_topology_diagram',
    );
    expect(
      registry.descriptorForPrompt('create a business case for Acme')?.id,
      'business_use_case_brief',
    );
    expect(
      registry.descriptorForPrompt('create an evidence pack')?.id,
      'evidence_pack',
    );
    expect(
      detectGeneratedArtifactKind('create a business case brief for Acme'),
      GeneratedArtifactKind.docx,
    );
    expect(
      detectGeneratedArtifactKind('create an evidence pack for this claim'),
      GeneratedArtifactKind.docx,
    );
    expect(
      detectGeneratedArtifactKind('create a JSON evidence pack'),
      GeneratedArtifactKind.json,
    );
    expect(
      isGeneratedArtifactRequest(
        'create a business case brief inline in chat without writing files',
      ),
      isFalse,
    );
    expect(
      registry.descriptorForPrompt('create a product comparison matrix')?.id,
      'product_comparison_matrix',
    );
    expect(
      registry.descriptorForPrompt('create an LDOS lifecycle report')?.id,
      'lifecycle_eox_report',
    );
    expect(
      registry.descriptorForPrompt('create a customer proposal report')?.id,
      'docx_report',
    );
    expect(
      registry.descriptorForPrompt('create an architecture review pack')?.id,
      'architecture_review_pack',
    );
    expect(
      registry.descriptorForPrompt('create an implementation plan')?.id,
      'implementation_plan',
    );
    expect(
      registry.descriptorForPrompt('create a post-work change summary')?.id,
      'change_summary_diff_report',
    );
    expect(
      registry
          .descriptorForPrompt('create a final customer handoff report')
          ?.id,
      'pdf_report',
    );
    expect(
      detectGeneratedArtifactKind('create a customer proposal report'),
      GeneratedArtifactKind.docx,
    );
    expect(
      detectGeneratedArtifactKind('create an architecture review pack'),
      GeneratedArtifactKind.docx,
    );
    expect(
      detectGeneratedArtifactKind('create an implementation plan'),
      GeneratedArtifactKind.docx,
    );
    expect(
      detectGeneratedArtifactKind('create a markdown report'),
      GeneratedArtifactKind.markdown,
    );
  });

  test('CSV artifacts can export to a real XLSX workbook', () async {
    final root = await Directory.systemTemp.createTemp(
      'circuit-artifact-export-',
    );
    addTearDown(() => root.delete(recursive: true));
    final source = await const GeneratedArtifactWriter()
        .writeFromAssistantOutput(
          rootPath: root.path,
          prompt: 'create a CSV file from this',
          content: '''
| Product | Count |
| --- | ---: |
| C9300 | 6 |
| CW9176 | 90 |
''',
          turnId: 'turn-csv',
          threadId: 'thread-1',
          requestId: 'request-1',
        );

    expect(source, isNotNull);
    expect(source!.kind, GeneratedArtifactKind.csv);

    final exported = await const GeneratedArtifactExporter().export(
      artifact: source,
      targetKind: GeneratedArtifactKind.excel,
    );

    expect(exported, isNotNull);
    expect(exported!.kind, GeneratedArtifactKind.excel);
    expect(exported.fileName, endsWith('.xlsx'));
    expect(File(exported.filePath).existsSync(), isTrue);
    expect(File(exported.filePath).readAsBytesSync().take(4), [
      0x50,
      0x4b,
      0x03,
      0x04,
    ]);
    expect(exported.previewRows.first, ['Product', 'Count']);
  });
}
