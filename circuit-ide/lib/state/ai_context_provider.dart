import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiContextState {
  final bool includeLsdfIndex;
  final bool includeActiveFile;
  final bool includeTerminalOutput;
  final bool includeGitDiff;

  const AiContextState({
    this.includeLsdfIndex = true,
    this.includeActiveFile = true,
    this.includeTerminalOutput = false,
    this.includeGitDiff = false,
  });

  AiContextState copyWith({
    bool? includeLsdfIndex,
    bool? includeActiveFile,
    bool? includeTerminalOutput,
    bool? includeGitDiff,
  }) {
    return AiContextState(
      includeLsdfIndex: includeLsdfIndex ?? this.includeLsdfIndex,
      includeActiveFile: includeActiveFile ?? this.includeActiveFile,
      includeTerminalOutput:
          includeTerminalOutput ?? this.includeTerminalOutput,
      includeGitDiff: includeGitDiff ?? this.includeGitDiff,
    );
  }
}

class AiContextNotifier extends Notifier<AiContextState> {
  @override
  AiContextState build() => const AiContextState();

  void toggleLsdfIndex() {
    state = state.copyWith(includeLsdfIndex: !state.includeLsdfIndex);
  }

  void toggleActiveFile() {
    state = state.copyWith(includeActiveFile: !state.includeActiveFile);
  }

  void toggleTerminalOutput() {
    state = state.copyWith(includeTerminalOutput: !state.includeTerminalOutput);
  }

  void toggleGitDiff() {
    state = state.copyWith(includeGitDiff: !state.includeGitDiff);
  }
}

final aiContextProvider = NotifierProvider<AiContextNotifier, AiContextState>(
  AiContextNotifier.new,
);
