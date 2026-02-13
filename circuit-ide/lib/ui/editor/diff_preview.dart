import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/diff_preview_provider.dart';
import '../../state/theme_provider.dart';

class DiffPreviewPanel extends ConsumerWidget {
  const DiffPreviewPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final diffState = ref.watch(diffPreviewProvider);

    if (!diffState.isVisible) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: tokens.bgLight,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            decoration: BoxDecoration(
              color: tokens.bgLighter,
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.compare, size: 14, color: tokens.accent),
                const SizedBox(width: 8),
                Text(
                  'AI Changes (${diffState.changes.length} file${diffState.changes.length == 1 ? '' : 's'})',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.check_circle, size: 14),
                  label: const Text('Accept All'),
                  onPressed: () =>
                      ref.read(diffPreviewProvider.notifier).acceptAll(),
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.success,
                    textStyle: const TextStyle(fontSize: FontSizes.xs),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text('Dismiss'),
                  onPressed: () =>
                      ref.read(diffPreviewProvider.notifier).close(),
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.error,
                    textStyle: const TextStyle(fontSize: FontSizes.xs),
                  ),
                ),
              ],
            ),
          ),

          // File changes list
          Expanded(
            child: ListView.builder(
              itemCount: diffState.changes.length,
              itemBuilder: (context, index) {
                final change = diffState.changes[index];
                final isActive = index == diffState.activeChangeIndex;
                final stats = change.stats;

                return InkWell(
                  onTap: () => ref
                      .read(diffPreviewProvider.notifier)
                      .setActiveChange(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.lg,
                      vertical: Spacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? tokens.accent.withValues(alpha: 0.08)
                          : Colors.transparent,
                      border: Border(
                        bottom: BorderSide(
                          color: tokens.border.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          change.isAccepted
                              ? Icons.check_circle
                              : change.wasCreated
                                  ? Icons.add_circle_outline
                                  : Icons.edit_outlined,
                          size: 14,
                          color: change.isAccepted
                              ? tokens.success
                              : change.wasCreated
                                  ? tokens.success
                                  : tokens.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                change.filePath,
                                style: TextStyle(
                                  color: tokens.textPrimary,
                                  fontSize: FontSizes.sm,
                                  fontFamily: 'JetBrains Mono',
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    change.description,
                                    style: TextStyle(
                                      color: tokens.textMuted,
                                      fontSize: FontSizes.xxs,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (stats.additions > 0)
                                    Text(
                                      '+${stats.additions}',
                                      style: TextStyle(
                                        color: tokens.success,
                                        fontSize: FontSizes.xxs,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  if (stats.additions > 0 &&
                                      stats.deletions > 0)
                                    const SizedBox(width: 4),
                                  if (stats.deletions > 0)
                                    Text(
                                      '-${stats.deletions}',
                                      style: TextStyle(
                                        color: tokens.error,
                                        fontSize: FontSizes.xxs,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (!change.isAccepted) ...[
                          _SmallButton(
                            icon: Icons.check,
                            color: tokens.success,
                            tooltip: 'Accept',
                            onTap: () => ref
                                .read(diffPreviewProvider.notifier)
                                .acceptChange(index),
                          ),
                          const SizedBox(width: 4),
                          _SmallButton(
                            icon: Icons.undo,
                            color: tokens.error,
                            tooltip: 'Reject & Revert',
                            onTap: () => ref
                                .read(diffPreviewProvider.notifier)
                                .rejectChange(index),
                          ),
                        ] else
                          Icon(Icons.check, size: 14, color: tokens.success),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _SmallButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_SmallButton> createState() => _SmallButtonState();
}

class _SmallButtonState extends State<_SmallButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: _isHovered
                  ? widget.color.withValues(alpha: 0.15)
                  : Colors.transparent,
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}
