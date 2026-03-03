import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/context/flow_analyzer.dart';
import '../core/utils/logger.dart';
import 'editor_provider.dart';
import 'file_tree_provider.dart';

class FlowContextState {
  final FlowContext? context;
  final bool isLoading;

  const FlowContextState({this.context, this.isLoading = false});

  FlowContextState copyWith({FlowContext? context, bool? isLoading}) {
    return FlowContextState(
      context: context ?? this.context,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class FlowContextNotifier extends Notifier<FlowContextState> {
  @override
  FlowContextState build() {
    // Watch active file changes and re-analyze
    ref.listen(editorProvider, (prev, next) {
      final prevPath = prev?.activeTab?.filePath;
      final nextPath = next.activeTab?.filePath;
      if (nextPath != null && nextPath != prevPath) {
        analyze(nextPath);
      }
    });
    return const FlowContextState();
  }

  Future<void> analyze(String filePath) async {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (rootPath == null) return;

    state = state.copyWith(isLoading: true);

    try {
      final analyzer = FlowAnalyzer(rootPath: rootPath);
      final ctx = await analyzer.analyze(filePath);
      state = FlowContextState(context: ctx, isLoading: false);
    } catch (e) {
      Logger.error('Flow analysis failed', e);
      state = state.copyWith(isLoading: false);
    }
  }
}

final flowContextProvider =
    NotifierProvider<FlowContextNotifier, FlowContextState>(
  FlowContextNotifier.new,
);
