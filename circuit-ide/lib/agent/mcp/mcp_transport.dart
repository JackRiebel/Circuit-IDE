import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/utils/logger.dart';
import '../security/network_address_policy.dart';
import '../security/pinned_network_http_client.dart';
import 'mcp_config.dart';
import 'mcp_token_storage.dart';

typedef McpHostAddressResolver = NetworkHostAddressResolver;

/// A safe, non-secret explanation for why a configured remote MCP endpoint
/// cannot receive a request.
class McpEndpointPolicyException implements Exception {
  final String message;

  const McpEndpointPolicyException(this.message);

  @override
  String toString() => message;
}

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
  final Uri _endpoint;
  final McpHostAddressResolver _hostAddressResolver;
  int _requestId = 0;

  McpHttpTransport._({
    required this.config,
    required Dio dio,
    required Uri endpoint,
    required McpHostAddressResolver hostAddressResolver,
  }) : _dio = dio,
       _endpoint = endpoint,
       _hostAddressResolver = hostAddressResolver;

  /// Creates a transport, loading tokens from secure storage when the config
  /// has [requiredEnvVars] so that the Authorization header is built at runtime.
  static Future<McpHttpTransport> create(
    McpServerConfig config, {
    Dio? dio,
    McpHostAddressResolver? hostAddressResolver,
  }) async {
    final resolver = hostAddressResolver ?? InternetAddress.lookup;
    final endpoint = await _validateEndpoint(config.url, resolver);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ...config.headers,
    };
    final tokenStorage = McpTokenStorage();

    if (config.secureHeaderEnvVars.isNotEmpty) {
      final secureHeaderTokens = await tokenStorage.loadTokens(
        config.name,
        config.secureHeaderEnvVars.values.toSet().toList(),
      );
      for (final entry in config.secureHeaderEnvVars.entries) {
        final value = secureHeaderTokens[entry.value];
        if (value != null && value.isNotEmpty) {
          headers[entry.key] = value;
        }
      }
    }

    // Load token from secure storage and inject Authorization header
    if (config.requiredEnvVars.isNotEmpty) {
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

    final client =
        dio ??
        createPinnedNetworkDio(
          hostAddressResolver: resolver,
          allowExplicitLoopback: true,
          options: BaseOptions(
            baseUrl: config.url,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 30),
            headers: headers,
          ),
        );
    client.options.baseUrl = endpoint.toString();
    client.options.headers.addAll(headers);
    // Remote MCP headers may carry a Keychain-backed credential. Do not let a
    // transport redirect forward that credential across the approved endpoint
    // boundary; users must configure the final canonical endpoint explicitly.
    client.options.followRedirects = false;
    client.options.maxRedirects = 0;

    return McpHttpTransport._(
      config: config,
      dio: client,
      endpoint: endpoint,
      hostAddressResolver: resolver,
    );
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
      // DNS answers can change after a user approves an endpoint. Resolve the
      // same configured origin immediately before every credentialed request
      // so a public remote MCP endpoint cannot silently rebind to a local or
      // reserved address. Explicit loopback sidecars remain supported.
      await _validateEndpoint(_endpoint.toString(), _hostAddressResolver);
    } on McpEndpointPolicyException catch (error) {
      return JsonRpcMessage(
        id: id,
        error: {'code': -32000, 'message': error.message},
      );
    }

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
      // A Dio diagnostic can include the configured endpoint, response body,
      // or request metadata. Remote MCP requests can carry Keychain-backed
      // headers, so neither the raw exception nor a user-supplied connector
      // name belongs in the model-visible result or application log.
      Logger.error('MCP HTTP request failed.');
      return JsonRpcMessage(
        id: id,
        error: {
          'code': e.response?.statusCode ?? -1,
          'message': _redactedHttpErrorMessage(e),
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

  static Future<Uri> _validateEndpoint(
    String value,
    McpHostAddressResolver resolver,
  ) async {
    final endpoint = Uri.tryParse(value.trim());
    if (endpoint == null ||
        endpoint.host.trim().isEmpty ||
        !endpoint.hasScheme) {
      throw const McpEndpointPolicyException(
        'MCP endpoint must be an absolute HTTP URL.',
      );
    }
    final scheme = endpoint.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw const McpEndpointPolicyException(
        'MCP endpoint must use HTTP or HTTPS.',
      );
    }
    if (endpoint.userInfo.isNotEmpty) {
      throw const McpEndpointPolicyException(
        'MCP endpoint must not contain URL credentials.',
      );
    }
    // Query strings and fragments are not needed to identify an MCP RPC
    // endpoint. Refuse them rather than allow a static credential, signed URL,
    // or user-private routing value to reach a transport diagnostic, proxy, or
    // persisted connector configuration. Connector authentication belongs in
    // reviewed Keychain-backed headers.
    if (endpoint.hasQuery || endpoint.fragment.isNotEmpty) {
      throw const McpEndpointPolicyException(
        'MCP endpoint must not contain a query or fragment.',
      );
    }

    final host = _normalizeHost(endpoint.host);
    final loopback = _isLoopbackHost(host);
    if (!loopback && scheme != 'https') {
      throw const McpEndpointPolicyException(
        'Remote MCP endpoints must use HTTPS. Only explicit loopback sidecars may use HTTP.',
      );
    }
    if (!loopback && _blockedHostReason(host) != null) {
      throw const McpEndpointPolicyException(
        'MCP endpoint host is not an allowed public origin.',
      );
    }

    final List<InternetAddress> addresses;
    try {
      addresses = await resolver(host);
    } on SocketException {
      throw const McpEndpointPolicyException(
        'MCP endpoint could not be resolved safely.',
      );
    } catch (_) {
      throw const McpEndpointPolicyException(
        'MCP endpoint could not be resolved safely.',
      );
    }
    if (addresses.isEmpty) {
      throw const McpEndpointPolicyException(
        'MCP endpoint did not resolve to an allowed address.',
      );
    }
    for (final address in addresses) {
      final resolved = _normalizeHost(address.address);
      if (loopback) {
        if (!_isLoopbackHost(resolved)) {
          throw const McpEndpointPolicyException(
            'MCP loopback sidecar resolved outside the loopback boundary.',
          );
        }
      } else if (_blockedHostReason(resolved) != null) {
        throw const McpEndpointPolicyException(
          'MCP endpoint resolved to a non-public address.',
        );
      }
    }
    return endpoint;
  }

  static String _normalizeHost(String host) =>
      NetworkAddressPolicy.normalizeHost(host);

  static bool _isLoopbackHost(String host) =>
      NetworkAddressPolicy.isExplicitLoopbackHost(host);

  static String? _blockedHostReason(String host) =>
      NetworkAddressPolicy.publicHostBlockReason(host);

  static String _redactedHttpErrorMessage(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401) return 'MCP authentication failed.';
    if (status == 403) return 'MCP permission was denied.';
    if (status == 408 ||
        status == 504 ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'MCP request timed out.';
    }
    return 'MCP request failed.';
  }
}
