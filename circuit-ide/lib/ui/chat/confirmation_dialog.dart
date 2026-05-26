import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/confirmation_request.dart';
import '../../state/chat_provider.dart';
import '../../state/theme_provider.dart';

class ConfirmationDialog extends ConsumerWidget {
  final ConfirmationRequest request;

  const ConfirmationDialog({super.key, required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.enter) {
            ref.read(chatProvider.notifier).approveConfirmation(request.id);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            ref.read(chatProvider.notifier).rejectConfirmation(request.id);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.sm,
        ),
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: tokens.bgLighter,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: tokens.warning.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: tokens.warning.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.xs),
                    color: tokens.warning.withValues(alpha: 0.1),
                  ),
                  child: Icon(
                    Icons.shield_outlined,
                    size: 12,
                    color: tokens.warning,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Confirmation Required',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: tokens.codeBlockBg,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: tokens.border.withValues(alpha: 0.3)),
              ),
              child: SelectableText(
                request.preview,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.xs,
                  fontFamily: 'JetBrains Mono',
                  height: 1.5,
                ),
              ),
            ),
            if (request.warnings.isNotEmpty) ...[
              const SizedBox(height: Spacing.md),
              ...request.warnings.map(
                (w) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.error_outline,
                          size: 12,
                          color: tokens.error,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          w,
                          style: TextStyle(
                            color: tokens.error,
                            fontSize: FontSizes.xs,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  height: 30,
                  child: TextButton(
                    onPressed: () => ref
                        .read(chatProvider.notifier)
                        .rejectConfirmation(request.id),
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.error,
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.lg,
                      ),
                    ),
                    child: const Text(
                      'Reject',
                      style: TextStyle(
                        fontSize: FontSizes.sm,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                SizedBox(
                  height: 30,
                  child: ElevatedButton(
                    onPressed: () => ref
                        .read(chatProvider.notifier)
                        .approveConfirmation(request.id),
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
