import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/suggested_learning.dart';
import 'memories_provider.dart';
import 'rules_provider.dart';

const _uuid = Uuid();

class SuggestedLearningState {
  final List<SuggestedLearning> suggestions;
  final String? message;

  const SuggestedLearningState({this.suggestions = const [], this.message});

  List<SuggestedLearning> get pending => suggestions
      .where(
        (suggestion) => suggestion.status == SuggestedLearningStatus.pending,
      )
      .toList(growable: false);

  SuggestedLearningState copyWith({
    List<SuggestedLearning>? suggestions,
    Object? message = _sentinel,
  }) {
    return SuggestedLearningState(
      suggestions: suggestions ?? this.suggestions,
      message: identical(message, _sentinel)
          ? this.message
          : message as String?,
    );
  }
}

class SuggestedLearningController extends Notifier<SuggestedLearningState> {
  @override
  SuggestedLearningState build() => const SuggestedLearningState();

  SuggestedMemory suggestMemory({
    required String name,
    required String content,
    bool global = false,
  }) {
    final suggestion = SuggestedLearning(
      id: _uuid.v4().substring(0, 8),
      type: SuggestedLearningType.memory,
      name: name,
      content: content,
      global: global,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      suggestions: [suggestion, ...state.suggestions].take(20).toList(),
      message: 'Memory suggestion ready for review.',
    );
    return suggestion;
  }

  SuggestedRule suggestRule({
    required String name,
    required String content,
    List<String> patterns = const [],
  }) {
    final suggestion = SuggestedLearning(
      id: _uuid.v4().substring(0, 8),
      type: SuggestedLearningType.rule,
      name: name,
      content: content,
      patterns: patterns,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      suggestions: [suggestion, ...state.suggestions].take(20).toList(),
      message: 'Rule suggestion ready for review.',
    );
    return suggestion;
  }

  Future<void> approve(String id) async {
    final suggestion = state.suggestions
        .where((candidate) => candidate.id == id)
        .firstOrNull;
    if (suggestion == null) return;
    if (suggestion.type == SuggestedLearningType.memory) {
      await ref
          .read(memoriesProvider.notifier)
          .saveMemory(
            suggestion.name,
            suggestion.content,
            global: suggestion.global,
          );
    } else {
      await ref
          .read(rulesProvider.notifier)
          .saveRule(
            suggestion.name,
            suggestion.content,
            patterns: suggestion.patterns,
          );
    }
    _setStatus(id, SuggestedLearningStatus.approved);
  }

  void reject(String id) => _setStatus(id, SuggestedLearningStatus.rejected);

  void _setStatus(String id, SuggestedLearningStatus status) {
    state = state.copyWith(
      suggestions: [
        for (final suggestion in state.suggestions)
          suggestion.id == id
              ? suggestion.copyWith(status: status)
              : suggestion,
      ],
      message: status.name,
    );
  }
}

final suggestedLearningProvider =
    NotifierProvider<SuggestedLearningController, SuggestedLearningState>(
      SuggestedLearningController.new,
    );

const _sentinel = Object();
