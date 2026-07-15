import '../../models/generated_artifact.dart';
import 'studio_artifact_metadata.dart';

/// Projects diagram and Excel metadata into compact Artifact drawer rows.
List<(String, String)> studioArtifactDiagramExcelDetailRows(
  GeneratedArtifact artifact,
) {
  return [
    if (artifact.kind == GeneratedArtifactKind.diagram) ...[
      if (studioArtifactMetadataString(artifact, 'topologyType').isNotEmpty)
        ('Topology', studioArtifactMetadataString(artifact, 'topologyType')),
      if (studioArtifactMetadataString(artifact, 'handoffStatus').isNotEmpty)
        ('Handoff', studioArtifactMetadataString(artifact, 'handoffStatus')),
      if (studioArtifactMetadataString(
        artifact,
        'topologyReadinessLevel',
      ).isNotEmpty)
        (
          'Readiness level',
          studioArtifactMetadataString(artifact, 'topologyReadinessLevel'),
        ),
      if (studioArtifactMetadataInt(artifact, 'topologyReadinessScore') > 0)
        (
          'Readiness score',
          '${studioArtifactMetadataInt(artifact, 'topologyReadinessScore')}/100',
        ),
      if (studioArtifactMetadataString(
        artifact,
        'topologyQualityStatus',
      ).isNotEmpty)
        (
          'Quality',
          studioArtifactMetadataString(artifact, 'topologyQualityStatus'),
        ),
      if (studioArtifactMetadataBool(artifact, 'hasTopologyQualityManifest'))
        (
          'Quality manifest',
          studioArtifactMetadataString(
                artifact,
                'topologyQualityManifestVersion',
              ).isEmpty
              ? 'Embedded'
              : 'Manifest v${studioArtifactMetadataString(artifact, 'topologyQualityManifestVersion')}',
        ),
      if (studioArtifactMetadataString(artifact, 'resiliencyModel').isNotEmpty)
        (
          'Resiliency',
          studioArtifactMetadataString(artifact, 'resiliencyModel'),
        ),
      if (studioArtifactMetadataStringList(artifact, 'designZones').isNotEmpty)
        (
          'Zones',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'designZones'),
          ),
        ),
      if (studioArtifactMetadataInt(artifact, 'nodeCount') > 0)
        ('Nodes', '${studioArtifactMetadataInt(artifact, 'nodeCount')}'),
      if (studioArtifactMetadataInt(artifact, 'edgeCount') > 0)
        ('Links', '${studioArtifactMetadataInt(artifact, 'edgeCount')}'),
      if (studioArtifactMetadataInt(artifact, 'siteCount') > 0)
        ('Sites', '${studioArtifactMetadataInt(artifact, 'siteCount')}'),
      if (studioArtifactMetadataInt(artifact, 'idfCount') > 0)
        ('IDFs', '${studioArtifactMetadataInt(artifact, 'idfCount')}'),
      if (studioArtifactMetadataInt(artifact, 'apCount') > 0)
        ('APs', '${studioArtifactMetadataInt(artifact, 'apCount')}'),
      if (studioArtifactMetadataInt(artifact, 'accessPortCount') > 0)
        (
          'Access ports',
          '${studioArtifactMetadataInt(artifact, 'accessPortCount')}',
        ),
      if (studioArtifactMetadataInt(artifact, 'estimatedApPowerWatts') > 0)
        (
          'AP power',
          '${studioArtifactMetadataInt(artifact, 'estimatedApPowerWatts')}W est.',
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'readinessSignals',
      ).isNotEmpty)
        (
          'Readiness',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'readinessSignals'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'topologyVisualVerificationChecklist',
      ).isNotEmpty)
        (
          'Visual checks',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'topologyVisualVerificationChecklist',
            ),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'topologyEvidencePolicy',
      ).isNotEmpty)
        (
          'Evidence policy',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'topologyEvidencePolicy',
            ),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'topologyPublishingMetadata',
      ).isNotEmpty)
        (
          'Publishing',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'topologyPublishingMetadata',
            ),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'validationGaps',
      ).isNotEmpty)
        (
          'Validation gaps',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'validationGaps'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'topologyReviewChecklist',
      ).isNotEmpty)
        (
          'Topology review',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'topologyReviewChecklist',
            ),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'topologyHandoffActions',
      ).isNotEmpty)
        (
          'Handoff actions',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'topologyHandoffActions',
            ),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'topologyRiskFlags',
      ).isNotEmpty)
        (
          'Topology risks',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'topologyRiskFlags'),
          ),
        ),
      if (studioArtifactMetadataBool(artifact, 'hasCustomerReadyTopology'))
        ('Package', 'Architecture-review topology'),
    ],
    if (artifact.kind == GeneratedArtifactKind.excel &&
        studioArtifactMetadataString(artifact, 'workbookKind') ==
            'solution_sizing') ...[
      if (studioArtifactMetadataString(
        artifact,
        'sizingReadinessLevel',
      ).isNotEmpty)
        (
          'Sizing readiness',
          studioArtifactMetadataString(artifact, 'sizingReadinessLevel'),
        ),
      if (studioArtifactMetadataString(
        artifact,
        'sizingHandoffStatus',
      ).isNotEmpty)
        (
          'Sizing handoff',
          studioArtifactMetadataString(artifact, 'sizingHandoffStatus'),
        ),
      if (studioArtifactMetadataString(
        artifact,
        'sizingDecisionPosture',
      ).isNotEmpty)
        (
          'Decision posture',
          studioArtifactMetadataString(artifact, 'sizingDecisionPosture'),
        ),
      if (studioArtifactMetadataInt(
            artifact,
            'sizingCustomerHandoffGateCount',
          ) >
          0)
        (
          'Handoff gates',
          '${studioArtifactMetadataInt(artifact, 'sizingCustomerHandoffReadyCount')}/${studioArtifactMetadataInt(artifact, 'sizingCustomerHandoffGateCount')} ready',
        ),
      if (studioArtifactMetadataBool(artifact, 'hasSizingQualityManifest'))
        (
          'Sizing manifest',
          studioArtifactMetadataString(
                artifact,
                'sizingQualityManifestVersion',
              ).isEmpty
              ? 'Embedded'
              : 'Manifest v${studioArtifactMetadataString(artifact, 'sizingQualityManifestVersion')}',
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'sizingEvidencePolicy',
      ).isNotEmpty)
        (
          'Evidence policy',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'sizingEvidencePolicy'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'sizingVisualVerificationChecklist',
      ).isNotEmpty)
        (
          'Visual checks',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'sizingVisualVerificationChecklist',
            ),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'sizingPublishingMetadata',
      ).isNotEmpty)
        (
          'Publishing',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'sizingPublishingMetadata',
            ),
          ),
        ),
      if (studioArtifactMetadataString(artifact, 'users').isNotEmpty)
        ('Users', studioArtifactMetadataString(artifact, 'users')),
      if (studioArtifactMetadataString(artifact, 'accessPoints').isNotEmpty)
        ('APs', studioArtifactMetadataString(artifact, 'accessPoints')),
      if (studioArtifactMetadataString(artifact, 'switches').isNotEmpty)
        ('Switches', studioArtifactMetadataString(artifact, 'switches')),
      if (studioArtifactMetadataString(artifact, 'wan').isNotEmpty)
        ('WAN', studioArtifactMetadataString(artifact, 'wan')),
      if (studioArtifactMetadataString(artifact, 'growth').isNotEmpty)
        ('Growth', studioArtifactMetadataString(artifact, 'growth')),
      if (studioArtifactMetadataInt(artifact, 'gateCount') > 0)
        ('Gates', '${studioArtifactMetadataInt(artifact, 'gateCount')}'),
      if (studioArtifactMetadataInt(artifact, 'riskCount') > 0)
        ('Risks', '${studioArtifactMetadataInt(artifact, 'riskCount')}'),
      if (studioArtifactMetadataInt(artifact, 'highRiskCount') > 0)
        (
          'High risk',
          '${studioArtifactMetadataInt(artifact, 'highRiskCount')}',
        ),
      if (studioArtifactMetadataInt(artifact, 'candidateCheckCount') > 0)
        (
          'Candidate checks',
          '${studioArtifactMetadataInt(artifact, 'candidateCheckCount')}',
        ),
      if (studioArtifactMetadataInt(artifact, 'validationCheckCount') > 0)
        (
          'Validation',
          '${studioArtifactMetadataInt(artifact, 'validationCheckCount')} checks',
        ),
      if (studioArtifactMetadataInt(artifact, 'recommendationCount') > 0)
        (
          'Recommendations',
          '${studioArtifactMetadataInt(artifact, 'recommendationCount')}',
        ),
      if (studioArtifactMetadataBool(artifact, 'hasHighPowerApSignal'))
        ('Power', 'High-power AP/UPOE signal'),
      if (studioArtifactMetadataBool(artifact, 'hasMultigigSignal'))
        ('Access speed', 'mGig validation signal'),
      if (studioArtifactMetadataBool(artifact, 'hasLifecycleValidation'))
        ('Lifecycle', 'Validation included'),
      if (studioArtifactMetadataStringList(
        artifact,
        'hardGateFailures',
      ).isNotEmpty)
        (
          'Hard gates',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'hardGateFailures'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'customerFollowUpQuestions',
      ).isNotEmpty)
        (
          'Customer questions',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'customerFollowUpQuestions',
            ),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'validationRoadmap',
      ).isNotEmpty)
        (
          'Validation roadmap',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'validationRoadmap'),
          ),
        ),
    ],
    if (artifact.kind == GeneratedArtifactKind.excel &&
        studioArtifactMetadataString(artifact, 'workbookKind') ==
            'lifecycle_eox') ...[
      if (studioArtifactMetadataString(
        artifact,
        'lifecycleReadinessLevel',
      ).isNotEmpty)
        (
          'Lifecycle readiness',
          studioArtifactMetadataString(artifact, 'lifecycleReadinessLevel'),
        ),
      if (studioArtifactMetadataString(
        artifact,
        'lifecycleHandoffStatus',
      ).isNotEmpty)
        (
          'Lifecycle handoff',
          studioArtifactMetadataString(artifact, 'lifecycleHandoffStatus'),
        ),
      if (studioArtifactMetadataString(
        artifact,
        'lifecycleDecisionPosture',
      ).isNotEmpty)
        (
          'Decision posture',
          studioArtifactMetadataString(artifact, 'lifecycleDecisionPosture'),
        ),
      if (studioArtifactMetadataInt(
            artifact,
            'lifecycleCustomerHandoffGateCount',
          ) >
          0)
        (
          'Handoff gates',
          '${studioArtifactMetadataInt(artifact, 'lifecycleCustomerHandoffReadyCount')}/${studioArtifactMetadataInt(artifact, 'lifecycleCustomerHandoffGateCount')} ready',
        ),
      if (studioArtifactMetadataBool(artifact, 'hasLifecycleQualityManifest'))
        (
          'Lifecycle manifest',
          studioArtifactMetadataString(
                artifact,
                'lifecycleQualityManifestVersion',
              ).isEmpty
              ? 'Embedded'
              : 'Manifest v${studioArtifactMetadataString(artifact, 'lifecycleQualityManifestVersion')}',
        ),
      if (studioArtifactMetadataString(
        artifact,
        'highestLifecycleRisk',
      ).isNotEmpty)
        (
          'Highest risk',
          studioArtifactMetadataString(artifact, 'highestLifecycleRisk'),
        ),
      if (studioArtifactMetadataString(artifact, 'dateAuthority').isNotEmpty)
        (
          'Date authority',
          studioArtifactMetadataString(artifact, 'dateAuthority'),
        ),
      if (studioArtifactMetadataString(
        artifact,
        'checkedDateStatus',
      ).isNotEmpty)
        (
          'Checked date',
          studioArtifactMetadataString(artifact, 'checkedDateStatus'),
        ),
      if (studioArtifactMetadataString(artifact, 'migrationPosture').isNotEmpty)
        (
          'Migration posture',
          studioArtifactMetadataString(artifact, 'migrationPosture'),
        ),
      if (studioArtifactMetadataString(
        artifact,
        'modernRequirementPressure',
      ).isNotEmpty)
        (
          'Modern requirements',
          studioArtifactMetadataString(artifact, 'modernRequirementPressure'),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'lifecycleEvidencePolicy',
      ).isNotEmpty)
        (
          'Evidence policy',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'lifecycleEvidencePolicy',
            ),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'lifecycleVisualVerificationChecklist',
      ).isNotEmpty)
        (
          'Visual checks',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'lifecycleVisualVerificationChecklist',
            ),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'lifecyclePublishingMetadata',
      ).isNotEmpty)
        (
          'Publishing',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'lifecyclePublishingMetadata',
            ),
          ),
        ),
      if (studioArtifactMetadataInt(artifact, 'lifecycleRecordCount') > 0)
        (
          'Products',
          '${studioArtifactMetadataInt(artifact, 'lifecycleRecordCount')}',
        ),
      if (studioArtifactMetadataInt(artifact, 'highRiskLifecycleCount') > 0)
        (
          'High-risk items',
          '${studioArtifactMetadataInt(artifact, 'highRiskLifecycleCount')}',
        ),
      if (studioArtifactMetadataInt(artifact, 'unknownLifecycleDateCount') > 0)
        (
          'Unknown dates',
          '${studioArtifactMetadataInt(artifact, 'unknownLifecycleDateCount')}',
        ),
      if (studioArtifactMetadataInt(artifact, 'migrationHintCount') > 0)
        (
          'Migration hints',
          '${studioArtifactMetadataInt(artifact, 'migrationHintCount')}',
        ),
    ],
    if (artifact.kind == GeneratedArtifactKind.excel &&
        studioArtifactMetadataString(artifact, 'workbookKind') ==
            'product_comparison') ...[
      if (studioArtifactMetadataString(
        artifact,
        'comparisonReadinessLevel',
      ).isNotEmpty)
        (
          'Comparison readiness',
          studioArtifactMetadataString(artifact, 'comparisonReadinessLevel'),
        ),
      if (studioArtifactMetadataString(
        artifact,
        'comparisonHandoffStatus',
      ).isNotEmpty)
        (
          'Comparison handoff',
          studioArtifactMetadataString(artifact, 'comparisonHandoffStatus'),
        ),
      if (studioArtifactMetadataString(
        artifact,
        'comparisonDecisionPosture',
      ).isNotEmpty)
        (
          'Decision posture',
          studioArtifactMetadataString(artifact, 'comparisonDecisionPosture'),
        ),
      if (studioArtifactMetadataInt(
            artifact,
            'comparisonCustomerHandoffGateCount',
          ) >
          0)
        (
          'Handoff gates',
          '${studioArtifactMetadataInt(artifact, 'comparisonCustomerHandoffReadyCount')}/${studioArtifactMetadataInt(artifact, 'comparisonCustomerHandoffGateCount')} ready',
        ),
      if (studioArtifactMetadataBool(artifact, 'hasComparisonQualityManifest'))
        (
          'Comparison manifest',
          studioArtifactMetadataString(
                artifact,
                'comparisonQualityManifestVersion',
              ).isEmpty
              ? 'Embedded'
              : 'Manifest v${studioArtifactMetadataString(artifact, 'comparisonQualityManifestVersion')}',
        ),
      if (studioArtifactMetadataString(
        artifact,
        'recommendedCandidate',
      ).isNotEmpty)
        (
          'Primary',
          studioArtifactMetadataString(artifact, 'recommendedCandidate'),
        ),
      if (studioArtifactMetadataString(
        artifact,
        'runnerUpCandidate',
      ).isNotEmpty)
        (
          'Runner-up',
          studioArtifactMetadataString(artifact, 'runnerUpCandidate'),
        ),
      if (studioArtifactMetadataString(
        artifact,
        'requirementPressure',
      ).isNotEmpty)
        (
          'Hard gates',
          studioArtifactMetadataString(artifact, 'requirementPressure'),
        ),
      if (studioArtifactMetadataString(artifact, 'evidenceQuality').isNotEmpty)
        ('Evidence', studioArtifactMetadataString(artifact, 'evidenceQuality')),
      if (studioArtifactMetadataStringList(
        artifact,
        'comparisonEvidencePolicy',
      ).isNotEmpty)
        (
          'Evidence policy',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'comparisonEvidencePolicy',
            ),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'comparisonVisualVerificationChecklist',
      ).isNotEmpty)
        (
          'Visual checks',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'comparisonVisualVerificationChecklist',
            ),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'comparisonPublishingMetadata',
      ).isNotEmpty)
        (
          'Publishing',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'comparisonPublishingMetadata',
            ),
          ),
        ),
      if (studioArtifactMetadataInt(artifact, 'candidateCount') > 0)
        (
          'Candidates',
          '${studioArtifactMetadataInt(artifact, 'candidateCount')}',
        ),
      if (studioArtifactMetadataInt(artifact, 'atRiskGateCount') > 0)
        (
          'At-risk gates',
          '${studioArtifactMetadataInt(artifact, 'atRiskGateCount')}',
        ),
      if (studioArtifactMetadataInt(artifact, 'needsValidationGateCount') > 0)
        (
          'Needs validation',
          '${studioArtifactMetadataInt(artifact, 'needsValidationGateCount')}',
        ),
    ],
  ];
}
