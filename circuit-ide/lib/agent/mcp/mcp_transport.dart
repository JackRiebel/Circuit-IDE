import 'package:dio/dio.dart';

import '../../core/utils/logger.dart';
import 'mcp_config.dart';

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

  McpHttpTransport({required this.config})
      : _dio = Dio(BaseOptions(
          baseUrl: config.url,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'Content-Type': 'application/json',
            ...config.headers,
          },
        ));

  Future<JsonRpcMessage> send(String method, [dynamic params]) async {
    final id = ++_requestId;
    final request = JsonRpcMessage(
      method: method,
      params: params,
      id: id,
    );

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
      'clientInfo': {
        'name': 'CircuitIDE',
        'version': '1.0.0',
      },
    });
  }

  Future<JsonRpcMessage> listTools() async {
    return send('tools/list');
  }

  Future<JsonRpcMessage> callTool(
      String name, Map<String, dynamic> arguments) async {
    return send('tools/call', {
      'name': name,
      'arguments': arguments,
    });
  }

  void dispose() {
    _dio.close();
  }
}
