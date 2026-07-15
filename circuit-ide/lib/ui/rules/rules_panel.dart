import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/context/rules_loader.dart';
import '../../core/constants/design_tokens.dart';
import '../../state/rules_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/theme_provider.dart';
import 'pattern_editor_widget.dart';

class RulesPanel extends ConsumerStatefulWidget {
  const RulesPanel({super.key});

  @override
  ConsumerState<RulesPanel> createState() => _RulesPanelState();
}

class _RulesPanelState extends ConsumerState<RulesPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rulesProvider.notifier).loadRules();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final rulesState = ref.watch(rulesProvider);
    final hasProject = ref.watch(fileTreeProvider).rootPath != null;

    if (!hasProject) {
      return Center(
        child: Text(
          'Open a project to manage rules',
          style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
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
                  'Project Rules',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _ToolbarBtn(
                icon: Icons.add,
                tooltip: 'New Rule',
                onTap: () => _showRuleEditor(context, ref),
              ),
              _ToolbarBtn(
                icon: Icons.refresh,
                tooltip: 'Refresh',
                onTap: () => ref.read(rulesProvider.notifier).loadRules(),
              ),
            ],
          ),
        ),

        // Rules list
        Expanded(
          child: rulesState.isLoading
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
              : rulesState.rules.isEmpty
              ? _EmptyState(tokens: tokens)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                  itemCount: rulesState.rules.length,
                  itemBuilder: (context, index) {
                    return _RuleItem(
                      rule: rulesState.rules[index],
                      onEdit: () => _showRuleEditor(
                        context,
                        ref,
                        rulesState.rules[index],
                      ),
                      onDelete: () =>
                          _confirmDelete(context, ref, rulesState.rules[index]),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showRuleEditor(
    BuildContext context,
    WidgetRef ref, [
    ProjectRule? existing,
  ]) {
    showDialog(
      context: context,
      builder: (ctx) => _RuleEditorDialog(existing: existing),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, ProjectRule rule) {
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
          'Delete Rule',
          style: TextStyle(color: tokens.textPrimary, fontSize: FontSizes.lg),
        ),
        content: Text(
          'Delete "${rule.name}"? This cannot be undone.',
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
              ref.read(rulesProvider.notifier).deleteRule(rule);
              Navigator.of(ctx).pop();
            },
            child: Text('Delete', style: TextStyle(color: tokens.error)),
          ),
        ],
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
            child: Icon(Icons.rule_outlined, size: 22, color: tokens.textMuted),
          ),
          const SizedBox(height: Spacing.xl),
          Text(
            'No rules defined',
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.md,
            ),
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'Rules guide the AI agent\'s behavior\nfor this project.',
            textAlign: TextAlign.center,
            style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
          ),
        ],
      ),
    );
  }
}

class _RuleItem extends ConsumerStatefulWidget {
  final ProjectRule rule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RuleItem({
    required this.rule,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  ConsumerState<_RuleItem> createState() => _RuleItemState();
}

class _RuleItemState extends ConsumerState<_RuleItem> {
  bool _isHovered = false;
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.xs,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.md),
          color: _isHovered
              ? tokens.accent.withValues(alpha: 0.04)
              : Colors.transparent,
          border: Border.all(
            color: _isHovered
                ? tokens.accent.withValues(alpha: 0.2)
                : tokens.border.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 14,
                      color: tokens.accent,
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.rule.name,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: FontSizes.sm,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (widget.rule.patterns.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Wrap(
                              spacing: 4,
                              runSpacing: 2,
                              children: widget.rule.patterns
                                  .map(
                                    (p) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(3),
                                        color: tokens.accent.withValues(
                                          alpha: 0.1,
                                        ),
                                      ),
                                      child: Text(
                                        p,
                                        style: TextStyle(
                                          color: tokens.accent,
                                          fontSize: FontSizes.xxs - 1,
                                          fontFamily: 'JetBrains Mono',
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_isHovered) ...[
                      _SmallIconBtn(
                        icon: Icons.edit_outlined,
                        onTap: widget.onEdit,
                        tokens: tokens,
                      ),
                      const SizedBox(width: 4),
                      _SmallIconBtn(
                        icon: Icons.delete_outline,
                        onTap: widget.onDelete,
                        tokens: tokens,
                        isDestructive: true,
                      ),
                    ],
                    const SizedBox(width: Spacing.sm),
                    Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 14,
                      color: tokens.textMuted,
                    ),
                  ],
                ),
              ),
            ),
            if (_isExpanded)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                  Spacing.xl,
                  0,
                  Spacing.lg,
                  Spacing.lg,
                ),
                child: Text(
                  widget.rule.content,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    height: 1.5,
                  ),
                  maxLines: 20,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SmallIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final dynamic tokens;
  final bool isDestructive;

  const _SmallIconBtn({
    required this.icon,
    required this.onTap,
    required this.tokens,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Icon(
          icon,
          size: 13,
          color: isDestructive
              ? (tokens.error as Color).withValues(alpha: 0.7)
              : tokens.textMuted,
        ),
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

class _RuleEditorDialog extends ConsumerStatefulWidget {
  final ProjectRule? existing;

  const _RuleEditorDialog({this.existing});

  @override
  ConsumerState<_RuleEditorDialog> createState() => _RuleEditorDialogState();
}

class _RuleEditorDialogState extends ConsumerState<_RuleEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _contentController;
  List<String> _patterns = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _contentController = TextEditingController(
      text: widget.existing?.content ?? '',
    );
    _patterns = List<String>.from(widget.existing?.patterns ?? []);
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
        isNew ? 'New Rule' : 'Edit Rule',
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
                color: tokens.textPrimary,
                fontSize: FontSizes.sm,
              ),
              decoration: _inputDecoration(tokens, 'e.g., coding-style'),
            ),
            const SizedBox(height: Spacing.xl),
            PatternEditorWidget(
              patterns: _patterns,
              onChanged: (p) => setState(() => _patterns = p),
            ),
            const SizedBox(height: Spacing.xl),
            Text(
              'Content (Markdown)',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            SizedBox(
              height: 200,
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
                  'Write rules that guide the AI agent...\n\n'
                  'Example:\n'
                  '- Always use const constructors\n'
                  '- Follow the existing naming conventions\n'
                  '- Add doc comments to public APIs',
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: tokens.textSecondary)),
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

    // Sanitize name for filename
    final safeName = name.replaceAll(RegExp(r'[^\w\-]'), '-').toLowerCase();
    ref
        .read(rulesProvider.notifier)
        .saveRule(safeName, content, patterns: _patterns);
    Navigator.of(context).pop();
  }
}
