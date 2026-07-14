import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/logger.dart';
import '../models/semantic_search_models.dart';
import '../services/semantic_index.dart';
import '../services/worker_cancellation.dart';
import '../state/connection_provider.dart';
import '../state/file_tree_provider.dart';

class SemanticSearchNotifier extends Notifier<SemanticSearchState> {
  final SemanticIndex _index = SemanticIndex();
  Timer? _debounceTimer;
  WorkerCancellationToken? _indexCancellation;

  @override
  SemanticSearchState build() {
    ref.onDispose(() {
      _debounceTimer?.cancel();
      _indexCancellation?.cancel('Semantic search disposed.');
    });
    return const SemanticSearchState();
  }

  /// Toggle semantic search mode on/off.
  void toggleSemanticMode() {
    final newMode = !state.isSemanticMode;
    state = state.copyWith(
      isSemanticMode: newMode,
      results: [],
      query: '',
      error: null,
    );

    // Auto-build index when entering semantic mode if needed
    if (newMode && _index.chunkCount == 0) {
      buildIndex();
    }
  }

  /// Build or rebuild the semantic index for the current project.
  Future<void> buildIndex() async {
    _indexCancellation?.cancel('Superseded by a newer semantic index build.');
    final cancellation = WorkerCancellationToken();
    _indexCancellation = cancellation;
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (rootPath == null) {
      state = state.copyWith(error: 'No project open');
      return;
    }

    state = state.copyWith(
      isIndexing: true,
      indexedFileCount: 0,
      totalFileCount: 0,
      error: null,
    );

    // Try loading cached index first
    bool loaded;
    try {
      loaded = await _index.loadIndex(
        rootPath,
        cancellationToken: cancellation,
      );
    } on WorkerCancelledException {
      if (identical(_indexCancellation, cancellation)) {
        state = state.copyWith(isIndexing: false);
      }
      return;
    }
    if (!identical(_indexCancellation, cancellation)) return;
    if (loaded && !_index.isStale) {
      state = state.copyWith(
        isIndexing: false,
        indexedFileCount: _index.chunkCount,
        totalFileCount: _index.chunkCount,
      );
      return;
    }

    // Build fresh index
    try {
      await _index.buildIndex(
        rootPath,
        cancellationToken: cancellation,
        onProgress: (indexed, total) {
          state = state.copyWith(
            indexedFileCount: indexed,
            totalFileCount: total,
          );
        },
      );
    } on WorkerCancelledException {
      if (identical(_indexCancellation, cancellation)) {
        state = state.copyWith(isIndexing: false);
      }
      return;
    }
    if (!identical(_indexCancellation, cancellation)) return;

    // Save to disk for next time
    try {
      await _index.saveIndex(rootPath, cancellationToken: cancellation);
    } on WorkerCancelledException {
      if (identical(_indexCancellation, cancellation)) {
        state = state.copyWith(isIndexing: false);
      }
      return;
    }
    if (!identical(_indexCancellation, cancellation)) return;

    state = state.copyWith(isIndexing: false);
    Logger.info(
      'Semantic index ready: ${_index.chunkCount} chunks',
      'SemanticSearch',
    );
  }

