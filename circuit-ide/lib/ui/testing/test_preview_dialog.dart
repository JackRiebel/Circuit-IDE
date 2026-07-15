import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/design_tokens.dart';
import '../../state/test_generation_provider.dart';
import '../../state/theme_provider.dart';

class TestPreviewDialog extends ConsumerStatefulWidget {
  const TestPreviewDialog({super.key});

  @override
  ConsumerState<TestPreviewDialog> createState() => _TestPreviewDialogState();
}

class _TestPreviewDialogState extends ConsumerState<TestPreviewDialog> {
  late TextEditingController _contentController;
  late TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    final result = ref.read(testGenerationProvider).result;
    _contentController = TextEditingController(text: result?.testContent ?? '');
    _pathController = TextEditingController(text: result?.testFilePath ?? '');
  }

  @override
  void dispose() {
    _contentController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final testState = ref.watch(testGenerationProvider);
    final result = testState.result;

    if (result == null) {
      return const SizedBox.shrink();
    }

    return Dialog(
      backgroundColor: tokens.bgMain,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: tokens.border),
      ),
      child: SizedBox(
        width: 700,
        height: 550,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(Spacing.xl),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: tokens.border)),
              ),
              child: Row(
                children: [
                  Icon(Icons.bug_report, size: 18, color: tokens.accent),
                  const SizedBox(width: Spacing.md),
                  Text(
                    'Generated Tests',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.lg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.md,
                      vertical: Spacing.xs,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.sm),
                      color: tokens.success.withValues(alpha: 0.15),
                    ),
                    child: Text(
                      '${result.testCount} tests',
                      style: TextStyle(
                        color: tokens.success,
                        fontSize: FontSizes.xs,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Output path
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.xl,
                Spacing.lg,
                Spacing.xl,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Output Path',
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: FontSizes.xs,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                  SizedBox(
                    height: 32,
                    child: TextField(
                      controller: _pathController,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.xs,
                        fontFamily: 'JetBrains Mono',
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: tokens.bgDark,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: Spacing.md,
                          vertical: Spacing.sm,
                        ),
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
                    ),
                  ),
                ],
              ),
            ),

            // Test content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.md),
                    color: tokens.bgDark,
                    border: Border.all(color: tokens.border),
                  ),
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
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.all(Spacing.lg),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.fromLTRB(
                Spacing.xl,
                0,
                Spacing.xl,
                Spacing.xl,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    result.summary,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: tokens.textSecondary),
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  TextButton(
                    onPressed: () {
                      ref.read(testGenerationProvider.notifier).saveAndOpen();
                      Navigator.of(context).pop();
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: tokens.accent.withValues(alpha: 0.15),
                    ),
                    child: Text(
                      'Save & Open',
                      style: TextStyle(color: tokens.accent),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
