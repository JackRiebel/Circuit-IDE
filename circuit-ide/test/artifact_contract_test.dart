import 'dart:io';

import 'package:circuit_ide/models/artifact_document.dart';
import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/services/artifact_contract.dart';
import 'package:circuit_ide/services/artifact_readiness_evaluator.dart';
import 'package:circuit_ide/services/artifact_type_registry.dart';
import 'package:circuit_ide/services/generated_artifact_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const evaluator = ArtifactReadinessEvaluator();
  const enterpriseDescriptors = <String>[
    'network_topology_diagram',
    'architecture_review_pack',
    'solution_sizing_workbook',
    'lifecycle_eox_report',
    'product_comparison_matrix',
    'business_use_case_brief',
    'chart_pack',
    'evidence_pack',
  ];

  test(
    'every enterprise artifact labels each missing contract field unknown',
    () {
      const registry = ArtifactTypeRegistry();
      for (final id in enterpriseDescriptors) {
        final descriptor = registry.descriptorForId(id);
        expect(descriptor, isNotNull, reason: 'Missing descriptor for $id');

        final metadata = evaluator.metadataFor(
          kind: descriptor!.primaryKind,
          status: GeneratedArtifactStatus.ready,
          document: const ArtifactDocument(title: 'Review', summary: 'Summary'),
          previewRows: const [
            ['Header'],
            ['Value'],
          ],
          count: 3,
          byteSize: 12,
          metadata: const {},
          contractFields: descriptor.contractFields,
        );
        final gaps = metadata['qualityGaps'] as List<Object?>;
        for (final field in descriptor.contractFields) {
          expect(
            gaps,
            contains(_unknownLabel(field)),
            reason: '$id must expose an actionable gap for ${field.label}',
          );
        }
        expect(metadata['hasCustomerReadyArtifact'], isFalse);
      }
    },
  );

  test('enterprise domain fixtures satisfy their typed contract gates', () {
    const registry = ArtifactTypeRegistry();
    for (final id in enterpriseDescriptors) {
      final descriptor = registry.descriptorForId(id)!;
      final metadata = evaluator.metadataFor(
        kind: descriptor.primaryKind,
        status: GeneratedArtifactStatus.ready,
        document: _evidenceDocument(),
        previewRows: const [
          ['Header'],
          ['Value'],
        ],
        count: 3,
        byteSize: 12,
        metadata: _validMetadataFor(id),
        contractFields: descriptor.contractFields,
      );
      final gates = metadata['qualityGates'] as List<Object?>;
      for (final field in descriptor.contractFields) {
        expect(
          gates,
          contains('Contract: ${field.label}'),
          reason: '$id should accept its explicit ${field.label} evidence',
        );
      }
    }
  });

  test(
    'EoX migration hints are not accepted as replacement suitability',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-contract-');
      addTearDown(() => root.delete(recursive: true));

      final artifact = await const GeneratedArtifactWriter()
          .writeFromAssistantOutput(
            rootPath: root.path,
            prompt: 'create a lifecycle EoX report with replacement PIDs',
            content: '''
# Lifecycle / EoX Review

| Product | Lifecycle Status | End of Sale | LDOS | Risk | Replacement PID | Source |
| --- | --- | --- | --- | --- | --- | --- |
| C9300-48P | End of Support | 2024-01-01 | 2026-10-31 | High | C9300X-48HX | Cisco EoX API checked 2026-07-11 |

## Assumptions
- The current UPOE and mGig requirements still need customer confirmation.

## Confidence
- Confidence: Medium pending current-portfolio validation.
''',
            turnId: 'turn-contract-eox',
            threadId: 'thread-contract',
            requestId: 'request-contract',
          );

      expect(artifact, isNotNull);
      expect(artifact!.metadata['hasValidatedReplacementSuitability'], isFalse);
      expect(
        artifact.metadata['qualityGaps'],
        contains(
          'Unknown Replacement suitability — EoX migration hints are not final recommendations',
        ),
      );
      expect(artifact.metadata['hasCustomerReadyArtifact'], isFalse);
      expect(
        String.fromCharCodes(await File(artifact.filePath).readAsBytes()),
        contains(
          'Never present EoX replacement PID as final best model by itself.',
        ),
      );
    },
  );
}

ArtifactDocument _evidenceDocument() {
  return const ArtifactDocument(
    title: 'Evidence-backed review',
    summary: 'Evidence has been reviewed.',
    assumptions: ['Customer requirements are confirmed for this fixture.'],
    citations: ['Official source checked 2026-07-11'],
  );
}

Map<String, Object?> _validMetadataFor(String id) {
  const shared = <String, Object?>{'confidence': 'High'};
  return switch (id) {
    'network_topology_diagram' => {
      ...shared,
      'nodeCount': 3,
      'edgeCount': 2,
      'hasCapacityChecks': true,
      'hasTopologyValidationGate': true,
    },
    'architecture_review_pack' => {
      ...shared,
      'architectureFindingCount': 1,
      'architectureRiskCount': 1,
      'architectureValidationCount': 1,
    },
    'solution_sizing_workbook' => {
      ...shared,
      'hasPoeBudget': true,
      'hasWanThroughput': true,
      'hasCandidateValidation': true,
    },
    'lifecycle_eox_report' => {
      ...shared,
      'hasOfficialLifecycleSource': true,
      'hasCheckedDateEvidence': true,
      'unknownLifecycleDateCount': 0,
      'hasValidatedReplacementSuitability': true,
    },
    'product_comparison_matrix' => {
      ...shared,
      'candidateCount': 2,
      'shortlistCount': 1,
      'hardGateEvaluationCount': 1,
      'mustHaveComplianceCount': 1,
    },
    'business_use_case_brief' => {
      ...shared,
      'businessUseCaseCount': 1,
      'businessValueMetricCount': 1,
    },
    'chart_pack' => {
      ...shared,
      'pointCount': 2,
      'hasThresholdGuidance': true,
      'hasDecisionMatrix': true,
    },
    'evidence_pack' => {...shared, 'claimCount': 1, 'claimDispositionCount': 1},
    _ => throw ArgumentError.value(id, 'id', 'Unknown enterprise descriptor'),
  };
}

String _unknownLabel(ArtifactContractField field) {
  if (field == ArtifactContractField.replacementSuitability) {
    return 'Unknown Replacement suitability — EoX migration hints are not final recommendations';
  }
  return 'Unknown ${field.label}';
}
