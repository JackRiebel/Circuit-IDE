class McpServerConfig {
  final String name;
  final String url;
  final McpTransportType transport;
  final Map<String, String> headers;
  final bool enabled;
  final String? scriptPath;
  final List<String> requiredEnvVars;
  final int? port;

  const McpServerConfig({
    required this.name,
    required this.url,
    this.transport = McpTransportType.http,
    this.headers = const {},
    this.enabled = true,
    this.scriptPath,
    this.requiredEnvVars = const [],
    this.port,
  });

  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    return McpServerConfig(
      name: json['name'] as String,
      url: json['url'] as String,
      transport: McpTransportType.values.firstWhere(
        (t) => t.name == json['transport'],
        orElse: () => McpTransportType.http,
      ),
      headers: (json['headers'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString())) ??
          {},
      enabled: json['enabled'] as bool? ?? true,
      scriptPath: json['scriptPath'] as String?,
      requiredEnvVars: (json['requiredEnvVars'] as List?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      port: json['port'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'transport': transport.name,
        'headers': headers,
        'enabled': enabled,
        if (scriptPath != null) 'scriptPath': scriptPath,
        if (requiredEnvVars.isNotEmpty) 'requiredEnvVars': requiredEnvVars,
        if (port != null) 'port': port,
      };

  McpServerConfig copyWith({
    String? name,
    String? url,
    McpTransportType? transport,
    Map<String, String>? headers,
    bool? enabled,
    String? scriptPath,
    List<String>? requiredEnvVars,
    int? port,
  }) {
    return McpServerConfig(
      name: name ?? this.name,
      url: url ?? this.url,
      transport: transport ?? this.transport,
      headers: headers ?? this.headers,
      enabled: enabled ?? this.enabled,
      scriptPath: scriptPath ?? this.scriptPath,
      requiredEnvVars: requiredEnvVars ?? this.requiredEnvVars,
      port: port ?? this.port,
    );
  }
}

enum McpTransportType {
  http,
  websocket,
  stdio,
}

class McpToolInfo {
  final String serverName;
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  const McpToolInfo({
    required this.serverName,
    required this.name,
    required this.description,
    required this.inputSchema,
  });
}
