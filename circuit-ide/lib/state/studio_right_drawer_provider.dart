import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/studio_right_drawer.dart';
import '../models/studio_source_artifact.dart';

class StudioRightDrawerController extends Notifier<StudioRightDrawerState> {
  @override
  StudioRightDrawerState build() => const StudioRightDrawerState();

  void openMode(StudioDrawerMode mode) {
    state = state.copyWith(mode: mode, collapsed: false);
  }

  void openArtifact(StudioSourceArtifact artifact) {
    state = state.copyWith(
      mode: _modeFor(artifact.kind),
      collapsed: false,
      selectedArtifactId: artifact.id,
      localUrl: artifact.localUrl,
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

  void openBrowser(String url) {
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

  void toggleCollapsed() {
    state = state.copyWith(collapsed: !state.collapsed);
  }

  void toggleExpanded() {
    state = state.copyWith(expanded: !state.expanded, collapsed: false);
  }

  StudioDrawerMode _modeFor(StudioSourceArtifactKind kind) {
    return switch (kind) {
      StudioSourceArtifactKind.localUrl ||
      StudioSourceArtifactKind.webSource => StudioDrawerMode.browser,
      StudioSourceArtifactKind.file => StudioDrawerMode.code,
      StudioSourceArtifactKind.diff ||
      StudioSourceArtifactKind.patch => StudioDrawerMode.diff,
      StudioSourceArtifactKind.command ||
      StudioSourceArtifactKind.terminalLog => StudioDrawerMode.terminal,
      StudioSourceArtifactKind.toolResult => StudioDrawerMode.sources,
    };
  }
}

final studioRightDrawerProvider =
    NotifierProvider<StudioRightDrawerController, StudioRightDrawerState>(
      StudioRightDrawerController.new,
    );
