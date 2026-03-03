import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/runtime_models.dart';
import '../../state/runtime_provider.dart';
import '../../state/theme_provider.dart';

class CallStackPanel extends ConsumerWidget {
  final ExecutionTrace trace;

  const CallStackPanel({super.key, required this.trace});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                  color: tokens.border.withValues(alpha: 0.3)),
            ),
          ),
          child: Text(
            'CALL STACK',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xxs,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(Spacing.sm),
            itemCount: trace.frames.length,
            itemBuilder: (context, index) {
              final frame = trace.frames[index];
              final isCurrent = index == trace.currentFrameIndex;

              return _FrameRow(
                frame: frame,
                isCurrent: isCurrent,
                tokens: tokens,
                onTap: () =>
                    ref.read(runtimeProvider.notifier).jumpToFrame(index),
              );
            },
          ),
        ),

        // Annotation for current frame
        if (trace.currentFrame?.annotation != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: tokens.accent.withValues(alpha: 0.08),
              border: Border(
                top: BorderSide(
                    color: tokens.border.withValues(alpha: 0.3)),
              ),
            ),
            child: Text(
              trace.currentFrame!.annotation!,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xxs,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }
}

class _FrameRow extends StatelessWidget {
  final RuntimeFrame frame;
  final bool isCurrent;
  final dynamic tokens;
  final VoidCallback onTap;

  const _FrameRow({
    required this.frame,
    required this.isCurrent,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md, vertical: Spacing.sm),
          margin: const EdgeInsets.only(bottom: 1),
          decoration: BoxDecoration(
            color: isCurrent
                ? tokens.accent.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Row(
            children: [
              Icon(
                isCurrent ? Icons.arrow_right : Icons.circle,
                size: isCurrent ? 16 : 6,
                color: isCurrent ? tokens.accent : tokens.textMuted,
              ),
              const SizedBox(width: Spacing.sm),
              Text(
                '${frame.frameNumber + 1}.',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xxs,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  '${frame.functionName}()',
                  style: TextStyle(
                    color: isCurrent
                        ? tokens.textPrimary
                        : tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    fontWeight:
                        isCurrent ? FontWeight.w600 : FontWeight.w400,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'L${frame.lineNumber}',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xxs,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
