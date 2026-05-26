import 'package:flutter/material.dart';

class ThemeTokens {
  final String name;
  final String displayName;
  final Brightness brightness;

  // Core UI
  final Color bgDark;
  final Color bgMain;
  final Color bgLight;
  final Color bgLighter;
  final Color border;
  final Color borderLight;

  // Text
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textDisabled;

  // Semantic
  final Color accent;
  final Color accentHover;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  // Activity Bar
  final Color activityBarBg;
  final Color activityBarIcon;
  final Color activityBarIconActive;
  final Color activityBarBadge;

  // Editor
  final Color editorBg;
  final Color editorLineHighlight;
  final Color editorSelection;
  final Color editorCursor;
  final Color editorLineNumber;
  final Color editorLineNumberActive;

  // Chat
  final Color userMsgBg;
  final Color agentMsgBg;
  final Color codeBlockBg;
  final Color codeBlockBorder;
  final Color inputBg;
  final Color inputBorder;
  final Color inputFocusBorder;

  // Tabs
  final Color tabActive;
  final Color tabInactive;
  final Color tabHover;
  final Color tabIndicator;

  // Status Bar
  final Color statusBarBg;
  final Color statusBarText;

  // Provider Colors
  final Color circuitColor;
  final Color claudeColor;

  // Terminal
  final Color terminalBg;
  final Color terminalText;

  // Modern surface aliases. These keep older call sites compatible while
  // giving new UI a clearer hierarchy than bgDark/bgMain/bgLight.
  Color get surfaceBase => bgMain;
  Color get surfaceRaised => bgLight.withValues(alpha: 0.72);
  Color get surfaceOverlay => bgLighter.withValues(alpha: 0.9);
  Color get surfaceHover => textMuted.withValues(alpha: 0.08);
  Color get surfaceSelected => accent.withValues(alpha: 0.12);
  Color get outlineSubtle => border.withValues(alpha: 0.45);
  Color get outlineStrong => borderLight.withValues(alpha: 0.78);

  const ThemeTokens({
    required this.name,
    required this.displayName,
    required this.brightness,
    required this.bgDark,
    required this.bgMain,
    required this.bgLight,
    required this.bgLighter,
    required this.border,
    required this.borderLight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textDisabled,
    required this.accent,
    required this.accentHover,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.activityBarBg,
    required this.activityBarIcon,
    required this.activityBarIconActive,
    required this.activityBarBadge,
    required this.editorBg,
    required this.editorLineHighlight,
    required this.editorSelection,
    required this.editorCursor,
    required this.editorLineNumber,
    required this.editorLineNumberActive,
    required this.userMsgBg,
    required this.agentMsgBg,
    required this.codeBlockBg,
    required this.codeBlockBorder,
    required this.inputBg,
    required this.inputBorder,
    required this.inputFocusBorder,
    required this.tabActive,
    required this.tabInactive,
    required this.tabHover,
    required this.tabIndicator,
    required this.statusBarBg,
    required this.statusBarText,
    required this.circuitColor,
    required this.claudeColor,
    required this.terminalBg,
    required this.terminalText,
  });

  static const dark = ThemeTokens(
    name: 'dark',
    displayName: 'Dark',
    brightness: Brightness.dark,
    bgDark: Color(0xFF1E1E1E),
    bgMain: Color(0xFF252526),
    bgLight: Color(0xFF2D2D2D),
    bgLighter: Color(0xFF333333),
    border: Color(0xFF3E3E3E),
    borderLight: Color(0xFF4A4A4A),
    textPrimary: Color(0xFFD4D4D4),
    textSecondary: Color(0xFFAAAAAA),
    textMuted: Color(0xFF808080),
    textDisabled: Color(0xFF5A5A5A),
    accent: Color(0xFF007ACC),
    accentHover: Color(0xFF1A8FD4),
    success: Color(0xFF4EC9B0),
    warning: Color(0xFFDCDCAA),
    error: Color(0xFFF44747),
    info: Color(0xFF75BEFF),
    activityBarBg: Color(0xFF333333),
    activityBarIcon: Color(0xFF858585),
    activityBarIconActive: Color(0xFFFFFFFF),
    activityBarBadge: Color(0xFF007ACC),
    editorBg: Color(0xFF1E1E1E),
    editorLineHighlight: Color(0xFF2A2D2E),
    editorSelection: Color(0xFF264F78),
    editorCursor: Color(0xFFAEAFAD),
    editorLineNumber: Color(0xFF5A5A5A),
    editorLineNumberActive: Color(0xFFC6C6C6),
    userMsgBg: Color(0xFF2B2D30),
    agentMsgBg: Color(0xFF1E1F22),
    codeBlockBg: Color(0xFF1A1A1A),
    codeBlockBorder: Color(0xFF3E3E3E),
    inputBg: Color(0xFF3C3C3C),
    inputBorder: Color(0xFF3E3E3E),
    inputFocusBorder: Color(0xFF007ACC),
    tabActive: Color(0xFF1E1E1E),
    tabInactive: Color(0xFF2D2D2D),
    tabHover: Color(0xFF353535),
    tabIndicator: Color(0xFF007ACC),
    statusBarBg: Color(0xFF007ACC),
    statusBarText: Color(0xFFFFFFFF),
    circuitColor: Color(0xFF88CFFF),
    claudeColor: Color(0xFFE8A87C),
    terminalBg: Color(0xFF1A1A1A),
    terminalText: Color(0xFFCCCCCC),
  );

