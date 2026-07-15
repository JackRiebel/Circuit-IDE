import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/test_generation_provider.dart';
import '../../state/theme_provider.dart';
import 'test_preview_dialog.dart';

class TestGenerationButton extends ConsumerStatefulWidget {
  final String filePath;

  const TestGenerationButton({super.key, required this.filePath});

  @override
  ConsumerState<TestGenerationButton> createState() =>
      _TestGenerationButtonState();
}

class _TestGenerationButtonState extends ConsumerState<TestGenerationButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final testState = ref.watch(testGenerationProvider);

    return Tooltip(
      message: 'Generate Tests',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: testState.isGenerating
              ? null
              : () async {
                  await ref
                      .read(testGenerationProvider.notifier)
                      .generate(widget.filePath);

                  final result = ref.read(testGenerationProvider).result;
                  if (result != null && context.mounted) {
                    showDialog(
                      context: context,
                      builder: (_) => const TestPreviewDialog(),
                    );
                  }
                },
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.sm),
              color: _isHovered
                  ? tokens.accent.withValues(alpha: 0.1)
                  : Colors.transparent,
            ),
            child: testState.isGenerating
                ? Center(
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: tokens.accent,
                      ),
                    ),
                  )
                : Icon(
                    Icons.bug_report_outlined,
                    size: 15,
                    color: _isHovered ? tokens.accent : tokens.textMuted,
                  ),
          ),
        ),
      ),
    );
  }
}
