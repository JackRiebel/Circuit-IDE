import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../agent/tools/tool_registry.dart';
import '../../models/agent_preflight.dart';
import '../../models/context_attachment.dart';
import '../../models/context_pack.dart';
import '../../models/specialist_agent.dart';
import '../../models/studio_shell.dart';
import '../../models/studio_thread.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/chat_provider.dart';
import '../../state/context_pack_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_project_creator.dart';
import '../../state/studio_request_lifecycle_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/studio_turn_provider.dart';
import '../../state/workspace_session_provider.dart';

const _uuid = Uuid();

enum StudioSendStatus { sent, blocked, failed, completed }

class StudioSendResult {
  final StudioSendStatus status;
  final String? requestId;
  final String? threadId;
  final String? taskId;
  final AgentPreflightResult? preflight;
  final StudioContextSummary? contextSummary;
  final String? error;
  final bool registeredRequest;
  final bool blockedByActiveRequest;

  const StudioSendResult._(
    this.status, {
    this.requestId,
    this.threadId,
    this.taskId,
    this.preflight,
    this.contextSummary,
    this.error,
    this.registeredRequest = false,
    this.blockedByActiveRequest = false,
  });

  const StudioSendResult.sent({
    String? requestId,
    String? threadId,
    String? taskId,
    StudioContextSummary? contextSummary,
    bool registeredRequest = false,
  }) : this._(
         StudioSendStatus.sent,
         requestId: requestId,
         threadId: threadId,
         taskId: taskId,
         contextSummary: contextSummary,
         registeredRequest: registeredRequest,
       );

  const StudioSendResult.blocked(
    String message, {
    String? requestId,
    String? threadId,
    String? taskId,
    AgentPreflightResult? preflight,
    StudioContextSummary? contextSummary,
    bool blockedByActiveRequest = false,
  }) : this._(
         StudioSendStatus.blocked,
         requestId: requestId,
         threadId: threadId,
         taskId: taskId,
         preflight: preflight,
         contextSummary: contextSummary,
         error: message,
         blockedByActiveRequest: blockedByActiveRequest,
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
    bool registeredRequest = false,
  }) : this._(
         StudioSendStatus.completed,
         requestId: requestId,
         threadId: threadId,
         taskId: taskId,
         contextSummary: contextSummary,
         registeredRequest: registeredRequest,
       );
}

Future<StudioSendResult> sendStudioMessage(
  WidgetRef ref,
  String text, {
  String? taskId,
  bool finishTask = false,
}) async {
  final beforeSend = ref.read(chatProvider);
  if (beforeSend.pendingConfirmation != null &&
      ref.read(chatProvider.notifier).handlePendingApprovalText(text)) {
    final thread = ref.read(studioThreadProvider).selectedThread;
    if (thread != null) {
      ref
          .read(studioThreadProvider.notifier)
          .markPhase(
            thread.id,
            status: StudioThreadStatus.runningCommand,
            phase: StudioSendPhase.runningCommand,
            requestId: thread.requestId,
            model: thread.model,
            contextSummary: thread.contextSummary,
          );
    }
    return StudioSendResult.sent(
      requestId: thread?.requestId,
      threadId: thread?.id,
      taskId: taskId,
      contextSummary: thread?.contextSummary,
      registeredRequest: true,
    );
  }
  ref.read(workspaceSessionProvider.notifier).syncFromCurrentWorkspace();
  final promptMode = ref.read(studioShellProvider).promptMode;
  final model = ref.read(settingsProvider).ciscoModel;
  var rootPath = ref.read(fileTreeProvider).rootPath;
  var workspace = ref.read(workspaceSessionProvider);
  if ((rootPath == null || !workspace.canCode) &&
      promptMode.agentProfile != null) {
    final path = await StudioProjectCreator.createProject(
      name: StudioProjectCreator.projectNameFromPrompt(text),
    );
    final openResult = await ref
        .read(workspaceSessionProvider.notifier)
        .openWorkspaceAndBindAgent(path);
    if (openResult.success) {
      ref.read(settingsProvider.notifier).addRecentProject(path);
      ref.read(studioShellProvider.notifier).openProject(path);
      rootPath = path;
      workspace = ref.read(workspaceSessionProvider);
    }
  }
  final payload = buildStudioContextPayload(ref, text);
  final thread = ref
      .read(studioThreadProvider.notifier)
      .ensureThread(taskId: taskId, title: text, model: model);
  final priorThreadMessages = thread.messages
      .map((message) => message.toChatMessage())
      .toList(growable: false);
  ref
      .read(studioThreadProvider.notifier)
      .markPhase(
        thread.id,
        status: StudioThreadStatus.buildingContext,
        phase: StudioSendPhase.buildingContext,
        model: model,
        contextSummary: payload.summary,
      );
  final userMessageId =
      ref
          .read(studioThreadProvider.notifier)
          .appendUserMessage(thread.id, text) ??
      _uuid.v4();

  if (beforeSend.isProcessing) {
    const message =
        'A request is already running. Wait for it to finish or cancel it before sending another.';
    ref.read(studioThreadProvider.notifier).block(thread.id, message);
    if (finishTask && taskId != null) {
      ref.read(agentWorkspaceProvider.notifier).failTask(taskId, message);
    }
    return StudioSendResult.blocked(
      message,
      threadId: thread.id,
      taskId: taskId,
      contextSummary: payload.summary,
      blockedByActiveRequest: true,
    );
  }

  if ((rootPath == null || !workspace.canCode) &&
      promptMode.agentProfile != null) {
    const message =
        'Choose a bound project folder before using Code, Fix, or Review mode.';
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
  final requestId = _uuid.v4();
  ref
      .read(studioTurnProvider.notifier)
      .registerTurn(
        requestId: requestId,
        threadId: thread.id,
        taskId: taskId,
        userMessageId: userMessageId,
        prompt: text,
        model: model,
        contextSummary: payload.summary,
      );
  ref
      .read(studioRequestLifecycleProvider.notifier)
      .registerRequest(
        requestId: requestId,
        threadId: thread.id,
        taskId: taskId,
        model: model,
        contextSummary: payload.summary,
      );
  await ref
      .read(chatProvider.notifier)
      .sendMessage(
        text,
        attachments: payload.attachments,
        historyOverride: priorThreadMessages,
        toolMode: _toolModeForPrompt(promptMode),
        requestId: requestId,
      );

  final chat = ref.read(chatProvider);
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
    ref
        .read(studioRequestLifecycleProvider.notifier)
        .failRequest(requestId, message);
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
    ref
        .read(studioRequestLifecycleProvider.notifier)
        .failRequest(requestId, chat.error!);
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
      registeredRequest: true,
    );
  }
  final lifecycleEntry = ref
      .read(studioRequestLifecycleProvider)
      .find(requestId);
  return StudioSendResult.completed(
    requestId: requestId,
    threadId: thread.id,
    taskId: taskId,
    contextSummary: payload.summary,
    registeredRequest: lifecycleEntry != null,
  );
}

