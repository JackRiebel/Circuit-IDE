import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/runtime_provider.dart';
import '../../state/theme_provider.dart';
import 'call_stack_panel.dart';
import 'variable_inspector.dart';

class RuntimeTab extends ConsumerWidget {
  final String traceId;

  const RuntimeTab({super.key, required this.traceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final trace = ref.watch(runtimeProvider);

    if (trace == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle_outline, size: 48, color: tokens.textMuted),
            const SizedBox(height: Spacing.lg),
            Text(
              'No execution trace available',
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
            ),
          ],
        ),
      );
    }

    final currentFrame = trace.currentFrame;
    final frameIndex = trace.currentFrameIndex;
    final totalFrames = trace.frames.length;

    return Column(
      children: [
        // Timeline header
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.xl,
            vertical: Spacing.md,
          ),
          decoration: BoxDecoration(
            color: tokens.bgLighter,
            border: Border(
              bottom: BorderSide(color: tokens.border.withValues(alpha: 0.3)),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.timeline, size: 16, color: tokens.accent),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  _buildTimelineLabel(trace),
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '[${frameIndex + 1}/$totalFrames]',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),

        // Main content area: call stack + variable inspector
        Expanded(
          child: Row(
            children: [
              // Call stack (left)
              SizedBox(
                width: 280,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: tokens.border.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  child: CallStackPanel(trace: trace),
                ),
              ),

              // Variable inspector (right)
              Expanded(
                child: VariableInspector(
                  variables: currentFrame?.variables ?? [],
                ),
              ),
            ],
          ),
        ),

        // Scrubber / controls
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.xl,
            vertical: Spacing.md,
          ),
          decoration: BoxDecoration(
            color: tokens.bgLighter,
            border: Border(
              top: BorderSide(color: tokens.border.withValues(alpha: 0.3)),
            ),
          ),
          child: Row(
            children: [
              // Step controls
              _ControlButton(
                icon: Icons.skip_previous,
                onTap: frameIndex > 0
                    ? () => ref.read(runtimeProvider.notifier).jumpToFrame(0)
                    : null,
                tokens: tokens,
                tooltip: 'First frame',
              ),
              _ControlButton(
                icon: Icons.chevron_left,
                onTap: frameIndex > 0
                    ? () => ref.read(runtimeProvider.notifier).stepBackward()
                    : null,
                tokens: tokens,
                tooltip: 'Previous frame',
              ),
              _ControlButton(
                icon: Icons.chevron_right,
                onTap: frameIndex < totalFrames - 1
                    ? () => ref.read(runtimeProvider.notifier).stepForward()
                    : null,
                tokens: tokens,
                tooltip: 'Next frame',
              ),
              _ControlButton(
                icon: Icons.skip_next,
                onTap: frameIndex < totalFrames - 1
                    ? () => ref
                          .read(runtimeProvider.notifier)
                          .jumpToFrame(totalFrames - 1)
                    : null,
                tokens: tokens,
                tooltip: 'Last frame',
              ),

              const SizedBox(width: Spacing.xl),

              // Frame label
              Text(
                'Frame ${frameIndex + 1} of $totalFrames',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                ),
              ),

              const SizedBox(width: Spacing.xl),

              // Slider scrubber
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: tokens.accent,
                    inactiveTrackColor: tokens.textMuted.withValues(alpha: 0.2),
                    thumbColor: tokens.accent,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    trackHeight: 3,
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                  ),
                  child: Slider(
                    value: frameIndex.toDouble(),
                    min: 0,
                    max: (totalFrames - 1).toDouble().clamp(0, double.infinity),
                    divisions: totalFrames > 1 ? totalFrames - 1 : null,
                    onChanged: (value) {
                      ref
                          .read(runtimeProvider.notifier)
                          .jumpToFrame(value.round());
                    },
                  ),
                ),
              ),

              // Summary
              if (trace.summary != null)
                Padding(
                  padding: const EdgeInsets.only(left: Spacing.lg),
                  child: Tooltip(
                    message: trace.summary!,
                    child: Icon(
                      Icons.info_outline,
                      size: 14,
                      color: tokens.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _buildTimelineLabel(dynamic trace) {
    final funcs = trace.frames
        .map((f) => '${f.functionName}()')
        .toSet()
        .take(4)
        .join(' -> ');
    return funcs;
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final dynamic tokens;
  final String tooltip;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    required this.tokens,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: onTap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: onTap != null
                  ? tokens.textPrimary
                  : tokens.textMuted.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}
