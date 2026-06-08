import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../core/constants/design_tokens.dart';
import '../../enums/message_role.dart';
import '../../models/agent_workspace.dart';
import '../../models/command_run.dart';
import '../../models/confirmation_request.dart';
import '../../models/reviewed_edit.dart';
import '../../models/studio_shell.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/chat_provider.dart';
import '../../state/command_run_provider.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/theme_provider.dart';
import '../chat/chat_message_widget.dart';
import 'studio_message_sender.dart';
import 'studio_progress_panel.dart';
import 'studio_prompt_composer.dart';

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
        if (studio.rightProgressPanelVisible) StudioProgressPanel(task: task),
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
    final patch = ref.watch(patchProposalProvider).active;
    final commands = ref.watch(commandRunProvider).values.toList();
    final visibleMessages = chat.messages
        .where(
          (message) =>
              message.role == MessageRole.user ||
              message.role == MessageRole.assistant,
        )
        .toList();
    final recentMessages = visibleMessages.length > 12
        ? visibleMessages.sublist(visibleMessages.length - 12)
        : visibleMessages;
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
    final title = task?.goal ?? 'New Circuit task';

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(72, 32, 72, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _statusLabel(task, chat),
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.sm,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Divider(color: tokens.studioDivider),
                const SizedBox(height: Spacing.md),
                if (recentMessages.isEmpty)
                  _ChatTranscriptLine(isUser: true, text: title),
                for (final message in recentMessages)
                  _ChatTranscriptLine(
                    isUser: message.role == MessageRole.user,
                    text: message.content,
                  ),
                if (chat.pendingConfirmation != null)
                  _StudioConfirmationCard(request: chat.pendingConfirmation!),
                if (artifacts.isNotEmpty ||
                    patch != null ||
                    commands.isNotEmpty)
                  _ActivitySection(
                    artifacts: artifacts,
                    commands: commands.take(4).toList(),
                    patch: patch,
                    artifactIcon: _artifactIcon,
                  ),
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
                if (chat.isStreaming)
                  _ChatTranscriptLine(
                    isUser: false,
                    text: chat.streamingContent.isEmpty
                        ? 'Circuit AI is responding...'
                        : chat.streamingContent,
                  ),
                if (chat.error != null)
                  _TranscriptEvent(
                    icon: Icons.error_outline,
                    title: 'Circuit AI needs attention',
                    detail: chat.error!,
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 72, Spacing.lg),
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

  String _statusLabel(AgentTask? task, ChatState chat) {
    if (chat.pendingConfirmation != null) return 'Waiting for approval';
    if (task == null) return chat.isProcessing ? 'Working' : 'Ready';
    return '${studioTaskStatusLabel(task.status)} for ${_elapsed(task.createdAt)}';
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
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => ref
                      .read(chatProvider.notifier)
                      .rejectConfirmation(request.id),
                  child: const Text('Reject'),
                ),
                const SizedBox(width: Spacing.md),
                FilledButton(
                  onPressed: () => ref
                      .read(chatProvider.notifier)
                      .approveConfirmation(request.id),
                  child: const Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivitySection extends ConsumerWidget {
  final List<AgentTaskArtifact> artifacts;
  final List<CommandRun> commands;
  final ProposedPatchSet? patch;
  final IconData Function(AgentTaskArtifactType type) artifactIcon;

  const _ActivitySection({
    required this.artifacts,
    required this.commands,
    required this.patch,
    required this.artifactIcon,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final patchSet = patch;
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm, bottom: Spacing.lg),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.md,
          Spacing.lg,
          Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: tokens.studioPanel.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.studioDivider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Activity',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Spacing.md),
            for (final artifact in artifacts)
              _TranscriptEvent(
                icon: artifactIcon(artifact.type),
                title: artifact.title,
                detail: artifact.detail,
                compact: true,
              ),
            if (patchSet != null)
              _TranscriptEvent(
                icon: Icons.rate_review_outlined,
                title: 'Patch ready for review',
                detail: '${patchSet.fileCount} files proposed',
                compact: true,
              ),
            for (final command in commands)
              _TranscriptEvent(
                icon: Icons.terminal_outlined,
                title: command.command,
                detail:
                    '${command.status.name} · ${command.elapsed.inSeconds}s',
                compact: true,
              ),
          ],
        ),
      ),
    );
  }
}

class _TranscriptEvent extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String detail;
  final bool compact;

  const _TranscriptEvent({
    required this.icon,
    required this.title,
    required this.detail,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? Spacing.sm : Spacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tokens.textMuted, size: 16),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.sm,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
          margin: const EdgeInsets.only(bottom: Spacing.lg),
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
        margin: const EdgeInsets.only(bottom: Spacing.md),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.md,
        ),
        decoration: BoxDecoration(
          color: tokens.studioPanel,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: FontSizes.sm,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