AgentToolMode _toolModeForPrompt(StudioPromptMode mode) {
  return switch (mode) {
    StudioPromptMode.ask => AgentToolMode.ask,
    StudioPromptMode.code => AgentToolMode.code,
    StudioPromptMode.fix => AgentToolMode.fix,
    StudioPromptMode.review => AgentToolMode.review,
  };
}

class StudioContextPayload {
  final List<ContextAttachment> attachments;
  final StudioContextSummary summary;
  final SpecialistAgentSelection specialistSelection;

  const StudioContextPayload({
    required this.attachments,
    required this.summary,
    required this.specialistSelection,
  });
}

StudioContextPayload buildStudioContextPayload(WidgetRef ref, String prompt) {
  final rootPath = ref.read(fileTreeProvider).rootPath;
  final studio = ref.read(studioShellProvider);
  const registry = SpecialistAgentRegistry();
  final selection = const SpecialistAgentRouter().route(
    prompt,
    explicitAgentId: studio.specialistAgentId,
  );
  final contextPack = ref
      .read(contextPackProvider.notifier)
      .buildForCodingTask(prompt: prompt);
  final attachment = _buildStudioContextAttachment(rootPath, contextPack);
  final attachments = <ContextAttachment>[
    attachment,
    if (selection.hasEnterpriseRouting)
      _buildSpecialistContextAttachment(selection, registry),
  ];
  return StudioContextPayload(
    attachments: attachments,
    summary: _buildContextSummary(
      rootPath,
      contextPack,
      attachments,
      selection,
      registry,
    ),
    specialistSelection: selection,
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

ContextAttachment _buildSpecialistContextAttachment(
  SpecialistAgentSelection selection,
  SpecialistAgentRegistry registry,
) {
  final content = selection.toPromptBlock(registry);
  return ContextAttachment(
    id: 'enterprise-specialists-${selection.resolvedAgentIds.map((id) => id.name).join('-')}',
    type: ContextAttachmentType.note,
    label: 'Enterprise specialist routing',
    content: content,
    resolutionStatus: ContextAttachmentResolutionStatus.resolved,
    estimatedTokens: (content.length / 4).ceil(),
    createdAt: DateTime.now(),
  );
}

StudioContextSummary _buildContextSummary(
  String? rootPath,
  ContextPack contextPack,
  List<ContextAttachment> attachments,
  SpecialistAgentSelection specialistSelection,
  SpecialistAgentRegistry registry,
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
    estimatedTokens: attachments.fold<int>(
      0,
      (sum, attachment) => sum + attachment.estimatedTokens,
    ),
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
    specialistLabels: specialistSelection.hasEnterpriseRouting
        ? specialistSelection
              .descriptors(registry)
              .map((descriptor) => descriptor.label)
              .toList(growable: false)
        : const [],
    specialistRouting: specialistSelection.hasEnterpriseRouting
        ? specialistSelection.rationale
        : null,
  );
}
