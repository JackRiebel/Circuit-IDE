import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/connection_provider.dart';
import '../../state/chat_provider.dart';
import '../../state/git_provider.dart';
import '../../state/model_routing_provider.dart';
import '../../enums/connection_status.dart';
import '../../agent/config/models_config.dart';
import '../../models/routing_models.dart';
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
            Icon(Icons.account_tree, size: 13, color: tokens.statusBarText.withValues(alpha: 0.85)),
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
          const SizedBox(width: Spacing.lg),
          const GhostStatusWidget(),

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
                    Icon(Icons.alt_route, size: 12, color: tokens.textMuted.withValues(alpha: 0.6)),
                    const SizedBox(width: 3),
                    Text('routing', style: textStyle.copyWith(color: tokens.textMuted.withValues(alpha: 0.6))),
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
              final shortName = routedModel.split('-').last.split('.').last;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.alt_route, size: 12, color: tierColor),
                  const SizedBox(width: 3),
                  Text(shortName, style: textStyle.copyWith(color: tierColor)),
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
                  ? [BoxShadow(color: tokens.success.withValues(alpha: 0.4), blurRadius: 4)]
                  : null,
            ),
          ),
          const SizedBox(width: 5),
          Text('AI', style: textStyle),

          if (chatState.tokenUsage.totalTokens > 0) ...[
            _Divider(color: tokens.statusBarText),
            Text(chatState.tokenUsage.formatted, style: textStyle),
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
