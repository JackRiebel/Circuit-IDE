import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/platform_utils.dart';
import '../../enums/connection_status.dart';
import '../../models/command_descriptor.dart';
import '../../models/run_diagnostics_summary.dart';
import '../../state/agent_run_provider.dart';
import '../../state/ai_context_provider.dart';
import '../../state/chat_context_draft_provider.dart';
import '../../state/chat_provider.dart';
import '../../state/command_palette_provider.dart';
import '../../state/connection_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/layout_provider.dart';
import '../../state/project_profile_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/terminal_provider.dart';
import '../../state/work_item_provider.dart';
import '../../state/workspace_context_provider.dart';
import '../../ui/chat/ai_workbench_panel.dart';
import '../../ui/layout/activity_bar.dart';

class CoreCommandRegistry {
  static void register(WidgetRef ref) {
    ref.read(commandPaletteProvider.notifier).registerCommands([
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
                  'Explain this project using the project profile and L-SDF map. '
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
        id: 'workspace.refreshContext',
        title: 'Refresh Workspace',
        description: 'Refresh workspace file index and code map.',
        category: 'Workspace',
        icon: Icons.refresh,
        shortcut: '⌘⇧M',
        isEnabled: () => ref.read(fileTreeProvider).rootPath != null,
        run: () => ref.read(workspaceContextProvider.notifier).refresh(),
      ),
      CommandDescriptor(
        id: 'workspace.rebuildLsdf',
        title: 'Force Rebuild L-SDF',
        description: 'Rebuild the L-SDF map even when files already exist.',
        category: 'Workspace',
        icon: Icons.hub_outlined,
        isEnabled: () => ref.read(fileTreeProvider).rootPath != null,
        run: () => ref
            .read(workspaceContextProvider.notifier)
            .refresh(forceLsdf: true),
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
        description:
            'Reconnect using saved credentials for the active provider.',
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
        id: 'context.toggleLsdf',
        title: 'Toggle L-SDF Context',
        category: 'Context',
        icon: Icons.hub_outlined,
        run: () {
          ref.read(aiContextProvider.notifier).toggleLsdfIndex();
          ref.read(chatContextDraftProvider.notifier).syncPinnedContext();
        },
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
        run: () => ref.read(editorProvider.notifier).openSettingsTab(),
      ),
    ]);
  }

  static void _showSidePanel(WidgetRef ref, ActivityBarItem item) {
    ref.read(activeActivityItemProvider.notifier).set(item);
    ref.read(sidePanelVisibleProvider.notifier).set(true);
  }
}
