import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'file_tree_provider.dart';

class StudioCodeEditState {
  final String? filePath;
  final String original;
  final String draft;
  final bool isEditing;
  final bool isLoading;
  final bool isSaving;
  final String? error;

  const StudioCodeEditState({
    this.filePath,
    this.original = '',
    this.draft = '',
    this.isEditing = false,
    this.isLoading = false,
    this.isSaving = false,
    this.error,
  });

  bool get isDirty => draft != original;

  StudioCodeEditState copyWith({
    Object? filePath = _sentinel,
    String? original,
    String? draft,
    bool? isEditing,
    bool? isLoading,
    bool? isSaving,
    Object? error = _sentinel,
  }) {
    return StudioCodeEditState(
      filePath: identical(filePath, _sentinel)
          ? this.filePath
          : filePath as String?,
      original: original ?? this.original,
      draft: draft ?? this.draft,
      isEditing: isEditing ?? this.isEditing,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

class StudioCodeEditController extends Notifier<StudioCodeEditState> {
  @override
  StudioCodeEditState build() => const StudioCodeEditState();

  Future<void> open(String path) async {
    if (state.filePath == path && !state.isLoading) return;
    state = state.copyWith(
      filePath: path,
      isLoading: true,
      isEditing: false,
      error: null,
    );
    try {
      final text = await File(_resolve(path)).readAsString();
      state = StudioCodeEditState(filePath: path, original: text, draft: text);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  void startEditing() {
    if (state.filePath == null) return;
    state = state.copyWith(isEditing: true, error: null);
  }

  void updateDraft(String value) {
    state = state.copyWith(draft: value);
  }

  void revert() {
    state = state.copyWith(
      draft: state.original,
      isEditing: false,
      error: null,
    );
  }

  Future<void> save() async {
    final path = state.filePath;
    if (path == null) return;
    state = state.copyWith(isSaving: true, error: null);
    try {
      await File(_resolve(path)).writeAsString(state.draft);
      state = state.copyWith(
        original: state.draft,
        isSaving: false,
        isEditing: false,
      );
    } catch (error) {
      state = state.copyWith(isSaving: false, error: error.toString());
    }
  }

  String _resolve(String path) {
    if (p.isAbsolute(path)) return path;
    final root = ref.read(fileTreeProvider).rootPath;
    if (root == null) return path;
    return p.normalize(p.join(root, path));
  }
}

final studioCodeEditProvider =
    NotifierProvider<StudioCodeEditController, StudioCodeEditState>(
      StudioCodeEditController.new,
    );

const _sentinel = Object();
