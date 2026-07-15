part of 'context_pack_provider.dart';

mixin ContextPackRelevance on Notifier<ContextPack?> {
  Map<String, Set<String>> get _includeNextByRoot;
  Map<String, Set<String>> get _excludeProjectByRoot;
  String _readFileIfSmall(String path);
  String _cleanInstructionContent(String content);
  int _estimateTokens(String value);
  String _truncate(String value, int maxChars);
  String _contextFingerprint(String value);

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
          retrievalScore: 1000,
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
    FileIndexer? indexerOverride,
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
    final excludedPaths = _excludeProjectByRoot.putIfAbsent(
      rootKey,
      () => ref
          .read(contextPreferenceStoreProvider)
          .loadExcludedPaths(rootPath)
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
    final indexedFiles =
        indexerOverride?.files ??
        ref.read(fileIndexerProvider)?.files ??
        const <IndexedFile>[];
    final indexedFilesByPath = {
      for (final indexedFile in indexedFiles)
        indexedFile.relativePath: indexedFile,
    };
    for (final term in terms) {
      final matches =
          indexerOverride?.search(term, limit: 12) ??
          ref.read(fileIndexerProvider.notifier).search(term, limit: 12);
      for (final file in matches) {
        if (!file.isDirectory) indexedCandidates.add(file.relativePath);
      }
    }
    if (_promptWantsWorkflowContext(prompt ?? '')) {
      for (final file in indexedFiles) {
        if (!file.isDirectory && _isWorkflowContextPath(file.relativePath)) {
          indexedCandidates.add(file.relativePath);
        }
      }
    }
    if (_promptWantsCommandContext(prompt ?? '')) {
      for (final file in indexedFiles) {
        if (!file.isDirectory && _isCommandContextPath(file.relativePath)) {
          indexedCandidates.add(file.relativePath);
        }
      }
    }
    if (_promptWantsDeploymentContext(prompt ?? '')) {
      for (final file in indexedFiles) {
        if (!file.isDirectory && _isDeploymentContextPath(file.relativePath)) {
          indexedCandidates.add(file.relativePath);
        }
      }
    }
    final activeDomains = _activeContextDomains(terms);
    if (activeDomains.isNotEmpty) {
      for (final file in indexedFiles) {
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

    var candidateFileReads = 0;

    void scoreFile(
      String relativePath,
      File file, {
      int boost = 0,
      String? boostReason,
    }) {
      if (!scoredPaths.add(relativePath)) return;
      if (excludedPaths.contains(relativePath)) return;
      if (!_fileContextAllowed(relativePath, allowedFileContextPaths)) return;
      if (alreadyIncludedSources.contains(relativePath)) return;
      if (_isIgnoredContextPath(relativePath)) return;
      if (_isInstructionContextPath(relativePath)) return;
      if (!_isRelevantContextExtension(relativePath)) return;
      if (candidateFileReads >= _maxContextCandidateFileReads) return;
      if (!file.existsSync() || file.lengthSync() > 80 * 1024) return;
      candidateFileReads++;
      final lowerPath = relativePath.toLowerCase();
      final lowerName = p.basename(relativePath).toLowerCase();
      final lowerStem = p.basenameWithoutExtension(relativePath).toLowerCase();
      final indexedFile = indexedFilesByPath[relativePath];
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
          ? 120
          : 0;
      final deploymentBoost =
          _promptWantsDeploymentContext(prompt ?? '') &&
              _isDeploymentContextPath(relativePath)
          ? 120
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
        score += 220;
        reasons.add('explicit path mention');
      } else if (lowerPrompt.contains(lowerName)) {
        score += 90;
        reasons.add('filename mention');
      } else if (lowerPrompt.contains(lowerStem)) {
        score += 60;
        reasons.add('filename stem mention');
      }
      for (final term in terms) {
        if (indexedFile?.symbols.contains(term) == true) {
          score += _symbolTermScore(term);
          reasons.add('symbol "$term"');
        }
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
        indexerOverride: indexerOverride,
      );
      for (final relativePath in traversalPaths.take(
        _maxRankedTraversalCandidates,
      )) {
        final before = scored.length;
        scoreFile(relativePath, File(p.join(rootPath, relativePath)));
        if (scored.length > before) scanned++;
      }
    } catch (_) {
      return const _RelevantFileResult(items: [], omittedCandidates: []);
    }

    scored.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      return a.path.compareTo(b.path);
    });
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
            contentFingerprint: _contextFingerprint(file.content),
            truncated: file.content.length > 5000,
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
    FileIndexer? indexerOverride,
  }) {
    final index = indexerOverride ?? ref.read(fileIndexerProvider);
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
          if (file.symbols.contains(term)) {
            score += 42;
          }
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

  int _symbolTermScore(String term) {
    if (term.length >= 16) return 92;
    if (term.length >= 11) return 64;
    if (term.length >= 8) return 36;
    return 18;
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
    return normalized == 'CIRCUIT.md' ||
        normalized == 'AGENTS.md' ||
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
}
