import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';

class CodeExplanationPopup extends ConsumerWidget {
  final Offset position;
  final String explanation;
  final bool isLoading;
  final VoidCallback onDismiss;

  const CodeExplanationPopup({
    super.key,
    required this.position,
    required this.explanation,
    this.isLoading = false,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Positioned(
      left: position.dx.clamp(20, MediaQuery.of(context).size.width - 420),
      top: position.dy,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Container(
          width: 400,
          constraints: const BoxConstraints(maxHeight: 300),
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: tokens.bgLight,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lightbulb_outline, size: 14, color: tokens.warning),
                  const SizedBox(width: 6),
                  Text(
                    'Code Explanation',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.sm,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: onDismiss,
                    child: Icon(Icons.close, size: 14, color: tokens.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              if (isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(Spacing.xl),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: MarkdownWidget(
                      data: explanation,
                      shrinkWrap: true,
                      config: MarkdownConfig(
                        configs: [
                          PConfig(textStyle: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: FontSizes.sm,
                            height: 1.5,
                          )),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
