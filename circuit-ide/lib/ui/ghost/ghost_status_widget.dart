import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/ghost_mode_provider.dart';
import '../../state/theme_provider.dart';

class GhostStatusWidget extends ConsumerWidget {
  const GhostStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final ghostState = ref.watch(ghostModeProvider);

    if (ghostState.tasks.isEmpty) return const SizedBox.shrink();

    final running = ghostState.runningCount;
    final textStyle = TextStyle(
      color: tokens.statusBarText.withValues(alpha: 0.9),
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w400,
    );

    if (running > 0) {
      return Tooltip(
        message: '$running ghost task${running > 1 ? 's' : ''} running',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: tokens.accent,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.visibility_off, size: 11, color: tokens.accent),
            const SizedBox(width: 3),
            Text(
              '$running ghost${running > 1 ? 's' : ''}',
              style: textStyle.copyWith(color: tokens.accent),
            ),
          ],
        ),
      );
    }

    final latest = ghostState.latestCompleted;
    if (latest != null) {
      return Tooltip(
        message: 'Ghost: ${latest.summary ?? latest.description}',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_off, size: 11, color: tokens.success),
            const SizedBox(width: 3),
            Text(
              'ghost done',
              style: textStyle.copyWith(color: tokens.success),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
