import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../enums/message_role.dart';
import '../../models/agent_preflight.dart';
import '../../models/agent_request.dart';
import '../../models/context_attachment.dart';
import '../../models/context_pack.dart';
import '../../models/studio_shell.dart';
import '../../models/studio_thread.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/agent_request_provider.dart';
import '../../state/chat_provider.dart';
import '../../state/context_pack_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';

enum StudioSendStatus { sent, blocked, failed, completed }

class StudioSendResult {
  final StudioSendStatus status;
  final String? requestId;
  final String? threadId;
  final String? taskId;
  final AgentPreflightResult? preflight;
  final StudioContextSummary? contextSummary;
  final String? error;

  const StudioSendResult._(
    this.status, {
    this.requestId,
    this.threadId,
    this.taskId,
    this.preflight,
    this.contextSummary,
    this.error,
  });

  const StudioSendResult.sent({
    String? requestId,
    String? threadId,
    String? taskId,
    StudioContextSummary? contextSummary,
  }) : this._(
         StudioSendStatus.sent,
         requestId: requestId,
         threadId: threadId,
         taskId: taskId,
         contextSummary: contextSummary,
       );

  const StudioSendResult.blocked(
    String message, {
    String? requestId,
    String? threadId,
    String? taskId,
    AgentPreflightResult? preflight,
    StudioContextSummary? contextSummary,
  }) : this._(
         StudioSendStatus.blocked,
         requestId: requestId,
         threadId: threadId,
         taskId: taskId,
         preflight: preflight,
         contextSummary: contextSummary,
         error: message,
       );

  const StudioSendResult.failed(
    String message, {
    String? requestId,
    String? threadId,
    String? taskId,
    StudioContextSummary? contextSummary,
  }) : this._(
         StudioSendStatus.failed,
         requestId: requestId,
         threadId: threadId,
         taskId: taskId,
         contextSummary: contextSummary,
         error: message,
       );

  const StudioSendResult.completed({
    String? requestId,
    String? threadId,
    String? taskId,
    StudioContextSummary? contextSummary,
  }) : this._(
         StudioSendStatus.completed,
         requestId: requestId,
         threadId: threadId,
         taskId: taskId,
         contextSummary: contextSummary,
       );
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
  final rootPath = ref.read(fileTreeProvider).rootPath;
  final promptMode = ref.read(studioShellProvider).promptMode;
  final model = ref.read(settingsProvider).ciscoModel;
  final payload = buildStudioContextPayload(ref, text);
  final thread = ref
      .read(studioThreadProvider.notifier)
      .ensureThread(taskId: taskId, title: text, model: model);
  ref
      .read(studioThreadProvider.notifier)
      .markPhase(
        thread.id,
        status: StudioThreadStatus.buildingContext,
        phase: StudioSendPhase.buildingContext,
        model: model,
        contextSummary: payload.summary,
      );
  ref.read(studioThreadProvider.notifier).appendUserMessage(thread.id, text);

  if (rootPath == null && promptMode.agentProfile != null) {
    const message =
        'Choose a project folder before using Code, Fix, or Review mode.';
    ref.read(studioThreadProvider.notifier).block(thread.id, message);
    if (finishTask && taskId != null) {
      ref.read(agentWorkspaceProvider.notifier).failTask(taskId, message);
    }
    return StudioSendResult.blocked(
      message,
      threadId: thread.id,
      taskId: taskId,
      contextSummary: payload.summary,
    );
  }

  ref
      .read(studioThreadProvider.notifier)
      .markPhase(
        thread.id,
        status: StudioThreadStatus.preflighting,
        phase: StudioSendPhase.preflighting,
        model: model,
        contextSummary: payload.summary,
      );
  await ref
      .read(chatProvider.notifier)
      .sendMessage(text, attachments: payload.attachments);

