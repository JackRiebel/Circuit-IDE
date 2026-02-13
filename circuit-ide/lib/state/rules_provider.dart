import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/context/rules_loader.dart';
import 'file_tree_provider.dart';

class RulesState {
  final List<ProjectRule> rules;
  final bool isLoading;
  final String? error;

  const RulesState({
    this.rules = const [],
    this.isLoading = false,
    this.error,
  });

  RulesState copyWith({
    List<ProjectRule>? rules,
    bool? isLoading,
    String? error,
  }) {
    return RulesState(
      rules: rules ?? this.rules,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class RulesNotifier extends Notifier<RulesState> {
  @override
  RulesState build() {
    // Auto-load when file tree changes
    ref.listen(fileTreeProvider, (prev, next) {
      if (next.rootPath != null && next.rootPath != prev?.rootPath) {
        loadRules();
      }
    });
    return const RulesState();
  }

  Future<void> loadRules() async {
    final workingDir = ref.read(fileTreeProvider).rootPath;
    if (workingDir == null) return;

    state = state.copyWith(isLoading: true);
    try {
      final rules = await RulesLoader.loadRules(workingDir);
      state = state.copyWith(rules: rules, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> saveRule(String name, String content) async {
    final workingDir = ref.read(fileTreeProvider).rootPath;
    if (workingDir == null) return;

    await RulesLoader.saveRule(workingDir, name, content);
    await loadRules();
  }

  Future<void> deleteRule(ProjectRule rule) async {
    await RulesLoader.deleteRule(rule.filePath);
    await loadRules();
  }
}

final rulesProvider =
    NotifierProvider<RulesNotifier, RulesState>(RulesNotifier.new);
