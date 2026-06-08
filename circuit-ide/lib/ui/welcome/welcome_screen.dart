import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/connection_provider.dart';
import '../../state/theme_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../models/workspace_open_result.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  String? _recentProjectMessage;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final settings = ref.watch(settingsProvider);

    return Container(
      color: tokens.editorBg,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      tokens.accent.withValues(alpha: 0.15),
                      tokens.accent.withValues(alpha: 0.05),
                    ],
                  ),
                  border: Border.all(
                    color: tokens.accent.withValues(alpha: 0.2),
                  ),
                ),
                child: Icon(Icons.memory, size: 32, color: tokens.accent),
              ),
              const SizedBox(height: Spacing.xxl),
              Text(
                'CircuitCode',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.title,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                'AI-Powered Code Editor',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.base,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: Spacing.xxxxl),

              // Quick actions
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _WelcomeAction(
                    icon: Icons.folder_open_outlined,
                    label: 'Open Folder',
                    onTap: () => _openFolder(ref),
                  ),
                  const SizedBox(width: Spacing.xl),
                  _WelcomeAction(
                    icon: Icons.create_new_folder_outlined,
                    label: 'New Folder',
                    onTap: () => _createNewFolder(context, ref),
                  ),
                  const SizedBox(width: Spacing.xl),
                  _WelcomeAction(
                    icon: Icons.add_outlined,
                    label: 'New File',
                    onTap: () {},
                  ),
                  const SizedBox(width: Spacing.xl),
                  _WelcomeAction(
                    icon: Icons.tune_outlined,
                    label: 'Settings',
                    onTap: () =>
                        ref.read(editorProvider.notifier).openSettingsTab(),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.xxxxl),

              // Recent projects
              if (settings.recentProjects.isNotEmpty) ...[
                if (_recentProjectMessage != null) ...[
                  _RecentProjectNotice(message: _recentProjectMessage!),
                  const SizedBox(height: Spacing.md),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'RECENT',
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.lg),
                    border: Border.all(
                      color: tokens.border.withValues(alpha: 0.5),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: settings.recentProjects
                        .take(5)
                        .toList()
                        .asMap()
                        .entries
                        .map((entry) {
                          final path = entry.value;
                          final isLast =
                              entry.key ==
                              settings.recentProjects.take(5).length - 1;
                          return _RecentProjectItem(
                            path: path,
                            showBorder: !isLast,
                            onRemove: () => _removeRecentProject(path),
                            onTap: () => _openRecentProject(path),
                          );
                        })
                        .toList(),
                  ),
                ),
              ],

              const SizedBox(height: Spacing.xxxl),

              // Keyboard shortcuts
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ShortcutChip(keys: '\u2318\u21E7P', label: 'Commands'),
                  SizedBox(width: Spacing.xl),
                  _ShortcutChip(keys: '\u2318`', label: 'Terminal'),
                  SizedBox(width: Spacing.xl),
                  _ShortcutChip(keys: '\u2318B', label: 'Sidebar'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createNewFolder(BuildContext context, WidgetRef ref) async {
    final tokens = ref.read(themeProvider);
    final controller = TextEditingController();

    final folderName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.bgLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: tokens.border),
        ),
        title: Text(
          'New Folder',
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: FontSizes.lg,
            fontWeight: FontWeight.w500,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Created in ~/Documents',
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
            ),
            const SizedBox(height: Spacing.lg),
            TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: FontSizes.sm,
              ),
              decoration: InputDecoration(
                hintText: 'my-project',
                hintStyle: TextStyle(color: tokens.textMuted),
                filled: true,
                fillColor: tokens.editorBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.md),
                  borderSide: BorderSide(color: tokens.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.md),
                  borderSide: BorderSide(color: tokens.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.md),
                  borderSide: BorderSide(color: tokens.accent),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: Spacing.lg,
                  vertical: Spacing.md,
                ),
              ),
              onSubmitted: (value) => Navigator.of(ctx).pop(value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: tokens.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text('Create', style: TextStyle(color: tokens.accent)),
          ),
        ],
      ),
    );

    if (folderName == null || folderName.trim().isEmpty) return;

    final documentsDir = '${Platform.environment['HOME']}/Documents';
    final newPath = '$documentsDir/${folderName.trim()}';
    final dir = Directory(newPath);

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    await _openWorkspacePath(newPath, addToRecents: true);
  }

  Future<void> _openFolder(WidgetRef ref) async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      await _openWorkspacePath(result, addToRecents: true);
    }
  }

  Future<void> _openRecentProject(String path) async {
    await _openWorkspacePath(path, addToRecents: true, fromRecent: true);
  }

  Future<void> _openWorkspacePath(
    String path, {
    required bool addToRecents,
    bool fromRecent = false,
  }) async {
    final result = await ref
        .read(fileTreeProvider.notifier)
        .openDirectory(path);
    if (!mounted) return;

    if (!result.success) {
      if (fromRecent &&
          result.recentProjectStatus == RecentProjectStatus.missing) {
        ref.read(settingsProvider.notifier).removeRecentProject(path);
      }
      setState(() {
        _recentProjectMessage =
            '${result.message ?? "Could not open project"} ${fromRecent ? "It was removed from Recent." : ""}'
                .trim();
      });
      return;
    }

    setState(() => _recentProjectMessage = null);
    if (addToRecents) {
      ref.read(settingsProvider.notifier).addRecentProject(path);
    }
    final service = ref.read(agentServiceProvider);
    if (service.isConnected) {
      await service.updateWorkingDir(path);
    }
  }

  void _removeRecentProject(String path) {
    ref.read(settingsProvider.notifier).removeRecentProject(path);
    setState(() => _recentProjectMessage = null);
  }
}

