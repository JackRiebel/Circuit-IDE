import 'dart:io';

import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/services/artifact_type_registry.dart';
import 'package:circuit_ide/services/generated_artifact_exporter.dart';
import 'package:circuit_ide/services/generated_artifact_package_writer.dart';
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
      expect(artifact.metadata['deckType'], 'Customer proposal deck');
      expect(
        artifact.metadata['handoffStatus'],
        'Ready for stakeholder review',
      );
      expect(
        artifact.metadata['decisionAsk'],
        'Review the recommendation, confirm assumptions, and approve the next implementation step.',
      );
      expect(artifact.metadata['theme'], 'Dark');
      expect(artifact.metadata['slideCount'], artifact.sheetCount);
      expect(artifact.metadata['sectionCount'], greaterThanOrEqualTo(4));
      expect(artifact.metadata['tableCount'], 1);
      expect(artifact.metadata['assumptionCount'], 1);
      expect(artifact.metadata['citationCount'], 1);
      expect(artifact.metadata['agendaItems'], contains('Current State'));
      expect(
        artifact.metadata['slideFamilies'],
        containsAll(['Opening', 'Agenda', 'Decision snapshot']),
      );
      expect(artifact.metadata['tableCoverage'], '1 table packaged');
      expect(artifact.metadata['sourceCoverage'], '1 source item captured');
      expect(artifact.metadata['validationGapCount'], 0);
      expect(artifact.metadata['hasAgenda'], isTrue);
      expect(artifact.metadata['hasDecisionSnapshot'], isTrue);
      expect(artifact.metadata['hasRoadmap'], isTrue);
      expect(artifact.metadata['hasTableSlides'], isTrue);
      expect(artifact.metadata['hasSourcesSlide'], isTrue);
      expect(artifact.metadata['hasCustomerReadyDeck'], isTrue);
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
      expect(packageText, contains('Agenda step'));
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
      expect(packageText, contains('Recommendation card'));
      expect(packageText, contains('Roadmap timeline'));
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
    expect(artifact.sheetCount, greaterThanOrEqualTo(18));
    expect(artifact.metadata['artifact'], 'solution_sizing_workbook');
    expect(artifact.metadata['workbookKind'], 'solution_sizing');
    expect(artifact.metadata['sheetCount'], artifact.sheetCount);
    expect(artifact.metadata['sourceSheetCount'], 1);
    expect(artifact.metadata['requirementCount'], greaterThanOrEqualTo(4));
    expect(artifact.metadata['gateCount'], 6);
    expect(artifact.metadata['candidateCheckCount'], greaterThanOrEqualTo(3));
    expect(artifact.metadata['recommendationCount'], greaterThanOrEqualTo(2));
    expect(artifact.metadata['riskCount'], 5);
    expect(artifact.metadata['highRiskCount'], greaterThanOrEqualTo(2));
    expect(artifact.metadata['validationCheckCount'], 5);
    expect(artifact.metadata['assumptionCount'], 2);
    expect(artifact.metadata['hasSizingAudit'], isTrue);
    expect(artifact.metadata['sizingAuditCount'], 8);
    expect(artifact.metadata['sizingAuditScore'], greaterThanOrEqualTo(60));
    expect(artifact.metadata['sizingAuditReadyCount'], greaterThanOrEqualTo(4));
    expect(artifact.metadata['hasSourceEvidence'], isTrue);
    expect(artifact.metadata['hasAssumptionCoverage'], isTrue);
    expect(artifact.metadata['users'], '500');
    expect(artifact.metadata['accessPoints'], '90');
    expect(artifact.metadata['switches'], '6');
    expect(artifact.metadata['wan'], '2 Gbps');
    expect(artifact.metadata['growth'], '25%');
    expect(artifact.metadata['hasPoeBudget'], isTrue);
    expect(artifact.metadata['hasWanThroughput'], isTrue);
    expect(artifact.metadata['hasClosetPower'], isTrue);
    expect(artifact.metadata['hasCandidateValidation'], isTrue);
    expect(artifact.metadata['hasLifecycleValidation'], isTrue);
    expect(artifact.metadata['hasHighPowerApSignal'], isTrue);
    expect(artifact.metadata['hasMultigigSignal'], isTrue);
    expect(artifact.metadata['qualityStatus'], 'Customer ready');
    expect(artifact.metadata['qualityScore'], greaterThanOrEqualTo(90));
    expect(
      artifact.metadata['qualityGates'],
      containsAll([
        'File generated',
        'Native format ready',
        'Workbook sheets packaged',
        'Header and data rows detected',
      ]),
    );
    expect(artifact.metadata['qualityGaps'], isEmpty);
    expect(artifact.metadata['hasCustomerReadyArtifact'], isTrue);
    expect(artifact.previewRows.first, [
      'Executive Signal',
      'Current Value',
      'Sizing Interpretation',
      'Next Action',
    ]);
    final bytes = File(artifact.filePath).readAsBytesSync();
    expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
    final packageText = String.fromCharCodes(bytes);
    expect(packageText, contains('Executive Summary'));
    expect(packageText, contains('Requirements'));
    expect(packageText, contains('Sizing Inputs'));
    expect(packageText, contains('Site Distribution'));
    expect(packageText, contains('Capacity Model'));
    expect(packageText, contains('PoE Budget'));
    expect(packageText, contains('Closet Power Plan'));
    expect(packageText, contains('WAN Throughput'));
    expect(packageText, contains('HA Growth'));
    expect(packageText, contains('Licensing Support'));
    expect(packageText, contains('Sizing Audit'));
    expect(packageText, contains('Requirement Gates'));
    expect(packageText, contains('Candidate Validation'));
    expect(packageText, contains('Recommendations'));
    expect(packageText, contains('Implementation Sequence'));
    expect(packageText, contains('Risk Register'));
    expect(packageText, contains('Validation'));
    expect(packageText, contains('Assumptions'));
    expect(packageText, contains('Decision Summary'));
    expect(packageText, contains('Source 1'));
    expect(packageText, contains('500'));
    expect(packageText, contains('90'));
    expect(packageText, contains('2 Gbps'));
    expect(packageText, contains('inspected throughput'));
    expect(packageText, contains('mGig validation required'));
    expect(packageText, contains('Access switch shortlist'));
    expect(packageText, contains('Per access switch'));
    expect(packageText, contains('Licensing / Support Check'));
    expect(packageText, contains('Source evidence'));
    expect(packageText, contains('Decision readiness'));
    expect(packageText, contains('migration hint only'));
    expect(
      packageText,
      contains('False precision from incomplete customer data'),
    );
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
      expect(artifact.summary, contains('executive decision'));
      expect(artifact.sheetCount, greaterThanOrEqualTo(18));
      expect(artifact.previewRows.first, [
        'Decision Signal',
        'Current Answer',
        'Why It Matters',
        'Next Action',
      ]);
      final bytes = File(artifact.filePath).readAsBytesSync();
      expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
      final packageText = String.fromCharCodes(bytes);
      expect(packageText, contains('Executive Decision'));
      expect(packageText, contains('Comparison Matrix'));
      expect(packageText, contains('Decision Summary'));
      expect(packageText, contains('Fit Scoring'));
      expect(packageText, contains('Requirements'));
      expect(packageText, contains('Requirement Gates'));
      expect(packageText, contains('Hard Gate Evaluation'));
      expect(packageText, contains('Source Confidence'));
      expect(packageText, contains('Scored Shortlist'));
      expect(packageText, contains('Migration Suitability'));
      expect(packageText, contains('Lifecycle Runway'));
      expect(packageText, contains('Alternatives'));
      expect(packageText, contains('Replacement Cautions'));
      expect(packageText, contains('Implementation Impact'));
      expect(packageText, contains('Customer Talking Points'));
      expect(packageText, contains('Validation Checklist'));
      expect(packageText, contains('Sources Needed'));
      expect(packageText, contains('Assumptions'));
      expect(packageText, contains('Source 1'));
      expect(packageText, contains('C9300-48P'));
      expect(packageText, contains('Meraki MS355'));
      expect(packageText, contains('Wi-Fi 7'));
      expect(packageText, contains('UPOE'));
      expect(packageText, contains('suggestedMigrationPid'));
      expect(packageText, contains('Power / UPOE'));
      expect(packageText, contains('Multigig access'));
      expect(packageText, contains('hard-gate compliance'));
      expect(packageText, contains('Official datasheet'));
      expect(
        packageText,
        contains('Current candidate or suggestedMigrationPid comparator'),
      );
      expect(
        packageText,
        contains('Do not treat EoX replacement PID as the final best model'),
      );
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
    expect(artifact.summary, contains('executive risk'));
    expect(artifact.summary, contains('replacement readiness'));
    expect(artifact.sheetCount, greaterThanOrEqualTo(18));
    expect(artifact.previewRows.first, [
      'Decision Signal',
      'Current Answer',
      'Why It Matters',
      'Next Action',
    ]);
    final bytes = File(artifact.filePath).readAsBytesSync();
    expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
    final packageText = String.fromCharCodes(bytes);
    expect(packageText, contains('Executive Risk'));
    expect(packageText, contains('Lifecycle Status'));
    expect(packageText, contains('Urgency Timeline'));
    expect(packageText, contains('Migration Hints'));
    expect(packageText, contains('Replacement Evaluation'));
    expect(packageText, contains('Decision Gates'));
    expect(packageText, contains('Source Quality'));
    expect(packageText, contains('Official Date Evidence'));
    expect(packageText, contains('Date Authority'));
    expect(packageText, contains('Support Runway'));
    expect(packageText, contains('Replacement Suitability'));
    expect(packageText, contains('Current Portfolio Shortlist'));
    expect(packageText, contains('Migration Decision'));
    expect(packageText, contains('Replacement Readiness'));
    expect(packageText, contains('WiFi7 UPOE Readiness'));
    expect(packageText, contains('Customer Actions'));
    expect(packageText, contains('Risk Register'));
    expect(packageText, contains('Assumptions'));
    expect(packageText, contains('C9300-48P'));
    expect(packageText, contains('AIR-AP2802I'));
    expect(packageText, contains('CW9176I'));
    expect(packageText, contains('migration clue only'));
    expect(packageText, contains('suggestedMigrationPid'));
    expect(packageText, contains('checked date'));
    expect(packageText, contains('2026-06-30'));
    expect(packageText, contains('Highest lifecycle risk'));
    expect(packageText, contains('Official lifecycle dates'));
    expect(packageText, contains('Support runway at risk'));
    expect(packageText, contains('Migration hint only'));
    expect(
      packageText,
      contains('Do not recommend CW9176I unless sourced facts prove'),
    );
    expect(packageText, contains('suggestedMigrationPid only'));
    expect(packageText, contains('Replacement Gate'));
    expect(packageText, contains('Customer-ready action plan'));
    expect(packageText, contains('current portfolio comparison'));
    expect(packageText, contains('Current UPOE/mGig access switching family'));
    expect(packageText, contains('Current Wi-Fi 7 AP family'));
    expect(packageText, contains('EoX suggestedMigrationPid comparator'));
    expect(
      packageText,
      contains('Supersede if a current candidate has better requirement fit'),
    );
    expect(
      packageText,
      contains('Official datasheet/catalog capability facts'),
    );
    expect(
      packageText,
      contains('Rejected alternatives and final fit rationale'),
    );
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
      expect(artifact.metadata['artifact'], 'word_report');
      expect(artifact.metadata['reportType'], 'Architecture report');
      expect(
        artifact.metadata['handoffStatus'],
        'Ready for stakeholder review',
      );
      expect(
        artifact.metadata['decisionAsk'],
        'Review findings, confirm assumptions, and approve the recommended architecture path.',
      );
      expect(
        artifact.metadata['reviewPath'],
        'Architecture review -> risk validation -> implementation decision',
      );
      expect(
        artifact.metadata['documentParts'],
        containsAll([
          'Executive decision brief',
          'Recommendation summary',
          'Risk register',
          'Next-step action plan',
          'Document map',
          'Evidence confidence matrix',
          'Approval gates',
          'Validation checklist',
          'Data tables',
          'Assumptions appendix',
          'Sources appendix',
        ]),
      );
      expect(artifact.metadata['documentPartCount'], greaterThanOrEqualTo(11));
      expect(artifact.metadata['tableCoverage'], '1 table packaged');
      expect(artifact.metadata['evidenceCoverage'], '1 source item captured');
      expect(
        artifact.metadata['appendixCoverage'],
        '1 assumption, 1 source item in appendices',
      );
      expect(artifact.metadata['validationGapCount'], 0);
      expect(artifact.metadata['hasCustomerReadyReport'], isTrue);
      expect(artifact.metadata['sectionCount'], greaterThanOrEqualTo(4));
      expect(artifact.metadata['tableCount'], 1);
      expect(artifact.metadata['assumptionCount'], 1);
      expect(artifact.metadata['citationCount'], 1);
      expect(artifact.metadata['wordCount'], greaterThan(20));
      expect(artifact.metadata['paragraphCount'], greaterThan(10));
      expect(artifact.metadata['hasTableOfContents'], isTrue);
      expect(artifact.metadata['hasRiskRegister'], isTrue);
      expect(artifact.metadata['hasSourcesAppendix'], isTrue);
      expect(File(artifact.filePath).existsSync(), isTrue);
      final bytes = File(artifact.filePath).readAsBytesSync();
      expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
      final packageText = String.fromCharCodes(bytes);
      expect(packageText, contains('word/document.xml'));
      expect(packageText, contains('word/styles.xml'));
      expect(packageText, contains('word/numbering.xml'));
      expect(packageText, contains('word/settings.xml'));
      expect(packageText, contains('word/header1.xml'));
      expect(packageText, contains('word/footer1.xml'));
      expect(packageText, contains('Branch Network Architecture Report'));
      expect(packageText, contains('CircuitCode generated report'));
      expect(packageText, contains('Table of Contents'));
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

  test('implementation plan prompt creates a shaped DOCX artifact', () async {
    final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
    addTearDown(() => root.delete(recursive: true));
    final artifact = await const GeneratedArtifactWriter()
        .writeFromAssistantOutput(
          rootPath: root.path,
          prompt:
              'create an implementation plan for the artifact workspace upgrade',
          content: '''
# Artifact Workspace Implementation Plan

Build the next artifact platform pass with reviewable batches and strong verification.

## Scope
- Add artifact composer templates for implementation plans.
- Keep Studio outcome-focused and avoid transcript noise.

## Workstreams
- Create implementation plan DOCX/PDF/deck outputs.
- Add drawer metadata and review previews.
- Preserve existing plan, patch, approval, and context flows.

## Phases
- Inspect current artifact writer and registry.
- Implement the template builder.
- Add focused tests and run verification.

## Dependencies
- Current artifact writer and DOCX/PDF/PPTX renderers.
- Workspace output directory.
- Reviewer approval for generated customer-facing plans.

## Verification
- Confirm generated file exists and parses as an Office package.
- Confirm preview metadata lists implementation sections.
- Confirm artifact card summary names the implementation plan.

## Rollback
- Restore the prior commit or remove the generated artifact template.

## Assumptions
- Existing artifact renderers remain the output engine.

## Sources
- CircuitCode artifact platform plan
''',
          turnId: 'turn-implementation-plan',
          threadId: 'thread-1',
          requestId: 'request-1',
        );

    expect(artifact, isNotNull);
    expect(artifact!.kind, GeneratedArtifactKind.docx);
    expect(artifact.status, GeneratedArtifactStatus.ready);
    expect(artifact.fileName, endsWith('.docx'));
    expect(artifact.summary, contains('implementation plan'));
    expect(artifact.summary, contains('workstreams'));
    expect(artifact.summary, contains('verification'));
    expect(artifact.sheetCount, greaterThanOrEqualTo(10));
    expect(
      artifact.previewRows.map((row) => row.join(' / ')),
      contains(contains('Implementation Overview')),
    );
    expect(
      artifact.previewRows.map((row) => row.join(' / ')),
      contains(contains('Verification Plan')),
    );
    expect(File(artifact.filePath).existsSync(), isTrue);
    final bytes = File(artifact.filePath).readAsBytesSync();
    expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
    final packageText = String.fromCharCodes(bytes);
    expect(packageText, contains('word/document.xml'));
    expect(packageText, contains('Artifact Workspace Implementation Plan'));
    expect(packageText, contains('Implementation Overview'));
    expect(packageText, contains('Scope And Success Criteria'));
    expect(packageText, contains('Workstreams And Deliverables'));
    expect(packageText, contains('Implementation Phases'));
    expect(packageText, contains('Dependencies And Inputs'));
    expect(packageText, contains('Verification Plan'));
    expect(packageText, contains('Rollback And Recovery'));
    expect(packageText, contains('Approval And Handoff Gates'));
    expect(packageText, contains('Implementation Decision Brief'));
    expect(packageText, contains('Phase Execution Plan'));
    expect(packageText, contains('Workstream And Artifact Matrix'));
    expect(packageText, contains('Dependency Register'));
    expect(packageText, contains('Rollback And Risk Register'));
    expect(packageText, contains('Approval Gates'));
    expect(packageText, contains('Plan approval'));
    expect(packageText, contains('Confirm generated file exists'));
    expect(packageText, contains('Patch or artifact review'));
  });

  test(
    'implementation plan prompt shapes PowerPoint and PDF artifacts',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
      addTearDown(() => root.delete(recursive: true));
      const content = '''
# Artifact Workspace Delivery Plan

Implementation plan for a customer-ready artifact workspace.

## Scope
- Create polished deliverables from structured content.
- Keep artifact application app-owned.

## Phases
- Build templates.
- Validate generated artifacts.
- Rebuild and hand off.

## Verification
- Inspect PowerPoint slide count.
- Inspect PDF page count.

## Sources
- Internal artifact roadmap
''';

      final deck = await const GeneratedArtifactWriter()
          .writeFromAssistantOutput(
            rootPath: root.path,
            prompt: 'create a PowerPoint implementation plan deck',
            content: content,
            turnId: 'turn-implementation-plan-deck',
            threadId: 'thread-1',
            requestId: 'request-1',
          );
      final pdf = await const GeneratedArtifactWriter()
          .writeFromAssistantOutput(
            rootPath: root.path,
            prompt: 'create a PDF implementation plan',
            content: content,
            turnId: 'turn-implementation-plan-pdf',
            threadId: 'thread-1',
            requestId: 'request-1',
          );

      expect(deck, isNotNull);
      expect(deck!.kind, GeneratedArtifactKind.powerPoint);
      expect(deck.fileName, endsWith('.pptx'));
      expect(deck.summary, contains('implementation plan PowerPoint deck'));
      expect(deck.sheetCount, greaterThanOrEqualTo(10));
      final deckText = String.fromCharCodes(
        File(deck.filePath).readAsBytesSync(),
      );
      expect(deckText, contains('Implementation Phases'));
      expect(deckText, contains('Scope And Success Criteria'));
      expect(deckText, contains('Approval And Handoff Gates'));
      expect(deckText, contains('Agenda step'));
      expect(deckText, contains('Recommendation card'));
      expect(deckText, contains('Roadmap timeline'));

      expect(pdf, isNotNull);
      expect(pdf!.kind, GeneratedArtifactKind.pdf);
      expect(pdf.fileName, endsWith('.pdf'));
      expect(pdf.summary, contains('implementation plan PDF'));
      expect(pdf.sheetCount, greaterThanOrEqualTo(1));
      final pdfText = String.fromCharCodes(
        File(pdf.filePath).readAsBytesSync(),
      );
      expect(pdfText, startsWith('%PDF-1.'));
      expect(pdfText, contains('Implementation Overview'));
      expect(pdfText, contains('Verification Checklist'));
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
    expect(artifact.summary, contains('executive decision snapshot'));
    expect(artifact.summary, contains('solution mapping'));
    expect(artifact.summary, contains('account motion'));
    expect(artifact.summary, contains('objection handling'));
    expect(artifact.sheetCount, greaterThanOrEqualTo(9));
    expect(File(artifact.filePath).existsSync(), isTrue);
    final bytes = File(artifact.filePath).readAsBytesSync();
    expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
    final packageText = String.fromCharCodes(bytes);
    expect(packageText, contains('word/document.xml'));
    expect(packageText, contains('Acme Manufacturing Business Use Case Brief'));
    expect(packageText, contains('Executive Summary'));
    expect(packageText, contains('Executive Decision Brief'));
    expect(packageText, contains('Buying Triggers And Timing'));
    expect(packageText, contains('Value Metrics And ROI'));
    expect(packageText, contains('Priority Use Cases'));
    expect(packageText, contains('Stakeholders And Workflows'));
    expect(packageText, contains('Evidence And Confidence'));
    expect(packageText, contains('Customer Discovery Questions'));
    expect(packageText, contains('Value And Impact'));
    expect(packageText, contains('Executive Decision Snapshot'));
    expect(packageText, contains('Use Case Prioritization Matrix'));
    expect(packageText, contains('Value Metrics Plan'));
    expect(packageText, contains('Solution Mapping'));
    expect(packageText, contains('Stakeholder Discovery Map'));
    expect(packageText, contains('Account Motion Plan'));
    expect(packageText, contains('Evidence And Confidence Register'));
    expect(packageText, contains('Objection And Risk Handling'));
    expect(packageText, contains('30 / 60 / 90 Day Action Plan'));
    expect(packageText, contains('Stakeholder Readout'));
    expect(packageText, contains('Evidence Confidence Matrix'));
    expect(packageText, contains('Approval Gates'));
    expect(packageText, contains('Predictive maintenance telemetry'));
    expect(packageText, contains('Operations leader / plant manager'));
    expect(packageText, contains('Business sponsor and technical owner'));
    expect(packageText, contains('Executive sponsor + workflow owner'));
    expect(packageText, contains('Evidence pack, value metrics plan'));
    expect(packageText, contains('Reduce unplanned downtime exposure'));
    expect(packageText, contains('Discovery question'));
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
- Industry analyst report — checked 2026-06-30 — https://example.com/report

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
    expect(packageText, contains('Executive Evidence Decision'));
    expect(packageText, contains('Evidence Summary'));
    expect(packageText, contains('Claim Register'));
    expect(packageText, contains('Source Inventory'));
    expect(packageText, contains('Citation Quality Rules'));
    expect(packageText, contains('Checked Dates'));
    expect(packageText, contains('Confidence And Risk'));
    expect(packageText, contains('Unsupported Claims / Follow-Up'));
    expect(packageText, contains('Claim To Source Matrix'));
    expect(packageText, contains('Citation Authority Register'));
    expect(packageText, contains('Source Freshness Register'));
    expect(packageText, contains('Unsupported Claim Triage'));
    expect(packageText, contains('Evidence Confidence Scorecard'));
    expect(packageText, contains('Customer-Ready Claim Gates'));
    expect(packageText, contains('Customer Follow-Up Checklist'));
    expect(packageText, contains('Stakeholder Readout'));
    expect(packageText, contains('Evidence Confidence Matrix'));
    expect(packageText, contains('Approval Gates'));
    expect(packageText, contains('Authority tier'));
    expect(packageText, contains('Customer-ready use'));
    expect(packageText, contains('Use with checked-date citation'));
    expect(packageText, contains('Use as context, not final proof'));
    expect(packageText, contains('Supporting source'));
    expect(packageText, contains('Freshness risk'));
    expect(packageText, contains('Required evidence'));
    expect(packageText, contains('Validate current portfolio fit'));
    expect(packageText, contains('Verify, qualify, rewrite, or remove'));
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
      expect(jsonText, contains('"Citation Authority Register"'));
      expect(jsonText, contains('"Source Freshness Register"'));
      expect(jsonText, contains('"Customer-Ready Claim Gates"'));
      expect(jsonText, contains('"Evidence Confidence Scorecard"'));
      expect(jsonText, contains('"Executive Evidence Decision"'));
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
      contains(contains('PDF Bookmarks')),
    );
    expect(
      artifact.previewRows.map((row) => row.join(' / ')),
      contains(contains('Recommendations')),
    );
    expect(artifact.metadata['artifact'], 'pdf_report');
    expect(artifact.metadata['reportType'], 'Architecture report');
    expect(artifact.metadata['audience'], 'Architecture reviewers');
    expect(
      artifact.metadata['reportPurpose'],
      'Review findings, risks, and recommendations',
    );
    expect(artifact.metadata['handoffStatus'], 'Ready for stakeholder review');
    expect(
      artifact.metadata['decisionOwner'],
      'Architecture owner / customer sponsor',
    );
    expect(
      artifact.metadata['decisionAsk'],
      'Review findings, confirm assumptions, and approve the recommended architecture path.',
    );
    expect(
      artifact.metadata['reviewPath'],
      'Architecture review -> risk validation -> implementation decision',
    );
    expect(
      artifact.metadata['documentParts'],
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
        'Data tables',
        'Assumptions appendix',
        'Sources appendix',
      ]),
    );
    expect(artifact.metadata['documentPartCount'], greaterThanOrEqualTo(11));
    expect(artifact.metadata['handoffScore'], 100);
    expect(
      artifact.metadata['handoffReadinessLevel'],
      'Customer handoff ready',
    );
    expect(artifact.metadata['handoffScorecardItemCount'], 5);
    expect(artifact.metadata['decisionLogCount'], 4);
    expect(artifact.metadata['tableCoverage'], '1 table packaged');
    expect(artifact.metadata['evidenceCoverage'], '1 source item captured');
    expect(
      artifact.metadata['appendixCoverage'],
      '1 assumption, 1 source item in appendices',
    );
    expect(artifact.metadata['validationGapCount'], 0);
    expect(artifact.metadata['pageCount'], artifact.sheetCount);
    expect(artifact.metadata['bookmarkCount'], greaterThanOrEqualTo(3));
    expect(artifact.metadata['reportSectionCount'], greaterThanOrEqualTo(12));
    expect(artifact.metadata['sectionCount'], greaterThanOrEqualTo(4));
    expect(artifact.metadata['tableCount'], 1);
    expect(artifact.metadata['assumptionCount'], 1);
    expect(artifact.metadata['citationCount'], 1);
    expect(artifact.metadata['evidenceGapCount'], 0);
    expect(
      artifact.metadata['readinessSignals'],
      containsAll([
        'Decision brief',
        'Recommendation summary',
        'Risk register',
        'Next steps',
        'Validation checklist',
        'Customer handoff scorecard',
        'Decision log',
        'Data tables',
        'Assumptions',
        'Sources',
      ]),
    );
    expect(artifact.metadata['hasOutline'], isTrue);
    expect(artifact.metadata['hasDocumentMap'], isTrue);
    expect(artifact.metadata['hasEvidenceConfidenceMatrix'], isTrue);
    expect(artifact.metadata['hasApprovalGates'], isTrue);
    expect(artifact.metadata['hasValidationChecklist'], isTrue);
    expect(artifact.metadata['hasCustomerHandoffScorecard'], isTrue);
    expect(artifact.metadata['hasDecisionLog'], isTrue);
    expect(artifact.metadata['hasSourcesAppendix'], isTrue);
    expect(artifact.metadata['hasCustomerReadyPackage'], isTrue);
    expect(artifact.metadata['hasCustomerReadyPdf'], isTrue);
    expect(File(artifact.filePath).existsSync(), isTrue);
    final bytes = File(artifact.filePath).readAsBytesSync();
    expect(String.fromCharCodes(bytes.take(8).toList()), startsWith('%PDF-1.'));
    final pdfText = String.fromCharCodes(bytes);
    expect(pdfText, contains('/Type /Catalog'));
    expect(pdfText, contains('/PageMode /UseOutlines'));
    expect(pdfText, contains('/Type /Outlines'));
    expect(pdfText, contains('/Title (Report Overview)'));
    expect(pdfText, contains('/Title (Executive Decision Brief)'));
    expect(pdfText, contains('/Title (Validation Checklist)'));
    expect(pdfText, contains('/Type /Page'));
    expect(pdfText, contains('/Info 6 0 R'));
    expect(pdfText, contains('/Title (Campus Refresh Handoff)'));
    expect(pdfText, contains('CircuitCode customer handoff report'));
    expect(pdfText, contains('Campus Refresh Handoff'));
    expect(pdfText, contains('Report Overview'));
    expect(pdfText, contains('Executive Decision Brief'));
    expect(pdfText, contains('Document Map'));
    expect(pdfText, contains('Stakeholder Readout'));
    expect(pdfText, contains('Evidence Confidence Matrix'));
    expect(pdfText, contains('Approval Gates'));
    expect(pdfText, contains('Validation Checklist'));
    expect(pdfText, contains('Customer Handoff Scorecard'));
    expect(pdfText, contains('Decision Log'));
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
    expect(artifact.previewRows.first, ['Signal', 'Value', 'Guidance']);
    expect(artifact.previewRows.expand((row) => row), contains('Topology'));
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
    expect(artifact.previewRows.first, ['Signal', 'Value', 'Guidance']);
    expect(artifact.previewRows.expand((row) => row), contains('AP power'));
    expect(artifact.previewRows.expand((row) => row), contains('2700W est.'));
    expect(artifact.metadata['topologyType'], 'Multi-site topology');
    expect(
      artifact.metadata['handoffStatus'],
      'Draft - validate topology inputs',
    );
    expect(artifact.metadata['resiliencyModel'], 'Dual WAN + HA');
    expect(
      artifact.metadata['designZones'],
      containsAll([
        'Sites',
        'WAN / Cloud',
        'Security Edge',
        'MDF / Core',
        'IDF / Access',
        'Wireless / Clients',
      ]),
    );
    expect(artifact.metadata['nodeCount'], greaterThanOrEqualTo(6));
    expect(artifact.metadata['accessPortCount'], 144);
    expect(artifact.metadata['estimatedApPowerWatts'], 2700);
    expect(
      artifact.metadata['readinessSignals'],
      containsAll(['Redundancy', 'Power', 'Evidence']),
    );
    expect(artifact.metadata['validationGaps'], contains('Uplinks'));
    expect(artifact.metadata['validationGapCount'], greaterThanOrEqualTo(1));
    expect(artifact.metadata['hasDeviceInventory'], isTrue);
    expect(artifact.metadata['hasLinkSchedule'], isTrue);
    expect(artifact.metadata['hasCapacityChecks'], isTrue);
    expect(artifact.metadata['hasReadinessScorecard'], isTrue);
    expect(artifact.metadata['hasFailureDomainReview'], isTrue);
    expect(artifact.metadata['failureDomainCount'], 5);
    expect(
      artifact.metadata['criticalFailureDomainCount'],
      greaterThanOrEqualTo(1),
    );
    expect(
      artifact.metadata['validationGaps'],
      contains('Failure domain: MDF / Core'),
    );
    expect(artifact.metadata['hasCustomerReadyTopology'], isFalse);
    expect(File(artifact.filePath).existsSync(), isTrue);
    final svg = File(artifact.filePath).readAsStringSync();
    expect(svg, contains('Logical topology'));
    expect(svg, contains('id="topology-summary"'));
    expect(svg, contains('id="topology-failure-domains"'));
    expect(svg, contains('id="topology-design-zones"'));
    expect(svg, contains('id="topology-link-schedule"'));
    expect(svg, contains('id="topology-readiness"'));
    expect(svg, contains('id="topology-capacity"'));
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
    expect(svg, contains('Capacity checks'));
    expect(svg, contains('Failure-domain review'));
    expect(svg, contains('WAN edge'));
    expect(svg, contains('Security edge'));
    expect(svg, contains('MDF / Core'));
    expect(svg, contains('2700W est.'));
    expect(svg, contains('90/144 AP ports'));
    expect(svg, contains('&quot;siteCount&quot;:4'));
    expect(svg, contains('&quot;idfCount&quot;:3'));
    expect(svg, contains('&quot;accessSwitchCount&quot;:3'));
    expect(svg, contains('&quot;apCount&quot;:90'));
    expect(svg, contains('&quot;accessPortCount&quot;:144'));
    expect(svg, contains('&quot;estimatedApPowerWatts&quot;:2700'));
    expect(svg, contains('&quot;failureDomainCount&quot;:5'));
    expect(
      svg,
      contains('&quot;topologyType&quot;:&quot;Multi-site topology&quot;'),
    );
    expect(
      svg,
      contains('&quot;resiliencyModel&quot;:&quot;Dual WAN + HA&quot;'),
    );
    expect(svg, contains('&quot;validationGapCount&quot;:'));
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
      expect(artifact.metadata['artifact'], 'chart_pack');
      expect(
        artifact.metadata['chartPackType'],
        'Capacity planning chart pack',
      );
      expect(
        artifact.metadata['handoffStatus'],
        'Review required - high risk signals',
      );
      expect(
        artifact.metadata['decisionPurpose'],
        'Capacity validation and sizing support',
      );
      expect(artifact.metadata['chartCount'], 1);
      expect(artifact.metadata['pointCount'], 4);
      expect(artifact.metadata['hasPoe'], isTrue);
      expect(artifact.metadata['chartFamilies'], contains('PoE Budget'));
      expect(artifact.metadata['readinessSignals'], contains('Source data'));
      expect(artifact.metadata['validationGateCount'], 4);
      expect(artifact.metadata['validationGapCount'], greaterThanOrEqualTo(1));
      expect(
        artifact.metadata['recommendedActionCount'],
        greaterThanOrEqualTo(1),
      );
      expect(artifact.metadata['hasDecisionMatrix'], isTrue);
      expect(artifact.metadata['decisionActionCount'], greaterThanOrEqualTo(1));
      expect(
        artifact.metadata['decisionOwners'],
        contains('Network architect'),
      );
      expect(File(artifact.filePath).existsSync(), isTrue);
      final svg = File(artifact.filePath).readAsStringSync();
      expect(svg, startsWith('<svg'));
      expect(svg, contains('PoE Budget Risk'));
      expect(svg, contains('Decision matrix'));
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
    expect(artifact.metadata['artifact'], 'chart_pack');
    expect(
      artifact.metadata['chartPackType'],
      'Enterprise readiness chart pack',
    );
    expect(
      artifact.metadata['handoffStatus'],
      'Review required - high risk signals',
    );
    expect(
      artifact.metadata['decisionPurpose'],
      'Capacity and lifecycle decision support',
    );
    expect(artifact.metadata['chartCount'], 6);
    expect(artifact.metadata['pointCount'], 17);
    expect(artifact.metadata['highRiskCount'], greaterThanOrEqualTo(1));
    expect(artifact.metadata['mediumRiskCount'], greaterThanOrEqualTo(2));
    expect(artifact.metadata['lowRiskCount'], greaterThanOrEqualTo(2));
    expect(artifact.metadata['hasPoe'], isTrue);
    expect(artifact.metadata['hasWan'], isTrue);
    expect(artifact.metadata['hasLifecycle'], isTrue);
    expect(artifact.metadata['hasComparison'], isTrue);
    expect(artifact.metadata['hasCost'], isTrue);
    expect(artifact.metadata['hasRoadmap'], isTrue);
    expect(
      artifact.metadata['signals'],
      containsAll(['PoE/UPOE', 'WAN capacity', 'Lifecycle']),
    );
    expect(
      artifact.metadata['chartFamilies'],
      containsAll(['PoE Budget', 'WAN Capacity', 'Lifecycle Risk']),
    );
    expect(
      artifact.metadata['readinessSignals'],
      containsAll(['Source data', 'Risk labels', 'Capacity signals']),
    );
    expect(artifact.metadata['validationGapCount'], 0);
    expect(artifact.metadata['hasDecisionMatrix'], isTrue);
    expect(artifact.metadata['decisionActionCount'], greaterThanOrEqualTo(5));
    expect(artifact.metadata['criticalDecisionCount'], greaterThanOrEqualTo(3));
    expect(
      artifact.metadata['decisionOwners'],
      containsAll([
        'Executive / technical owner',
        'Network architect',
        'Lifecycle owner',
        'SE / account team',
        'Project owner',
      ]),
    );
    expect(artifact.metadata['hasCustomerReadyChartPack'], isFalse);
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
    expect(svg, contains('id="chart-executive-insights"'));
    expect(svg, contains('id="chart-validation-gates"'));
    expect(svg, contains('id="chart-recommended-actions"'));
    expect(svg, contains('id="chart-decision-matrix"'));
    expect(svg, contains('id="chart-risk-legend"'));
    expect(svg, contains('&quot;highRiskCount&quot;'));
    expect(svg, contains('&quot;insightCount&quot;'));
    expect(svg, contains('&quot;validationGateCount&quot;'));
    expect(svg, contains('&quot;recommendedActionCount&quot;'));
    expect(svg, contains('&quot;decisionActionCount&quot;'));
    expect(svg, contains('&quot;criticalDecisionCount&quot;'));
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
    expect(svg, contains('Decision matrix'));
    expect(svg, contains('Risk ownership'));
    expect(svg, contains('Lifecycle evidence'));
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

  test('change summary prompt creates a shaped DOCX artifact', () async {
    final root = await Directory.systemTemp.createTemp(
      'circuit-change-summary-',
    );
    addTearDown(() => root.delete(recursive: true));
    final artifact = await const GeneratedArtifactWriter()
        .writeFromAssistantOutput(
          rootPath: root.path,
          prompt: 'create a post-work change summary / diff report',
          content: '''
# CircuitCode Artifact Workspace Change Summary

Implemented artifact workspace improvements and rebuilt the desktop app.

## Files changed
- lib/services/generated_artifact_writer.dart (+42 -3)
- lib/services/implementation_plan_artifact_builder.dart (+280 -0)
- test/generated_artifact_writer_test.dart (+90 -0)

## Verification
- flutter analyze passed
- git diff --check passed
- flutter test passed
- flutter build macos passed

## Commands run
- flutter analyze
- git diff --check
- flutter test
- flutter build macos

## Checkpoint
- Commit 97aaf55 Add implementation plan artifact builder

## Risks
- Need live smoke test with real user prompt.

## Next steps
- Add change summary / diff report artifact depth.

## Sources
- Local git diff
- Test output
''',
          turnId: 'turn-change-summary',
          threadId: 'thread-1',
          requestId: 'request-1',
        );

    expect(artifact, isNotNull);
    expect(artifact!.kind, GeneratedArtifactKind.docx);
    expect(artifact.status, GeneratedArtifactStatus.ready);
    expect(artifact.fileName, endsWith('.docx'));
    expect(artifact.summary, contains('change summary / diff report'));
    expect(artifact.summary, contains('verification'));
    final bytes = File(artifact.filePath).readAsBytesSync();
    expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
    final packageText = String.fromCharCodes(bytes);
    expect(packageText, contains('Change Outcome Summary'));
    expect(packageText, contains('Changed File Inventory'));
    expect(packageText, contains('Verification Result Matrix'));
    expect(packageText, contains('Command Run Log'));
    expect(packageText, contains('Checkpoint Register'));
    expect(packageText, contains('Open Risk And Follow-Up Register'));
    expect(
      packageText,
      contains('lib/services/generated_artifact_writer.dart'),
    );
    expect(packageText, contains('flutter analyze'));
    expect(packageText, contains('flutter test'));
    expect(packageText, contains('97aaf55'));
    expect(packageText, contains('live smoke test'));
  });

  test('change summary prompt can create a PDF handoff report', () async {
    final root = await Directory.systemTemp.createTemp(
      'circuit-change-summary-pdf-',
    );
    addTearDown(() => root.delete(recursive: true));
    final artifact = await const GeneratedArtifactWriter()
        .writeFromAssistantOutput(
          rootPath: root.path,
          prompt: 'create a PDF post-work change summary',
          content: '''
# Post-work summary

Edited files:
- lib/services/generated_artifact_writer.dart (+12 -1)

Verification:
- flutter analyze passed
- flutter test passed

Checkpoint:
- checkpoint abc1234
''',
          turnId: 'turn-change-summary-pdf',
          threadId: 'thread-1',
          requestId: 'request-1',
        );

    expect(artifact, isNotNull);
    expect(artifact!.kind, GeneratedArtifactKind.pdf);
    expect(artifact.status, GeneratedArtifactStatus.ready);
    expect(artifact.fileName, endsWith('.pdf'));
    expect(artifact.summary, contains('change summary / diff report PDF'));
    final text = String.fromCharCodes(
      File(artifact.filePath).readAsBytesSync(),
    );
    expect(text, startsWith('%PDF-1.'));
    expect(text, contains('Change Outcome Summary'));
    expect(text, contains('Changed File Inventory'));
    expect(text, contains('Verification Result Matrix'));
  });

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
      detectGeneratedArtifactKind('create a post-work change summary'),
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

  test(
    'business case package creates DOCX, deck, and chart artifacts',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-artifact-package-',
      );
      addTearDown(() => root.delete(recursive: true));

      final package = await const GeneratedArtifactPackageWriter()
          .writePackageFromAssistantOutput(
            rootPath: root.path,
            prompt: 'create a business case package for Acme manufacturing',
            content: '''
# Acme Manufacturing Business Case

## Executive Summary
Acme can reduce plant downtime and improve operational visibility by
modernizing access switching, wireless telemetry, and lifecycle reporting.

## Use Cases
- Reduce troubleshooting time for plant-floor incidents.
- Prioritize lifecycle refreshes before LDOS risk becomes urgent.
- Give executives a simple scorecard for resiliency and support exposure.

## Business Impact
| Initiative | Annual Value | Confidence |
| --- | ---: | ---: |
| Downtime reduction | 240000 | 0.8 |
| Support consolidation | 85000 | 0.7 |

## Sources
- Customer workshop notes checked 2026-07-01.
''',
            turnId: 'turn-business',
            threadId: 'thread-1',
            requestId: 'request-1',
          );

      expect(package, isNotNull);
      expect(package!.label, 'business use case package');
      expect(package.artifacts.map((artifact) => artifact.kind), [
        GeneratedArtifactKind.markdown,
        GeneratedArtifactKind.docx,
        GeneratedArtifactKind.powerPoint,
        GeneratedArtifactKind.chart,
      ]);
      expect(
        package.artifacts.map((artifact) => artifact.id).toSet().length,
        4,
      );
      for (final artifact in package.artifacts) {
        expect(artifact.status, GeneratedArtifactStatus.ready);
        expect(File(artifact.filePath).existsSync(), isTrue);
        expect(artifact.threadId, 'thread-1');
        expect(artifact.requestId, 'request-1');
        expect(artifact.metadata['qualityStatus'], isNotNull);
      }
      expect(package.primary!.fileName, endsWith('-package.md'));
      expect(
        package.primary!.metadata['artifact'],
        'artifact_package_manifest',
      );
      expect(package.primary!.metadata['artifactCount'], 3);
      final manifestText = File(package.primary!.filePath).readAsStringSync();
      expect(manifestText, contains('Business Use Case Package'));
      expect(manifestText, contains('Package Contents'));
      expect(manifestText, contains('Next Actions'));
      expect(manifestText, contains('.docx'));
      expect(manifestText, contains('.pptx'));
      expect(manifestText, contains('.svg'));
      expect(package.artifacts[1].fileName, endsWith('.docx'));
      expect(package.artifacts[2].fileName, endsWith('.pptx'));
      expect(package.artifacts[3].fileName, endsWith('.svg'));
    },
  );

  test('solution sizing package creates workbook and chart artifacts', () async {
    final root = await Directory.systemTemp.createTemp(
      'circuit-sizing-package-',
    );
    addTearDown(() => root.delete(recursive: true));

    final package = await const GeneratedArtifactPackageWriter()
        .writePackageFromAssistantOutput(
          rootPath: root.path,
          prompt:
              'create a solution sizing package for 500 users, 90 APs, PoE budget, and 2 Gbps WAN',
          content: '''
# Campus Sizing Package

## Summary
Size access, WAN, PoE, and growth headroom for a campus refresh.

| Requirement | Value | Notes |
| --- | ---: | --- |
| Users | 500 | 25% growth target |
| APs | 90 | Wi-Fi 7 UPOE validation required |
| WAN Mbps | 2000 | Inspect security throughput |
| Switches | 6 | Multigig uplinks required |

## Recommendations
- Validate UPOE budget before selecting access switches.
- Size firewall throughput with services enabled.
''',
          turnId: 'turn-sizing-package',
          threadId: 'thread-1',
          requestId: 'request-1',
        );

    expect(package, isNotNull);
    expect(package!.label, 'solution sizing package');
    expect(package.artifacts.map((artifact) => artifact.kind), [
      GeneratedArtifactKind.markdown,
      GeneratedArtifactKind.excel,
      GeneratedArtifactKind.chart,
    ]);
    for (final artifact in package.artifacts) {
      expect(artifact.status, GeneratedArtifactStatus.ready);
      expect(File(artifact.filePath).existsSync(), isTrue);
      expect(artifact.metadata['qualityStatus'], isNotNull);
    }
    expect(package.primary!.fileName, endsWith('-package.md'));
    expect(package.primary!.metadata['artifactCount'], 2);
    final manifestText = File(package.primary!.filePath).readAsStringSync();
    expect(manifestText, contains('Solution Sizing Package'));
    expect(manifestText, contains('.xlsx'));
    expect(manifestText, contains('.svg'));
    expect(package.artifacts[1].fileName, endsWith('.xlsx'));
    expect(package.artifacts[1].sheetCount, greaterThanOrEqualTo(18));
    expect(package.artifacts[2].fileName, endsWith('.svg'));
  });
}
