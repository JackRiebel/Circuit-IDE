class EditorTab {
  final String id;
  final String filePath;
  final String fileName;
  final String content;
  final String? savedContent;
  final bool isModified;
  final int cursorLine;
  final int cursorColumn;
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
    this.language = 'plaintext',
  });

  EditorTab copyWith({
    String? content,
    String? savedContent,
    bool? isModified,
    int? cursorLine,
    int? cursorColumn,
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
      language: language ?? this.language,
    );
  }
}

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
