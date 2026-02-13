import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
