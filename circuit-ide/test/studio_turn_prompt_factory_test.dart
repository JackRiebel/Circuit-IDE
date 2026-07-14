import 'package:circuit_ide/agent/studio_turn_prompt_factory.dart';
import 'package:circuit_ide/agent/tools/tool_registry.dart';
import 'package:circuit_ide/models/accepted_plan_context.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const acceptedPlan = AcceptedPlanContext(
    patchSetId: 'plan-router',
    title: 'Route authentication',
    summary: 'Add the authenticated route.',
    markdown: 'Implement the route and verify it.',
    plannedTargets: [
      PlannedFileTarget(
        path: 'lib/router.dart',
        intent: 'Add authenticated route',
        operation: ProposedFileEditType.modify,
      ),
    ],
  );

  test(
    'keeps accepted-plan and repair prompts inside the app-owned contract',
    () {
      final message = StudioTurnPromptFactory.messageWithAcceptedPlan(
        'Implement it.',
        acceptedPlan,
      );
      final repair = StudioTurnPromptFactory.outcomeRepairPrompt(
        intent: TurnIntent.code,
        toolMode: AgentToolMode.code,
        acceptedPlan: acceptedPlan,
        violation: 'The patch did not include the route.',
      );

      expect(message, contains('<accepted_plan_context>'));
      expect(message, contains('lib/router.dart [modify]'));
      expect(
        message,
        contains('Do not call command, write, edit, git mutation'),
      );
      expect(repair, contains('Repair this accepted-plan Code turn'));
      expect(repair, contains('Do not re-plan.'));
      expect(
        StudioTurnPromptFactory.boundedInspectionQuestion(acceptedPlan),
        'What exact behavior should I implement in lib/router.dart?',
      );
    },
  );

  test('keeps research repair isolated to explicit source acquisition', () {
    final repair = StudioTurnPromptFactory.outcomeRepairPrompt(
      intent: TurnIntent.ask,
      toolMode: AgentToolMode.research,
      violation: 'A second publisher is required.',
    );

    expect(repair, contains('only `web_search` and `web_fetch`'));
    expect(repair, contains('Do not inspect the workspace'));
    expect(repair, contains('Evidence gap to repair: A second publisher'));
  });

  test('maps phase and declared limits without changing runtime policy', () {
    expect(
      StudioTurnPromptFactory.phaseFor(
        AgentToolMode.code,
        0,
        hasAcceptedPlan: false,
      ),
      AgentToolPhase.inspect,
    );
    expect(
      StudioTurnPromptFactory.phaseFor(
        AgentToolMode.code,
        1,
        hasAcceptedPlan: false,
      ),
      AgentToolPhase.propose,
    );
    expect(
      StudioTurnPromptFactory.phaseFor(
        AgentToolMode.verify,
        0,
        hasAcceptedPlan: false,
      ),
      AgentToolPhase.verify,
    );
    expect(StudioTurnPromptFactory.iterationLimit(AgentToolMode.plan, 99), 4);
    expect(StudioTurnPromptFactory.iterationLimit(AgentToolMode.code, 0), 1);
  });
}
