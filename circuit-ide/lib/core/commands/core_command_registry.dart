import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/platform_utils.dart';
import '../../enums/connection_status.dart';
import '../../models/command_descriptor.dart';
import '../../state/agent_run_provider.dart';
import '../../state/ai_context_provider.dart';
import '../../state/chat_context_draft_provider.dart';
import '../../state/command_palette_provider.dart';
import '../../state/connection_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/layout_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/terminal_provider.dart';
import '../../state/workspace_context_provider.dart';
import '../../ui/chat/ai_workbench_panel.dart';
import '../../ui/layout/activity_bar.dart';

class CoreCommandRegistry {
  static void register(WidgetRef ref) {
    ref.read(commandPaletteProvider.notifier).registerCommands([
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
            ClipboardData(
              text: [
                '${run.kind.name} run',
                'Status: ${run.status.name}',
                'Model: ${run.model}',
                if (run.inputPreview != null) 'Input: ${run.inputPreview}',
                if (run.outputPreview != null) 'Output: ${run.outputPreview}',
                if (run.error != null) 'Error: ${run.error}',
                if (run.tokenUsage.isNotEmpty)
                  'Tokens: ${run.tokenUsage.formattedInputOutput}',
              ].join('\n'),
            ),
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
