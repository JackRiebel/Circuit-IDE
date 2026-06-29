import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/utils/platform_utils.dart';
import '../models/context_pack.dart';
import '../services/file_indexer.dart';
import 'editor_provider.dart';
import 'file_indexer_provider.dart';
import 'file_tree_provider.dart';
import 'git_provider.dart';
import 'memories_provider.dart';
import 'project_profile_provider.dart';
import 'rules_provider.dart';
import 'settings_provider.dart';
import 'terminal_provider.dart';

const _uuid = Uuid();
const _maxRelevantFileContextItems = 5;
const _maxOmittedRelevantFileCandidates = 50;
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

class _RelevantFileScore {
  final String path;
  final String content;
  final int score;
  final String reason;

  const _RelevantFileScore(this.path, this.content, this.score, this.reason);
}

class _RelevantFileResult {
  final List<ContextPackItem> items;
  final List<ContextCandidate> omittedCandidates;

  const _RelevantFileResult({
    required this.items,
    required this.omittedCandidates,
  });
}

class _InstructionFileScore {
  final ContextPackItem item;
  final int score;
  final String relativePath;

  const _InstructionFileScore({
    required this.item,
    required this.score,
    required this.relativePath,
  });
}

class ContextPreferenceStore {
  final String baseDir;

  ContextPreferenceStore({String? baseDir})
    : baseDir = baseDir ?? p.join(PlatformUtils.configDir, 'context');

  String pathForRoot(String? rootPath) {
    final key = _projectKey(rootPath);
    return p.join(baseDir, '$key.preferences.json');
  }

  Set<String> loadIncludedPaths(String? rootPath) {
    try {
      final file = File(pathForRoot(rootPath));
      if (!file.existsSync()) return const {};
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final paths =
          (json['include_next_paths'] as List<dynamic>?)?.whereType<String>() ??
          const Iterable<String>.empty();
      return paths.map(_normalizePreferencePath).whereType<String>().toSet();
    } catch (_) {
      return const {};
    }
  }

  void saveIncludedPaths(String? rootPath, Set<String> paths) {
    try {
      final file = File(pathForRoot(rootPath));
      if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
      final safePaths =
          paths.map(_normalizePreferencePath).whereType<String>().toList()
            ..sort();
      file.writeAsStringSync(
        const JsonEncoder.withIndent(
          '  ',
        ).convert({'rootPath': rootPath, 'include_next_paths': safePaths}),
      );
    } catch (_) {}
  }

  static String _projectKey(String? rootPath) {
    if (rootPath == null || rootPath.isEmpty) return 'scratch';
    return base64Url.encode(utf8.encode(rootPath)).replaceAll('=', '');
  }

  static String? _normalizePreferencePath(String path) {
    final normalized = p.normalize(path).replaceAll('\\', '/');
    if (normalized.isEmpty ||
        normalized == '.' ||
        normalized == '..' ||
        normalized.startsWith('/') ||
        normalized.startsWith('//') ||
        p.isAbsolute(normalized) ||
        RegExp(r'^[A-Za-z]:/').hasMatch(normalized)) {
      return null;
    }
    final parts = normalized.split('/');
    if (parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      return null;
    }
    return normalized;
  }
}

final contextPreferenceStoreProvider = Provider<ContextPreferenceStore>(
  (ref) => ContextPreferenceStore(),
);

class ContextPreferenceRevisionController extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {
    state++;
  }
}

final contextPreferenceRevisionProvider =
    NotifierProvider<ContextPreferenceRevisionController, int>(
      ContextPreferenceRevisionController.new,
    );

class ContextPackController extends Notifier<ContextPack?> {
  final Map<String, Set<String>> _includeNextByRoot = {};

  @override
  ContextPack? build() {
    _includeNextByRoot.clear();
    return null;
  }

  Future<ContextPack> buildForCodingTaskWithFreshIndex({
    String? prompt,
    Set<String> allowedFileContextPaths = const {},
  }) async {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (rootPath != null) {
      await ref.read(fileIndexerProvider.notifier).refreshIfStale();
    }
    return buildForCodingTask(
      prompt: prompt,
      allowedFileContextPaths: allowedFileContextPaths,
    );
  }

  ContextPack buildForCodingTask({
    String? prompt,
    Set<String> allowedFileContextPaths = const {},
  }) {
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
    }

    items.addAll(
      _mentionedFileItems(
        prompt,
        rootPath,
        allowedFileContextPaths: allowedFileContextPaths,
      ),
    );
    final changedFiles = {
      ...git.staged.map((change) => change.path),
      ...git.unstaged.map((change) => change.path),
      ...git.untracked.map((change) => change.path),
    };
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

