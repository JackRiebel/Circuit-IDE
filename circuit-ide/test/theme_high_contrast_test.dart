import 'package:circuit_ide/state/theme_provider.dart';
import 'package:circuit_ide/theme/app_theme.dart';
import 'package:circuit_ide/theme/theme_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('high-contrast variant preserves the selected theme identity', () {
    final highContrast = ThemeTokens.midnight.highContrastVariant;

    expect(highContrast.highContrast, isTrue);
    expect(highContrast.name, ThemeTokens.midnight.name);
    expect(highContrast.brightness, Brightness.dark);
    expect(highContrast.studioCanvas, const Color(0xFF000000));
    expect(highContrast.studioDrawer, const Color(0xFF000000));
    expect(highContrast.studioRailSelected, const Color(0xFF003A80));
  });

  test(
    'theme provider restores the chosen palette after high contrast ends',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(themeProvider.notifier);

      notifier.setTheme(ThemeTokens.light);
      notifier.setHighContrast(true);
      final enabled = container.read(themeProvider);
      expect(enabled.highContrast, isTrue);
      expect(enabled.name, ThemeTokens.light.name);
      expect(enabled.bgMain, const Color(0xFFFFFFFF));

      notifier.setHighContrast(false);
      final restored = container.read(themeProvider);
      expect(restored.highContrast, isFalse);
      expect(restored.name, ThemeTokens.light.name);
      expect(restored.bgMain, ThemeTokens.light.bgMain);
      expect(restored.accent, ThemeTokens.light.accent);
    },
  );

  test(
    'high-contrast text, actions, and focus affordances meet AA contrast',
    () {
      for (final tokens in [
        ThemeTokens.dark.highContrastVariant,
        ThemeTokens.light.highContrastVariant,
      ]) {
        final theme = AppTheme.fromTokens(tokens);
        expect(
          _contrast(tokens.textPrimary, tokens.bgMain),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(theme.colorScheme.onPrimary, tokens.accent),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(theme.colorScheme.onSecondary, tokens.accentHover),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(theme.colorScheme.onError, tokens.error),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(tokens.outlineFocus, tokens.inputBg),
          greaterThanOrEqualTo(3),
        );
        expect(tokens.studioTopBar, tokens.bgMain);
        expect(tokens.studioComposer, tokens.inputBg);
      }
    },
  );
}

double _contrast(Color foreground, Color background) {
  final lighter = foreground.computeLuminance();
  final darker = background.computeLuminance();
  final high = lighter > darker ? lighter : darker;
  final low = lighter > darker ? darker : lighter;
  return (high + 0.05) / (low + 0.05);
}
