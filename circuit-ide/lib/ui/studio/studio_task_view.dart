import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../core/constants/design_tokens.dart';
import '../../enums/message_role.dart';
import '../../models/agent_workspace.dart';
import '../../models/chat_message.dart';
import '../../models/command_run.dart';
import '../../models/confirmation_request.dart';
import '../../models/reviewed_edit.dart';
import '../../models/studio_right_drawer.dart';
import '../../models/studio_source_artifact.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_turn.dart';
import '../../models/studio_view_models.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/chat_provider.dart';
import '../../state/command_run_provider.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';
import '../chat/chat_message_widget.dart';
import 'studio_chrome.dart';
import 'studio_message_sender.dart';
import 'studio_prompt_composer.dart';
import 'studio_right_drawer.dart';

class StudioTaskView extends ConsumerWidget {
  const StudioTaskView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studio = ref.watch(studioShellProvider);
    final workspace = ref.watch(agentWorkspaceProvider);
    final task = studio.selectedTaskId == null
        ? workspace.selectedTask
        : workspace.tasks
              .where((candidate) => candidate.id == studio.selectedTaskId)
              .firstOrNull;

    return Row(
      children: [
        Expanded(child: _TaskTranscript(task: task)),
        if (studio.rightProgressPanelVisible) StudioRightDrawer(task: task),
      ],
    );
  }
}

class _TaskTranscript extends ConsumerWidget {
  final AgentTask? task;