  static const light = ThemeTokens(
    name: 'light',
    displayName: 'Light',
    brightness: Brightness.light,
    bgDark: Color(0xFFF3F3F3),
    bgMain: Color(0xFFFFFFFF),
    bgLight: Color(0xFFF8F8F8),
    bgLighter: Color(0xFFEEEEEE),
    border: Color(0xFFE0E0E0),
    borderLight: Color(0xFFD0D0D0),
    textPrimary: Color(0xFF333333),
    textSecondary: Color(0xFF666666),
    textMuted: Color(0xFF999999),
    textDisabled: Color(0xFFBBBBBB),
    accent: Color(0xFF007ACC),
    accentHover: Color(0xFF0065A9),
    success: Color(0xFF16825D),
    warning: Color(0xFFBF8803),
    error: Color(0xFFE51400),
    info: Color(0xFF007ACC),
    activityBarBg: Color(0xFF2C2C2C),
    activityBarIcon: Color(0xFF858585),
    activityBarIconActive: Color(0xFFFFFFFF),
    activityBarBadge: Color(0xFF007ACC),
    editorBg: Color(0xFFFFFFFF),
    editorLineHighlight: Color(0xFFF0F0F0),
    editorSelection: Color(0xFFADD6FF),
    editorCursor: Color(0xFF000000),
    editorLineNumber: Color(0xFFAAAAAA),
    editorLineNumberActive: Color(0xFF333333),
    userMsgBg: Color(0xFFEDF6FF),
    agentMsgBg: Color(0xFFF8F8F8),
    codeBlockBg: Color(0xFFF5F5F5),
    codeBlockBorder: Color(0xFFE0E0E0),
    inputBg: Color(0xFFFFFFFF),
    inputBorder: Color(0xFFCECECE),
    inputFocusBorder: Color(0xFF007ACC),
    tabActive: Color(0xFFFFFFFF),
    tabInactive: Color(0xFFECECEC),
    tabHover: Color(0xFFF0F0F0),
    tabIndicator: Color(0xFF007ACC),
    statusBarBg: Color(0xFF007ACC),
    statusBarText: Color(0xFFFFFFFF),
    circuitColor: Color(0xFF0078D4),
    claudeColor: Color(0xFFD97757),
    terminalBg: Color(0xFFFFFFFF),
    terminalText: Color(0xFF333333),
  );

  static const midnight = ThemeTokens(
    name: 'midnight',
    displayName: 'Midnight',
    brightness: Brightness.dark,
    bgDark: Color(0xFF0D1117),
    bgMain: Color(0xFF161B22),
    bgLight: Color(0xFF1C2128),
    bgLighter: Color(0xFF21262D),
    border: Color(0xFF30363D),
    borderLight: Color(0xFF3D444D),
    textPrimary: Color(0xFFE6EDF3),
    textSecondary: Color(0xFF8B949E),
    textMuted: Color(0xFF6E7681),
    textDisabled: Color(0xFF484F58),
    accent: Color(0xFF58A6FF),
    accentHover: Color(0xFF79C0FF),
    success: Color(0xFF3FB950),
    warning: Color(0xFFD29922),
    error: Color(0xFFF85149),
    info: Color(0xFF58A6FF),
    activityBarBg: Color(0xFF0D1117),
    activityBarIcon: Color(0xFF6E7681),
    activityBarIconActive: Color(0xFFE6EDF3),
    activityBarBadge: Color(0xFF58A6FF),
    editorBg: Color(0xFF0D1117),
    editorLineHighlight: Color(0xFF161B22),
    editorSelection: Color(0xFF1F3A5F),
    editorCursor: Color(0xFF58A6FF),
    editorLineNumber: Color(0xFF484F58),
    editorLineNumberActive: Color(0xFFE6EDF3),
    userMsgBg: Color(0xFF1C2128),
    agentMsgBg: Color(0xFF0D1117),
    codeBlockBg: Color(0xFF0A0E14),
    codeBlockBorder: Color(0xFF30363D),
    inputBg: Color(0xFF0D1117),
    inputBorder: Color(0xFF30363D),
    inputFocusBorder: Color(0xFF58A6FF),
    tabActive: Color(0xFF0D1117),
    tabInactive: Color(0xFF161B22),
    tabHover: Color(0xFF1C2128),
    tabIndicator: Color(0xFF58A6FF),
    statusBarBg: Color(0xFF1F6FEB),
    statusBarText: Color(0xFFFFFFFF),
    circuitColor: Color(0xFF79C0FF),
    claudeColor: Color(0xFFE8A87C),
    terminalBg: Color(0xFF0A0E14),
    terminalText: Color(0xFFE6EDF3),
  );

