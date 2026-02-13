import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';

class FindReplaceBar extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  final void Function(String query, {bool caseSensitive, bool regex}) onFind;
  final void Function(String replacement) onReplace;
  final void Function(String replacement) onReplaceAll;

  const FindReplaceBar({
    super.key,
    required this.onClose,
    required this.onFind,
    required this.onReplace,
    required this.onReplaceAll,
  });

  @override
  ConsumerState<FindReplaceBar> createState() => _FindReplaceBarState();
}

class _FindReplaceBarState extends ConsumerState<FindReplaceBar> {
  final _findController = TextEditingController();
  final _replaceController = TextEditingController();
  final _findFocusNode = FocusNode();
  bool _showReplace = false;
  bool _caseSensitive = false;
  bool _useRegex = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _findFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _findController.dispose();
    _replaceController.dispose();
    _findFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
        }
      },
      child: Container(
      padding: const EdgeInsets.all(Spacing.md),
      color: tokens.bgLight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _showReplace ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                ),
                onPressed: () => setState(() => _showReplace = !_showReplace),
                iconSize: 16,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: TextField(
                    controller: _findController,
                    focusNode: _findFocusNode,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: TextStyle(fontSize: FontSizes.sm, color: tokens.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Find',
                      hintStyle: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
                      filled: true,
                      fillColor: tokens.inputBg,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Radii.sm),
                        borderSide: BorderSide(color: tokens.inputBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Radii.sm),
                        borderSide: BorderSide(color: tokens.inputBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Radii.sm),
                        borderSide: BorderSide(color: tokens.inputFocusBorder),
                      ),
                    ),
                    onChanged: (value) => widget.onFind(
                      value,
                      caseSensitive: _caseSensitive,
                      regex: _useRegex,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _ToggleButton(
                icon: Icons.text_fields,
                tooltip: 'Match Case',
                isActive: _caseSensitive,
                onTap: () => setState(() => _caseSensitive = !_caseSensitive),
              ),
              _ToggleButton(
                icon: Icons.code,
                tooltip: 'Use Regex',
                isActive: _useRegex,
                onTap: () => setState(() => _useRegex = !_useRegex),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: widget.onClose,
                iconSize: 16,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ],
          ),
          if (_showReplace) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const SizedBox(width: 28),
                const SizedBox(width: 4),
                Expanded(
                  child: SizedBox(
                    height: 28,
                    child: TextField(
                      controller: _replaceController,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: TextStyle(fontSize: FontSizes.sm, color: tokens.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Replace',
                        hintStyle: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
                        filled: true,
                        fillColor: tokens.inputBg,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(Radii.sm),
                          borderSide: BorderSide(color: tokens.inputBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(Radii.sm),
                          borderSide: BorderSide(color: tokens.inputBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(Radii.sm),
                          borderSide: BorderSide(color: tokens.inputFocusBorder),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.find_replace, size: 16),
                  tooltip: 'Replace',
                  onPressed: () =>
                      widget.onReplace(_replaceController.text),
                  iconSize: 16,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
                IconButton(
                  icon: const Icon(Icons.done_all, size: 16),
                  tooltip: 'Replace All',
                  onPressed: () =>
                      widget.onReplaceAll(_replaceController.text),
                  iconSize: 16,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
              ],
            ),
          ],
        ],
      ),
      ),
    );
  }
}

class _ToggleButton extends ConsumerWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isActive
                ? tokens.accent.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            size: 14,
            color: isActive ? tokens.accent : tokens.textMuted,
          ),
        ),
      ),
    );
  }
}