  const _TaskTranscript({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final chat = ref.watch(chatProvider);
    final threadState = ref.watch(studioThreadProvider);
    final thread =
        threadState.threadForTask(task?.id) ?? threadState.selectedThread;
    final activePatch = ref.watch(patchProposalProvider).active;
    final patch =
        activePatch?.agentTaskId == null || activePatch?.agentTaskId == task?.id
        ? activePatch
        : null;
    final allCommands = ref.watch(commandRunProvider).values.toList();
    final taskCommandIds = task?.commandRunIds.toSet() ?? const <String>{};
    final commands = taskCommandIds.isEmpty
        ? const <CommandRun>[]
        : allCommands
              .where((command) => taskCommandIds.contains(command.id))
              .toList();
    final commandIds = commands.map((command) => command.id).toSet();
    final artifacts =
        task?.artifacts
            .where(
              (artifact) =>
                  artifact.type != AgentTaskArtifactType.commandRun ||
                  !commandIds.contains(artifact.id),
            )
            .toList() ??
        const <AgentTaskArtifact>[];
    final title = task?.goal ?? thread?.title ?? 'New Circuit task';
    final lifecycle = StudioTaskLifecycleState.fromThread(thread);
    final displayState = thread == null
        ? TaskDisplayState.derive(
            task: task,
            isChatProcessing: chat.isProcessing,
            isChatStreaming: chat.isStreaming,
            hasAssistantResponse: false,
            hasPendingApproval: chat.pendingConfirmation != null,
            commands: commands,
            chatError: chat.error,
          )
        : TaskDisplayState.fromLifecycle(lifecycle);
    final transcriptItems = _buildTranscriptItems(
      messages:
          thread?.messages.map((message) => message.toChatMessage()).toList() ??
          const [],
      artifacts: artifacts,
      sourceArtifacts: thread?.sourceArtifacts ?? const [],
      commands: commands.take(4).toList(),
      patch: patch,
      confirmation: (thread?.isActive ?? false)
          ? chat.pendingConfirmation
          : null,
      error: thread?.lastError,
      thread: thread,
      fallbackUserText: title,
      fallbackCreatedAt: task?.createdAt,
    );
    final turnWidgets = thread?.turns.isNotEmpty == true
        ? _buildTurnWidgets(context, ref, thread!.turns)
        : null;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(72, 28, 72, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _statusLabel(task, displayState),
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Divider(color: tokens.studioDivider.withValues(alpha: 0.82)),
                const SizedBox(height: Spacing.lg),
                if (turnWidgets != null)
                  ...turnWidgets
                else
                  for (final item in transcriptItems)
                    switch (item.type) {
                      StudioTranscriptItemType.userMessage =>
                        _ChatTranscriptLine(
                          isUser: true,
                          text: item.message!.content,
                        ),
                      StudioTranscriptItemType.assistantMarkdown =>
                        _ChatTranscriptLine(
                          isUser: false,
                          text: item.message!.content,
                        ),
                      StudioTranscriptItemType.approval =>
                        _StudioConfirmationCard(request: item.confirmation!),
                      StudioTranscriptItemType.error => _TranscriptEvent(
                        icon: Icons.error_outline,
                        title: 'Circuit AI needs attention',
                        detail: item.error!,
                      ),
                      StudioTranscriptItemType.activity ||
                      StudioTranscriptItemType.patchReview ||
                      StudioTranscriptItemType.commandRun => _ActivityItem(
                        item: item,
                        iconFor: _artifactIcon,
                      ),
                    },
                if (patch != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.md),
                      child: OutlinedButton(
                        onPressed: () =>
                            ref.read(studioShellProvider.notifier).openReview(),
                        child: const Text('Review changes'),
                      ),
                    ),
                  ),
                if ((thread?.isActive ?? false) &&
                    (thread?.status == StudioThreadStatus.streaming ||
                        chat.isStreaming))
                  _ChatTranscriptLine(
                    isUser: false,
                    text:
                        (thread?.streamingContent ?? chat.streamingContent)
                            .isEmpty
                        ? 'Circuit AI is responding...'
                        : thread?.streamingContent ?? chat.streamingContent,
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 72, Spacing.md),
          child: StudioPromptComposer(
            compact: true,
            hintText: 'Ask for follow-up changes',
            submitTooltip: 'Send follow-up',
            onSubmit: (text) => unawaited(
              sendStudioMessage(
                ref,
                text,
                taskId: task?.id,
                finishTask: task != null,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _elapsed(DateTime start) {
    final delta = DateTime.now().difference(start);
    if (delta.inMinutes < 1) return '${delta.inSeconds}s';
    return '${delta.inMinutes}m ${delta.inSeconds.remainder(60)}s';
  }

  String _statusLabel(AgentTask? task, TaskDisplayState displayState) {
    final elapsed = task == null ? '' : ' for ${_elapsed(task.createdAt)}';
    return '${displayState.label}$elapsed';
  }

  IconData _artifactIcon(AgentTaskArtifactType type) {
    return switch (type) {
      AgentTaskArtifactType.contextPack => Icons.dataset_linked_outlined,
      AgentTaskArtifactType.patchProposal => Icons.rate_review_outlined,
      AgentTaskArtifactType.commandRun => Icons.terminal_outlined,
      AgentTaskArtifactType.checkpoint => Icons.restore_outlined,
      AgentTaskArtifactType.verification => Icons.playlist_add_check_outlined,
      AgentTaskArtifactType.diagnostic => Icons.fact_check_outlined,
    };
  }

  List<Widget> _buildTurnWidgets(
    BuildContext context,
    WidgetRef ref,
    List<StudioTurn> turns,
  ) {
    final orderedTurns = turns.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final recentTurns = orderedTurns.length > 8
        ? orderedTurns.sublist(orderedTurns.length - 8)
        : orderedTurns;
    final widgets = <Widget>[];
    for (final turn in recentTurns) {
      widgets.add(_ChatTranscriptLine(isUser: true, text: turn.prompt));
      final events = turn.events.toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      for (final event in events) {
        switch (event.type) {
          case StudioTurnEventType.userMessage:
            break;
          case StudioTurnEventType.context:
            widgets.add(
              _TranscriptEvent(
                icon: Icons.dataset_linked_outlined,
                title: event.title,
                detail: event.detail,
                onTap: () => ref
                    .read(studioRightDrawerProvider.notifier)
                    .openMode(StudioDrawerMode.sources),
              ),
            );
          case StudioTurnEventType.progress:
            if (event.transcriptVisible) {
              widgets.add(
                _TranscriptEvent(
                  icon: Icons.pending_outlined,
                  title: event.title,
                  detail: event.detail,
                ),
              );
            }
          case StudioTurnEventType.tool:
            widgets.add(
              _TranscriptEvent(
                icon: _iconForTurnTool(event.toolName),
                title: event.title,
                detail: event.detail,
                onTap: () => ref
                    .read(studioRightDrawerProvider.notifier)
                    .openMode(StudioDrawerMode.sources),
              ),
            );
          case StudioTurnEventType.approvalRequest:
            widgets.add(_StudioTurnApprovalCard(event: event));
          case StudioTurnEventType.assistantMessage:
            if ((event.content ?? '').trim().isNotEmpty) {
              widgets.add(
                _ChatTranscriptLine(isUser: false, text: event.content!),
              );
            }
          case StudioTurnEventType.error:
            widgets.add(
              _TranscriptEvent(
                icon: Icons.error_outline,
                title: event.title,
                detail: event.detail,
              ),
            );
          case StudioTurnEventType.completionSummary:
            widgets.add(
              _TranscriptEvent(
                icon: Icons.check_circle_outline,
                title: event.title,
                detail: event.detail,
              ),
            );
        }
      }
      final hasFinalAssistant = events.any(
        (event) => event.type == StudioTurnEventType.assistantMessage,
      );
      if (!hasFinalAssistant && turn.assistantDraft.trim().isNotEmpty) {
        widgets.add(
          _ChatTranscriptLine(isUser: false, text: turn.assistantDraft),
        );
      }
    }
    return widgets;
  }

  IconData _iconForTurnTool(String? toolName) {
    return switch (toolName) {
      'run_command' => Icons.terminal_outlined,
      'read_file' ||
      'list_files' ||
      'search_files' => Icons.fact_check_outlined,
      'write_file' || 'edit_file' => Icons.edit_document,
      'propose_patch' => Icons.rate_review_outlined,
      'git_status' || 'git_diff' => Icons.account_tree_outlined,
      _ => Icons.task_alt_outlined,
    };
  }

  List<StudioTranscriptItem> _buildTranscriptItems({
    required List<ChatMessage> messages,
    required List<AgentTaskArtifact> artifacts,
    required List<StudioSourceArtifact> sourceArtifacts,
    required List<CommandRun> commands,
    required ProposedPatchSet? patch,
    required ConfirmationRequest? confirmation,
    required String? error,
    required StudioThread? thread,
    required String fallbackUserText,
    required DateTime? fallbackCreatedAt,
  }) {
    final visibleMessages = messages
        .where(
          (message) =>
              message.role == MessageRole.user ||
              message.role == MessageRole.assistant,
        )
        .toList();
    final recentMessages = visibleMessages.length > 12
        ? visibleMessages.sublist(visibleMessages.length - 12)
        : visibleMessages;
    final items = <StudioTranscriptItem>[];
    final lastUserMessageId = recentMessages
        .where((message) => message.role == MessageRole.user)
        .lastOrNull
        ?.id;
    if (recentMessages.isEmpty) {
      items.add(
        StudioTranscriptItem.userMessage(
          ChatMessage(
            id: 'studio-fallback-user-message',
            role: MessageRole.user,
            content: fallbackUserText,
            timestamp: fallbackCreatedAt ?? DateTime.now(),
          ),
        ),
      );
    } else {
      for (final message in recentMessages) {
        if (message.role == MessageRole.user) {
          items.add(
            StudioTranscriptItem.userMessage(
              message,
              threadId: thread?.id,
              requestId: thread?.requestId,
            ),
          );
          if (message.id == lastUserMessageId &&
              thread?.contextSummary != null) {
            items.add(
              StudioTranscriptItem.activity(
                AgentTaskArtifact(
                  id: 'context-${thread!.id}-${message.id}',
                  type: AgentTaskArtifactType.contextPack,
                  title: thread.contextSummary!.title,
                  detail: thread.contextSummary!.detail,
                  createdAt: message.timestamp,
                ),
                threadId: thread.id,
                requestId: thread.requestId,
                relatedMessageId: message.id,
                contextSummary: thread.contextSummary,
              ),
            );
          }
        } else {
          items.add(
            StudioTranscriptItem.assistantMarkdown(
              message,
              threadId: thread?.id,
              requestId: thread?.requestId,
            ),
          );
        }
      }
    }
    if (confirmation != null) {
      items.add(
        StudioTranscriptItem.approval(
          confirmation,
          threadId: thread?.id,
          requestId: thread?.requestId,
        ),
      );
    }
    final earliestVisible = recentMessages.firstOrNull?.timestamp;
    for (final source in _compactSourceArtifacts(
      sourceArtifacts,
      earliestVisible: earliestVisible,
    )) {
      items.add(
        StudioTranscriptItem.activity(
          AgentTaskArtifact(
            id: source.id,
            type: _artifactTypeForSource(source.kind),
            title: source.title,
            detail: source.subtitle.isEmpty ? source.value : source.subtitle,
            createdAt: source.createdAt,
          ),
          threadId: thread?.id,
          requestId: source.requestId ?? thread?.requestId,
          relatedMessageId: source.relatedMessageId,
          sourceArtifactId: source.id,
          filePath: source.filePath,
          localUrl: source.localUrl,
        ),
      );
    }
    for (final artifact in artifacts) {
      items.add(
        StudioTranscriptItem.activity(
          artifact,
          threadId: thread?.id,
          requestId: thread?.requestId,
        ),
      );
    }
    if (patch != null) {
      items.add(
        StudioTranscriptItem.patchReview(
          patch,
          threadId: thread?.id,
          requestId: thread?.requestId,
        ),
      );
    }
    for (final command in commands) {
      items.add(
        StudioTranscriptItem.commandRun(
          command,
          threadId: thread?.id,
          requestId: thread?.requestId,
        ),
      );
    }
    if (error != null) {
      items.add(
        StudioTranscriptItem.error(
          error,
          threadId: thread?.id,
          requestId: thread?.requestId,
        ),
      );
    }
    items.sort(_compareTranscriptItems);
    return items;
  }

  List<StudioSourceArtifact> _compactSourceArtifacts(
    List<StudioSourceArtifact> artifacts, {
    DateTime? earliestVisible,
  }) {
    final visible = artifacts.where((artifact) {
      if (earliestVisible != null &&
          artifact.createdAt.isBefore(earliestVisible)) {
        return false;
      }
      if (artifact.kind == StudioSourceArtifactKind.toolResult &&
          const {'Request sent', 'Completed'}.contains(artifact.title)) {
        return false;
      }
      return true;
    }).toList();
    final completedKeys = visible
        .where((artifact) => artifact.subtitle.toLowerCase() == 'completed')
        .map(_artifactDedupKey)
        .toSet();
    final byId = <String, StudioSourceArtifact>{};
    for (final artifact in visible) {
      if (artifact.subtitle.toLowerCase() == 'running' &&
          completedKeys.contains(_artifactDedupKey(artifact))) {
        continue;
      }
      byId[artifact.id] = artifact;
    }
    final compact = byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return compact.take(48).toList();
  }

  String _artifactDedupKey(StudioSourceArtifact artifact) {
    final title = artifact.title
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceFirst(RegExp(r'^(reading|read) '), 'read ')
        .replaceFirst(RegExp(r'^(listing|listed) '), 'list ')
        .replaceFirst(RegExp(r'^(checking|checked) '), 'check ')
        .replaceFirst(RegExp(r'^(preparing|prepared) '), 'prepare ')
        .replaceFirst(RegExp(r'^(editing|edited) '), 'edit ');
    return [
      artifact.requestId ?? '',
      artifact.kind.name,
      title,
      artifact.filePath ?? '',
      artifact.localUrl ?? '',
    ].join('|');
  }

  int _compareTranscriptItems(StudioTranscriptItem a, StudioTranscriptItem b) {
    final time = (a.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0))
        .compareTo(b.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0));
    if (time != 0) return time;
    return _transcriptPriority(a).compareTo(_transcriptPriority(b));
  }

  int _transcriptPriority(StudioTranscriptItem item) {
    return switch (item.type) {
      StudioTranscriptItemType.userMessage => 0,
      StudioTranscriptItemType.activity => 1,
      StudioTranscriptItemType.commandRun => 2,
      StudioTranscriptItemType.patchReview => 3,
      StudioTranscriptItemType.approval => 4,
      StudioTranscriptItemType.assistantMarkdown => 5,
      StudioTranscriptItemType.error => 6,
    };
  }

  AgentTaskArtifactType _artifactTypeForSource(StudioSourceArtifactKind kind) {
    return switch (kind) {
      StudioSourceArtifactKind.command ||
      StudioSourceArtifactKind.terminalLog ||
      StudioSourceArtifactKind.terminalSession =>
        AgentTaskArtifactType.commandRun,
      StudioSourceArtifactKind.patch ||
      StudioSourceArtifactKind.diff ||
      StudioSourceArtifactKind.gitChange ||
      StudioSourceArtifactKind.gitHunk ||
      StudioSourceArtifactKind.reviewComment =>
        AgentTaskArtifactType.patchProposal,
      StudioSourceArtifactKind.localUrl ||
      StudioSourceArtifactKind.file ||
      StudioSourceArtifactKind.webSource ||
      StudioSourceArtifactKind.toolResult ||
      StudioSourceArtifactKind.browserComment ||
      StudioSourceArtifactKind.topology ||
      StudioSourceArtifactKind.sizing ||
      StudioSourceArtifactKind.lifecycle ||
      StudioSourceArtifactKind.chart ||
      StudioSourceArtifactKind.businessUseCase ||
      StudioSourceArtifactKind.evidence => AgentTaskArtifactType.diagnostic,
    };
  }
}

class _StudioConfirmationCard extends ConsumerWidget {
  final ConfirmationRequest request;

  const _StudioConfirmationCard({required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final command = request.toolCall.arguments['command'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 660),
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: tokens.studioPanel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.warning.withValues(alpha: 0.34)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, color: tokens.warning, size: 16),
                const SizedBox(width: Spacing.sm),
                Text(
                  'Approval needed',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Text(
              command == null
                  ? 'Circuit wants to run a protected tool.'
                  : 'Circuit wants to run this command:',
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
            ),
            const SizedBox(height: Spacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: tokens.surfaceInset,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tokens.studioDivider),
              ),
              child: SelectableText(
                command ?? request.preview,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.xs,
                  height: 1.45,
                  fontFamily: EditorDefaults.fallbackFontFamily,
                ),
              ),
            ),
            if (request.warnings.isNotEmpty) ...[
              const SizedBox(height: Spacing.md),
              for (final warning in request.warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    warning,
                    style: TextStyle(
                      color: tokens.error,
                      fontSize: FontSizes.xs,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: Spacing.lg),
            Wrap(
              alignment: WrapAlignment.end,
              runSpacing: Spacing.sm,
              spacing: Spacing.sm,
              children: [
                TextButton(
                  onPressed: () => ref
                      .read(chatProvider.notifier)
                      .rejectConfirmation(request.id),
                  child: const Text('Reject'),
                ),
                OutlinedButton.icon(
                  onPressed: () => ref
                      .read(chatProvider.notifier)
                      .approveConfirmationForCurrentTask(request.id),
                  icon: const Icon(Icons.task_alt_outlined, size: 15),
                  label: const Text('Approve this task'),
                ),
                FilledButton(
                  onPressed: () => ref
                      .read(chatProvider.notifier)
                      .approveConfirmation(request.id),
                  child: const Text('Approve once'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StudioTurnApprovalCard extends ConsumerWidget {
  final StudioTurnEvent event;

  const _StudioTurnApprovalCard({required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final approvalId = event.approvalId;
    final isPending = event.approvalState == ApprovalRequestState.pending;
    final statusLabel = switch (event.approvalState) {
      ApprovalRequestState.approved => 'Approved',
      ApprovalRequestState.rejected => 'Rejected',
      ApprovalRequestState.expired => 'Expired',
      ApprovalRequestState.pending || null => 'Approval needed',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 660),
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: tokens.studioPanel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isPending
                ? tokens.warning.withValues(alpha: 0.34)
                : tokens.studioDivider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isPending ? Icons.shield_outlined : Icons.task_alt_outlined,
                  color: isPending ? tokens.warning : tokens.textMuted,
                  size: 16,
                ),
                const SizedBox(width: Spacing.sm),
                Text(
                  statusLabel,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Text(
              event.toolName == null
                  ? 'Circuit wants approval for a protected action.'
                  : 'Circuit wants to use ${event.toolName!.replaceAll('_', ' ')}:',
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
            ),
            const SizedBox(height: Spacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: tokens.surfaceInset,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tokens.studioDivider),
              ),
              child: SelectableText(
                event.approvalPreview ?? event.detail,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.xs,
                  height: 1.45,
                  fontFamily: EditorDefaults.fallbackFontFamily,
                ),
              ),
            ),
            if (event.approvalWarnings.isNotEmpty) ...[
              const SizedBox(height: Spacing.md),
              for (final warning in event.approvalWarnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    warning,
                    style: TextStyle(
                      color: tokens.error,
                      fontSize: FontSizes.xs,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: Spacing.lg),
            Wrap(
              alignment: WrapAlignment.end,
              runSpacing: Spacing.sm,
              spacing: Spacing.sm,
              children: [
                TextButton(
                  onPressed: isPending && approvalId != null
                      ? () => ref
                            .read(chatProvider.notifier)
                            .rejectConfirmation(approvalId)
                      : null,
                  child: const Text('Reject'),
                ),
                OutlinedButton.icon(
                  onPressed: isPending && approvalId != null
                      ? () => ref
                            .read(chatProvider.notifier)
                            .approveConfirmationForCurrentTask(approvalId)
                      : null,
                  icon: const Icon(Icons.task_alt_outlined, size: 15),
                  label: const Text('Approve this task'),
                ),
                FilledButton(
                  onPressed: isPending && approvalId != null
                      ? () => ref
                            .read(chatProvider.notifier)
                            .approveConfirmation(approvalId)
                      : null,
                  child: const Text('Approve once'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityItem extends ConsumerWidget {
  final StudioTranscriptItem item;
  final IconData Function(AgentTaskArtifactType type) iconFor;

  const _ActivityItem({required this.item, required this.iconFor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (item.type) {
      StudioTranscriptItemType.activity => _TranscriptEvent(
        icon: iconFor(item.artifact!.type),
        title: item.artifact!.title,
        detail: item.artifact!.detail,
        onTap: () => ref
            .read(studioRightDrawerProvider.notifier)
            .openMode(StudioDrawerMode.sources),
      ),
      StudioTranscriptItemType.patchReview => _TranscriptEvent(
        icon: Icons.rate_review_outlined,
        title: 'Patch ready for review',
        detail: '${item.patch!.fileCount} files proposed',
        elevated: true,
        onTap: () => ref
            .read(studioRightDrawerProvider.notifier)
            .openMode(StudioDrawerMode.diff),
      ),
      StudioTranscriptItemType.commandRun => _TranscriptEvent(
        icon: Icons.terminal_outlined,
        title: item.commandRun!.command,
        detail:
            '${item.commandRun!.status.name} · ${item.commandRun!.elapsed.inSeconds}s',
        elevated: true,
        onTap: () => ref
            .read(studioRightDrawerProvider.notifier)
            .openCommand(item.commandRun!.id),
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _TranscriptEvent extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String detail;
  final bool elevated;
  final VoidCallback? onTap;

  const _TranscriptEvent({
    required this.icon,
    required this.title,
    required this.detail,
    this.elevated = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StudioActivityRow(
      icon: icon,
      title: title,
      detail: detail,
      onTap: onTap,
      elevated: elevated,
    );
  }
}

class _ChatTranscriptLine extends ConsumerWidget {
  final bool isUser;
  final String text;

  const _ChatTranscriptLine({required this.isUser, required this.text});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    if (!isUser) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 660),
          margin: const EdgeInsets.only(bottom: Spacing.xl),
          child: MarkdownWidget(
            data: text,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            config: buildChatMarkdownConfig(tokens),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.only(bottom: Spacing.lg),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: tokens.studioBubble,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: FontSizes.sm,
            height: 1.32,
          ),
        ),
      ),
    );
  }
}
