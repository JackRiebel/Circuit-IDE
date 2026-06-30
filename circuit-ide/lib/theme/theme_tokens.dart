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

  // Terminal
  final Color terminalBg;
  final Color terminalText;

  final Color? _surfaceBase;
  final Color? _surfacePanel;
  final Color? _surfaceInset;
  final Color? _surfacePopover;
  final Color? _surfaceHover;
  final Color? _surfacePressed;
  final Color? _outlineSoft;
  final Color? _outlineFocus;

  Color get surfaceBase => _surfaceBase ?? bgMain;
  Color get surfacePanel => _surfacePanel ?? bgLight.withValues(alpha: 0.86);
  Color get surfaceInset => _surfaceInset ?? bgDark.withValues(alpha: 0.78);
  Color get surfacePopover => _surfacePopover ?? bgLighter;
  Color get surfaceHover => _surfaceHover ?? textMuted.withValues(alpha: 0.08);
  Color get surfacePressed => _surfacePressed ?? accent.withValues(alpha: 0.14);
  Color get outlineSoft => _outlineSoft ?? border.withValues(alpha: 0.45);
  Color get outlineFocus => _outlineFocus ?? accent.withValues(alpha: 0.55);

  // Compatibility aliases for the first reliability/UX pass.
  Color get surfaceRaised => surfacePanel;
  Color get surfaceOverlay => surfacePopover;
  Color get surfaceSelected => surfacePressed;
  Color get outlineSubtle => outlineSoft;
  Color get outlineStrong => borderLight.withValues(alpha: 0.78);

  Color get studioCanvas =>
      brightness == Brightness.dark ? const Color(0xFF111111) : bgDark;
  Color get studioRail => activityBarBg;
  Color get studioTopBar =>
      brightness == Brightness.dark ? const Color(0xFF141414) : bgMain;
  Color get studioPanel => surfacePanel;
  Color get studioDrawer =>
      brightness == Brightness.dark ? const Color(0xFF202020) : surfacePanel;
  Color get studioCard => brightness == Brightness.dark
      ? const Color(0xFF1B1B1B)
      : surfacePopover.withValues(alpha: 0.54);
  Color get studioComposer =>
      brightness == Brightness.dark ? const Color(0xFF262626) : inputBg;
  Color get studioBubble =>
      brightness == Brightness.dark ? const Color(0xFF242424) : userMsgBg;
  Color get studioControl =>
      brightness == Brightness.dark ? const Color(0xFF2C2C2C) : surfacePanel;
  Color get studioActivityRow =>
      brightness == Brightness.dark ? const Color(0xFF191919) : surfacePanel;
  Color get studioRailSelected =>
      brightness == Brightness.dark ? const Color(0xFF333333) : surfacePressed;
  Color get studioTaskSelected =>
      brightness == Brightness.dark ? const Color(0xFF2A2A2A) : surfacePressed;
  Color get studioDivider => outlineSoft;
  Color get studioHover => surfaceHover;

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
    required this.terminalBg,
    required this.terminalText,
    Color? surfaceBase,
    Color? surfacePanel,
    Color? surfaceInset,
    Color? surfacePopover,
    Color? surfaceHover,
    Color? surfacePressed,
    Color? outlineSoft,
    Color? outlineFocus,
  }) : _surfaceBase = surfaceBase,
       _surfacePanel = surfacePanel,
       _surfaceInset = surfaceInset,
       _surfacePopover = surfacePopover,
       _surfaceHover = surfaceHover,
       _surfacePressed = surfacePressed,
       _outlineSoft = outlineSoft,
       _outlineFocus = outlineFocus;

  static const dark = ThemeTokens(
    name: 'dark',
    displayName: 'Dark',
    brightness: Brightness.dark,
    bgDark: Color(0xFF111111),
    bgMain: Color(0xFF151515),
    bgLight: Color(0xFF202020),
    bgLighter: Color(0xFF2A2A2A),
    border: Color(0xFF2D2D2D),
    borderLight: Color(0xFF3A3A3A),
    textPrimary: Color(0xFFECECEC),
    textSecondary: Color(0xFFC9C9C9),
    textMuted: Color(0xFF8E8E8E),
    textDisabled: Color(0xFF5C5C5C),
    accent: Color(0xFF7EA7A0),
    accentHover: Color(0xFF95BBB4),
    success: Color(0xFF7FB58B),
    warning: Color(0xFFD4B06A),
    error: Color(0xFFE27D73),
    info: Color(0xFF8FAFCE),
    activityBarBg: Color(0xFF1C1C1C),
    activityBarIcon: Color(0xFF8E8E8E),
    activityBarIconActive: Color(0xFFE6E6E6),
    activityBarBadge: Color(0xFF7EA7A0),
    editorBg: Color(0xFF131313),
    editorLineHighlight: Color(0xFF222222),
    editorSelection: Color(0xFF354A4A),
    editorCursor: Color(0xFFDCDCDC),
    editorLineNumber: Color(0xFF666666),
    editorLineNumberActive: Color(0xFFC2C2C2),
    userMsgBg: Color(0xFF242424),
    agentMsgBg: Color(0xFF151515),
    codeBlockBg: Color(0xFF111111),
    codeBlockBorder: Color(0xFF343434),
    inputBg: Color(0xFF242424),
    inputBorder: Color(0xFF343434),
    inputFocusBorder: Color(0xFF7EA7A0),
    tabActive: Color(0xFF171717),
    tabInactive: Color(0xFF202020),
    tabHover: Color(0xFF2B2B2B),
    tabIndicator: Color(0xFF7EA7A0),
    statusBarBg: Color(0xFF222222),
    statusBarText: Color(0xFFDCDCDC),
    circuitColor: Color(0xFF9AC7C0),
    terminalBg: Color(0xFF111111),
    terminalText: Color(0xFFDCDCDC),
    surfaceBase: Color(0xFF151515),
    surfacePanel: Color(0xFF202020),
    surfaceInset: Color(0xFF101010),
    surfacePopover: Color(0xFF2A2A2A),
    surfaceHover: Color(0x14E6E6E6),
    surfacePressed: Color(0x1F7EA7A0),
    outlineSoft: Color(0x553A3A3A),
    outlineFocus: Color(0x887EA7A0),
  );

  static const light = ThemeTokens(
    name: 'light',
    displayName: 'Light',
    brightness: Brightness.light,
    bgDark: Color(0xFFF2EFEA),
    bgMain: Color(0xFFFAF8F4),
    bgLight: Color(0xFFF3F0EA),
    bgLighter: Color(0xFFEAE5DD),
    border: Color(0xFFD8D1C6),
    borderLight: Color(0xFFC8BFB2),
    textPrimary: Color(0xFF2F2C29),
    textSecondary: Color(0xFF635C54),
    textMuted: Color(0xFF8B8176),
    textDisabled: Color(0xFFB7AEA3),
    accent: Color(0xFF577F78),
    accentHover: Color(0xFF456B65),
    success: Color(0xFF3E8456),
    warning: Color(0xFFB27A22),
    error: Color(0xFFC7534B),
    info: Color(0xFF587C9D),
    activityBarBg: Color(0xFFE9E4DC),
    activityBarIcon: Color(0xFF8B8176),
    activityBarIconActive: Color(0xFF2F2C29),
    activityBarBadge: Color(0xFF577F78),
    editorBg: Color(0xFFFAF8F4),
    editorLineHighlight: Color(0xFFF0ECE5),
    editorSelection: Color(0xFFCFE0DC),
    editorCursor: Color(0xFF2F2C29),
    editorLineNumber: Color(0xFFB7AEA3),
    editorLineNumberActive: Color(0xFF635C54),
    userMsgBg: Color(0xFFE7F0ED),
    agentMsgBg: Color(0xFFF3F0EA),
    codeBlockBg: Color(0xFFEDE9E1),
    codeBlockBorder: Color(0xFFD8D1C6),
    inputBg: Color(0xFFFFFFFF),
    inputBorder: Color(0xFFD8D1C6),
    inputFocusBorder: Color(0xFF577F78),
    tabActive: Color(0xFFFAF8F4),
    tabInactive: Color(0xFFEDE8E0),
    tabHover: Color(0xFFE6E0D7),
    tabIndicator: Color(0xFF577F78),
    statusBarBg: Color(0xFFE6E0D7),
    statusBarText: Color(0xFF4F4942),
    circuitColor: Color(0xFF577F78),
    terminalBg: Color(0xFFFAF8F4),
    terminalText: Color(0xFF2F2C29),
    surfaceBase: Color(0xFFFAF8F4),
    surfacePanel: Color(0xFFF3F0EA),
    surfaceInset: Color(0xFFF2EFEA),
    surfacePopover: Color(0xFFFFFFFF),
    surfaceHover: Color(0x1A2F2C29),
    surfacePressed: Color(0x22577F78),
    outlineSoft: Color(0x99D8D1C6),
    outlineFocus: Color(0x99577F78),
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
    terminalBg: Color(0xFF00212B),
    terminalText: Color(0xFF839496),
  );

  static const allThemes = [dark, light, midnight, forest, solarized];

  static ThemeTokens fromName(String name) {
    return allThemes.firstWhere((t) => t.name == name, orElse: () => dark);
  }
}
