import '../../models/generated_artifact.dart';
import '../../services/artifact_type_registry.dart';

/// Human-readable label used when an artifact does not have a registry entry.
String studioArtifactExportLabel(GeneratedArtifactKind kind) {
  return switch (kind) {
    GeneratedArtifactKind.excel => 'Excel workbook',
    GeneratedArtifactKind.csv => 'CSV',
    GeneratedArtifactKind.markdown => 'Markdown',
    GeneratedArtifactKind.html => 'HTML',
    GeneratedArtifactKind.json => 'JSON',
    GeneratedArtifactKind.pdf => 'PDF report',
    GeneratedArtifactKind.powerPoint => 'PowerPoint deck',
    GeneratedArtifactKind.docx => 'Word report',
    GeneratedArtifactKind.diagram => 'Diagram',
    GeneratedArtifactKind.chart => 'Chart',
    GeneratedArtifactKind.report => 'Report',
  };
}

/// Looks up the durable descriptor for an artifact kind with a safe fallback.
ArtifactTypeDescriptor studioArtifactDescriptorFor(GeneratedArtifactKind kind) {
  return const ArtifactTypeRegistry().descriptorForKind(kind) ??
      ArtifactTypeDescriptor(
        id: kind.name,
        label: studioArtifactExportLabel(kind),
        supportedKinds: [kind],
      );
}
