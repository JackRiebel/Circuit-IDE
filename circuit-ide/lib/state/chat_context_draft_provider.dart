import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/context_attachment.dart';
import '../services/file_indexer.dart';
import '../services/screenshot_context_attachment_builder.dart';
import 'ai_context_provider.dart';
import 'editor_provider.dart';
import 'file_tree_provider.dart';
import 'terminal_provider.dart';

class ChatContextDraftState {
  final List<ContextAttachment> pinnedAttachments;
  final List<ContextAttachment> userAttachments;
  final Set<String> suppressedPinnedIds;

  const ChatContextDraftState({
    this.pinnedAttachments = const [],
    this.userAttachments = const [],
    this.suppressedPinnedIds = const {},
  });

  List<ContextAttachment> get attachments => [
    ...pinnedAttachments,
    ...userAttachments,
  ];

  ChatContextDraftState copyWith({
    List<ContextAttachment>? pinnedAttachments,
    List<ContextAttachment>? userAttachments,
    Set<String>? suppressedPinnedIds,
  }) {
    return ChatContextDraftState(
      pinnedAttachments: pinnedAttachments ?? this.pinnedAttachments,
      userAttachments: userAttachments ?? this.userAttachments,
      suppressedPinnedIds: suppressedPinnedIds ?? this.suppressedPinnedIds,
    );
  }
}

class SlashCommandSpec {
  final String command;
  final String label;
  final String description;
  final ContextAttachmentType type;

  const SlashCommandSpec({
    required this.command,
    required this.label,
    required this.description,
    required this.type,
  });
}

class SlashParseResult {
  final String message;
  final List<ContextAttachment> attachments;

  const SlashParseResult({required this.message, required this.attachments});
}

class ChatContextDraftNotifier extends Notifier<ChatContextDraftState> {
  static const _uuid = Uuid();

  static const slashCommands = [
    SlashCommandSpec(
      command: '/file',
      label: 'Attach file',
      description: 'Attach a workspace file by relative path.',
      type: ContextAttachmentType.file,
    ),
    SlashCommandSpec(
      command: '/image',
      label: 'Attach image',
      description: 'Attach screenshot/image metadata by path.',
      type: ContextAttachmentType.image,
    ),
    SlashCommandSpec(
      command: '/screenshot',
      label: 'Attach screenshot',
      description: 'Attach screenshot metadata by path.',
      type: ContextAttachmentType.image,
    ),
    SlashCommandSpec(
      command: '/selection',
      label: 'Active selection',
      description: 'Attach the active editor context.',
      type: ContextAttachmentType.selection,
    ),
    SlashCommandSpec(
      command: '/terminal',
      label: 'Terminal output',
      description: 'Attach recent terminal output.',
      type: ContextAttachmentType.terminal,
    ),
    SlashCommandSpec(
      command: '/diff',
      label: 'Git diff',
      description: 'Tell the agent to inspect the working tree diff.',
      type: ContextAttachmentType.gitDiff,
    ),
    SlashCommandSpec(
      command: '/symbols',
      label: 'Symbols',
      description: 'Attach active file symbol context.',
      type: ContextAttachmentType.symbols,
    ),
    SlashCommandSpec(
      command: '/now',
      label: 'Current time',
      description: 'Attach the current timestamp.',
      type: ContextAttachmentType.note,
    ),
    SlashCommandSpec(
      command: '/diagnostics',
      label: 'Diagnostics',
      description: 'Attach diagnostics instruction.',
      type: ContextAttachmentType.diagnostics,
    ),
  ];

  @override
  ChatContextDraftState build() {
    ref.listen(aiContextProvider, (previous, next) => syncPinnedContext());
    ref.listen(editorProvider, (previous, next) => syncPinnedContext());
    return ChatContextDraftState(pinnedAttachments: _buildPinnedAttachments());
  }

  void syncPinnedContext() {
    state = state.copyWith(
      pinnedAttachments: _buildPinnedAttachments(state.suppressedPinnedIds),
    );
  }

