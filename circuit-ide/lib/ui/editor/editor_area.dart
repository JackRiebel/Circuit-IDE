import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/editor_state.dart';
import '../../state/chat_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/layout_provider.dart';
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
    final isNotebookTab =
        activeTab?.filePath.startsWith('circuit://notebook/') ?? false;
    final isDiffTab =
        activeTab?.filePath.startsWith('circuit://diff/') ?? false;
    final isSpecTab =
        activeTab?.filePath.startsWith('circuit://spec/') ?? false;
    final isRuntimeTab =
        activeTab?.filePath.startsWith('circuit://runtime/') ?? false;
    final isSpecialTab =
        isSettingsTab ||
        isCodebaseMapTab ||
        isNotebookTab ||
        isDiffTab ||
        isSpecTab ||
        isRuntimeTab;

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
          if (activeTab != null && !isSpecialTab)
            _EditorContextBar(tab: activeTab),
          Expanded(
            child: activeTab == null
                ? const SizedBox.shrink()
                : isSettingsTab
                ? const SettingsPanel()
                : isCodebaseMapTab
                ? const GraphCanvas()
                : isNotebookTab
                ? NotebookEditor(
                    notebookId: activeTab.filePath.replaceFirst(
                      'circuit://notebook/',
                      '',
                    ),
                  )
                : isDiffTab
                ? DiffEditorWidget(
                    diffId: activeTab.filePath.replaceFirst(
                      'circuit://diff/',
                      '',
                    ),
                  )
                : isSpecTab
                ? SpecEditorTab(
                    specId: activeTab.filePath.replaceFirst(
                      'circuit://spec/',
                      '',
                    ),
                  )
                : isRuntimeTab
                ? RuntimeTab(
                    traceId: activeTab.filePath.replaceFirst(
                      'circuit://runtime/',
                      '',
                    ),
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
                            totalLines: activeTab.content.split('\n').length,
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

class _EditorContextBar extends ConsumerWidget {
  final EditorTab tab;

  const _EditorContextBar({required this.tab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final lineCount = tab.content.isEmpty ? 1 : tab.content.split('\n').length;
    final charCount = tab.content.length;

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
      decoration: BoxDecoration(
        color: tokens.editorBg,
        border: Border(
          bottom: BorderSide(color: tokens.border.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          _ContextMetric(icon: Icons.code, label: tab.language.toUpperCase()),
          const SizedBox(width: Spacing.lg),
          _ContextMetric(
            icon: Icons.format_list_numbered,
            label: '$lineCount lines',
          ),
          const SizedBox(width: Spacing.lg),
          _ContextMetric(
            icon: Icons.data_object,
            label: _formatCount(charCount),
          ),
          if (tab.isModified) ...[
            const SizedBox(width: Spacing.lg),
            _ContextMetric(
              icon: Icons.circle,
              label: 'Unsaved',
              color: tokens.warning,
            ),
          ],
          const Spacer(),
          _AiActionButton(
            icon: Icons.travel_explore,
            label: 'Explain',
            onTap: () => _sendFilePrompt(
              ref,
              'Explain how this file works, including the most important flows and dependencies.',
            ),
          ),
          const SizedBox(width: Spacing.sm),
          _AiActionButton(
            icon: Icons.manage_search,
            label: 'Review',
            onTap: () => _sendFilePrompt(
              ref,
              'Review this file for bugs, edge cases, and maintainability issues. Prioritize actionable findings.',
            ),
          ),
          const SizedBox(width: Spacing.sm),
          _AiActionButton(
            icon: Icons.science_outlined,
            label: 'Tests',
            onTap: () => _sendFilePrompt(
              ref,
              'Identify useful tests for this file and add or update them if appropriate.',
            ),
          ),
        ],
      ),
    );
  }

  static String _formatCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k chars';
    }
    return '$count chars';
  }

  void _sendFilePrompt(WidgetRef ref, String task) {
    ref.read(chatPanelVisibleProvider.notifier).set(true);
    ref
        .read(chatProvider.notifier)
        .sendMessage(
          '[Active file: ${tab.filePath}]\n'
          '$task\n\n'
          'Use the current editor contents and make code changes when that is the right next step.',
        );
  }
}

class _ContextMetric extends ConsumerWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _ContextMetric({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final effectiveColor = color ?? tokens.textMuted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: effectiveColor),
        const SizedBox(width: Spacing.sm),
        Text(
          label,
          style: TextStyle(
            color: effectiveColor,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _AiActionButton extends ConsumerStatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AiActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  ConsumerState<_AiActionButton> createState() => _AiActionButtonState();
}

class _AiActionButtonState extends ConsumerState<_AiActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AnimationDurations.fast,
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.sm,
            ),
            decoration: BoxDecoration(
              color: _hovered
                  ? tokens.accent.withValues(alpha: 0.12)
                  : tokens.bgLight.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(
                color: _hovered
                    ? tokens.accent.withValues(alpha: 0.28)
                    : tokens.border.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 13,
                  color: _hovered ? tokens.accent : tokens.textSecondary,
                ),
                const SizedBox(width: Spacing.sm),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: _hovered ? tokens.accent : tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
