import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/generated_artifact.dart';

/// Validates an immutable visual-review snapshot before it is opened.
///
/// The sidecar is evidence for one exact generated output, not a general
/// illustration. Verify both regular files, their persisted sizes and hashes,
/// and their shared output directory so an externally replaced artifact can
/// never be shown beside stale quality evidence.
class ArtifactVisualPreviewVerifier {
  const ArtifactVisualPreviewVerifier();

  Future<ArtifactVisualPreviewVerification> verify(
    GeneratedArtifact artifact,
  ) async => verifySync(artifact);

  ArtifactVisualPreviewVerification verifySync(GeneratedArtifact artifact) {
    final artifactPath = artifact.filePath.trim();
    final path = artifact.metadata['visualPreviewPath']?.toString().trim();
    final expectedArtifactDigest = artifact.outputHash.trim().toLowerCase();
    final expectedArtifactSize = artifact.byteSize;
    final expectedDigest = artifact.metadata['visualPreviewSha256']
        ?.toString()
        .trim()
        .toLowerCase();
    final expectedSize = _positiveInt(
      artifact.metadata['visualPreviewByteSize'],
    );
    if (path == null || path.isEmpty) {
      return const ArtifactVisualPreviewVerification.invalid(
        'This artifact has no persisted visual preview.',
      );
    }
    if (artifactPath.isEmpty ||
        !p.isAbsolute(artifactPath) ||
        !p.isAbsolute(path) ||
        p.dirname(p.normalize(artifactPath)) != p.dirname(p.normalize(path))) {
      return const ArtifactVisualPreviewVerification.invalid(
        'This visual preview is not bound to a local generated artifact.',
      );
    }
    if (expectedArtifactSize <= 0 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedArtifactDigest)) {
      return const ArtifactVisualPreviewVerification.invalid(
        'This artifact predates output integrity verification. Regenerate it before using visual review evidence.',
      );
    }
    if (expectedDigest == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedDigest) ||
        expectedSize == null) {
      return const ArtifactVisualPreviewVerification.invalid(
        'This visual preview predates integrity verification. Regenerate the artifact before using it as review evidence.',
      );
    }

    try {
      final artifactType = FileSystemEntity.typeSync(
        artifactPath,
        followLinks: false,
      );
      if (artifactType != FileSystemEntityType.file) {
        return const ArtifactVisualPreviewVerification.invalid(
          'The generated artifact is missing or is not a regular file.',
        );
      }
      final artifactBytes = File(artifactPath).readAsBytesSync();
      if (artifactBytes.length != expectedArtifactSize) {
        return const ArtifactVisualPreviewVerification.invalid(
          'The generated artifact size no longer matches its generation record.',
        );
      }
      if (sha256.convert(artifactBytes).toString() != expectedArtifactDigest) {
        return const ArtifactVisualPreviewVerification.invalid(
          'The generated artifact no longer matches its generation record.',
        );
      }

      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type != FileSystemEntityType.file) {
        return const ArtifactVisualPreviewVerification.invalid(
          'The persisted visual preview is missing or is not a regular file.',
        );
      }
      final bytes = File(path).readAsBytesSync();
      if (bytes.length != expectedSize) {
        return const ArtifactVisualPreviewVerification.invalid(
          'The persisted visual preview size no longer matches its generation record.',
        );
      }
      if (sha256.convert(bytes).toString() != expectedDigest) {
        return const ArtifactVisualPreviewVerification.invalid(
          'The persisted visual preview no longer matches its generation record.',
        );
      }
      return ArtifactVisualPreviewVerification.valid(path);
    } on FileSystemException {
      return const ArtifactVisualPreviewVerification.invalid(
        'The generated artifact or its visual preview could not be read safely.',
      );
    }
  }

  int? _positiveInt(Object? value) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    return parsed == null || parsed <= 0 ? null : parsed;
  }
}

class ArtifactVisualPreviewVerification {
  final bool isValid;
  final String? path;
  final String? reason;

  const ArtifactVisualPreviewVerification._({
    required this.isValid,
    this.path,
    this.reason,
  });

  const ArtifactVisualPreviewVerification.valid(String path)
    : this._(isValid: true, path: path);

  const ArtifactVisualPreviewVerification.invalid(String reason)
    : this._(isValid: false, reason: reason);
}
