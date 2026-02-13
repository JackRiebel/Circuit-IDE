import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/code_review_models.dart';
import '../../state/code_review_provider.dart';
import '../../state/theme_provider.dart';
import 'review_annotation_widget.dart';

class ReviewSummaryPanel extends ConsumerStatefulWidget {
  const ReviewSummaryPanel({super.key});

  @override
  ConsumerState<ReviewSummaryPanel> createState() =>
      _ReviewSummaryPanelState();
}

class _ReviewSummaryPanelState extends ConsumerState<ReviewSummaryPanel> {
  final Set<String> _expandedFiles = {};

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final reviewState = ref.watch(codeReviewProvider);
    final review = reviewState.currentReview;

    if (review == null) return const SizedBox.shrink();

    // Show spinner while reviewing
    if (review.isReviewing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: tokens.accent,
              ),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'Reviewing changes...',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.sm,
              ),
            ),
          ],
        ),
      );
    }

    final (verdictLabel, verdictColor) = switch (review.verdict) {
      ReviewVerdict.pass => ('PASS', tokens.success),
      ReviewVerdict.passWithWarnings =>
        ('PASS WITH WARNINGS', tokens.warning),
      ReviewVerdict.needsChanges => ('NEEDS CHANGES', tokens.error),
    };

    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        // Verdict badge
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: Spacing.sm,
            ),
            decoration: BoxDecoration(
              color: verdictColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(
                color: verdictColor.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  review.verdict == ReviewVerdict.pass
                      ? Icons.check_circle
                      : review.verdict == ReviewVerdict.passWithWarnings
                          ? Icons.warning_amber
                          : Icons.cancel,
                  size: 14,
                  color: verdictColor,
                ),
                const SizedBox(width: Spacing.sm),
                Text(
                  verdictLabel,
                  style: TextStyle(
                    color: verdictColor,
                    fontSize: FontSizes.xxs,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),

        // Overall assessment
        if (review.overallAssessment != null) ...[
          Text(
            review.overallAssessment!,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: FontSizes.sm,
              height: 1.4,
            ),
          ),
          const SizedBox(height: Spacing.md),
        ],

        // Stats row
        _StatsRow(review: review),
        const SizedBox(height: Spacing.md),

        Container(
          height: 1,
          color: tokens.border.withValues(alpha: 0.2),
        ),
        const SizedBox(height: Spacing.md),

        // File list with expandable annotations
        ...review.fileResults.map((fileResult) => _FileSection(
              fileResult: fileResult,
              isExpanded: _expandedFiles.contains(fileResult.filePath),
              onToggle: () {
                setState(() {
                  if (_expandedFiles.contains(fileResult.filePath)) {
                    _expandedFiles.remove(fileResult.filePath);
                  } else {
                    _expandedFiles.add(fileResult.filePath);
                  }
                });
              },
            )),

        const SizedBox(height: Spacing.md),

        // Back to Changes button
        SizedBox(
          width: double.infinity,
          height: 30,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () =>
                  ref.read(codeReviewProvider.notifier).dismissReview(),
              child: Container(
                decoration: BoxDecoration(
                  color: tokens.border.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(
                    color: tokens.border.withValues(alpha: 0.2),
                  ),
                ),
                child: Center(
                  child: Text(
                    'Back to Changes',
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.sm,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatsRow extends ConsumerWidget {
  final CodeReview review;

  const _StatsRow({required this.review});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _StatBadge(
          label: 'Critical',
          count: review.totalCritical,
          color: tokens.error,
        ),
        _StatBadge(
          label: 'Warnings',
          count: review.totalWarnings,
          color: tokens.warning,
        ),
        _StatBadge(
          label: 'Suggestions',
          count: review.fileResults.fold(
              0, (sum, f) => sum + f.suggestionCount),
          color: tokens.info,
        ),
        _StatBadge(
          label: 'Nits',
          count:
              review.fileResults.fold(0, (sum, f) => sum + f.nitCount),
          color: tokens.textMuted,
        ),
      ],
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatBadge({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          style: TextStyle(
            color: count > 0 ? color : color.withValues(alpha: 0.4),
            fontSize: FontSizes.lg,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.6),
            fontSize: FontSizes.xxs,
          ),
        ),
      ],
    );
  }
}

class _FileSection extends ConsumerWidget {
  final FileReviewResult fileResult;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _FileSection({
    required this.fileResult,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final annotationCount = fileResult.annotations.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // File header
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
              decoration: BoxDecoration(
                color: tokens.border.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
              child: Row(
                children: [
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 14,
                    color: tokens.textMuted,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      fileResult.filePath,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.sm,
                        letterSpacing: -0.1,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (annotationCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.sm,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: fileResult.criticalCount > 0
                            ? tokens.error.withValues(alpha: 0.15)
                            : fileResult.warningCount > 0
                                ? tokens.warning.withValues(alpha: 0.15)
                                : tokens.info.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(Radii.xs),
                      ),
                      child: Text(
                        '$annotationCount',
                        style: TextStyle(
                          color: fileResult.criticalCount > 0
                              ? tokens.error
                              : fileResult.warningCount > 0
                                  ? tokens.warning
                                  : tokens.info,
                          fontSize: FontSizes.xxs,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    Icon(
                      Icons.check_circle_outline,
                      size: 12,
                      color: tokens.success.withValues(alpha: 0.5),
                    ),
                ],
              ),
            ),
          ),
        ),

        // Expanded annotations
        if (isExpanded && fileResult.annotations.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(
              left: Spacing.lg,
              top: Spacing.sm,
              bottom: Spacing.sm,
            ),
            child: Column(
              children: fileResult.annotations
                  .map((a) => ReviewAnnotationWidget(annotation: a))
                  .toList(),
            ),
          ),

        const SizedBox(height: Spacing.xs),
      ],
    );
  }
}
