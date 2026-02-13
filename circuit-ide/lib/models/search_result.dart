class SearchResult {
  final String filePath;
  final String fileName;
  final int lineNumber;
  final String lineContent;
  final int matchStart;
  final int matchEnd;

  const SearchResult({
    required this.filePath,
    required this.fileName,
    required this.lineNumber,
    required this.lineContent,
    required this.matchStart,
    required this.matchEnd,
  });

  String get matchText => lineContent.substring(matchStart, matchEnd);
}

class SearchState {
  final String query;
  final bool isRegex;
  final bool caseSensitive;
  final bool wholeWord;
  final String includePattern;
  final String excludePattern;
  final List<SearchResult> results;
  final bool isSearching;
  final int totalMatches;
  final int filesSearched;

  const SearchState({
    this.query = '',
    this.isRegex = false,
    this.caseSensitive = false,
    this.wholeWord = false,
    this.includePattern = '',
    this.excludePattern = '',
    this.results = const [],
    this.isSearching = false,
    this.totalMatches = 0,
    this.filesSearched = 0,
  });

  SearchState copyWith({
    String? query,
    bool? isRegex,
    bool? caseSensitive,
    bool? wholeWord,
    String? includePattern,
    String? excludePattern,
    List<SearchResult>? results,
    bool? isSearching,
    int? totalMatches,
    int? filesSearched,
  }) {
    return SearchState(
      query: query ?? this.query,
      isRegex: isRegex ?? this.isRegex,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      wholeWord: wholeWord ?? this.wholeWord,
      includePattern: includePattern ?? this.includePattern,
      excludePattern: excludePattern ?? this.excludePattern,
      results: results ?? this.results,
      isSearching: isSearching ?? this.isSearching,
      totalMatches: totalMatches ?? this.totalMatches,
      filesSearched: filesSearched ?? this.filesSearched,
    );
  }
}
