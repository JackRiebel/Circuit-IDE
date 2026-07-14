import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../core/constants/studio_layout_contract.dart';
import '../../core/utils/platform_utils.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_view_models.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_project_creator.dart';
import '../../state/studio_project_history_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/studio_thread_search_provider.dart';
import '../../state/theme_provider.dart';
import '../../state/workspace_session_provider.dart';
import '../../theme/theme_tokens.dart';
import 'studio_chrome.dart';
import 'studio_rail_row.dart';
import 'studio_recent_project_group.dart';
import 'studio_workspace_opening.dart';

export 'studio_recent_project_group.dart'
    show studioRailAgeLabel, studioRailShouldShowStatusIndicator;

class StudioLeftRail extends ConsumerWidget {
  const StudioLeftRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final recentProjects = ref.watch(
      settingsProvider.select((settings) => settings.recentProjects),
    );
    final historyPathKey = ref.watch(
      studioProjectHistoryProvider.select(
        (state) => state.byPath.keys.join('\u001f'),
      ),
    );
    final historyPaths = historyPathKey.isEmpty
        ? const <String>[]
        : historyPathKey.split('\u001f');
    final projectPaths = [
      ...recentProjects,
      for (final path in historyPaths)
        if (!recentProjects.contains(path)) path,
    ];
    return Container(
      width: StudioLayoutContract.leftRailWidth,
      decoration: BoxDecoration(
        color: tokens.studioRail,
        border: Border(
          right: BorderSide(
            color: tokens.studioDivider.withValues(alpha: 0.34),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 5),
            _RailTopBar(),
            const SizedBox(height: 6),
            _RailAction(
              icon: StudioIcons.editSquare,
              label: 'New chat',
              onTap: () => ref.read(studioShellProvider.notifier).openHome(),
            ),
            _RailAction(
              icon: StudioIcons.search,
              label: 'Search',
              onTap: () =>
                  ref.read(studioThreadSearchProvider.notifier).toggle(),
            ),
            _RailAction(
              icon: StudioIcons.filterList,
              label: 'Filter tasks',
              onTap: () => _showTaskFilters(context, ref),
            ),
            _RailAction(
              icon: StudioIcons.createNewFolderOutlined,
              label: 'New project',
              onTap: () => unawaited(_createProject(context, ref)),
            ),
            const _RailSearchBox(),
            const SizedBox(height: 9),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: projectPaths.isEmpty ? 2 : projectPaths.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) return const _RailSectionLabel('Projects');
                  if (projectPaths.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.lg,
                        vertical: Spacing.sm,
                      ),
                      child: Text(
                        'No recent projects',
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FontSizes.xs,
                        ),
                      ),
                    );
                  }
                  final path = projectPaths[index - 1];
                  return StudioRecentProjectGroup(
                    key: ValueKey('studio-rail-project-$path'),
                    path: path,
                  );
                },
              ),
            ),
            _RailAction(
              icon: StudioIcons.settingsOutlined,
              label: 'Settings',
              onTap: () =>
                  ref.read(studioShellProvider.notifier).openSettings(),
            ),
            const SizedBox(height: 7),
          ],
        ),
      ),
    );
  }
}

