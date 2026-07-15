import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_tokens.dart';

class ThemeNotifier extends Notifier<ThemeTokens> {
  ThemeTokens _selectedTheme = ThemeTokens.dark;
  bool _highContrast = false;

  @override
  ThemeTokens build() => _resolvedTheme;

  ThemeTokens get _resolvedTheme =>
      _highContrast ? _selectedTheme.highContrastVariant : _selectedTheme;

  void setTheme(ThemeTokens theme) {
    _selectedTheme = theme.highContrast
        ? ThemeTokens.fromName(theme.name)
        : theme;
    state = _resolvedTheme;
  }

  /// Applies the platform accessibility setting without persisting a second
  /// user theme preference. [setTheme] still controls the underlying palette.
  void setHighContrast(bool enabled) {
    if (_highContrast == enabled) return;
    _highContrast = enabled;
    state = _resolvedTheme;
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeTokens>(
  ThemeNotifier.new,
);
