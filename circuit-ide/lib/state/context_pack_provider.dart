import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/utils/platform_utils.dart';
import '../agent/context/flow_analyzer.dart';
import '../models/context_pack.dart';
import '../services/semantic_index.dart';
import '../services/file_indexer.dart';
import 'editor_provider.dart';
import 'file_indexer_provider.dart';
import 'file_tree_provider.dart';
import 'git_provider.dart';
import 'memories_provider.dart';
import 'project_profile_provider.dart';
import 'settings_provider.dart';
import 'terminal_provider.dart';

part 'context_pack_support.dart';
part 'context_pack_selection.dart';
part 'context_pack_instructions.dart';
part 'context_pack_relevance.dart';

const _uuid = Uuid();
const _maxRelevantFileContextItems = 5;
const _maxOmittedRelevantFileCandidates = 50;
const _maxContextCandidateFileReads = 180;
const _maxRankedTraversalCandidates = 800;
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
const _importantContextFiles = {
  'readme.md',
  'package.json',
  'pubspec.yaml',
  'pyproject.toml',
  'requirements.txt',
  'cargo.toml',
  'go.mod',
  'pom.xml',
  'build.gradle',
  'settings.gradle',
  'tsconfig.json',
  'vite.config.ts',
  'next.config.js',
  'dockerfile',
  'makefile',
  'justfile',
  'procfile',
  'gemfile',
  'rakefile',
  'podfile',
  'fastfile',
  'appfile',
};
const _workspaceContextFiles = {
  'pnpm-workspace.yaml',
  'pnpm-workspace.yml',
  'turbo.json',
  'nx.json',
  'lerna.json',
  'rush.json',
  'melos.yaml',
  'melos.yml',
  'workspace.yaml',
  'workspace.yml',
};
const _deploymentContextFiles = {
  'vercel.json',
  'netlify.toml',
  'firebase.json',
  '.firebaserc',
  'railway.json',
  'railway.toml',
  'render.yaml',
  'render.yml',
  'fly.toml',
  'app.yaml',
  'app.yml',
  'cloudbuild.yaml',
  'cloudbuild.yml',
  'docker-compose.yml',
  'docker-compose.yaml',
  'compose.yml',
  'compose.yaml',
};
const _domainContextTerms = {
  'auth': {
    'auth',
    'login',
    'signin',
    'sign',
    'oauth',
    'sso',
    'session',
    'token',
    'jwt',
    'redirect',
    'callback',
    'permission',
    'permissions',
    'role',
    'roles',
    'security',
  },
  'test': {
    'test',
    'tests',
    'testing',
    'spec',
    'failing',
    'failed',
    'failure',
    'pytest',
    'jest',
    'vitest',
    'flutter',
    'analyze',
  },
  'routing': {
    'route',
    'routes',
    'router',
    'routing',
    'navigation',
    'redirect',
    'screen',
    'page',
    'view',
  },
  'api': {
    'api',
    'endpoint',
    'request',
    'response',
    'client',
    'server',
    'http',
    'graphql',
    'rest',
  },
  'data': {
    'database',
    'db',
    'schema',
    'model',
    'models',
    'migration',
    'query',
    'table',
    'store',
    'repository',
  },
  'state': {
    'state',
    'provider',
    'store',
    'notifier',
    'controller',
    'bloc',
    'redux',
    'riverpod',
  },
  'ui': {
    'ui',
    'ux',
    'component',
    'components',
    'widget',
    'widgets',
    'button',
    'form',
    'layout',
    'style',
  },
};

