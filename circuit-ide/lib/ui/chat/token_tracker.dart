import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/token_provider.dart';
import '../../state/theme_provider.dart';

class TokenTracker extends ConsumerWidget {
  const TokenTracker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final usage = ref.watch(tokenUsageProvider);
    final cost = ref.watch(costInfoProvider);

    if (usage.totalTokens == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: tokens.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.data_usage_outlined, size: 11, color: tokens.textMuted),
          const SizedBox(width: 4),
          Text(
            usage.formatted,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xxs,
              fontFamily: 'JetBrains Mono',
              letterSpacing: 0.2,
            ),
          ),
          Container(
            width: 1,
            height: 10,
            margin: const EdgeInsets.symmetric(horizontal: Spacing.md),
            color: tokens.border.withValues(alpha: 0.3),
          ),
          Icon(Icons.payments_outlined, size: 11, color: tokens.textMuted),
          const SizedBox(width: 4),
          Text(
            cost.formatted,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xxs,
              fontFamily: 'JetBrains Mono',
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
