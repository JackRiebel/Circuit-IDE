import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/vericoding_models.dart';
import '../../state/theme_provider.dart';

class CheckResultCard extends ConsumerStatefulWidget {
  final VericodeResult result;

  const CheckResultCard({super.key, required this.result});

  @override
  ConsumerState<CheckResultCard> createState() => _CheckResultCardState();
}

class _CheckResultCardState extends ConsumerState<CheckResultCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final r = widget.result;

    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      decoration: BoxDecoration(
        color: tokens.bgLighter,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: r.passed
              ? tokens.success.withValues(alpha: 0.3)
              : tokens.error.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          // Header row
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(Radii.md),
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Row(
                children: [
                  Icon(
                    r.passed ? Icons.check_circle : Icons.cancel,
                    size: 16,
                    color: r.passed ? tokens.success : tokens.error,
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Text(
                      r.checkName,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.sm,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    '${r.duration.inMilliseconds}ms',
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xxs,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: tokens.textMuted,
                  ),
                ],
              ),
            ),
          ),

          // Expandable output
          if (_expanded && r.output.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                0,
                Spacing.md,
                Spacing.md,
              ),
              child: Container(
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: tokens.bgMain,
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: SelectableText(
                  r.output,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xxs,
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                  maxLines: 50,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