Future<void> _showTaskFilters(BuildContext context, WidgetRef ref) {
  final controller = ref.read(studioThreadSearchProvider.notifier);
  final current = ref.read(studioThreadSearchProvider);
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('Task filters')),
          for (final filter in StudioThreadStatusFilter.values)
            ListTile(
              title: Text(_statusFilterLabel(filter)),
              selected: current.statusFilter == filter,
              trailing: current.statusFilter == filter
                  ? const Icon(StudioIcons.check)
                  : null,
              onTap: () {
                controller.setStatusFilter(filter);
                Navigator.pop(context);
              },
            ),
          CheckboxListTile(
            title: const Text('Show archived tasks'),
            value: current.showArchived,
            onChanged: (value) {
              controller.setShowArchived(value ?? false);
              Navigator.pop(context);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(StudioIcons.inventory2Outlined),
            title: const Text('Archive completed tasks'),
            subtitle: const Text(
              'Keeps history; hides completed, failed, and cancelled tasks.',
            ),
            onTap: () async {
              final completedIds = ref
                  .read(studioThreadProvider)
                  .threads
                  .where(
                    (thread) =>
                        !thread.archived &&
                        studioRailMatchesTaskFilter(
                          TaskDisplayState.fromLifecycle(
                            StudioTaskLifecycleState.fromThread(thread),
                          ),
                          StudioThreadStatusFilter.completed,
                        ),
                  )
                  .map((thread) => thread.id)
                  .toList(growable: false);
              if (completedIds.isEmpty) {
                Navigator.pop(context);
                return;
              }
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Archive completed tasks?'),
                  content: Text(
                    'Archive ${completedIds.length} completed task${completedIds.length == 1 ? '' : 's'}? You can restore them later.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Archive'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                ref
                    .read(studioThreadProvider.notifier)
                    .archiveThreads(completedIds);
              }
              if (context.mounted) Navigator.pop(context);
            },
          ),
          if (current.showArchived)
            ListTile(
              leading: const Icon(StudioIcons.unarchiveOutlined),
              title: const Text('Restore archived tasks'),
              subtitle: const Text(
                'Returns archived task history to the rail.',
              ),
              onTap: () {
                final archivedIds = ref
                    .read(studioThreadProvider)
                    .threads
                    .where((thread) => thread.archived)
                    .map((thread) => thread.id)
                    .toList(growable: false);
                if (archivedIds.isNotEmpty) {
                  ref
                      .read(studioThreadProvider.notifier)
                      .restoreThreads(archivedIds);
                }
                Navigator.pop(context);
              },
            ),
        ],
      ),
    ),
  );
}

String _statusFilterLabel(StudioThreadStatusFilter filter) => switch (filter) {
  StudioThreadStatusFilter.all => 'All active tasks',
  StudioThreadStatusFilter.active => 'Working or waiting',
  StudioThreadStatusFilter.attention => 'Needs attention',
  StudioThreadStatusFilter.completed => 'Completed',
};

class _RailSearchBox extends ConsumerWidget {
  const _RailSearchBox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = ref.watch(studioThreadSearchProvider);
    if (!search.isOpen) return const SizedBox.shrink();
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.sm, 7, Spacing.sm, 0),
      child: SizedBox(
        height: 28,
        child: TextField(
          autofocus: true,
          onChanged: ref.read(studioThreadSearchProvider.notifier).setQuery,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: FontSizes.xs,
            height: 1.1,
          ),
          decoration: InputDecoration(
            hintText: 'Search chats',
            hintStyle: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xs,
            ),
            prefixIcon: Icon(
              StudioIcons.search,
              size: 14,
              color: tokens.textMuted,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 26,
              minHeight: 26,
            ),
            suffixIcon: StudioChromeIconButton(
              tooltip: 'Close search',
              onTap: ref.read(studioThreadSearchProvider.notifier).close,
              icon: StudioIcons.close,
              width: 24,
              height: 22,
              iconSize: 14,
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 26,
              minHeight: 26,
            ),
            filled: true,
            fillColor: tokens.studioHover.withValues(alpha: 0.24),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm,
              vertical: 0,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
              borderSide: BorderSide(
                color: tokens.studioDivider.withValues(alpha: 0.36),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
              borderSide: BorderSide(
                color: tokens.studioDivider.withValues(alpha: 0.36),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
              borderSide: BorderSide(
                color: tokens.outlineFocus.withValues(alpha: 0.72),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailTopBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigation = ref.watch(
      studioShellProvider.select(
        (state) => (
          canNavigateBack: state.canNavigateBack,
          canNavigateForward: state.canNavigateForward,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const SizedBox(width: 72),
          StudioChromeIconButton(
            tooltip: 'Back',
            onTap: navigation.canNavigateBack
                ? ref.read(studioShellProvider.notifier).navigateBack
                : null,
            icon: StudioIcons.arrowBack,
            width: 24,
            height: 22,
            iconSize: 14,
          ),
          const SizedBox(width: 4),
          StudioChromeIconButton(
            tooltip: 'Forward',
            onTap: navigation.canNavigateForward
                ? ref.read(studioShellProvider.notifier).navigateForward
                : null,
            icon: StudioIcons.arrowForward,
            width: 24,
            height: 22,
            iconSize: 14,
          ),
          const Spacer(),
          StudioChromeIconButton(
            tooltip: 'Open project folder',
            onTap: () => unawaited(chooseStudioProjectRoot(ref)),
            icon: StudioIcons.folderOpenOutlined,
            width: 26,
            height: 24,
            iconSize: 14,
          ),
        ],
      ),
    );
  }
}

Future<void> _createProject(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<_NewProjectResult>(
    context: context,
    builder: (context) => const _NewProjectDialog(),
  );
  if (result == null) return;
  final path = await StudioProjectCreator.createProject(
    name: result.name,
    parentPath: result.parentPath,
  );
  final openResult = await ref
      .read(workspaceSessionProvider.notifier)
      .openWorkspaceAndBindAgent(path);
  if (!openResult.success) return;
  recordBoundStudioWorkspace(ref, requestedPath: path, binding: openResult);
}

class _RailAction extends ConsumerWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _RailAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StudioRailRow(icon: icon, label: label, onTap: onTap);
  }
}