  static const forest = ThemeTokens(
    name: 'forest',
    displayName: 'Forest',
    brightness: Brightness.dark,
    bgDark: Color(0xFF1A2318),
    bgMain: Color(0xFF1E2A1C),
    bgLight: Color(0xFF253324),
    bgLighter: Color(0xFF2C3B2A),
    border: Color(0xFF3A4D38),
    borderLight: Color(0xFF4A5E48),
    textPrimary: Color(0xFFD4E0D0),
    textSecondary: Color(0xFFA0B09A),
    textMuted: Color(0xFF708068),
    textDisabled: Color(0xFF556050),
    accent: Color(0xFF7BC47F),
    accentHover: Color(0xFF8FD493),
    success: Color(0xFF7BC47F),
    warning: Color(0xFFD4C07A),
    error: Color(0xFFE06060),
    info: Color(0xFF7ABAD6),
    activityBarBg: Color(0xFF162014),
    activityBarIcon: Color(0xFF708068),
    activityBarIconActive: Color(0xFFD4E0D0),
    activityBarBadge: Color(0xFF7BC47F),
    editorBg: Color(0xFF1A2318),
    editorLineHighlight: Color(0xFF1E2A1C),
    editorSelection: Color(0xFF2D4A2F),
    editorCursor: Color(0xFF7BC47F),
    editorLineNumber: Color(0xFF556050),
    editorLineNumberActive: Color(0xFFD4E0D0),
    userMsgBg: Color(0xFF253324),
    agentMsgBg: Color(0xFF1A2318),
    codeBlockBg: Color(0xFF151E13),
    codeBlockBorder: Color(0xFF3A4D38),
    inputBg: Color(0xFF1A2318),
    inputBorder: Color(0xFF3A4D38),
    inputFocusBorder: Color(0xFF7BC47F),
    tabActive: Color(0xFF1A2318),
    tabInactive: Color(0xFF1E2A1C),
    tabHover: Color(0xFF253324),
    tabIndicator: Color(0xFF7BC47F),
    statusBarBg: Color(0xFF2D6A30),
    statusBarText: Color(0xFFFFFFFF),
    circuitColor: Color(0xFF88CFFF),
    claudeColor: Color(0xFFE8A87C),
    terminalBg: Color(0xFF151E13),
    terminalText: Color(0xFFD4E0D0),
  );

  static const solarized = ThemeTokens(
    name: 'solarized',
    displayName: 'Solarized Dark',
    brightness: Brightness.dark,
    bgDark: Color(0xFF002B36),
    bgMain: Color(0xFF073642),
    bgLight: Color(0xFF0A3F4E),
    bgLighter: Color(0xFF0D4A5A),
    border: Color(0xFF2A6070),
    borderLight: Color(0xFF3A7080),
    textPrimary: Color(0xFF839496),
    textSecondary: Color(0xFF657B83),
    textMuted: Color(0xFF586E75),
    textDisabled: Color(0xFF405055),
    accent: Color(0xFF268BD2),
    accentHover: Color(0xFF3A9DE0),
    success: Color(0xFF859900),
    warning: Color(0xFFB58900),
    error: Color(0xFFDC322F),
    info: Color(0xFF268BD2),
    activityBarBg: Color(0xFF002028),
    activityBarIcon: Color(0xFF586E75),
    activityBarIconActive: Color(0xFF93A1A1),
    activityBarBadge: Color(0xFF268BD2),
    editorBg: Color(0xFF002B36),
    editorLineHighlight: Color(0xFF073642),
    editorSelection: Color(0xFF1A4F5E),
    editorCursor: Color(0xFF268BD2),
    editorLineNumber: Color(0xFF405055),
    editorLineNumberActive: Color(0xFF93A1A1),
    userMsgBg: Color(0xFF073642),
    agentMsgBg: Color(0xFF002B36),
    codeBlockBg: Color(0xFF00212B),
    codeBlockBorder: Color(0xFF2A6070),
    inputBg: Color(0xFF002B36),
    inputBorder: Color(0xFF2A6070),
    inputFocusBorder: Color(0xFF268BD2),
    tabActive: Color(0xFF002B36),
    tabInactive: Color(0xFF073642),
    tabHover: Color(0xFF0A3F4E),
    tabIndicator: Color(0xFF268BD2),
    statusBarBg: Color(0xFF268BD2),
    statusBarText: Color(0xFFFDF6E3),
    circuitColor: Color(0xFF88CFFF),
    claudeColor: Color(0xFFE8A87C),
    terminalBg: Color(0xFF00212B),
    terminalText: Color(0xFF839496),
  );

  static const allThemes = [dark, light, midnight, forest, solarized];

  static ThemeTokens fromName(String name) {
    return allThemes.firstWhere((t) => t.name == name, orElse: () => dark);
  }
}
