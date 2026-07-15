import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../agent/config/models_config.dart';
import '../agent/providers/provider_interface.dart';
import '../core/utils/platform_utils.dart';
import '../enums/ai_provider.dart';
import '../models/settings_model.dart';
import '../services/versioned_json_document.dart';

class SettingsNotifier extends Notifier<SettingsModel> {
  static const _schemaKind = 'circuit.ui-settings';
  static const _schemaVersion = 5;
  static String? debugSettingsFileOverride;
  bool _settingsSchemaUnsupported = false;

  @override
  SettingsModel build() {
    _load();
    return const SettingsModel();
  }

  static String get _settingsFile =>
      debugSettingsFileOverride ??
      p.join(PlatformUtils.configDir, 'ui_settings.json');

  Future<void> _load() async {
    try {
      final file = File(_settingsFile);
      if (await file.exists()) {
        final contents = await file.readAsString();
        final document = VersionedJsonDocument.decode(
          jsonDecode(contents),
          expectedKind: _schemaKind,
          currentSchemaVersion: _schemaVersion,
        );
        final payload = document.payload;
        if (payload is! Map) {
          throw const FormatException('Settings payload is not an object.');
        }
        final json = Map<String, dynamic>.from(payload);
        final connectorModels =
            (json['connector_models'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(ConnectorModelInfo.fromJson)
                .whereType<ConnectorModelInfo>()
                .toList() ??
            const <ConnectorModelInfo>[];
        final loadedRecent =
            (json['recent_projects'] as List<dynamic>?)?.cast<String>() ?? [];
        final mergedRecent = [
          ...state.recentProjects,
          for (final path in loadedRecent)
            if (!state.recentProjects.contains(path)) path,
        ];
        state = SettingsModel(
          activeProvider: AIProviderType.cisco,
          ciscoModel: _coerceCiscoModel(
            json['cisco_model'] as String?,
            connectorModels,
          ),
          connectorModels: connectorModels,
          connectorModelsRefreshedAt: DateTime.tryParse(
            json['connector_models_refreshed_at'] as String? ?? '',
          ),
          connectorHealthStatus: ConnectorHealthStatus.values.firstWhere(
            (status) => status.name == json['connector_health_status'],
            orElse: () => ConnectorHealthStatus.unknown,
          ),
          connectorHealthMessage: json['connector_health_message'] as String?,
          connectorHealthEndpoint:
              json['connector_health_endpoint'] as String? ?? '',
          connectorHealthProtocolVersion:
              json['connector_health_protocol_version'] as int? ?? 0,
          connectorHealthLatencyMs:
              json['connector_health_latency_ms'] as int? ?? 0,
          connectorHealthErrorCategory: ConnectorHealthErrorCategory.values
              .firstWhere(
                (category) =>
                    category.name == json['connector_health_error_category'],
                orElse: () => ConnectorHealthErrorCategory.none,
              ),
          connectorHealthRetryAdvice:
              json['connector_health_retry_advice'] as String? ?? '',
          themeName: json['theme'] as String? ?? 'dark',
          editorFontSize:
              (json['editor_font_size'] as num?)?.toDouble() ?? 14.0,
          editorWordWrap: json['editor_word_wrap'] as bool? ?? false,
          editorMinimap: json['editor_minimap'] as bool? ?? true,
          autoApprove: json['auto_approve'] as bool? ?? false,
          thinkingMode: json['thinking_mode'] as bool? ?? false,
          streamResponses: json['stream_responses'] as bool? ?? true,
          sendOnEnter: json['send_on_enter'] as bool? ?? true,
          diagnosticRetentionDays: _diagnosticRetentionDays(
            json['diagnostic_retention_days'],
          ),
          crashReportingEnabled:
              json['crash_reporting_enabled'] as bool? ?? false,
          lastProjectPath: json['last_project_path'] as String?,
          recentProjects: mergedRecent,
        );
        if (document.schemaVersion < _schemaVersion) {
          await migrateVersionedJsonFile(
            file: file,
            originalContents: contents,
            migratedContents: _encode(state),
            previousSchemaVersion: document.schemaVersion,
          );
        }
      }
    } on UnsupportedRuntimeSchemaVersion catch (error) {
      _settingsSchemaUnsupported = true;
      state = state.copyWith(connectorHealthMessage: error.toString());
    } catch (_) {}
  }

  Future<void> _save() async {
    if (_settingsSchemaUnsupported) return;
    try {
      final dir = Directory(PlatformUtils.configDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File(_settingsFile);
      await writeVersionedJsonAtomically(file, _encode(state));
    } catch (_) {}
  }

  String _encode(SettingsModel value) {
    final payload = {
      'active_provider': value.activeProvider.name,
      'cisco_model': value.ciscoModel,
      'connector_models': value.connectorModels
          .map((model) => model.toJson())
          .toList(),
      'connector_models_refreshed_at': value.connectorModelsRefreshedAt
          ?.toIso8601String(),
      'connector_health_status': value.connectorHealthStatus.name,
      'connector_health_message': value.connectorHealthMessage,
      'connector_health_endpoint': value.connectorHealthEndpoint,
      'connector_health_protocol_version': value.connectorHealthProtocolVersion,
      'connector_health_latency_ms': value.connectorHealthLatencyMs,
      'connector_health_error_category':
          value.connectorHealthErrorCategory.name,
      'connector_health_retry_advice': value.connectorHealthRetryAdvice,
      'theme': value.themeName,
      'editor_font_size': value.editorFontSize,
      'editor_word_wrap': value.editorWordWrap,
      'editor_minimap': value.editorMinimap,
      'auto_approve': value.autoApprove,
      'thinking_mode': value.thinkingMode,
      'stream_responses': value.streamResponses,
      'send_on_enter': value.sendOnEnter,
      'diagnostic_retention_days': value.diagnosticRetentionDays,
      'crash_reporting_enabled': value.crashReportingEnabled,
      'last_project_path': value.lastProjectPath,
      'recent_projects': value.recentProjects,
    };
    return VersionedJsonDocument(
      kind: _schemaKind,
      schemaVersion: _schemaVersion,
      payload: payload,
    ).encode(pretty: true);
  }

  void setTheme(String themeName) {
    state = state.copyWith(themeName: themeName);
    _save();
  }

  void setActiveProvider(AIProviderType provider) {
    state = state.copyWith(activeProvider: AIProviderType.cisco);
    _save();
  }

  void setCiscoModel(String model) {
    final selectedModel = _coerceCiscoModel(model);
    state = state.copyWith(
      ciscoModel: selectedModel,
      thinkingMode: _modelInfoFor(selectedModel)?.supportsReasoning == true
          ? state.thinkingMode
          : false,
    );
    _save();
  }

  void setConnectorModels(List<ConnectorModelInfo> models) {
    final selectedModel = _coerceCiscoModel(state.ciscoModel, models);
    state = state.copyWith(
      connectorModels: models,
      ciscoModel: selectedModel,
      thinkingMode:
          _modelInfoFor(selectedModel, models)?.supportsReasoning == true
          ? state.thinkingMode
          : false,
      connectorModelsRefreshedAt: DateTime.now(),
    );
    _save();
  }

  String _coerceCiscoModel(
    String? model, [
    List<ConnectorModelInfo>? connectorModels,
  ]) {
    final trimmed = model?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return ModelsConfig.defaultCiscoModel;
    }
    final knownStatic = ModelsConfig.ciscoModels.any((m) => m.id == trimmed);
    final knownConnector = (connectorModels ?? state.connectorModels).any(
      (m) => m.id == trimmed,
    );
    if (knownStatic || knownConnector) return trimmed;
    return ModelsConfig.defaultCiscoModel;
  }

  ModelInfo? _modelInfoFor(
    String id, [
    List<ConnectorModelInfo>? connectorModels,
  ]) {
    for (final model in connectorModels ?? state.connectorModels) {
      if (model.id == id) return model.toModelInfo();
    }
    return ModelsConfig.getModel(id);
  }

  void setConnectorHealth(ConnectorHealth health) {
    state = state.copyWith(
      connectorHealthStatus: health.status,
      connectorHealthMessage: health.message,
      connectorHealthEndpoint: health.endpoint,
      connectorHealthProtocolVersion: health.protocolVersion,
      connectorHealthLatencyMs: health.latency?.inMilliseconds ?? 0,
      connectorHealthErrorCategory: health.errorCategory,
      connectorHealthRetryAdvice: health.retryAdvice,
    );
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
    final supported =
        _modelInfoFor(state.ciscoModel)?.supportsReasoning == true;
    state = state.copyWith(thinkingMode: supported && value);
    _save();
  }

  void setSendOnEnter(bool value) {
    state = state.copyWith(sendOnEnter: value);
    _save();
  }

  void setDiagnosticRetentionDays(int days) {
    state = state.copyWith(
      diagnosticRetentionDays: _diagnosticRetentionDays(days),
    );
    _save();
  }

  void setCrashReportingEnabled(bool enabled) {
    state = state.copyWith(crashReportingEnabled: enabled);
    _save();
  }

  static int _diagnosticRetentionDays(Object? value) {
    final days = value is num ? value.toInt() : 14;
    return switch (days) {
      7 || 14 || 30 => days,
      _ => 14,
    };
  }

  void addRecentProject(String path) {
    final projects = List<String>.from(state.recentProjects);
    projects.remove(path);
    projects.insert(0, path);
    state = state.copyWith(recentProjects: projects, lastProjectPath: path);
    _save();
  }

  /// Replaces a previously stored path with the canonical root returned by
  /// the native workspace-access boundary. This prevents a symlink or legacy
  /// spelling from repeatedly reopening the same project as a distinct recent
  /// workspace after macOS has resolved its security-scoped bookmark.
  void replaceRecentProjectPath({
    required String requestedPath,
    required String resolvedPath,
  }) {
    final projects = List<String>.from(state.recentProjects)
      ..remove(requestedPath)
      ..remove(resolvedPath)
      ..insert(0, resolvedPath);
    state = state.copyWith(
      recentProjects: projects,
      lastProjectPath: resolvedPath,
    );
    _save();
  }

  void removeRecentProject(String path) {
    final projects = List<String>.from(state.recentProjects)..remove(path);
    state = state.copyWith(
      recentProjects: projects,
      lastProjectPath: state.lastProjectPath == path
          ? null
          : state.lastProjectPath,
    );
    _save();
  }

  Future<void> pruneRecentProjects() async {
    final kept = <String>[];
    for (final path in state.recentProjects) {
      final dir = Directory(path);
      if (await dir.exists()) {
        kept.add(path);
      }
    }
    state = state.copyWith(
      recentProjects: kept,
      lastProjectPath: kept.contains(state.lastProjectPath)
          ? state.lastProjectPath
          : null,
    );
    _save();
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsModel>(
  SettingsNotifier.new,
);
