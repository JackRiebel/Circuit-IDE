import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/utils/file_utils.dart';
import '../models/diff_models.dart';
import '../models/editor_state.dart';

class EditorNotifier extends Notifier<EditorState> {
  static const _uuid = Uuid();
  final Map<String, DiffData> _diffData = {};


  @override
  EditorState build() => const EditorState();

  Future<void> openFile(String filePath) async {
    // Check if already open
    final existingIndex =
        state.tabs.indexWhere((t) => t.filePath == filePath);
    if (existingIndex >= 0) {
      state = state.copyWith(activeTabIndex: existingIndex);
      return;
    }

    // Read file content
    final file = File(filePath);
    if (!await file.exists()) return;

    final content = await file.readAsString();
    final language = FileUtils.getLanguageFromPath(filePath);

    final tab = EditorTab(
      id: _uuid.v4(),
      filePath: filePath,
      fileName: p.basename(filePath),
      content: content,
      savedContent: content,
      language: language,
    );

    final newTabs = [...state.tabs, tab];
    state = state.copyWith(
      tabs: newTabs,
      activeTabIndex: newTabs.length - 1,
    );
  }

  void closeTab(int index) {
    if (index < 0 || index >= state.tabs.length) return;

    final newTabs = List<EditorTab>.from(state.tabs)..removeAt(index);
    int newActive = state.activeTabIndex;
    if (newActive >= newTabs.length) {
      newActive = newTabs.length - 1;
    }

    state = state.copyWith(tabs: newTabs, activeTabIndex: newActive);
  }

  void setActiveTab(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    state = state.copyWith(activeTabIndex: index);
  }

  void updateContent(int index, String content) {
    if (index < 0 || index >= state.tabs.length) return;

    final tab = state.tabs[index];
    final isModified = content != tab.savedContent;
    final newTabs = List<EditorTab>.from(state.tabs);
    newTabs[index] = tab.copyWith(content: content, isModified: isModified);
    state = state.copyWith(tabs: newTabs);
  }

