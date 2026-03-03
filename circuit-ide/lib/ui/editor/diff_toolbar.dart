import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/diff_models.dart';
import '../../state/theme_provider.dart';

class DiffToolbar extends ConsumerWidget {
  final DiffResult diffResult;
  final VoidCallback? onPrevChange;
  final VoidCallback? onNextChange;

  const DiffToolbar({
    super.key,
    required this.diffResult,
    this.onPrevChange,
    this.onNextChange,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      decoration: BoxDecoration(
        color: tokens.bgLighter,
        border: Border(
          bottom: BorderSide(color: tokens.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          // Left file name
          Text(
            diffResult.leftTitle,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w500,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            child: Icon(
              Icons.compare_arrows,
              size: 14,
              color: tokens.textMuted,
            ),
          ),
          // Right file name
          Text(
            diffResult.rightTitle,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w500,
            ),
          ),

          const Spacer(),

          // Change summary
          if (diffResult.additions > 0)
            _ChangeBadge(
              label: '+${diffResult.additions}',
              color: tokens.success,
            ),
          if (diffResult.deletions > 0) ...[
            const SizedBox(width: Spacing.sm),
            _ChangeBadge(
              label: '-${diffResult.deletions}',
              color: tokens.error,
            ),
          ],
          if (diffResult.modifications > 0) ...[
            const SizedBox(width: Spacing.sm),
            _ChangeBadge(
              label: '~${diffResult.modifications}',
              color: tokens.warning,
            ),
          ],

          const SizedBox(width: Spacing.lg),

          // Navigation arrows
          _NavButton(
            icon: Icons.keyboard_arrow_up,
            onTap: onPrevChange,
            tokens: tokens,
          ),
          _NavButton(
            icon: Icons.keyboard_arrow_down,
            onTap: onNextChange,
            tokens: tokens,
          ),
        ],
      ),
    );
  }
}

class _ChangeBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _ChangeBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: FontSizes.xxs,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final dynamic tokens;

  const _NavButton({
    required this.icon,
    this.onTap,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.xs),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          icon,
          size: 16,
          color: onTap != null ? tokens.textSecondary : tokens.textMuted,
        ),
      ),
    );
  }
}