  /// Search using natural language query.
  /// Phase 1: keyword pre-filter from index.
  /// Phase 2: AI ranking and explanation.
  void search(String query) {
    if (query.trim().isEmpty) {
      _debounceTimer?.cancel();
      state = state.copyWith(query: '', results: [], error: null);
      return;
    }

    state = state.copyWith(query: query);

    // Debounce AI calls at 600ms
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () {
      _executeSearch(query);
    });
  }

  /// Clear all search results.
  void clearResults() {
    _debounceTimer?.cancel();
    state = state.copyWith(query: '', results: [], error: null);
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  Future<void> _executeSearch(String query) async {
    if (_index.chunkCount == 0) {
      state = state.copyWith(error: 'Index not built. Building now...');
      await buildIndex();
    }

    state = state.copyWith(isSearching: true, error: null);

    try {
      // Phase 1: Get keyword-matched candidates
      final candidates = _index.getCandidates(query, limit: 30);

      if (candidates.isEmpty) {
        state = state.copyWith(isSearching: false, results: []);
        return;
      }

      // Phase 2: Ask AI to rank and explain relevance
      final agentService = ref.read(agentServiceProvider);
      if (!agentService.isConnected) {
        // Fall back to keyword-only results without AI ranking
        final results = candidates.map((chunk) {
          return SemanticSearchResult(
            chunk: chunk,
            score: 0.5,
            explanation: null,
          );
        }).toList();
        state = state.copyWith(isSearching: false, results: results);
        return;
      }

      // Build compact candidate summaries for AI
      final candidateSummaries = <Map<String, dynamic>>[];
      for (int i = 0; i < candidates.length; i++) {
        final c = candidates[i];
        final preview = c.content.length > 300
            ? c.content.substring(0, 300)
            : c.content;
        candidateSummaries.add({
          'index': i,
          'name': c.name,
          'type': c.type.name,
          'file': c.filePath.split('/').last,
          'lines': '${c.startLine}-${c.endLine}',
          'preview': preview,
        });
      }

      final prompt =
          '''Given the user's search query and a list of code chunks, rank the most relevant chunks and explain why they match.

User query: "$query"

Code chunks:
${jsonEncode(candidateSummaries)}

Respond with ONLY a JSON array of objects, each with:
- "index": the chunk index from the list above
- "score": relevance score from 0.0 to 1.0
- "explanation": brief explanation of why this chunk is relevant

Return only the top 10 most relevant chunks, sorted by score descending.
Respond with ONLY the JSON array, no other text.''';

      final response = await agentService.sendOneShot(
        prompt,
        systemPrompt:
            'You are a code search assistant. Respond only with valid JSON arrays. No markdown, no explanation outside the JSON.',
      );

      if (response == null) {
        // Fall back to keyword results
        final results = candidates.take(10).map((chunk) {
          return SemanticSearchResult(chunk: chunk, score: 0.5);
        }).toList();
        state = state.copyWith(isSearching: false, results: results);
        return;
      }

      // Parse AI response
      final results = _parseAiResponse(response, candidates);
      state = state.copyWith(isSearching: false, results: results);
    } catch (e) {
      Logger.error('Semantic search failed', e);
      state = state.copyWith(
        isSearching: false,
        error: 'Search failed: ${e.toString()}',
      );
    }
  }

  List<SemanticSearchResult> _parseAiResponse(
    String response,
    List<CodeChunk> candidates,
  ) {
    try {
      // Extract JSON array from response (handle markdown fences)
      String jsonStr = response.trim();
      if (jsonStr.startsWith('```')) {
        jsonStr = jsonStr.replaceFirst(RegExp(r'^```\w*\n?'), '');
        jsonStr = jsonStr.replaceFirst(RegExp(r'\n?```$'), '');
      }

      final decoded = jsonDecode(jsonStr) as List<dynamic>;
      final results = <SemanticSearchResult>[];

      for (final item in decoded) {
        final map = item as Map<String, dynamic>;
        final index = map['index'] as int? ?? -1;
        final score = (map['score'] as num?)?.toDouble() ?? 0.5;
        final explanation = map['explanation'] as String?;

        if (index >= 0 && index < candidates.length) {
          results.add(
            SemanticSearchResult(
              chunk: candidates[index],
              score: score.clamp(0.0, 1.0),
              explanation: explanation,
            ),
          );
        }
      }

      return results;
    } catch (e) {
      Logger.warning('Failed to parse AI ranking response', 'SemanticSearch');
      // Fall back to returning candidates with default scores
      return candidates.take(10).map((chunk) {
        return SemanticSearchResult(chunk: chunk, score: 0.5);
      }).toList();
    }
  }
}

final semanticSearchProvider =
    NotifierProvider<SemanticSearchNotifier, SemanticSearchState>(
      SemanticSearchNotifier.new,
    );
