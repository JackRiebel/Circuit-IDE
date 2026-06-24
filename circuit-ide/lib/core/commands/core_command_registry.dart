import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/platform_utils.dart';
import '../../enums/connection_status.dart';
import '../../models/agent_workspace.dart';
import '../../models/command_descriptor.dart';
import '../../models/run_diagnostics_summary.dart';
import '../../models/studio_shell.dart';
import '../../state/agent_run_provider.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/ai_context_provider.dart';
import '../../state/chat_context_draft_provider.dart';
import '../../state/chat_provider.dart';
import '../../state/command_palette_provider.dart';
import '../../state/connection_provider.dart';
import '../../state/context_pack_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/layout_provider.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/project_profile_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/terminal_provider.dart';
import '../../state/work_item_provider.dart';
import '../../state/workspace_context_provider.dart';
import '../../ui/chat/ai_workbench_panel.dart';
import '../../ui/layout/activity_bar.dart';

class CoreCommandRegistry {
  static void register(WidgetRef ref) {
    final commands = <CommandDescriptor>[
      CommandDescriptor(
        id: 'project.openCockpit',
        title: 'Open Project Cockpit',
        description:
            'Show stack, readiness, recommended checks, and guided work.',
        category: 'Project',
        icon: Icons.space_dashboard_outlined,
        surface: 'cockpit',
        priority: 100,
        run: () {
          _showSidePanel(ref, ActivityBarItem.tools);
          unawaited(ref.read(projectProfileProvider.notifier).refresh());
        },
      ),
      CommandDescriptor(
        id: 'studio.home',
        title: 'Open Studio Home',
        description: 'Return to the Cisco Circuit prompt-first home.',
        category: 'Studio',
        icon: Icons.dashboard_customize_outlined,
        priority: 120,
        run: () => ref.read(studioShellProvider.notifier).openHome(),
      ),
      CommandDescriptor(
        id: 'studio.newTask',
        title: 'New Circuit Task',
        description: 'Start a supervised Cisco Circuit coding task.',
        category: 'Studio',
        icon: Icons.edit_square,
        priority: 118,
        run: () {
          ref
              .read(studioShellProvider.notifier)
              .setPromptMode(StudioPromptMode.code);
          ref.read(studioShellProvider.notifier).openHome();
        },
      ),
      CommandDescriptor(
        id: 'studio.backToStudio',
        title: 'Back to Studio',
        description: 'Leave Advanced Editor and return to Studio Home.',
        category: 'Studio',
        icon: Icons.home_outlined,
        priority: 115,
        run: () => ref.read(studioShellProvider.notifier).openHome(),
      ),
      CommandDescriptor(
        id: 'studio.reviewChanges',
        title: 'Review Changes',
        description: 'Open the beginner-friendly Studio review surface.',
        category: 'Studio',
        icon: Icons.rate_review_outlined,
        priority: 114,
        isEnabled: () => ref.read(patchProposalProvider).active != null,
        run: () => ref.read(studioShellProvider.notifier).openReview(),
      ),
      CommandDescriptor(
        id: 'project.startWorkItem',
        title: 'Start Work Item',
        description: 'Create a guided task with steps, checks, and handoff.',
        category: 'Project',
        icon: Icons.add_task_outlined,
        surface: 'cockpit',
        priority: 90,
        recommendedWhen: 'A workspace is open and the next action is unclear.',
        isEnabled: () => ref.read(fileTreeProvider).rootPath != null,
        run: () {
          _showSidePanel(ref, ActivityBarItem.tools);
          ref
              .read(workItemProvider.notifier)
              .start(
                'Review this project and suggest the safest next improvement',
              );
        },
      ),
      CommandDescriptor(
        id: 'project.runRecommendedChecks',
        title: 'Run Recommended Checks',
        description:
            'Run detected lint, test, or build checks for this project.',
        category: 'Project',
        icon: Icons.playlist_add_check_outlined,
        surface: 'cockpit',
        priority: 85,
        isEnabled: () =>
            ref.read(projectProfileProvider).commands.any((c) => c.enabled),
        run: () {
          _showSidePanel(ref, ActivityBarItem.tools);
          ref.read(workItemProvider.notifier).start('Run recommended checks');
          unawaited(ref.read(workItemProvider.notifier).runVerification());
        },
      ),
      CommandDescriptor(
        id: 'project.explain',
        title: 'Explain Project',
        description:
            'Ask AI to explain stack, architecture, and safe next steps.',
        category: 'Project',
        icon: Icons.psychology_outlined,
        surface: 'cockpit',
        priority: 80,
        isEnabled: () => ref.read(fileTreeProvider).rootPath != null,
        run: () {
          ref.read(chatPanelVisibleProvider.notifier).set(true);
          unawaited(
            ref
                .read(chatProvider.notifier)
                .sendMessage(
                  'Explain this project using the project profile and visible context. '
                  'Cover stack, entrypoints, architecture, and safest next steps.',
                ),
          );
        },
      ),
      CommandDescriptor(
        id: 'project.summarizeChanges',
        title: 'Summarize Current Changes',
        description: 'Create a concise handoff from the current working tree.',
        category: 'Project',
        icon: Icons.summarize_outlined,
        surface: 'cockpit',
        priority: 75,
        isEnabled: () => ref.read(projectProfileProvider).changedFiles > 0,
        run: () {
          ref.read(chatPanelVisibleProvider.notifier).set(true);
          unawaited(
            ref
                .read(chatProvider.notifier)
                .sendMessage(
                  'Summarize the current working tree changes as a handoff. '
                  'Include files changed, risk, tests run, and next steps.',
                ),
          );
        },
      ),
      CommandDescriptor(
        id: 'project.copyHandoff',
        title: 'Create Handoff Summary',
        description: 'Copy the active guided work item handoff.',
        category: 'Project',
        icon: Icons.copy_all_outlined,
        surface: 'cockpit',
        priority: 70,
        run: () {
          Clipboard.setData(
            ClipboardData(
              text: ref.read(workItemProvider.notifier).handoffSummary(),
            ),
          );
          _showSidePanel(ref, ActivityBarItem.tools);
        },
      ),
      CommandDescriptor(
        id: 'project.refreshContextPack',
        title: 'Build Coding Context Pack',
        description: 'Preview the context Circuit AI will use for guided work.',
        category: 'Project',
        icon: Icons.dataset_linked_outlined,
        surface: 'cockpit',
        priority: 68,
        isEnabled: () => ref.read(fileTreeProvider).rootPath != null,
        run: () {
          _showSidePanel(ref, ActivityBarItem.tools);
          ref.read(contextPackProvider.notifier).buildForCodingTask();
        },
      ),
      CommandDescriptor(
        id: 'agentWorkspace.open',
        title: 'Open Agent Workspace',
        description: 'Show supervised parallel tasks in Project Cockpit.',
        category: 'Agent Workspace',
        icon: Icons.supervised_user_circle_outlined,
        surface: 'cockpit',
        priority: 88,
        run: () => _showSidePanel(ref, ActivityBarItem.tools),
      ),
      CommandDescriptor(
        id: 'agentWorkspace.startParallelTask',
        title: 'Start Parallel Task',
        description:
            'Start a supervised investigation with reviewed writes and commands.',
        category: 'Agent Workspace',
        icon: Icons.play_arrow_outlined,
        surface: 'cockpit',
        priority: 86,
        isEnabled: () => ref.read(fileTreeProvider).rootPath != null,
        run: () {
          _showSidePanel(ref, ActivityBarItem.tools);
          ref
              .read(agentWorkspaceProvider.notifier)
              .startTask(
                goal:
                    'Investigate this project and propose the safest next coding step.',
                profile: AgentTaskProfile.investigate,
              );
        },
      ),
      CommandDescriptor(
        id: 'agentWorkspace.approveSelectedProposal',
        title: 'Approve Selected Proposal',
        description: 'Apply the active reviewed patch proposal.',
        category: 'Agent Workspace',
        icon: Icons.check_circle_outline,
        surface: 'cockpit',
        priority: 84,
        isEnabled: () => ref.read(patchProposalProvider).active != null,
        run: () =>
            unawaited(ref.read(patchProposalProvider.notifier).applyActive()),
      ),
      CommandDescriptor(
        id: 'agentWorkspace.rejectSelectedProposal',
        title: 'Reject Selected Proposal',
        description: 'Reject the active supervised patch proposal.',
        category: 'Agent Workspace',
        icon: Icons.cancel_outlined,
        surface: 'cockpit',
        priority: 83,
        isEnabled: () => ref.read(patchProposalProvider).active != null,
        run: () => ref.read(patchProposalProvider.notifier).rejectActive(),
      ),
      CommandDescriptor(
        id: 'agentWorkspace.compareProposals',
        title: 'Compare Proposals',
        description: 'Copy a comparison of supervised agent patch proposals.',
        category: 'Agent Workspace',
        icon: Icons.compare_arrows,
        surface: 'cockpit',
        priority: 82,
        run: () {
          Clipboard.setData(
            ClipboardData(
              text: ref
                  .read(agentWorkspaceProvider.notifier)
                  .compareProposals(),
            ),
          );
          _showSidePanel(ref, ActivityBarItem.tools);
        },
      ),
      CommandDescriptor(
        id: 'agentWorkspace.runVerification',
        title: 'Run Verification',
        description: 'Run recommended checks for the active work item.',
        category: 'Agent Workspace',
        icon: Icons.playlist_add_check_outlined,
        surface: 'cockpit',
        priority: 81,
        run: () {
          _showSidePanel(ref, ActivityBarItem.tools);
          unawaited(ref.read(workItemProvider.notifier).runVerification());
        },
      ),
      CommandDescriptor(
        id: 'agentWorkspace.restoreCheckpoint',
        title: 'Restore Checkpoint',
        description: 'Restore the active patch checkpoint when available.',
        category: 'Agent Workspace',
        icon: Icons.restore_outlined,
        surface: 'cockpit',
        priority: 79,
        isEnabled: () =>
            ref.read(patchProposalProvider).active?.checkpointId != null,
        run: () {
          final checkpointId = ref
              .read(patchProposalProvider)
              .active
              ?.checkpointId;
          if (checkpointId == null) return;
          unawaited(
            ref
                .read(patchProposalProvider.notifier)
                .restoreCheckpoint(checkpointId),
          );
        },
      ),
      CommandDescriptor(
        id: 'agentWorkspace.copyTaskDiagnostics',
        title: 'Copy Task Diagnostics',
        description: 'Copy diagnostics for the selected supervised task.',
        category: 'Agent Workspace',
        icon: Icons.assignment_outlined,
        surface: 'cockpit',
        priority: 78,
        isEnabled: () => ref.read(agentWorkspaceProvider).selectedTask != null,
        run: () {
          final task = ref.read(agentWorkspaceProvider).selectedTask;
          if (task == null) return;
          Clipboard.setData(
            ClipboardData(
              text: ref
                  .read(agentWorkspaceProvider.notifier)
                  .diagnosticsFor(task.id),
            ),
          );
        },
      ),
      CommandDescriptor(
        id: 'project.approvePatch',
        title: 'Approve Active Patch',
        description: 'Apply the active reviewed patch proposal.',
        category: 'Project',
        icon: Icons.check,
        surface: 'cockpit',
        priority: 67,
        isEnabled: () => ref.read(patchProposalProvider).active != null,
        run: () =>
            unawaited(ref.read(patchProposalProvider.notifier).applyActive()),
      ),
      CommandDescriptor(
        id: 'project.rejectPatch',
        title: 'Reject Active Patch',
        description: 'Reject the active reviewed patch proposal.',
        category: 'Project',
        icon: Icons.close,
        surface: 'cockpit',
        priority: 66,
        isEnabled: () => ref.read(patchProposalProvider).active != null,
        run: () => ref.read(patchProposalProvider.notifier).rejectActive(),
      ),
      CommandDescriptor(
        id: 'workspace.refreshContext',
        title: 'Refresh Workspace',
        description: 'Refresh the lightweight workspace file index.',
        category: 'Workspace',
        icon: Icons.refresh,
        shortcut: '⌘⇧M',
        isEnabled: () => ref.read(fileTreeProvider).rootPath != null,
        run: () => ref.read(workspaceContextProvider.notifier).refresh(),
      ),
      CommandDescriptor(
        id: 'workspace.health',
        title: 'Open Workspace Health',
        description: 'Focus the workspace tools and status surfaces.',
        category: 'Workspace',
        icon: Icons.health_and_safety_outlined,
        run: () => _showSidePanel(ref, ActivityBarItem.tools),
      ),
      CommandDescriptor(
        id: 'file.openQuick',
        title: 'Open File',
        description: 'Open search as the file quick-open surface.',
        category: 'File',
        icon: Icons.file_open_outlined,
        run: () => _showSidePanel(ref, ActivityBarItem.search),
      ),
      CommandDescriptor(
        id: 'ai.runConsole',
        title: 'Open Run Console',
        description: 'Show active and recent AI runs.',
        category: 'AI',
        icon: Icons.fact_check_outlined,
        run: () {
          ref.read(chatPanelVisibleProvider.notifier).set(true);
          ref.read(aiWorkbenchTabProvider.notifier).set(WorkbenchTab.activity);
        },
      ),
      CommandDescriptor(
        id: 'ai.copyLatestRun',
        title: 'Copy Latest Run Summary',
        category: 'AI',
        icon: Icons.copy,
        isEnabled: () => ref.read(agentRunProvider).latestRun != null,
        run: () {
          final run = ref.read(agentRunProvider).latestRun;
          if (run == null) return;
          Clipboard.setData(
            ClipboardData(text: RunDiagnosticsSummary(run).serialize()),
          );
          ref.read(chatPanelVisibleProvider.notifier).set(true);
          ref.read(aiWorkbenchTabProvider.notifier).set(WorkbenchTab.activity);
        },
      ),
      CommandDescriptor(
        id: 'ai.reconnect',
        title: 'Reconnect AI',
        description: 'Reconnect using saved Circuit Company AI credentials.',
        category: 'AI',
        icon: Icons.power_settings_new,
        run: () async {
          ref
              .read(connectionStatusProvider.notifier)
              .set(ConnectionStatus.connecting);
          final service = ref.read(agentServiceProvider);
          final workingDir =
              ref.read(fileTreeProvider).rootPath ?? PlatformUtils.scratchDir;
          final success = await service.connectWithSavedCredentials(
            workingDir: workingDir,
            preferredProvider: ref.read(settingsProvider).activeProvider,
          );
          ref
              .read(connectionStatusProvider.notifier)
              .set(
                success ? ConnectionStatus.connected : ConnectionStatus.error,
              );
        },
      ),
      CommandDescriptor(
        id: 'view.explorer',
        title: 'Show Explorer',
        category: 'View',
        icon: Icons.folder_outlined,
        shortcut: '⌘B',
        run: () => _showSidePanel(ref, ActivityBarItem.explorer),
      ),
      CommandDescriptor(
        id: 'view.search',
        title: 'Show Search',
        category: 'View',
        icon: Icons.search,
        run: () => _showSidePanel(ref, ActivityBarItem.search),
      ),
      CommandDescriptor(
        id: 'view.sourceControl',
        title: 'Show Source Control',
        category: 'View',
        icon: Icons.account_tree_outlined,
        run: () => _showSidePanel(ref, ActivityBarItem.git),
      ),
      CommandDescriptor(
        id: 'view.tools',
        title: 'Show Tools',
        description: 'Open advanced tools, MCP, agents, rules, and notebooks.',
        category: 'View',
        icon: Icons.widgets_outlined,
        run: () => _showSidePanel(ref, ActivityBarItem.tools),
      ),
      CommandDescriptor(
        id: 'view.toggleTerminal',
        title: 'Toggle Terminal',
        category: 'View',
        icon: Icons.terminal,
        shortcut: '⌘J',
        run: () => ref.read(terminalProvider.notifier).toggle(),
      ),
      CommandDescriptor(
        id: 'view.toggleAI',
        title: 'Toggle AI Assistant',
        category: 'View',
        icon: Icons.auto_awesome,
        shortcut: '⌘⇧L',
        run: () => ref.read(chatPanelVisibleProvider.notifier).toggle(),
      ),
      CommandDescriptor(
        id: 'context.toggleActiveFile',
        title: 'Toggle Active File Context',
        category: 'Context',
        icon: Icons.description_outlined,
        run: () {
          ref.read(aiContextProvider.notifier).toggleActiveFile();
          ref.read(chatContextDraftProvider.notifier).syncPinnedContext();
        },
      ),
      CommandDescriptor(
        id: 'context.toggleTerminal',
        title: 'Toggle Terminal Context',
        category: 'Context',
        icon: Icons.terminal,
        run: () {
          ref.read(aiContextProvider.notifier).toggleTerminalOutput();
          ref.read(chatContextDraftProvider.notifier).syncPinnedContext();
        },
      ),
      CommandDescriptor(
        id: 'context.toggleGitDiff',
        title: 'Toggle Git Diff Context',
        category: 'Context',
        icon: Icons.account_tree_outlined,
        run: () {
          ref.read(aiContextProvider.notifier).toggleGitDiff();
          ref.read(chatContextDraftProvider.notifier).syncPinnedContext();
        },
      ),
      CommandDescriptor(
        id: 'file.save',
        title: 'Save Active File',
        category: 'File',
        icon: Icons.save_outlined,
        shortcut: '⌘S',
        isEnabled: () => ref.read(editorProvider).activeTab != null,
        run: () => ref.read(editorProvider.notifier).saveActiveFile(),
      ),
      CommandDescriptor(
        id: 'settings.open',
        title: 'Open Settings',
        category: 'Preferences',
        icon: Icons.settings_outlined,
        run: () => ref.read(studioShellProvider.notifier).openSettings(),
      ),
    ];
    ref
        .read(commandPaletteProvider.notifier)
        .registerCommands(
          commands
              .where(
                (command) => !_studioQuarantinedCommandIds.contains(command.id),
              )
              .toList(),
        );
  }

  static void _showSidePanel(WidgetRef ref, ActivityBarItem item) {
    ref.read(activeActivityItemProvider.notifier).set(item);
    ref.read(sidePanelVisibleProvider.notifier).set(true);
  }
}

const _studioQuarantinedCommandIds = <String>{
  'project.openCockpit',
  'project.startWorkItem',
  'project.runRecommendedChecks',
  'project.explain',
  'project.summarizeChanges',
  'project.copyHandoff',
  'project.refreshContextPack',
  'agentWorkspace.open',
  'agentWorkspace.startParallelTask',
  'agentWorkspace.approveSelectedProposal',
  'agentWorkspace.rejectSelectedProposal',
  'agentWorkspace.compareProposals',
  'agentWorkspace.runVerification',
  'agentWorkspace.restoreCheckpoint',
  'agentWorkspace.copyTaskDiagnostics',
  'project.approvePatch',
  'project.rejectPatch',
  'workspace.health',
  'file.openQuick',
  'ai.runConsole',
  'ai.copyLatestRun',
  'view.explorer',
  'view.search',
  'view.sourceControl',
  'view.tools',
  'view.toggleTerminal',
  'view.toggleAI',
  'file.save',
};
