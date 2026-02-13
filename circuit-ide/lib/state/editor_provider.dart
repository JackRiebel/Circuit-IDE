import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/utils/file_utils.dart';
import '../models/editor_state.dart';

class EditorNotifier extends Notifier<EditorState> {
  static const _uuid = Uuid();

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
