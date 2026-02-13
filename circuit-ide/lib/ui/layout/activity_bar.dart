import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/editor_provider.dart';
import '../../state/theme_provider.dart';
import '../../state/terminal_provider.dart';
import 'ide_scaffold.dart';

enum ActivityBarItem {
  explorer(Icons.folder_outlined, Icons.folder, 'Explorer'),
  search(Icons.search, Icons.search, 'Search'),
  git(Icons.account_tree_outlined, Icons.account_tree, 'Source Control'),
  codebaseMap(Icons.hub_outlined, Icons.hub, 'Codebase Map'),
  notebook(Icons.science_outlined, Icons.science, 'Notebooks'),
  checkpoints(Icons.history_outlined, Icons.history, 'Checkpoints'),
  rules(Icons.rule_outlined, Icons.rule, 'Rules'),
  agents(Icons.smart_toy_outlined, Icons.smart_toy, 'Agents');

  const ActivityBarItem(this.icon, this.activeIcon, this.tooltip);
  final IconData icon;
  final IconData activeIcon;
  final String tooltip;
}

class ActiveActivityItemNotifier extends Notifier<ActivityBarItem> {
  @override
  ActivityBarItem build() => ActivityBarItem.explorer;

  void set(ActivityBarItem item) {
    state = item;
  }
}

final activeActivityItemProvider =
    NotifierProvider<ActiveActivityItemNotifier, ActivityBarItem>(
  ActiveActivityItemNotifier.new,
);

class ActivityBar extends ConsumerWidget {
  const ActivityBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final activeItem = ref.watch(activeActivityItemProvider);

    return Container(
      width: LayoutDimensions.activityBarWidth,
      decoration: BoxDecoration(
        color: tokens.activityBarBg,
        border: Border(
          right: BorderSide(
            color: tokens.border.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),
          ...ActivityBarItem.values.map((item) => _ActivityBarButton(
                    item: item,
                    isActive: activeItem == item,
                    onTap: () {
                      final current = ref.read(activeActivityItemProvider);
                      if (current == item) {
                        ref.read(sidePanelVisibleProvider.notifier).toggle();
                      } else {
                        ref.read(activeActivityItemProvider.notifier).set(item);
                        ref.read(sidePanelVisibleProvider.notifier).set(true);
                      }
                    },
                  )),
          const Spacer(),
          _SettingsButton(),
          _TerminalButton(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ActivityBarButton extends ConsumerStatefulWidget {
  final ActivityBarItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _ActivityBarButton({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  ConsumerState<_ActivityBarButton> createState() =>
      _ActivityBarButtonState();
}

class _ActivityBarButtonState extends ConsumerState<_ActivityBarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return Tooltip(
      message: widget.item.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: LayoutDimensions.activityBarWidth,
            height: LayoutDimensions.activityBarWidth,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: widget.isActive ? tokens.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Center(
              child: AnimatedContainer(
                duration: AnimationDurations.fast,
                curve: AnimationCurves.snappy,
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.md),
                  color: widget.isActive
                      ? tokens.accent.withValues(alpha: 0.1)
                      : _isHovered
                          ? tokens.textMuted.withValues(alpha: 0.08)
                          : Colors.transparent,
                ),
                child: Icon(
                  widget.isActive ? widget.item.activeIcon : widget.item.icon,
                  color: widget.isActive
                      ? tokens.activityBarIconActive
                      : _isHovered
                          ? tokens.textPrimary
                          : tokens.activityBarIcon,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsButton extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SettingsButton> createState() => _SettingsButtonState();
}

class _SettingsButtonState extends ConsumerState<_SettingsButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return Tooltip(
      message: 'Settings',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => ref.read(editorProvider.notifier).openSettingsTab(),
          child: Container(
            width: LayoutDimensions.activityBarWidth,
            height: LayoutDimensions.activityBarWidth,
            alignment: Alignment.center,
            child: AnimatedContainer(
              duration: AnimationDurations.fast,
              curve: AnimationCurves.snappy,
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.md),
                color: _isHovered
                    ? tokens.textMuted.withValues(alpha: 0.08)
                    : Colors.transparent,
              ),
              child: Icon(
                Icons.settings_outlined,
                color: _isHovered ? tokens.textPrimary : tokens.activityBarIcon,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TerminalButton extends ConsumerStatefulWidget {
  @override
  ConsumerState<_TerminalButton> createState() => _TerminalButtonState();
}

class _TerminalButtonState extends ConsumerState<_TerminalButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final isVisible = ref.watch(terminalProvider).isVisible;

    return Tooltip(
      message: 'Terminal',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => ref.read(terminalProvider.notifier).toggle(),
          child: Container(
            width: LayoutDimensions.activityBarWidth,
            height: LayoutDimensions.activityBarWidth,
            alignment: Alignment.center,
            child: AnimatedContainer(
              duration: AnimationDurations.fast,
              curve: AnimationCurves.snappy,
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.md),
                color: isVisible
                    ? tokens.accent.withValues(alpha: 0.1)
                    : _isHovered
                        ? tokens.textMuted.withValues(alpha: 0.08)
                        : Colors.transparent,
              ),
              child: Icon(
                Icons.terminal,
                color: isVisible
                    ? tokens.activityBarIconActive
                    : _isHovered
                        ? tokens.textPrimary
                        : tokens.activityBarIcon,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
