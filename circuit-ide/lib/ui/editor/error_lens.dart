import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';

class ErrorInfo {
  final int line;
  final String message;
  final ErrorSeverity severity;
  final String? source;

  const ErrorInfo({
    required this.line,
    required this.message,
    required this.severity,
    this.source,
  });
}

enum ErrorSeverity { error, warning, info, hint }

class ErrorLensWidget extends ConsumerWidget {
  final ErrorInfo error;
  final VoidCallback? onFixWithAI;

  const ErrorLensWidget({
    super.key,
    required this.error,
    this.onFixWithAI,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    final color = switch (error.severity) {
      ErrorSeverity.error => tokens.error,
      ErrorSeverity.warning => tokens.warning,
      ErrorSeverity.info => tokens.info,
      ErrorSeverity.hint => tokens.textMuted,
    };

    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            switch (error.severity) {
              ErrorSeverity.error => Icons.error,
              ErrorSeverity.warning => Icons.warning,
              ErrorSeverity.info => Icons.info,
              ErrorSeverity.hint => Icons.lightbulb,
            },
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              error.message,
              style: TextStyle(
                color: color.withValues(alpha: 0.8),
                fontSize: FontSizes.xs,
                fontStyle: FontStyle.italic,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onFixWithAI != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: onFixWithAI,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  'Fix with AI',
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
