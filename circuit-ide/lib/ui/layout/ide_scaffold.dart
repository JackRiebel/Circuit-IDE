import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';
import '../../state/terminal_provider.dart';
import 'activity_bar.dart';
import 'side_panel.dart';
import 'status_bar.dart';
import 'resizable_split.dart';
import '../editor/editor_area.dart';
import '../terminal/terminal_panel.dart';
import '../chat/chat_panel.dart';

class SidePanelVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
  void set(bool value) => state = value;
}

final sidePanelVisibleProvider = NotifierProvider<SidePanelVisibleNotifier, bool>(
  SidePanelVisibleNotifier.new,
);

class ChatPanelVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
  void set(bool value) => state = value;
}

final chatPanelVisibleProvider = NotifierProvider<ChatPanelVisibleNotifier, bool>(
  ChatPanelVisibleNotifier.new,
);

class IDEScaffold extends ConsumerStatefulWidget {
  const IDEScaffold({super.key});

  @override
  ConsumerState<IDEScaffold> createState() => _IDEScaffoldState();
}

class _IDEScaffoldState extends ConsumerState<IDEScaffold> {
  double _sidePanelWidth = LayoutDimensions.sidePanelDefaultWidth;
  double _chatPanelWidth = LayoutDimensions.chatPanelDefaultWidth;
  double _terminalHeight = LayoutDimensions.terminalDefaultHeight;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final showSidePanel = ref.watch(sidePanelVisibleProvider);
    final showChatPanel = ref.watch(chatPanelVisibleProvider);
    final terminalState = ref.watch(terminalProvider);

    return Column(
      children: [
        // Title bar
        Container(
          height: LayoutDimensions.titleBarHeight,
          color: tokens.bgDark,
          child: Row(
            children: [
              const SizedBox(width: 78),
              Expanded(
                child: GestureDetector(
                  onPanStart: (_) {},
                  child: Center(
                    child: Text(
                      'CircuitCode',
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: FontSizes.md,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 78),
            ],
          ),
        ),

        // Main content
        Expanded(
          child: Row(
            children: [
              const ActivityBar(),

              if (showSidePanel) ...[
                SizedBox(
                  width: _sidePanelWidth,
                  child: const SidePanel(),
                ),
                ResizableHandle(
                  direction: Axis.horizontal,
                  onDrag: (delta) {
                    setState(() {
                      _sidePanelWidth = (_sidePanelWidth + delta).clamp(
                        LayoutDimensions.sidePanelMinWidth,
                        LayoutDimensions.sidePanelMaxWidth,
                      );
                    });
                  },
                  color: tokens.border,
                ),
              ],

              Expanded(
                child: Column(
                  children: [
                    const Expanded(child: EditorArea()),
                    if (terminalState.isVisible) ...[
                      ResizableHandle(
                        direction: Axis.vertical,
                        onDrag: (delta) {
                          setState(() {
                            _terminalHeight = (_terminalHeight - delta).clamp(
                              LayoutDimensions.terminalMinHeight,
                              LayoutDimensions.terminalMaxHeight,
                            );
                          });
                        },
                        color: tokens.border,
                      ),
                      SizedBox(
                        height: _terminalHeight,
                        child: const TerminalPanel(),
                      ),
                    ],
                  ],
                ),
              ),

              if (showChatPanel) ...[
                ResizableHandle(
                  direction: Axis.horizontal,
                  onDrag: (delta) {
                    setState(() {
                      _chatPanelWidth = (_chatPanelWidth - delta).clamp(
                        LayoutDimensions.chatPanelMinWidth,
                        LayoutDimensions.chatPanelMaxWidth,
                      );
                    });
                  },
                  color: tokens.border,
                ),
                SizedBox(
                  width: _chatPanelWidth,
                  child: const ChatPanel(),
                ),
              ],
            ],
          ),
        ),

        const StatusBar(),
      ],
    );
  }
}
