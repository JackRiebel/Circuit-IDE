import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/generated_artifact.dart';
import 'artifact_type_registry.dart';
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
  final ArtifactTypeRegistry registry;

  const GeneratedArtifactPackageWriter({
    this.writer = const GeneratedArtifactWriter(),
    this.registry = const ArtifactTypeRegistry(),
  });

  List<GeneratedArtifactKind> packageTargetsForPrompt(String prompt) {
    final descriptor = registry.descriptorForPrompt(prompt);
    if (descriptor?.supportsCompanionPackage == true) {
      return descriptor!.packageKinds;
    }
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
      r'\b(evidence pack|citation pack|source pack|source validation|claim validation|unsupported claims?|checked dates?|confidence notes?)\b',
    ).hasMatch(normalized)) {
      add(primary ?? GeneratedArtifactKind.docx);
      add(GeneratedArtifactKind.json);
      if (normalized.contains('handoff') || normalized.contains('final')) {
        add(GeneratedArtifactKind.pdf);
      }
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
          expectedTargets: targets,
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
    required List<GeneratedArtifactKind> expectedTargets,
    required List<GeneratedArtifact> artifacts,
  }) async {
    final root = p.normalize(rootPath);
    final packageDescriptor = registry.descriptorForPrompt(prompt);
    final outputDir = Directory(p.join(root, 'outputs'));
    await outputDir.create(recursive: true);
    final label = _labelFor(prompt, artifacts);
    final fileName = '${_safeBaseName(prompt)}-package.md';
    final filePath = p.normalize(p.join(outputDir.path, fileName));
    if (!p.isWithin(root, filePath)) {
      throw StateError('Package manifest path escaped workspace root.');
    }
    final readiness = _packageReadinessFor(
      artifacts,
      packageDescriptor: packageDescriptor,
      expectedTargets: expectedTargets,
    );
    final content = _manifestMarkdown(
      label: label,
      prompt: prompt,
      artifacts: artifacts,
      readiness: readiness,
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
        'readyArtifactCount': readiness.readyCount,
        'fallbackArtifactCount': readiness.fallbackCount,
        'failedArtifactCount': readiness.failedCount,
        'averageQualityScore': readiness.averageQualityScore,
        'packageQualityStatus': readiness.status,
        'packageNextAction': readiness.nextAction,
        'packageReviewWorkflow': readiness.reviewWorkflow,
        'packageReadinessGaps': readiness.gaps,
        'packageReadinessSignals': readiness.signals,
        'packagePreviewSurfaces': _packagePreviewSurfaces(
          artifacts,
          packageDescriptor: packageDescriptor,
        ),
        'packageVerificationChecks': _packageVerificationChecks(
          artifacts,
          packageDescriptor: packageDescriptor,
        ),
        'packageDrawerActions': _packageDrawerActions(
          artifacts,
          packageDescriptor: packageDescriptor,
        ),
        'packageFileTypes': artifacts
            .map((artifact) => artifact.typeLabel)
            .toSet()
            .toList(growable: false),
        'expectedArtifactCount': expectedTargets.length,
        'producedArtifactCount': artifacts.length,
        'expectedArtifactKinds': expectedTargets.map(_kindLabel).toList(),
        'producedArtifactKinds': artifacts
            .map((artifact) => artifact.typeLabel)
            .toSet()
            .toList(growable: false),
        'missingArtifactKinds': readiness.missingKinds,
        'packageCompletenessStatus': readiness.completenessStatus,
        'hasCompletePackage': readiness.missingKinds.isEmpty,
        'artifactIds': artifacts.map((artifact) => artifact.id).toList(),
        'artifactFiles': artifacts
            .map((artifact) => artifact.fileName)
            .toList(),
        'qualityStatus': readiness.status,
        'qualityScore': readiness.averageQualityScore,
        'hasCustomerReadyArtifact': readiness.failedCount == 0,
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
    required _PackageReadiness readiness,
  }) {
    final buffer = StringBuffer()
      ..writeln('# ${_titleCase(label)}')
      ..writeln()
      ..writeln('Generated artifact package for:')
      ..writeln()
      ..writeln('> ${prompt.trim()}')
      ..writeln()
      ..writeln('## Package Readiness')
      ..writeln()
      ..writeln('| Signal | Value |')
      ..writeln('| --- | --- |')
      ..writeln('| Status | ${_escapeTable(readiness.status)} |')
      ..writeln(
        '| Completeness | ${_escapeTable(readiness.completenessStatus)} |',
      )
      ..writeln('| Expected deliverables | ${readiness.expectedCount} |')
      ..writeln('| Produced deliverables | ${artifacts.length} |')
      ..writeln('| Average quality score | ${readiness.averageQualityScore} |')
      ..writeln(
        '| Ready artifacts | ${readiness.readyCount}/${artifacts.length} |',
      )
      ..writeln('| Fallback artifacts | ${readiness.fallbackCount} |')
      ..writeln('| Failed artifacts | ${readiness.failedCount} |')
      ..writeln('| Next action | ${_escapeTable(readiness.nextAction)} |')
      ..writeln()
      ..writeln('## Package Contract')
      ..writeln()
      ..writeln('| Expected | Produced | Missing |')
      ..writeln('| --- | --- | --- |')
      ..writeln(
        '| ${_escapeTable(readiness.expectedKinds.join(', '))} | ${_escapeTable(artifacts.map((artifact) => artifact.typeLabel).toSet().join(', '))} | ${_escapeTable(readiness.missingKinds.isEmpty ? 'None' : readiness.missingKinds.join(', '))} |',
      )
      ..writeln()
      ..writeln('## Package Contents')
      ..writeln()
      ..writeln('| File | Type | Status | Quality | Summary |')
      ..writeln('| --- | --- | --- | --- | --- |');
    for (final artifact in artifacts) {
      buffer.writeln(
        '| ${_escapeTable(artifact.fileName)} | ${artifact.typeLabel} | ${artifact.statusLabel} | ${_escapeTable(_qualityLabel(artifact))} | ${_escapeTable(artifact.summary)} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Review Workflow')
      ..writeln();
    for (final step in readiness.reviewWorkflow) {
      buffer.writeln('- $step');
    }
    if (readiness.signals.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Readiness Signals')
        ..writeln();
      for (final signal in readiness.signals) {
        buffer.writeln('- $signal');
      }
    }
    if (readiness.gaps.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Gaps To Resolve')
        ..writeln();
      for (final gap in readiness.gaps) {
        buffer.writeln('- $gap');
      }
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

  _PackageReadiness _packageReadinessFor(
    List<GeneratedArtifact> artifacts, {
    ArtifactTypeDescriptor? packageDescriptor,
    List<GeneratedArtifactKind> expectedTargets = const [],
  }) {
    final readyCount = artifacts
        .where((artifact) => artifact.status == GeneratedArtifactStatus.ready)
        .length;
    final fallbackCount = artifacts
        .where(
          (artifact) => artifact.status == GeneratedArtifactStatus.fallback,
        )
        .length;
    final failedCount = artifacts
        .where((artifact) => artifact.status == GeneratedArtifactStatus.failed)
        .length;
    final expectedKinds = expectedTargets.map(_kindLabel).toList();
    final producedKinds = artifacts
        .map((artifact) => artifact.typeLabel)
        .toSet()
        .toList(growable: false);
    final missingKinds = expectedKinds
        .where((kind) => !producedKinds.contains(kind))
        .toList(growable: false);
    final completenessStatus = expectedTargets.isEmpty
        ? 'No package contract'
        : missingKinds.isEmpty
        ? 'Complete'
        : 'Incomplete - missing ${missingKinds.join(', ')}';
    final scores = artifacts
        .map((artifact) => _metadataInt(artifact, 'qualityScore'))
        .whereType<int>()
        .toList(growable: false);
    final averageQualityScore = scores.isEmpty
        ? (failedCount > 0 ? 0 : 100)
        : (scores.reduce((a, b) => a + b) / scores.length).round();
    final gaps = <String>{
      for (final artifact in artifacts)
        ..._metadataStringList(
          artifact,
          'qualityGaps',
        ).map((gap) => '${artifact.fileName}: $gap'),
      for (final artifact in artifacts)
        ..._metadataStringList(
          artifact,
          'validationGaps',
        ).map((gap) => '${artifact.fileName}: $gap'),
    }.toList(growable: false);
    final signals = <String>{
      for (final artifact in artifacts)
        ..._metadataStringList(
          artifact,
          'qualityGates',
        ).map((gate) => '${artifact.typeLabel}: $gate'),
      for (final artifact in artifacts)
        ..._metadataStringList(
          artifact,
          'readinessSignals',
        ).map((signal) => '${artifact.typeLabel}: $signal'),
    }.take(10).toList(growable: false);
    final status = missingKinds.isNotEmpty
        ? 'Package incomplete'
        : failedCount > 0
        ? 'Package has failed artifacts'
        : fallbackCount > 0
        ? 'Package has fallback artifacts'
        : gaps.isNotEmpty
        ? 'Package needs review'
        : 'Package ready';
    final nextAction = missingKinds.isNotEmpty
        ? 'Regenerate or export missing deliverables: ${missingKinds.join(', ')}.'
        : failedCount > 0
        ? 'Regenerate failed artifacts before handoff.'
        : fallbackCount > 0
        ? 'Review fallback artifacts before sharing.'
        : gaps.isNotEmpty
        ? 'Resolve listed evidence and quality gaps.'
        : 'Review the package and share the selected customer-ready files.';
    return _PackageReadiness(
      status: status,
      nextAction: nextAction,
      readyCount: readyCount,
      fallbackCount: fallbackCount,
      failedCount: failedCount,
      expectedCount: expectedTargets.length,
      expectedKinds: expectedKinds,
      missingKinds: missingKinds,
      completenessStatus: completenessStatus,
      averageQualityScore: averageQualityScore,
      gaps: gaps,
      signals: signals,
      reviewWorkflow: _reviewWorkflowFor(
        artifacts,
        packageDescriptor: packageDescriptor,
      ),
    );
  }

  List<String> _reviewWorkflowFor(
    List<GeneratedArtifact> artifacts, {
    ArtifactTypeDescriptor? packageDescriptor,
  }) {
    final steps = <String>{
      if (packageDescriptor?.supportsCompanionPackage == true)
        ...packageDescriptor!.verificationChecks,
      for (final artifact in artifacts)
        ..._descriptorFor(artifact).verificationChecks,
    }.toList();
    steps.add(
      'Open each generated artifact from the Artifacts drawer before sharing.',
    );
    return steps.toList(growable: false);
  }

  List<String> _packagePreviewSurfaces(
    List<GeneratedArtifact> artifacts, {
    ArtifactTypeDescriptor? packageDescriptor,
  }) {
    return <String>{
      if (packageDescriptor != null) packageDescriptor.previewSurface,
      for (final artifact in artifacts) _descriptorFor(artifact).previewSurface,
    }.toList(growable: false);
  }

  List<String> _packageVerificationChecks(
    List<GeneratedArtifact> artifacts, {
    ArtifactTypeDescriptor? packageDescriptor,
  }) {
    return <String>{
      if (packageDescriptor?.supportsCompanionPackage == true)
        ...packageDescriptor!.verificationChecks,
      for (final artifact in artifacts)
        ..._descriptorFor(artifact).verificationChecks,
    }.toList(growable: false);
  }

  List<String> _packageDrawerActions(
    List<GeneratedArtifact> artifacts, {
    ArtifactTypeDescriptor? packageDescriptor,
  }) {
    return <String>{
      if (packageDescriptor != null) ...packageDescriptor.drawerActions,
      for (final artifact in artifacts)
        ..._descriptorFor(artifact).drawerActions,
    }.toList(growable: false);
  }

  ArtifactTypeDescriptor _descriptorFor(GeneratedArtifact artifact) {
    return registry.descriptorForKind(artifact.kind) ??
        ArtifactTypeDescriptor(
          id: artifact.kind.name,
          label: artifact.typeLabel,
          supportedKinds: [artifact.kind],
        );
  }

  String _qualityLabel(GeneratedArtifact artifact) {
    final status = _metadataString(artifact, 'qualityStatus');
    final score = _metadataInt(artifact, 'qualityScore');
    if (status.isEmpty && score == null) return 'Not scored';
    if (score == null) return status;
    if (status.isEmpty) return '$score/100';
    return '$status ($score/100)';
  }

  String _kindLabel(GeneratedArtifactKind kind) {
    return switch (kind) {
      GeneratedArtifactKind.excel => 'Excel',
      GeneratedArtifactKind.csv => 'CSV',
      GeneratedArtifactKind.markdown => 'Markdown',
      GeneratedArtifactKind.json => 'JSON',
      GeneratedArtifactKind.pdf => 'PDF',
      GeneratedArtifactKind.powerPoint => 'PowerPoint',
      GeneratedArtifactKind.docx => 'Word',
      GeneratedArtifactKind.diagram => 'Diagram',
      GeneratedArtifactKind.chart => 'Chart',
      GeneratedArtifactKind.report => 'Report',
    };
  }

  String _metadataString(GeneratedArtifact artifact, String key) {
    return artifact.metadata[key]?.toString().trim() ?? '';
  }

  int? _metadataInt(GeneratedArtifact artifact, String key) {
    final value = artifact.metadata[key];
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  List<String> _metadataStringList(GeneratedArtifact artifact, String key) {
    final value = artifact.metadata[key];
    if (value is Iterable) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
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
    if (normalized.contains('product comparison') ||
        normalized.contains('comparison matrix') ||
        normalized.contains('model comparison') ||
        normalized.contains('fit score') ||
        normalized.contains('shortlist')) {
      return 'product comparison package';
    }
    if (normalized.contains('lifecycle') ||
        normalized.contains('eox') ||
        normalized.contains('ldos')) {
      return 'lifecycle review package';
    }
    if (normalized.contains('evidence pack') ||
        normalized.contains('citation pack') ||
        normalized.contains('source pack') ||
        normalized.contains('source validation') ||
        normalized.contains('claim validation')) {
      return 'evidence pack package';
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

class _PackageReadiness {
  final String status;
  final String nextAction;
  final int readyCount;
  final int fallbackCount;
  final int failedCount;
  final int expectedCount;
  final List<String> expectedKinds;
  final List<String> missingKinds;
  final String completenessStatus;
  final int averageQualityScore;
  final List<String> gaps;
  final List<String> signals;
  final List<String> reviewWorkflow;

  const _PackageReadiness({
    required this.status,
    required this.nextAction,
    required this.readyCount,
    required this.fallbackCount,
    required this.failedCount,
    required this.expectedCount,
    required this.expectedKinds,
    required this.missingKinds,
    required this.completenessStatus,
    required this.averageQualityScore,
    required this.gaps,
    required this.signals,
    required this.reviewWorkflow,
  });
}
