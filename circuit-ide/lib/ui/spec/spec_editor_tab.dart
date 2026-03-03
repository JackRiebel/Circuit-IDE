import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/spec_models.dart';
import '../../state/spec_provider.dart';
import '../../state/theme_provider.dart';
import 'spec_execution_widget.dart';

class SpecEditorTab extends ConsumerStatefulWidget {
  final String specId;

  const SpecEditorTab({super.key, required this.specId});

  @override
  ConsumerState<SpecEditorTab> createState() => _SpecEditorTabState();
}

class _SpecEditorTabState extends ConsumerState<SpecEditorTab> {
  final _contentController = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final spec = ref.watch(specProvider);

    // Initialize spec if not exists
    if (spec == null && !_initialized) {
      _initialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(specProvider.notifier).createSpec('Specification');
      });
      return Center(
        child: CircularProgressIndicator(color: tokens.accent),
      );
    }

    if (spec == null) {
      return Center(
        child: CircularProgressIndicator(color: tokens.accent),
      );
    }

    // Sync controller with spec content
    if (_contentController.text != spec.content && !_contentController.text.isNotEmpty) {
      _contentController.text = spec.content;
    }

    return Container(
      color: tokens.editorBg,
      child: Column(
        children: [
          // Header bar
          _SpecHeader(spec: spec),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Spacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Spec content editor
                  _SpecContentEditor(
                    controller: _contentController,
                    enabled: spec.status == SpecStatus.draft,
                    tokens: tokens,
                    onChanged: (value) {
                      ref.read(specProvider.notifier).updateContent(value);
                    },
                  ),

                  // Steps section (appears after planning)
                  if (spec.steps.isNotEmpty) ...[
                    const SizedBox(height: Spacing.xxl),
                    const SpecExecutionWidget(),
                  ],

                  // Summary (after completion)
                  if (spec.status == SpecStatus.completed) ...[
                    const SizedBox(height: Spacing.xxl),
                    _CompletionSummary(spec: spec, tokens: tokens),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecHeader extends ConsumerWidget {
  final Spec spec;
  const _SpecHeader({required this.spec});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
      decoration: BoxDecoration(
        color: tokens.bgLighter,
        border: Border(
          bottom: BorderSide(color: tokens.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 16, color: tokens.accent),
          const SizedBox(width: Spacing.md),
          Text(
            spec.name,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: FontSizes.sm,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: Spacing.lg),
          _StatusBadge(status: spec.status, tokens: tokens),
          if (spec.steps.isNotEmpty) ...[
            const SizedBox(width: Spacing.lg),
            Text(
              '${spec.completedCount}/${spec.steps.length} steps',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xs,
              ),
            ),
          ],
          const Spacer(),

          // Action buttons
          if (spec.status == SpecStatus.draft)
            _ActionButton(
              label: 'Generate Plan',
              icon: Icons.auto_fix_high,
              color: tokens.accent,
              onTap: () => ref.read(specProvider.notifier).generatePlan(),
            ),
          if (spec.status == SpecStatus.ready)
            _ActionButton(
              label: 'Execute',
              icon: Icons.play_arrow,
              color: tokens.success,
              onTap: () => ref.read(specProvider.notifier).execute(),
            ),
          if (spec.status == SpecStatus.executing)
            _ActionButton(
              label: 'Pause',
              icon: Icons.pause,
              color: tokens.warning,
              onTap: () => ref.read(specProvider.notifier).pauseExecution(),
            ),
          if (spec.status == SpecStatus.planning)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: tokens.accent,
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final SpecStatus status;
  final dynamic tokens;
  const _StatusBadge({required this.status, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      SpecStatus.draft => ('Draft', tokens.textMuted as Color),
      SpecStatus.planning => ('Planning...', tokens.accent as Color),
      SpecStatus.ready => ('Ready', tokens.accent as Color),
      SpecStatus.executing => ('Executing', tokens.warning as Color),
      SpecStatus.completed => ('Completed', tokens.success as Color),
      SpecStatus.failed => ('Failed', tokens.error as Color),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: FontSizes.xxs,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.sm),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: Spacing.sm),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpecContentEditor extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final dynamic tokens;
  final ValueChanged<String> onChanged;

  const _SpecContentEditor({
    required this.controller,
    required this.enabled,
    required this.tokens,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 200),
      decoration: BoxDecoration(
        color: tokens.bgLighter,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.border),
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        maxLines: null,
        onChanged: onChanged,
        style: TextStyle(
          color: tokens.textPrimary,
          fontSize: FontSizes.sm,
          fontFamily: EditorDefaults.fontFamily,
          height: 1.6,
        ),
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.all(Spacing.xl),
          hintText: 'Write your specification here...\n\n'
              'Describe what you want to build, including:\n'
              '- Feature requirements\n'
              '- Technical constraints\n'
              '- Expected behavior',
          hintStyle: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.sm,
          ),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class _CompletionSummary extends StatelessWidget {
  final Spec spec;
  final dynamic tokens;

  const _CompletionSummary({required this.spec, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.xl),
      decoration: BoxDecoration(
        color: tokens.success.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.success.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, size: 16, color: tokens.success),
              const SizedBox(width: Spacing.md),
              Text(
                'Specification Complete',
                style: TextStyle(
                  color: tokens.success,
                  fontSize: FontSizes.sm,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          Text(
            '${spec.completedCount} of ${spec.steps.length} steps completed',
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.xs,
            ),
          ),
        ],
      ),
    );
  }
}
