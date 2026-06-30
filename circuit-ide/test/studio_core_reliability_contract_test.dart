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
      final leftRailSource = await File(
        'lib/ui/studio/studio_left_rail.dart',
      ).readAsString();
      final runtimeSource = await File(
        'lib/state/agent_turn_runtime_provider.dart',
      ).readAsString();
      final senderSource = await File(
        'lib/ui/studio/studio_message_sender.dart',
      ).readAsString();
      final reviewPanelSource = await File(
        'lib/ui/studio/studio_review_panel.dart',
      ).readAsString();
      final drawerSource = await File(
        'lib/ui/studio/studio_right_drawer.dart',
      ).readAsString();
      final progressPanelSource = await File(
        'lib/ui/studio/studio_progress_panel.dart',
      ).readAsString();
      final composerSource = await File(
        'lib/ui/studio/studio_prompt_composer.dart',
      ).readAsString();
      final shellSource = await File(
        'lib/ui/studio/studio_shell.dart',
      ).readAsString();
      final projectHistorySource = await File(
        'lib/state/studio_project_history_provider.dart',
      ).readAsString();
      final sourceArtifactSource = await File(
        'lib/state/studio_source_artifact_provider.dart',
      ).readAsString();

      expect(taskViewSource, contains('Implement this plan'));
      expect(taskViewSource, contains('Continue next batch'));
      expect(taskViewSource, contains('Patch conflict'));
      expect(taskViewSource, contains('Needs rebase before apply'));
      expect(taskViewSource, contains('Refresh patch'));
      expect(taskViewSource, contains('ListView.builder'));
      expect(taskViewSource, contains('_TaskTranscriptIndex'));
      expect(taskViewSource, contains('_TurnTranscriptItem'));
      expect(taskViewSource, contains('_PlanProgressSnapshot'));
      expect(taskViewSource, contains('_PatchVerificationSnapshot'));
      expect(taskViewSource, contains('state.threadForTaskView(taskId)'));
      expect(taskViewSource, contains('_DraftPlanActionFooter'));
      expect(
        taskViewSource,
        contains('Actions unlock when Circuit finishes writing the plan.'),
      );
      expect(taskViewSource, contains('RepaintBoundary'));
      expect(taskViewSource, contains('patchProposalProvider.select('));
      expect(taskViewSource, contains('ValueKey(\'studio-turn-\${turn.id}\')'));
      expect(taskViewSource, isNot(contains('...turnWidgets')));
      expect(leftRailSource, contains('ListView.builder'));
      expect(
        leftRailSource,
        contains("ValueKey('studio-rail-project-\$path')"),
      );
      expect(leftRailSource, contains('_maxCollapsedRailConversations'));
      expect(leftRailSource, contains('_ShowMoreConversationsRow'));
      expect(
        leftRailSource,
        contains('commandRunProvider.select(_runningCommandTaskKey)'),
      );
      expect(leftRailSource, contains('_runningCommandTaskKey'));
      expect(
        runtimeSource,
        contains('required List<ChatMessage> modelHistory'),
      );
      expect(runtimeSource, isNot(contains('historyOverride')));
      expect(senderSource, contains('modelHistory: priorThreadMessages'));
      expect(senderSource, isNot(contains('historyOverride')));
      expect(reviewPanelSource, contains('Patch conflict'));
      expect(reviewPanelSource, contains('Refresh patch'));
      expect(reviewPanelSource, contains('Ask Circuit to rebase'));
      expect(drawerSource, contains('_PatchDiffReviewDrawer'));
      expect(drawerSource, contains('_MissingPatchReviewDrawer'));
      expect(drawerSource, contains('_PatchReviewActionBar'));
      expect(drawerSource, contains('Apply changes'));
      expect(drawerSource, contains('Ask for revision'));
      expect(drawerSource, contains('Refresh patch'));
      expect(drawerSource, contains('Restore checkpoint'));
      expect(drawerSource, contains('Patch review unavailable'));
      expect(drawerSource, contains('openRepositoryDiff'));
      expect(
        drawerSource,
        contains(
          'studioThreadProvider.select((state) => state.threadForTaskView',
        ),
      );
      expect(
        drawerSource,
        contains('patchProposalProvider.select((state) => _patchForTurn'),
      );
      expect(drawerSource, contains('commandRunProvider.select('));
      expect(
        progressPanelSource,
        contains(
          'studioThreadProvider.select((state) => state.threadForTaskView',
        ),
      );
      expect(
        progressPanelSource,
        contains('patchProposalProvider.select((state) => _patchForTurn'),
      );
      expect(progressPanelSource, contains('commandRunProvider.select('));
      expect(composerSource, isNot(contains('chatProvider')));
      expect(composerSource, contains('studioControls = ref.watch'));
      expect(
        composerSource,
        contains('fileTreeProvider.select((state) => state.rootPath)'),
      );
      expect(
        composerSource,
        contains('gitProvider.select((state) => state.status.branch)'),
      );
      expect(shellSource, contains('state) => state.mode'));
      expect(
        shellSource,
        contains('studioThreadProvider.select((threadState) {'),
      );
      expect(
        shellSource,
        contains('threadState.threadForTaskView(studio.selectedTaskId);'),
      );
      expect(
        shellSource,
        isNot(contains('final studio = ref.watch(studioShellProvider);')),
      );
      expect(
        projectHistorySource,
        isNot(contains('ref.listen(studioThreadProvider')),
      );
      expect(
        projectHistorySource,
        isNot(contains('ref.listen(agentWorkspaceProvider')),
      );
      expect(
        leftRailSource,
        contains(
          'settingsProvider.select((settings) => settings.recentProjects)',
        ),
      );
      expect(leftRailSource, contains('state.byPath.keys.join'));
      expect(
        sourceArtifactSource,
        contains('StudioFeatureFlags.advancedStudioSurfaces'),
      );
      expect(sourceArtifactSource, contains('_isQuarantinedArtifact'));
      expect(
        sourceArtifactSource,
        contains('StudioSourceArtifactKind.browserComment'),
      );
      expect(sourceArtifactSource, contains('_threadSyncFingerprints'));
      expect(sourceArtifactSource, contains('_patchSyncFingerprints'));
      expect(
        sourceArtifactSource,
        contains('studioSourceArtifactsForThreadProvider'),
      );
      expect(drawerSource, contains('studioSourceArtifactByIdProvider'));
      expect(
        drawerSource,
        isNot(contains('ref.watch(studioSourceArtifactProvider).artifacts')),
      );
    },
  );
}

Set<String> _toolNames(AgentToolMode mode) {
  return ToolRegistry.toolsForMode(mode).map((tool) => tool.name).toSet();
}