  final chat = ref.read(chatProvider);
  final request = ref.read(agentRequestProvider)[AgentRequestLane.chat];
  final requestId = request?.requestId;
  final assistantMessages = chat.messages
      .skip(beforeSend.messages.length)
      .where((message) => message.role == MessageRole.assistant)
      .toList();
  ref
      .read(studioThreadProvider.notifier)
      .appendChatMessages(thread.id, assistantMessages);
  ref
      .read(studioThreadProvider.notifier)
      .updateTokenUsage(
        thread.id,
        chat.lastTokenUsage.isNotEmpty ? chat.lastTokenUsage : chat.tokenUsage,
      );
  final preflight = chat.preflight;
  if (preflight != null && !preflight.canSend) {
    final message =
        preflight.primaryIssue?.message ?? 'Circuit AI is not ready.';
    ref
        .read(studioThreadProvider.notifier)
        .block(thread.id, message, preflight: preflight);
    if (finishTask && taskId != null) {
      ref.read(agentWorkspaceProvider.notifier).failTask(taskId, message);
    }
    return StudioSendResult.blocked(
      message,
      requestId: requestId,
      threadId: thread.id,
      taskId: taskId,
      preflight: preflight,
      contextSummary: payload.summary,
    );
  }
  if (chat.error != null) {
    ref.read(studioThreadProvider.notifier).fail(thread.id, chat.error!);
    if (finishTask && taskId != null) {
      ref.read(agentWorkspaceProvider.notifier).failTask(taskId, chat.error!);
    }
    return StudioSendResult.failed(
      chat.error!,
      requestId: requestId,
      threadId: thread.id,
      taskId: taskId,
      contextSummary: payload.summary,
    );
  }
  if (chat.isProcessing ||
      chat.isStreaming ||
      chat.pendingConfirmation != null) {
    ref
        .read(studioThreadProvider.notifier)
        .markPhase(
          thread.id,
          status: chat.pendingConfirmation == null
              ? StudioThreadStatus.streaming
              : StudioThreadStatus.waitingForApproval,
          phase: chat.pendingConfirmation == null
              ? StudioSendPhase.streaming
              : StudioSendPhase.waitingForApproval,
          requestId: requestId,
          model: model,
          contextSummary: payload.summary,
          streamingContent: chat.streamingContent,
        );
    if (chat.pendingConfirmation != null && taskId != null) {
      ref.read(agentWorkspaceProvider.notifier).markWaitingForApproval(taskId);
    }
    return StudioSendResult.sent(
      requestId: requestId,
      threadId: thread.id,
      taskId: taskId,
      contextSummary: payload.summary,
    );
  }
  if (finishTask && taskId != null) {
    ref
        .read(agentWorkspaceProvider.notifier)
        .completeTask(taskId, result: _lastAssistantPreview(chat));
  }
  ref
      .read(studioThreadProvider.notifier)
      .complete(
        thread.id,
        tokenUsage: chat.lastTokenUsage.isNotEmpty
            ? chat.lastTokenUsage
            : chat.tokenUsage,
      );
  return StudioSendResult.completed(
    requestId: requestId,
    threadId: thread.id,
    taskId: taskId,
    contextSummary: payload.summary,
  );
}

class StudioContextPayload {
  final List<ContextAttachment> attachments;
  final StudioContextSummary summary;

  const StudioContextPayload({
    required this.attachments,
    required this.summary,
  });
}

StudioContextPayload buildStudioContextPayload(WidgetRef ref, String prompt) {
  final rootPath = ref.read(fileTreeProvider).rootPath;
  final contextPack = ref
      .read(contextPackProvider.notifier)
      .buildForCodingTask(prompt: prompt);
  final attachment = _buildStudioContextAttachment(rootPath, contextPack);
  return StudioContextPayload(
    attachments: [attachment],
    summary: _buildContextSummary(rootPath, contextPack, attachment),
  );
}

List<ContextAttachment> buildStudioContextAttachments(
  WidgetRef ref,
  String prompt,
) {
  return buildStudioContextPayload(ref, prompt).attachments;
}

ContextAttachment _buildStudioContextAttachment(
  String? rootPath,
  ContextPack contextPack,
) {
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

  return ContextAttachment(
    id: 'studio-project-context-${contextPack.id}',
    type: ContextAttachmentType.note,
    label: 'Project directory context',
    path: rootPath,
    content: content,
    resolutionStatus: ContextAttachmentResolutionStatus.resolved,
    estimatedTokens: (content.length / 4).ceil(),
    createdAt: DateTime.now(),
  );
}

StudioContextSummary _buildContextSummary(
  String? rootPath,
  ContextPack contextPack,
  ContextAttachment attachment,
) {
  final files = contextPack.visibleItems
      .where(
        (item) =>
            item.type == ContextPackItemType.activeFile ||
            item.type == ContextPackItemType.selection ||
            item.type == ContextPackItemType.mentionedFile,
      )
      .map((item) => item.source ?? item.title)
      .where((value) => value.trim().isNotEmpty)
      .toSet()
      .toList();
  return StudioContextSummary(
    rootPath: rootPath,
    projectLabel: rootPath == null
        ? 'No project selected'
        : p.basename(rootPath),
    includedItemCount: contextPack.visibleItems.length,
    estimatedTokens: attachment.estimatedTokens,
    selectedFiles: files,
    includesGit: contextPack.visibleItems.any(
      (item) => item.type == ContextPackItemType.gitDiff,
    ),
    includesTerminal: contextPack.visibleItems.any(
      (item) => item.type == ContextPackItemType.terminal,
    ),
    warnings: rootPath == null
        ? const ['chat only until a project is selected']
        : const [],
  );
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
