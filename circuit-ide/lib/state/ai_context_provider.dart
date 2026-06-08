import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LsdfIndexStatus { idle, checking, building, ready, error }

class AiContextState {
  final bool includeLsdfIndex;
  final bool includeActiveFile;
  final bool includeTerminalOutput;
  final bool includeGitDiff;
  final LsdfIndexStatus lsdfStatus;
  final String? lsdfRootPath;
  final String? lsdfMessage;
  final String? lsdfError;
  final DateTime? lsdfIndexedAt;
  final int lsdfDirectoriesIndexed;
  final int lsdfFilesIndexed;

  const AiContextState({
    this.includeLsdfIndex = false,
    this.includeActiveFile = true,
    this.includeTerminalOutput = false,
    this.includeGitDiff = false,
    this.lsdfStatus = LsdfIndexStatus.idle,
    this.lsdfRootPath,
    this.lsdfMessage,
    this.lsdfError,
    this.lsdfIndexedAt,
    this.lsdfDirectoriesIndexed = 0,
    this.lsdfFilesIndexed = 0,
  });

  AiContextState copyWith({
    bool? includeLsdfIndex,
    bool? includeActiveFile,
    bool? includeTerminalOutput,
    bool? includeGitDiff,
    LsdfIndexStatus? lsdfStatus,
    String? lsdfRootPath,
    String? lsdfMessage,
    Object? lsdfError = _sentinel,
    Object? lsdfIndexedAt = _sentinel,
    int? lsdfDirectoriesIndexed,
    int? lsdfFilesIndexed,
  }) {
    return AiContextState(
      includeLsdfIndex: includeLsdfIndex ?? this.includeLsdfIndex,
      includeActiveFile: includeActiveFile ?? this.includeActiveFile,
      includeTerminalOutput:
          includeTerminalOutput ?? this.includeTerminalOutput,
      includeGitDiff: includeGitDiff ?? this.includeGitDiff,
      lsdfStatus: lsdfStatus ?? this.lsdfStatus,
      lsdfRootPath: lsdfRootPath ?? this.lsdfRootPath,
      lsdfMessage: lsdfMessage ?? this.lsdfMessage,
      lsdfError: identical(lsdfError, _sentinel)
          ? this.lsdfError
          : lsdfError as String?,
      lsdfIndexedAt: identical(lsdfIndexedAt, _sentinel)
          ? this.lsdfIndexedAt
          : lsdfIndexedAt as DateTime?,
      lsdfDirectoriesIndexed:
          lsdfDirectoriesIndexed ?? this.lsdfDirectoriesIndexed,
      lsdfFilesIndexed: lsdfFilesIndexed ?? this.lsdfFilesIndexed,
    );
  }

  bool get isLsdfBuilding =>
      lsdfStatus == LsdfIndexStatus.checking ||
      lsdfStatus == LsdfIndexStatus.building;
}

const _sentinel = Object();

class AiContextNotifier extends Notifier<AiContextState> {
  @override
  AiContextState build() => const AiContextState();

  Future<void> ensureLsdfIndex(String? rootPath) {
    _disableLsdf(rootPath);
    return Future.value();
  }

  Future<void> rebuildLsdfIndex(String? rootPath) {
    _disableLsdf(rootPath);
    return Future.value();
  }

  void _disableLsdf(String? rootPath) {
    state = state.copyWith(
      includeLsdfIndex: false,
      lsdfStatus: LsdfIndexStatus.idle,
      lsdfRootPath: rootPath,
      lsdfMessage: 'L-SDF mapping is temporarily disabled.',
      lsdfError: null,
      lsdfIndexedAt: null,
      lsdfDirectoriesIndexed: 0,
      lsdfFilesIndexed: 0,
    );
  }

  void toggleLsdfIndex() {
    state = state.copyWith(includeLsdfIndex: false);
  }

  void toggleActiveFile() {
    state = state.copyWith(includeActiveFile: !state.includeActiveFile);
  }

  void toggleTerminalOutput() {
    state = state.copyWith(includeTerminalOutput: !state.includeTerminalOutput);
  }

  void toggleGitDiff() {
    state = state.copyWith(includeGitDiff: !state.includeGitDiff);
  }
}

final aiContextProvider = NotifierProvider<AiContextNotifier, AiContextState>(
  AiContextNotifier.new,
);
