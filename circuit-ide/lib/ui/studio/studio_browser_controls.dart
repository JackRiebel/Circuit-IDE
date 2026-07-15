import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/studio_browser.dart';
import '../../state/theme_provider.dart';
import 'studio_chrome.dart';

/// Stateless browser controls for the user-owned Studio preview surface.
///
/// The surrounding drawer owns WebView state and every callback. This module
/// deliberately contains no model/tool integration, so preview navigation
/// remains separate from Studio turn permissions.
class StudioBrowserTabStrip extends ConsumerWidget {
  final StudioBrowserSession session;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final VoidCallback onCreate;

  const StudioBrowserTabStrip({
    super.key,
    required this.session,
    required this.onSelect,
    required this.onClose,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final divider = tokens.studioDivider;
    final panel = tokens.studioPanel;
    final selected = tokens.studioCanvas;
    final text = tokens.textSecondary;
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: panel,
        border: Border(bottom: BorderSide(color: divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
              itemCount: session.tabs.length,
              separatorBuilder: (_, _) => const SizedBox(width: Spacing.xs),
              itemBuilder: (context, index) {
                final tab = session.tabs[index];
                final active = tab.id == session.activeTab.id;
                return StudioBrowserTabButton(
                  key: ValueKey('browser-tab-${tab.id}'),
                  tab: tab,
                  active: active,
                  onSelect: () => onSelect(tab.id),
                  onClose: () => onClose(tab.id),
                  selectedColor: selected,
                  textColor: text,
                );
              },
            ),
          ),
          StudioChromeIconButton(
            tooltip: 'Open new browser tab',
            onTap: session.tabs.length < StudioBrowserSession.maxTabCount
                ? onCreate
                : null,
            icon: StudioIcons.add,
            iconSize: 15,
            width: 32,
            height: 30,
          ),
          const SizedBox(width: Spacing.xs),
        ],
      ),
    );
  }
}

/// A focusable browser-tab selector with a separate close action.
///
/// The tab-strip key is stable per tab id, so the owned focus node remains
/// attached through navigation, loading, and other browser-session updates.
class StudioBrowserTabButton extends ConsumerStatefulWidget {
  final StudioBrowserTab tab;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final FocusNode? focusNode;
  final Color? selectedColor;
  final Color? textColor;

  const StudioBrowserTabButton({
    super.key,
    required this.tab,
    required this.active,
    required this.onSelect,
    required this.onClose,
    this.focusNode,
    this.selectedColor,
    this.textColor,
  });

  @override
  ConsumerState<StudioBrowserTabButton> createState() =>
      _StudioBrowserTabButtonState();
}

