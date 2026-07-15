part of 'context_pack_provider.dart';

mixin ContextPackSelection on Notifier<ContextPack?> {
  Map<String, Set<String>> get _includeNextByRoot;
  Map<String, Set<String>> get _excludeProjectByRoot;
  List<ContextPackWarning> _instructionPolicyWarningsForSelection(
    List<ContextPackItem> instructionItems,
  );
  int _contextScoreForSelection(ContextPackItem item);
  String _contextReasonForSelection(ContextPackItem item);
  bool _isIgnoredContextPath(String path);
  bool _isInstructionContextPath(String path);
  bool _isRelevantContextExtension(String path);

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

  void excludeForProject(String relativePath) {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (rootPath == null) return;
    final normalized = ContextPreferenceStore._normalizePreferencePath(
      relativePath,
    );
    if (normalized == null) return;
    final rootKey = p.normalize(rootPath);
    final excluded = _excludeProjectByRoot.putIfAbsent(
      rootKey,
      () => ref
          .read(contextPreferenceStoreProvider)
          .loadExcludedPaths(rootPath)
          .toSet(),
    );
    if (!excluded.add(normalized)) return;
    final included = _includeNextByRoot.putIfAbsent(
      rootKey,
      () => ref
          .read(contextPreferenceStoreProvider)
          .loadIncludedPaths(rootPath)
          .toSet(),
    );
    included.remove(normalized);
    final store = ref.read(contextPreferenceStoreProvider);
    store.saveIncludedPaths(rootPath, included);
    store.saveExcludedPaths(rootPath, excluded);
    ref.read(contextPreferenceRevisionProvider.notifier).bump();
  }

  void removeProjectExclusion(String relativePath) {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (rootPath == null) return;
    final normalized = ContextPreferenceStore._normalizePreferencePath(
      relativePath,
    );
    if (normalized == null) return;
    final rootKey = p.normalize(rootPath);
    final excluded = _excludeProjectByRoot.putIfAbsent(
      rootKey,
      () => ref
          .read(contextPreferenceStoreProvider)
          .loadExcludedPaths(rootPath)
          .toSet(),
    );
    if (!excluded.remove(normalized)) return;
    ref
        .read(contextPreferenceStoreProvider)
        .saveExcludedPaths(rootPath, excluded);
    ref.read(contextPreferenceRevisionProvider.notifier).bump();
  }

  void resetProjectContextChoices() {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (rootPath == null) return;
    final rootKey = p.normalize(rootPath);
    _includeNextByRoot.remove(rootKey);
    _excludeProjectByRoot.remove(rootKey);
    ref.read(contextPreferenceStoreProvider).clear(rootPath);
    ref.read(contextPreferenceRevisionProvider.notifier).bump();
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

  Set<String> excludedPathsForCurrentRoot() {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (rootPath == null) return const {};
    final rootKey = p.normalize(rootPath);
    return Set.unmodifiable(
      _excludeProjectByRoot[rootKey] ??
          ref.read(contextPreferenceStoreProvider).loadExcludedPaths(rootPath),
    );
  }

  /// A deterministic non-cryptographic fingerprint for context accountability.
  /// It lets support compare the supplied/omitted content without retaining
  /// another copy of potentially sensitive source text.
  String _contextFingerprint(String value) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  ContextCandidate _candidateWithRank(ContextCandidate candidate, int rank) {
    return ContextCandidate(
      id: candidate.id,
      title: candidate.title,
      path: candidate.path,
      sourceKind: candidate.sourceKind,
      score: candidate.score,
      estimatedTokens: candidate.estimatedTokens,
      included: candidate.included,
      reason: candidate.reason,
      rank: rank,
      contentFingerprint: candidate.contentFingerprint,
      truncated: candidate.truncated,
    );
  }

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
        item.id: item.retrievalScore ?? _contextScoreForSelection(item),
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
    final unrankedCandidates = [
      for (final item in allItems)
        ContextCandidate(
          id: item.id,
          title: item.title,
          path: item.source,
          sourceKind: item.sourceKind,
          score: scoresById[item.id] ?? _contextScoreForSelection(item),
          estimatedTokens: item.estimatedTokens,
          included: item.includedByDefault && selectedIds.contains(item.id),
          reason: selectedIds.contains(item.id)
              ? _contextReasonForSelection(item)
              : '${_contextReasonForSelection(item)} Omitted by token budget.',
          contentFingerprint: _contextFingerprint(item.detail),
          truncated: item.detail.contains('... truncated ...'),
        ),
      ...omittedCandidates,
    ]..sort((a, b) => b.score.compareTo(a.score));
    final candidates = [
      for (var index = 0; index < unrankedCandidates.length; index++)
        _candidateWithRank(unrankedCandidates[index], index + 1),
    ];
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
        ..._instructionPolicyWarningsForSelection(instructionItems),
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
        final scoreA = scoresById[a.id] ?? _contextScoreForSelection(a);
        final scoreB = scoresById[b.id] ?? _contextScoreForSelection(b);
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
}
