import 'package:dio/dio.dart';

import '../../core/utils/logger.dart';
import 'mcp_config.dart';
import 'mcp_token_storage.dart';

/// JSON-RPC message for MCP protocol
class JsonRpcMessage {
  final String jsonrpc;
  final String? method;
  final dynamic params;
  final dynamic id;
  final dynamic result;
  final Map<String, dynamic>? error;

  const JsonRpcMessage({
    this.jsonrpc = '2.0',
    this.method,
    this.params,
    this.id,
    this.result,
    this.error,
  });

  factory JsonRpcMessage.fromJson(Map<String, dynamic> json) {
    return JsonRpcMessage(
      jsonrpc: json['jsonrpc'] as String? ?? '2.0',
      method: json['method'] as String?,
      params: json['params'],
      id: json['id'],
      result: json['result'],
      error: json['error'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'jsonrpc': jsonrpc};
    if (method != null) map['method'] = method;
    if (params != null) map['params'] = params;
    if (id != null) map['id'] = id;
    if (result != null) map['result'] = result;
    if (error != null) map['error'] = error;
    return map;
  }

  bool get isResponse => result != null || error != null;
  bool get isError => error != null;
}

/// HTTP transport for MCP servers
class McpHttpTransport {
  final McpServerConfig config;
  final Dio _dio;
  int _requestId = 0;

  McpHttpTransport._({required this.config, required Dio dio}) : _dio = dio;

  /// Creates a transport, loading tokens from secure storage when the config
  /// has [requiredEnvVars] so that the Authorization header is built at runtime.
  static Future<McpHttpTransport> create(McpServerConfig config) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ...config.headers,
    };

    // Load token from secure storage and inject Authorization header
    if (config.requiredEnvVars.isNotEmpty) {
      final tokenStorage = McpTokenStorage();
      final tokens = await tokenStorage.loadTokens(
        config.name,
        config.requiredEnvVars,
      );
      final authEnvVar = config.requiredEnvVars.firstWhere(
        _looksLikeAuthTokenName,
        orElse: () => config.requiredEnvVars.first,
      );
      final authToken = tokens[authEnvVar];
      if (authToken != null &&
          authToken.isNotEmpty &&
          !headers.containsKey('Authorization')) {
        headers['Authorization'] = 'Bearer $authToken';
      }
    }

    final dio = Dio(
      BaseOptions(
        baseUrl: config.url,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: headers,
      ),
    );

    return McpHttpTransport._(config: config, dio: dio);
  }

  static bool _looksLikeAuthTokenName(String name) {
    final upper = name.toUpperCase();
    return upper.contains('TOKEN') ||
        upper.contains('API_KEY') ||
        upper.contains('ACCESS_KEY') ||
        upper == 'PAT';
  }

  Future<JsonRpcMessage> send(String method, [dynamic params]) async {
    final id = ++_requestId;
    final request = JsonRpcMessage(method: method, params: params, id: id);

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '',
        data: request.toJson(),
      );

      if (response.data == null) {
        return JsonRpcMessage(
          id: id,
          error: {'code': -1, 'message': 'Empty response'},
        );
      }

      return JsonRpcMessage.fromJson(response.data!);
    } on DioException catch (e) {
      Logger.error('MCP HTTP error for ${config.name}', e);
      return JsonRpcMessage(
        id: id,
        error: {
          'code': e.response?.statusCode ?? -1,
          'message': e.message ?? 'HTTP error',
        },
      );
    }
  }

  Future<JsonRpcMessage> initialize() async {
    return send('initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': {},
      'clientInfo': {'name': 'CircuitIDE', 'version': '1.0.0'},
    });
  }

  Future<JsonRpcMessage> listTools() async {
    return send('tools/list');
  }

  Future<JsonRpcMessage> callTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    return send('tools/call', {'name': name, 'arguments': arguments});
  }

  void dispose() {
    _dio.close();
  }
}
