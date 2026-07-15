import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../models/test_generation_models.dart';
import '../../state/editor_provider.dart';
import '../../state/test_generation_provider.dart';
import '../../state/theme_provider.dart';
import 'test_preview_dialog.dart';

class TestGenerationPanel extends ConsumerWidget {
  const TestGenerationPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final testState = ref.watch(testGenerationProvider);
    final editorState = ref.watch(editorProvider);
    final activeTab = editorState.activeTab;
    final hasSourceFile =
        activeTab != null && !activeTab.filePath.startsWith('circuit://');

    return Column(
      children: [
        // Header
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Test Generation',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Spacing.lg),
            children: [
              // Source File
              _SectionLabel(label: 'Source File', tokens: tokens),
              const SizedBox(height: Spacing.md),
              Container(
                padding: const EdgeInsets.all(Spacing.lg),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.md),
                  color: tokens.bgDark,
                  border: Border.all(
                    color: tokens.border.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 14,
                      color: hasSourceFile ? tokens.accent : tokens.textMuted,
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Text(
                        hasSourceFile
                            ? p.basename(activeTab.filePath)
                            : 'No file selected',
                        style: TextStyle(
                          color: hasSourceFile
                              ? tokens.textPrimary
                              : tokens.textMuted,
                          fontSize: FontSizes.sm,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: Spacing.xxl),

              // Framework
              _SectionLabel(label: 'Framework', tokens: tokens),
              const SizedBox(height: Spacing.md),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: TestFramework.values.map((fw) {
                  final isSelected = testState.selectedFramework == fw;
                  return GestureDetector(
                    onTap: () => ref
                        .read(testGenerationProvider.notifier)
                        .setFramework(fw),
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
                          fw.displayName,
                          style: TextStyle(
                            color: isSelected
                                ? tokens.accent
                                : tokens.textSecondary,
                            fontSize: FontSizes.xs,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: Spacing.xxl),

              // Options
              _SectionLabel(label: 'Options', tokens: tokens),
              const SizedBox(height: Spacing.md),
              _OptionCheckbox(
                label: 'Include edge cases',
                value: testState.includeEdgeCases,
                onChanged: (v) => ref
                    .read(testGenerationProvider.notifier)
                    .setIncludeEdgeCases(v),
                tokens: tokens,
              ),
              const SizedBox(height: Spacing.sm),
              _OptionCheckbox(
                label: 'Include mocks',
                value: testState.includeMocks,
                onChanged: (v) => ref
                    .read(testGenerationProvider.notifier)
                    .setIncludeMocks(v),
                tokens: tokens,
              ),

              const SizedBox(height: Spacing.xxl),

              // Generate button
              GestureDetector(
                onTap: hasSourceFile && !testState.isGenerating
                    ? () async {
                        await ref
                            .read(testGenerationProvider.notifier)
                            .generate(activeTab.filePath);

                        final result = ref.read(testGenerationProvider).result;
                        if (result != null && context.mounted) {
                          showDialog(
                            context: context,
                            builder: (_) => const TestPreviewDialog(),
                          );
                        }
                      }
                    : null,
                child: MouseRegion(
                  cursor: hasSourceFile && !testState.isGenerating
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.md),
                      color: hasSourceFile
                          ? tokens.accent
                          : tokens.textMuted.withValues(alpha: 0.2),
                    ),
                    alignment: Alignment.center,
                    child: testState.isGenerating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Generate Tests',
                            style: TextStyle(
                              color: hasSourceFile
                                  ? Colors.white
                                  : tokens.textMuted,
                              fontSize: FontSizes.sm,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ),

              // Error
              if (testState.error != null) ...[
                const SizedBox(height: Spacing.lg),
                Text(
                  testState.error!,
                  style: TextStyle(color: tokens.error, fontSize: FontSizes.xs),
                ),
              ],

              // History
              if (testState.history.isNotEmpty) ...[
                const SizedBox(height: Spacing.xxl),
                _SectionLabel(label: 'Recent', tokens: tokens),
                const SizedBox(height: Spacing.md),
                ...testState.history.map(
                  (path) => _HistoryItem(
                    path: path,
                    tokens: tokens,
                    onTap: () =>
                        ref.read(editorProvider.notifier).openFile(path),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final dynamic tokens;
  const _SectionLabel({required this.label, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: tokens.textMuted,
        fontSize: FontSizes.xxs,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.0,
      ),
    );
  }
}

class _OptionCheckbox extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final dynamic tokens;

  const _OptionCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: value
                    ? tokens.accent.withValues(alpha: 0.15)
                    : tokens.bgDark,
                border: Border.all(
                  color: value ? tokens.accent : tokens.border,
                ),
              ),
              child: value
                  ? Icon(Icons.check, size: 12, color: tokens.accent)
                  : null,
            ),
            const SizedBox(width: Spacing.md),
            Text(
              label,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.sm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryItem extends StatefulWidget {
  final String path;
  final dynamic tokens;
  final VoidCallback onTap;

  const _HistoryItem({
    required this.path,
    required this.tokens,
    required this.onTap,
  });

  @override
  State<_HistoryItem> createState() => _HistoryItemState();
}

class _HistoryItemState extends State<_HistoryItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          margin: const EdgeInsets.only(bottom: Spacing.xs),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.sm),
            color: _isHovered
                ? widget.tokens.accent.withValues(alpha: 0.05)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              Icon(
                Icons.description_outlined,
                size: 12,
                color: widget.tokens.textMuted,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  p.basename(widget.path),
                  style: TextStyle(
                    color: _isHovered
                        ? widget.tokens.accent
                        : widget.tokens.textSecondary,
                    fontSize: FontSizes.xs,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
