import 'dart:io';

import 'package:circuit_ide/agent/security/agent_tool_permission_policy.dart';
import 'package:circuit_ide/agent/tools/tool_registry.dart';
import 'package:circuit_ide/models/agent_tool_permission.dart';
import 'package:circuit_ide/models/studio_shell.dart';
import 'package:circuit_ide/models/tool_call_info.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('core intent classifier keeps greetings and discovery non-mutating', () {
    expect(
      IntentClassifier.classify(
        'hello',
        promptMode: StudioPromptMode.code,
        planModeEnabled: true,
      ),
      TurnIntent.chat,
    );
    expect(
      IntentClassifier.classify(
        'I want to build something to help me size out datacenters for customers',
        promptMode: StudioPromptMode.code,
        planModeEnabled: false,
      ),
      TurnIntent.ask,
    );
    expect(
      IntentClassifier.classify(
        'Refactor src/main.dart and create an implementation plan first.',
        promptMode: StudioPromptMode.code,
        planModeEnabled: true,
      ),
      TurnIntent.plan,
    );
  });

  test('tool profiles preserve chat plan code verify boundaries', () {
    final chatTools = _toolNames(AgentToolMode.chat);
    final askTools = _toolNames(AgentToolMode.ask);
    final planTools = _toolNames(AgentToolMode.plan);
    final codeTools = _toolNames(AgentToolMode.code);
    final verifyTools = _toolNames(AgentToolMode.verify);

    expect(chatTools, isEmpty);
    expect(askTools, containsAll({'read_file', 'search_files'}));
    expect(askTools, isNot(contains('propose_patch')));
    expect(askTools, isNot(contains('run_command')));
    expect(planTools, contains('propose_patch'));
    expect(planTools, isNot(contains('run_command')));
    expect(planTools, isNot(contains('apply_patch_set')));
    expect(codeTools, contains('propose_patch'));
    expect(codeTools, isNot(contains('run_command')));
    expect(codeTools, isNot(contains('apply_patch_set')));
    expect(verifyTools, contains('run_command'));
    expect(verifyTools, isNot(contains('propose_patch')));
  });

  test(
    'permission policy denies mutation until app-owned review or approval',
    () {
      final root = Directory.systemTemp.createTempSync(
        'studio_reliability_policy_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final chatPolicy = AgentToolPermissionPolicy(
        workingDir: root.path,
        request: const ToolPermissionRequest(
          intent: TurnIntent.chat,
          phase: ToolPermissionPhase.inspect,
        ),
      );
      final planPolicy = AgentToolPermissionPolicy(
        workingDir: root.path,
        request: const ToolPermissionRequest(
          intent: TurnIntent.plan,
          phase: ToolPermissionPhase.propose,
        ),
      );
      final verifyPolicy = AgentToolPermissionPolicy(
        workingDir: root.path,
        request: const ToolPermissionRequest(
          intent: TurnIntent.verify,
          phase: ToolPermissionPhase.verify,
          commandCategory: CommandCategory.test,
        ),
      );

      expect(
        chatPolicy
            .evaluate(const ToolCallInfo(id: 'read', name: 'read_file'))
            .verdict,
        ToolPermissionVerdict.deny,
      );
      expect(
        planPolicy
            .evaluate(const ToolCallInfo(id: 'patch', name: 'propose_patch'))
            .verdict,
        ToolPermissionVerdict.allow,
      );
      expect(
        planPolicy
            .evaluate(
              const ToolCallInfo(
                id: 'command',
                name: 'run_command',
                arguments: {'command': 'flutter test'},
              ),
            )
            .verdict,
        ToolPermissionVerdict.deny,
      );
      expect(
        verifyPolicy
            .evaluate(
              const ToolCallInfo(
                id: 'command',
                name: 'run_command',
                arguments: {'command': 'flutter test'},
              ),
            )
            .verdict,
        ToolPermissionVerdict.ask,
      );
    },
  );

  test(
    'Studio review surfaces expose actionable plan and conflict outcomes',
    () async {
      final taskViewSource = await File(
        'lib/ui/studio/studio_task_view.dart',
      ).readAsString();
      final reviewPanelSource = await File(
        'lib/ui/studio/studio_review_panel.dart',
      ).readAsString();
      final composerSource = await File(
        'lib/ui/studio/studio_prompt_composer.dart',
      ).readAsString();

      expect(taskViewSource, contains('Implement this plan'));
      expect(taskViewSource, contains('Continue next batch'));
      expect(taskViewSource, contains('Patch conflict'));
      expect(taskViewSource, contains('Needs rebase before apply'));
      expect(reviewPanelSource, contains('Patch conflict'));
      expect(reviewPanelSource, contains('Ask Circuit to rebase'));
      expect(composerSource, isNot(contains('chatProvider')));
    },
  );
}

Set<String> _toolNames(AgentToolMode mode) {
  return ToolRegistry.toolsForMode(mode).map((tool) => tool.name).toSet();
}
