import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/inline_completion_provider.dart';
import '../../state/theme_provider.dart';

class InlineCompletion extends ConsumerWidget {
  final double lineHeight;
  final double charWidth;

  const InlineCompletion({super.key, this.lineHeight = 20, this.charWidth = 8});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final state = ref.watch(inlineCompletionProvider);

    if (!state.isVisible || state.suggestion == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: (state.cursorLine - 1) * lineHeight,
      left: state.cursorColumn * charWidth,
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.tab) {
              ref.read(inlineCompletionProvider.notifier).accept();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
              ref.read(inlineCompletionProvider.notifier).dismiss();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              state.suggestion!,
              style: TextStyle(
                color: tokens.textMuted.withValues(alpha: 0.5),
                fontSize: FontSizes.md,
                fontFamily: 'JetBrains Mono',
                fontStyle: FontStyle.italic,
              ),
            ),
            if (state.isLoading)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1,
                    color: tokens.textMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
