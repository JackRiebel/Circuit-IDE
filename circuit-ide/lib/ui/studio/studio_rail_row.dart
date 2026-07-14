import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';

/// A focusable, semantic row shared by the project and conversation rail.
///
/// Keeping this interaction boundary outside the generic chrome primitives
/// lets rail-specific features evolve without growing the common toolbar API.
class StudioRailRow extends ConsumerStatefulWidget {
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final bool project;
  final Widget? trailing;
  final Widget? hoverTrailing;
  final double leftIndent;
  final FocusNode? focusNode;

  const StudioRailRow({
    super.key,
    this.icon,
    required this.label,
    this.onTap,
    this.selected = false,
    this.project = false,
    this.trailing,
    this.hoverTrailing,
    this.leftIndent = 0,
    this.focusNode,
  });

  @override
  ConsumerState<StudioRailRow> createState() => _StudioRailRowState();
}

class _StudioRailRowState extends ConsumerState<StudioRailRow> {
  bool _hovered = false;
  bool _focused = false;
  FocusNode? _ownedFocusNode;
  FocusNode? _listenedFocusNode;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();
    _configureFocusNode();
  }

  @override
  void didUpdateWidget(covariant StudioRailRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _configureFocusNode();
    }
  }

  @override
  void dispose() {
    _listenedFocusNode?.removeListener(_onFocusChanged);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _configureFocusNode() {
    _listenedFocusNode?.removeListener(_onFocusChanged);
    if (widget.focusNode == null) {
      _ownedFocusNode ??= FocusNode(debugLabel: 'studio-rail-${widget.label}');
    } else {
      _ownedFocusNode?.dispose();
      _ownedFocusNode = null;
    }
    _listenedFocusNode = _focusNode..addListener(_onFocusChanged);
    _focused = _focusNode.hasFocus;
  }

  void _onFocusChanged() {
    if (mounted) setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final showHoverTrailing =
        widget.hoverTrailing != null &&
        (_hovered || _focused || widget.selected);
    final highlighted = _hovered || _focused;
    return Semantics(
      label: widget.label,
      button: true,
      enabled: widget.onTap != null,
      selected: widget.selected,
      onTap: widget.onTap,
      child: Padding(
        padding: EdgeInsets.only(
          left: 7 + widget.leftIndent,
          right: 7,
          bottom: 1,
        ),
        child: FocusableActionDetector(
          focusNode: _focusNode,
          enabled: widget.onTap != null,
          onShowHoverHighlight: (value) => setState(() => _hovered = value),
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap?.call();
                return null;
              },
            ),
          },
          child: InkWell(
            canRequestFocus: false,
            onTap: widget.onTap == null
                ? null
                : () {
                    _focusNode.requestFocus();
                    widget.onTap!.call();
                  },
            borderRadius: BorderRadius.circular(7),
            child: Container(
              height: widget.project ? 30 : 28,
              padding: EdgeInsets.symmetric(horizontal: widget.project ? 8 : 8),
              decoration: BoxDecoration(
                color: widget.selected
                    ? (widget.project
                          ? tokens.studioRailSelected.withValues(alpha: 0.48)
                          : tokens.studioTaskSelected.withValues(alpha: 0.44))
                    : highlighted
                    ? tokens.studioHover.withValues(alpha: 0.22)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: _focused
                    ? Border.all(color: tokens.outlineFocus, width: 1.5)
                    : null,
              ),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(
                      widget.icon,
                      color: widget.selected
                          ? tokens.textPrimary
                          : tokens.textMuted,
                      size: 14,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.selected
                            ? tokens.textPrimary
                            : tokens.textSecondary,
                        fontSize: FontSizes.sm,
                        height: 1.12,
                        fontWeight: widget.selected
                            ? FontWeight.w600
                            : widget.project
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (widget.trailing != null) ...[
                    const SizedBox(width: Spacing.sm),
                    widget.trailing!,
                  ],
                  if (showHoverTrailing) ...[
                    const SizedBox(width: Spacing.xs),
                    widget.hoverTrailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
