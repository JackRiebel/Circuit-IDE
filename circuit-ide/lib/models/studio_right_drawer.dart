enum StudioDrawerMode {
  progress,
  browser,
  code,
  diff,
  files,
  terminal,
  sources,
}

enum StudioDrawerWidthMode { standard, expanded, split }

class StudioRightDrawerState {
  final StudioDrawerMode mode;
  final bool collapsed;
  final StudioDrawerWidthMode widthMode;
  final String? selectedArtifactId;
  final String? localUrl;
  final String? filePath;
  final String? diffId;
  final String? commandRunId;

  const StudioRightDrawerState({
    this.mode = StudioDrawerMode.progress,
    this.collapsed = false,
    this.widthMode = StudioDrawerWidthMode.standard,
    this.selectedArtifactId,
    this.localUrl,
    this.filePath,
    this.diffId,
    this.commandRunId,
  });

  double get width {
    if (collapsed) return 52;
    return switch (widthMode) {
      StudioDrawerWidthMode.standard => 328,
      StudioDrawerWidthMode.expanded => 520,
      StudioDrawerWidthMode.split => 680,
    };
  }

  bool get expanded => widthMode != StudioDrawerWidthMode.standard;

  StudioRightDrawerState copyWith({
    StudioDrawerMode? mode,
    bool? collapsed,
    StudioDrawerWidthMode? widthMode,
    Object? selectedArtifactId = _sentinel,
    Object? localUrl = _sentinel,
    Object? filePath = _sentinel,
    Object? diffId = _sentinel,
    Object? commandRunId = _sentinel,
  }) {
    return StudioRightDrawerState(
      mode: mode ?? this.mode,
      collapsed: collapsed ?? this.collapsed,
      widthMode: widthMode ?? this.widthMode,
      selectedArtifactId: identical(selectedArtifactId, _sentinel)
          ? this.selectedArtifactId
          : selectedArtifactId as String?,
      localUrl: identical(localUrl, _sentinel)
          ? this.localUrl
          : localUrl as String?,
      filePath: identical(filePath, _sentinel)
          ? this.filePath
          : filePath as String?,
      diffId: identical(diffId, _sentinel) ? this.diffId : diffId as String?,
      commandRunId: identical(commandRunId, _sentinel)
          ? this.commandRunId
          : commandRunId as String?,
    );
  }
}

const _sentinel = Object();
