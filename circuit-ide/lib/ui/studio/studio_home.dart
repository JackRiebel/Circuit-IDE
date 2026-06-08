import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../models/studio_shell.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/chat_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_prompt_composer.dart';
import 'studio_task_card.dart';

class StudioHome extends ConsumerWidget {
  const StudioHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final tasks = ref.watch(agentWorkspaceProvider).activeTasks;
    final rootPath = ref.watch(fileTreeProvider).rootPath;
    final settings = ref.watch(settingsProvider);
    final projectLabel = rootPath == null
        ? 'Circuit-IDE'
        : p.basename(rootPath);

    return Container(
      color: tokens.studioCanvas,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 728),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.xxxl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'What should we build in Circuit-IDE?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: Spacing.xxxl),
                StudioPromptComposer(
                  hintText: 'Do anything',
                  submitTooltip: 'Start Circuit task',
                  onSubmit: (text) => _submit(ref, text),
                ),
                const SizedBox(height: Spacing.xl),
                if (tasks.isNotEmpty) ...[
                  for (final task in tasks.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.sm),
                      child: StudioTaskCard(
                        task: task,
                        projectLabel: projectLabel,
                        onTap: () {
                          ref
                              .read(agentWorkspaceProvider.notifier)
                              .selectTask(task.id);
                          ref
                              .read(studioShellProvider.notifier)
                              .openTask(task.id);
                        },
                      ),
                    ),
                ] else
                  ..._suggestions(settings.recentProjects.isNotEmpty).map(
                    (suggestion) => _SuggestionRow(
                      text: suggestion,
                      onTap: () => _submit(ref, suggestion),
                    ),
                  ),
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
        'Create a plan for the first safe improvement',
        'Review the current codebase for risky areas',
      ];
    }
    return const [
      'Explain this project in plain English',
      'Find the safest next improvement',
      'Review the current changes before I ship',
    ];
  }

  void _submit(WidgetRef ref, String text) {
    final mode = ref.read(studioShellProvider).promptMode;
    final profile = mode.agentProfile;
    if (profile == null) {
      unawaited(ref.read(chatProvider.notifier).sendMessage(text));
      ref.read(studioShellProvider.notifier).openProject();
      return;
    }
    final task = ref
        .read(agentWorkspaceProvider.notifier)
        .startTask(goal: text, profile: profile);
    ref.read(studioShellProvider.notifier).openTask(task.id);
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
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.8)),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.chat_bubble_outline, color: tokens.textMuted, size: 16),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.sm,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
