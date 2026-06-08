enum ContextPackItemType {
  projectProfile,
  activeFile,
  selection,
  mentionedFile,
  gitDiff,
  diagnostics,
  terminal,
  rule,
  memory,
}

class ContextPackItem {
  final String id;
  final ContextPackItemType type;
  final String title;
  final String detail;
  final String? source;
  final int estimatedTokens;
  final bool removable;

  const ContextPackItem({
    required this.id,
    required this.type,
    required this.title,
    required this.detail,
    this.source,
    this.estimatedTokens = 0,
    this.removable = true,
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
      'estimatedTokens': estimatedTokens,
      'removable': removable,
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
        estimatedTokens: json['estimatedTokens'] as int? ?? 0,
        removable: json['removable'] as bool? ?? true,
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
  final List<String> removedItemIds;

  const ContextPack({
    required this.id,
    required this.projectKey,
    required this.createdAt,
    this.items = const [],
    this.removedItemIds = const [],
  });

  List<ContextPackItem> get visibleItems => items
      .where((item) => !removedItemIds.contains(item.id))
      .toList(growable: false);

  int get estimatedTokens =>
      visibleItems.fold<int>(0, (total, item) => total + item.estimatedTokens);

  ContextPack copyWith({
    List<ContextPackItem>? items,
    List<String>? removedItemIds,
  }) {
    return ContextPack(
      id: id,
      projectKey: projectKey,
      createdAt: createdAt,
      items: items ?? this.items,
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
        removedItemIds:
            (json['removedItemIds'] as List<dynamic>?)?.cast<String>() ??
            const [],
      );
    } catch (_) {
      return null;
    }
  }
}
