import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/connection_provider.dart';
import '../../state/chat_provider.dart';
import '../../state/git_provider.dart';
import '../../state/ai_context_provider.dart';
import '../../state/terminal_provider.dart';
import '../../state/model_routing_provider.dart';
import '../../state/workspace_context_provider.dart';
import '../../enums/connection_status.dart';
import '../../agent/config/models_config.dart';
import '../../core/config/studio_feature_flags.dart';
import '../../models/routing_models.dart';
import '../../models/workspace_context.dart';
import '../editor/prediction_status_widget.dart';
import '../agents/background_agent_status.dart';
import '../ghost/ghost_status_widget.dart';

class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final editorState = ref.watch(editorProvider);
    final connectionStatus = ref.watch(connectionStatusProvider);
    final chatState = ref.watch(chatProvider);
    final workspaceState = ref.watch(workspaceContextProvider);
    final gitState = ref.watch(gitProvider);
    final activeTab = editorState.activeTab;

    final textStyle = TextStyle(
      color: tokens.statusBarText.withValues(alpha: 0.9),
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.1,
    );

    return Container(
      height: LayoutDimensions.statusBarHeight,
      decoration: BoxDecoration(
        color: tokens.statusBarBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 4,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
      child: Row(
        children: [
          if (gitState.status.branch.isNotEmpty) ...[
            Icon(
              Icons.account_tree,
              size: 13,
              color: tokens.statusBarText.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 4),
            Text(gitState.status.branch, style: textStyle),
            const SizedBox(width: Spacing.xl),
          ],

          if (gitState.status.totalChanges > 0) ...[
            Text('${gitState.status.totalChanges} changes', style: textStyle),
            const SizedBox(width: Spacing.xl),
          ],

          const PredictionStatusWidget(),

          const SizedBox(width: Spacing.lg),
          const BackgroundAgentStatus(),
          if (StudioFeatureFlags.advancedStudioSurfaces) ...[
            const SizedBox(width: Spacing.lg),
            const GhostStatusWidget(),
          ],
          const SizedBox(width: Spacing.lg),
          const _WorkspaceHealthButton(),
          if (workspaceState.isBusy) ...[
            const SizedBox(width: Spacing.lg),
            Icon(
              Icons.sync,
              size: 12,
              color: tokens.statusBarText.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 3),
            Text(
              workspaceState.message ?? 'Indexing workspace',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
          ],

          const Spacer(),

          // Model routing indicator
          Consumer(
            builder: (context, ref, _) {
              final routing = ref.watch(modelRoutingProvider);
              if (!routing.enabled) return const SizedBox.shrink();
              final service = ref.watch(agentServiceProvider);
              final routedModel = service.lastRoutedModel;
              if (routedModel == null) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: 'Model routing enabled',
                      child: Icon(
                        Icons.alt_route,
                        size: 12,
                        color: tokens.statusBarText.withValues(alpha: 0.45),
                      ),
                    ),
                    _Divider(color: tokens.statusBarText),
                  ],
                );
              }
              final tier = ModelsConfig.getTierForModel(routedModel);
              final tierColor = switch (tier) {
                ModelTier.fast => tokens.success,
                ModelTier.balanced => tokens.warning,
                ModelTier.powerful => tokens.accent,
                null => tokens.textMuted,
              };
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: 'Routed model: $routedModel',
                    child: Icon(Icons.alt_route, size: 12, color: tierColor),
                  ),
                  _Divider(color: tokens.statusBarText),
                ],
              );
            },
          ),

          if (activeTab != null) ...[
            Text(
              'Ln ${activeTab.cursorLine}, Col ${activeTab.cursorColumn}',
              style: textStyle,
            ),
            _Divider(color: tokens.statusBarText),
            Text(activeTab.language.toUpperCase(), style: textStyle),
            _Divider(color: tokens.statusBarText),
            Text('UTF-8', style: textStyle),
            _Divider(color: tokens.statusBarText),
          ],

          // AI connection indicator
          AnimatedContainer(
            duration: AnimationDurations.normal,
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: switch (connectionStatus) {
                ConnectionStatus.connected => tokens.success,
                ConnectionStatus.connecting => tokens.warning,
                ConnectionStatus.error => tokens.error,
                ConnectionStatus.disconnected =>
                  tokens.statusBarText.withValues(alpha: 0.4),
              },
              boxShadow: connectionStatus == ConnectionStatus.connected
                  ? [
                      BoxShadow(
                        color: tokens.success.withValues(alpha: 0.4),
                        blurRadius: 4,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 5),
          Text('AI', style: textStyle),

          if (chatState.tokenUsage.totalTokens > 0) ...[
            _Divider(color: tokens.statusBarText),
            Tooltip(
              message: chatState.lastTokenUsage.isNotEmpty
                  ? chatState.lastTokenUsage.formattedInputOutput
                  : chatState.tokenUsage.formattedWithBreakdown,
              child: Icon(
                Icons.data_usage,
                size: 12,
                color: tokens.statusBarText.withValues(alpha: 0.78),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final Color color;
  const _Divider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: Container(
        width: 1,
        height: 12,
        color: color.withValues(alpha: 0.25),
      ),
    );
  }
}

class _WorkspaceHealthButton extends ConsumerWidget {
  const _WorkspaceHealthButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final workspace = ref.watch(workspaceContextProvider);
    final color = switch (workspace.status) {
      WorkspaceLifecycleStatus.ready => tokens.success,
      WorkspaceLifecycleStatus.error => tokens.error,
      WorkspaceLifecycleStatus.cancelled => tokens.warning,
      WorkspaceLifecycleStatus.loading ||
      WorkspaceLifecycleStatus.indexing => tokens.warning,
      WorkspaceLifecycleStatus.empty => tokens.statusBarText.withValues(
        alpha: 0.5,
      ),
    };

    return Tooltip(
      message: 'Workspace health',
      child: InkWell(
        onTap: () => _showWorkspaceHealthPopover(context),
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.health_and_safety_outlined, size: 12, color: color),
            const SizedBox(width: 3),
            Text(
              workspace.status == WorkspaceLifecycleStatus.empty
                  ? 'workspace'
                  : workspace.status.name,
              style: TextStyle(
                color: tokens.statusBarText.withValues(alpha: 0.9),
                fontSize: FontSizes.xs,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showWorkspaceHealthPopover(BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    showMenu<void>(
      context: context,
      position: position,
      color: Colors.transparent,
      elevation: 0,
      items: const [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _WorkspaceHealthDialog(),
        ),
      ],
    );
  }
}

class _WorkspaceHealthDialog extends ConsumerWidget {
  const _WorkspaceHealthDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final workspace = ref.watch(workspaceContextProvider);
    final aiContext = ref.watch(aiContextProvider);
    final connection = ref.watch(connectionStatusProvider);
    final terminal = ref.watch(terminalProvider);
    final git = ref.watch(gitProvider);
    final terminalLines = terminal.terminals.isEmpty
        ? 0
        : terminal.terminals[terminal.activeTerminalIndex].outputBuffer.length;

    final aiState = switch (connection) {
      ConnectionStatus.connected when workspace.error == null => 'AI-ready',
      ConnectionStatus.connected => 'AI degraded',
      ConnectionStatus.connecting => 'AI reconnecting',
      ConnectionStatus.error => 'AI offline',
      ConnectionStatus.disconnected => 'AI offline',
    };

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 460,
        decoration: BoxDecoration(
          color: tokens.surfaceOverlay,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: tokens.outlineStrong),
          boxShadow: Shadows.elevated,
        ),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.health_and_safety_outlined,
                    color: tokens.accent,
                    size: 18,
                  ),
                  const SizedBox(width: Spacing.md),
                  Text(
                    'Workspace Health',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.xl,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: tokens.textMuted, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.lg),
              _HealthLine(label: 'AI', value: aiState),
              _HealthLine(
                label: 'Root',
                value: workspace.rootPath ?? 'No workspace open',
              ),
              _HealthLine(
                label: 'File index',
                value:
                    '${workspace.fileIndexProgress?.files ?? 0} files · ${workspace.fileIndexProgress?.directories ?? 0} dirs',
              ),
              _HealthLine(
                label: 'Terminal',
                value: '$terminalLines buffered lines',
              ),
              _HealthLine(
                label: 'Git',
                value:
                    '${git.status.totalChanges} changes · diff context ${aiContext.includeGitDiff ? "on" : "off"}',
              ),
              _HealthLine(
                label: 'Refreshed',
                value: workspace.refreshedAt?.toLocal().toString() ?? 'Not yet',
              ),
              if (workspace.error != null)
                _HealthLine(label: 'Last error', value: workspace.error!),
              const SizedBox(height: Spacing.lg),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  _HealthAction(
                    label: 'Refresh',
                    icon: Icons.refresh,
                    onTap: () =>
                        ref.read(workspaceContextProvider.notifier).refresh(),
                  ),
                  _HealthAction(
                    label: 'Cancel',
                    icon: Icons.stop_circle_outlined,
                    onTap: () =>
                        ref.read(workspaceContextProvider.notifier).cancel(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HealthLine extends ConsumerWidget {
  final String label;
  final String value;

  const _HealthLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthAction extends ConsumerWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _HealthAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: tokens.outlineSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: tokens.textSecondary),
            const SizedBox(width: Spacing.sm),
            Text(
              label,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
