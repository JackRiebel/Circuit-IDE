import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';

class DiffViewer extends ConsumerWidget {
  final String diff;

  const DiffViewer({super.key, required this.diff});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final lines = diff.split('\n');

    return Container(
      color: tokens.editorBg,
      child: ListView.builder(
        itemCount: lines.length,
        itemBuilder: (context, index) {
          final line = lines[index];
          Color bgColor = Colors.transparent;
          Color textColor = tokens.textPrimary;

          if (line.startsWith('+') && !line.startsWith('+++')) {
            bgColor = tokens.success.withValues(alpha: 0.1);
            textColor = tokens.success;
          } else if (line.startsWith('-') && !line.startsWith('---')) {
            bgColor = tokens.error.withValues(alpha: 0.1);
            textColor = tokens.error;
          } else if (line.startsWith('@@')) {
            bgColor = tokens.info.withValues(alpha: 0.1);
            textColor = tokens.info;
          } else if (line.startsWith('diff ') || line.startsWith('index ')) {
            textColor = tokens.textMuted;
          }

          return Container(
            color: bgColor,
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: 1,
            ),
            child: Text(
              line,
              style: TextStyle(
                color: textColor,
                fontSize: FontSizes.sm,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          );
        },
      ),
    );
  }
}
