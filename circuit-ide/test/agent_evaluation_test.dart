import 'package:circuit_ide/models/agent_config_model.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'agent evaluation fixtures gate activation on contract and tool bounds',
    () {
      final config = AgentConfigModel(
        id: 'evidence-reviewer',
        name: 'Evidence reviewer',
        allowedIntents: const {TurnIntent.ask, TurnIntent.review},
        outputContracts: const {
          AgentOutputContract.summary,
          AgentOutputContract.evidence,
        },
        limits: const AgentExecutionLimits(maxToolCalls: 4),
        evaluationSuite: const AgentEvaluationSuite(
          cases: [
            AgentEvaluationCase(
              id: 'source-check',
              prompt: 'Review source freshness and cite evidence.',
              intent: TurnIntent.review,
              requiredOutputContracts: {
                AgentOutputContract.summary,
                AgentOutputContract.evidence,
              },
              maxToolCalls: 2,
              requiresCitation: true,
            ),
          ],
        ),
        createdAt: DateTime(2026, 7, 11),
      );

      expect(config.evaluationReport.passedGate, isTrue);
      expect(config.evaluationReport.passed, 1);
    },
  );

  test('evaluation reports regressions that would weaken agent behavior', () {
    final config = AgentConfigModel(
      id: 'summary-agent',
      name: 'Summary agent',
      allowedIntents: const {TurnIntent.ask},
      outputContracts: const {AgentOutputContract.summary},
      limits: const AgentExecutionLimits(maxToolCalls: 1),
      evaluationSuite: const AgentEvaluationSuite(
        cases: [
          AgentEvaluationCase(
            id: 'unsupported-review',
            prompt: 'Review this change with citations.',
            intent: TurnIntent.review,
            requiredOutputContracts: {AgentOutputContract.evidence},
            maxToolCalls: 2,
            requiresCitation: true,
          ),
        ],
      ),
      createdAt: DateTime(2026, 7, 11),
    );

    expect(config.evaluationReport.passedGate, isFalse);
    expect(
      config.evaluationReport.failures.join(' '),
      allOf(contains('not an allowed intent'), contains('tool-call limit')),
    );
  });
}
