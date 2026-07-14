import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';

class StudioChromeIconButton extends ConsumerStatefulWidget {
  /// WCAG 2.2 target-size baseline for compact desktop actions.
  static const minimumTargetSize = 24.0;

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  final bool loading;
  final double width;
  final double height;
  final double iconSize;
  final bool prominent;
  final FocusNode? focusNode;

  const StudioChromeIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.active = false,
    this.loading = false,
    this.width = 28,
    this.height = 24,
    this.iconSize = 14,
    this.prominent = false,
    this.focusNode,
  });

  @override
  ConsumerState<StudioChromeIconButton> createState() =>
      _StudioChromeIconButtonState();
}

class _StudioChromeIconButtonState
    extends ConsumerState<StudioChromeIconButton> {
  FocusNode? _ownedFocusNode;
  FocusNode? _listenedFocusNode;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();
    _configureFocusNode();
  }

  @override
  void didUpdateWidget(covariant StudioChromeIconButton oldWidget) {
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
      _ownedFocusNode ??= FocusNode(
        debugLabel: 'studio-chrome-${widget.tooltip}',
      );
    } else {
      _ownedFocusNode?.dispose();
      _ownedFocusNode = null;
    }
    _listenedFocusNode = _focusNode..addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (widget.onTap == null || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.space &&
        key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    widget.onTap!.call();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final enabled = widget.onTap != null && !widget.loading;
    final focused = _focusNode.hasFocus;
    final targetWidth = widget.width < StudioChromeIconButton.minimumTargetSize
        ? StudioChromeIconButton.minimumTargetSize
        : widget.width;
    final targetHeight =
        widget.height < StudioChromeIconButton.minimumTargetSize
        ? StudioChromeIconButton.minimumTargetSize
        : widget.height;
    final prominentColor = tokens.brightness == Brightness.dark
        ? tokens.textPrimary
        : tokens.accent;
    return Semantics(
      label: widget.tooltip,
      button: true,
      enabled: enabled,
      selected: widget.active,
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: Tooltip(
          message: widget.tooltip,
          child: Focus(
            focusNode: _focusNode,
            onKeyEvent: _handleKeyEvent,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                canRequestFocus: false,
                onTap: !enabled
                    ? null
                    : () {
                        _focusNode.requestFocus();
                        widget.onTap!.call();
                      },
                borderRadius: BorderRadius.circular(
                  widget.prominent ? Radii.pill : 6,
                ),
                child: Container(
                  width: targetWidth,
                  height: targetHeight,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.prominent && enabled
                        ? prominentColor
                        : widget.active
                        ? tokens.studioControl.withValues(alpha: 0.44)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(
                      widget.prominent ? Radii.pill : 6,
                    ),
                    border: focused
                        ? Border.all(color: tokens.outlineFocus, width: 1.5)
                        : widget.active && !widget.prominent
                        ? Border.all(
                            color: tokens.studioDivider.withValues(alpha: 0.34),
                          )
                        : null,
                  ),
                  child: widget.loading
                      ? SizedBox(
                          width: widget.iconSize,
                          height: widget.iconSize,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: tokens.textMuted,
                          ),
                        )
                      : Icon(
                          widget.icon,
                          color: widget.prominent
                              ? (enabled ? tokens.bgDark : tokens.textDisabled)
                              : !enabled
                              ? tokens.textDisabled
                              : widget.active
                              ? tokens.textSecondary
                              : tokens.textMuted,
                          size: widget.iconSize,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StudioMiniChip extends ConsumerWidget {
  final String label;
  final bool attention;

  const StudioMiniChip({
    super.key,
    required this.label,
    this.attention = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: attention
            ? tokens.warning.withValues(alpha: 0.11)
            : tokens.studioControl.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: attention ? tokens.warning : tokens.textMuted,
          fontSize: FontSizes.xxs,
          height: 1.15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Gives a non-button Studio surface a durable keyboard and semantic action.
///
/// Use this for full-row/card actions whose content is not itself interactive.
/// It intentionally keeps the child layout intact while ensuring selection can
/// be reached, identified, and activated without a pointer.
class StudioFocusableActionSurface extends ConsumerStatefulWidget {
  final String semanticLabel;
  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final BorderRadius borderRadius;
  final FocusNode? focusNode;

  const StudioFocusableActionSurface({
    super.key,
    required this.semanticLabel,
    required this.child,
    this.onTap,
    this.selected = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
    this.focusNode,
  });

  @override
  ConsumerState<StudioFocusableActionSurface> createState() =>
      _StudioFocusableActionSurfaceState();
}

class _StudioFocusableActionSurfaceState
    extends ConsumerState<StudioFocusableActionSurface> {
  FocusNode? _ownedFocusNode;
  FocusNode? _listenedFocusNode;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();
    _configureFocusNode();
  }

  @override
  void didUpdateWidget(covariant StudioFocusableActionSurface oldWidget) {
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
      _ownedFocusNode ??= FocusNode(
        debugLabel: 'studio-action-${widget.semanticLabel}',
      );
    } else {
      _ownedFocusNode?.dispose();
      _ownedFocusNode = null;
    }
    _listenedFocusNode = _focusNode..addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _activate() {
    if (widget.onTap == null) return;
    _focusNode.requestFocus();
    widget.onTap!.call();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (widget.onTap == null || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.space &&
        key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    widget.onTap!.call();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) {
      return Semantics(
        label: widget.semanticLabel,
        button: true,
        enabled: false,
        selected: widget.selected,
        child: ExcludeSemantics(child: widget.child),
      );
    }
    final tokens = ref.watch(themeProvider);
    return Semantics(
      label: widget.semanticLabel,
      button: true,
      enabled: true,
      selected: widget.selected,
      onTap: _activate,
      child: ExcludeSemantics(
        child: Focus(
          focusNode: _focusNode,
          onKeyEvent: _handleKeyEvent,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              canRequestFocus: false,
              borderRadius: widget.borderRadius,
              onTap: _activate,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: widget.borderRadius,
                  border: _focusNode.hasFocus
                      ? Border.all(color: tokens.outlineFocus, width: 1.5)
                      : null,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StudioTonalButton extends ConsumerStatefulWidget {
  /// WCAG 2.2 target-size baseline for compact desktop actions.
  static const minimumTargetSize = 24.0;

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final FocusNode? focusNode;

  const StudioTonalButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.focusNode,
  });

  @override
  ConsumerState<StudioTonalButton> createState() => _StudioTonalButtonState();
}

class _StudioTonalButtonState extends ConsumerState<StudioTonalButton> {
  FocusNode? _ownedFocusNode;
  FocusNode? _listenedFocusNode;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();
    _configureFocusNode();
  }

  @override
  void didUpdateWidget(covariant StudioTonalButton oldWidget) {
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
      _ownedFocusNode ??= FocusNode(debugLabel: 'studio-tonal-${widget.label}');
    } else {
      _ownedFocusNode?.dispose();
      _ownedFocusNode = null;
    }
    _listenedFocusNode = _focusNode..addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final focused = _focusNode.hasFocus;
    return Semantics(
      label: widget.label,
      button: true,
      enabled: widget.onTap != null,
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: InkWell(
          focusNode: _focusNode,
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(Radii.lg),
          child: Container(
            height: 30 < StudioTonalButton.minimumTargetSize
                ? StudioTonalButton.minimumTargetSize
                : 30,
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            decoration: BoxDecoration(
              color: tokens.studioControl,
              borderRadius: BorderRadius.circular(Radii.lg),
              border: focused
                  ? Border.all(color: tokens.outlineFocus, width: 1.5)
                  : Border.all(
                      color: tokens.studioDivider.withValues(alpha: 0.7),
                    ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, color: tokens.textMuted, size: 14),
                  const SizedBox(width: Spacing.sm),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StudioActivityRow extends ConsumerStatefulWidget {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;
  final bool elevated;
  final FocusNode? focusNode;

  const StudioActivityRow({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.onTap,
    this.elevated = false,
    this.focusNode,
  });

  @override
  ConsumerState<StudioActivityRow> createState() => _StudioActivityRowState();
}

class _StudioActivityRowState extends ConsumerState<StudioActivityRow> {
  FocusNode? _ownedFocusNode;
  FocusNode? _listenedFocusNode;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();
    _configureFocusNode();
  }

  @override
  void didUpdateWidget(covariant StudioActivityRow oldWidget) {
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
      _ownedFocusNode ??= FocusNode(
        debugLabel: 'studio-activity-${widget.title}',
      );
    } else {
      _ownedFocusNode?.dispose();
      _ownedFocusNode = null;
    }
    _listenedFocusNode = _focusNode..addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _activate() {
    if (widget.onTap == null) return;
    _focusNode.requestFocus();
    widget.onTap!.call();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (widget.onTap == null || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.space &&
        key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    _activate();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final focused = _focusNode.hasFocus;
    final enabled = widget.onTap != null;
    final semanticLabel = widget.detail.trim().isEmpty
        ? widget.title
        : '${widget.title}, ${widget.detail}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Semantics(
        container: true,
        label: semanticLabel,
        button: true,
        enabled: enabled,
        onTap: enabled ? _activate : null,
        child: ExcludeSemantics(
          child: Focus(
            focusNode: _focusNode,
            canRequestFocus: enabled,
            skipTraversal: !enabled,
            onKeyEvent: _handleKeyEvent,
            child: InkWell(
              canRequestFocus: false,
              onTap: enabled ? _activate : null,
              borderRadius: BorderRadius.circular(Radii.md),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 706),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: widget.elevated
                      ? tokens.studioActivityRow.withValues(alpha: 0.58)
                      : tokens.studioActivityRow.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: focused
                      ? Border.all(color: tokens.outlineFocus, width: 1.5)
                      : Border.all(
                          color: tokens.studioDivider.withValues(alpha: 0.34),
                        ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(widget.icon, color: tokens.textMuted, size: 14),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: FontSizes.sm,
                              height: 1.15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (widget.detail.trim().isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              widget.detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: FontSizes.xs,
                                height: 1.15,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (enabled)
                      Icon(
                        StudioIcons.chevronRight,
                        color: tokens.textMuted,
                        size: 14,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
