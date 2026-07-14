import 'package:circuit_ide/agent/tools/tool_registry.dart';
import 'package:circuit_ide/models/agent_workspace.dart';
import 'package:circuit_ide/models/studio_shell.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:circuit_ide/ui/studio/studio_shell.dart';
import 'package:circuit_ide/ui/studio/studio_turn_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a queued research task keeps the Research tool contract at dispatch',
    () {
      final task = AgentTask(
        id: 'research-queue-1',
        mascotAlias: 'Benny',
        profile: AgentTaskProfile.research,
        status: AgentTaskStatus.queued,
        goal: 'Compare official deployment guidance',
        backgroundExecutionRequested: true,
        createdAt: DateTime.utc(2026, 7, 13),
      );

      final promptMode = backgroundTaskPromptMode(task);
      final toolMode = studioToolModeForIntent(
        intent: TurnIntent.ask,
        promptMode: promptMode ?? StudioPromptMode.ask,
        hasWorkspace: true,
        planModeEnabled: false,
      );

      expect(promptMode, StudioPromptMode.research);
      expect(toolMode, AgentToolMode.research);
      expect(
        ToolRegistry.toolsForMode(toolMode).map((tool) => tool.name).toSet(),
        {'web_search', 'web_fetch'},
      );
    },
  );

  test('non-research background work cannot inherit the Research contract', () {
    final task = AgentTask(
      id: 'review-queue-1',
      mascotAlias: 'Clark',
      profile: AgentTaskProfile.review,
      goal: 'Review current work',
      backgroundExecutionRequested: true,
      createdAt: DateTime.utc(2026, 7, 13),
    );

    expect(backgroundTaskPromptMode(task), isNull);
  });
}
