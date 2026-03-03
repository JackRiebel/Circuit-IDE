import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/utils/platform_utils.dart';
import '../enums/ai_provider.dart';
import '../models/settings_model.dart';

class SettingsNotifier extends Notifier<SettingsModel> {
  @override
  SettingsModel build() {
    _load();
    return const SettingsModel();
  }

  static String get _settingsFile =>
      p.join(PlatformUtils.configDir, 'ui_settings.json');

  Future<void> _load() async {
    try {
      final file = File(_settingsFile);
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        state = SettingsModel(
          activeProvider: AIProviderType.values.firstWhere(
            (p) => p.name == json['active_provider'],
            orElse: () => AIProviderType.cisco,
          ),
          ciscoModel: json['cisco_model'] as String? ?? 'gpt-4.1',
          anthropicModel:
              json['anthropic_model'] as String? ?? 'claude-sonnet-4-20250514',
          themeName: json['theme'] as String? ?? 'dark',
          editorFontSize:
              (json['editor_font_size'] as num?)?.toDouble() ?? 14.0,
          editorWordWrap: json['editor_word_wrap'] as bool? ?? false,
          editorMinimap: json['editor_minimap'] as bool? ?? true,
          autoApprove: json['auto_approve'] as bool? ?? false,
          thinkingMode: json['thinking_mode'] as bool? ?? false,
          streamResponses: json['stream_responses'] as bool? ?? true,
          lastProjectPath: json['last_project_path'] as String?,
          recentProjects: (json['recent_projects'] as List<dynamic>?)
                  ?.cast<String>() ??
              [],
        );
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final dir = Directory(PlatformUtils.configDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File(_settingsFile);
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert({
        'active_provider': state.activeProvider.name,
        'cisco_model': state.ciscoModel,
        'anthropic_model': state.anthropicModel,
        'theme': state.themeName,
        'editor_font_size': state.editorFontSize,
        'editor_word_wrap': state.editorWordWrap,
        'editor_minimap': state.editorMinimap,
        'auto_approve': state.autoApprove,
        'thinking_mode': state.thinkingMode,
        'stream_responses': state.streamResponses,
        'last_project_path': state.lastProjectPath,
        'recent_projects': state.recentProjects,
      }));
    } catch (_) {}
  }

  void setTheme(String themeName) {
    state = state.copyWith(themeName: themeName);
    _save();
  }

  void setActiveProvider(AIProviderType provider) {
    state = state.copyWith(activeProvider: provider);
    _save();
  }

  void setCiscoModel(String model) {
    state = state.copyWith(ciscoModel: model);
    _save();
  }

  void setAnthropicModel(String model) {
    state = state.copyWith(anthropicModel: model);
    _save();
  }

  void setEditorFontSize(double size) {
    state = state.copyWith(editorFontSize: size);
    _save();
  }

  void toggleWordWrap() {
    state = state.copyWith(editorWordWrap: !state.editorWordWrap);
    _save();
  }

  void toggleMinimap() {
    state = state.copyWith(editorMinimap: !state.editorMinimap);
    _save();
  }

  void setAutoApprove(bool value) {
    state = state.copyWith(autoApprove: value);
    _save();
  }

  void setThinkingMode(bool value) {
    state = state.copyWith(thinkingMode: value);
    _save();
  }

  void addRecentProject(String path) {
    final projects = List<String>.from(state.recentProjects);
    projects.remove(path);
    projects.insert(0, path);
    if (projects.length > 10) projects.removeLast();
    state = state.copyWith(
      recentProjects: projects,
      lastProjectPath: path,
    );
    _save();
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsModel>(SettingsNotifier.new);
