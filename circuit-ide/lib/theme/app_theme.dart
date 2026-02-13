import 'package:flutter/material.dart';

import 'theme_tokens.dart';

class AppTheme {
  static ThemeData fromTokens(ThemeTokens tokens) {
    return ThemeData(
      brightness: tokens.brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: tokens.bgMain,
      fontFamily: _uiFontFamily,
      colorScheme: ColorScheme(
        brightness: tokens.brightness,
        primary: tokens.accent,
        onPrimary: Colors.white,
        secondary: tokens.accentHover,
        onSecondary: Colors.white,
        error: tokens.error,
        onError: Colors.white,
        surface: tokens.bgMain,
        onSurface: tokens.textPrimary,
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(
          color: tokens.textPrimary,
          fontSize: 14,
          fontFamily: _uiFontFamily,
          letterSpacing: -0.1,
        ),
        bodyMedium: TextStyle(
          color: tokens.textPrimary,
          fontSize: 13,
          fontFamily: _uiFontFamily,
          letterSpacing: -0.1,
        ),
        bodySmall: TextStyle(
          color: tokens.textSecondary,
          fontSize: 11,
          fontFamily: _uiFontFamily,
        ),
        labelLarge: TextStyle(
          color: tokens.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          fontFamily: _uiFontFamily,
          letterSpacing: -0.1,
        ),
        labelMedium: TextStyle(
          color: tokens.textSecondary,
          fontSize: 11,
          fontFamily: _uiFontFamily,
        ),
        titleMedium: TextStyle(
          color: tokens.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          fontFamily: _uiFontFamily,
          letterSpacing: -0.2,
        ),
      ),
      iconTheme: IconThemeData(
        color: tokens.textSecondary,
        size: 18,
      ),
      dividerTheme: DividerThemeData(
        color: tokens.border,
        thickness: 1,
        space: 0,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          tokens.textMuted.withValues(alpha: 0.25),
        ),
        thickness: const WidgetStatePropertyAll(5),
        radius: const Radius.circular(3),
        thumbVisibility: const WidgetStatePropertyAll(false),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: tokens.bgLighter,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: tokens.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        textStyle: TextStyle(
          color: tokens.textPrimary,
          fontSize: 11,
          fontFamily: _uiFontFamily,
          fontWeight: FontWeight.w400,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tokens.bgLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: tokens.border),
        ),
        textStyle: TextStyle(
          color: tokens.textPrimary,
          fontSize: 13,
          fontFamily: _uiFontFamily,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.inputBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: tokens.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: tokens.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: tokens.inputFocusBorder, width: 1.5),
        ),
        hintStyle: TextStyle(
          color: tokens.textMuted,
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return tokens.accent.withValues(alpha: 0.35);
            }
            if (states.contains(WidgetState.pressed)) {
              return tokens.accentHover;
            }
            if (states.contains(WidgetState.hovered)) {
              return Color.lerp(tokens.accent, tokens.accentHover, 0.5)!;
            }
            return tokens.accent;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          )),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
          elevation: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return 0;
            if (states.contains(WidgetState.hovered)) return 2;
            return 0;
          }),
          shadowColor: WidgetStatePropertyAll(
            tokens.accent.withValues(alpha: 0.25),
          ),
          overlayColor: WidgetStatePropertyAll(
            Colors.white.withValues(alpha: 0.08),
          ),
          animationDuration: const Duration(milliseconds: 150),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(tokens.textPrimary),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return BorderSide(color: tokens.accent);
            }
            return BorderSide(color: tokens.border);
          }),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          )),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
          overlayColor: WidgetStatePropertyAll(
            tokens.accent.withValues(alpha: 0.06),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  static const _uiFontFamily = '.SF Pro Text';
}