    final instructionItems = _instructionItems(
      rootPath,
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

  void includeNextTime(String relativePath) {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (rootPath == null) return;
    final normalized = ContextPreferenceStore._normalizePreferencePath(
      relativePath,
    );
    if (normalized == null) return;
    if (_isIgnoredContextPath(normalized) ||
        _isInstructionContextPath(normalized) ||
        !_isRelevantContextExtension(normalized)) {
      return;
    }
    final file = File(p.join(rootPath, normalized));
    if (!file.existsSync() || file.lengthSync() > 80 * 1024) return;
    final rootKey = p.normalize(rootPath);
    final paths = _includeNextByRoot.putIfAbsent(
      rootKey,
      () => ref
          .read(contextPreferenceStoreProvider)
          .loadIncludedPaths(rootPath)
          .toSet(),
    );
    paths.add(normalized);
    ref.read(contextPreferenceStoreProvider).saveIncludedPaths(rootPath, paths);
    ref.read(contextPreferenceRevisionProvider.notifier).bump();
  }

  void removeIncludeNextTime(String relativePath) {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (rootPath == null) return;
    final normalized = ContextPreferenceStore._normalizePreferencePath(
      relativePath,
    );
    if (normalized == null) return;
    final rootKey = p.normalize(rootPath);
    final paths = _includeNextByRoot.putIfAbsent(
      rootKey,
      () => ref
          .read(contextPreferenceStoreProvider)
          .loadIncludedPaths(rootPath)
          .toSet(),
    );
    if (!paths.remove(normalized)) return;
    ref.read(contextPreferenceStoreProvider).saveIncludedPaths(rootPath, paths);
    ref.read(contextPreferenceRevisionProvider.notifier).bump();

    final pack = state;
    if (pack == null) return;
    final pinnedIds = {
      for (final item in pack.allItems)
        if (item.source == normalized &&
            (item.retrievalReason ?? '').contains('included next time'))
          item.id,
      for (final candidate
          in pack.retrievalResult?.rankedCandidates ??
              const <ContextCandidate>[])
        if (candidate.path == normalized &&
            candidate.reason.contains('included next time'))
          candidate.id,
    };
    if (pinnedIds.isEmpty) return;
    final retrieval = pack.retrievalResult;
    state = pack.copyWith(
      items: pack.items
          .where((item) => !pinnedIds.contains(item.id))
          .toList(growable: false),
      instructionItems: pack.instructionItems
          .where((item) => !pinnedIds.contains(item.id))
          .toList(growable: false),
      retrievalResult: retrieval == null
          ? null
          : ContextRetrievalResult(
              rankedCandidates: retrieval.rankedCandidates
                  .where((candidate) => !pinnedIds.contains(candidate.id))
                  .toList(growable: false),
              budget: retrieval.budget,
              warnings: retrieval.warnings,
            ),
    );
  }

  Set<String> includeNextTimePathsForCurrentRoot() {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (rootPath == null) return const {};
    final rootKey = p.normalize(rootPath);
    return Set.unmodifiable(
      _includeNextByRoot[rootKey] ??
          ref.read(contextPreferenceStoreProvider).loadIncludedPaths(rootPath),
    );
  }

  static int _estimateTokens(String value) => (value.length / 4).ceil();

  ContextRetrievalResult _buildRetrievalResult({
    required List<ContextPackItem> items,
    required List<ContextPackItem> instructionItems,
    List<ContextCandidate> omittedCandidates = const [],
    required int maxTokens,
  }) {
    final allItems = [...items, ...instructionItems];
    final used = allItems.fold<int>(
      0,
      (total, item) => total + item.estimatedTokens,
    );
    final budget = ContextBudgetReport(
      maxTokens: maxTokens,
      reservedForResponse: 4096,
      availableForContext: ContextPackBudget(
        maxTokens: maxTokens,
      ).availableForContext,
      usedTokens: used,
    );
    final scoresById = {
      for (final item in allItems)
        item.id: item.retrievalScore ?? _contextScore(item),
    };
    final selectedIds = _selectContextItemIdsForBudget(
      allItems,
      scoresById: scoresById,
      budget: budget,
    );
    final budgetOmittedCount = allItems
        .where(
          (item) => item.includedByDefault && !selectedIds.contains(item.id),
        )
        .length;
    final candidates = [
      for (final item in allItems)
        ContextCandidate(
          id: item.id,
          title: item.title,
          path: item.source,
          sourceKind: item.sourceKind,
          score: scoresById[item.id] ?? _contextScore(item),
          estimatedTokens: item.estimatedTokens,
          included: item.includedByDefault && selectedIds.contains(item.id),
          reason: selectedIds.contains(item.id)
              ? _contextReason(item)
              : '${_contextReason(item)} Omitted by token budget.',
        ),
      ...omittedCandidates,
    ]..sort((a, b) => b.score.compareTo(a.score));
    return ContextRetrievalResult(
      rankedCandidates: candidates,
      budget: budget,
      warnings: [
        if (budget.exceeded)
          const ContextPackWarning(
            message: 'Context exceeds the selected model token budget.',
          ),
        if (omittedCandidates.isNotEmpty)
          ContextPackWarning(
            message:
                '${omittedCandidates.length} high-scoring context candidate${omittedCandidates.length == 1 ? '' : 's'} omitted from this turn.',
          ),
        if (budgetOmittedCount > 0)
          ContextPackWarning(
            message:
                '$budgetOmittedCount visible context item${budgetOmittedCount == 1 ? '' : 's'} omitted by token budget before sending.',
          ),
        ..._instructionPolicyWarnings(instructionItems),
      ],
    );
  }

  Set<String> _selectContextItemIdsForBudget(
    List<ContextPackItem> items, {
    required Map<String, int> scoresById,
    required ContextBudgetReport budget,
  }) {
    final includedItems = items
        .where((item) => item.includedByDefault)
        .toList(growable: false);
    if (includedItems.isEmpty) return const {};
    if (budget.availableForContext <= 0 ||
        budget.usedTokens <= budget.availableForContext) {
      return {for (final item in includedItems) item.id};
    }

    final ranked = [...includedItems]
      ..sort((a, b) {
        if (a.removable != b.removable) return a.removable ? 1 : -1;
        final scoreA = scoresById[a.id] ?? _contextScore(a);
        final scoreB = scoresById[b.id] ?? _contextScore(b);
        final scoreCompare = scoreB.compareTo(scoreA);
        if (scoreCompare != 0) return scoreCompare;
        return includedItems.indexOf(a).compareTo(includedItems.indexOf(b));
      });

    final selected = <String>{};
    var used = 0;
    for (final item in ranked) {
      final nextUsed = used + item.estimatedTokens;
      if (selected.isEmpty || nextUsed <= budget.availableForContext) {
        selected.add(item.id);
        used = nextUsed;
      }
    }
    return selected;
  }

  List<ContextPackWarning> _instructionPolicyWarnings(
    List<ContextPackItem> instructionItems,
  ) {
    final warnings = <ContextPackWarning>[];
    for (final item in instructionItems) {
      final text = item.detail.toLowerCase();
      final source = item.source ?? item.title;
      if (_mentionsInstructionPermissionBypass(text)) {
        warnings.add(
          ContextPackWarning(
            itemId: item.id,
            message:
                '$source contains permission-like instructions. Circuit treats project instruction files as guidance only; app policy still controls tools, approvals, and workspace boundaries.',
          ),
        );
      }
      if (_mentionsInstructionWorkspaceBypass(text)) {
        warnings.add(
          ContextPackWarning(
            itemId: item.id,
            message:
                '$source references filesystem or workspace-boundary behavior. Circuit will still enforce the selected workspace root and deny unsafe paths.',
          ),
        );
      }
      if (_mentionsInstructionNetworkBypass(text)) {
        warnings.add(
          ContextPackWarning(
            itemId: item.id,
            message:
                '$source references network or internet access. Circuit treats project instruction files as guidance only; app policy still controls network tools and domain access.',
          ),
        );
      }
      if (_mentionsInstructionMcpBypass(text)) {
        warnings.add(
          ContextPackWarning(
            itemId: item.id,
            message:
                '$source references MCP or connector side effects. Circuit treats project instruction files as guidance only; app policy still controls connector tools and mutation access.',
          ),
        );
      }
    }
    warnings.addAll(_instructionConflictWarnings(instructionItems));
    return warnings;
  }

  List<ContextPackWarning> _instructionConflictWarnings(
    List<ContextPackItem> instructionItems,
  ) {
    final approvalBypassSources = <String>[];
    final approvalRequiredSources = <String>[];
    final workspaceBypassSources = <String>[];
    final workspaceRestrictedSources = <String>[];
    final networkBypassSources = <String>[];
    final networkRestrictedSources = <String>[];
    final mcpBypassSources = <String>[];
    final mcpRestrictedSources = <String>[];

    for (final item in instructionItems) {
      final text = item.detail.toLowerCase();
      final source = item.source ?? item.title;
      if (_mentionsInstructionPermissionBypass(text)) {
        approvalBypassSources.add(source);
      }
      if (_mentionsInstructionApprovalRequired(text)) {
        approvalRequiredSources.add(source);
      }
      if (_mentionsInstructionWorkspaceBypass(text)) {
        workspaceBypassSources.add(source);
      }
      if (_mentionsInstructionWorkspaceRestricted(text)) {
        workspaceRestrictedSources.add(source);
      }
      if (_mentionsInstructionNetworkBypass(text)) {
        networkBypassSources.add(source);
      }
      if (_mentionsInstructionNetworkRestricted(text)) {
        networkRestrictedSources.add(source);
      }
      if (_mentionsInstructionMcpBypass(text)) {
        mcpBypassSources.add(source);
      }
      if (_mentionsInstructionMcpRestricted(text)) {
        mcpRestrictedSources.add(source);
      }
    }

    return [
      if (approvalBypassSources.isNotEmpty &&
          approvalRequiredSources.isNotEmpty)
        ContextPackWarning(
          itemId: 'instruction-conflict:approval',
          message:
              'Project instruction files contain conflicting approval guidance (${_sourceList(approvalBypassSources)} vs ${_sourceList(approvalRequiredSources)}). Circuit treats instructions as guidance only; app permission policy decides when tools require review.',
        ),
      if (workspaceBypassSources.isNotEmpty &&
          workspaceRestrictedSources.isNotEmpty)
        ContextPackWarning(
          itemId: 'instruction-conflict:workspace',
          message:
              'Project instruction files contain conflicting workspace-boundary guidance (${_sourceList(workspaceBypassSources)} vs ${_sourceList(workspaceRestrictedSources)}). Circuit enforces the selected workspace root regardless of instruction text.',
        ),
      if (networkBypassSources.isNotEmpty &&
          networkRestrictedSources.isNotEmpty)
        ContextPackWarning(
          itemId: 'instruction-conflict:network',
          message:
              'Project instruction files contain conflicting network guidance (${_sourceList(networkBypassSources)} vs ${_sourceList(networkRestrictedSources)}). Circuit treats instructions as guidance only; app network policy decides when web or domain access requires review.',
        ),
      if (mcpBypassSources.isNotEmpty && mcpRestrictedSources.isNotEmpty)
        ContextPackWarning(
          itemId: 'instruction-conflict:mcp',
          message:
              'Project instruction files contain conflicting connector guidance (${_sourceList(mcpBypassSources)} vs ${_sourceList(mcpRestrictedSources)}). Circuit treats instructions as guidance only; app connector policy decides when MCP tools require review.',
        ),
    ];
  }

  String _sourceList(List<String> sources) {
    final unique = <String>[];
    for (final source in sources) {
      if (!unique.contains(source)) unique.add(source);
    }
    if (unique.length <= 2) return unique.join(', ');
    return '${unique.take(2).join(', ')} +${unique.length - 2} more';
  }

  bool _mentionsInstructionPermissionBypass(String text) {
    const phrases = [
      'bypass approval',
      'bypass approvals',
      'skip approval',
      'skip approvals',
      'auto approve',
      'auto-approve',
      'never ask approval',
      'never ask for approval',
      'do not ask approval',
      'do not ask for approval',
      'without asking approval',
      'without asking for approval',
      'run commands without asking',
      'execute commands without asking',
      'ignore permissions',
      'ignore safety',
      'disable safety',
      'ignore sandbox',
      'disable sandbox',
    ];
    return phrases.any(text.contains);
  }

  bool _mentionsInstructionWorkspaceBypass(String text) {
    const phrases = [
      'full filesystem access',
      'full file system access',
      'outside the workspace',
      'outside workspace',
      'outside the project',
      'outside project',
      'write anywhere',
      'edit anywhere',
      'read anywhere',
      'unrestricted filesystem',
      'unrestricted file system',
    ];
    return phrases.any(text.contains);
  }

  bool _mentionsInstructionApprovalRequired(String text) {
    const phrases = [
      'always ask for approval',
      'always request approval',
      'ask before running commands',
      'ask before executing commands',
      'ask before shell commands',
      'request approval before',
      'require approval',
      'approval required',
      'review first',
      'do not run commands without approval',
      'never run commands without approval',
    ];
    return phrases.any(text.contains);
  }

  bool _mentionsInstructionWorkspaceRestricted(String text) {
    const phrases = [
      'stay inside the workspace',
      'stay within the workspace',
      'stay inside workspace',
      'stay within workspace',
      'only edit files in the workspace',
      'only write files in the workspace',
      'do not edit outside the workspace',
      'do not write outside the workspace',
      'workspace root only',
      'selected workspace root',
      'project root only',
      'inside the project root',
      'within the project root',
    ];
    return phrases.any(text.contains);
  }

  bool _mentionsInstructionNetworkBypass(String text) {
    const phrases = [
      'unrestricted network',
      'full network access',
      'internet access is allowed',
      'use the internet freely',
      'use web freely',
      'browse freely',
      'browse the web freely',
      'fetch external urls',
      'fetch external urls without asking',
      'call external apis without asking',
      'curl without asking',
      'wget without asking',
      'access any domain',
      'ignore network policy',
      'disable network policy',
    ];
    return phrases.any(text.contains);
  }

  bool _mentionsInstructionNetworkRestricted(String text) {
    const phrases = [
      'no internet',
      'no network',
      'network disabled',
      'offline only',
      'do not browse',
      'do not use the internet',
      'do not access external urls',
      'ask before internet',
      'ask before network',
      'ask before web',
      'ask before browsing',
      'request approval before internet',
      'request approval before network',
      'network requires approval',
      'internet requires approval',
      'web access requires approval',
    ];
    return phrases.any(text.contains);
  }

  bool _mentionsInstructionMcpBypass(String text) {
    const phrases = [
      'use mcp without asking',
      'use mcp tools without asking',
      'mcp without approval',
      'mcp tools without approval',
      'mutate mcp freely',
      'connector mutation is allowed',
      'connectors can mutate',
      'ignore mcp policy',
      'ignore connector policy',
      'disable mcp policy',
      'disable connector policy',
    ];
    return phrases.any(text.contains);
  }

  bool _mentionsInstructionMcpRestricted(String text) {
    const phrases = [
      'no mcp',
      'disable mcp',
      'mcp read only',
      'mcp read-only',
      'connector read only',
      'connector read-only',
      'ask before mcp',
      'ask before connectors',
      'request approval before mcp',
      'mcp requires approval',
      'connectors require approval',
      'do not mutate mcp',
      'do not mutate connectors',
    ];
    return phrases.any(text.contains);
  }

  int _contextScore(ContextPackItem item) {
    final override = item.retrievalScore;
    if (override != null) return override;
    return switch (item.type) {
      ContextPackItemType.mentionedFile => 100,
      ContextPackItemType.activeFile => 95,
      ContextPackItemType.selection => 95,
      ContextPackItemType.gitDiff => 90,
      ContextPackItemType.instruction => 80,
      ContextPackItemType.projectProfile => 75,
      ContextPackItemType.diagnostics => 65,
      ContextPackItemType.rule => 60,
      ContextPackItemType.terminal => 45,
      ContextPackItemType.memory => 35,
    };
  }

  String _contextReason(ContextPackItem item) {
    final override = item.retrievalReason;
    if (override != null && override.trim().isNotEmpty) return override;
    return switch (item.type) {
      ContextPackItemType.mentionedFile =>
        'Directly referenced or ranked by prompt terms.',
      ContextPackItemType.activeFile => 'Current editor context.',
      ContextPackItemType.selection => 'Current editor selection.',
      ContextPackItemType.gitDiff => 'Current working tree changes.',
      ContextPackItemType.instruction => 'Project instruction file.',
      ContextPackItemType.projectProfile =>
        'Workspace profile and recommended commands.',
      ContextPackItemType.diagnostics => 'Project scripts or diagnostics.',
      ContextPackItemType.rule => 'Circuit project rule.',
      ContextPackItemType.terminal => 'Recent selected terminal output.',
      ContextPackItemType.memory => 'Saved project or user memory.',
    };
  }

  static String _truncate(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}\n... truncated ...';
  }

