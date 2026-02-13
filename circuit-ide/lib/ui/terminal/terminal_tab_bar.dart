import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/chat_provider.dart';
import '../../state/terminal_provider.dart';
import '../../state/theme_provider.dart';

class TerminalTabBar extends ConsumerWidget {
  const TerminalTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final terminalState = ref.watch(terminalProvider);
    final terminals = terminalState.terminals;

    return Container(
      height: 30,
      color: tokens.bgLight,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      child: Row(
        children: [
          Text(
            'TERMINAL',
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: Spacing.xl),
          for (int i = 0; i < terminals.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _TerminalTab(
                index: i,
                isActive: i == terminalState.activeTerminalIndex,
                canClose: terminals.length > 1,
              ),
            ),
          const Spacer(),
          _FixWithAIButton(),
          const SizedBox(width: Spacing.md),
          InkWell(
            onTap: () => ref.read(terminalProvider.notifier).addTerminal(),
            child: Icon(Icons.add, size: 16, color: tokens.textSecondary),
          ),
          const SizedBox(width: Spacing.md),
          InkWell(
            onTap: () => ref.read(terminalProvider.notifier).hide(),
            child: Icon(Icons.close, size: 16, color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _TerminalTab extends ConsumerStatefulWidget {
  final int index;
  final bool isActive;
  final bool canClose;

  const _TerminalTab({
    required this.index,
    required this.isActive,
    required this.canClose,
  });

  @override
  ConsumerState<_TerminalTab> createState() => _TerminalTabState();
}

class _TerminalTabState extends ConsumerState<_TerminalTab> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () =>
            ref.read(terminalProvider.notifier).setActiveTerminal(widget.index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: widget.isActive ? tokens.bgDark : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Terminal ${widget.index + 1}',
                style: TextStyle(
                  color: widget.isActive
                      ? tokens.textPrimary
                      : tokens.textSecondary,
                  fontSize: FontSizes.xs,
                ),
              ),
              if (widget.canClose)
                AnimatedOpacity(
                  duration: AnimationDurations.fast,
                  opacity: _isHovered ? 1.0 : 0.0,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: GestureDetector(
                      onTap: () => ref
                          .read(terminalProvider.notifier)
                          .removeTerminal(widget.index),
                      child: Icon(
                        Icons.close,
                        size: 12,
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FixWithAIButton extends ConsumerStatefulWidget {
  @override
  ConsumerState<_FixWithAIButton> createState() => _FixWithAIButtonState();
}

class _FixWithAIButtonState extends ConsumerState<_FixWithAIButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return Tooltip(
      message: 'Send terminal output to AI for diagnosis',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _sendToAI,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.sm),
              color: _isHovered
                  ? tokens.accent.withValues(alpha: 0.12)
                  : tokens.accent.withValues(alpha: 0.06),
              border: Border.all(
                color: _isHovered
                    ? tokens.accent.withValues(alpha: 0.3)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_fix_high,
                  size: 12,
                  color: tokens.accent,
                ),
                const SizedBox(width: 4),
                Text(
                  'Fix with AI',
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: FontSizes.xxs,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _sendToAI() {
    final output = ref
        .read(terminalProvider.notifier)
        .getActiveTerminalOutput(lines: 50);

    if (output.trim().isEmpty) return;

    ref.read(chatProvider.notifier).sendMessage(
      'The following is recent terminal output that may contain errors. '
      'Analyze it, identify the problem, and fix the code or suggest the correct command.\n\n'
      '```\n$output\n```',
    );
  }
}
