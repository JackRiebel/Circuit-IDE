import '../../enums/ai_provider.dart';
import '../config/models_config.dart';

enum BotAgentState { stopped, starting, running, error }

/// Configuration model for the Webex bot agent.
class BotAgentConfig {
  final String? scriptPath;
  final int port;
  final String model;
  final String? systemPrompt;
  final List<String> roomIds;
  final List<String> mcpServerUrls;

  static const requiredEnvVars = ['WEBEX_TOKEN', 'OPENAI_API_KEY'];

  const BotAgentConfig({
    this.scriptPath,
    this.port = 8090,
    this.model = ModelsConfig.defaultCiscoModel,
    this.systemPrompt,
    this.roomIds = const [],
    this.mcpServerUrls = const [],
  });

  factory BotAgentConfig.fromJson(Map<String, dynamic> json) {
    return BotAgentConfig(
      scriptPath: json['scriptPath'] as String?,
      port: json['port'] as int? ?? 8090,
      model: ModelsConfig.coerceModelForProvider(
        AIProviderType.cisco,
        json['model'] as String?,
      ),
      systemPrompt: json['systemPrompt'] as String?,
      roomIds:
          (json['roomIds'] as List?)?.map((e) => e as String).toList() ??
          const [],
      mcpServerUrls:
          (json['mcpServerUrls'] as List?)?.map((e) => e as String).toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
    if (scriptPath != null) 'scriptPath': scriptPath,
    'port': port,
    'model': model,
    if (systemPrompt != null) 'systemPrompt': systemPrompt,
    if (roomIds.isNotEmpty) 'roomIds': roomIds,
    if (mcpServerUrls.isNotEmpty) 'mcpServerUrls': mcpServerUrls,
  };

  BotAgentConfig copyWith({
    String? scriptPath,
    int? port,
    String? model,
    String? systemPrompt,
    List<String>? roomIds,
    List<String>? mcpServerUrls,
  }) {
    return BotAgentConfig(
      scriptPath: scriptPath ?? this.scriptPath,
      port: port ?? this.port,
      model: model ?? this.model,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      roomIds: roomIds ?? this.roomIds,
      mcpServerUrls: mcpServerUrls ?? this.mcpServerUrls,
    );
  }
}

/// Runtime status wrapper for the bot agent.
class BotAgentStatus {
  final BotAgentConfig config;
  final BotAgentState state;
  final String? error;
  final String? publicUrl;
  final int? pid;

  const BotAgentStatus({
    required this.config,
    this.state = BotAgentState.stopped,
    this.error,
    this.publicUrl,
    this.pid,
  });

  BotAgentStatus copyWith({
    BotAgentConfig? config,
    BotAgentState? state,
    String? error,
    String? publicUrl,
    int? pid,
  }) {
    return BotAgentStatus(
      config: config ?? this.config,
      state: state ?? this.state,
      error: error,
      publicUrl: publicUrl ?? this.publicUrl,
      pid: pid ?? this.pid,
    );
  }
}
