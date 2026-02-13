import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/file_tree_provider.dart';
import '../../state/theme_provider.dart';

class NewFileDialog extends ConsumerStatefulWidget {
  final String rootPath;
  final bool initialIsDirectory;

  const NewFileDialog({
    super.key,
    required this.rootPath,
    this.initialIsDirectory = false,
  });

  @override
  ConsumerState<NewFileDialog> createState() => _NewFileDialogState();
}

class _NewFileDialogState extends ConsumerState<NewFileDialog> {
  final _controller = TextEditingController();
  late bool _isDirectory = widget.initialIsDirectory;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(Spacing.xxl),
        decoration: BoxDecoration(
          color: tokens.bgLight,
          borderRadius: BorderRadius.circular(Radii.xl),
          border: Border.all(color: tokens.border),
          boxShadow: Shadows.elevated,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isDirectory ? 'New Folder' : 'New File',
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: FontSizes.xl,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: Spacing.xxl),

            // Type selector
            Container(
              height: 32,
              decoration: BoxDecoration(
                color: tokens.bgDark,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: tokens.border.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _TypeTab(
                      label: 'File',
                      icon: Icons.description_outlined,
                      isActive: !_isDirectory,
                      onTap: () => setState(() => _isDirectory = false),
                    ),
                  ),
                  Expanded(
                    child: _TypeTab(
                      label: 'Folder',
                      icon: Icons.folder_outlined,
                      isActive: _isDirectory,
                      onTap: () => setState(() => _isDirectory = true),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.xl),

            // Name input
            SizedBox(
              height: 36,
              child: TextField(
                controller: _controller,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.base,
                ),
                decoration: InputDecoration(
                  hintText: _isDirectory ? 'folder-name' : 'filename.ext',
                  prefixIcon: Icon(
                    _isDirectory
                        ? Icons.folder_outlined
                        : Icons.description_outlined,
                    size: 16,
                    color: tokens.textMuted,
                  ),
                ),
                onSubmitted: (_) => _create(),
              ),
            ),
            const SizedBox(height: Spacing.xxl),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  height: 32,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: FontSizes.md,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                SizedBox(
                  height: 32,
                  child: ElevatedButton(
                    onPressed: _create,
                    child: const Text('Create'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _create() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;

    if (_isDirectory) {
      ref
          .read(fileTreeProvider.notifier)
          .createDirectory(widget.rootPath, name);
    } else {
      ref.read(fileTreeProvider.notifier).createFile(widget.rootPath, name);
    }
    Navigator.pop(context);
  }
}

class _TypeTab extends ConsumerWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _TypeTab({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: AnimationDurations.fast,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isActive ? tokens.accent.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isActive ? tokens.accent : tokens.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? tokens.accent : tokens.textMuted,
                  fontSize: FontSizes.sm,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
