import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/studio_feature_flags.dart';
import '../models/studio_right_drawer.dart';
import '../models/studio_source_artifact.dart';

class StudioRightDrawerController extends Notifier<StudioRightDrawerState> {
  @override
  StudioRightDrawerState build() => const StudioRightDrawerState();

  void openMode(StudioDrawerMode mode) {
    state = state.copyWith(mode: _safeMode(mode), collapsed: false);
  }

  void openArtifact(StudioSourceArtifact artifact) {
    final mode = _modeFor(artifact.kind);
    state = state.copyWith(
      mode: mode,
      collapsed: false,
      selectedArtifactId: artifact.id,
      localUrl: mode == StudioDrawerMode.browser ? artifact.localUrl : null,
      filePath: artifact.filePath,
      diffId: artifact.patchSetId,
      commandRunId: artifact.commandRunId,
    );
  }

  void openFile(String path) {
    state = state.copyWith(
      mode: StudioDrawerMode.code,
      collapsed: false,
      filePath: path,
      selectedArtifactId: null,
    );
  }

  void openPatchFile(String patchSetId, String path) {
    state = state.copyWith(
      mode: StudioDrawerMode.diff,
      collapsed: false,
      diffId: patchSetId,
      patchFilePath: path,
      filePath: path,
      selectedArtifactId: null,
    );
  }

  void openBrowser(String url) {
    if (!StudioFeatureFlags.advancedStudioSurfaces) {
      state = state.copyWith(
        mode: StudioDrawerMode.sources,
        collapsed: false,
        localUrl: null,
        selectedArtifactId: null,
      );
      return;
    }
    state = state.copyWith(
      mode: StudioDrawerMode.browser,
      collapsed: false,
      localUrl: url,
      selectedArtifactId: null,
    );
  }

  void openCommand(String commandRunId) {
    state = state.copyWith(
      mode: StudioDrawerMode.terminal,
      collapsed: false,
      commandRunId: commandRunId,
      selectedArtifactId: null,
    );
  }

  void openContext() {
    state = state.copyWith(mode: StudioDrawerMode.context, collapsed: false);
  }

  void toggleCollapsed() {
    state = state.copyWith(collapsed: !state.collapsed);
  }

  void toggleExpanded() {
    final next = state.widthMode == StudioDrawerWidthMode.standard
        ? StudioDrawerWidthMode.expanded
        : StudioDrawerWidthMode.standard;
    state = state.copyWith(widthMode: next, collapsed: false);
  }

  void setWidthMode(StudioDrawerWidthMode mode) {
    state = state.copyWith(widthMode: mode, collapsed: false);
  }

  StudioDrawerMode _safeMode(StudioDrawerMode mode) {
    if (mode == StudioDrawerMode.browser &&
        !StudioFeatureFlags.advancedStudioSurfaces) {
      return StudioDrawerMode.sources;
    }
    return mode;
  }

  StudioDrawerMode _modeFor(StudioSourceArtifactKind kind) {
    return switch (kind) {
      StudioSourceArtifactKind.localUrl ||
      StudioSourceArtifactKind.webSource ||
      StudioSourceArtifactKind.browserComment => _safeMode(
        StudioDrawerMode.browser,
      ),
      StudioSourceArtifactKind.file => StudioDrawerMode.code,
      StudioSourceArtifactKind.diff ||
      StudioSourceArtifactKind.gitChange ||
      StudioSourceArtifactKind.gitHunk ||
      StudioSourceArtifactKind.reviewComment ||
      StudioSourceArtifactKind.patch => StudioDrawerMode.diff,
      StudioSourceArtifactKind.command ||
      StudioSourceArtifactKind.terminalLog ||
      StudioSourceArtifactKind.terminalSession => StudioDrawerMode.terminal,
      StudioSourceArtifactKind.topology ||
      StudioSourceArtifactKind.sizing ||
      StudioSourceArtifactKind.lifecycle ||
      StudioSourceArtifactKind.chart ||
      StudioSourceArtifactKind.businessUseCase ||
      StudioSourceArtifactKind.evidence ||
      StudioSourceArtifactKind.toolResult => StudioDrawerMode.sources,
    };
  }
}

final studioRightDrawerProvider =
    NotifierProvider<StudioRightDrawerController, StudioRightDrawerState>(
      StudioRightDrawerController.new,
    );
