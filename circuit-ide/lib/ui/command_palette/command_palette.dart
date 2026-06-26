import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/command_palette_provider.dart';
import '../../state/theme_provider.dart';

class CommandPalette extends ConsumerStatefulWidget {
  const CommandPalette({super.key});

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  int _selectedIndex = 0;

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
    final paletteState = ref.watch(commandPaletteProvider);
    final visibleCommands =
        paletteState.query.isEmpty &&
            paletteState.categoryFilter == null &&
            paletteState.recentCommands.isNotEmpty
        ? paletteState.recentCommands
        : paletteState.filteredCommands;

    return GestureDetector(
      onTap: () => ref.read(commandPaletteProvider.notifier).close(),
      child: Container(
        color: Colors.black.withValues(alpha: 0.28),
        child: Align(
          alignment: const Alignment(0, -0.2),
          child: GestureDetector(
            onTap: _focusNode.requestFocus,
            child: Container(
              width: 520,
              constraints: const BoxConstraints(maxHeight: 380),
              decoration: BoxDecoration(
                color: tokens.studioPanel.withValues(alpha: 0.98),
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(
                  color: tokens.studioDivider.withValues(alpha: 0.42),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search input
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: KeyboardListener(
                      focusNode: FocusNode(),
                      onKeyEvent: (event) {
                        if (event is KeyDownEvent) {
                          if (event.logicalKey == LogicalKeyboardKey.escape) {
                            ref.read(commandPaletteProvider.notifier).close();
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.arrowDown) {
                            if (visibleCommands.isEmpty) return;
                            setState(() {
                              _selectedIndex = (_selectedIndex + 1).clamp(
                                0,
                                visibleCommands.length - 1,
                              );
                            });
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.arrowUp) {
                            if (visibleCommands.isEmpty) return;
                            setState(() {
                              _selectedIndex = (_selectedIndex - 1).clamp(
                                0,
                                visibleCommands.length - 1,
                              );
                            });
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.enter) {
                            if (visibleCommands.isNotEmpty) {
                              final index = _selectedIndex.clamp(
                                0,
                                visibleCommands.length - 1,
                              );
                              ref
                                  .read(commandPaletteProvider.notifier)
                                  .execute(visibleCommands[index]);
                            }
                          }
                        }
                      },
                      child: Row(
                        children: [
                          Icon(Icons.search, size: 14, color: tokens.textMuted),
                          const SizedBox(width: 9),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              autocorrect: false,
                              enableSuggestions: false,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: FontSizes.sm,
                                height: 1.2,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Search commands...',
                                hintStyle: TextStyle(
                                  color: tokens.textMuted,
                                  fontSize: FontSizes.sm,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: (value) {
                                ref
                                    .read(commandPaletteProvider.notifier)
                                    .filter(value);
                                setState(() => _selectedIndex = 0);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Divider(
                    color: tokens.studioDivider.withValues(alpha: 0.36),
                    height: 1,
                  ),
                  if (paletteState.query.isEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 7, 10, 0),
                      child: _CategoryChips(
                        categories: paletteState.categories,
                        selected: paletteState.categoryFilter,
                      ),
                    ),
                    if (paletteState.recentCommands.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Spacing.xl,
                          9,
                          Spacing.xl,
                          Spacing.xs,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Recent',
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: FontSizes.xxs,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],

                  // Commands list
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      itemCount: visibleCommands.length,
                      itemBuilder: (context, index) {
                        final command = visibleCommands[index];
                        final isSelected = index == _selectedIndex;
                        final enabled = command.enabled;

                        return InkWell(
                          mouseCursor: enabled
                              ? SystemMouseCursors.click
                              : SystemMouseCursors.basic,
                          onTap: () => ref
                              .read(commandPaletteProvider.notifier)
                              .execute(command),
                          child: Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? tokens.studioControl.withValues(alpha: 0.54)
                                  : tokens.studioActivityRow.withValues(
                                      alpha: 0.22,
                                    ),
                              borderRadius: BorderRadius.circular(Radii.sm),
                              border: Border.all(
                                color: isSelected
                                    ? tokens.studioDivider.withValues(
                                        alpha: 0.44,
                                      )
                                    : Colors.transparent,
                              ),
                            ),
                            margin: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  command.icon,
                                  size: 14,
                                  color: !enabled
                                      ? tokens.textDisabled
                                      : isSelected
                                      ? tokens.accent
                                      : tokens.textMuted,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        command.title,
                                        style: TextStyle(
                                          color: !enabled
                                              ? tokens.textDisabled
                                              : isSelected
                                              ? tokens.textPrimary
                                              : tokens.textSecondary,
                                          fontSize: FontSizes.xs,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          command.description ??
                                              command.category,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: tokens.textMuted,
                                            fontSize: FontSizes.xxs,
                                            height: 1.1,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (command.shortcut != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: tokens.studioCanvas.withValues(
                                        alpha: 0.72,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        Radii.xs,
                                      ),
                                      border: Border.all(
                                        color: tokens.studioDivider.withValues(
                                          alpha: 0.38,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      command.shortcut!,
                                      style: TextStyle(
                                        color: tokens.textMuted,
                                        fontSize: FontSizes.xxs,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChips extends ConsumerWidget {
  final List<String> categories;
  final String? selected;

  const _CategoryChips({required this.categories, required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allSelected = selected == null;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _PaletteChip(
            label: 'All',
            selected: allSelected,
            onTap: () =>
                ref.read(commandPaletteProvider.notifier).setCategory(null),
          ),
          const SizedBox(width: Spacing.sm),
          ...categories.map(
            (category) => Padding(
              padding: const EdgeInsets.only(right: Spacing.sm),
              child: _PaletteChip(
                label: category,
                selected: selected == category,
                onTap: () => ref
                    .read(commandPaletteProvider.notifier)
                    .setCategory(category),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaletteChip extends ConsumerWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PaletteChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? tokens.studioControl.withValues(alpha: 0.7)
              : tokens.studioActivityRow.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(
            color: selected
                ? tokens.studioDivider.withValues(alpha: 0.55)
                : tokens.studioDivider.withValues(alpha: 0.22),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? tokens.textPrimary : tokens.textMuted,
            fontSize: FontSizes.xxs,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
