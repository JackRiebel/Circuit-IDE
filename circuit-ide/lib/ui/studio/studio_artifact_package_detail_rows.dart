import '../../models/generated_artifact.dart';
import 'studio_artifact_metadata.dart';

/// Projects package-manifest metadata into compact Artifact drawer rows.
List<(String, String)> studioArtifactPackageDetailRows(
  GeneratedArtifact artifact,
) {
  return [
    if (studioArtifactMetadataString(artifact, 'packageLabel').isNotEmpty)
      ('Package', studioArtifactMetadataString(artifact, 'packageLabel')),
    if (studioArtifactMetadataString(
      artifact,
      'packageQualityStatus',
    ).isNotEmpty)
      (
        'Package status',
        studioArtifactMetadataString(artifact, 'packageQualityStatus'),
      ),
    if (studioArtifactMetadataString(
      artifact,
      'packageCompletenessStatus',
    ).isNotEmpty)
      (
        'Completeness',
        studioArtifactMetadataString(artifact, 'packageCompletenessStatus'),
      ),
    if (studioArtifactMetadataInt(artifact, 'averageQualityScore') > 0)
      (
        'Package score',
        '${studioArtifactMetadataInt(artifact, 'averageQualityScore')}/100',
      ),
    if (studioArtifactMetadataInt(artifact, 'expectedArtifactCount') > 0)
      (
        'Expected',
        '${studioArtifactMetadataInt(artifact, 'expectedArtifactCount')}',
      ),
    if (studioArtifactMetadataInt(artifact, 'producedArtifactCount') > 0)
      (
        'Produced',
        '${studioArtifactMetadataInt(artifact, 'producedArtifactCount')}',
      ),
    if (studioArtifactMetadataInt(artifact, 'artifactCount') > 0)
      ('Artifacts', '${studioArtifactMetadataInt(artifact, 'artifactCount')}'),
    if (studioArtifactMetadataInt(artifact, 'readyArtifactCount') > 0)
      (
        'Ready artifacts',
        '${studioArtifactMetadataInt(artifact, 'readyArtifactCount')}/${studioArtifactMetadataInt(artifact, 'artifactCount')}',
      ),
    if (studioArtifactMetadataString(artifact, 'packageNextAction').isNotEmpty)
      (
        'Package next',
        studioArtifactMetadataString(artifact, 'packageNextAction'),
      ),
    if (studioArtifactMetadataStringList(
      artifact,
      'packageReviewWorkflow',
    ).isNotEmpty)
      (
        'Review workflow',
        studioArtifactCompactSignalList(
          studioArtifactMetadataStringList(artifact, 'packageReviewWorkflow'),
        ),
      ),
    if (studioArtifactMetadataStringList(
      artifact,
      'packageFileTypes',
    ).isNotEmpty)
      (
        'File types',
        studioArtifactCompactSignalList(
          studioArtifactMetadataStringList(artifact, 'packageFileTypes'),
        ),
      ),
    if (studioArtifactMetadataStringList(
      artifact,
      'expectedArtifactKinds',
    ).isNotEmpty)
      (
        'Expected types',
        studioArtifactCompactSignalList(
          studioArtifactMetadataStringList(artifact, 'expectedArtifactKinds'),
        ),
      ),
    if (studioArtifactMetadataStringList(
      artifact,
      'producedArtifactKinds',
    ).isNotEmpty)
      (
        'Produced types',
        studioArtifactCompactSignalList(
          studioArtifactMetadataStringList(artifact, 'producedArtifactKinds'),
        ),
      ),
    if (studioArtifactMetadataStringList(
      artifact,
      'missingArtifactKinds',
    ).isNotEmpty)
      (
        'Missing',
        studioArtifactCompactSignalList(
          studioArtifactMetadataStringList(artifact, 'missingArtifactKinds'),
        ),
      ),
    if (studioArtifactMetadataStringList(
      artifact,
      'packageReadinessSignals',
    ).isNotEmpty)
      (
        'Package signals',
        studioArtifactCompactSignalList(
          studioArtifactMetadataStringList(artifact, 'packageReadinessSignals'),
        ),
      ),
    if (studioArtifactMetadataStringList(
      artifact,
      'packageReadinessGaps',
    ).isNotEmpty)
      (
        'Package gaps',
        studioArtifactCompactSignalList(
          studioArtifactMetadataStringList(artifact, 'packageReadinessGaps'),
        ),
      ),
    if (studioArtifactMetadataStringList(artifact, 'artifactFiles').isNotEmpty)
      (
        'Files',
        studioArtifactCompactSignalList(
          studioArtifactMetadataStringList(artifact, 'artifactFiles'),
        ),
      ),
  ];
}
