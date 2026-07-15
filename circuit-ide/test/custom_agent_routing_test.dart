import 'package:circuit_ide/models/agent_config_model.dart';
import 'package:circuit_ide/models/custom_agent_routing.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const router = CustomAgentRouter();
  final agents = [
    AgentConfigModel(
      id: 'security-reviewer',
      name: 'Security reviewer',
      description:
          'Reviews authentication, authorization, secrets, and threat risks.',
      allowedIntents: const {TurnIntent.ask, TurnIntent.review},
      enabled: true,
      createdAt: DateTime(2026, 7, 11),
    ),
    AgentConfigModel(
      id: 'release-planner',
      name: 'Release planner',
      description:
          'Plans rollout, release notes, deployment, and verification work.',
      allowedIntents: const {TurnIntent.ask, TurnIntent.plan},
      outputContracts: const {
        AgentOutputContract.summary,
        AgentOutputContract.plan,
      },
      allowedTools: const {'propose_patch'},
      enabled: true,
      createdAt: DateTime(2026, 7, 11),
    ),
  ];

  test(
    'explicit custom-agent selection always wins over automatic routing',
    () {
      final selection = router.route(
        prompt: 'Review authentication and secrets for risk.',
        intent: TurnIntent.ask,
        configs: agents,
        explicitAgentId: 'release-planner',
        auto: true,
      );

      expect(selection.isAuto, isFalse);
      expect(selection.agent?.id, 'release-planner');
      expect(selection.confidence, 1);
      expect(selection.rationale, contains('explicitly selected'));
    },
  );

  test('automatic routing selects an eligible high-confidence candidate', () {
    final selection = router.route(
      prompt: 'Review authentication secrets and authorization threat risks.',
      intent: TurnIntent.review,
      configs: agents,
      auto: true,
    );

    expect(selection.isAuto, isTrue);
    expect(selection.agent?.id, 'security-reviewer');
    expect(selection.confidence, greaterThanOrEqualTo(0.60));
    expect(selection.matchedTerms, containsAll(['authentication', 'secrets']));
  });

  test('automatic routing falls back to General for low confidence', () {
    final selection = router.route(
      prompt: 'Can you help me with this?',
      intent: TurnIntent.ask,
      configs: agents,
      auto: true,
    );

    expect(selection.usesGeneralAgent, isTrue);
    expect(selection.rationale, contains('General Studio agent'));
    expect(selection.confidence, lessThan(0.60));
  });

  test(
    'automatic routing filters agents that cannot run the requested intent',
    () {
      final selection = router.route(
        prompt: 'Plan a release deployment and verification rollout.',
        intent: TurnIntent.plan,
        configs: agents,
        auto: true,
      );

      expect(selection.agent?.id, 'release-planner');
      expect(selection.matchedTerms, containsAll(['release', 'deployment']));
    },
  );
}
