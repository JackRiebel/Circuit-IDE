import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/agent/memory/agent_config_storage.dart';
import 'package:circuit_ide/models/agent_config_model.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('agent manifest round-trips every declared contract field', () async {
    final root = await Directory.systemTemp.createTemp('agent-manifest-');
    addTearDown(() => root.delete(recursive: true));
    final storage = AgentConfigStorage(agentsDir: root.path);
    final config = AgentConfigModel(
      id: 'code-reviewer',
      name: 'Code reviewer',
      description: 'Reviews a bounded code change for correctness and risk.',
      systemPrompt: 'Return evidence and unresolved risks.',
      allowedIntents: const {TurnIntent.review, TurnIntent.ask},
      allowedTools: const {'read_file', 'search_files', 'git_diff'},
      contextPolicy: AgentContextPolicy.selectedFiles,
      outputContracts: const {
        AgentOutputContract.summary,
        AgentOutputContract.evidence,
      },
      limits: const AgentExecutionLimits(maxTurns: 3, maxToolCalls: 8),
      author: const AgentAuthorMetadata(author: 'quality-team', revision: '7'),
      createdAt: DateTime(2026, 7, 10),
    );

    await storage.save(config);

    final json =
        jsonDecode(await File('${root.path}/code-reviewer.json').readAsString())
            as Map<String, dynamic>;
    final manifest = json['payload']['manifest'] as Map<String, dynamic>;
    expect(json['schemaVersion'], 4);
    expect(manifest['version'], AgentManifest.currentVersion);
    expect(manifest['id'], 'code-reviewer');
    expect(manifest['allowedIntents'], containsAll(['review', 'ask']));
    expect(manifest['allowedTools'], contains('git_diff'));
    expect(manifest['contextPolicy'], 'selectedFiles');
    expect(manifest['outputContracts'], contains('evidence'));
    expect(manifest['author'], {'author': 'quality-team', 'revision': '7'});

    final loaded = (await storage.loadAll()).single;
    expect(loaded.manifest.toJson(), manifest);
    expect(loaded.enabled, isTrue);
    expect(loaded.validate(), isEmpty);
  });

  test(
    'agent manifests reject undeclared capabilities and auto approval',
    () async {
      final root = await Directory.systemTemp.createTemp('agent-manifest-');
      addTearDown(() => root.delete(recursive: true));
      final storage = AgentConfigStorage(agentsDir: root.path);
      final unsafe = AgentConfigModel(
        id: 'unsafe-agent',
        name: 'Unsafe agent',
        description: 'Attempts undeclared access.',
        allowedTools: const {'mcp_upload_everything'},
        allowedConnectors: const {'unapproved-connector'},
        autoApprove: true,
        createdAt: DateTime(2026, 7, 10),
      );

      expect(
        unsafe.validate().join(' '),
        contains('Undeclared or unsupported'),
      );
      expect(
        unsafe.validate().join(' '),
        contains('Connectors are not available'),
      );
      expect(unsafe.validate().join(' '), contains('cannot auto-approve'));
      await expectLater(storage.save(unsafe), throwsA(isA<FormatException>()));
      expect(await File('${root.path}/unsafe-agent.json').exists(), isFalse);
    },
  );

  test(
    'agent manifests require reviewable contracts for plan and code turns',
    () {
      final unsafeCodeAgent = AgentConfigModel(
        id: 'unsafe-code-agent',
        name: 'Unsafe code agent',
        description:
            'Attempts a code turn without a reviewable patch contract.',
        allowedIntents: const {TurnIntent.code},
        allowedTools: const {'read_file'},
        outputContracts: const {AgentOutputContract.summary},
        createdAt: DateTime(2026, 7, 10),
      );

      expect(
        unsafeCodeAgent.validate().join(' '),
        contains('patchProposal output contract'),
      );
      expect(
        unsafeCodeAgent.validate().join(' '),
        contains('must declare propose_patch'),
      );
    },
  );

  test(
    'documented authoring sample imports without CircuitCode source edits',
    () async {
      final root = await Directory.systemTemp.createTemp('agent-doc-sample-');
      addTearDown(() => root.delete(recursive: true));
      final sample = File('../docs/examples/code-reviewer.agent.json');
      expect(await sample.exists(), isTrue);
      final destination = File('${root.path}/code-reviewer.json');
      await destination.writeAsString(await sample.readAsString());

      final loaded = await AgentConfigStorage(agentsDir: root.path).loadAll();

      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'code-reviewer');
      expect(loaded.single.enabled, isFalse);
      expect(loaded.single.validate(), isEmpty);
      expect(
        loaded.single.manifest.contextPolicy,
        AgentContextPolicy.selectedFiles,
      );
      expect(loaded.single.manifest.allowedTools, {
        'read_file',
        'search_files',
        'git_diff',
      });
    },
  );
}
