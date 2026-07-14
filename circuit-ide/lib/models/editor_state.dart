class EditorTab {
  final String id;
  final String filePath;
  final String fileName;
  final String content;
  final String? savedContent;
  final bool isModified;
  final int cursorLine;
  final int cursorColumn;
  final String selectedText;
  final int? selectionStartLine;
  final int? selectionEndLine;
  final String language;

  const EditorTab({
    required this.id,
    required this.filePath,
    required this.fileName,
    this.content = '',
    this.savedContent,
    this.isModified = false,
    this.cursorLine = 1,
    this.cursorColumn = 1,
    this.selectedText = '',
    this.selectionStartLine,
    this.selectionEndLine,
    this.language = 'plaintext',
  });

  EditorTab copyWith({
    String? content,
    String? savedContent,
    bool? isModified,
    int? cursorLine,
    int? cursorColumn,
    String? selectedText,
    Object? selectionStartLine = _editorSentinel,
    Object? selectionEndLine = _editorSentinel,
    String? language,
  }) {
    return EditorTab(
      id: id,
      filePath: filePath,
      fileName: fileName,
      content: content ?? this.content,
      savedContent: savedContent ?? this.savedContent,
      isModified: isModified ?? this.isModified,
      cursorLine: cursorLine ?? this.cursorLine,
      cursorColumn: cursorColumn ?? this.cursorColumn,
      selectedText: selectedText ?? this.selectedText,
      selectionStartLine: identical(selectionStartLine, _editorSentinel)
          ? this.selectionStartLine
          : selectionStartLine as int?,
      selectionEndLine: identical(selectionEndLine, _editorSentinel)
          ? this.selectionEndLine
          : selectionEndLine as int?,
      language: language ?? this.language,
    );
  }
}

const _editorSentinel = Object();

class EditorState {
  final List<EditorTab> tabs;
  final int activeTabIndex;
  final bool showMinimap;
  final bool wordWrap;
  final double fontSize;

  const EditorState({
    this.tabs = const [],
    this.activeTabIndex = -1,
    this.showMinimap = true,
    this.wordWrap = false,
    this.fontSize = 14.0,
  });

  EditorTab? get activeTab {
    if (activeTabIndex < 0 || activeTabIndex >= tabs.length) return null;
    return tabs[activeTabIndex];
  }

  EditorState copyWith({
    List<EditorTab>? tabs,
    int? activeTabIndex,
    bool? showMinimap,
    bool? wordWrap,
    double? fontSize,
  }) {
    return EditorState(
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
      showMinimap: showMinimap ?? this.showMinimap,
      wordWrap: wordWrap ?? this.wordWrap,
      fontSize: fontSize ?? this.fontSize,
    );
  }
}
