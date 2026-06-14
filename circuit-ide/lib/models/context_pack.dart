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
}

class ContextPackSource {
  final ContextPackSourceKind kind;
  final String label;
  final String? path;

  const ContextPackSource({required this.kind, required this.label, this.path});
}

class ContextPack {
  final String id;
  final String projectKey;
  final DateTime createdAt;
  final List<ContextPackItem> items;
  final List<ContextPackItem> instructionItems;
  final List<String> removedItemIds;

  const ContextPack({
    required this.id,
    required this.projectKey,
    required this.createdAt,
    this.items = const [],
    this.instructionItems = const [],
    this.removedItemIds = const [],
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
  }) {
    return ContextPack(
      id: id,
      projectKey: projectKey,
      createdAt: createdAt,
      items: items ?? this.items,
      instructionItems: instructionItems ?? this.instructionItems,
      removedItemIds: removedItemIds ?? this.removedItemIds,
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
      );
    } catch (_) {
      return null;
    }
  }
}
