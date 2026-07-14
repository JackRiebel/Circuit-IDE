import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/context/memories_loader.dart';
import '../../core/constants/design_tokens.dart';
import '../../state/memories_provider.dart';
import '../../state/theme_provider.dart';
import 'memory_editor_dialog.dart';
import 'memory_item.dart';

class MemoriesPanel extends ConsumerStatefulWidget {
  const MemoriesPanel({super.key});

  @override
  ConsumerState<MemoriesPanel> createState() => _MemoriesPanelState();
}

class _MemoriesPanelState extends ConsumerState<MemoriesPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(memoriesProvider.notifier).loadMemories();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final memoriesState = ref.watch(memoriesProvider);

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
                  'AI Memories',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _ToolbarBtn(
                icon: Icons.add,
                tooltip: 'New Memory',
                onTap: () => _showMemoryEditor(context),
              ),
              _ToolbarBtn(
                icon: Icons.refresh,
                tooltip: 'Refresh',
                onTap: () => ref.read(memoriesProvider.notifier).loadMemories(),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.xs,
            Spacing.lg,
            Spacing.sm,
          ),
          child: Text(
            'Instructions stay in the Context drawer. This view contains durable user-authored or reviewed learned notes; editor, selection, and terminal context are turn-only.',
            style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xxs),
          ),
        ),

        // Memories list
        Expanded(
          child: memoriesState.isLoading
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
              : memoriesState.memories.isEmpty
              ? _EmptyState(tokens: tokens)
              : _MemoriesList(
                  memories: memoriesState.memories,
                  onEdit: (m) => _showMemoryEditor(context, m),
                  onDelete: (m) => _confirmDelete(context, m),
                ),
        ),
      ],
    );
  }

  void _showMemoryEditor(BuildContext context, [Memory? existing]) {
    showDialog(
      context: context,
      builder: (ctx) => MemoryEditorDialog(existing: existing),
    );
  }

  void _confirmDelete(BuildContext context, Memory memory) {
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
          'Delete Memory',
          style: TextStyle(color: tokens.textPrimary, fontSize: FontSizes.lg),
        ),
        content: Text(
          'Delete "${memory.name}"? This cannot be undone.',
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
            onPressed: () {
              ref.read(memoriesProvider.notifier).deleteMemory(memory);
              Navigator.of(ctx).pop();
            },
            child: Text('Delete', style: TextStyle(color: tokens.error)),
          ),
        ],
      ),
    );
  }
}

class _MemoriesList extends StatelessWidget {
  final List<Memory> memories;
  final void Function(Memory) onEdit;
  final void Function(Memory) onDelete;

  const _MemoriesList({
    required this.memories,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // Group by scope
    final global = memories.where((m) => m.isGlobal).toList();
    final project = memories.where((m) => !m.isGlobal).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
      children: [
        if (project.isNotEmpty) ...[
          _SectionHeader(label: 'Project Memories (${project.length})'),
          ...project.map(
            (m) => MemoryItem(
              key: ValueKey(m.filePath),
              memory: m,
              onEdit: () => onEdit(m),
              onDelete: () => onDelete(m),
            ),
          ),
        ],
        if (global.isNotEmpty) ...[
          if (project.isNotEmpty) const SizedBox(height: Spacing.lg),
          _SectionHeader(label: 'Global Memories (${global.length})'),
          ...global.map(
            (m) => MemoryItem(
              key: ValueKey(m.filePath),
              memory: m,
              onEdit: () => onEdit(m),
              onDelete: () => onDelete(m),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends ConsumerWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.xl,
        Spacing.sm,
        Spacing.lg,
        Spacing.sm,
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: tokens.textMuted,
          fontSize: FontSizes.xxs,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final dynamic tokens;
  const _EmptyState({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.xl),
              color: (tokens.textMuted as Color).withValues(alpha: 0.06),
            ),
            child: Icon(
              Icons.auto_awesome_outlined,
              size: 22,
              color: tokens.textMuted,
            ),
          ),
          const SizedBox(height: Spacing.xl),
          Text(
            'No memories yet',
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.md,
            ),
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'Memories help the AI learn your\npreferences across sessions.',
            textAlign: TextAlign.center,
            style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
          ),
        ],
      ),
    );
  }
}

class _ToolbarBtn extends ConsumerStatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ToolbarBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  ConsumerState<_ToolbarBtn> createState() => _ToolbarBtnState();
}

class _ToolbarBtnState extends ConsumerState<_ToolbarBtn> {
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
          child: Container(
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