  void addAttachment(ContextAttachment attachment) {
    final attachments = [
      ...state.userAttachments.where((item) => item.id != attachment.id),
      attachment,
    ];
    state = state.copyWith(userAttachments: attachments);
  }

  void addMention(IndexedFile file) {
    addAttachment(
      ContextAttachment(
        id: 'mention:${file.relativePath}',
        type: ContextAttachmentType.file,
        label: file.fileName,
        path: file.relativePath,
        content: 'Read this file if needed before making changes.',
        createdAt: DateTime.now(),
      ),
    );
  }

  void toggleActiveFileAttachment() {
    final activeTab = ref.read(editorProvider).activeTab;
    if (activeTab == null || activeTab.filePath.startsWith('circuit://')) {
      return;
    }
    final id = 'active-file:${activeTab.filePath}';
    if (state.userAttachments.any((item) => item.id == id)) {
      removeAttachment(id);
      return;
    }
    addAttachment(
      ContextAttachment(
        id: id,
        type: ContextAttachmentType.file,
        label: activeTab.fileName,
        path: activeTab.filePath,
        content: 'The user explicitly attached the active editor file.',
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<SlashParseResult> parseSlashCommands(String text) async {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    final activeTab = ref.read(editorProvider).activeTab;
    final terminalOutput = ref
        .read(terminalProvider.notifier)
        .getActiveTerminalOutput(lines: 80)
        .trim();
    final attachments = <ContextAttachment>[];
    final messageLines = <String>[];

    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (!line.startsWith('/')) {
        messageLines.add(rawLine);
        continue;
      }

      final parts = line.split(RegExp(r'\s+'));
      final command = parts.first.toLowerCase();
      final arg = parts.length > 1 ? parts.sublist(1).join(' ') : '';

      switch (command) {
        case '/now':
          attachments.add(
            _note('Current date', DateTime.now().toIso8601String()),
          );
          break;
        case '/terminal':
          if (terminalOutput.isNotEmpty) {
            attachments.add(
              _attachment(
                ContextAttachmentType.terminal,
                'Recent terminal',
                '```\n$terminalOutput\n```',
              ),
            );
          }
          break;
        case '/selection':
        case '/symbols':
          if (activeTab != null &&
              !activeTab.filePath.startsWith('circuit://')) {
            attachments.add(
              ContextAttachment(
                id: _uuid.v4(),
                type: command == '/symbols'
                    ? ContextAttachmentType.symbols
                    : ContextAttachmentType.selection,
                label: activeTab.fileName,
                path: activeTab.filePath,
                content: command == '/symbols'
                    ? 'Use symbols from this active file as structural context.'
                    : 'Use the current active editor context.',
                createdAt: DateTime.now(),
              ),
            );
          }
          break;
        case '/file':
          final attachment = await _fileAttachment(rootPath, arg);
          if (attachment != null) attachments.add(attachment);
          break;
        case '/image':
        case '/screenshot':
          final attachment = await _imageAttachment(rootPath, arg);
          if (attachment != null) attachments.add(attachment);
          break;
        case '/diff':
          attachments.add(
            _attachment(
              ContextAttachmentType.gitDiff,
              'Git diff',
              'Inspect the current working tree diff before answering.',
            ),
          );
          break;
        case '/diagnostics':
          attachments.add(
            _attachment(
              ContextAttachmentType.diagnostics,
              'Diagnostics',
              'Use available analyzer/test/linter diagnostics if relevant.',
            ),
          );
          break;
        default:
          messageLines.add(rawLine);
      }
    }

    return SlashParseResult(
      message: messageLines.join('\n').trim(),
      attachments: attachments,
    );
  }

  void removeAttachment(String id) {
    final isPinned = state.pinnedAttachments.any((item) => item.id == id);
    state = state.copyWith(
      userAttachments: state.userAttachments
          .where((item) => item.id != id)
          .toList(),
      suppressedPinnedIds: isPinned
          ? {...state.suppressedPinnedIds, id}
          : state.suppressedPinnedIds,
    );
    if (isPinned) syncPinnedContext();
  }

  void clearAfterSend() {
    state = ChatContextDraftState(pinnedAttachments: _buildPinnedAttachments());
  }

  List<ContextAttachment> _buildPinnedAttachments([
    Set<String> suppressedPinnedIds = const {},
  ]) {
    final contextState = ref.read(aiContextProvider);
    final activeTab = ref.read(editorProvider).activeTab;
    final terminalOutput = ref
        .read(terminalProvider.notifier)
        .getActiveTerminalOutput(lines: 60)
        .trim();
    final attachments = <ContextAttachment>[];

    if (contextState.includeActiveFile &&
        activeTab != null &&
        !activeTab.filePath.startsWith('circuit://')) {
      attachments.add(
        ContextAttachment(
          id: 'pinned-active-file:${activeTab.filePath}',
          type: ContextAttachmentType.file,
          label: activeTab.fileName,
          path: activeTab.filePath,
          content: 'The active editor file should be considered relevant.',
          createdAt: DateTime.now(),
        ),
      );
    }
    if (contextState.includeTerminalOutput && terminalOutput.isNotEmpty) {
      attachments.add(
        ContextAttachment(
          id: 'pinned-terminal',
          type: ContextAttachmentType.terminal,
          label: 'Recent terminal',
          content: '```\n$terminalOutput\n```',
          createdAt: DateTime.now(),
        ),
      );
    }
    if (contextState.includeGitDiff) {
      attachments.add(
        ContextAttachment(
          id: 'pinned-git-diff',
          type: ContextAttachmentType.gitDiff,
          label: 'Git diff',
          content: 'Inspect the current working tree diff before answering.',
          createdAt: DateTime.now(),
        ),
      );
    }

    return attachments
        .where((attachment) => !suppressedPinnedIds.contains(attachment.id))
        .toList();
  }

  Future<ContextAttachment?> _fileAttachment(
    String? rootPath,
    String relativePath,
  ) async {
    if (rootPath == null || relativePath.isEmpty) return null;
    final safePath = p.normalize(p.join(rootPath, relativePath));
    if (!p.isWithin(rootPath, safePath) || !await File(safePath).exists()) {
      return null;
    }
    final content = await File(safePath).readAsString();
    return ContextAttachment(
      id: 'slash-file:$relativePath',
      type: ContextAttachmentType.file,
      label: p.basename(safePath),
      path: safePath,
      content: '```\n${_truncate(content, 12000)}\n```',
      createdAt: DateTime.now(),
    );
  }

  Future<ContextAttachment?> _imageAttachment(
    String? rootPath,
    String rawPath,
  ) async {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      return ContextAttachment(
        id: _uuid.v4(),
        type: ContextAttachmentType.image,
        label: 'Missing image path',
        content:
            'The /image command needs a PNG, JPG, GIF, or WebP path. Example: /image screenshots/home.png',
        resolutionStatus: ContextAttachmentResolutionStatus.missing,
        estimatedTokens: 24,
        metadata: const {
          'artifactRole': 'visual_evidence',
          'visionInputStatus': 'missing_path',
        },
        createdAt: DateTime.now(),
      );
    }
    final imagePath = p.isAbsolute(trimmed)
        ? p.normalize(trimmed)
        : rootPath == null
        ? p.normalize(trimmed)
        : p.normalize(p.join(rootPath, trimmed));
    return const ScreenshotContextAttachmentBuilder().build(imagePath);
  }

  ContextAttachment _attachment(
    ContextAttachmentType type,
    String label,
    String content,
  ) {
    return ContextAttachment(
      id: _uuid.v4(),
      type: type,
      label: label,
      content: content,
      createdAt: DateTime.now(),
    );
  }

  ContextAttachment _note(String label, String content) {
    return _attachment(ContextAttachmentType.note, label, content);
  }

  static String _truncate(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}\n... truncated ...';
  }
}

final chatContextDraftProvider =
    NotifierProvider<ChatContextDraftNotifier, ChatContextDraftState>(
      ChatContextDraftNotifier.new,
    );
