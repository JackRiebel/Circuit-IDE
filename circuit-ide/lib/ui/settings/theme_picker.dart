import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/settings_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';

class ThemePicker extends ConsumerWidget {
  const ThemePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTokens = ref.watch(themeProvider);

    return Wrap(
      spacing: Spacing.md,
      runSpacing: Spacing.md,
      children: ThemeTokens.allThemes.map((theme) {
        final isSelected = theme.name == currentTokens.name;

        return _ThemeCard(
          theme: theme,
          isSelected: isSelected,
          onTap: () {
            ref
                .read(themeProvider.notifier)
                .setTheme(ThemeTokens.fromName(theme.name));
            ref.read(settingsProvider.notifier).setTheme(theme.name);
          },
        );
      }).toList(),
    );
  }
}

class _ThemeCard extends StatefulWidget {
  final ThemeTokens theme;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.theme,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_ThemeCard> createState() => _ThemeCardState();
}

class _ThemeCardState extends State<_ThemeCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AnimationDurations.fast,
          curve: AnimationCurves.snappy,
          width: 80,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: widget.isSelected
                  ? widget.theme.accent
                  : _isHovered
                      ? widget.theme.accent.withValues(alpha: 0.4)
                      : widget.theme.border,
              width: widget.isSelected ? 2 : 1,
            ),
            boxShadow: _isHovered || widget.isSelected
                ? [
                    BoxShadow(
                      color: widget.theme.accent.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              // Color preview
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.theme.editorBg,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(Radii.md - 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        color: widget.theme.activityBarBg,
                      ),
                      Expanded(
                        child: Container(
                          color: widget.theme.editorBg,
                          padding: const EdgeInsets.all(4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 3,
                                width: 30,
                                decoration: BoxDecoration(
                                  color: widget.theme.accent,
                                  borderRadius:
                                      BorderRadius.circular(1),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Container(
                                height: 2,
                                width: 40,
                                decoration: BoxDecoration(
                                  color: widget.theme.textMuted,
                                  borderRadius:
                                      BorderRadius.circular(1),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Label
              Container(
                height: 18,
                decoration: BoxDecoration(
                  color: widget.theme.statusBarBg,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(Radii.md - 1),
                  ),
                ),
                child: Center(
                  child: Text(
                    widget.theme.displayName,
                    style: TextStyle(
                      color: widget.theme.statusBarText,
                      fontSize: FontSizes.xxs,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.1,
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
