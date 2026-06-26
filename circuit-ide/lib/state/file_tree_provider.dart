import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/file_node.dart';
import '../models/workspace_open_result.dart';

class FileTreeState {
  final String? rootPath;
  final List<FileNode> nodes;
  final bool isLoading;
  final String? error;
  final WorkspaceOpenResult? lastOpenResult;

  const FileTreeState({
    this.rootPath,
    this.nodes = const [],
    this.isLoading = false,
    this.error,
    this.lastOpenResult,
  });

  FileTreeState copyWith({
    String? rootPath,
    List<FileNode>? nodes,
    bool? isLoading,
    String? error,
    WorkspaceOpenResult? lastOpenResult,
  }) {
    return FileTreeState(
      rootPath: rootPath ?? this.rootPath,
      nodes: nodes ?? this.nodes,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      lastOpenResult: lastOpenResult ?? this.lastOpenResult,
    );
  }
}

class FileTreeNotifier extends Notifier<FileTreeState> {
  @override
  FileTreeState build() => const FileTreeState();

  static const _ignoredDirs = {
    '.git',
    '.dart_tool',
    'build',
    'node_modules',
    '__pycache__',
    '.venv',
    'venv',
    '.idea',
    '.vscode',
    'target',
    '.gradle',
  };

  Future<WorkspaceOpenResult> openDirectory(String path) async {
    final validation = await _validateDirectory(path);
    if (!ref.mounted) return validation;
    if (!validation.success) {
      state = state.copyWith(
        isLoading: false,
        error: validation.message,
        lastOpenResult: validation,
      );
      return validation;
    }

    state = state.copyWith(
      rootPath: path,
      nodes: const [],
      isLoading: true,
      error: null,
      lastOpenResult: validation,
    );

    try {
      final nodes = await _loadDirectory(path, 0);
      if (!ref.mounted) return validation;
      state = state.copyWith(
        nodes: nodes,
        isLoading: false,
        error: null,
        lastOpenResult: validation,
      );
      return validation;
    } catch (e) {
      final failure = WorkspaceOpenResult.failure(
        path: path,
        reason: WorkspaceOpenFailureReason.unknown,
        message: 'Could not open project: $e',
      );
      if (!ref.mounted) return failure;
      state = state.copyWith(
        isLoading: false,
        error: failure.message,
        lastOpenResult: failure,
      );
      return failure;
    }
  }

  Future<WorkspaceOpenResult> _validateDirectory(String path) async {
    final dir = Directory(path);
    try {
      final type = await FileSystemEntity.type(path);
      if (type == FileSystemEntityType.notFound) {
        return WorkspaceOpenResult.failure(
          path: path,
          reason: WorkspaceOpenFailureReason.missing,
          message: 'Project no longer exists.',
        );
      }
      if (type != FileSystemEntityType.directory) {
        return WorkspaceOpenResult.failure(
          path: path,
          reason: WorkspaceOpenFailureReason.notDirectory,
          message: 'Recent project is not a folder.',
        );
      }
      await dir.list().take(1).drain<void>();
      return WorkspaceOpenResult.success(path);
    } on FileSystemException catch (e) {
      return WorkspaceOpenResult.failure(
        path: path,
        reason: WorkspaceOpenFailureReason.unreadable,
        message: e.message.isEmpty ? 'Project is not readable.' : e.message,
      );
    } catch (e) {
      return WorkspaceOpenResult.failure(
        path: path,
        reason: WorkspaceOpenFailureReason.unknown,
        message: 'Could not open project: $e',
      );
    }
  }

  Future<List<FileNode>> _loadDirectory(String dirPath, int depth) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final entities = await dir.list().toList();
    entities.sort((a, b) {
      // Directories first, then alphabetical
      final aIsDir = a is Directory;
      final bIsDir = b is Directory;
      if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
      return p
          .basename(a.path)
          .toLowerCase()
          .compareTo(p.basename(b.path).toLowerCase());
    });

    final nodes = <FileNode>[];
    for (final entity in entities) {
      final name = p.basename(entity.path);
      if (name.startsWith('.') && name != '.gitignore') continue;
      if (entity is Directory && _ignoredDirs.contains(name)) continue;

      nodes.add(
        FileNode(
          name: name,
          path: entity.path,
          isDirectory: entity is Directory,
          depth: depth,
          isHidden: name.startsWith('.'),
        ),
      );
    }
    return nodes;
  }

  Future<void> toggleExpand(FileNode node) async {
    if (!node.isDirectory) return;

    final index = state.nodes.indexWhere((n) => n.path == node.path);
    if (index < 0) return;

    final newNodes = List<FileNode>.from(state.nodes);

    if (node.isExpanded) {
      // Collapse: remove all children
      newNodes[index] = node.copyWith(isExpanded: false);
      int removeCount = 0;
      for (int i = index + 1; i < newNodes.length; i++) {
        if (newNodes[i].depth > node.depth) {
          removeCount++;
        } else {
          break;
        }
      }
      newNodes.removeRange(index + 1, index + 1 + removeCount);
    } else {
      // Expand: load and insert children
      final children = await _loadDirectory(node.path, node.depth + 1);
      if (!ref.mounted) return;
      newNodes[index] = node.copyWith(isExpanded: true, children: children);
      newNodes.insertAll(index + 1, children);
    }

    if (!ref.mounted) return;
    state = state.copyWith(nodes: newNodes);
  }

  Future<void> refresh() async {
    final rootPath = state.rootPath;
    if (rootPath == null) return;
    await openDirectory(rootPath);
  }

  Future<void> createFile(String parentPath, String name) async {
    final filePath = p.join(parentPath, name);
    await File(filePath).create(recursive: true);
    await refresh();
  }

  Future<void> createDirectory(String parentPath, String name) async {
    final dirPath = p.join(parentPath, name);
    await Directory(dirPath).create(recursive: true);
    await refresh();
  }

  Future<void> deleteNode(FileNode node) async {
    if (node.isDirectory) {
      await Directory(node.path).delete(recursive: true);
    } else {
      await File(node.path).delete();
    }
    await refresh();
  }

  Future<void> renameNode(FileNode node, String newName) async {
    final newPath = p.join(p.dirname(node.path), newName);
    if (node.isDirectory) {
      await Directory(node.path).rename(newPath);
    } else {
      await File(node.path).rename(newPath);
    }
    await refresh();
  }
}

final fileTreeProvider = NotifierProvider<FileTreeNotifier, FileTreeState>(
  FileTreeNotifier.new,
);
