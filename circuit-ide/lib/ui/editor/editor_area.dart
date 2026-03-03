import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import '../../state/editor_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme/syntax_theme.dart';
import '../codebase_map/graph_canvas.dart';
import '../notebook/notebook_editor.dart';
import '../spec/spec_editor_tab.dart';
import '../welcome/welcome_screen.dart';
import '../settings/settings_panel.dart';
import '../runtime/runtime_tab.dart';
import 'diff_editor_widget.dart';
import 'editor_tab_bar.dart';
import 'code_editor_widget.dart';
import 'breadcrumb_bar.dart';
import 'minimap_widget.dart';

class EditorArea extends ConsumerStatefulWidget {
  const EditorArea({super.key});

  @override
  ConsumerState<EditorArea> createState() => _EditorAreaState();
}

class _EditorAreaState extends ConsumerState<EditorArea> {
  CodeScrollController? _scrollController;
  String? _currentTabId;
  int _visibleStartLine = 0;
  int _visibleEndLine = 50;
  double _editorHeight = 600;

  @override
  void dispose() {
    _scrollController?.verticalScroller.removeListener(_onScroll);
    _scrollController?.dispose();
    super.dispose();
  }

  void _ensureScrollController(String tabId) {
    if (_currentTabId != tabId) {
      _scrollController?.verticalScroller.removeListener(_onScroll);
      _scrollController?.dispose();
      _scrollController = CodeScrollController();
      _currentTabId = tabId;
      _visibleStartLine = 0;
      _visibleEndLine = 50;

      // Defer listener attachment so the scroll controller is attached first
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollController?.verticalScroller.addListener(_onScroll);
        }
      });
    }
  }

  void _onScroll() {
    final scroller = _scrollController?.verticalScroller;
    if (scroller == null || !scroller.hasClients) return;

    final editorState = ref.read(editorProvider);
    final lineHeight = editorState.fontSize * 1.5;
    final offset = scroller.offset;
    final viewportHeight = scroller.position.viewportDimension;

    final startLine = (offset / lineHeight).floor();
    final endLine = startLine + (viewportHeight / lineHeight).ceil();

    if (startLine != _visibleStartLine || endLine != _visibleEndLine) {
      setState(() {
        _visibleStartLine = startLine;
        _visibleEndLine = endLine;
        _editorHeight = viewportHeight;
      });
    }
  }

  void _onMinimapLineSelected(int line) {
    final scroller = _scrollController?.verticalScroller;
    if (scroller == null || !scroller.hasClients) return;

    final editorState = ref.read(editorProvider);
    final lineHeight = editorState.fontSize * 1.5;
    final viewportLines = (_editorHeight / lineHeight).ceil();

    // Center the target line in the viewport
    final targetOffset = (line - viewportLines ~/ 2) * lineHeight;
    final clampedOffset = targetOffset.clamp(
      scroller.position.minScrollExtent,
      scroller.position.maxScrollExtent,
    );

    scroller.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(editorProvider);
    final tokens = ref.watch(themeProvider);

    if (editorState.tabs.isEmpty) {
      return const WelcomeScreen();
    }

    final activeTab = editorState.activeTab;
    final isSettingsTab = activeTab?.filePath == 'circuit://settings';
    final isCodebaseMapTab = activeTab?.filePath == 'circuit://codebase-map';
    final isNotebookTab = activeTab?.filePath.startsWith('circuit://notebook/') ?? false;
    final isDiffTab = activeTab?.filePath.startsWith('circuit://diff/') ?? false;
    final isSpecTab = activeTab?.filePath.startsWith('circuit://spec/') ?? false;
    final isRuntimeTab = activeTab?.filePath.startsWith('circuit://runtime/') ?? false;
    final isSpecialTab = isSettingsTab || isCodebaseMapTab || isNotebookTab || isDiffTab || isSpecTab || isRuntimeTab;

    // Get syntax theme for minimap coloring
    final syntaxTheme = SyntaxTheme.fromThemeTokens(tokens);

    if (activeTab != null && !isSpecialTab) {
      _ensureScrollController(activeTab.id);
    }

    return Container(
      color: tokens.editorBg,
      child: Column(
        children: [
          const EditorTabBar(),
          if (activeTab != null && !isSpecialTab)
            BreadcrumbBar(filePath: activeTab.filePath),
          Expanded(
            child: activeTab == null
                ? const SizedBox.shrink()
                : isSettingsTab
                    ? const SettingsPanel()
                    : isCodebaseMapTab
                        ? const GraphCanvas()
                        : isNotebookTab
                            ? NotebookEditor(
                                notebookId: activeTab.filePath
                                    .replaceFirst('circuit://notebook/', ''),
                              )
                            : isDiffTab
                                ? DiffEditorWidget(
                                    diffId: activeTab.filePath
                                        .replaceFirst('circuit://diff/', ''),
                                  )
                                : isSpecTab
                                    ? SpecEditorTab(
                                        specId: activeTab.filePath
                                            .replaceFirst('circuit://spec/', ''),
                                      )
                                    : isRuntimeTab
                                        ? RuntimeTab(
                                            traceId: activeTab.filePath
                                                .replaceFirst('circuit://runtime/', ''),
                                          )
                                        : Row(
                                children: [
                                  Expanded(
                                    child: CodeEditorWidget(
                                      key: ValueKey(activeTab.id),
                                      tab: activeTab,
                                      tabIndex: editorState.activeTabIndex,
                                      scrollController: _scrollController,
                                    ),
                                  ),
                                  if (editorState.showMinimap)
                                    Container(
                                      width: 60,
                                      decoration: BoxDecoration(
                                        border: Border(
                                          left: BorderSide(
                                            color: tokens.border,
                                            width: 0.5,
                                          ),
                                        ),
                                      ),
                                      child: MinimapWidget(
                                        content: activeTab.content,
                                        totalLines:
                                            activeTab.content.split('\n').length,
                                        visibleStartLine: _visibleStartLine,
                                        visibleEndLine: _visibleEndLine,
                                        onLineSelected: _onMinimapLineSelected,
                                        syntaxTheme: syntaxTheme,
                                        bgColor: tokens.editorBg,
                                        viewportColor: tokens.textPrimary,
                                      ),
                                    ),
                                ],
                              ),
          ),
        ],
      ),
    );
  }
}
