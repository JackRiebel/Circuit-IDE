import 'dart:io';

import 'package:circuit_ide/agent/memory/agent_config_storage.dart';
import 'package:circuit_ide/models/agent_config_model.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:circuit_ide/state/agent_manager_provider.dart';
import 'package:circuit_ide/ui/agents/agent_manager_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Agent Library shows requested capability risk before enabling a saved agent',
    (tester) async {
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('agent-library-ui-'),
      );
      expect(root, isNotNull);
      final tempRoot = root!;
      addTearDown(() => tempRoot.delete(recursive: true));
      final storage = AgentConfigStorage(agentsDir: tempRoot.path);
      final config = AgentConfigModel(
        id: 'safe-reviewer',
        name: 'Safe reviewer',
        description: 'Reviews a bounded change.',
        allowedTools: const {'read_file'},
        contextPolicy: AgentContextPolicy.userProvidedOnly,
        enabled: false,
        evaluationSuite: const AgentEvaluationSuite(
          cases: [
            AgentEvaluationCase(
              id: 'safe-review',
              prompt: 'Explain the review scope without changing files.',
              intent: TurnIntent.ask,
            ),
          ],
        ),
        createdAt: DateTime(2026, 7, 11),
      );
      expect(config.validate(), isEmpty);
      expect(config.evaluationReport.passedGate, isTrue);
      final container = ProviderContainer(
        overrides: [
          agentManagerProvider.overrideWith(
            () => _LoadedAgentManagerNotifier(storage: storage, config: config),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 720,
                height: 800,
                child: AgentManagerPanel(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Disabled'), findsOneWidget);
      expect(find.textContaining('Requested tools: read_file'), findsOneWidget);
      expect(find.textContaining('Low risk'), findsOneWidget);

      await tester.tap(find.text('Enable'));
      await tester.pump();

      expect(find.text('Enable Safe reviewer?'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Requested tools: read_file'),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Every tool action remains subject to Studio approval',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Enable after review'));
      await tester.pumpAndSettle();
      final enableError = await tester.runAsync(
        () => container
            .read(agentManagerProvider.notifier)
            .setConfigEnabled(config.id, true),
      );
      expect(enableError, isNull);
      await tester.pump();

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        container.read(agentManagerProvider).configs.single.enabled,
        isTrue,
      );
      expect(find.text('Enabled'), findsOneWidget);
      final savedConfigs = await tester.runAsync(storage.loadAll);
      expect(savedConfigs, isNotNull);
      expect(savedConfigs!.single.enabled, isTrue);
    },
  );

  test('Agent Library clone is disabled and starts a new revision', () async {
    final root = await Directory.systemTemp.createTemp('agent-library-clone-');
    addTearDown(() => root.delete(recursive: true));
    final storage = AgentConfigStorage(agentsDir: root.path);
    final container = ProviderContainer(
      overrides: [
        agentManagerProvider.overrideWith(
          () => AgentManagerNotifier(storage: storage),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(agentManagerProvider.notifier);
    await notifier.loadConfigs();
    await notifier.saveConfig(
      AgentConfigModel(
        id: 'reviewer',
        name: 'Reviewer',
        enabled: true,
        createdAt: DateTime(2026, 7, 11),
        author: const AgentAuthorMetadata(
          author: 'quality-team',
          revision: '8',
        ),
      ),
    );

    final clone = await notifier.cloneConfig('reviewer');

    expect(clone, isNotNull);
    expect(clone!.id, isNot('reviewer'));
    expect(clone.name, 'Reviewer copy');
    expect(clone.enabled, isFalse);
    expect(clone.author.author, 'quality-team');
    expect(clone.author.revision, '1');
    expect(
      (await storage.loadAll())
          .where((config) => config.id == clone.id)
          .single
          .enabled,
      isFalse,
    );
  });
}

class _LoadedAgentManagerNotifier extends AgentManagerNotifier {
  final AgentConfigModel config;

  _LoadedAgentManagerNotifier({required super.storage, required this.config});

  @override
  AgentManagerState build() => AgentManagerState(configs: [config]);
}
