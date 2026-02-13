class McpServerConfig {
  final String name;
  final String url;
  final McpTransportType transport;
  final Map<String, String> headers;
  final bool enabled;

  const McpServerConfig({
    required this.name,
    required this.url,
    this.transport = McpTransportType.http,
    this.headers = const {},
    this.enabled = true,
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
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'transport': transport.name,
        'headers': headers,
        'enabled': enabled,
      };

  McpServerConfig copyWith({
    String? name,
    String? url,
    McpTransportType? transport,
    Map<String, String>? headers,
    bool? enabled,
  }) {
    return McpServerConfig(
      name: name ?? this.name,
      url: url ?? this.url,
      transport: transport ?? this.transport,
      headers: headers ?? this.headers,
      enabled: enabled ?? this.enabled,
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
