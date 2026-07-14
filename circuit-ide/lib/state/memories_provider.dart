import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/context/memories_loader.dart';
import '../core/utils/logger.dart';
import '../enums/message_role.dart';
import '../models/chat_message.dart';
import '../models/provider_lifecycle_event.dart';
import 'studio_provider_connection.dart';
import 'file_tree_provider.dart';
import 'settings_provider.dart';
import 'suggested_learning_provider.dart';

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

  List<Memory> get globalMemories => memories.where((m) => m.isGlobal).toList();
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
    MemoryProvenance provenance = MemoryProvenance.userAuthored,
    DateTime? createdAt,
    DateTime? lastUsedAt,
  }) async {
    final workingDir = ref.read(fileTreeProvider).rootPath;
    if (workingDir == null && !global) return;

    await MemoriesLoader.saveMemory(
      workingDir ?? '',
      name,
      content,
      global: global,
      provenance: provenance,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt,
    );
    await loadMemories();
  }

  Future<void> markUsed(Iterable<Memory> memories) async {
    final selected = memories.toList(growable: false);
    if (selected.isEmpty) return;
    final usedAt = DateTime.now().toUtc();
    try {
      await Future.wait(
        selected.map((memory) => MemoriesLoader.markUsed(memory, at: usedAt)),
      );
      if (!ref.mounted) return;
      final usedPaths = selected.map((memory) => memory.filePath).toSet();
      state = state.copyWith(
        memories: [
          for (final memory in state.memories)
            usedPaths.contains(memory.filePath)
                ? memory.copyWith(lastUsedAt: usedAt)
                : memory,
        ],
      );
    } catch (error) {
      Logger.warning('Could not record memory use: $error', 'Memories');
    }
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
    final provider = ref.read(studioAgentConnectionProvider).provider;
    if (provider == null || !provider.isConnected) return;

    final workingDir = ref.read(fileTreeProvider).rootPath;
    if (workingDir == null) return;
    if (containsSensitiveAutomaticLearningContent(lastUserMsg) ||
        containsSensitiveAutomaticLearningContent(lastAssistantMsg)) {
      Logger.info(
        'Skipped automatic memory suggestion because the turn may contain sensitive content.',
        'Memories',
      );
      return;
    }

    try {
      final prompt =
          '''Analyze this conversation turn and extract any learnable user preferences, project patterns, or coding conventions that should be remembered for future sessions.

User message:
$lastUserMsg

Assistant response:
$lastAssistantMsg

If there are learnable patterns (coding style preferences, naming conventions, architectural decisions, tool preferences, etc.), respond with EXACTLY this format:
MEMORY_NAME: <short-kebab-case-name>
MEMORY_CONTENT: <1-3 lines describing the learned pattern>

If there is nothing worth remembering, respond with exactly: NONE''';

      final response = await _sendProviderOneShot(prompt);
      if (response == null || response.trim() == 'NONE') return;

      final nameMatch = RegExp(r'MEMORY_NAME:\s*(.+)').firstMatch(response);
      final contentMatch = RegExp(
        r'MEMORY_CONTENT:\s*([\s\S]+)',
        multiLine: true,
      ).firstMatch(response);

      if (nameMatch != null && contentMatch != null) {
        final name = nameMatch
            .group(1)!
            .trim()
            .replaceAll(RegExp(r'[^\w\-]'), '-')
            .toLowerCase();
        final content = contentMatch.group(1)!.trim();

        if (name.isNotEmpty &&
            content.isNotEmpty &&
            !containsSensitiveAutomaticLearningContent(content)) {
          ref
              .read(suggestedLearningProvider.notifier)
              .suggestMemory(name: name, content: content);
          Logger.info('Suggested memory for review: $name', 'Memories');
        }
      }
    } catch (e) {
      Logger.warning('Memory extraction failed: $e', 'Memories');
    }
  }

  Future<String?> _sendProviderOneShot(String prompt) async {
    final provider = ref.read(studioAgentConnectionProvider).provider;
    if (provider == null || !provider.isConnected) return null;
    final content = StringBuffer();
    await for (final chunk in provider.chat(
      [
        ChatMessage(
          id: 'memory-extraction-${DateTime.now().microsecondsSinceEpoch}',
          role: MessageRole.user,
          content: prompt,
          timestamp: DateTime.now(),
        ),
      ],
      model: ref.read(settingsProvider).ciscoModel,
      tools: const [],
      systemPrompt:
          'Extract one concise memory only when it is clearly useful. Do not call tools.',
      temperature: 0,
      maxTokens: 512,
    )) {
      if (chunk.lifecycleKind == ProviderLifecycleEventKind.failed) {
        return null;
      }
      if (chunk.content != null) content.write(chunk.content);
      if (chunk.isDone) break;
    }
    final text = content.toString().trim();
    return text.isEmpty ? null : text;
  }
}

bool containsSensitiveAutomaticLearningContent(String value) {
  return RegExp(
    r'(?:\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|password|passwd|secret|authorization)\b|bearer\s+[a-z0-9._~+\-/=]{8,}|-----begin [a-z ]*private key-----|\b(?:sk-[a-z0-9_-]{8,}|gh[pousr]_[a-z0-9]{8,}|akia[0-9a-z]{12,})\b|\.env\b)',
    caseSensitive: false,
  ).hasMatch(value);
}

final memoriesProvider = NotifierProvider<MemoriesNotifier, MemoriesState>(
  MemoriesNotifier.new,
);
