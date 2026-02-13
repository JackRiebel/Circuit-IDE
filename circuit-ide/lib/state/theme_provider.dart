import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_tokens.dart';

class ThemeNotifier extends Notifier<ThemeTokens> {
  @override
  ThemeTokens build() => ThemeTokens.dark;

  void setTheme(ThemeTokens theme) {
    state = theme;
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeTokens>(
  ThemeNotifier.new,
);
