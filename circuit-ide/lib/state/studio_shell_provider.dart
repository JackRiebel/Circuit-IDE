import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/studio_shell.dart';
import '../models/specialist_agent.dart';
import 'file_tree_provider.dart';
import 'studio_thread_provider.dart';

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
    ref.read(studioThreadProvider.notifier).selectThread(null);
    state = state.copyWith(
      mode: StudioMode.home,
      selectedProjectPath: projectPath ?? state.selectedProjectPath,
      selectedTaskId: null,
    );
  }

  void openTask(String taskId) {
    ref.read(studioThreadProvider.notifier).selectTaskThread(taskId);
    state = state.copyWith(mode: StudioMode.task, selectedTaskId: taskId);
  }

  void openThread(String threadId) {
    ref.read(studioThreadProvider.notifier).selectThread(threadId);
    state = state.copyWith(mode: StudioMode.task, selectedTaskId: null);
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

  void setExecutionMode(StudioExecutionMode mode) {
    state = state.copyWith(executionMode: mode);
  }

  void setSpecialistAgent(SpecialistAgentId agentId) {
    state = state.copyWith(specialistAgentId: agentId);
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

  void setPlanModeEnabled(bool value) {
    state = state.copyWith(planModeEnabled: value);
  }

  void togglePlanMode() {
    state = state.copyWith(planModeEnabled: !state.planModeEnabled);
  }
}

final studioShellProvider =
    NotifierProvider<StudioShellNotifier, StudioShellState>(
      StudioShellNotifier.new,
    );
