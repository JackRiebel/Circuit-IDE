import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/generated_artifact.dart';
import 'generated_artifact_writer.dart';

class GeneratedArtifactPackage {
  final String label;
  final List<GeneratedArtifact> artifacts;

  const GeneratedArtifactPackage({
    required this.label,
    required this.artifacts,
  });

  GeneratedArtifact? get primary => artifacts.isEmpty ? null : artifacts.first;

  List<GeneratedArtifact> get companions => artifacts.length <= 1
      ? const []
      : artifacts.skip(1).toList(growable: false);
}

class GeneratedArtifactPackageWriter {
  final GeneratedArtifactWriter writer;

  const GeneratedArtifactPackageWriter({
    this.writer = const GeneratedArtifactWriter(),
  });

  List<GeneratedArtifactKind> packageTargetsForPrompt(String prompt) {
    final normalized = prompt.toLowerCase();
    final primary = detectGeneratedArtifactKind(prompt);
    final targets = <GeneratedArtifactKind>[];

    void add(GeneratedArtifactKind kind) {
      if (!targets.contains(kind)) targets.add(kind);
    }

    if (RegExp(
      r'\b(solution sizing|sizing workbook|sizing package|datacenter sizing|data center sizing|poe budget|wan sizing)\b',
    ).hasMatch(normalized)) {
      add(GeneratedArtifactKind.excel);
      add(GeneratedArtifactKind.chart);
    } else if (RegExp(
      r'\b(product comparison|comparison matrix|model comparison|shortlist|fit score)\b',
    ).hasMatch(normalized)) {
      add(GeneratedArtifactKind.excel);
      add(GeneratedArtifactKind.chart);
    } else if (RegExp(
      r'\b(lifecycle|eox|eol|eos|ldos|replacement pid|migration pid)\b',
    ).hasMatch(normalized)) {
      add(GeneratedArtifactKind.excel);
      add(GeneratedArtifactKind.pdf);
    } else if (RegExp(
      r'\b(topology package|network topology|topology diagram|architecture diagram|diagram package)\b',
    ).hasMatch(normalized)) {
      add(GeneratedArtifactKind.diagram);
      add(GeneratedArtifactKind.pdf);
    } else if (RegExp(
      r'\b(business case|use case brief|company research|account plan|sales play|executive brief)\b',
    ).hasMatch(normalized)) {
      add(GeneratedArtifactKind.docx);
      add(GeneratedArtifactKind.powerPoint);
      add(GeneratedArtifactKind.chart);
    } else if (RegExp(
      r'\b(architecture review|design review|review pack|proposal package|customer proposal|customer handoff package)\b',
    ).hasMatch(normalized)) {
      add(primary ?? GeneratedArtifactKind.docx);
      add(GeneratedArtifactKind.powerPoint);
      add(GeneratedArtifactKind.pdf);
    } else if (RegExp(
      r'\b(implementation plan|deployment plan|migration plan|project plan)\b',
    ).hasMatch(normalized)) {
      add(primary ?? GeneratedArtifactKind.docx);
      add(GeneratedArtifactKind.powerPoint);
      add(GeneratedArtifactKind.pdf);
    } else if (RegExp(
      r'\b(change summary|diff report|verification summary|post[- ]work summary|release summary)\b',
    ).hasMatch(normalized)) {
      add(primary ?? GeneratedArtifactKind.docx);
      add(GeneratedArtifactKind.pdf);
    } else if (primary != null) {
      add(primary);
    }

    return targets;
  }

  Future<GeneratedArtifactPackage?> writePackageFromAssistantOutput({
    required String rootPath,
    required String prompt,
    required String content,
    required String turnId,
    required String? threadId,
    required String? requestId,
  }) async {
    final targets = packageTargetsForPrompt(prompt);
    if (targets.isEmpty) return null;

    final artifacts = <GeneratedArtifact>[];
    for (final target in targets) {
      final artifact = await writer.writeStructuredArtifact(
        rootPath: rootPath,
        prompt: prompt,
        content: content,
        targetKind: target,
        turnId: targets.length == 1 ? turnId : '$turnId-${target.name}',
        threadId: threadId,
        requestId: requestId,
      );
      if (artifact != null) artifacts.add(artifact);
    }
    if (artifacts.length > 1) {
      artifacts.insert(
        0,
        await _writeManifestArtifact(
          rootPath: rootPath,
          prompt: prompt,
          turnId: turnId,
          threadId: threadId,
          requestId: requestId,
          artifacts: artifacts,
        ),
      );
    }
    if (artifacts.isEmpty) return null;
    return GeneratedArtifactPackage(
      label: _labelFor(prompt, artifacts),
      artifacts: artifacts,
    );
  }

