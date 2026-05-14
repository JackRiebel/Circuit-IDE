import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:xterm/xterm.dart';

import '../../core/constants/design_tokens.dart';
import '../../core/utils/platform_utils.dart';
import '../../state/theme_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/terminal_provider.dart';
import 'terminal_tab_bar.dart';

class TerminalPanel extends ConsumerStatefulWidget {
  const TerminalPanel({super.key});

  @override
  ConsumerState<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends ConsumerState<TerminalPanel> {
  int _initializedCount = 0;

  @override
  void initState() {
    super.initState();
    // Initialize PTY for the first terminal
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureTerminalsInitialized();
    });
  }

  void _ensureTerminalsInitialized() {
    final termState = ref.read(terminalProvider);
    final workingDir =
        ref.read(fileTreeProvider).rootPath ?? PlatformUtils.scratchDir;

    for (int i = _initializedCount; i < termState.terminals.length; i++) {
      ref.read(terminalProvider.notifier).initializePty(i, workingDir);
    }
    _initializedCount = termState.terminals.length;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final termState = ref.watch(terminalProvider);

    // Initialize PTY for any newly added terminals
    if (termState.terminals.length > _initializedCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureTerminalsInitialized();
      });
    }

    return Container(
      color: tokens.terminalBg,
      child: Column(
        children: [
          const TerminalTabBar(),
          _TerminalContextStrip(
            workingDir:
                ref.watch(fileTreeProvider).rootPath ??
                PlatformUtils.scratchDir,
            activeTerminal: termState.activeTerminalIndex + 1,
            bufferedLines: termState.terminals.isEmpty
                ? 0
                : termState
                      .terminals[termState.activeTerminalIndex]
                      .outputBuffer
                      .length,
            lastCommand: termState.terminals.isEmpty
                ? null
                : termState
                      .terminals[termState.activeTerminalIndex]
                      .lastCommand,
            lastErrorLine: termState.terminals.isEmpty
                ? null
                : termState
                      .terminals[termState.activeTerminalIndex]
                      .lastErrorLine,
            hasRecentError:
                termState.terminals.isNotEmpty &&
                termState
                    .terminals[termState.activeTerminalIndex]
                    .hasRecentError,
          ),
          Expanded(
            child: IndexedStack(
              index: termState.activeTerminalIndex,
              children: termState.terminals
                  .map(
                    (instance) => TerminalView(
                      instance.terminal,
                      textStyle: const TerminalStyle(
                        fontSize: FontSizes.md,
                        fontFamily: 'JetBrains Mono',
                      ),
                      autofocus: false,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminalContextStrip extends ConsumerWidget {
  final String workingDir;
  final int activeTerminal;
  final int bufferedLines;
  final String? lastCommand;
  final String? lastErrorLine;
  final bool hasRecentError;

  const _TerminalContextStrip({
    required this.workingDir,
    required this.activeTerminal,
    required this.bufferedLines,
    this.lastCommand,
    this.lastErrorLine,
    this.hasRecentError = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      decoration: BoxDecoration(
        color: tokens.terminalBg,
        border: Border(
          top: BorderSide(color: tokens.border.withValues(alpha: 0.35)),
          bottom: BorderSide(color: tokens.border.withValues(alpha: 0.35)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_open_outlined, size: 12, color: tokens.textMuted),
          const SizedBox(width: Spacing.sm),
          Tooltip(
            message: workingDir,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                p.basename(workingDir),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: Spacing.lg),
          _TerminalMetric(icon: Icons.tag, label: 'Terminal $activeTerminal'),
          const SizedBox(width: Spacing.lg),
          _TerminalMetric(
            icon: Icons.notes,
            label: '$bufferedLines buffered lines',
          ),
          if (lastCommand != null && lastCommand!.isNotEmpty) ...[
            const SizedBox(width: Spacing.lg),
            _TerminalMetric(
              icon: Icons.keyboard_return,
              label: lastCommand!,
              tooltip: 'Last command: $lastCommand',
            ),
          ],
          const Spacer(),
          if (hasRecentError && lastErrorLine != null) ...[
            Icon(Icons.error_outline, size: 12, color: tokens.error),
            const SizedBox(width: Spacing.sm),
            Flexible(
              child: Tooltip(
                message: lastErrorLine!,
                child: Text(
                  lastErrorLine!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.error,
                    fontSize: FontSizes.xxs,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ] else
            Flexible(
              child: Text(
                'AI can inspect recent output from the tab bar action',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xxs,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TerminalMetric extends ConsumerWidget {
  final IconData icon;
  final String label;
  final String? tooltip;

  const _TerminalMetric({
    required this.icon,
    required this.label,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Tooltip(
      message: tooltip ?? label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: tokens.textMuted),
          const SizedBox(width: Spacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
