import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../services/lsdf_index_service.dart';

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
    this.includeLsdfIndex = true,
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
  Future<void>? _activeIndexRun;
  String? _activeRootPath;

  @override
  AiContextState build() => const AiContextState();

  Future<void> ensureLsdfIndex(String? rootPath) {
    if (rootPath == null || rootPath.trim().isEmpty) {
      state = const AiContextState();
      return Future.value();
    }

    final normalized = p.normalize(rootPath);
    if (_activeIndexRun != null &&
        _activeRootPath == normalized &&
        state.isLsdfBuilding) {
      return _activeIndexRun!;
    }

    _activeRootPath = normalized;
    _activeIndexRun = _ensureLsdfIndex(normalized);
    return _activeIndexRun!;
  }

  Future<void> rebuildLsdfIndex(String? rootPath) {
    if (rootPath == null || rootPath.trim().isEmpty) {
      state = const AiContextState();
      return Future.value();
    }

    final normalized = p.normalize(rootPath);
    _activeRootPath = normalized;
    _activeIndexRun = _ensureLsdfIndex(normalized, force: true);
    return _activeIndexRun!;
  }

  Future<void> _ensureLsdfIndex(String rootPath, {bool force = false}) async {
    state = state.copyWith(
      lsdfStatus: LsdfIndexStatus.checking,
      lsdfRootPath: rootPath,
      lsdfMessage: 'Checking L-SDF project map...',
      lsdfError: null,
      lsdfDirectoriesIndexed: 0,
      lsdfFilesIndexed: 0,
    );

    try {
      final projectManifest = File(p.join(rootPath, 'project.lsdf'));
      final rootIndex = File(p.join(rootPath, 'INDEX.lsdf'));
      final needsBuild =
          force || !await projectManifest.exists() || !await rootIndex.exists();

      if (!needsBuild) {
        state = state.copyWith(
          lsdfStatus: LsdfIndexStatus.ready,
          lsdfRootPath: rootPath,
          lsdfMessage: 'L-SDF map ready',
          lsdfError: null,
          lsdfIndexedAt: DateTime.now(),
          lsdfDirectoriesIndexed: 0,
          lsdfFilesIndexed: 0,
        );
        return;
      }

      state = state.copyWith(
        lsdfStatus: LsdfIndexStatus.building,
        lsdfRootPath: rootPath,
        lsdfMessage: 'Building L-SDF map for this project...',
        lsdfError: null,
        lsdfDirectoriesIndexed: 0,
        lsdfFilesIndexed: 0,
      );

      await LsdfIndexService(
        rootPath: rootPath,
        onProgress: (progress) {
          if (_activeRootPath != rootPath) return;
          state = state.copyWith(
            lsdfStatus: LsdfIndexStatus.building,
            lsdfRootPath: rootPath,
            lsdfMessage: progress.message,
            lsdfDirectoriesIndexed: progress.directories,
            lsdfFilesIndexed: progress.files,
          );
        },
      ).generate();

      state = state.copyWith(
        lsdfStatus: LsdfIndexStatus.ready,
        lsdfRootPath: rootPath,
        lsdfMessage:
            'L-SDF map ready · ${state.lsdfFilesIndexed} files indexed',
        lsdfError: null,
        lsdfIndexedAt: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(
        lsdfStatus: LsdfIndexStatus.error,
        lsdfRootPath: rootPath,
        lsdfMessage: 'L-SDF map failed',
        lsdfError: e.toString(),
      );
    } finally {
      if (_activeRootPath == rootPath) {
        _activeIndexRun = null;
      }
    }
  }

  void toggleLsdfIndex() {
    state = state.copyWith(includeLsdfIndex: !state.includeLsdfIndex);
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
