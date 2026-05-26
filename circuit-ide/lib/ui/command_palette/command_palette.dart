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
              constraints: const BoxConstraints(maxHeight: 400),
              decoration: BoxDecoration(
                color: tokens.bgLight,
                borderRadius: BorderRadius.circular(Radii.xl),
                border: Border.all(color: tokens.border),
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
                            if (paletteState.filteredCommands.isEmpty) return;
                            setState(() {
                              _selectedIndex = (_selectedIndex + 1).clamp(
                                0,
                                paletteState.filteredCommands.length - 1,
                              );
                            });
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.arrowUp) {
                            if (paletteState.filteredCommands.isEmpty) return;
                            setState(() {
                              _selectedIndex = (_selectedIndex - 1).clamp(
                                0,
                                paletteState.filteredCommands.length - 1,
                              );
                            });
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.enter) {
                            if (paletteState.filteredCommands.isNotEmpty) {
                              ref
                                  .read(commandPaletteProvider.notifier)
                                  .execute(
                                    paletteState
                                        .filteredCommands[_selectedIndex],
                                  );
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
                  Divider(
                    color: tokens.border.withValues(alpha: 0.5),
                    height: 1,
                  ),

                  // Commands list
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                      itemCount: paletteState.filteredCommands.length,
                      itemBuilder: (context, index) {
                        final command = paletteState.filteredCommands[index];
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
                                  ? tokens.accent.withValues(alpha: 0.1)
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
                                      color: tokens.bgDark,
                                      borderRadius: BorderRadius.circular(
                                        Radii.xs,
                                      ),
                                      border: Border.all(
                                        color: tokens.border.withValues(
                                          alpha: 0.5,
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
