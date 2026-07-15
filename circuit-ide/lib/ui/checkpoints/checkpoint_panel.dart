import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/checkpoint.dart';
import '../../state/checkpoint_provider.dart';
import '../../state/theme_provider.dart';

class CheckpointPanel extends ConsumerWidget {
  const CheckpointPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final cpState = ref.watch(checkpointProvider);

    // Show revert feedback
    if (cpState.lastRevertMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(cpState.lastRevertMessage!),
            duration: const Duration(seconds: 3),
          ),
        );
        ref.read(checkpointProvider.notifier).clearMessage();
      });
    }

    if (cpState.checkpoints.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.xl),
                color: tokens.textMuted.withValues(alpha: 0.06),
              ),
              child: Icon(Icons.history, size: 22, color: tokens.textMuted),
            ),
            const SizedBox(height: Spacing.xl),
            Text(
              'No checkpoints yet',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.md,
              ),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'Checkpoints are created automatically\nwhen the AI edits files.',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
      itemCount: cpState.checkpoints.length,
      itemBuilder: (context, index) {
        return _CheckpointCard(
          checkpoint: cpState.checkpoints[index],
          isReverting: cpState.isReverting,
        );
      },
    );
  }
}

class _CheckpointCard extends ConsumerStatefulWidget {
  final Checkpoint checkpoint;
  final bool isReverting;

  const _CheckpointCard({required this.checkpoint, required this.isReverting});

  @override
  ConsumerState<_CheckpointCard> createState() => _CheckpointCardState();
}

class _CheckpointCardState extends ConsumerState<_CheckpointCard> {
  bool _isHovered = false;
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final cp = widget.checkpoint;
    final timeStr = _formatTime(cp.timestamp);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.xs,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.md),
          color: _isHovered
              ? tokens.accent.withValues(alpha: 0.04)
              : Colors.transparent,
          border: Border.all(
            color: _isHovered
                ? tokens.accent.withValues(alpha: 0.2)
                : tokens.border.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            GestureDetector(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Row(
                  children: [
                    Icon(Icons.restore, size: 14, color: tokens.accent),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cp.description,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: FontSizes.sm,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$timeStr  ·  ${cp.fileCount} file${cp.fileCount == 1 ? '' : 's'}',
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: FontSizes.xxs,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isHovered && !widget.isReverting)
                      _RewindButton(
                        onTap: () => ref
                            .read(checkpointProvider.notifier)
                            .revertToCheckpoint(cp.id),
                      ),
                    if (widget.isReverting)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: tokens.accent,
                        ),
                      ),
                    const SizedBox(width: Spacing.sm),
                    Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 14,
                      color: tokens.textMuted,
                    ),
                  ],
                ),
              ),
            ),

            // Expanded file list
            if (_isExpanded)
              Container(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.xl,
                  0,
                  Spacing.lg,
                  Spacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: cp.snapshots.map((s) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(
                            s.wasCreated
                                ? Icons.add_circle_outline
                                : Icons.edit_outlined,
                            size: 11,
                            color: s.wasCreated
                                ? tokens.success
                                : tokens.warning,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              s.path,
                              style: TextStyle(
                                color: tokens.textSecondary,
                                fontSize: FontSizes.xxs,
                                fontFamily: 'JetBrains Mono',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _RewindButton extends ConsumerStatefulWidget {
  final VoidCallback onTap;

  const _RewindButton({required this.onTap});

  @override
  ConsumerState<_RewindButton> createState() => _RewindButtonState();
}

class _RewindButtonState extends ConsumerState<_RewindButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.sm),
            color: _isHovered
                ? tokens.warning.withValues(alpha: 0.15)
                : tokens.warning.withValues(alpha: 0.08),
            border: Border.all(color: tokens.warning.withValues(alpha: 0.3)),
          ),
          child: Text(
            'Rewind',
            style: TextStyle(
              color: tokens.warning,
              fontSize: FontSizes.xxs,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
