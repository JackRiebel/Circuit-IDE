import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/context/memories_loader.dart';
import '../../core/constants/design_tokens.dart';
import '../../state/memories_provider.dart';
import '../../state/theme_provider.dart';

class MemoryEditorDialog extends ConsumerStatefulWidget {
  final Memory? existing;

  const MemoryEditorDialog({super.key, this.existing});

  @override
  ConsumerState<MemoryEditorDialog> createState() =>
      _MemoryEditorDialogState();
}

class _MemoryEditorDialogState extends ConsumerState<MemoryEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _contentController;
  bool _isGlobal = false;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.existing?.name ?? '');
    _contentController =
        TextEditingController(text: widget.existing?.content ?? '');
    _isGlobal = widget.existing?.isGlobal ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final isNew = widget.existing == null;

    return AlertDialog(
      backgroundColor: tokens.bgMain,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: tokens.border),
      ),
      title: Text(
        isNew ? 'New Memory' : 'Edit Memory',
        style: TextStyle(color: tokens.textPrimary, fontSize: FontSizes.lg),
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Name',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: TextStyle(
                  color: tokens.textPrimary, fontSize: FontSizes.sm),
              decoration: _inputDecoration(tokens, 'e.g., coding-preferences'),
            ),
            const SizedBox(height: Spacing.xl),
            Text(
              'Content',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            SizedBox(
              height: 160,
              child: TextField(
                controller: _contentController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.sm,
                  fontFamily: 'JetBrains Mono',
                  height: 1.5,
                ),
                decoration: _inputDecoration(
                  tokens,
                  'What should the AI remember?\n\n'
                      'Examples:\n'
                      '- Prefers const constructors\n'
                      '- Uses Riverpod for state management\n'
                      '- Project follows clean architecture',
                ),
              ),
            ),
            const SizedBox(height: Spacing.xl),
            Row(
              children: [
                Text(
                  'Scope',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                _ScopeChip(
                  label: 'Project',
                  isSelected: !_isGlobal,
                  onTap: () => setState(() => _isGlobal = false),
                  tokens: tokens,
                ),
                const SizedBox(width: Spacing.md),
                _ScopeChip(
                  label: 'Global',
                  isSelected: _isGlobal,
                  onTap: () => setState(() => _isGlobal = true),
                  tokens: tokens,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child:
              Text('Cancel', style: TextStyle(color: tokens.textSecondary)),
        ),
        TextButton(
          onPressed: _save,
          child: Text(
            isNew ? 'Create' : 'Save',
            style: TextStyle(color: tokens.accent),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(dynamic tokens, String hint) {
    return InputDecoration(
      filled: true,
      fillColor: tokens.bgDark,
      hintText: hint,
      hintStyle: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
      contentPadding: const EdgeInsets.all(Spacing.lg),
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
    );
  }

  void _save() {
    final name = _nameController.text.trim();
    final content = _contentController.text.trim();
    if (name.isEmpty || content.isEmpty) return;

    final safeName =
        name.replaceAll(RegExp(r'[^\w\-]'), '-').toLowerCase();
    ref.read(memoriesProvider.notifier).saveMemory(
          safeName,
          content,
          global: _isGlobal,
        );
    Navigator.of(context).pop();
  }
}

class _ScopeChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final dynamic tokens;

  const _ScopeChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.sm),
            color: isSelected
                ? tokens.accent.withValues(alpha: 0.15)
                : tokens.bgDark,
            border: Border.all(
              color: isSelected
                  ? tokens.accent.withValues(alpha: 0.4)
                  : tokens.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? tokens.accent : tokens.textSecondary,
              fontSize: FontSizes.xs,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
