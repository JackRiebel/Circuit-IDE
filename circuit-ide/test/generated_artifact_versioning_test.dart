import 'dart:io';

import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/services/generated_artifact_exporter.dart';
import 'package:circuit_ide/services/generated_artifact_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'artifact recipes survive restart and regenerate a child format without the prior file',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-artifact-versioning-',
      );
      addTearDown(() => root.delete(recursive: true));

      const prompt = 'Create an architecture review Word document';
      const content = '''
# Campus Architecture Review

## Findings
- Validate PoE and uplink capacity.

## Recommendation
- Standardize resilient access pairs before rollout.

## Assumptions
- Inventory counts need customer validation.
''';
      const writer = GeneratedArtifactWriter();
      final original = await writer.writeStructuredArtifact(
        rootPath: root.path,
        prompt: prompt,
        content: content,
        targetKind: GeneratedArtifactKind.docx,
        turnId: 'turn-artifact-v1',
        threadId: 'thread-1',
        requestId: 'request-1',
      );

      expect(original, isNotNull);
      expect(original!.version, 1);
      expect(original.parentArtifactId, isNull);
      expect(original.outputHash, hasLength(64));
      expect(original.generationRecipe?.prompt, prompt);
      expect(original.generationRecipe?.sourceContent, content);
      expect(original.canRegenerate, isTrue);

      final restored = GeneratedArtifact.fromJson(original.toJson());
      expect(restored, isNotNull);
      expect(
        restored!.generationRecipe?.compositionHash,
        original.generationRecipe?.compositionHash,
      );
      expect(restored.outputHash, original.outputHash);
      final persistedArtifact = GeneratedArtifact.fromSourceArtifact(
        restored.toSourceArtifact(),
      );
      expect(persistedArtifact?.generationRecipe?.sourceContent, content);
      expect(persistedArtifact?.outputHash, original.outputHash);

      const exporter = GeneratedArtifactExporter();
      expect(await exporter.hasExternalChanges(original), isFalse);
      await File(original.filePath).writeAsString('Externally edited file');
      expect(await exporter.hasExternalChanges(original), isTrue);

      await File(original.filePath).delete();
      expect(
        exporter.supportedTargets(persistedArtifact!),
        contains(GeneratedArtifactKind.pdf),
      );
      final regenerated = await exporter.export(
        artifact: persistedArtifact,
        targetKind: GeneratedArtifactKind.pdf,
      );

      expect(regenerated, isNotNull);
      expect(regenerated!.kind, GeneratedArtifactKind.pdf);
      expect(regenerated.version, 2);
      expect(regenerated.parentArtifactId, original.id);
      expect(regenerated.fileName, contains('-v2.pdf'));
      expect(regenerated.outputHash, hasLength(64));
      expect(regenerated.outputHash, isNot(original.outputHash));
      expect(
        regenerated.generationRecipe?.compositionHash,
        original.generationRecipe?.compositionHash,
      );
      expect(await File(regenerated.filePath).exists(), isTrue);

      const editedContent =
          '# Campus Architecture Review\n\n## Recommendation\n- Replace the access layer after a final PoE survey.';
      final edited = await exporter.regenerate(
        artifact: persistedArtifact,
        sourceContentOverride: editedContent,
      );
      expect(edited, isNotNull);
      expect(edited!.version, 2);
      expect(edited.generationRecipe?.sourceContent, editedContent);
      expect(
        edited.generationRecipe?.compositionHash,
        isNot(original.generationRecipe?.compositionHash),
      );
    },
  );
}
