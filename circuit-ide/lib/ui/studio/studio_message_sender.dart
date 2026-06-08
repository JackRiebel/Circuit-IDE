import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../enums/message_role.dart';
import '../../models/context_attachment.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/chat_provider.dart';
import '../../state/context_pack_provider.dart';
import '../../state/file_tree_provider.dart';

enum StudioSendStatus { sent, blocked, failed, completed }

class StudioSendResult {
  final StudioSendStatus status;
  final String? message;

  const StudioSendResult._(this.status, [this.message]);

  const StudioSendResult.sent() : this._(StudioSendStatus.sent);

  const StudioSendResult.blocked(String message)
    : this._(StudioSendStatus.blocked, message);

  const StudioSendResult.failed(String message)
    : this._(StudioSendStatus.failed, message);

  const StudioSendResult.completed() : this._(StudioSendStatus.completed);
}

Future<StudioSendResult> sendStudioMessage(
  WidgetRef ref,
  String text, {
  String? taskId,
  bool finishTask = false,
}) async {
  final beforeSend = ref.read(chatProvider);
  if (beforeSend.isProcessing) {
    return const StudioSendResult.sent();
  }
  final attachments = buildStudioContextAttachments(ref, text);
  await ref
      .read(chatProvider.notifier)
      .sendMessage(text, attachments: attachments);

  final chat = ref.read(chatProvider);
  final preflight = chat.preflight;
  if (preflight != null && !preflight.canSend) {
    final message =
        preflight.primaryIssue?.message ?? 'Circuit AI is not ready.';
    if (finishTask && taskId != null) {
      ref.read(agentWorkspaceProvider.notifier).failTask(taskId, message);
    }
    return StudioSendResult.blocked(message);
  }
  if (chat.error != null) {
    if (finishTask && taskId != null) {
      ref.read(agentWorkspaceProvider.notifier).failTask(taskId, chat.error!);
    }
    return StudioSendResult.failed(chat.error!);
  }
  if (chat.isProcessing ||
      chat.isStreaming ||
      chat.pendingConfirmation != null) {
    return const StudioSendResult.sent();
  }
  if (finishTask && taskId != null) {
    ref
        .read(agentWorkspaceProvider.notifier)
        .completeTask(taskId, result: _lastAssistantPreview(chat));
  }
  return const StudioSendResult.completed();
}

List<ContextAttachment> buildStudioContextAttachments(
  WidgetRef ref,
  String prompt,
) {
  final rootPath = ref.read(fileTreeProvider).rootPath;
  final contextPack = ref
      .read(contextPackProvider.notifier)
      .buildForCodingTask(prompt: prompt);
  final projectLabel = rootPath == null
      ? 'No project selected'
      : p.basename(rootPath);
  final content = [
    if (rootPath == null)
      'No project directory is selected. Ask the user to choose a project before reviewing or editing files.'
    else ...[
      'Open project directory: $rootPath',
      'Project name: $projectLabel',
      'Use this directory as the working root for all file reads, searches, commands, and edits.',
      'Do not assume a different repository unless the user explicitly asks.',
    ],
    contextPack.serializePrompt(),
  ].where((part) => part.trim().isNotEmpty).join('\n\n');

  return [
    ContextAttachment(
      id: 'studio-project-context-${contextPack.id}',
      type: ContextAttachmentType.note,
      label: 'Project directory context',
      path: rootPath,
      content: content,
      resolutionStatus: ContextAttachmentResolutionStatus.resolved,
      estimatedTokens: (content.length / 4).ceil(),
      createdAt: DateTime.now(),
    ),
  ];
}

String _lastAssistantPreview(ChatState chat) {
  final assistants = chat.messages
      .where((message) => message.role == MessageRole.assistant)
      .toList();
  if (assistants.isEmpty) return 'Circuit AI responded.';
  final normalized = assistants.last.content.trim().replaceAll(
    RegExp(r'\s+'),
    ' ',
  );
  if (normalized.isEmpty) return 'Circuit AI responded.';
  if (normalized.length <= 180) return normalized;
  return '${normalized.substring(0, 180)}...';
}
