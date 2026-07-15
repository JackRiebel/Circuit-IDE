import 'package:circuit_ide/theme/app_theme.dart';
import 'package:circuit_ide/theme/theme_tokens.dart';
import 'package:flutter/material.dart';

/// Renders a fixture through the same dark Material theme as CircuitCode.
///
/// Studio widgets resolve colors from [themeProvider], but their host Scaffold,
/// menus, inputs, and typography must also use the production Material theme
/// for a golden to represent the shipped macOS surface.
Widget studioGoldenHarness(
  Widget child, {
  TextScaler? textScaler,
  ThemeTokens tokens = ThemeTokens.dark,
}) {
  return MaterialApp(
    theme: AppTheme.fromTokens(tokens),
    themeMode: ThemeMode.dark,
    home: Builder(
      builder: (context) {
        final scaffold = Scaffold(backgroundColor: tokens.bgDark, body: child);
        if (textScaler == null) return scaffold;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: scaffold,
        );
      },
    ),
  );
}
