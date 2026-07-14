import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/studio_right_drawer.dart';
import '../../models/studio_shell.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_chrome.dart';

/// Returns the slash commands matching the user's current composer text.
List<StudioSlashCommand> studioSlashCommandMatches(String composerText) {
  final text = composerText.trimLeft();
  if (!text.startsWith('/')) return const [];
  final query = text.substring(1).toLowerCase();
  return _slashCommands
      .where((command) => command.name.startsWith(query))
      .take(8)
      .toList();
}

class StudioSlashCommandMenu extends ConsumerWidget {
  final List<StudioSlashCommand> commands;
  final ValueChanged<StudioSlashCommand> onSelect;

  const StudioSlashCommandMenu({
    super.key,
    required this.commands,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: tokens.studioDrawer.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.66)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final command in commands)
              _SlashCommandRow(command: command, onSelect: onSelect),
          ],
        ),
      ),
    );
  }
}

class _SlashCommandRow extends ConsumerWidget {
  final StudioSlashCommand command;
  final ValueChanged<StudioSlashCommand> onSelect;

  const _SlashCommandRow({required this.command, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return StudioFocusableActionSurface(
      key: ValueKey('studio-slash-command-${command.name}'),
      semanticLabel: 'Use ${command.title} slash command: ${command.detail}',
      onTap: () => onSelect(command),
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.studioControl.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Icon(command.icon, size: 14, color: tokens.textMuted),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  command.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: Spacing.md),
              Flexible(
                child: Text(
                  command.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xxs,
                    height: 1.1,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StudioSlashCommand {
  final String name;
  final String title;
  final String detail;
  final String prompt;
  final IconData icon;
  final void Function(WidgetRef ref)? run;

  const StudioSlashCommand({
    required this.name,
    required this.title,
    required this.detail,
    required this.prompt,
    required this.icon,
    this.run,
  });
}

final _slashCommands = <StudioSlashCommand>[
  const StudioSlashCommand(
    name: 'status',
    title: 'Status',
    detail: 'Summarize project state',
    prompt: 'Summarize the current project status, branch, changes, and risks.',
    icon: StudioIcons.radioButtonChecked,
  ),
  StudioSlashCommand(
    name: 'review',
    title: 'Review',
    detail: 'Inspect current changes',
    prompt: 'Review the current changes and call out risks or missing checks.',
    icon: StudioIcons.rateReviewOutlined,
    run: (ref) => ref
        .read(studioShellProvider.notifier)
        .setPromptMode(StudioPromptMode.review),
  ),
  StudioSlashCommand(
    name: 'plan',
    title: 'Plan',
    detail: 'Create plan first',
    prompt: 'Create a short implementation plan before making changes.',
    icon: StudioIcons.altRouteOutlined,
    run: (ref) =>
        ref.read(studioShellProvider.notifier).setPlanModeEnabled(true),
  ),
  const StudioSlashCommand(
    name: 'init',
    title: 'Initialize',
    detail: 'Explain structure',
    prompt:
        'Inspect this project and explain its structure and best next steps.',
    icon: StudioIcons.autoAwesomeOutlined,
  ),
  StudioSlashCommand(
    name: 'files',
    title: 'Files',
    detail: 'Open file drawer',
    prompt: '',
    icon: StudioIcons.folderOutlined,
    run: (ref) => ref
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.files),
  ),
  StudioSlashCommand(
    name: 'context',
    title: 'Context',
    detail: 'Open context drawer',
    prompt: '',
    icon: StudioIcons.inventory2Outlined,
    run: (ref) => ref.read(studioRightDrawerProvider.notifier).openContext(),
  ),
  StudioSlashCommand(
    name: 'terminal',
    title: 'Terminal',
    detail: 'Open command logs',
    prompt: '',
    icon: StudioIcons.terminalOutlined,
    run: (ref) => ref
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.terminal),
  ),
  const StudioSlashCommand(
    name: 'image',
    title: 'Image',
    detail: 'Attach image path',
    prompt: '/image ',
    icon: StudioIcons.imageOutlined,
  ),
  const StudioSlashCommand(
    name: 'screenshot',
    title: 'Screenshot',
    detail: 'Attach screenshot path',
    prompt: '/screenshot ',
    icon: StudioIcons.screenshotMonitorOutlined,
  ),
  const StudioSlashCommand(
    name: 'compare',
    title: 'Compare screenshots',
    detail: 'Reference | current images',
    prompt: '/compare reference.png | current.png',
    icon: StudioIcons.compareOutlined,
  ),
];
