import '../../models/generated_artifact.dart';
import 'studio_artifact_metadata.dart';

/// Projects chart-pack metadata into compact Artifact drawer rows.
List<(String, String)> studioArtifactChartDetailRows(
  GeneratedArtifact artifact,
) {
  return [
    if (artifact.kind == GeneratedArtifactKind.chart) ...[
      if (studioArtifactMetadataString(artifact, 'chartPackType').isNotEmpty)
        ('Pack', studioArtifactMetadataString(artifact, 'chartPackType')),
      if (studioArtifactMetadataString(artifact, 'handoffStatus').isNotEmpty)
        ('Handoff', studioArtifactMetadataString(artifact, 'handoffStatus')),
      if (studioArtifactMetadataString(
        artifact,
        'chartReadinessLevel',
      ).isNotEmpty)
        (
          'Readiness level',
          studioArtifactMetadataString(artifact, 'chartReadinessLevel'),
        ),
      if (studioArtifactMetadataInt(artifact, 'chartReadinessScore') > 0)
        (
          'Readiness score',
          '${studioArtifactMetadataInt(artifact, 'chartReadinessScore')}/100',
        ),
      if (studioArtifactMetadataString(
        artifact,
        'chartQualityStatus',
      ).isNotEmpty)
        (
          'Quality',
          studioArtifactMetadataString(artifact, 'chartQualityStatus'),
        ),
      if (studioArtifactMetadataInt(
            artifact,
            'chartHandoffReadinessGateCount',
          ) >
          0)
        (
          'Handoff gates',
          '${studioArtifactMetadataInt(artifact, 'chartHandoffReadinessReadyCount')}/${studioArtifactMetadataInt(artifact, 'chartHandoffReadinessGateCount')} ready',
        ),
      if (studioArtifactMetadataBool(artifact, 'hasChartQualityManifest'))
        (
          'Quality manifest',
          studioArtifactMetadataString(
                artifact,
                'chartQualityManifestVersion',
              ).isEmpty
              ? 'Embedded'
              : 'Manifest v${studioArtifactMetadataString(artifact, 'chartQualityManifestVersion')}',
        ),
      if (studioArtifactMetadataString(artifact, 'riskPosture').isNotEmpty)
        ('Risk posture', studioArtifactMetadataString(artifact, 'riskPosture')),
      if (studioArtifactMetadataString(artifact, 'decisionPurpose').isNotEmpty)
        ('Purpose', studioArtifactMetadataString(artifact, 'decisionPurpose')),
      if (studioArtifactMetadataInt(artifact, 'chartCount') > 0)
        ('Charts', '${studioArtifactMetadataInt(artifact, 'chartCount')}'),
      if (studioArtifactMetadataInt(artifact, 'pointCount') > 0)
        ('Data points', '${studioArtifactMetadataInt(artifact, 'pointCount')}'),
      if (studioArtifactMetadataInt(artifact, 'highRiskCount') > 0)
        (
          'High risk',
          '${studioArtifactMetadataInt(artifact, 'highRiskCount')}',
        ),
      if (studioArtifactMetadataInt(artifact, 'mediumRiskCount') > 0)
        ('Review', '${studioArtifactMetadataInt(artifact, 'mediumRiskCount')}'),
      if (studioArtifactMetadataInt(artifact, 'lowRiskCount') > 0)
        (
          'Low/active',
          '${studioArtifactMetadataInt(artifact, 'lowRiskCount')}',
        ),
      if (studioArtifactMetadataStringList(artifact, 'signals').isNotEmpty)
        (
          'Signals',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'signals'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'chartFamilies',
      ).isNotEmpty)
        (
          'Families',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'chartFamilies'),
          ),
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
        'chartVisualVerificationChecklist',
      ).isNotEmpty)
        (
          'Visual checks',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'chartVisualVerificationChecklist',
            ),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'chartEvidencePolicy',
      ).isNotEmpty)
        (
          'Evidence policy',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'chartEvidencePolicy'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'chartPublishingMetadata',
      ).isNotEmpty)
        (
          'Publishing',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'chartPublishingMetadata',
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
        'decisionQuestions',
      ).isNotEmpty)
        (
          'Decision questions',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'decisionQuestions'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'handoffChecklist',
      ).isNotEmpty)
        (
          'Handoff checklist',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'handoffChecklist'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'reviewerNextSteps',
      ).isNotEmpty)
        (
          'Reviewer next',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'reviewerNextSteps'),
          ),
        ),
      if (studioArtifactMetadataInt(artifact, 'validationGateCount') > 0)
        (
          'Validation',
          '${studioArtifactMetadataInt(artifact, 'validationGateCount')} gates',
        ),
      if (studioArtifactMetadataInt(artifact, 'recommendedActionCount') > 0)
        (
          'Actions',
          '${studioArtifactMetadataInt(artifact, 'recommendedActionCount')} recommended',
        ),
      if (studioArtifactMetadataBool(artifact, 'hasCustomerReadyChartPack'))
        ('Package', 'Stakeholder-review chart pack'),
    ],
  ];
}