class ContextPackController extends Notifier<ContextPack?>
    with ContextPackSelection, ContextPackInstructions, ContextPackRelevance {
  @override
  final Map<String, Set<String>> _includeNextByRoot = {};

  @override
  final Map<String, Set<String>> _excludeProjectByRoot = {};

  @override
  int _estimateTokens(String value) => (value.length / 4).ceil();

  @override
  List<ContextPackWarning> _instructionPolicyWarningsForSelection(
    List<ContextPackItem> instructionItems,
  ) => _instructionPolicyWarnings(instructionItems);

  @override
  int _contextScoreForSelection(ContextPackItem item) => _contextScore(item);

  @override
  String _contextReasonForSelection(ContextPackItem item) =>
      _contextReason(item);
  @override
  ContextPack? build() {
    _includeNextByRoot.clear();
    _excludeProjectByRoot.clear();
    return null;
  }

  Future<ContextPack> buildForCodingTaskWithFreshIndex({
    String? prompt,
    Set<String> allowedFileContextPaths = const {},
    String? workspaceRoot,
  }) async {
    final boundRoot = ref.read(fileTreeProvider).rootPath;
    final rootPath = workspaceRoot ?? boundRoot;
    if (rootPath != null &&
        p.normalize(rootPath) == p.normalize(boundRoot ?? '')) {
      await ref.read(fileIndexerProvider.notifier).refreshIfStale();
    } else if (rootPath != null) {
      final worktreeIndexer = FileIndexer(workingDir: rootPath);
      await worktreeIndexer.index();
      return buildForCodingTask(
        prompt: prompt,
        allowedFileContextPaths: allowedFileContextPaths,
        workspaceRoot: rootPath,
        indexerOverride: worktreeIndexer,
      );
    }
    final pack = buildForCodingTask(
      prompt: prompt,
      allowedFileContextPaths: allowedFileContextPaths,
    );
    return _augmentFreshSemanticContext(
      pack,
      prompt: prompt ?? '',
      allowedFileContextPaths: allowedFileContextPaths,
    );
  }

  Future<ContextPack> _augmentFreshSemanticContext(
    ContextPack base, {
    required String prompt,
    required Set<String> allowedFileContextPaths,
  }) async {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    final activeTab = ref.read(editorProvider).activeTab;
    final settings = ref.read(settingsProvider);
    if (rootPath == null || prompt.trim().isEmpty) return base;
    final additions = <ContextPackItem>[];
    final existingSources = base.allItems
        .map((item) => item.source)
        .whereType<String>()
        .toSet();

    if (activeTab != null && !activeTab.filePath.startsWith('circuit://')) {
      try {
        final flow = await FlowAnalyzer(
          rootPath: rootPath,
        ).analyze(activeTab.filePath);
        for (final signature in [...flow.dependencies, ...flow.dependents]) {
          if (!_fileContextAllowed(
            signature.relativePath,
            allowedFileContextPaths,
          )) {
            continue;
          }
          if (!existingSources.add(signature.relativePath)) continue;
          final detail = [
            if (signature.classNames.isNotEmpty)
              'Classes: ${signature.classNames.take(8).join(', ')}',
            if (signature.functionSignatures.isNotEmpty)
              'Symbols:\n${signature.functionSignatures.take(12).join('\n')}',
          ].join('\n');
          if (detail.trim().isEmpty) continue;
          additions.add(
            ContextPackItem(
              id: 'dependency:${signature.relativePath}',
              type: ContextPackItemType.mentionedFile,
              title: p.basename(signature.relativePath),
              detail: _truncate(detail, 1800),
              source: signature.relativePath,
              sourceKind: ContextPackSourceKind.sourceArtifact,
              estimatedTokens: _estimateTokens(detail),
              retrievalScore: 88,
              retrievalReason: 'One-hop dependency of the active editor file.',
            ),
          );
        }
      } catch (_) {}
    }

    final indexedCount = ref.read(fileIndexerProvider)?.files.length ?? 0;
    if (indexedCount <= 1200) {
      try {
        final semantic = SemanticIndex();
        await semantic.buildIndex(rootPath);
        for (final chunk in semantic.getCandidates(prompt, limit: 3)) {
          final relativePath = p.relative(chunk.filePath, from: rootPath);
          if (!_fileContextAllowed(relativePath, allowedFileContextPaths) ||
              !existingSources.add(relativePath)) {
            continue;
          }
          final detail = _truncate(chunk.content, 1800);
          if (detail.trim().isEmpty) continue;
          additions.add(
            ContextPackItem(
              id: 'semantic:${chunk.id}',
              type: ContextPackItemType.mentionedFile,
              title: '${p.basename(relativePath)} · ${chunk.name}',
              detail: detail,
              source: relativePath,
              sourceKind: ContextPackSourceKind.sourceArtifact,
              estimatedTokens: _estimateTokens(detail),
              retrievalScore: 82,
              retrievalReason: 'Local semantic chunk match.',
            ),
          );
        }
      } catch (_) {}
    }
    if (additions.isEmpty) return base;
    final enrichedItems = [...base.items, ...additions];
    final enriched = base.copyWith(
      items: enrichedItems,
      retrievalResult: _buildRetrievalResult(
        items: enrichedItems,
        instructionItems: base.instructionItems,
        // Semantic enrichment must not hide the ranked candidates that were
        // intentionally left out of the compact file context. The drawer
        // uses them for transparent review and "include next time".
        omittedCandidates: base.retrievalResult?.omittedCandidates ?? const [],
        maxTokens:
            settings.connectorModels
                .map((model) => model.toModelInfo())
                .where((model) => model.id == settings.ciscoModel)
                .firstOrNull
                ?.contextWindow ??
            120000,
      ),
    );
    state = enriched;
    return enriched;
  }

  ContextPack buildForCodingTask({
    String? prompt,
    Set<String> allowedFileContextPaths = const {},
    String? workspaceRoot,
    FileIndexer? indexerOverride,
  }) {
    final profile = ref.read(projectProfileProvider);
    final editor = ref.read(editorProvider);
    final git = ref.read(gitProvider).status;
    final memories = ref.read(memoriesProvider).memories;
    final settings = ref.read(settingsProvider);
    final boundRoot = ref.read(fileTreeProvider).rootPath;
    final rootPath = workspaceRoot ?? boundRoot;
    final usesBoundWorkspace =
        rootPath != null &&
        p.normalize(rootPath) == p.normalize(boundRoot ?? '');
    final terminal = usesBoundWorkspace
        ? ref
              .read(terminalProvider.notifier)
              .getActiveTerminalOutput(lines: 40)
              .trim()
        : '';
    final activeTab = usesBoundWorkspace ? editor.activeTab : null;
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
    items.addAll(_lsdfContextItems(rootPath));

    if (activeTab != null && !activeTab.filePath.startsWith('circuit://')) {
      final relativeSource = rootPath == null
          ? activeTab.filePath
          : p.relative(activeTab.filePath, from: rootPath);
      if (_fileContextAllowed(relativeSource, allowedFileContextPaths)) {
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
      if (_fileContextAllowed(relativeSource, allowedFileContextPaths) &&
          activeTab.selectedText.trim().isNotEmpty) {
        final selectedText = _truncate(activeTab.selectedText.trim(), 4000);
        items.add(
          ContextPackItem(
            id: 'selection:${activeTab.filePath}',
            type: ContextPackItemType.selection,
            title: '${activeTab.fileName} selection',
            detail: [
              'Selected editor text${activeTab.selectionStartLine == null ? '' : ' · lines ${activeTab.selectionStartLine}${activeTab.selectionEndLine == null || activeTab.selectionEndLine == activeTab.selectionStartLine ? '' : '-${activeTab.selectionEndLine}'}'}.',
              selectedText,
            ].join('\n\n'),
            source: relativeSource,
            sourceKind: ContextPackSourceKind.editor,
            estimatedTokens: _estimateTokens(selectedText) + 16,
            retrievalScore: 115,
            retrievalReason: 'Active editor selection.',
          ),
        );
      }
    }

    items.addAll(
      _mentionedFileItems(
        prompt,
        rootPath,
        allowedFileContextPaths: allowedFileContextPaths,
      ),
    );
    final changedFiles = usesBoundWorkspace
        ? {
            ...git.staged.map((change) => change.path),
            ...git.unstaged.map((change) => change.path),
            ...git.untracked.map((change) => change.path),
          }
        : _changedFilesForRoot(rootPath);
    final displayedChangedFiles = changedFiles.take(12).toList();

    final relevantFiles = _relevantFileItems(
      prompt,
      rootPath,
      changedFiles: changedFiles,
      alreadyIncludedSources: {
        for (final item in items)
          if (item.source != null) item.source!,
      },
      allowedFileContextPaths: allowedFileContextPaths,
      indexerOverride: indexerOverride,
    );
    items.addAll(relevantFiles.items);

    if (changedFiles.isNotEmpty) {
      final diff = _gitDiffSnippet(rootPath);
      items.add(
        ContextPackItem(
          id: 'git-diff',
          type: ContextPackItemType.gitDiff,
          title: 'Working tree changes',
          detail: [
            displayedChangedFiles.join('\n'),
            if (changedFiles.length > displayedChangedFiles.length)
              '${changedFiles.length - displayedChangedFiles.length} more changed file${changedFiles.length - displayedChangedFiles.length == 1 ? '' : 's'} considered for context ranking.',
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

    final contextMemories = memories.take(4).toList(growable: false);
    for (final memory in contextMemories) {
      items.add(
        ContextPackItem(
          id: 'memory:${memory.isGlobal ? 'global' : 'project'}:${memory.name}',
          type: ContextPackItemType.memory,
          title: memory.name,
          detail: _truncate(memory.content, 1600),
          source: memory.isGlobal ? 'global memory' : 'project memory',
          sourceKind: ContextPackSourceKind.memory,
          estimatedTokens: _estimateTokens(memory.content),
          retrievalReason:
              '${memory.provenanceLabel} · ${memory.isGlobal ? 'global' : 'project'} scope${memory.lastUsedAt == null ? ' · not previously used' : ' · last used ${memory.lastUsedAt!.toIso8601String()}'}',
        ),
      );
    }

    final instructionItems = _instructionItems(
      rootPath,
      globalInstructionDirectory: ref.read(
        globalCircuitInstructionDirectoryProvider,
      ),
      prompt: prompt,
      contextSources: {
        for (final item in items)
          if (item.source != null && item.source != rootPath) item.source!,
        ...changedFiles,
      },
    );
    final retrievalResult = _buildRetrievalResult(
      items: items,
      instructionItems: instructionItems,
      omittedCandidates: relevantFiles.omittedCandidates,
      maxTokens:
          settings.connectorModels
              .map((model) => model.toModelInfo())
              .where((model) => model.id == settings.ciscoModel)
              .firstOrNull
              ?.contextWindow ??
          120000,
    );
    final includedMemoryIds = retrievalResult.includedCandidates
        .where(
          (candidate) => candidate.sourceKind == ContextPackSourceKind.memory,
        )
        .map((candidate) => candidate.id)
        .toSet();
    final usedMemories = contextMemories.where(
      (memory) => includedMemoryIds.contains(
        'memory:${memory.isGlobal ? 'global' : 'project'}:${memory.name}',
      ),
    );
    unawaited(ref.read(memoriesProvider.notifier).markUsed(usedMemories));
    state = ContextPack(
      id: _uuid.v4().substring(0, 8),
      projectKey: rootPath ?? 'scratch',
      createdAt: DateTime.now(),
      items: items,
      instructionItems: instructionItems,
      retrievalResult: retrievalResult,
    );
    return state!;
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
}

final contextPackProvider =
    NotifierProvider<ContextPackController, ContextPack?>(
      ContextPackController.new,
    );
