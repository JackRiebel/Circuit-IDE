import '../enums/ai_provider.dart';

class SettingsModel {
  final AIProviderType activeProvider;
  final String ciscoModel;
  final String anthropicModel;
  final String themeName;
  final double editorFontSize;
  final bool editorWordWrap;
  final bool editorMinimap;
  final bool autoApprove;
  final bool thinkingMode;
  final bool streamResponses;
  final String? lastProjectPath;
  final List<String> recentProjects;

  const SettingsModel({
    this.activeProvider = AIProviderType.cisco,
    this.ciscoModel = 'gpt-5-nano',
    this.anthropicModel = 'claude-sonnet-4-20250514',
    this.themeName = 'dark',
    this.editorFontSize = 14.0,
    this.editorWordWrap = false,
    this.editorMinimap = true,
    this.autoApprove = false,
    this.thinkingMode = false,
    this.streamResponses = true,
    this.lastProjectPath,
    this.recentProjects = const [],
  });

  SettingsModel copyWith({
    AIProviderType? activeProvider,
    String? ciscoModel,
    String? anthropicModel,
    String? themeName,
    double? editorFontSize,
    bool? editorWordWrap,
    bool? editorMinimap,
    bool? autoApprove,
    bool? thinkingMode,
    bool? streamResponses,
    String? lastProjectPath,
    List<String>? recentProjects,
  }) {
    return SettingsModel(
      activeProvider: activeProvider ?? this.activeProvider,
      ciscoModel: ciscoModel ?? this.ciscoModel,
      anthropicModel: anthropicModel ?? this.anthropicModel,
      themeName: themeName ?? this.themeName,
      editorFontSize: editorFontSize ?? this.editorFontSize,
      editorWordWrap: editorWordWrap ?? this.editorWordWrap,
      editorMinimap: editorMinimap ?? this.editorMinimap,
      autoApprove: autoApprove ?? this.autoApprove,
      thinkingMode: thinkingMode ?? this.thinkingMode,
      streamResponses: streamResponses ?? this.streamResponses,
      lastProjectPath: lastProjectPath ?? this.lastProjectPath,
      recentProjects: recentProjects ?? this.recentProjects,
    );
  }
}
