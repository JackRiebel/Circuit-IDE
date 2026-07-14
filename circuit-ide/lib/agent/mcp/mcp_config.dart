class McpServerConfig {
  final String name;
  final String url;
  final McpTransportType transport;
  final Map<String, String> headers;

  /// Header names mapped to their Keychain-backed token keys. Values are
  /// intentionally non-secret and safe to persist in the MCP config file.
  final Map<String, String> secureHeaderEnvVars;
  final bool enabled;

  /// Connector-specific consent metadata is safe to persist. Tokens remain in
  /// Keychain and are never represented here.
  final McpConnectorKind connectorKind;
  final List<String> requestedScopes;
  final String dataAccessSummary;
  final DateTime? consentedAt;
  final DateTime? lastTestedAt;
  final DateTime? lastUsedAt;

  /// Server configs are inert until a user explicitly approves their current
  /// endpoint and declared environment requirements in CircuitCode.
  final DateTime? approvedAt;
  final String? scriptPath;
  final List<String> requiredEnvVars;
  final int? port;

  const McpServerConfig({
    required this.name,
    required this.url,
    this.transport = McpTransportType.http,
    this.headers = const {},
    this.secureHeaderEnvVars = const {},
    this.enabled = true,
    this.connectorKind = McpConnectorKind.custom,
    this.requestedScopes = const [],
    this.dataAccessSummary = '',
    this.consentedAt,
    this.lastTestedAt,
    this.lastUsedAt,
    this.approvedAt,
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
      headers:
          (json['headers'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v.toString()),
          ) ??
          {},
      secureHeaderEnvVars:
          (json['secureHeaderEnvVars'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v.toString()),
          ) ??
          {},
      enabled: json['enabled'] as bool? ?? true,
      connectorKind: McpConnectorKind.values.firstWhere(
        (kind) => kind.name == json['connectorKind'],
        orElse: () => McpConnectorKind.custom,
      ),
      requestedScopes:
          (json['requestedScopes'] as List?)?.whereType<String>().toList() ??
          const [],
      dataAccessSummary: json['dataAccessSummary'] as String? ?? '',
      consentedAt: DateTime.tryParse(json['consentedAt'] as String? ?? ''),
      lastTestedAt: DateTime.tryParse(json['lastTestedAt'] as String? ?? ''),
      lastUsedAt: DateTime.tryParse(json['lastUsedAt'] as String? ?? ''),
      approvedAt: DateTime.tryParse(json['approvedAt'] as String? ?? ''),
      scriptPath: json['scriptPath'] as String?,
      requiredEnvVars:
          (json['requiredEnvVars'] as List?)
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
    if (secureHeaderEnvVars.isNotEmpty)
      'secureHeaderEnvVars': secureHeaderEnvVars,
    'enabled': enabled,
    'connectorKind': connectorKind.name,
    if (requestedScopes.isNotEmpty) 'requestedScopes': requestedScopes,
    if (dataAccessSummary.isNotEmpty) 'dataAccessSummary': dataAccessSummary,
    if (consentedAt != null) 'consentedAt': consentedAt!.toIso8601String(),
    if (lastTestedAt != null) 'lastTestedAt': lastTestedAt!.toIso8601String(),
    if (lastUsedAt != null) 'lastUsedAt': lastUsedAt!.toIso8601String(),
    if (approvedAt != null) 'approvedAt': approvedAt!.toIso8601String(),
    if (scriptPath != null) 'scriptPath': scriptPath,
    if (requiredEnvVars.isNotEmpty) 'requiredEnvVars': requiredEnvVars,
    if (port != null) 'port': port,
  };

  McpServerConfig copyWith({
    String? name,
    String? url,
    McpTransportType? transport,
    Map<String, String>? headers,
    Map<String, String>? secureHeaderEnvVars,
    bool? enabled,
    McpConnectorKind? connectorKind,
    List<String>? requestedScopes,
    String? dataAccessSummary,
    Object? consentedAt = _sentinel,
    Object? lastTestedAt = _sentinel,
    Object? lastUsedAt = _sentinel,
    Object? approvedAt = _sentinel,
    String? scriptPath,
    List<String>? requiredEnvVars,
    int? port,
  }) {
    return McpServerConfig(
      name: name ?? this.name,
      url: url ?? this.url,
      transport: transport ?? this.transport,
      headers: headers ?? this.headers,
      secureHeaderEnvVars: secureHeaderEnvVars ?? this.secureHeaderEnvVars,
      enabled: enabled ?? this.enabled,
      connectorKind: connectorKind ?? this.connectorKind,
      requestedScopes: requestedScopes ?? this.requestedScopes,
      dataAccessSummary: dataAccessSummary ?? this.dataAccessSummary,
      consentedAt: identical(consentedAt, _sentinel)
          ? this.consentedAt
          : consentedAt as DateTime?,
      lastTestedAt: identical(lastTestedAt, _sentinel)
          ? this.lastTestedAt
          : lastTestedAt as DateTime?,
      lastUsedAt: identical(lastUsedAt, _sentinel)
          ? this.lastUsedAt
          : lastUsedAt as DateTime?,
      approvedAt: identical(approvedAt, _sentinel)
          ? this.approvedAt
          : approvedAt as DateTime?,
      scriptPath: scriptPath ?? this.scriptPath,
      requiredEnvVars: requiredEnvVars ?? this.requiredEnvVars,
      port: port ?? this.port,
    );
  }
}

const _sentinel = Object();

enum McpTransportType { http, websocket, stdio }

enum McpConnectorKind { custom, webex, jira, github }

extension McpConnectorConsent on McpConnectorKind {
  String get label => switch (this) {
    McpConnectorKind.custom => 'Custom MCP server',
    McpConnectorKind.webex => 'Webex Teams',
    McpConnectorKind.jira => 'Jira',
    McpConnectorKind.github => 'GitHub',
  };

  List<String> get defaultScopes => switch (this) {
    McpConnectorKind.webex => const ['rooms:read', 'messages:read'],
    McpConnectorKind.jira => const ['issues:read', 'projects:read'],
    McpConnectorKind.github => const [
      'repo:read',
      'issues:read',
      'pull_requests:read',
    ],
    McpConnectorKind.custom => const [],
  };

  String get defaultDataAccessSummary => switch (this) {
    McpConnectorKind.webex =>
      'Reads the selected Webex rooms and messages exposed by the configured MCP server.',
    McpConnectorKind.jira =>
      'Reads Jira projects and issues exposed by the configured MCP server.',
    McpConnectorKind.github =>
      'Reads GitHub repository, issue, and pull-request data exposed by the configured MCP server.',
    McpConnectorKind.custom =>
      'Access is limited to the read-only tools declared by this MCP server after review.',
  };
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
