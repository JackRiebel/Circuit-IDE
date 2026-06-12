enum StudioDrawerMode {
  progress,
  browser,
  code,
  diff,
  files,
  terminal,
  sources,
}

class StudioRightDrawerState {
  final StudioDrawerMode mode;
  final bool collapsed;
  final bool expanded;
  final String? selectedArtifactId;
  final String? localUrl;
  final String? filePath;
  final String? diffId;
  final String? commandRunId;

  const StudioRightDrawerState({
    this.mode = StudioDrawerMode.progress,
    this.collapsed = false,
    this.expanded = false,
    this.selectedArtifactId,
    this.localUrl,
    this.filePath,
    this.diffId,
    this.commandRunId,
  });

  double get width {
    if (collapsed) return 52;
    if (expanded) return 520;
    return 328;
  }

  StudioRightDrawerState copyWith({
    StudioDrawerMode? mode,
    bool? collapsed,
    bool? expanded,
    Object? selectedArtifactId = _sentinel,
    Object? localUrl = _sentinel,
    Object? filePath = _sentinel,
    Object? diffId = _sentinel,
    Object? commandRunId = _sentinel,
  }) {
    return StudioRightDrawerState(
      mode: mode ?? this.mode,
      collapsed: collapsed ?? this.collapsed,
      expanded: expanded ?? this.expanded,
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
