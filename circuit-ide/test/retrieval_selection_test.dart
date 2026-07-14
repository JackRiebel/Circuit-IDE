import 'dart:io';

import 'package:circuit_ide/models/context_pack.dart';
import 'package:circuit_ide/state/context_pack_provider.dart';
import 'package:circuit_ide/state/editor_provider.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('active editor selection is sent as high-authority context', () async {
    final root = await Directory.systemTemp.createTemp('selection_context_');
    addTearDown(() => root.delete(recursive: true));
    final file = File(p.join(root.path, 'lib', 'policy.dart'));
    await file.parent.create(recursive: true);
    await file.writeAsString('''
class Policy {
  bool requireMfa(String role) => role == 'admin';
}
''');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(fileTreeProvider.notifier).openDirectory(root.path);
    await container.read(editorProvider.notifier).openFile(file.path);
    container
        .read(editorProvider.notifier)
        .updateSelection(
          0,
          "bool requireMfa(String role) => role == 'admin';",
          startLine: 2,
          endLine: 2,
        );

    final pack = container
        .read(contextPackProvider.notifier)
        .buildForCodingTask(prompt: 'Explain this selected behavior');
    final selection = pack.visibleItems.singleWhere(
      (item) => item.type == ContextPackItemType.selection,
    );

    expect(selection.source, 'lib/policy.dart');
    expect(selection.detail, contains('lines 2'));
    expect(selection.detail, contains('requireMfa'));
    expect(selection.retrievalReason, 'Active editor selection.');
    expect(pack.serializePrompt(), contains('requireMfa'));
  });

  test('existing L-SDF indexes are bounded structural context', () async {
    final root = await Directory.systemTemp.createTemp('lsdf_context_');
    addTearDown(() => root.delete(recursive: true));
    await File(p.join(root.path, 'project.lsdf')).writeAsString('''
^sample:dart
 @lib:source
\$lsdf:1.1-circuit
''');
    await File(p.join(root.path, 'INDEX.lsdf')).writeAsString('''
@policy.dart
 @Policy
 !requireMfa
''');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(fileTreeProvider.notifier).openDirectory(root.path);
    final pack = container
        .read(contextPackProvider.notifier)
        .buildForCodingTask(prompt: 'Explain the policy structure');
    final lsdf = pack.visibleItems.singleWhere(
      (item) => item.id == 'lsdf:workspace-map',
    );

    expect(lsdf.detail, contains('requireMfa'));
    expect(lsdf.retrievalReason, 'Workspace L-SDF structural index.');
    expect(pack.serializePrompt(), contains('project.lsdf'));
  });

  test('fresh context adds local semantic and dependency candidates', () async {
    final root = await Directory.systemTemp.createTemp('semantic_flow_');
    addTearDown(() => root.delete(recursive: true));
    final active = File(p.join(root.path, 'lib', 'checkout.dart'));
    final dependency = File(p.join(root.path, 'lib', 'entitlements.dart'));
    await active.parent.create(recursive: true);
    await dependency.writeAsString('''
class EntitlementGate {
  bool permitsPremium(String tier) => tier == 'gold';
}
''');
    await active.writeAsString('''
import 'entitlements.dart';

class CheckoutScreen {
  bool canContinue(String tier) => EntitlementGate().permitsPremium(tier);
}
''');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(fileTreeProvider.notifier).openDirectory(root.path);
    await container.read(editorProvider.notifier).openFile(active.path);
    final pack = await container
        .read(contextPackProvider.notifier)
        .buildForCodingTaskWithFreshIndex(
          prompt: 'Explain the active checkout behavior',
        );

    final dependencyItem = pack.visibleItems.firstWhere(
      (item) => item.source == 'lib/entitlements.dart',
    );
    expect(
      dependencyItem.retrievalReason,
      'One-hop dependency of the active editor file.',
    );
    expect(pack.serializePrompt(), contains('permitsPremium'));
  });
}
