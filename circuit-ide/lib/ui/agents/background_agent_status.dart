import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/background_agent_provider.dart';
import '../../state/theme_provider.dart';

class BackgroundAgentStatus extends ConsumerWidget {
  const BackgroundAgentStatus({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final bgState = ref.watch(backgroundAgentProvider);

    if (bgState.runningCount == 0 && bgState.recentResults.isEmpty) {
      return const SizedBox.shrink();
    }

    final textStyle = TextStyle(
      color: tokens.statusBarText.withValues(alpha: 0.9),
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w400,
    );

    return Tooltip(
      richMessage: bgState.recentResults.isNotEmpty
          ? TextSpan(
              children: [
                TextSpan(
                  text: 'Recent background agents:\n',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                    fontSize: FontSizes.xs,
                  ),
                ),
                ...bgState.recentResults
                    .take(3)
                    .map(
                      (r) => TextSpan(
                        text:
                            '${r.success ? "+" : "x"} ${r.agentName}: ${r.summary}\n',
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: FontSizes.xxs,
                        ),
                      ),
                    ),
              ],
            )
          : null,
      message: bgState.recentResults.isEmpty
          ? '${bgState.runningCount} background agents running'
          : '',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (bgState.runningCount > 0) ...[
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: tokens.warning,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${bgState.runningCount} agent${bgState.runningCount > 1 ? 's' : ''}',
              style: textStyle.copyWith(color: tokens.warning),
            ),
          ] else if (bgState.recentResults.isNotEmpty) ...[
            Icon(
              bgState.recentResults.first.success
                  ? Icons.check_circle
                  : Icons.error,
              size: 11,
              color: bgState.recentResults.first.success
                  ? tokens.success
                  : tokens.error,
            ),
            const SizedBox(width: 4),
            Text(
              bgState.recentResults.first.agentName,
              style: textStyle.copyWith(
                color: bgState.recentResults.first.success
                    ? tokens.success
                    : tokens.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
