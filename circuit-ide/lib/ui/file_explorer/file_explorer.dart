import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../models/file_node.dart';
import '../../state/chat_provider.dart';
import '../../state/connection_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/theme_provider.dart';
import '../../state/settings_provider.dart';
import 'file_tree_item.dart';
import 'new_file_dialog.dart';

class FileExplorer extends ConsumerWidget {
  const FileExplorer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fileTree = ref.watch(fileTreeProvider);
    final tokens = ref.watch(themeProvider);

    if (fileTree.rootPath == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.xl),
                color: tokens.textMuted.withValues(alpha: 0.06),
              ),
              child: Icon(
                Icons.folder_open_outlined,
                size: 22,
                color: tokens.textMuted,
              ),
            ),
            const SizedBox(height: Spacing.xl),
            Text(
              'No folder opened',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.md,
              ),
            ),
            const SizedBox(height: Spacing.xl),
            SizedBox(
              height: 32,
              child: ElevatedButton.icon(
                onPressed: () => _openFolder(ref),
                icon: const Icon(Icons.folder_open_outlined, size: 14),
                label: const Text('Open Folder'),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Toolbar
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  fileTree.rootPath!.split('/').last,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _ToolbarButton(
                icon: Icons.note_add_outlined,
                tooltip: 'New File',
                onTap: () => _showNewFileDialog(context, ref, false),
              ),
              _ToolbarButton(
                icon: Icons.create_new_folder_outlined,
                tooltip: 'New Folder',
                onTap: () => _showNewFileDialog(context, ref, true),
              ),
              _ToolbarButton(
                icon: Icons.refresh,
                tooltip: 'Refresh',
                onTap: () => ref.read(fileTreeProvider.notifier).refresh(),
              ),
            ],
          ),
        ),

        // File tree
        Expanded(
          child: fileTree.isLoading
              ? Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: tokens.accent,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: fileTree.nodes.length,
                  itemBuilder: (context, index) {
                    final node = fileTree.nodes[index];
                    return FileTreeItem(
                      node: node,
                      onTap: () {
                        if (node.isDirectory) {
                          ref
                              .read(fileTreeProvider.notifier)
                              .toggleExpand(node);
                        } else {
                          ref.read(editorProvider.notifier).openFile(node.path);
                        }
                      },
                      onSecondaryTap: (position) =>
                          _showContextMenu(context, ref, node, position),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _openFolder(WidgetRef ref) async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      final opened = await ref
          .read(fileTreeProvider.notifier)
          .openDirectory(result);
      if (!opened.success) return;
      ref.read(settingsProvider.notifier).addRecentProject(result);
      // Reconnect agent with new working directory
      final service = ref.read(agentServiceProvider);
      if (service.isConnected) {
        await service.updateWorkingDir(result);
      }
    }
  }

  void _showNewFileDialog(
    BuildContext context,
    WidgetRef ref,
    bool isDirectory, [
    String? rootPath,
  ]) {
    showDialog(
      context: context,
      builder: (context) => NewFileDialog(
        rootPath: rootPath ?? ref.read(fileTreeProvider).rootPath!,
        initialIsDirectory: isDirectory,
      ),
    );
  }

  void _showContextMenu(
    BuildContext context,
    WidgetRef ref,
    FileNode node,
    Offset position,
  ) async {
    final tokens = ref.read(themeProvider);

    final items = <PopupMenuEntry<String>>[
      if (!node.isDirectory)
        _menuItem('open', Icons.open_in_new, 'Open', tokens),
      if (node.isDirectory) ...[
        _menuItem('new_file', Icons.note_add_outlined, 'New File', tokens),
        _menuItem(
          'new_folder',
          Icons.create_new_folder_outlined,
          'New Folder',
          tokens,
        ),
        const PopupMenuDivider(height: 8),
      ],
      if (!node.isDirectory) ...[
        _menuItem(
          'generate_tests',
          Icons.science_outlined,
          'Generate Tests',
          tokens,
        ),
        const PopupMenuDivider(height: 8),
      ],
      _menuItem('rename', Icons.edit_outlined, 'Rename', tokens),
      _menuItem('delete', Icons.delete_outline, 'Delete', tokens),
      const PopupMenuDivider(height: 8),
      _menuItem('copy_path', Icons.copy, 'Copy Path', tokens),
      _menuItem(
        'reveal',
        Icons.folder_open_outlined,
        'Reveal in Finder',
        tokens,
      ),
    ];

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: tokens.bgLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: tokens.border.withValues(alpha: 0.5)),
      ),
      items: items,
    );

    if (result == null || !context.mounted) return;

    switch (result) {
      case 'open':
        ref.read(editorProvider.notifier).openFile(node.path);
      case 'new_file':
        final parent = node.isDirectory ? node.path : p.dirname(node.path);
        _showNewFileDialog(context, ref, false, parent);
      case 'new_folder':
        final parent = node.isDirectory ? node.path : p.dirname(node.path);
        _showNewFileDialog(context, ref, true, parent);
      case 'generate_tests':
        _generateTests(ref, node);
      case 'rename':
        _showRenameDialog(context, ref, node);
      case 'delete':
        _showDeleteDialog(context, ref, node);
      case 'copy_path':
        Clipboard.setData(ClipboardData(text: node.path));
      case 'reveal':
        Process.run('open', ['-R', node.path]);
    }
  }

  void _generateTests(WidgetRef ref, FileNode node) {
    final relativePath = node.path.replaceFirst(
      '${ref.read(fileTreeProvider).rootPath}/',
      '',
    );
    ref
        .read(chatProvider.notifier)
        .sendMessage(
          'Read the file "$relativePath" and generate comprehensive tests for it. '
          'Use the appropriate testing framework for the language. '
          'Create the test file in a logical location following project conventions. '
          'Cover edge cases, error handling, and key business logic.',
        );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
    dynamic tokens,
  ) {
    return PopupMenuItem<String>(
      value: value,
      height: 32,
      child: Row(
        children: [
          Icon(icon, size: 14, color: tokens.textSecondary),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: tokens.textPrimary, fontSize: FontSizes.sm),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, FileNode node) {
    final controller = TextEditingController(text: node.name);
    final tokens = ref.read(themeProvider);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.bgMain,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: tokens.border),
        ),
        title: Text(
          'Rename',
          style: TextStyle(color: tokens.textPrimary, fontSize: FontSizes.lg),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: tokens.textPrimary, fontSize: FontSizes.sm),
          decoration: InputDecoration(
            filled: true,
            fillColor: tokens.bgDark,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.sm),
              borderSide: BorderSide(color: tokens.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.sm),
              borderSide: BorderSide(color: tokens.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.sm),
              borderSide: BorderSide(color: tokens.accent),
            ),
          ),
          onSubmitted: (value) async {
            if (value.isNotEmpty && value != node.name) {
              await ref.read(fileTreeProvider.notifier).renameNode(node, value);
            }
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: tokens.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              final value = controller.text;
              if (value.isNotEmpty && value != node.name) {
                await ref
                    .read(fileTreeProvider.notifier)
                    .renameNode(node, value);
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text('Rename', style: TextStyle(color: tokens.accent)),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref, FileNode node) {
    final tokens = ref.read(themeProvider);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.bgMain,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: tokens.border),
        ),
        title: Text(
          'Delete ${node.isDirectory ? 'Folder' : 'File'}',
          style: TextStyle(color: tokens.textPrimary, fontSize: FontSizes.lg),
        ),
        content: Text(
          'Are you sure you want to delete "${node.name}"?'
          '${node.isDirectory ? ' This will delete all contents.' : ''}',
          style: TextStyle(color: tokens.textSecondary, fontSize: FontSizes.sm),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: tokens.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(fileTreeProvider.notifier).deleteNode(node);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text('Delete', style: TextStyle(color: tokens.error)),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends ConsumerStatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  ConsumerState<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends ConsumerState<_ToolbarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AnimationDurations.fast,
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.sm),
              color: _isHovered
                  ? tokens.textMuted.withValues(alpha: 0.1)
                  : Colors.transparent,
            ),
            child: Icon(
              widget.icon,
              size: 15,
              color: _isHovered ? tokens.textPrimary : tokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