  Future<GeneratedArtifact> _writeManifestArtifact({
    required String rootPath,
    required String prompt,
    required String turnId,
    required String? threadId,
    required String? requestId,
    required List<GeneratedArtifact> artifacts,
  }) async {
    final root = p.normalize(rootPath);
    final outputDir = Directory(p.join(root, 'outputs'));
    await outputDir.create(recursive: true);
    final label = _labelFor(prompt, artifacts);
    final fileName = '${_safeBaseName(prompt)}-package.md';
    final filePath = p.normalize(p.join(outputDir.path, fileName));
    if (!p.isWithin(root, filePath)) {
      throw StateError('Package manifest path escaped workspace root.');
    }
    final content = _manifestMarkdown(
      label: label,
      prompt: prompt,
      artifacts: artifacts,
    );
    final bytes = utf8.encode(content);
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    return GeneratedArtifact(
      id: '$turnId-package',
      kind: GeneratedArtifactKind.markdown,
      status: GeneratedArtifactStatus.ready,
      fileName: fileName,
      filePath: filePath,
      summary:
          'Created a package manifest for ${artifacts.length} generated artifacts.',
      byteSize: bytes.length,
      previewRows: [
        const ['Artifact', 'Type', 'Status'],
        for (final artifact in artifacts.take(8))
          [artifact.fileName, artifact.typeLabel, artifact.statusLabel],
      ],
      sheetCount: artifacts.length,
      metadata: {
        'artifact': 'artifact_package_manifest',
        'packageLabel': label,
        'artifactCount': artifacts.length,
        'artifactIds': artifacts.map((artifact) => artifact.id).toList(),
        'artifactFiles': artifacts
            .map((artifact) => artifact.fileName)
            .toList(),
        'qualityStatus': 'Package ready',
        'qualityScore': 100,
        'hasCustomerReadyArtifact': true,
      },
      threadId: threadId,
      requestId: requestId,
      createdAt: DateTime.now(),
    );
  }

  String _manifestMarkdown({
    required String label,
    required String prompt,
    required List<GeneratedArtifact> artifacts,
  }) {
    final buffer = StringBuffer()
      ..writeln('# ${_titleCase(label)}')
      ..writeln()
      ..writeln('Generated artifact package for:')
      ..writeln()
      ..writeln('> ${prompt.trim()}')
      ..writeln()
      ..writeln('## Package Contents')
      ..writeln()
      ..writeln('| File | Type | Status | Summary |')
      ..writeln('| --- | --- | --- | --- |');
    for (final artifact in artifacts) {
      buffer.writeln(
        '| ${_escapeTable(artifact.fileName)} | ${artifact.typeLabel} | ${artifact.statusLabel} | ${_escapeTable(artifact.summary)} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Next Actions')
      ..writeln()
      ..writeln('- Open or reveal individual files from the Artifacts drawer.')
      ..writeln('- Review generated facts, assumptions, and source coverage.')
      ..writeln(
        '- Export companion formats only after confirming the package contents.',
      )
      ..writeln()
      ..writeln('## Generated Files');
    for (final artifact in artifacts) {
      buffer.writeln('- `${artifact.fileName}`');
    }
    return buffer.toString();
  }

  String _safeBaseName(String prompt) {
    final normalized = prompt
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (normalized.isEmpty) return 'artifact-package';
    return normalized.length > 48 ? normalized.substring(0, 48) : normalized;
  }

  String _titleCase(String value) {
    return value
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _escapeTable(String value) {
    return value.replaceAll('|', r'\|').replaceAll('\n', ' ').trim();
  }

  String _labelFor(String prompt, List<GeneratedArtifact> artifacts) {
    final normalized = prompt.toLowerCase();
    if (normalized.contains('business case') ||
        normalized.contains('use case')) {
      return 'business use case package';
    }
    if (normalized.contains('solution sizing') ||
        normalized.contains('sizing')) {
      return 'solution sizing package';
    }
    if (normalized.contains('lifecycle') ||
        normalized.contains('eox') ||
        normalized.contains('ldos')) {
      return 'lifecycle review package';
    }
    if (normalized.contains('topology') || normalized.contains('diagram')) {
      return 'topology package';
    }
    if (normalized.contains('architecture review') ||
        normalized.contains('proposal')) {
      return 'architecture review package';
    }
    if (normalized.contains('implementation plan')) {
      return 'implementation plan package';
    }
    if (normalized.contains('change summary') ||
        normalized.contains('diff report')) {
      return 'change summary package';
    }
    return artifacts.length == 1 ? 'artifact' : 'artifact package';
  }
}