  Future<bool> saveFile(int index) async {
    if (index < 0 || index >= state.tabs.length) return false;

    final tab = state.tabs[index];
    try {
      await File(tab.filePath).writeAsString(tab.content);
      final newTabs = List<EditorTab>.from(state.tabs);
      newTabs[index] = tab.copyWith(
        savedContent: tab.content,
        isModified: false,
      );
      state = state.copyWith(tabs: newTabs);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> saveActiveFile() async {
    return saveFile(state.activeTabIndex);
  }

  void updateCursor(int index, int line, int column) {
    if (index < 0 || index >= state.tabs.length) return;
    final newTabs = List<EditorTab>.from(state.tabs);
    newTabs[index] = state.tabs[index].copyWith(
      cursorLine: line,
      cursorColumn: column,
    );
    state = state.copyWith(tabs: newTabs);
  }

  /// Open the settings tab (or focus it if already open)
  void openSettingsTab() {
    const settingsPath = 'circuit://settings';
    final existingIndex =
        state.tabs.indexWhere((t) => t.filePath == settingsPath);
    if (existingIndex >= 0) {
      state = state.copyWith(activeTabIndex: existingIndex);
      return;
    }

    const tab = EditorTab(
      id: 'settings',
      filePath: settingsPath,
      fileName: 'Settings',
      content: '',
      language: 'settings',
    );

    final newTabs = [...state.tabs, tab];
    state = state.copyWith(
      tabs: newTabs,
      activeTabIndex: newTabs.length - 1,
    );
  }

  /// Open the codebase map tab (or focus it if already open)
  void openCodebaseMapTab() {
    const mapPath = 'circuit://codebase-map';
    final existingIndex =
        state.tabs.indexWhere((t) => t.filePath == mapPath);
    if (existingIndex >= 0) {
      state = state.copyWith(activeTabIndex: existingIndex);
      return;
    }

    const tab = EditorTab(
      id: 'codebase-map',
      filePath: mapPath,
      fileName: 'Codebase Map',
      content: '',
      language: 'codebase-map',
    );

    final newTabs = [...state.tabs, tab];
    state = state.copyWith(
      tabs: newTabs,
      activeTabIndex: newTabs.length - 1,
    );
  }

  /// Open a notebook tab (or focus it if already open)
  void openNotebookTab(String id, String name) {
    final notebookPath = 'circuit://notebook/$id';
    final existingIndex =
        state.tabs.indexWhere((t) => t.filePath == notebookPath);
    if (existingIndex >= 0) {
      state = state.copyWith(activeTabIndex: existingIndex);
      return;
    }

    final tab = EditorTab(
      id: 'notebook-$id',
      filePath: notebookPath,
      fileName: name,
      content: '',
      language: 'notebook',
    );

    final newTabs = [...state.tabs, tab];
    state = state.copyWith(
      tabs: newTabs,
      activeTabIndex: newTabs.length - 1,
    );
  }

  /// Open a diff tab comparing two contents
  void openDiffTab(
    String leftTitle,
    String rightTitle,
    String leftContent,
    String rightContent,
  ) {
    final id = _uuid.v4().substring(0, 8);
    final diffPath = 'circuit://diff/$id';

    _diffData[id] = DiffData(
      leftTitle: leftTitle,
      rightTitle: rightTitle,
      leftContent: leftContent,
      rightContent: rightContent,
    );

    final tab = EditorTab(
      id: 'diff-$id',
      filePath: diffPath,
      fileName: '$leftTitle ↔ $rightTitle',
      content: '',
      language: 'diff',
    );

    final newTabs = [...state.tabs, tab];
    state = state.copyWith(
      tabs: newTabs,
      activeTabIndex: newTabs.length - 1,
    );
  }

  /// Get stored diff data by id
  DiffData? getDiffData(String id) => _diffData[id];

  /// Open a spec-driven development tab
  void openSpecTab(String id, String name) {
    final specPath = 'circuit://spec/$id';
    final existingIndex =
        state.tabs.indexWhere((t) => t.filePath == specPath);
    if (existingIndex >= 0) {
      state = state.copyWith(activeTabIndex: existingIndex);
      return;
    }

    final tab = EditorTab(
      id: 'spec-$id',
      filePath: specPath,
      fileName: name,
      content: '',
      language: 'spec',
    );

    final newTabs = [...state.tabs, tab];
    state = state.copyWith(
      tabs: newTabs,
      activeTabIndex: newTabs.length - 1,
    );
  }

  /// Open a runtime visualization tab
  void openRuntimeTab(String traceId, String filePath) {
    final runtimePath = 'circuit://runtime/$traceId';
    final existingIndex =
        state.tabs.indexWhere((t) => t.filePath == runtimePath);
    if (existingIndex >= 0) {
      state = state.copyWith(activeTabIndex: existingIndex);
      return;
    }

    final fileName = filePath.split('/').last;
    final tab = EditorTab(
      id: 'runtime-$traceId',
      filePath: runtimePath,
      fileName: 'Runtime: $fileName',
      content: '',
      language: 'runtime',
    );

    final newTabs = [...state.tabs, tab];
    state = state.copyWith(
      tabs: newTabs,
      activeTabIndex: newTabs.length - 1,
    );
  }

  /// Open multiple diff tabs for a list of file diffs (used by Ghost Mode).
  void openMultiDiffTab(List<({String name, String before, String after})> diffs) {
    for (final diff in diffs) {
      openDiffTab('Before', diff.name, diff.before, diff.after);
    }
  }

  void setFontSize(double size) {
    state = state.copyWith(fontSize: size.clamp(8, 32));
  }

  void toggleMinimap() {
    state = state.copyWith(showMinimap: !state.showMinimap);
  }

  void toggleWordWrap() {
    state = state.copyWith(wordWrap: !state.wordWrap);
  }
}

final editorProvider =
    NotifierProvider<EditorNotifier, EditorState>(EditorNotifier.new);
