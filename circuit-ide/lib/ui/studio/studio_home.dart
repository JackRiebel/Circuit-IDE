import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../models/studio_thread.dart';
import '../../state/file_tree_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_message_sender.dart';
import 'studio_prompt_composer.dart';

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
    final recentThreads = threads.take(3).toList();

    return Container(
      color: tokens.studioCanvas,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 724),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.xxl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'What should Circuit do next?',
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 21,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    _HomeContextChip(label: projectLabel),
                  ],
                ),
                const SizedBox(height: Spacing.lg),
                Text(
                  rootPath == null
                      ? 'Ask a question or describe the work. Circuit will create a project only when the task needs one.'
                      : 'Working in $projectLabel.',
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
                    height: 1.32,
                  ),
                ),
                const SizedBox(height: 22),
                StudioPromptComposer(
                  hintText: 'Do anything',
                  submitTooltip: 'Start Circuit task',
                  onSubmit: (text) => _submit(ref, text),
                ),
                const SizedBox(height: 18),
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
                  const _HomeSectionLabel('Try'),
                  ..._suggestions(settings.recentProjects.isNotEmpty).map(
                    (suggestion) => _SuggestionRow(
                      text: suggestion,
                      onTap: () => _submit(ref, suggestion),
                    ),
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
        'Open a project and explain what it does',
        'Create a network topology from requirements',
        'Size a switching solution for Wi-Fi 7 and UPOE needs',
      ];
    }
    return const [
      'Create a network topology for this customer',
      'Size a Cisco solution from client count, WAN speed, and PoE needs',
      'Validate model lifecycle and replacement options',
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
}

class _HomeContextChip extends ConsumerWidget {
  final String label;

  const _HomeContextChip({required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.studioControl.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.48)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_outlined, size: 13, color: tokens.textMuted),
          const SizedBox(width: Spacing.sm),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xs,
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
      padding: const EdgeInsets.fromLTRB(2, 0, 2, Spacing.sm),
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

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        decoration: BoxDecoration(
          color: tokens.studioActivityRow.withValues(alpha: 0.36),
          border: Border.all(
            color: tokens.studioDivider.withValues(alpha: 0.48),
          ),
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: Row(
          children: [
            Icon(Icons.chat_bubble_outline, color: tokens.textMuted, size: 14),
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

class _SuggestionRow extends ConsumerWidget {
  final String text;
  final VoidCallback onTap;

  const _SuggestionRow({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: tokens.studioDivider.withValues(alpha: 0.62),
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.chat_bubble_outline, color: tokens.textMuted, size: 14),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
