import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../enums/message_role.dart';
import '../../models/agent_workspace.dart';
import '../../models/studio_shell.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/chat_provider.dart';
import '../../state/command_run_provider.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/theme_provider.dart';
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
    final title = task?.goal ?? 'New Circuit task';

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(72, 32, 72, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 520),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.lg,
                      vertical: Spacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.studioPanel,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      title,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.sm,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.xxxl),
                Text(
                  task == null
                      ? 'Ready'
                      : '${studioTaskStatusLabel(task!.status)} for ${_elapsed(task!.createdAt)}',
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.sm,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Divider(color: tokens.studioDivider),
                const SizedBox(height: Spacing.md),
                if (task != null)
                  for (final artifact in task!.artifacts)
                    _TranscriptEvent(
                      icon: _artifactIcon(artifact.type),
                      title: artifact.title,
                      detail: artifact.detail,
                    ),
                if (patch != null)
                  _TranscriptEvent(
                    icon: Icons.rate_review_outlined,
                    title: 'Patch ready for review',
                    detail: '${patch.fileCount} files proposed',
                    actionLabel: 'Review changes',
                    onAction: () =>
                        ref.read(studioShellProvider.notifier).openReview(),
                  ),
                for (final command in commands.take(4))
                  _TranscriptEvent(
                    icon: Icons.terminal_outlined,
                    title: command.command,
                    detail:
                        '${command.status.name} · ${command.elapsed.inSeconds}s',
                  ),
                for (final message in chat.messages.take(8))
                  _ChatTranscriptLine(
                    isUser: message.role == MessageRole.user,
                    text: message.content,
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
            onSubmit: (text) =>
                unawaited(ref.read(chatProvider.notifier).sendMessage(text)),
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

class _TranscriptEvent extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _TranscriptEvent({
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
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
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: Spacing.sm),
                  OutlinedButton(
                    onPressed: onAction,
                    child: Text(actionLabel!),
                  ),
                ],
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
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        margin: const EdgeInsets.only(bottom: Spacing.md),
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: isUser ? tokens.studioPanel : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: isUser ? null : Border.all(color: tokens.studioDivider),
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
