import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/context/memories_loader.dart';
import '../core/utils/logger.dart';
import 'connection_provider.dart';
import 'file_tree_provider.dart';

class MemoriesState {
  final List<Memory> memories;
  final bool isLoading;
  final String? error;

  const MemoriesState({
    this.memories = const [],
    this.isLoading = false,
    this.error,
  });

  MemoriesState copyWith({
    List<Memory>? memories,
    bool? isLoading,
    String? error,
  }) {
    return MemoriesState(
      memories: memories ?? this.memories,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  List<Memory> get projectMemories =>
      memories.where((m) => !m.isGlobal).toList();

  List<Memory> get globalMemories =>
      memories.where((m) => m.isGlobal).toList();
}

class MemoriesNotifier extends Notifier<MemoriesState> {
  @override
  MemoriesState build() {
    ref.listen(fileTreeProvider, (prev, next) {
      if (next.rootPath != null && next.rootPath != prev?.rootPath) {
        loadMemories();
      }
    });
    return const MemoriesState();
  }

  Future<void> loadMemories() async {
    state = state.copyWith(isLoading: true);
    try {
      final workingDir = ref.read(fileTreeProvider).rootPath;
      final projectMemories = workingDir != null
          ? await MemoriesLoader.loadMemories(workingDir)
          : <Memory>[];
      final globalMemories = await MemoriesLoader.loadGlobalMemories();
      state = state.copyWith(
        memories: [...globalMemories, ...projectMemories],
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> saveMemory(
    String name,
    String content, {
    bool global = false,
  }) async {
    final workingDir = ref.read(fileTreeProvider).rootPath;
    if (workingDir == null && !global) return;

    await MemoriesLoader.saveMemory(
      workingDir ?? '',
      name,
      content,
      global: global,
    );
    await loadMemories();
  }

  Future<void> deleteMemory(Memory memory) async {
    await MemoriesLoader.deleteMemory(memory.filePath);
    await loadMemories();
  }

  /// Use AI to extract learnable patterns from a conversation turn.
  Future<void> extractFromConversation(
    String lastUserMsg,
    String lastAssistantMsg,
  ) async {
    final service = ref.read(agentServiceProvider);
    if (!service.isConnected) return;

    final workingDir = ref.read(fileTreeProvider).rootPath;
    if (workingDir == null) return;

    try {
      final prompt = '''Analyze this conversation turn and extract any learnable user preferences, project patterns, or coding conventions that should be remembered for future sessions.

User message:
$lastUserMsg

Assistant response:
$lastAssistantMsg

If there are learnable patterns (coding style preferences, naming conventions, architectural decisions, tool preferences, etc.), respond with EXACTLY this format:
MEMORY_NAME: <short-kebab-case-name>
MEMORY_CONTENT: <1-3 lines describing the learned pattern>

If there is nothing worth remembering, respond with exactly: NONE''';

      final response = await service.sendOneShot(prompt);
      if (response == null || response.trim() == 'NONE') return;

      final nameMatch =
          RegExp(r'MEMORY_NAME:\s*(.+)').firstMatch(response);
      final contentMatch =
          RegExp(r'MEMORY_CONTENT:\s*([\s\S]+)', multiLine: true)
              .firstMatch(response);

      if (nameMatch != null && contentMatch != null) {
        final name = nameMatch
            .group(1)!
            .trim()
            .replaceAll(RegExp(r'[^\w\-]'), '-')
            .toLowerCase();
        final content = contentMatch.group(1)!.trim();

        if (name.isNotEmpty && content.isNotEmpty) {
          await MemoriesLoader.saveMemory(workingDir, name, content);
          await loadMemories();
          Logger.info('Auto-extracted memory: $name', 'Memories');
        }
      }
    } catch (e) {
      Logger.warning('Memory extraction failed: $e', 'Memories');
    }
  }
}

final memoriesProvider =
    NotifierProvider<MemoriesNotifier, MemoriesState>(MemoriesNotifier.new);
