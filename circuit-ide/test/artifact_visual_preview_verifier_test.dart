import 'dart:io';

import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/services/artifact_visual_preview_verifier.dart';
import 'package:circuit_ide/services/generated_artifact_writer.dart';
import 'package:flutter_test/flutter_test.dart';

const _content = '''
# Customer Readiness

## Decision

- Approve the validated rollout path.

## Evidence

- Validation owner confirmed the remaining checks.

## Assumptions

- Customer inventory remains current.

## Sources

- https://example.test/readiness checked 2026-07-13
''';

void main() {
  test(
    'every native customer format writes an immutable verifiable snapshot',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-artifact-preview-integrity-',
      );
      addTearDown(() => root.delete(recursive: true));
      const cases = [
        (GeneratedArtifactKind.docx, 'Create a Word readiness report'),
        (GeneratedArtifactKind.pdf, 'Create a PDF readiness report'),
        (
          GeneratedArtifactKind.powerPoint,
          'Create a PowerPoint readiness deck',
        ),
        (GeneratedArtifactKind.excel, 'Create an Excel readiness workbook'),
      ];

      for (final (kind, prompt) in cases) {
        final artifact = await const GeneratedArtifactWriter()
            .writeStructuredArtifact(
              rootPath: root.path,
              prompt: prompt,
              content: _content,
              targetKind: kind,
              turnId: 'integrity-${kind.name}',
              threadId: 'thread-integrity',
              requestId: 'request-integrity',
            );

        expect(artifact, isNotNull, reason: kind.name);
        final previewPath = artifact!.metadata['visualPreviewPath']! as String;
        expect(previewPath, contains('.preview-'));
        expect(
          artifact.metadata['visualPreviewPersistence'],
          'atomic-sidecar-v1',
        );
        expect(artifact.metadata['visualPreviewSha256'], hasLength(64));
        expect(artifact.metadata['visualPreviewByteSize'], greaterThan(0));
        final verification = await const ArtifactVisualPreviewVerifier().verify(
          artifact,
        );
        expect(verification.isValid, isTrue, reason: kind.name);
      }

      final stagedFiles = await root
          .list(recursive: true)
          .where((entry) => entry.path.contains('.staging-'))
          .toList();
      expect(stagedFiles, isEmpty);
    },
  );

  test(
    'a changed snapshot is rejected instead of opened as quality evidence',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-artifact-preview-corrupt-',
      );
      addTearDown(() => root.delete(recursive: true));
      final artifact = await const GeneratedArtifactWriter()
          .writeStructuredArtifact(
            rootPath: root.path,
            prompt: 'Create a Word readiness report',
            content: _content,
            targetKind: GeneratedArtifactKind.docx,
            turnId: 'corrupt-preview',
            threadId: 'thread-integrity',
            requestId: 'request-integrity',
          );

      expect(artifact, isNotNull);
      final preview = File(artifact!.metadata['visualPreviewPath']! as String);
      await preview.writeAsString('<svg>substituted review evidence</svg>');

      final verification = await const ArtifactVisualPreviewVerifier().verify(
        artifact,
      );
      expect(verification.isValid, isFalse);
      expect(verification.reason, contains('no longer matches'));
    },
  );

  test(
    'a changed generated artifact invalidates its otherwise valid snapshot',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-artifact-output-corrupt-',
      );
      addTearDown(() => root.delete(recursive: true));
      final artifact = await const GeneratedArtifactWriter()
          .writeStructuredArtifact(
            rootPath: root.path,
            prompt: 'Create a PDF readiness report',
            content: _content,
            targetKind: GeneratedArtifactKind.pdf,
            turnId: 'corrupt-output',
            threadId: 'thread-integrity',
            requestId: 'request-integrity',
          );

      expect(artifact, isNotNull);
      await File(artifact!.filePath).writeAsString('externally substituted');

      final verification = await const ArtifactVisualPreviewVerifier().verify(
        artifact,
      );
      expect(verification.isValid, isFalse);
      expect(verification.reason, contains('generated artifact'));
      expect(verification.reason, isNot(contains('visual preview')));
    },
  );

  test(
    'a symlinked generated artifact is rejected before preview launch',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-artifact-output-symlink-',
      );
      addTearDown(() => root.delete(recursive: true));
      final artifact = await const GeneratedArtifactWriter()
          .writeStructuredArtifact(
            rootPath: root.path,
            prompt: 'Create a Word readiness report',
            content: _content,
            targetKind: GeneratedArtifactKind.docx,
            turnId: 'symlink-output',
            threadId: 'thread-integrity',
            requestId: 'request-integrity',
          );

      expect(artifact, isNotNull);
      final output = File(artifact!.filePath);
      final replacement = File('${root.path}/replacement.docx');
      await output.rename(replacement.path);
      await Link(output.path).create(replacement.path);

      final verification = await const ArtifactVisualPreviewVerifier().verify(
        artifact,
      );
      expect(verification.isValid, isFalse);
      expect(verification.reason, contains('not a regular file'));
    },
  );

  test(
    'replacement output cannot reuse an earlier snapshot as current evidence',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-artifact-preview-regenerate-',
      );
      addTearDown(() => root.delete(recursive: true));
      const prompt = 'Create a PDF readiness report';
      final first = await const GeneratedArtifactWriter()
          .writeStructuredArtifact(
            rootPath: root.path,
            prompt: prompt,
            content: _content,
            targetKind: GeneratedArtifactKind.pdf,
            turnId: 'first-preview',
            threadId: 'thread-integrity',
            requestId: 'request-integrity',
          );
      final second = await const GeneratedArtifactWriter()
          .writeStructuredArtifact(
            rootPath: root.path,
            prompt: prompt,
            content: _content.replaceFirst(
              'Approve the validated rollout path.',
              'Hold the rollout until the final evidence review.',
            ),
            targetKind: GeneratedArtifactKind.pdf,
            turnId: 'second-preview',
            threadId: 'thread-integrity',
            requestId: 'request-integrity',
          );

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first!.filePath, second!.filePath);
      expect(
        first.metadata['visualPreviewPath'],
        isNot(second.metadata['visualPreviewPath']),
      );
      expect(
        (await const ArtifactVisualPreviewVerifier().verify(first)).isValid,
        isFalse,
      );
      expect(
        (await const ArtifactVisualPreviewVerifier().verify(second)).isValid,
        isTrue,
      );
      final stagedFiles = await root
          .list(recursive: true)
          .where((entry) => entry.path.contains('.staging-'))
          .toList();
      expect(stagedFiles, isEmpty);
    },
  );
}