class _RecentProjectNotice extends ConsumerWidget {
  final String message;

  const _RecentProjectNotice({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.md,
      ),
      decoration: BoxDecoration(
        color: tokens.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.warning.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: tokens.warning),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeAction extends ConsumerStatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _WelcomeAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  ConsumerState<_WelcomeAction> createState() => _WelcomeActionState();
}

class _WelcomeActionState extends ConsumerState<_WelcomeAction> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AnimationDurations.normal,
          curve: AnimationCurves.snappy,
          width: 120,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.xl,
            vertical: Spacing.xxl,
          ),
          decoration: BoxDecoration(
            color: _isHovered
                ? tokens.accent.withValues(alpha: 0.06)
                : tokens.bgLight.withValues(alpha: 0.5),
            border: Border.all(
              color: _isHovered
                  ? tokens.accent.withValues(alpha: 0.3)
                  : tokens.border.withValues(alpha: 0.5),
            ),
            borderRadius: BorderRadius.circular(Radii.xl),
            boxShadow: _isHovered ? Shadows.medium : null,
          ),
          child: Column(
            children: [
              Icon(
                widget.icon,
                size: 24,
                color: _isHovered ? tokens.accent : tokens.textSecondary,
              ),
              const SizedBox(height: Spacing.lg),
              Text(
                widget.label,
                style: TextStyle(
                  color: _isHovered ? tokens.textPrimary : tokens.textSecondary,
                  fontSize: FontSizes.sm,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentProjectItem extends ConsumerStatefulWidget {
  final String path;
  final bool showBorder;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _RecentProjectItem({
    required this.path,
    required this.showBorder,
    required this.onTap,
    required this.onRemove,
  });

  @override
  ConsumerState<_RecentProjectItem> createState() => _RecentProjectItemState();
}

class _RecentProjectItemState extends ConsumerState<_RecentProjectItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final name = widget.path.split('/').last;
    final dir = widget.path.substring(0, widget.path.length - name.length);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.xl,
          vertical: Spacing.lg,
        ),
        decoration: BoxDecoration(
          color: _isHovered
              ? tokens.accent.withValues(alpha: 0.04)
              : Colors.transparent,
          border: widget.showBorder
              ? Border(
                  bottom: BorderSide(
                    color: tokens.border.withValues(alpha: 0.3),
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 15,
                      color: _isHovered ? tokens.accent : tokens.textMuted,
                    ),
                    const SizedBox(width: Spacing.lg),
                    Text(
                      name,
                      style: TextStyle(
                        color: _isHovered ? tokens.accent : tokens.textPrimary,
                        fontSize: FontSizes.sm,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Text(
                        dir,
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FontSizes.xs,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_isHovered)
              IconButton(
                tooltip: 'Remove from Recent',
                onPressed: widget.onRemove,
                icon: Icon(Icons.close, size: 13, color: tokens.textMuted),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutChip extends ConsumerWidget {
  final String keys;
  final String label;

  const _ShortcutChip({required this.keys, required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: tokens.bgLight,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: tokens.border.withValues(alpha: 0.6)),
          ),
          child: Text(
            keys,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
        ),
      ],
    );
  }
}
