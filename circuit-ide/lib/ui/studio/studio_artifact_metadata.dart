import '../../models/generated_artifact.dart';

/// Typed accessors for durable artifact metadata shown across drawer surfaces.
///
int studioArtifactMetadataInt(GeneratedArtifact artifact, String key) {
  final value = artifact.metadata[key];
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String studioArtifactMetadataString(GeneratedArtifact artifact, String key) {
  final value = artifact.metadata[key]?.toString().trim() ?? '';
  return value;
}

String studioArtifactManifestLabel(String value) {
  final index = value.indexOf(':');
  if (index <= 0) return 'Manifest';
  return value.substring(0, index).trim();
}

String studioArtifactManifestDetail(String value) {
  final index = value.indexOf(':');
  if (index < 0 || index + 1 >= value.length) return value.trim();
  return value.substring(index + 1).trim();
}

bool studioArtifactMetadataBool(GeneratedArtifact artifact, String key) {
  final value = artifact.metadata[key];
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase() ?? '';
  return text == 'true' || text == 'yes' || text == '1';
}

/// Whether an artifact represents the durable manifest for a deliverable set.
bool studioIsArtifactPackageManifest(GeneratedArtifact artifact) {
  return artifact.metadata['artifact'] == 'artifact_package_manifest';
}

/// Formats an artifact byte count for compact drawer surfaces.
String studioArtifactFormatBytes(int value) {
  if (value < 1024) return '$value B';
  final kb = value / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
}

List<String> studioArtifactMetadataStringList(
  GeneratedArtifact artifact,
  String key,
) {
  final value = artifact.metadata[key];
  if (value is Iterable) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return const [];
  return text
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String studioArtifactCompactSignalList(List<String> signals) {
  if (signals.length <= 2) return signals.join(', ');
  return '${signals.take(2).join(', ')} +${signals.length - 2}';
}

String studioArtifactVisualEvidenceReliabilityLabel(String value) {
  return switch (value.trim()) {
    'metadata_plus_ocr_or_user_description' => 'Screenshot text attached',
    'metadata_only_until_vision_or_user_description' =>
      'Metadata-only screenshots',
    final other when other.isNotEmpty =>
      other
          .replaceAll('_', ' ')
          .replaceFirstMapped(
            RegExp(r'^\w'),
            (match) => match[0]!.toUpperCase(),
          ),
    _ => 'Visual evidence captured',
  };
}
