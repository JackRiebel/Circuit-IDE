enum ContextPackItemType {
  projectProfile,
  activeFile,
  selection,
  mentionedFile,
  gitDiff,
  diagnostics,
  terminal,
  instruction,
  rule,
  memory,
}

enum ContextPackSourceKind {
  projectProfile,
  editor,
  git,
  terminal,
  instructionFile,
  circuitRule,
  memory,
  packageScript,
  diagnostics,
  sourceArtifact,
}

class ContextPackItem {
  final String id;
  final ContextPackItemType type;
  final String title;
  final String detail;
  final String? source;
  final ContextPackSourceKind sourceKind;
  final int estimatedTokens;
  final bool removable;
  final bool includedByDefault;
  final int? retrievalScore;
  final String? retrievalReason;

  const ContextPackItem({
    required this.id,
    required this.type,
    required this.title,
    required this.detail,
    this.source,
    this.sourceKind = ContextPackSourceKind.projectProfile,
    this.estimatedTokens = 0,
    this.removable = true,
    this.includedByDefault = true,
    this.retrievalScore,
    this.retrievalReason,
  });

  String get promptBlock {
    final sourceLabel = source == null ? '' : ' ($source)';
    return '[${type.name}: $title$sourceLabel]\n$detail';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'detail': detail,
      'source': source,
      'sourceKind': sourceKind.name,
      'estimatedTokens': estimatedTokens,
      'removable': removable,
      'includedByDefault': includedByDefault,
      'retrievalScore': retrievalScore,
      'retrievalReason': retrievalReason,
    };
  }

  static ContextPackItem? fromJson(Map<String, dynamic> json) {
    try {
      return ContextPackItem(
        id: json['id'] as String,
        type: ContextPackItemType.values.firstWhere(
          (value) => value.name == json['type'],
          orElse: () => ContextPackItemType.projectProfile,
        ),
        title: json['title'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        source: json['source'] as String?,
        sourceKind: ContextPackSourceKind.values.firstWhere(
          (value) => value.name == json['sourceKind'],
          orElse: () => ContextPackSourceKind.projectProfile,
        ),
        estimatedTokens: json['estimatedTokens'] as int? ?? 0,
        removable: json['removable'] as bool? ?? true,
        includedByDefault: json['includedByDefault'] as bool? ?? true,
        retrievalScore: json['retrievalScore'] as int?,
        retrievalReason: json['retrievalReason'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

class ContextPackBudget {
  final int maxTokens;
  final int reservedForResponse;

  const ContextPackBudget({
    required this.maxTokens,
    this.reservedForResponse = 4096,
  });

  int get availableForContext =>
      (maxTokens - reservedForResponse).clamp(0, maxTokens);
}

class ContextPackWarning {
  final String message;
  final String? itemId;

  const ContextPackWarning({required this.message, this.itemId});

  Map<String, dynamic> toJson() => {'message': message, 'itemId': itemId};

  static ContextPackWarning fromJson(Map<String, dynamic> json) {
    return ContextPackWarning(
      message: json['message'] as String? ?? '',
      itemId: json['itemId'] as String?,
    );
  }
}

class ContextPackSource {
  final ContextPackSourceKind kind;
  final String label;
  final String? path;

  const ContextPackSource({required this.kind, required this.label, this.path});
}

class ContextCandidate {
  final String id;
  final String title;
  final String? path;
  final ContextPackSourceKind sourceKind;
  final int score;
  final int estimatedTokens;
  final bool included;
  final String reason;

  const ContextCandidate({
    required this.id,
    required this.title,
    this.path,
    required this.sourceKind,
    required this.score,
    required this.estimatedTokens,
    required this.included,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'path': path,
    'sourceKind': sourceKind.name,
    'score': score,
    'estimatedTokens': estimatedTokens,
    'included': included,
    'reason': reason,
  };

  static ContextCandidate fromJson(Map<String, dynamic> json) {
    return ContextCandidate(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      path: json['path'] as String?,
      sourceKind: ContextPackSourceKind.values.firstWhere(
        (value) => value.name == json['sourceKind'],
        orElse: () => ContextPackSourceKind.projectProfile,
      ),
      score: json['score'] as int? ?? 0,
      estimatedTokens: json['estimatedTokens'] as int? ?? 0,
      included: json['included'] as bool? ?? false,
      reason: json['reason'] as String? ?? '',
    );
  }
}

class ContextBudgetReport {
  final int maxTokens;
  final int reservedForResponse;
  final int availableForContext;
  final int usedTokens;

  const ContextBudgetReport({
    required this.maxTokens,
    required this.reservedForResponse,
    required this.availableForContext,
    required this.usedTokens,
  });

  bool get exceeded => usedTokens > availableForContext;

  Map<String, dynamic> toJson() => {
    'maxTokens': maxTokens,
    'reservedForResponse': reservedForResponse,
    'availableForContext': availableForContext,
    'usedTokens': usedTokens,
    'exceeded': exceeded,
  };

  static ContextBudgetReport fromJson(Map<String, dynamic>? json) {
    return ContextBudgetReport(
      maxTokens: json?['maxTokens'] as int? ?? 0,
      reservedForResponse: json?['reservedForResponse'] as int? ?? 0,
      availableForContext: json?['availableForContext'] as int? ?? 0,
      usedTokens: json?['usedTokens'] as int? ?? 0,
    );
  }
}

class ContextRetrievalResult {
  final List<ContextCandidate> rankedCandidates;
  final ContextBudgetReport budget;
  final List<ContextPackWarning> warnings;

  const ContextRetrievalResult({
    required this.rankedCandidates,
    required this.budget,
    this.warnings = const [],
  });

  List<ContextCandidate> get includedCandidates =>
      rankedCandidates.where((candidate) => candidate.included).toList();

  List<ContextCandidate> get omittedCandidates =>
      rankedCandidates.where((candidate) => !candidate.included).toList();

  Map<String, dynamic> toJson() => {
    'rankedCandidates': rankedCandidates
        .map((candidate) => candidate.toJson())
        .toList(),
    'budget': budget.toJson(),
    'warnings': warnings.map((warning) => warning.toJson()).toList(),
  };

  static ContextRetrievalResult? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    try {
      return ContextRetrievalResult(
        rankedCandidates:
            (json['rankedCandidates'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(ContextCandidate.fromJson)
                .toList(),
        budget: ContextBudgetReport.fromJson(
          json['budget'] as Map<String, dynamic>?,
        ),
        warnings: (json['warnings'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ContextPackWarning.fromJson)
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }
}

class ContextPack {
  final String id;
  final String projectKey;
  final DateTime createdAt;
  final List<ContextPackItem> items;
  final List<ContextPackItem> instructionItems;
  final List<String> removedItemIds;
  final ContextRetrievalResult? retrievalResult;

  const ContextPack({
    required this.id,
    required this.projectKey,
    required this.createdAt,
    this.items = const [],
    this.instructionItems = const [],
    this.removedItemIds = const [],
    this.retrievalResult,
  });

  List<ContextPackItem> get allItems => [...items, ...instructionItems];

  List<ContextPackItem> get visibleItems => allItems
      .where((item) => !removedItemIds.contains(item.id))
      .toList(growable: false);

  int get estimatedTokens =>
      visibleItems.fold<int>(0, (total, item) => total + item.estimatedTokens);

  ContextPack copyWith({
    List<ContextPackItem>? items,
    List<ContextPackItem>? instructionItems,
    List<String>? removedItemIds,
    ContextRetrievalResult? retrievalResult,
  }) {
    return ContextPack(
      id: id,
      projectKey: projectKey,
      createdAt: createdAt,
      items: items ?? this.items,
      instructionItems: instructionItems ?? this.instructionItems,
      removedItemIds: removedItemIds ?? this.removedItemIds,
      retrievalResult: retrievalResult ?? this.retrievalResult,
    );
  }

  String serializePrompt() {
    if (visibleItems.isEmpty) return '';
    return [
      'Visible coding context pack:',
      for (final item in visibleItems) item.promptBlock,
    ].join('\n\n');
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'projectKey': projectKey,
      'createdAt': createdAt.toIso8601String(),
      'items': items.map((item) => item.toJson()).toList(),
      'instructionItems': instructionItems
          .map((item) => item.toJson())
          .toList(),
      'removedItemIds': removedItemIds,
      'retrievalResult': retrievalResult?.toJson(),
    };
  }

  static ContextPack? fromJson(Map<String, dynamic> json) {
    try {
      return ContextPack(
        id: json['id'] as String,
        projectKey: json['projectKey'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        items: (json['items'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ContextPackItem.fromJson)
            .nonNulls
            .toList(),
        instructionItems: (json['instructionItems'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ContextPackItem.fromJson)
            .nonNulls
            .toList(),
        removedItemIds:
            (json['removedItemIds'] as List<dynamic>?)?.cast<String>() ??
            const [],
        retrievalResult: ContextRetrievalResult.fromJson(
          json['retrievalResult'] as Map<String, dynamic>?,
        ),
      );
    } catch (_) {
      return null;
    }
  }
}
