import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/code_review_provider.dart';
import '../../state/connection_provider.dart';
import '../../state/git_provider.dart';
import '../../state/theme_provider.dart';

class CodeReviewButton extends ConsumerWidget {
  const CodeReviewButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final git = ref.watch(gitProvider);
    final reviewState = ref.watch(codeReviewProvider);
    final isConnected = ref.watch(agentServiceProvider).isConnected;
    final hasChanges = !git.status.isClean;
    final isReviewing = reviewState.isReviewing;
    final isEnabled = isConnected && hasChanges && !isReviewing;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      child: SizedBox(
        width: double.infinity,
        height: 30,
        child: MouseRegion(
          cursor:
              isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: GestureDetector(
            onTap: isEnabled
                ? () {
                    final staged = git.status.staged.isNotEmpty;
                    ref
                        .read(codeReviewProvider.notifier)
                        .startReview(staged: staged);
                  }
                : null,
            child: AnimatedContainer(
              duration: AnimationDurations.fast,
              decoration: BoxDecoration(
                color: isEnabled
                    ? tokens.accent.withValues(alpha: 0.1)
                    : tokens.border.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(
                  color: isEnabled
                      ? tokens.accent.withValues(alpha: 0.3)
                      : tokens.border.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isReviewing)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: tokens.accent,
                      ),
                    )
                  else
                    Icon(
                      Icons.rate_review_outlined,
                      size: 14,
                      color: isEnabled ? tokens.accent : tokens.textMuted,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    isReviewing ? 'Reviewing...' : 'AI Review',
                    style: TextStyle(
                      color: isEnabled ? tokens.accent : tokens.textMuted,
                      fontSize: FontSizes.sm,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
