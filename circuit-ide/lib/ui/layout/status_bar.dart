import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/connection_provider.dart';
import '../../state/chat_provider.dart';
import '../../state/git_provider.dart';
import '../../enums/connection_status.dart';

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

          const Spacer(),

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
