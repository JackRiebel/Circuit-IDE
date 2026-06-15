import 'dart:io';
import 'dart:convert';

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
import 'settings_provider.dart';
import 'terminal_provider.dart';

const _uuid = Uuid();
const _commonContextTerms = {
  'please',
  'review',
  'create',
  'update',
  'change',
  'build',
  'make',
  'file',
  'files',
  'code',
  'project',
  'app',
  'this',
  'that',
  'with',
  'from',
};

class _RelevantFileScore {
  final String path;
  final String content;
  final int score;

  const _RelevantFileScore(this.path, this.content, this.score);
}

class ContextPackController extends Notifier<ContextPack?> {
  @override
  ContextPack? build() => null;

  ContextPack buildForCodingTask({String? prompt}) {
    final profile = ref.read(projectProfileProvider);
    final editor = ref.read(editorProvider);
    final git = ref.read(gitProvider).status;
    final rules = ref.read(rulesProvider).rules;
    final memories = ref.read(memoriesProvider).memories;
    final settings = ref.read(settingsProvider);
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
          if (rootPath != null) 'Workspace root: $rootPath',
          'Stack: ${profile.projectTypes.isEmpty ? profile.primaryType.label : profile.projectTypes.map((type) => type.label).join(', ')}',
          if (profile.entrypoints.isNotEmpty)
            'Entrypoints: ${profile.entrypoints.take(6).join(', ')}',
          if (profile.commands.isNotEmpty)
            'Recommended checks: ${profile.commands.where((command) => command.enabled).take(4).map((command) => command.command).join(', ')}',
          'Selected model: ${settings.ciscoModel}',
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
      final relativeSource = rootPath == null
          ? activeTab.filePath
          : p.relative(activeTab.filePath, from: rootPath);
      final activeContent = activeTab.content.trim().isEmpty
          ? _readFileIfSmall(activeTab.filePath)
          : activeTab.content;
      items.add(
        ContextPackItem(
          id: 'active-file:${activeTab.filePath}',
          type: ContextPackItemType.activeFile,
          title: activeTab.fileName,
          detail: [
            'Active editor file. Cursor: ${activeTab.cursorLine}:${activeTab.cursorColumn}.',
            if (activeTab.isModified) 'Unsaved editor changes are present.',
            if (activeContent.trim().isNotEmpty)
              _truncate(activeContent, 8000)
            else
              'File content was not loaded.',
          ].join('\n\n'),
          source: relativeSource,
          sourceKind: ContextPackSourceKind.editor,
          estimatedTokens: _estimateTokens(activeContent) + 40,
        ),
      );
    }

    items.addAll(_mentionedFileItems(prompt, rootPath));
    items.addAll(
      _relevantFileItems(
        prompt,
        rootPath,
        alreadyIncludedSources: {
          for (final item in items)
            if (item.source != null) item.source!,
        },
      ),
    );

    final changedFiles = {
      ...git.staged.map((change) => change.path),
      ...git.unstaged.map((change) => change.path),
      ...git.untracked.map((change) => change.path),
    }.take(8).toList();
    if (changedFiles.isNotEmpty) {
      final diff = _gitDiffSnippet(rootPath);
      items.add(
        ContextPackItem(
          id: 'git-diff',
          type: ContextPackItemType.gitDiff,
          title: 'Working tree changes',
          detail: [
            changedFiles.join('\n'),
            if (diff.trim().isNotEmpty)
              '\nDiff snippet:\n${_truncate(diff, 8000)}',
          ].join('\n'),
          sourceKind: ContextPackSourceKind.git,
          estimatedTokens: 80 + _estimateTokens(diff),
        ),
      );
    }

