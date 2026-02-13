import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';

class InlineChatOverlay extends ConsumerStatefulWidget {
  final Offset position;
  final String? selectedText;
  final void Function(String instruction) onSubmit;
  final VoidCallback onDismiss;

  const InlineChatOverlay({
    super.key,
    required this.position,
    this.selectedText,
    required this.onSubmit,
    required this.onDismiss,
  });

  @override
  ConsumerState<InlineChatOverlay> createState() => _InlineChatOverlayState();
}

class _InlineChatOverlayState extends ConsumerState<InlineChatOverlay> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return Positioned(
      left: widget.position.dx.clamp(50, MediaQuery.of(context).size.width - 400),
      top: widget.position.dy,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Container(
          width: 350,
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: tokens.bgLight,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: tokens.accent.withValues(alpha: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_fix_high, size: 14, color: tokens.accent),
                  const SizedBox(width: 6),
                  Text(
                    'Inline Edit',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.sm,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: widget.onDismiss,
                    child: Icon(Icons.close, size: 14, color: tokens.textMuted),
                  ),
                ],
              ),
              if (widget.selectedText != null) ...[
                const SizedBox(height: Spacing.md),
                Container(
                  padding: const EdgeInsets.all(Spacing.sm),
                  decoration: BoxDecoration(
                    color: tokens.codeBlockBg,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Text(
                    widget.selectedText!.length > 100
                        ? '${widget.selectedText!.substring(0, 100)}...'
                        : widget.selectedText!,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                      fontFamily: 'JetBrains Mono',
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const SizedBox(height: Spacing.md),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: 3,
                minLines: 1,
                autocorrect: false,
                enableSuggestions: false,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.sm,
                ),
                decoration: InputDecoration(
                  hintText: 'Describe what to change...',
                  suffixIcon: IconButton(
                    icon: Icon(Icons.send, size: 16, color: tokens.accent),
                    onPressed: () {
                      if (_controller.text.trim().isNotEmpty) {
                        widget.onSubmit(_controller.text.trim());
                      }
                    },
                  ),
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    widget.onSubmit(value.trim());
                  }
                },
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                'Enter to submit, Escape to dismiss',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