  List<ContextPackItem> _instructionItems(
    String? rootPath, {
    String? prompt,
    Set<String> contextSources = const {},
  }) {
    if (rootPath == null) return const [];
    const candidates = [
      'AGENTS.md',
      'AGENT.md',
      'CLAUDE.md',
      'CLAUDE.local.md',
      '.rules',
      '.cursorrules',
      '.github/copilot-instructions.md',
    ];
    final items = <ContextPackItem>[];
    for (final relativePath in candidates) {
      final file = File(p.join(rootPath, relativePath));
      if (!file.existsSync()) continue;
      try {
        final content = _cleanInstructionContent(file.readAsStringSync());
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
    items.addAll(
      _directoryInstructionItems(
        rootPath: rootPath,
        directoryPath: p.join('.claude', 'rules'),
        prompt: prompt,
        contextSources: contextSources,
        limit: 8,
      ),
    );
    items.addAll(
      _directoryInstructionItems(
        rootPath: rootPath,
        directoryPath: p.join('.circuit', 'rules'),
        prompt: prompt,
        contextSources: contextSources,
        limit: 8,
      ),
    );
    return items;
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

  List<ContextPackItem> _mentionedFileItems(
    String? prompt,
    String? rootPath, {
    required Set<String> allowedFileContextPaths,
  }) {
    if (rootPath == null || prompt == null || prompt.trim().isEmpty) {
      return const [];
    }
    final matches = RegExp(
      r'(?:(?:[\w.-]+/)+)?[\w.-]+\.(?:dart|js|jsx|ts|tsx|py|md|json|yaml|yml|html|css|scss|go|rs|java|kt|swift|sh|sql|txt)',
      caseSensitive: false,
    ).allMatches(prompt);
    final terms = _contextSearchTerms(prompt);
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
      var content = _readFileIfSmall(candidate);
      if (content.trim().isEmpty) continue;
      final relativePath = p.relative(candidate, from: rootPath);
      if (!_fileContextAllowed(relativePath, allowedFileContextPaths)) {
        continue;
      }
      if (_isInstructionContextPath(relativePath)) {
        content = _cleanInstructionContent(content);
        if (content.trim().isEmpty) continue;
      }
      final lowerContent = content.toLowerCase();
      final contentTerms = [
        for (final term in terms)
          if (lowerContent.contains(term)) 'content term "$term"',
      ];
      items.add(
        ContextPackItem(
          id: 'mentioned-file:$relativePath',
          type: ContextPackItemType.mentionedFile,
          title: relativePath,
          detail: _truncate(content, 8000),
          source: relativePath,
          sourceKind: ContextPackSourceKind.editor,
          estimatedTokens: _estimateTokens(content) + 20,
          retrievalScore: 190,
          retrievalReason: _summarizeContextReasons([
            'explicit path mention',
            ...contentTerms.take(3),
          ]),
        ),
      );
    }
    return items;
  }

  _RelevantFileResult _relevantFileItems(
    String? prompt,
    String? rootPath, {
    required Set<String> changedFiles,
    required Set<String> alreadyIncludedSources,
    required Set<String> allowedFileContextPaths,
  }) {
    if (rootPath == null) {
      return const _RelevantFileResult(items: [], omittedCandidates: []);
    }
    final rootKey = p.normalize(rootPath);
    final pinnedPaths = _includeNextByRoot.putIfAbsent(
      rootKey,
      () => ref
          .read(contextPreferenceStoreProvider)
          .loadIncludedPaths(rootPath)
          .toSet(),
    );
    if ((prompt == null || prompt.trim().isEmpty) && pinnedPaths.isEmpty) {
      return const _RelevantFileResult(items: [], omittedCandidates: []);
    }
    final terms = _contextSearchTerms(prompt ?? '');
    if (terms.isEmpty && pinnedPaths.isEmpty) {
      return const _RelevantFileResult(items: [], omittedCandidates: []);
    }

    final scored = <_RelevantFileScore>[];
    final scoredPaths = <String>{};
    final indexedCandidates = <String>{};
    final indexer = ref.read(fileIndexerProvider.notifier);
    for (final term in terms) {
      for (final file in indexer.search(term, limit: 12)) {
        if (!file.isDirectory) indexedCandidates.add(file.relativePath);
      }
    }
    if (_promptWantsWorkflowContext(prompt ?? '')) {
      for (final file in ref.read(fileIndexerProvider)?.files ?? const []) {
        if (!file.isDirectory && _isWorkflowContextPath(file.relativePath)) {
          indexedCandidates.add(file.relativePath);
        }
      }
    }
    if (_promptWantsCommandContext(prompt ?? '')) {
      for (final file in ref.read(fileIndexerProvider)?.files ?? const []) {
        if (!file.isDirectory && _isCommandContextPath(file.relativePath)) {
          indexedCandidates.add(file.relativePath);
        }
      }
    }
    if (_promptWantsDeploymentContext(prompt ?? '')) {
      for (final file in ref.read(fileIndexerProvider)?.files ?? const []) {
        if (!file.isDirectory && _isDeploymentContextPath(file.relativePath)) {
          indexedCandidates.add(file.relativePath);
        }
      }
    }
    final activeDomains = _activeContextDomains(terms);
    if (activeDomains.isNotEmpty) {
      for (final file in ref.read(fileIndexerProvider)?.files ?? const []) {
        if (!file.isDirectory &&
            _domainContextBoost(file.relativePath, activeDomains) > 0) {
          indexedCandidates.add(file.relativePath);
        }
      }
    }
    for (final important in _importantContextFiles) {
      indexedCandidates.add(important);
    }
    for (final workspaceConfig in _workspaceContextFiles) {
      indexedCandidates.add(workspaceConfig);
    }
    for (final deploymentConfig in _deploymentContextFiles) {
      indexedCandidates.add(deploymentConfig);
    }

    final lowerPrompt = (prompt ?? '').toLowerCase();
    final normalizedChangedFiles = {
      for (final path in changedFiles) p.normalize(path),
    };

    void scoreFile(
      String relativePath,
      File file, {
      int boost = 0,
      String? boostReason,
    }) {
      if (!scoredPaths.add(relativePath)) return;
      if (!_fileContextAllowed(relativePath, allowedFileContextPaths)) return;
      if (alreadyIncludedSources.contains(relativePath)) return;
      if (_isIgnoredContextPath(relativePath)) return;
      if (_isInstructionContextPath(relativePath)) return;
      if (!_isRelevantContextExtension(relativePath)) return;
      if (!file.existsSync() || file.lengthSync() > 80 * 1024) return;
      final lowerPath = relativePath.toLowerCase();
      final lowerName = p.basename(relativePath).toLowerCase();
      final lowerStem = p.basenameWithoutExtension(relativePath).toLowerCase();
      final importantFileBoost = _importantContextFiles.contains(lowerName)
          ? 3
          : 0;
      final workflowBoost =
          _promptWantsWorkflowContext(prompt ?? '') &&
              _isWorkflowContextPath(relativePath)
          ? 22
          : 0;
      final commandBoost =
          _promptWantsCommandContext(prompt ?? '') &&
              _isCommandContextPath(relativePath)
          ? 20
          : 0;
      final workspaceBoost =
          _promptWantsWorkspaceContext(prompt ?? '') &&
              _isWorkspaceContextPath(relativePath)
          ? 45
          : 0;
      final deploymentBoost =
          _promptWantsDeploymentContext(prompt ?? '') &&
              _isDeploymentContextPath(relativePath)
          ? 48
          : 0;
      final domainBoost = _domainContextBoost(relativePath, activeDomains);
      final content = file.readAsStringSync();
      final lowerContent = content.toLowerCase();
      final reasons = <String>[];
      var score =
          boost +
          importantFileBoost +
          workflowBoost +
          commandBoost +
          workspaceBoost +
          deploymentBoost +
          domainBoost;
      if (boost > 0) reasons.add(boostReason ?? 'file index match');
      if (importantFileBoost > 0) reasons.add('important project file');
      if (workflowBoost > 0) reasons.add('CI workflow context');
      if (commandBoost > 0) reasons.add('command/script context');
      if (workspaceBoost > 0) reasons.add('workspace config context');
      if (deploymentBoost > 0) reasons.add('deployment config context');
      if (domainBoost > 0) {
        reasons.add(
          '${_domainContextLabels(relativePath, activeDomains).join('/')} context',
        );
      }
      if (normalizedChangedFiles.contains(p.normalize(relativePath))) {
        score += 18;
        reasons.add('changed file');
      }
      if (lowerPrompt.contains(lowerPath)) {
        score += 30;
        reasons.add('explicit path mention');
      } else if (lowerPrompt.contains(lowerName)) {
        score += 18;
        reasons.add('filename mention');
      } else if (lowerPrompt.contains(lowerStem)) {
        score += 14;
        reasons.add('filename stem mention');
      }
      for (final term in terms) {
        if (lowerStem == term || lowerName == term) {
          score += 16;
          reasons.add('exact filename term "$term"');
        } else if (lowerName.contains(term)) {
          score += 8;
          reasons.add('filename term "$term"');
        }
        if (lowerPath.contains(term)) {
          score += 5;
          reasons.add('path term "$term"');
        }
        if (lowerContent.contains(term)) {
          score += _contentTermScore(term);
          reasons.add('content term "$term"');
        }
      }
      if (score > 0) {
        scored.add(
          _RelevantFileScore(
            relativePath,
            content,
            score,
            _summarizeContextReasons(reasons),
          ),
        );
      }
    }

    var scanned = 0;
    try {
      final root = Directory(rootPath);
      if (!root.existsSync()) {
        return const _RelevantFileResult(items: [], omittedCandidates: []);
      }
      final stalePinnedPaths = [
        for (final relativePath in pinnedPaths)
          if (!_includeNextPathStillValid(rootPath, relativePath)) relativePath,
      ];
      if (stalePinnedPaths.isNotEmpty) {
        pinnedPaths.removeAll(stalePinnedPaths);
        ref
            .read(contextPreferenceStoreProvider)
            .saveIncludedPaths(rootPath, pinnedPaths);
        ref.read(contextPreferenceRevisionProvider.notifier).bump();
      }
      for (final relativePath in pinnedPaths) {
        final before = scored.length;
        scoreFile(
          relativePath,
          File(p.join(rootPath, relativePath)),
          boost: 80,
          boostReason: 'included next time from Context drawer',
        );
        if (scored.length > before) scanned++;
      }
      for (final relativePath in indexedCandidates) {
        if (scanned > 120) break;
        final file = File(p.join(rootPath, relativePath));
        final before = scored.length;
        scoreFile(relativePath, file, boost: 8);
        if (scored.length > before) scanned++;
      }

      final traversalPaths = _rankedTraversalPaths(
        rootPath: rootPath,
        promptTerms: terms,
      );
      var visited = 0;
      for (final relativePath in traversalPaths) {
        if (visited++ > 5000) break;
        final before = scored.length;
        scoreFile(relativePath, File(p.join(rootPath, relativePath)));
        if (scored.length > before) scanned++;
      }
    } catch (_) {
      return const _RelevantFileResult(items: [], omittedCandidates: []);
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final included = scored.take(_maxRelevantFileContextItems).toList();
    final omitted = scored
        .skip(_maxRelevantFileContextItems)
        .take(_maxOmittedRelevantFileCandidates)
        .toList();
    return _RelevantFileResult(
      items: [
        for (final file in included)
          ContextPackItem(
            id: 'relevant-file:${file.path}',
            type: ContextPackItemType.mentionedFile,
            title: file.path,
            detail: _truncate(file.content, 5000),
            source: file.path,
            sourceKind: ContextPackSourceKind.editor,
            estimatedTokens: _estimateTokens(file.content) + 20,
            retrievalScore: 70 + file.score,
            retrievalReason: file.reason,
          ),
      ],
      omittedCandidates: [
        for (final file in omitted)
          ContextCandidate(
            id: 'omitted-relevant-file:${file.path}',
            title: file.path,
            path: file.path,
            sourceKind: ContextPackSourceKind.editor,
            score: 70 + file.score,
            estimatedTokens: _estimateTokens(file.content) + 20,
            included: false,
            reason: '${file.reason}; omitted from this turn.',
          ),
      ],
    );
  }

  bool _includeNextPathStillValid(String rootPath, String relativePath) {
    final normalized = ContextPreferenceStore._normalizePreferencePath(
      relativePath,
    );
    if (normalized == null) return false;
    if (_isIgnoredContextPath(normalized) ||
        _isInstructionContextPath(normalized) ||
        !_isRelevantContextExtension(normalized)) {
      return false;
    }
    final file = File(p.join(rootPath, normalized));
    return file.existsSync() && file.lengthSync() <= 80 * 1024;
  }

  List<String> _rankedTraversalPaths({
    required String rootPath,
    required Set<String> promptTerms,
  }) {
    final index = ref.read(fileIndexerProvider);
    final indexedFiles = index?.workingDir == rootPath
        ? index!.files.where((file) => !file.isDirectory).toList()
        : const <IndexedFile>[];
    if (indexedFiles.isNotEmpty) {
      final scored = <({String path, int score})>[];
      final activeDomains = _activeContextDomains(promptTerms);
      for (final file in indexedFiles) {
        final relativePath = file.relativePath;
        if (_isIgnoredContextPath(relativePath) ||
            !_isRelevantContextExtension(relativePath)) {
          continue;
        }
        final lowerPath = relativePath.toLowerCase();
        final lowerName = file.fileName.toLowerCase();
        var score = _importantContextFiles.contains(lowerName) ? 20 : 0;
        if (_isWorkflowContextPath(relativePath) &&
            promptTerms.any(_isWorkflowPromptTerm)) {
          score += 35;
        }
        if (_isCommandContextPath(relativePath) &&
            promptTerms.any(_isCommandPromptTerm)) {
          score += 32;
        }
        if (_isWorkspaceContextPath(relativePath) &&
            promptTerms.any(_isWorkspacePromptTerm)) {
          score += 50;
        }
        if (_isDeploymentContextPath(relativePath) &&
            promptTerms.any(_isDeploymentPromptTerm)) {
          score += 55;
        }
        for (final term in promptTerms) {
          if (lowerName == term) {
            score += 40;
          } else if (lowerName.contains(term)) {
            score += 18;
          }
          if (lowerPath.contains(term)) score += 10;
        }
        final domainBoost = _domainContextBoost(relativePath, activeDomains);
        if (domainBoost > 0) score += domainBoost;
        scored.add((path: relativePath, score: score));
      }
      scored.sort((a, b) {
        final scoreCompare = b.score.compareTo(a.score);
        if (scoreCompare != 0) return scoreCompare;
        return a.path.compareTo(b.path);
      });
      return [for (final file in scored) file.path];
    }

    final paths = <String>[];
    try {
      for (final entity in Directory(
        rootPath,
      ).listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final relativePath = p.relative(entity.path, from: rootPath);
        if (_isIgnoredContextPath(relativePath) ||
            !_isRelevantContextExtension(relativePath)) {
          continue;
        }
        paths.add(relativePath);
      }
    } catch (_) {}
    paths.sort();
    return paths;
  }

  Set<String> _contextSearchTerms(String prompt) {
    final terms = <String>{};
    for (final match in RegExp(r'[A-Za-z0-9_./-]{3,}').allMatches(prompt)) {
      final raw = match.group(0)!;
      void add(String value) {
        final term = value.toLowerCase();
        if (term.length < 3) return;
        if (_commonContextTerms.contains(term)) return;
        terms.add(term);
      }

      add(raw);
      add(p.basename(raw));
      add(p.basenameWithoutExtension(raw));

      for (final part in raw.split(RegExp(r'[^A-Za-z0-9]+'))) {
        add(part);
        for (final camel in _splitCamelCase(part)) {
          add(camel);
        }
      }
    }
    return terms.take(32).toSet();
  }

  int _contentTermScore(String term) {
    if (term.length >= 16) return 64;
    if (term.length >= 11) return 32;
    if (term.length >= 8) return 12;
    return 2;
  }

  bool _promptWantsWorkflowContext(String prompt) {
    final normalized = prompt
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s./_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return false;
    return RegExp(
      r'\b(ci|workflow|workflows|github actions?|action|actions|pipeline|pipelines|build|deploy|deployment|release|releases|check|checks|test|tests|failing|failure|failed)\b',
    ).hasMatch(normalized);
  }

  bool _isWorkflowPromptTerm(String term) {
    return {
      'ci',
      'workflow',
      'workflows',
      'github',
      'actions',
      'action',
      'pipeline',
      'pipelines',
      'build',
      'deploy',
      'deployment',
      'release',
      'releases',
      'check',
      'checks',
      'test',
      'tests',
      'failing',
      'failure',
      'failed',
    }.contains(term);
  }

  bool _isWorkflowContextPath(String path) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    return normalized.startsWith('.github/workflows/') &&
        (normalized.endsWith('.yml') || normalized.endsWith('.yaml'));
  }

  bool _promptWantsCommandContext(String prompt) {
    final normalized = prompt
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s./_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return false;
    return RegExp(
      r'\b(script|scripts|command|commands|check|checks|verify|verification|test|tests|lint|build|deploy|deployment|release|ci|pipeline|failing|failure|failed)\b',
    ).hasMatch(normalized);
  }

  bool _isCommandPromptTerm(String term) {
    return {
      'script',
      'scripts',
      'command',
      'commands',
      'check',
      'checks',
      'verify',
      'verification',
      'test',
      'tests',
      'lint',
      'build',
      'deploy',
      'deployment',
      'release',
      'ci',
      'pipeline',
      'failing',
      'failure',
      'failed',
    }.contains(term);
  }

  bool _isCommandContextPath(String path) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    final parts = normalized.split('/');
    if (parts.isEmpty) return false;
    final first = parts.first;
    final inCommandDirectory = {
      'bin',
      'script',
      'scripts',
      'tool',
      'tools',
      'task',
      'tasks',
    }.contains(first);
    if (!inCommandDirectory) return false;
    final ext = p.extension(normalized);
    if (ext.isEmpty) return true;
    return {
      '.sh',
      '.bash',
      '.zsh',
      '.ps1',
      '.py',
      '.js',
      '.mjs',
      '.cjs',
      '.ts',
      '.dart',
      '.rb',
      '.pl',
      '.php',
      '.yaml',
      '.yml',
      '.json',
      '.md',
      '.txt',
    }.contains(ext);
  }

  bool _promptWantsWorkspaceContext(String prompt) {
    final normalized = prompt
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s./_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return false;
    return RegExp(
      r'\b(monorepo|workspace|workspaces|package|packages|app|apps|turbo|turborepo|nx|pnpm|yarn|melos|lerna|rush|build|test|deploy|pipeline|ci)\b',
    ).hasMatch(normalized);
  }

  bool _isWorkspacePromptTerm(String term) {
    return {
      'monorepo',
      'workspace',
      'workspaces',
      'package',
      'packages',
      'app',
      'apps',
      'turbo',
      'turborepo',
      'nx',
      'pnpm',
      'yarn',
      'melos',
      'lerna',
      'rush',
      'build',
      'test',
      'deploy',
      'pipeline',
      'ci',
    }.contains(term);
  }

  bool _isWorkspaceContextPath(String path) {
    final lowerName = p.basename(path).toLowerCase();
    return _workspaceContextFiles.contains(lowerName);
  }

  bool _promptWantsDeploymentContext(String prompt) {
    final normalized = prompt
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s./_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return false;
    return RegExp(
      r'\b(deploy|deployment|hosting|production|preview|release|vercel|netlify|firebase|railway|render|fly|docker|compose|container|containers|kubernetes|k8s|helm|cloudbuild|cloud run|gcp|aws|azure|environment|env|domain|domains)\b',
    ).hasMatch(normalized);
  }

  bool _isDeploymentPromptTerm(String term) {
    return {
      'deploy',
      'deployment',
      'hosting',
      'production',
      'preview',
      'release',
      'vercel',
      'netlify',
      'firebase',
      'railway',
      'render',
      'fly',
      'docker',
      'compose',
      'container',
      'containers',
      'kubernetes',
      'k8s',
      'helm',
      'cloudbuild',
      'gcp',
      'aws',
      'azure',
      'environment',
      'env',
      'domain',
      'domains',
    }.contains(term);
  }

  bool _isDeploymentContextPath(String path) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    final lowerName = p.basename(normalized);
    if (_deploymentContextFiles.contains(lowerName)) return true;
    final parts = normalized.split('/');
    if (parts.isEmpty) return false;
    final first = parts.first;
    if ({
      'deploy',
      'deployment',
      'deployments',
      'k8s',
      'kubernetes',
      'helm',
      'charts',
      'infra',
      'infrastructure',
      'terraform',
    }.contains(first)) {
      final ext = p.extension(normalized);
      return {
        '.yaml',
        '.yml',
        '.json',
        '.toml',
        '.tf',
        '.hcl',
        '.sh',
        '.md',
        '.txt',
      }.contains(ext);
    }
    return false;
  }

