import 'dart:io';

import 'package:circuit_ide/models/context_pack.dart';
import 'package:circuit_ide/state/context_pack_provider.dart';
import 'package:circuit_ide/state/editor_provider.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/git_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// CI retrieval gate. The fixtures are intentionally labelled and deterministic
/// so a ranking change cannot silently weaken direct-file authority.
void main() {
  test('retrieval quality benchmark meets Studio thresholds', () async {
    final direct = await _directMentionCase();
    final symbol = await _symbolCase();
    final selection = await _selectionAndInstructionCase();
    final diff = await _changedDiffCase();
    final results = [direct, symbol, selection, diff];

    final recall =
        results.where((result) => result.found).length / results.length;
    final precisionAtFive =
        results
            .map((result) => result.precisionAtFive)
            .reduce((a, b) => a + b) /
        results.length;
    final meanReciprocalRank =
        results.map((result) => result.reciprocalRank).reduce((a, b) => a + b) /
        results.length;
    final averageContextTokens =
        results.map((result) => result.contextTokens).reduce((a, b) => a + b) /
        results.length;

    expect(recall, greaterThanOrEqualTo(1.0), reason: results.toString());
    expect(
      precisionAtFive,
      greaterThanOrEqualTo(0.20),
      reason: results.toString(),
    );
    expect(
      meanReciprocalRank,
      greaterThanOrEqualTo(0.75),
      reason: results.toString(),
    );
    expect(
      averageContextTokens,
      lessThanOrEqualTo(900),
      reason: results.toString(),
    );
    expect(direct.rank, 1, reason: 'Direct file mentions are authoritative.');
  });
}

class _BenchmarkResult {
  final String label;
  final int? rank;
  final int includedCount;
  final int contextTokens;

  const _BenchmarkResult({
    required this.label,
    required this.rank,
    required this.includedCount,
    required this.contextTokens,
  });

  bool get found => rank != null;
  double get reciprocalRank => rank == null ? 0 : 1 / rank!;
  double get precisionAtFive => rank != null && rank! <= 5 ? 1 / 5 : 0;

  @override
  String toString() =>
      '$label(rank: $rank, included: $includedCount, tokens: $contextTokens)';
}

Future<_BenchmarkResult> _directMentionCase() async {
  final root = await Directory.systemTemp.createTemp('retrieval_direct_');
  try {
    final target = File(p.join(root.path, 'lib', 'router', 'auth_router.dart'));
    await target.parent.create(recursive: true);
    await target.writeAsString(
      'class AuthRouter { bool requireMfa() => true; }',
    );
    for (var index = 0; index < 30; index++) {
      await File(
        p.join(root.path, 'lib', 'noise_$index.dart'),
      ).writeAsString('class RouterNoise$index {}');
    }
    final pack = await _build(root, 'Review lib/router/auth_router.dart');
    return _resultFor(pack, 'direct mention', 'lib/router/auth_router.dart');
  } finally {
    await root.delete(recursive: true);
  }
}

Future<_BenchmarkResult> _symbolCase() async {
  final root = await Directory.systemTemp.createTemp('retrieval_symbol_');
  try {
    await Directory(p.join(root.path, 'lib', 'core')).create(recursive: true);
    for (var index = 0; index < 70; index++) {
      await File(
        p.join(root.path, 'lib', 'auth_noise_$index.dart'),
      ).writeAsString(
        'class LoginAuth$index { String login() => "login auth session"; }',
      );
    }
    await File(
      p.join(root.path, 'lib', 'core', 'session_policy.dart'),
    ).writeAsString(
      'class SessionPolicy { bool validateMagicSessionRoute() => true; }',
    );
    final pack = await _build(
      root,
      'Explain validateMagicSessionRoute behavior',
    );
    return _resultFor(pack, 'indexed symbol', 'lib/core/session_policy.dart');
  } finally {
    await root.delete(recursive: true);
  }
}

Future<_BenchmarkResult> _selectionAndInstructionCase() async {
  final root = await Directory.systemTemp.createTemp('retrieval_selection_');
  try {
    final file = File(p.join(root.path, 'lib', 'policy.dart'));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      'bool requireMfa(String role) => role == "admin";',
    );
    await File(
      p.join(root.path, 'AGENTS.md'),
    ).writeAsString('Use small patches.');
    await File(p.join(root.path, 'project.lsdf')).writeAsString('^sample:dart');
    await File(
      p.join(root.path, 'INDEX.lsdf'),
    ).writeAsString('@policy.dart\n !requireMfa');
    final container = ProviderContainer();
    try {
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      await container.read(editorProvider.notifier).openFile(file.path);
      container
          .read(editorProvider.notifier)
          .updateSelection(
            0,
            'bool requireMfa(String role) => role == "admin";',
            startLine: 1,
            endLine: 1,
          );
      final pack = container
          .read(contextPackProvider.notifier)
          .buildForCodingTask(prompt: 'Explain the selected policy');
      expect(
        pack.visibleItems.map((item) => item.type),
        containsAll([
          ContextPackItemType.selection,
          ContextPackItemType.instruction,
        ]),
      );
      expect(
        pack.visibleItems.map((item) => item.id),
        contains('lsdf:workspace-map'),
      );
      return _resultFor(pack, 'selection and instructions', 'lib/policy.dart');
    } finally {
      container.dispose();
    }
  } finally {
    await root.delete(recursive: true);
  }
}

Future<_BenchmarkResult> _changedDiffCase() async {
  final root = await Directory.systemTemp.createTemp('retrieval_diff_');
  try {
    final file = File(p.join(root.path, 'lib', 'feature_flags.dart'));
    await file.parent.create(recursive: true);
    await file.writeAsString('bool newCheckoutEnabled = false;');
    for (final command in const [
      ['init'],
      ['config', 'user.email', 'benchmark@circuit.local'],
      ['config', 'user.name', 'Circuit benchmark'],
      ['add', '.'],
      ['commit', '-m', 'initial'],
    ]) {
      final result = await Process.run(
        'git',
        command,
        workingDirectory: root.path,
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());
    }
    await file.writeAsString('bool newCheckoutEnabled = true;');
    final container = ProviderContainer();
    try {
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      await container.read(gitProvider.notifier).refresh();
      final pack = await container
          .read(contextPackProvider.notifier)
          .buildForCodingTaskWithFreshIndex(
            prompt: 'Review the feature flags behavior before patching',
          );
      return _resultFor(pack, 'changed diff', 'lib/feature_flags.dart');
    } finally {
      container.dispose();
    }
  } finally {
    await root.delete(recursive: true);
  }
}

Future<ContextPack> _build(Directory root, String prompt) async {
  final container = ProviderContainer();
  try {
    await container.read(fileTreeProvider.notifier).openDirectory(root.path);
    return await container
        .read(contextPackProvider.notifier)
        .buildForCodingTaskWithFreshIndex(prompt: prompt);
  } finally {
    container.dispose();
  }
}

_BenchmarkResult _resultFor(ContextPack pack, String label, String path) {
  final candidate = pack.retrievalResult!.rankedCandidates
      .where((candidate) => candidate.path == path)
      .firstOrNull;
  return _BenchmarkResult(
    label: label,
    rank: candidate?.rank,
    includedCount: pack.retrievalResult!.includedCandidates.length,
    contextTokens: pack.estimatedTokens,
  );
}
