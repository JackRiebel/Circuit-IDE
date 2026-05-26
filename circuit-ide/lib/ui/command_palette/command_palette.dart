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
        color: Colors.black.withValues(alpha: 0.35),
        child: Align(
          alignment: const Alignment(0, -0.35),
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: 520,
              constraints: const BoxConstraints(maxHeight: 460),
              decoration: BoxDecoration(
                color: tokens.surfacePopover,
                borderRadius: BorderRadius.circular(Radii.xl),
                border: Border.all(color: tokens.outlineSoft),
                boxShadow: Shadows.elevated,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search input
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.xl,
                      vertical: Spacing.lg,
                    ),
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
                          Icon(Icons.search, size: 16, color: tokens.textMuted),
                          const SizedBox(width: Spacing.md),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              autocorrect: false,
                              enableSuggestions: false,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: FontSizes.base,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Search commands...',
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
                  Divider(color: tokens.outlineSoft, height: 1),
                  if (paletteState.query.isEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Spacing.lg,
                        Spacing.sm,
                        Spacing.lg,
                        0,
                      ),
                      child: _CategoryChips(
                        categories: paletteState.categories,
                        selected: paletteState.categoryFilter,
                      ),
                    ),
                    if (paletteState.recentCommands.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Spacing.xl,
                          Spacing.md,
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
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],

                  // Commands list
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: Spacing.xl,
                              vertical: Spacing.lg,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? tokens.surfacePressed
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(Radii.sm),
                            ),
                            margin: const EdgeInsets.symmetric(
                              horizontal: Spacing.sm,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  command.icon,
                                  size: 16,
                                  color: !enabled
                                      ? tokens.textDisabled
                                      : isSelected
                                      ? tokens.accent
                                      : tokens.textMuted,
                                ),
                                const SizedBox(width: Spacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${command.category}: ${command.title}',
                                        style: TextStyle(
                                          color: !enabled
                                              ? tokens.textDisabled
                                              : isSelected
                                              ? tokens.textPrimary
                                              : tokens.textSecondary,
                                          fontSize: FontSizes.md,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (command.description != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: Text(
                                            command.description!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: tokens.textMuted,
                                              fontSize: FontSizes.xs,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (command.shortcut != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: tokens.surfaceInset,
                                      borderRadius: BorderRadius.circular(
                                        Radii.xs,
                                      ),
                                      border: Border.all(
                                        color: tokens.outlineSoft,
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
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: selected ? tokens.surfacePressed : tokens.surfaceInset,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(
            color: selected ? tokens.outlineFocus : tokens.outlineSoft,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? tokens.textPrimary : tokens.textMuted,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
