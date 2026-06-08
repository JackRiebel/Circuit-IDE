import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/studio_shell.dart';
import 'file_tree_provider.dart';

class StudioShellNotifier extends Notifier<StudioShellState> {
  @override
  StudioShellState build() {
    ref.listen(fileTreeProvider, (previous, next) {
      if (previous?.rootPath != next.rootPath && next.rootPath != null) {
        state = state.copyWith(selectedProjectPath: next.rootPath);
      }
    });
    return const StudioShellState();
  }

  void openHome() {
    state = state.copyWith(mode: StudioMode.home, selectedTaskId: null);
  }

  void openProject([String? projectPath]) {
    state = state.copyWith(
      mode: StudioMode.home,
      selectedProjectPath: projectPath ?? state.selectedProjectPath,
      selectedTaskId: null,
    );
  }

  void openTask(String taskId) {
    state = state.copyWith(mode: StudioMode.task, selectedTaskId: taskId);
  }

  void openReview({String? taskId}) {
    state = state.copyWith(
      mode: StudioMode.review,
      selectedTaskId: taskId ?? state.selectedTaskId,
    );
  }

  void openAdvancedEditor() {
    state = state.copyWith(mode: StudioMode.advancedEditor);
  }

  void setPromptMode(StudioPromptMode mode) {
    state = state.copyWith(promptMode: mode);
  }

  void setComposerText(String text) {
    state = state.copyWith(composerText: text);
  }

  void clearComposer() {
    state = state.copyWith(composerText: '');
  }

  void toggleRightProgressPanel() {
    state = state.copyWith(
      rightProgressPanelVisible: !state.rightProgressPanelVisible,
    );
  }
}

final studioShellProvider =
    NotifierProvider<StudioShellNotifier, StudioShellState>(
      StudioShellNotifier.new,
    );