class _NewProjectResult {
  final String name;
  final String parentPath;

  const _NewProjectResult({required this.name, required this.parentPath});
}

class _NewProjectDialog extends ConsumerStatefulWidget {
  const _NewProjectDialog();

  @override
  ConsumerState<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends ConsumerState<_NewProjectDialog> {
  late final TextEditingController _nameController;
  late String _parentPath;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: 'New Circuit project');
    _parentPath = PlatformUtils.defaultProjectsDir;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    return Dialog(
      backgroundColor: tokens.studioPanel,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.xl),
        side: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.46)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: StudioLayoutContract.projectDialogWidth,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Create project',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.base,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                'Name a new folder for this Circuit task.',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                  height: 1.28,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 34,
                child: TextField(
                  controller: _nameController,
                  autofocus: true,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                    height: 1.18,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Project name',
                    labelStyle: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                    ),
                    floatingLabelStyle: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                    ),
                    filled: true,
                    fillColor: tokens.studioControl.withValues(alpha: 0.72),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.lg),
                      borderSide: BorderSide(
                        color: tokens.studioDivider.withValues(alpha: 0.62),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.lg),
                      borderSide: BorderSide(
                        color: tokens.studioDivider.withValues(alpha: 0.62),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.lg),
                      borderSide: BorderSide(
                        color: tokens.outlineFocus.withValues(alpha: 0.76),
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(height: Spacing.md),
              Container(
                padding: const EdgeInsets.fromLTRB(9, 7, 5, 7),
                decoration: BoxDecoration(
                  color: tokens.studioControl.withValues(alpha: 0.56),
                  borderRadius: BorderRadius.circular(Radii.lg),
                  border: Border.all(
                    color: tokens.studioDivider.withValues(alpha: 0.52),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      StudioIcons.folderOutlined,
                      size: 14,
                      color: tokens.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _parentPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: FontSizes.xs,
                          height: 1.2,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _chooseParent,
                      style: _dialogTextButtonStyle(tokens),
                      child: const Text('Change'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: _dialogTextButtonStyle(tokens),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: Spacing.sm),
                  FilledButton(
                    onPressed: _submit,
                    style: _dialogFilledButtonStyle(tokens),
                    child: const Text('Create'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseParent() async {
    final result = await FilePicker.platform.getDirectoryPath(
      initialDirectory: Directory(_parentPath).existsSync()
          ? _parentPath
          : null,
    );
    if (result == null || !mounted) return;
    setState(() => _parentPath = result);
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(
      context,
    ).pop(_NewProjectResult(name: name, parentPath: _parentPath));
  }

  ButtonStyle _dialogTextButtonStyle(ThemeTokens tokens) {
    return TextButton.styleFrom(
      minimumSize: const Size(0, 28),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 0),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: tokens.textMuted,
      textStyle: const TextStyle(
        fontSize: FontSizes.xs,
        height: 1.1,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    );
  }

  ButtonStyle _dialogFilledButtonStyle(ThemeTokens tokens) {
    return FilledButton.styleFrom(
      minimumSize: const Size(0, 28),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: tokens.textPrimary,
      foregroundColor: tokens.bgDark,
      textStyle: const TextStyle(
        fontSize: FontSizes.xs,
        height: 1.1,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    );
  }
}

class _RailSectionLabel extends ConsumerWidget {
  final String label;

  const _RailSectionLabel(this.label);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, Spacing.md, 3),
      child: Text(
        label,
        style: TextStyle(
          color: tokens.textMuted.withValues(alpha: 0.62),
          fontSize: FontSizes.xs,
          fontWeight: FontWeight.w500,
          height: 1.1,
        ),
      ),
    );
  }
}
