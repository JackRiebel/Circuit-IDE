enum SuggestedLearningType { rule, memory }

enum SuggestedLearningStatus { pending, approved, rejected }

class SuggestedLearning {
  final String id;
  final SuggestedLearningType type;
  final SuggestedLearningStatus status;
  final String name;
  final String content;
  final List<String> patterns;
  final bool global;
  final DateTime createdAt;

  const SuggestedLearning({
    required this.id,
    required this.type,
    this.status = SuggestedLearningStatus.pending,
    required this.name,
    required this.content,
    this.patterns = const [],
    this.global = false,
    required this.createdAt,
  });

  SuggestedLearning copyWith({SuggestedLearningStatus? status}) {
    return SuggestedLearning(
      id: id,
      type: type,
      status: status ?? this.status,
      name: name,
      content: content,
      patterns: patterns,
      global: global,
      createdAt: createdAt,
    );
  }
}

typedef SuggestedRule = SuggestedLearning;
typedef SuggestedMemory = SuggestedLearning;
