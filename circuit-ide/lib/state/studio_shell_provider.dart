import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/studio_feature_flags.dart';
import '../models/studio_shell.dart';
import '../models/specialist_agent.dart';
import 'file_tree_provider.dart';
import 'studio_thread_provider.dart';

class _StudioShellLocation {
  final StudioMode mode;
  final String? selectedProjectPath;
  final String? selectedTaskId;
  final String? selectedThreadId;

  const _StudioShellLocation({
    required this.mode,
    required this.selectedProjectPath,
    required this.selectedTaskId,
    required this.selectedThreadId,
  });

  bool sameAs(_StudioShellLocation other) {
    return mode == other.mode &&
        selectedProjectPath == other.selectedProjectPath &&
        selectedTaskId == other.selectedTaskId &&
        selectedThreadId == other.selectedThreadId;
  }
}

class StudioShellNotifier extends Notifier<StudioShellState> {
  final List<_StudioShellLocation> _backStack = [];
  final List<_StudioShellLocation> _forwardStack = [];

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
    final target = _StudioShellLocation(
      mode: StudioMode.home,
      selectedProjectPath: state.selectedProjectPath,
      selectedTaskId: null,
      selectedThreadId: null,
    );
    _pushCurrentLocationIfTargetDiffers(target);
    ref.read(studioThreadProvider.notifier).selectThread(null);
    state = state.copyWith(mode: StudioMode.home, selectedTaskId: null);
    _syncNavigationFlags();
  }

  void openProject([String? projectPath]) {
    final target = _StudioShellLocation(
      mode: StudioMode.home,
      selectedProjectPath: projectPath ?? state.selectedProjectPath,
      selectedTaskId: null,
      selectedThreadId: null,
    );
    _pushCurrentLocationIfTargetDiffers(target);
    ref.read(studioThreadProvider.notifier).selectThread(null);
    state = state.copyWith(
      mode: StudioMode.home,
      selectedProjectPath: projectPath ?? state.selectedProjectPath,
      selectedTaskId: null,
    );
    _syncNavigationFlags();
  }

  void openTask(String taskId) {
    if (state.mode == StudioMode.task && state.selectedTaskId == taskId) {
      return;
    }
    _pushCurrentLocation();
    ref.read(studioThreadProvider.notifier).selectTaskThread(taskId);
    state = state.copyWith(mode: StudioMode.task, selectedTaskId: taskId);
    _syncNavigationFlags();
  }

  void openThread(String threadId) {
    final target = _StudioShellLocation(
      mode: StudioMode.task,
      selectedProjectPath: state.selectedProjectPath,
      selectedTaskId: null,
      selectedThreadId: threadId,
    );
    _pushCurrentLocationIfTargetDiffers(target);
    ref.read(studioThreadProvider.notifier).selectThread(threadId);
    state = state.copyWith(mode: StudioMode.task, selectedTaskId: null);
    _syncNavigationFlags();
  }

  void openReview({String? taskId}) {
    final target = _StudioShellLocation(
      mode: StudioMode.review,
      selectedProjectPath: state.selectedProjectPath,
      selectedTaskId: taskId ?? state.selectedTaskId,
      selectedThreadId: ref.read(studioThreadProvider).selectedThreadId,
    );
    _pushCurrentLocationIfTargetDiffers(target);
    state = state.copyWith(
      mode: StudioMode.review,
      selectedTaskId: taskId ?? state.selectedTaskId,
    );
    _syncNavigationFlags();
  }

  void openSettings() {
    final target = _StudioShellLocation(
      mode: StudioMode.settings,
      selectedProjectPath: state.selectedProjectPath,
      selectedTaskId: null,
      selectedThreadId: ref.read(studioThreadProvider).selectedThreadId,
    );
    _pushCurrentLocationIfTargetDiffers(target);
    state = state.copyWith(mode: StudioMode.settings, selectedTaskId: null);
    _syncNavigationFlags();
  }

  void setPromptMode(StudioPromptMode mode) {
    state = state.copyWith(promptMode: mode);
  }

  void setExecutionMode(StudioExecutionMode mode) {
    final supportedMode =
        mode == StudioExecutionMode.local ||
            StudioFeatureFlags.advancedStudioSurfaces
        ? mode
        : StudioExecutionMode.local;
    state = state.copyWith(executionMode: supportedMode);
  }

  void setSpecialistAgent(SpecialistAgentId agentId) {
    final supportedAgent = StudioFeatureFlags.enterpriseSpecialists
        ? agentId
        : SpecialistAgentId.auto;
    state = state.copyWith(specialistAgentId: supportedAgent);
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

  void showRightProgressPanel() {
    if (state.rightProgressPanelVisible) return;
    state = state.copyWith(rightProgressPanelVisible: true);
  }

  void setPlanModeEnabled(bool value) {
    state = state.copyWith(planModeEnabled: value);
  }

  void togglePlanMode() {
    state = state.copyWith(planModeEnabled: !state.planModeEnabled);
  }

  void navigateBack() {
    if (_backStack.isEmpty) return;
    final current = _currentLocation();
    final target = _backStack.removeLast();
    _forwardStack.add(current);
    _restoreLocation(target);
  }

  void navigateForward() {
    if (_forwardStack.isEmpty) return;
    final current = _currentLocation();
    final target = _forwardStack.removeLast();
    _backStack.add(current);
    _restoreLocation(target);
  }

  _StudioShellLocation _currentLocation() {
    return _StudioShellLocation(
      mode: state.mode,
      selectedProjectPath: state.selectedProjectPath,
      selectedTaskId: state.selectedTaskId,
      selectedThreadId: ref.read(studioThreadProvider).selectedThreadId,
    );
  }

  void _pushCurrentLocation() {
    final current = _currentLocation();
    if (_backStack.isNotEmpty && _backStack.last.sameAs(current)) return;
    _backStack.add(current);
    _forwardStack.clear();
    _syncNavigationFlags();
  }

  void _pushCurrentLocationIfTargetDiffers(_StudioShellLocation target) {
    if (_currentLocation().sameAs(target)) return;
    _pushCurrentLocation();
  }

  void _restoreLocation(_StudioShellLocation location) {
    if (location.selectedThreadId != null) {
      ref
          .read(studioThreadProvider.notifier)
          .selectThread(location.selectedThreadId);
    } else if (location.selectedTaskId != null) {
      ref
          .read(studioThreadProvider.notifier)
          .selectTaskThread(location.selectedTaskId!);
    } else {
      ref.read(studioThreadProvider.notifier).selectThread(null);
    }
    state = state.copyWith(
      mode: location.mode,
      selectedProjectPath: location.selectedProjectPath,
      selectedTaskId: location.selectedTaskId,
      canNavigateBack: _backStack.isNotEmpty,
      canNavigateForward: _forwardStack.isNotEmpty,
    );
  }

  void _syncNavigationFlags() {
    state = state.copyWith(
      canNavigateBack: _backStack.isNotEmpty,
      canNavigateForward: _forwardStack.isNotEmpty,
    );
  }
}

final studioShellProvider =
    NotifierProvider<StudioShellNotifier, StudioShellState>(
      StudioShellNotifier.new,
    );
