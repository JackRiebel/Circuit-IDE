import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/code_review_models.dart';
import '../../state/code_review_provider.dart';
import '../../state/theme_provider.dart';

class ReviewHistoryPanel extends ConsumerWidget {
  const ReviewHistoryPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final reviewState = ref.watch(codeReviewProvider);
    final history = reviewState.history;

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: 24,
              color: tokens.textMuted.withValues(alpha: 0.3),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'No review history',
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(Spacing.md),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final review = history[index];
        return _ReviewHistoryItem(review: review);
      },
    );
  }
}

class _ReviewHistoryItem extends ConsumerStatefulWidget {
  final CodeReview review;

  const _ReviewHistoryItem({required this.review});

  @override
  ConsumerState<_ReviewHistoryItem> createState() => _ReviewHistoryItemState();
}

class _ReviewHistoryItemState extends ConsumerState<_ReviewHistoryItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final review = widget.review;
    final timeStr = DateFormat('MMM d, h:mm a').format(review.timestamp);

    final (verdictLabel, verdictColor) = switch (review.verdict) {
      ReviewVerdict.pass => ('PASS', tokens.success),
      ReviewVerdict.passWithWarnings => ('WARNINGS', tokens.warning),
      ReviewVerdict.needsChanges => ('CHANGES', tokens.error),
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () =>
            ref.read(codeReviewProvider.notifier).viewHistoryItem(review),
        child: AnimatedContainer(
          duration: AnimationDurations.fast,
          margin: const EdgeInsets.only(bottom: Spacing.sm),
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: _isHovered
                ? tokens.accent.withValues(alpha: 0.05)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: tokens.border.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              // Verdict badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: verdictColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(Radii.xs),
                ),
                child: Text(
                  verdictLabel,
                  style: TextStyle(
                    color: verdictColor,
                    fontSize: FontSizes.xxs,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: Spacing.md),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (review.branch != null)
                      Text(
                        review.branch!,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: FontSizes.sm,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      timeStr,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: FontSizes.xxs,
                      ),
                    ),
                  ],
                ),
              ),

              // Annotation count
              Text(
                '${review.totalAnnotations}',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.sm,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.comment_outlined, size: 12, color: tokens.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
