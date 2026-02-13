enum ChunkType { function, classDecl, method, block, imports, topLevel }

class CodeChunk {
  final String id;
  final String filePath;
  final int startLine;
  final int endLine;
  final ChunkType type;
  final String name;
  final String content;
  final String language;

  const CodeChunk({
    required this.id,
    required this.filePath,
    required this.startLine,
    required this.endLine,
    required this.type,
    required this.name,
    required this.content,
    required this.language,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'startLine': startLine,
        'endLine': endLine,
        'type': type.name,
        'name': name,
        'content': content,
        'language': language,
      };

  factory CodeChunk.fromJson(Map<String, dynamic> json) => CodeChunk(
        id: json['id'] ?? '',
        filePath: json['filePath'] ?? '',
        startLine: json['startLine'] ?? 0,
        endLine: json['endLine'] ?? 0,
        type: ChunkType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => ChunkType.block,
        ),
        name: json['name'] ?? '',
        content: json['content'] ?? '',
        language: json['language'] ?? '',
      );
}

class SemanticSearchResult {
  final CodeChunk chunk;
  final double score;
  final String? explanation;

  const SemanticSearchResult({
    required this.chunk,
    required this.score,
    this.explanation,
  });
}

class SemanticSearchState {
  final String query;
  final List<SemanticSearchResult> results;
  final bool isSearching;
  final bool isIndexing;
  final int indexedFileCount;
  final int totalFileCount;
  final bool isSemanticMode;
  final String? error;

  const SemanticSearchState({
    this.query = '',
    this.results = const [],
    this.isSearching = false,
    this.isIndexing = false,
    this.indexedFileCount = 0,
    this.totalFileCount = 0,
    this.isSemanticMode = false,
    this.error,
  });

  SemanticSearchState copyWith({
    String? query,
    List<SemanticSearchResult>? results,
    bool? isSearching,
    bool? isIndexing,
    int? indexedFileCount,
    int? totalFileCount,
    bool? isSemanticMode,
    String? error,
  }) {
    return SemanticSearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isSearching: isSearching ?? this.isSearching,
      isIndexing: isIndexing ?? this.isIndexing,
      indexedFileCount: indexedFileCount ?? this.indexedFileCount,
      totalFileCount: totalFileCount ?? this.totalFileCount,
      isSemanticMode: isSemanticMode ?? this.isSemanticMode,
      error: error ?? this.error,
    );
  }
}
