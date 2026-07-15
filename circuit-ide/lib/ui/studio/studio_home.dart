import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../models/agent_workspace.dart';
import '../../state/agent_workspace_provider.dart';
import '../../models/studio_thread.dart';
import '../../state/file_tree_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_message_sender.dart';
import 'studio_chrome.dart';
import 'studio_prompt_composer.dart';
import 'studio_workspace_opening.dart';

class StudioHome extends ConsumerWidget {
  const StudioHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final threads = ref.watch(studioThreadProvider).threads;
    final settings = ref.watch(settingsProvider);
    final rootPath = ref.watch(fileTreeProvider).rootPath;
    final projectLabel = rootPath == null
        ? 'No project selected'
        : p.basename(rootPath);
    final recentThreads = threads.take(4).toList();

    return Container(
      color: tokens.studioCanvas,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 706),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        'Where should we start?',
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: FontSizes.lg,
                          height: 1.16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    _HomeContextChip(label: projectLabel),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                Text(
                  rootPath == null
                      ? 'Ask a question, sketch an idea, or describe a concrete change. Circuit will only create a project when the request truly needs one.'
                      : 'Working in $projectLabel. Broad ideas start with discovery; concrete changes move into plans and patches.',
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
                    height: 1.3,
                  ),
                ),
                if (rootPath == null) ...[
                  const SizedBox(height: Spacing.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => unawaited(chooseStudioProjectRoot(ref)),
                      icon: const Icon(
                        StudioIcons.folderOpenOutlined,
                        size: 15,
                      ),
                      label: const Text('Open project folder'),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                StudioPromptComposer(
                  hintText: 'Ask, plan, or describe work',
                  submitTooltip: 'Start Circuit task',
                  onSubmit: (text) => _submit(ref, text),
                  onQueueResearch: (text) => _queueResearch(context, ref, text),
                ),
                const SizedBox(height: Spacing.lg),
                if (recentThreads.isNotEmpty) ...[
                  const _HomeSectionLabel('Recent'),
                  for (final thread in recentThreads)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.sm),
                      child: _RecentThreadRow(
                        thread: thread,
                        onTap: () => ref
                            .read(studioShellProvider.notifier)
                            .openThread(thread.id),
                      ),
                    ),
                ] else ...[
                  const _HomeSectionLabel('Start with'),
                  _SuggestionList(
                    suggestions: _suggestions(
                      settings.recentProjects.isNotEmpty,
                    ),
                    onTap: (suggestion) => _submit(ref, suggestion),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<String> _suggestions(bool hasProjects) {
    if (!hasProjects) {
      return const [
        'Open a project and explain the codebase',
        'Explore requirements for a network topology',
        'Work through sizing rules for Wi-Fi 7 and UPOE',
      ];
    }
    return const [
      'Review this project and summarize the next safe change',
      'Turn these requirements into a plan',
      'Validate model lifecycle and replacement risk',
    ];
  }

  void _submit(WidgetRef ref, String text) {
    if (isConversationalOnlyPrompt(text)) {
      unawaited(_submitConversational(ref, text));
      return;
    }
    unawaited(_submitThreadOwned(ref, text));
  }

  Future<void> _submitConversational(WidgetRef ref, String text) async {
    final result = await sendStudioMessage(ref, text);
    final threadId = result.threadId;
    if (threadId != null) {
      ref.read(studioShellProvider.notifier).openThread(threadId);
    }
  }

  Future<void> _submitThreadOwned(WidgetRef ref, String text) async {
    final result = await sendStudioMessage(ref, text);
    final threadId = result.threadId;
    if (threadId != null) {
      ref.read(studioShellProvider.notifier).openThread(threadId);
    }
  }

  void _queueResearch(BuildContext context, WidgetRef ref, String text) {
    try {
      final task = ref
          .read(agentWorkspaceProvider.notifier)
          .startTask(
            goal: text,
            profile: AgentTaskProfile.research,
            backgroundExecutionRequested: true,
          );
      ref.read(studioShellProvider.notifier).openTask(task.id);
    } on StateError catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message.toString())));
    }
  }
}

class _HomeContextChip extends ConsumerWidget {
  final String label;

  const _HomeContextChip({required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.studioControl.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(StudioIcons.folderOutlined, size: 12, color: tokens.textMuted),
          const SizedBox(width: Spacing.sm),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xxs,
                height: 1.1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeSectionLabel extends ConsumerWidget {
  final String label;

  const _HomeSectionLabel(this.label);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 7),
      child: Text(
        label,
        style: TextStyle(
          color: tokens.textMuted.withValues(alpha: 0.82),
          fontSize: FontSizes.xs,
          height: 1.15,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _RecentThreadRow extends ConsumerWidget {
  final StudioThread thread;
  final VoidCallback onTap;

  const _RecentThreadRow({required this.thread, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final lifecycle = StudioTaskLifecycleState.fromThread(thread);
    final chipColor = lifecycle.needsAttention
        ? tokens.warning
        : lifecycle.isActive
        ? tokens.accent
        : tokens.textMuted;

    return StudioFocusableActionSurface(
      key: ValueKey('studio-home-recent-thread-${thread.id}'),
      semanticLabel: 'Open ${thread.title}, ${lifecycle.label} recent task',
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        decoration: BoxDecoration(
          color: tokens.studioActivityRow.withValues(alpha: 0.28),
          border: Border.all(
            color: tokens.studioDivider.withValues(alpha: 0.38),
          ),
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Row(
          children: [
            Icon(
              StudioIcons.chatBubbleOutline,
              color: tokens.textMuted,
              size: 13,
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(
                thread.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.sm,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: chipColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(
                lifecycle.label,
                style: TextStyle(
                  color: chipColor,
                  fontSize: FontSizes.xxs,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionList extends ConsumerWidget {
  final List<String> suggestions;
  final ValueChanged<String> onTap;

  const _SuggestionList({required this.suggestions, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.5)),
          bottom: BorderSide(
            color: tokens.studioDivider.withValues(alpha: 0.32),
          ),
        ),
      ),
      child: Column(
        children: [
          for (var index = 0; index < suggestions.length; index++)
            _SuggestionRow(
              text: suggestions[index],
              onTap: () => onTap(suggestions[index]),
              showDivider: index > 0,
            ),
        ],
      ),
    );
  }
}

class _SuggestionRow extends ConsumerWidget {
  final String text;
  final VoidCallback onTap;
  final bool showDivider;

  const _SuggestionRow({
    required this.text,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return StudioFocusableActionSurface(
      key: ValueKey('studio-home-suggestion-$text'),
      semanticLabel: 'Use suggestion: $text',
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(
                  top: BorderSide(
                    color: tokens.studioDivider.withValues(alpha: 0.34),
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            Icon(
              StudioIcons.arrowOutward,
              color: tokens.textMuted.withValues(alpha: 0.86),
              size: 13,
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                  height: 1.1,
                ),
              ),
            ),
            Icon(StudioIcons.chevronRight, color: tokens.textMuted, size: 14),
          ],
        ),
      ),
    );
  }
}
