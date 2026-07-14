import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../state/edit_prediction_provider.dart';
import '../../state/theme_provider.dart';

class PredictionStatusWidget extends ConsumerStatefulWidget {
  const PredictionStatusWidget({super.key});

  @override
  ConsumerState<PredictionStatusWidget> createState() =>
      _PredictionStatusWidgetState();
}

class _PredictionStatusWidgetState
    extends ConsumerState<PredictionStatusWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final predictionState = ref.watch(editPredictionProvider);
    final prediction = predictionState.prediction;

    if (prediction == null && !predictionState.isLoading) {
      return const SizedBox.shrink();
    }

    final textStyle = TextStyle(
      color: tokens.statusBarText.withValues(alpha: 0.9),
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.1,
    );

    if (predictionState.isLoading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _divider(tokens),
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1,
              color: tokens.statusBarText.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 4),
          Text('Predicting...', style: textStyle),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _divider(tokens),
        Tooltip(
          message: prediction!.description.isNotEmpty
              ? '${prediction.description}\n${prediction.reasoning}'
              : prediction.reasoning,
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                ref
                    .read(editPredictionProvider.notifier)
                    .navigateToPrediction();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  color: _isHovered
                      ? tokens.accent.withValues(alpha: 0.15)
                      : Colors.transparent,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_forward, size: 11, color: tokens.accent),
                    const SizedBox(width: 4),
                    Text(
                      '${p.basename(prediction.filePath)}:${prediction.line}',
                      style: textStyle.copyWith(
                        color: _isHovered
                            ? tokens.accent
                            : tokens.statusBarText.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _divider(dynamic tokens) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: Container(
        width: 1,
        height: 12,
        color: (tokens.statusBarText as Color).withValues(alpha: 0.25),
      ),
    );
  }
}
