import '../enums/ai_provider.dart';
import '../agent/providers/provider_interface.dart';

class SettingsModel {
  final AIProviderType activeProvider;
  final String ciscoModel;
  final List<ConnectorModelInfo> connectorModels;
  final DateTime? connectorModelsRefreshedAt;
  final ConnectorHealthStatus connectorHealthStatus;
  final String? connectorHealthMessage;
  final String connectorHealthEndpoint;
  final int connectorHealthProtocolVersion;
  final int connectorHealthLatencyMs;
  final ConnectorHealthErrorCategory connectorHealthErrorCategory;
  final String connectorHealthRetryAdvice;
  final String themeName;
  final double editorFontSize;
  final bool editorWordWrap;
  final bool editorMinimap;
  final bool autoApprove;
  final bool thinkingMode;
  final bool streamResponses;
  final bool sendOnEnter;
  final int diagnosticRetentionDays;
  final bool crashReportingEnabled;
  final String? lastProjectPath;
  final List<String> recentProjects;

  const SettingsModel({
    this.activeProvider = AIProviderType.cisco,
    this.ciscoModel = 'gpt-5-nano',
    this.connectorModels = const [],
    this.connectorModelsRefreshedAt,
    this.connectorHealthStatus = ConnectorHealthStatus.unknown,
    this.connectorHealthMessage,
    this.connectorHealthEndpoint = '',
    this.connectorHealthProtocolVersion = 0,
    this.connectorHealthLatencyMs = 0,
    this.connectorHealthErrorCategory = ConnectorHealthErrorCategory.none,
    this.connectorHealthRetryAdvice = '',
    this.themeName = 'dark',
    this.editorFontSize = 14.0,
    this.editorWordWrap = false,
    this.editorMinimap = true,
    this.autoApprove = false,
    this.thinkingMode = false,
    this.streamResponses = true,
    this.sendOnEnter = true,
    this.diagnosticRetentionDays = 14,
    this.crashReportingEnabled = false,
    this.lastProjectPath,
    this.recentProjects = const [],
  });

  SettingsModel copyWith({
    AIProviderType? activeProvider,
    String? ciscoModel,
    List<ConnectorModelInfo>? connectorModels,
    DateTime? connectorModelsRefreshedAt,
    ConnectorHealthStatus? connectorHealthStatus,
    String? connectorHealthMessage,
    String? connectorHealthEndpoint,
    int? connectorHealthProtocolVersion,
    int? connectorHealthLatencyMs,
    ConnectorHealthErrorCategory? connectorHealthErrorCategory,
    String? connectorHealthRetryAdvice,
    String? themeName,
    double? editorFontSize,
    bool? editorWordWrap,
    bool? editorMinimap,
    bool? autoApprove,
    bool? thinkingMode,
    bool? streamResponses,
    bool? sendOnEnter,
    int? diagnosticRetentionDays,
    bool? crashReportingEnabled,
    Object? lastProjectPath = _sentinel,
    List<String>? recentProjects,
  }) {
    return SettingsModel(
      activeProvider: activeProvider ?? this.activeProvider,
      ciscoModel: ciscoModel ?? this.ciscoModel,
      connectorModels: connectorModels ?? this.connectorModels,
      connectorModelsRefreshedAt:
          connectorModelsRefreshedAt ?? this.connectorModelsRefreshedAt,
      connectorHealthStatus:
          connectorHealthStatus ?? this.connectorHealthStatus,
      connectorHealthMessage:
          connectorHealthMessage ?? this.connectorHealthMessage,
      connectorHealthEndpoint:
          connectorHealthEndpoint ?? this.connectorHealthEndpoint,
      connectorHealthProtocolVersion:
          connectorHealthProtocolVersion ?? this.connectorHealthProtocolVersion,
      connectorHealthLatencyMs:
          connectorHealthLatencyMs ?? this.connectorHealthLatencyMs,
      connectorHealthErrorCategory:
          connectorHealthErrorCategory ?? this.connectorHealthErrorCategory,
      connectorHealthRetryAdvice:
          connectorHealthRetryAdvice ?? this.connectorHealthRetryAdvice,
      themeName: themeName ?? this.themeName,
      editorFontSize: editorFontSize ?? this.editorFontSize,
      editorWordWrap: editorWordWrap ?? this.editorWordWrap,
      editorMinimap: editorMinimap ?? this.editorMinimap,
      autoApprove: autoApprove ?? this.autoApprove,
      thinkingMode: thinkingMode ?? this.thinkingMode,
      streamResponses: streamResponses ?? this.streamResponses,
      sendOnEnter: sendOnEnter ?? this.sendOnEnter,
      diagnosticRetentionDays:
          diagnosticRetentionDays ?? this.diagnosticRetentionDays,
      crashReportingEnabled:
          crashReportingEnabled ?? this.crashReportingEnabled,
      lastProjectPath: identical(lastProjectPath, _sentinel)
          ? this.lastProjectPath
          : lastProjectPath as String?,
      recentProjects: recentProjects ?? this.recentProjects,
    );
  }
}

const _sentinel = Object();
