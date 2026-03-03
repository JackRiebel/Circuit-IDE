import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/context/memories_loader.dart';
import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';

class MemoryItem extends ConsumerStatefulWidget {
  final Memory memory;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const MemoryItem({
    super.key,
    required this.memory,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  ConsumerState<MemoryItem> createState() => _MemoryItemState();
}

class _MemoryItemState extends ConsumerState<MemoryItem> {
  bool _isHovered = false;
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

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
            GestureDetector(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: widget.memory.isGlobal
                          ? tokens.warning
                          : tokens.accent,
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.memory.name,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: FontSizes.sm,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.memory.isGlobal ? 'Global' : 'Project',
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: FontSizes.xxs,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isHovered) ...[
                      _SmallIconBtn(
                        icon: Icons.edit_outlined,
                        onTap: widget.onEdit,
                        tokens: tokens,
                      ),
                      const SizedBox(width: 4),
                      _SmallIconBtn(
                        icon: Icons.delete_outline,
                        onTap: widget.onDelete,
                        tokens: tokens,
                        isDestructive: true,
                      ),
                    ],
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
            if (_isExpanded)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                  Spacing.xl,
                  0,
                  Spacing.lg,
                  Spacing.lg,
                ),
                child: Text(
                  widget.memory.content,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    height: 1.5,
                  ),
                  maxLines: 20,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SmallIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final dynamic tokens;
  final bool isDestructive;

  const _SmallIconBtn({
    required this.icon,
    required this.onTap,
    required this.tokens,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Icon(
          icon,
          size: 13,
          color: isDestructive
              ? (tokens.error as Color).withValues(alpha: 0.7)
              : tokens.textMuted,
        ),
      ),
    );
  }
}