    final packageScripts = _packageScripts(rootPath);
    if (packageScripts.isNotEmpty) {
      items.add(
        ContextPackItem(
          id: 'package-scripts',
          type: ContextPackItemType.diagnostics,
          title: 'Package scripts',
          detail: packageScripts.entries
              .take(12)
              .map((entry) => '${entry.key}: ${entry.value}')
              .join('\n'),
          source: 'package.json',
          sourceKind: ContextPackSourceKind.packageScript,
          estimatedTokens: _estimateTokens(packageScripts.toString()),
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
      'CLAUDE.md',
      'CLAUDE.local.md',
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
        final content = _stripHtmlComments(file.readAsStringSync());
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
    items.addAll(_claudeRuleItems(rootPath));
    return items.take(10).toList();
  }

  String _readFileIfSmall(String path) {
    try {
      final file = File(path);
      if (!file.existsSync() || file.lengthSync() > 80 * 1024) return '';
      return file.readAsStringSync();
    } catch (_) {
      return '';
    }
  }

  List<ContextPackItem> _mentionedFileItems(String? prompt, String? rootPath) {
    if (rootPath == null || prompt == null || prompt.trim().isEmpty) {
      return const [];
    }
    final matches = RegExp(
      r'(?:(?:[\w.-]+/)+)?[\w.-]+\.(?:dart|js|jsx|ts|tsx|py|md|json|yaml|yml|html|css|scss|go|rs|java|kt|swift|sh|sql|txt)',
      caseSensitive: false,
    ).allMatches(prompt);
    final seen = <String>{};
    final items = <ContextPackItem>[];
    for (final match in matches) {
      if (items.length >= 6) break;
      final rawPath = match.group(0);
      if (rawPath == null || rawPath.trim().isEmpty) continue;
      final candidate = p.isAbsolute(rawPath)
          ? p.normalize(rawPath)
          : p.normalize(p.join(rootPath, rawPath));
      if (candidate != p.normalize(rootPath) &&
          !p.isWithin(rootPath, candidate)) {
        continue;
      }
      if (!seen.add(candidate)) continue;
      final content = _readFileIfSmall(candidate);
      if (content.trim().isEmpty) continue;
      final relativePath = p.relative(candidate, from: rootPath);
      items.add(
        ContextPackItem(
          id: 'mentioned-file:$relativePath',
          type: ContextPackItemType.mentionedFile,
          title: relativePath,
          detail: _truncate(content, 8000),
          source: relativePath,
          sourceKind: ContextPackSourceKind.editor,
          estimatedTokens: _estimateTokens(content) + 20,
        ),
      );
    }
    return items;
  }

  List<ContextPackItem> _relevantFileItems(
    String? prompt,
    String? rootPath, {
    required Set<String> alreadyIncludedSources,
  }) {
    if (rootPath == null || prompt == null || prompt.trim().isEmpty) {
      return const [];
    }
    final terms = RegExp(r'[A-Za-z0-9_/-]{4,}')
        .allMatches(prompt.toLowerCase())
        .map((match) => match.group(0)!)
        .where((term) => !_commonContextTerms.contains(term))
        .take(12)
        .toSet();
    if (terms.isEmpty) return const [];

    final scored = <_RelevantFileScore>[];
    var visited = 0;
    try {
      final root = Directory(rootPath);
      if (!root.existsSync()) return const [];
      for (final entity in root.listSync(recursive: true, followLinks: false)) {
        if (visited++ > 180) break;
        if (entity is! File) continue;
        final relativePath = p.relative(entity.path, from: rootPath);
        if (alreadyIncludedSources.contains(relativePath)) continue;
        if (_isIgnoredContextPath(relativePath)) continue;
        if (!_isRelevantContextExtension(relativePath)) continue;
        if (entity.lengthSync() > 80 * 1024) continue;
        final lowerPath = relativePath.toLowerCase();
        final content = entity.readAsStringSync();
        final lowerContent = content.toLowerCase();
        var score = 0;
        for (final term in terms) {
          if (lowerPath.contains(term)) score += 4;
          if (lowerContent.contains(term)) score += 1;
        }
        if (score > 0) {
          scored.add(_RelevantFileScore(relativePath, content, score));
        }
      }
    } catch (_) {
      return const [];
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return [
      for (final file in scored.take(5))
        ContextPackItem(
          id: 'relevant-file:${file.path}',
          type: ContextPackItemType.mentionedFile,
          title: file.path,
          detail: _truncate(file.content, 5000),
          source: file.path,
          sourceKind: ContextPackSourceKind.editor,
          estimatedTokens: _estimateTokens(file.content) + 20,
        ),
    ];
  }

  bool _isIgnoredContextPath(String path) {
    final parts = p.split(path);
    return parts.any(
      (part) =>
          part == '.git' ||
          part == 'node_modules' ||
          part == 'build' ||
          part == 'dist' ||
          part == '.dart_tool' ||
          part == '.next' ||
          part == 'Pods',
    );
  }

  bool _isRelevantContextExtension(String path) {
    const extensions = {
      '.dart',
      '.js',
      '.jsx',
      '.ts',
      '.tsx',
      '.py',
      '.md',
      '.json',
      '.yaml',
      '.yml',
      '.html',
      '.css',
      '.scss',
      '.go',
      '.rs',
      '.java',
      '.kt',
      '.swift',
      '.sh',
      '.sql',
      '.txt',
    };
    return extensions.contains(p.extension(path).toLowerCase());
  }

  String _gitDiffSnippet(String? rootPath) {
    if (rootPath == null) return '';
    try {
      final result = Process.runSync('git', [
        'diff',
        '--',
      ], workingDirectory: rootPath);
      if (result.exitCode != 0) return '';
      return (result.stdout as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  Map<String, String> _packageScripts(String? rootPath) {
    if (rootPath == null) return const {};
    try {
      final file = File(p.join(rootPath, 'package.json'));
      if (!file.existsSync()) return const {};
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final scripts = json['scripts'] as Map<String, dynamic>?;
      if (scripts == null) return const {};
      return scripts.map((key, value) => MapEntry(key, value.toString()));
    } catch (_) {
      return const {};
    }
  }

  List<ContextPackItem> _claudeRuleItems(String rootPath) {
    final dir = Directory(p.join(rootPath, '.claude', 'rules'));
    if (!dir.existsSync()) return const [];
    final items = <ContextPackItem>[];
    try {
      for (final entity in dir.listSync(recursive: true).whereType<File>()) {
        if (p.extension(entity.path).toLowerCase() != '.md') continue;
        final relativePath = p.relative(entity.path, from: rootPath);
        final content = _stripHtmlComments(entity.readAsStringSync());
        if (content.trim().isEmpty) continue;
        items.add(
          ContextPackItem(
            id: 'instruction:$relativePath',
            type: ContextPackItemType.instruction,
            title: p.basename(entity.path),
            detail: _truncate(content.trim(), 2200),
            source: relativePath,
            sourceKind: ContextPackSourceKind.instructionFile,
            estimatedTokens: _estimateTokens(content),
            removable: true,
            includedByDefault: true,
          ),
        );
        if (items.length >= 5) break;
      }
    } catch (_) {}
    return items;
  }

  String _stripHtmlComments(String content) {
    return content.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '').trim();
  }
}

final contextPackProvider =
    NotifierProvider<ContextPackController, ContextPack?>(
      ContextPackController.new,
    );