class _StudioBrowserTabButtonState
    extends ConsumerState<StudioBrowserTabButton> {
  late FocusNode _focusNode;
  late bool _ownsFocusNode;

  @override
  void initState() {
    super.initState();
    _bindFocusNode(widget.focusNode);
  }

  @override
  void didUpdateWidget(covariant StudioBrowserTabButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _unbindFocusNode();
      _bindFocusNode(widget.focusNode);
    }
  }

  @override
  void dispose() {
    _unbindFocusNode();
    super.dispose();
  }

  void _bindFocusNode(FocusNode? focusNode) {
    _ownsFocusNode = focusNode == null;
    _focusNode =
        focusNode ??
        FocusNode(debugLabel: 'Studio browser tab ${widget.tab.id}');
    _focusNode.addListener(_handleFocusChange);
  }

  void _unbindFocusNode() {
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) _focusNode.dispose();
  }

  void _handleFocusChange() {
    if (mounted) setState(() {});
  }

  void _select() {
    _focusNode.requestFocus();
    widget.onSelect();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.space ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      widget.onSelect();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final radius = BorderRadius.circular(Radii.sm);
    return SizedBox(
      width: 158,
      height: 30,
      child: Material(
        color: widget.active
            ? widget.selectedColor ?? tokens.studioCanvas
            : Colors.transparent,
        borderRadius: radius,
        child: Row(
          children: [
            Expanded(
              child: Focus(
                focusNode: _focusNode,
                onKeyEvent: _handleKeyEvent,
                child: Semantics(
                  button: true,
                  selected: widget.active,
                  label: '${widget.tab.label} browser tab',
                  onTap: _select,
                  child: ExcludeSemantics(
                    child: InkWell(
                      canRequestFocus: false,
                      borderRadius: BorderRadius.horizontal(
                        left: radius.topLeft,
                      ),
                      onTap: _select,
                      child: Container(
                        height: double.infinity,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: Spacing.sm),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.horizontal(
                            left: radius.topLeft,
                          ),
                          border: _focusNode.hasFocus
                              ? Border.all(
                                  color: tokens.outlineFocus,
                                  width: 1.5,
                                )
                              : null,
                        ),
                        child: Text(
                          widget.tab.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: widget.textColor ?? tokens.textSecondary,
                            fontSize: FontSizes.xs,
                            fontWeight: widget.active
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            StudioChromeIconButton(
              tooltip: 'Close ${widget.tab.label}',
              icon: StudioIcons.close,
              iconSize: 14,
              width: 26,
              height: 30,
              onTap: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class StudioBrowserToolbar extends ConsumerWidget {
  final StudioBrowserSession session;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final ValueChanged<String> onNavigate;
  final VoidCallback onReload;
  final VoidCallback? onCopy;
  final VoidCallback? onOpenExternal;
  final VoidCallback onAllow;
  final VoidCallback onBlock;
  final VoidCallback onComment;
  final VoidCallback onCaptureObservation;
  final VoidCallback onSaveVisualSnapshot;
  final VoidCallback onShareSelection;

  const StudioBrowserToolbar({
    super.key,
    required this.session,
    required this.onBack,
    required this.onForward,
    required this.onNavigate,
    required this.onReload,
    required this.onCopy,
    required this.onOpenExternal,
    required this.onAllow,
    required this.onBlock,
    required this.onComment,
    required this.onCaptureObservation,
    required this.onSaveVisualSnapshot,
    required this.onShareSelection,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final url = session.currentUrl ?? session.addressDraft;
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.studioDivider)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              StudioChromeIconButton(
                tooltip: 'Back',
                onTap: session.canGoBack ? onBack : null,
                icon: StudioIcons.chevronLeft,
                iconSize: 14,
                width: 28,
                height: 24,
              ),
              StudioChromeIconButton(
                tooltip: 'Forward',
                onTap: session.canGoForward ? onForward : null,
                icon: StudioIcons.chevronRight,
                iconSize: 14,
                width: 28,
                height: 24,
              ),
              Expanded(
                child: TextFormField(
                  key: ValueKey(session.activeTabId),
                  initialValue: url,
                  onFieldSubmitted: onNavigate,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: Spacing.md,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      borderSide: BorderSide(color: tokens.studioDivider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      borderSide: BorderSide(color: tokens.studioDivider),
                    ),
                  ),
                ),
              ),
              StudioChromeIconButton(
                tooltip: 'Reload',
                onTap: onReload,
                icon: StudioIcons.refresh,
                iconSize: 14,
                width: 28,
                height: 24,
              ),
              StudioChromeIconButton(
                tooltip: 'Copy URL',
                onTap: onCopy,
                icon: StudioIcons.copy,
                iconSize: 14,
                width: 28,
                height: 24,
              ),
              StudioChromeIconButton(
                tooltip: 'Open external',
                onTap: onOpenExternal,
                icon: StudioIcons.openInNew,
                iconSize: 14,
                width: 28,
                height: 24,
              ),
              PopupMenuButton<BrowserSitePermission>(
                tooltip: 'Site permission',
                enabled: session.currentUrl != null,
                color: tokens.studioPanel,
                onSelected: (value) {
                  if (value == BrowserSitePermission.allowed) onAllow();
                  if (value == BrowserSitePermission.blocked) onBlock();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: BrowserSitePermission.allowed,
                    child: Text('Allow site'),
                  ),
                  PopupMenuItem(
                    value: BrowserSitePermission.blocked,
                    child: Text('Block site'),
                  ),
                ],
                child: Icon(
                  session.permissionFor(session.currentUrl) ==
                          BrowserSitePermission.blocked
                      ? StudioIcons.block
                      : StudioIcons.securityOutlined,
                  size: 14,
                  color: tokens.textMuted,
                ),
              ),
              StudioChromeIconButton(
                tooltip: 'Add browser comment',
                onTap: onComment,
                icon: StudioIcons.addCommentOutlined,
                iconSize: 14,
                width: 28,
                height: 24,
              ),
              StudioChromeIconButton(
                tooltip: 'Capture page observation',
                onTap: onCaptureObservation,
                icon: StudioIcons.contentCopyOutlined,
                iconSize: 14,
                width: 28,
                height: 24,
              ),
              if (session.snapshot?.hasVisualSnapshot == true)
                StudioChromeIconButton(
                  tooltip: 'Save visible pixels locally with this task',
                  onTap: onSaveVisualSnapshot,
                  icon: StudioIcons.screenshotMonitorOutlined,
                  iconSize: 14,
                  width: 28,
                  height: 24,
                ),
              StudioChromeIconButton(
                tooltip: 'Share selected text with task',
                onTap: session.snapshot?.hasSelection == true
                    ? onShareSelection
                    : null,
                icon: StudioIcons.iosShareOutlined,
                iconSize: 14,
                width: 28,
                height: 24,
              ),
            ],
          ),
          if (session.loadingProgress > 0 && session.loadingProgress < 100)
            LinearProgressIndicator(value: session.loadingProgress / 100),
          if (session.annotations.isNotEmpty) ...[
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${session.annotations.length} preview comments attached',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                ),
              ),
            ),
          ],
          if (session.snapshot != null) ...[
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                session.snapshot!.hasSelection
                    ? 'Selection captured — review and explicitly share it with the current task.'
                    : 'Page title and text snapshot captured locally. Select page text, then capture again to share it.',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
