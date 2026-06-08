import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/context_pack.dart';
import 'editor_provider.dart';
import 'file_tree_provider.dart';
import 'git_provider.dart';
import 'memories_provider.dart';
import 'project_profile_provider.dart';
import 'rules_provider.dart';
import 'terminal_provider.dart';

const _uuid = Uuid();

class ContextPackController extends Notifier<ContextPack?> {
  @override
  ContextPack? build() => null;

  ContextPack buildForCodingTask({String? prompt}) {
    final profile = ref.read(projectProfileProvider);
    final editor = ref.read(editorProvider);
    final git = ref.read(gitProvider).status;
    final rules = ref.read(rulesProvider).rules;
    final memories = ref.read(memoriesProvider).memories;
    final terminal = ref
        .read(terminalProvider.notifier)
        .getActiveTerminalOutput(lines: 40)
        .trim();
    final rootPath = ref.read(fileTreeProvider).rootPath;
    final activeTab = editor.activeTab;
    final items = <ContextPackItem>[
      ContextPackItem(
        id: 'profile',
        type: ContextPackItemType.projectProfile,
        title: 'Project profile',
        detail: [
          'Stack: ${profile.projectTypes.isEmpty ? profile.primaryType.label : profile.projectTypes.map((type) => type.label).join(', ')}',
          if (profile.entrypoints.isNotEmpty)
            'Entrypoints: ${profile.entrypoints.take(6).join(', ')}',
          'Changed files: ${profile.changedFiles}',
          if (prompt?.trim().isNotEmpty == true) 'Task: ${prompt!.trim()}',
        ].join('\n'),
        source: rootPath,
        sourceKind: ContextPackSourceKind.projectProfile,
        estimatedTokens: 80,
        removable: false,
      ),
    ];

    if (activeTab != null && !activeTab.filePath.startsWith('circuit://')) {
      items.add(
        ContextPackItem(
          id: 'active-file:${activeTab.filePath}',
          type: ContextPackItemType.activeFile,
          title: activeTab.fileName,
          detail: 'Active editor file is likely relevant to the task.',
          source: rootPath == null
              ? activeTab.filePath
              : p.relative(activeTab.filePath, from: rootPath),
          sourceKind: ContextPackSourceKind.editor,
          estimatedTokens: 40,
        ),
      );
    }

    final changedFiles = {
      ...git.staged.map((change) => change.path),
      ...git.unstaged.map((change) => change.path),
      ...git.untracked.map((change) => change.path),
    }.take(8).toList();
    if (changedFiles.isNotEmpty) {
      items.add(
        ContextPackItem(
          id: 'git-diff',
          type: ContextPackItemType.gitDiff,
          title: 'Working tree changes',
          detail: changedFiles.join('\n'),
          sourceKind: ContextPackSourceKind.git,
          estimatedTokens: 80,
        ),
      );
    }

    if (terminal.isNotEmpty) {
      items.add(
        ContextPackItem(
          id: 'terminal',
          type: ContextPackItemType.terminal,
          title: 'Recent terminal',
          detail: _truncate(terminal, 3000),
          sourceKind: ContextPackSourceKind.terminal,
          estimatedTokens: _estimateTokens(terminal),
        ),
      );
    }

    for (final rule in rules.take(4)) {
      items.add(
        ContextPackItem(
          id: 'rule:${rule.name}',
          type: ContextPackItemType.rule,
          title: rule.name,
          detail: _truncate(rule.content, 1600),
          source: rule.filePath,
          sourceKind: ContextPackSourceKind.circuitRule,
          estimatedTokens: _estimateTokens(rule.content),
        ),
      );
    }

    for (final memory in memories.take(4)) {
      items.add(
        ContextPackItem(
          id: 'memory:${memory.name}',
          type: ContextPackItemType.memory,
          title: memory.name,
          detail: _truncate(memory.content, 1600),
          source: memory.isGlobal ? 'global memory' : 'project memory',
          sourceKind: ContextPackSourceKind.memory,
          estimatedTokens: _estimateTokens(memory.content),
        ),
      );
    }

    state = ContextPack(
      id: _uuid.v4().substring(0, 8),
      projectKey: rootPath ?? 'scratch',
      createdAt: DateTime.now(),
      items: items,
      instructionItems: _instructionItems(rootPath),
    );
    return state!;
  }

  void removeItem(String id) {
    final pack = state;
    if (pack == null) return;
    final item = pack.allItems
        .where((candidate) => candidate.id == id)
        .firstOrNull;
    if (item == null || !item.removable) return;
    state = pack.copyWith(
      removedItemIds: {...pack.removedItemIds, id}.toList(),
    );
  }

  void restoreItem(String id) {
    final pack = state;
    if (pack == null) return;
    state = pack.copyWith(
      removedItemIds: pack.removedItemIds
          .where((candidate) => candidate != id)
          .toList(),
    );
  }

  static int _estimateTokens(String value) => (value.length / 4).ceil();

  static String _truncate(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}\n... truncated ...';
  }

  List<ContextPackItem> _instructionItems(String? rootPath) {
    if (rootPath == null) return const [];
    const candidates = [
      'AGENTS.md',
      'AGENT.md',
      '.rules',
      '.cursorrules',
      '.github/copilot-instructions.md',
      '.circuit/rules',
    ];
    final items = <ContextPackItem>[];
    for (final relativePath in candidates) {
      final file = File(p.join(rootPath, relativePath));
      if (!file.existsSync()) continue;
      try {
        final content = file.readAsStringSync();
        if (content.trim().isEmpty) continue;
        items.add(
          ContextPackItem(
            id: 'instruction:$relativePath',
            type: ContextPackItemType.instruction,
            title: p.basename(relativePath),
            detail: _truncate(content.trim(), 2200),
            source: relativePath,
            sourceKind: ContextPackSourceKind.instructionFile,
            estimatedTokens: _estimateTokens(content),
            removable: true,
            includedByDefault: true,
          ),
        );
      } catch (_) {}
    }
    return items.take(5).toList();
  }
}

final contextPackProvider =
    NotifierProvider<ContextPackController, ContextPack?>(
      ContextPackController.new,
    );