  Set<String> _activeContextDomains(Set<String> terms) {
    if (terms.isEmpty) return const {};
    final active = <String>{};
    for (final entry in _domainContextTerms.entries) {
      if (terms.any(entry.value.contains)) active.add(entry.key);
    }
    return active;
  }

  int _domainContextBoost(String relativePath, Set<String> activeDomains) {
    if (activeDomains.isEmpty) return 0;
    final labels = _domainContextLabels(relativePath, activeDomains);
    if (labels.isEmpty) return 0;
    return 42 + (labels.length - 1) * 8;
  }

  List<String> _domainContextLabels(
    String relativePath,
    Set<String> activeDomains,
  ) {
    if (activeDomains.isEmpty) return const [];
    final normalized = relativePath
        .replaceAll('\\', '/')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9/._-]+'), ' ');
    final tokens = normalized
        .split(RegExp(r'[/._\-\s]+'))
        .where((token) => token.length >= 2)
        .toSet();
    final labels = <String>[];
    for (final domain in activeDomains) {
      final domainTerms = _domainContextTerms[domain] ?? const <String>{};
      if (tokens.any(domainTerms.contains) ||
          domainTerms
              .where((term) => term.length >= 6)
              .any((term) => normalized.contains(term))) {
        labels.add(domain);
      }
    }
    return labels;
  }

  Iterable<String> _splitCamelCase(String value) {
    return value
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty);
  }

  String _summarizeContextReasons(List<String> reasons) {
    final unique = <String>[];
    for (final reason in reasons) {
      if (!unique.contains(reason)) unique.add(reason);
      if (unique.length >= 4) break;
    }
    if (unique.isEmpty) return 'Ranked by file index and prompt terms.';
    return 'Included by ${unique.join(', ')}.';
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

  bool _fileContextAllowed(String path, Set<String> allowedFileContextPaths) {
    if (allowedFileContextPaths.isEmpty) return true;
    final normalized = p.normalize(path).replaceAll('\\', '/');
    return allowedFileContextPaths.contains(normalized);
  }

  bool _isInstructionContextPath(String path) {
    final normalized = p.normalize(path).replaceAll('\\', '/');
    return normalized == 'AGENTS.md' ||
        normalized == 'AGENT.md' ||
        normalized == 'CLAUDE.md' ||
        normalized == 'CLAUDE.local.md' ||
        normalized == '.rules' ||
        normalized == '.cursorrules' ||
        normalized == '.github/copilot-instructions.md' ||
        normalized.startsWith('.claude/rules/') ||
        normalized.startsWith('.circuit/rules/');
  }

  bool _isRelevantContextExtension(String path) {
    final lowerName = p.basename(path).toLowerCase();
    if (_importantContextFiles.contains(lowerName)) return true;
    if (_workspaceContextFiles.contains(lowerName)) return true;
    if (_deploymentContextFiles.contains(lowerName)) return true;
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
      '.bash',
      '.zsh',
      '.ps1',
      '.rb',
      '.pl',
      '.php',
      '.toml',
      '.tf',
      '.hcl',
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

  List<ContextPackItem> _directoryInstructionItems({
    required String rootPath,
    required String directoryPath,
    String? prompt,
    Set<String> contextSources = const {},
    required int limit,
  }) {
    final dir = Directory(p.join(rootPath, directoryPath));
    if (!dir.existsSync()) return const [];
    final scoredItems = <_InstructionFileScore>[];
    final terms = _contextSearchTerms(prompt ?? '');
    final normalizedContextSources = {
      for (final source in contextSources)
        if (source.trim().isNotEmpty)
          p.normalize(source).replaceAll('\\', '/').toLowerCase(),
    };
    try {
      final files =
          dir
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .where(
                (entity) => p.extension(entity.path).toLowerCase() == '.md',
              )
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final entity in files) {
        if (p.extension(entity.path).toLowerCase() != '.md') continue;
        final relativePath = p.relative(entity.path, from: rootPath);
        final rawContent = entity.readAsStringSync();
        final content = _cleanInstructionContent(rawContent);
        if (content.trim().isEmpty) continue;
        final patternMatch = _frontmatterPatternsMatchContext(
          rawContent,
          normalizedContextSources,
        );
        final contextPathMatch = _instructionPathMatchesContext(
          relativePath,
          normalizedContextSources,
        );
        final promptTermMatch = _instructionTextMatchesTerms(
          relativePath,
          content,
          terms,
        );
        final score = _instructionRuleScore(
          patternMatch: patternMatch,
          contextPathMatch: contextPathMatch,
          promptTermMatch: promptTermMatch,
        );
        scoredItems.add(
          _InstructionFileScore(
            relativePath: relativePath,
            score: score,
            item: ContextPackItem(
              id: 'instruction:$relativePath',
              type: ContextPackItemType.instruction,
              title: p.basename(entity.path),
              detail: _truncate(content.trim(), 2200),
              source: relativePath,
              sourceKind: ContextPackSourceKind.instructionFile,
              estimatedTokens: _estimateTokens(content),
              removable: true,
              includedByDefault: true,
              retrievalScore: 80 + score,
              retrievalReason: score > 0
                  ? _summarizeContextReasons([
                      if (patternMatch) 'path-scoped rule pattern',
                      if (contextPathMatch) 'active context path',
                      if (promptTermMatch) 'prompt terms',
                    ])
                  : null,
            ),
          ),
        );
      }
      scoredItems.sort((a, b) {
        final scoreOrder = b.score.compareTo(a.score);
        if (scoreOrder != 0) return scoreOrder;
        return a.relativePath.compareTo(b.relativePath);
      });
    } catch (_) {}
    return scoredItems.take(limit).map((score) => score.item).toList();
  }

  int _instructionRuleScore({
    required bool patternMatch,
    required bool contextPathMatch,
    required bool promptTermMatch,
  }) {
    var score = 0;
    if (patternMatch) score += 90;
    if (contextPathMatch) score += 45;
    if (promptTermMatch) score += 25;
    return score;
  }

  bool _instructionTextMatchesTerms(
    String relativePath,
    String content,
    Set<String> terms,
  ) {
    if (terms.isEmpty) return false;
    final haystack = '${relativePath.toLowerCase()}\n${content.toLowerCase()}';
    return terms.any(haystack.contains);
  }

  bool _instructionPathMatchesContext(
    String relativePath,
    Set<String> contextSources,
  ) {
    if (contextSources.isEmpty) return false;
    final ruleParts = p
        .split(relativePath)
        .map((part) => part.toLowerCase())
        .where((part) => part.length >= 3)
        .toSet();
    if (ruleParts.isEmpty) return false;
    for (final source in contextSources) {
      final sourceParts = p
          .split(source)
          .map((part) => part.toLowerCase())
          .where((part) => part.length >= 3)
          .toSet();
      if (sourceParts.any(ruleParts.contains)) return true;
    }
    return false;
  }

  bool _frontmatterPatternsMatchContext(
    String rawContent,
    Set<String> contextSources,
  ) {
    if (contextSources.isEmpty) return false;
    final frontmatter = _yamlFrontmatter(rawContent);
    if (frontmatter == null || frontmatter.trim().isEmpty) return false;
    final patterns = <String>[];
    for (final line in frontmatter.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('- ')) {
        patterns.add(_unquoteYamlValue(trimmed.substring(2).trim()));
      } else if (trimmed.contains(':')) {
        final value = trimmed.substring(trimmed.indexOf(':') + 1).trim();
        if (value.isNotEmpty && value != '|' && value != '>') {
          patterns.add(_unquoteYamlValue(value));
        }
      }
    }
    return patterns.any(
      (pattern) => contextSources.any(
        (source) => _globLikePatternMatchesPath(pattern, source),
      ),
    );
  }

  String? _yamlFrontmatter(String content) {
    final trimmed = content.trimLeft();
    if (!trimmed.startsWith('---')) return null;
    final match = RegExp(r'^---\s*\n([\s\S]*?)\n---\s*\n?').firstMatch(trimmed);
    return match?.group(1);
  }

  String _unquoteYamlValue(String value) {
    var normalized = value.trim();
    if (normalized.startsWith('[') && normalized.endsWith(']')) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    return normalized
        .split(',')
        .first
        .trim()
        .replaceAll(RegExp(r'''^['"]|['"]$'''), '');
  }

  bool _globLikePatternMatchesPath(String pattern, String path) {
    final normalizedPattern = pattern.trim().replaceAll('\\', '/');
    if (normalizedPattern.isEmpty || normalizedPattern.contains('\n')) {
      return false;
    }
    final normalizedPath = path.trim().replaceAll('\\', '/');
    if (normalizedPattern == normalizedPath) return true;
    final buffer = StringBuffer('^');
    for (var i = 0; i < normalizedPattern.length; i++) {
      final char = normalizedPattern[i];
      if (char == '*') {
        if (i + 1 < normalizedPattern.length &&
            normalizedPattern[i + 1] == '*') {
          buffer.write('.*');
          i++;
        } else {
          buffer.write('[^/]*');
        }
      } else {
        buffer.write(RegExp.escape(char));
      }
    }
    buffer.write(r'$');
    try {
      return RegExp(buffer.toString()).hasMatch(normalizedPath);
    } catch (_) {
      return false;
    }
  }

  String _cleanInstructionContent(String content) {
    return _stripYamlFrontmatter(_stripHtmlComments(content)).trim();
  }

  String _stripHtmlComments(String content) {
    return content.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '').trim();
  }

  String _stripYamlFrontmatter(String content) {
    final trimmed = content.trimLeft();
    if (!trimmed.startsWith('---')) return content;
    final match = RegExp(r'^---\s*\n[\s\S]*?\n---\s*\n?').firstMatch(trimmed);
    if (match == null) return content;
    return trimmed.substring(match.end);
  }
}

final contextPackProvider =
    NotifierProvider<ContextPackController, ContextPack?>(
      ContextPackController.new,
    );
