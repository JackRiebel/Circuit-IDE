import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/notebook.dart';
import '../../state/theme_provider.dart';

/// Displays the output of a notebook cell: stdout, stderr, execution time,
/// and running/error indicators.
class CellOutputWidget extends ConsumerWidget {
  final NotebookCell cell;

  const CellOutputWidget({super.key, required this.cell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tokens.editorBg,
        border: Border(
          top: BorderSide(
            color: tokens.border.withValues(alpha: 0.4),
          ),
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(Radii.md),
          bottomRight: Radius.circular(Radii.md),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Running indicator
          if (cell.status == CellStatus.running) _buildRunning(tokens),

          // Output content
          if (cell.output != null) ...[
            // Stdout
            if (cell.output!.stdout.isNotEmpty)
              _buildStdout(tokens, cell.output!.stdout),

            // Stderr
            if (cell.output!.stderr.isNotEmpty)
              _buildStderr(tokens, cell.output!.stderr),

            // Error message
            if (cell.output!.errorMessage != null)
              _buildError(tokens, cell.output!.errorMessage!),

            // Execution time badge
            _buildTimeBadge(tokens, cell.output!),
          ],
        ],
      ),
    );
  }

  Widget _buildRunning(dynamic tokens) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: tokens.accent,
            ),
          ),
          const SizedBox(width: Spacing.md),
          Text(
            'Running...',
            style: TextStyle(
              color: tokens.accent,
              fontSize: FontSizes.xs,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStdout(dynamic tokens, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.lg,
        Spacing.lg,
        0,
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          fontFamily: EditorDefaults.fontFamily,
          fontSize: FontSizes.xs,
          color: tokens.textPrimary,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildStderr(dynamic tokens, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        0,
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          fontFamily: EditorDefaults.fontFamily,
          fontSize: FontSizes.xs,
          color: tokens.error,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildError(dynamic tokens, String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.error_outline,
              size: 13,
              color: tokens.error,
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: FontSizes.xs,
                color: tokens.error,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeBadge(dynamic tokens, CellOutput output) {
    final ms = output.executionTime.inMilliseconds;
    final timeStr = ms < 1000 ? '${ms}ms' : '${(ms / 1000).toStringAsFixed(1)}s';
    final isSuccess = output.exitCode == 0;

    return Padding(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: (isSuccess ? tokens.success : tokens.error)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(
                color: (isSuccess ? tokens.success : tokens.error)
                    .withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSuccess ? Icons.check_circle_outline : Icons.cancel_outlined,
                  size: 11,
                  color: isSuccess ? tokens.success : tokens.error,
                ),
                const SizedBox(width: 4),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: FontSizes.xxs,
                    color: isSuccess ? tokens.success : tokens.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (output.exitCode != 0) ...[
            const SizedBox(width: Spacing.md),
            Text(
              'exit code: ${output.exitCode}',
              style: TextStyle(
                fontSize: FontSizes.xxs,
                color: tokens.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
