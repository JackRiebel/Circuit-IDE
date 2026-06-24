import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';
import '../../models/chat_message.dart';
import '../../models/provider_lifecycle_event.dart';
import '../config/models_config.dart';
import 'provider_interface.dart';

class CiscoProvider implements AIProvider {
  late final Dio _dio;
  String? _clientId;
  String? _clientSecret;
  String? _appKey;
  String? _accessToken;
  DateTime? _tokenExpiry;
  bool _connected = false;
  CancelToken? _activeCancelToken;
  late final String _chatBaseUrl;

  /// Retry config
  static const int _maxRetries = 3;
  static const Duration _baseRetryDelay = Duration(seconds: 1);

  CiscoProvider({
    Dio? dio,
    String? accessToken,
    DateTime? tokenExpiry,
    String? appKey,
    String? chatBaseUrl,
  }) {
    _dio =
        dio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(minutes: 4),
          ),
        );
    _accessToken = accessToken;
    _tokenExpiry = tokenExpiry;
    _appKey = appKey;
    _chatBaseUrl = chatBaseUrl ?? AppConstants.ciscoChatBaseUrl;
    _connected = accessToken != null;
  }

  @override
  String get name => 'Circuit Company AI';

  @override
  List<ModelInfo> get availableModels => ModelsConfig.ciscoModels;

  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
    id: 'circuit',
    displayName: 'Circuit Company AI',
    shortName: 'Circuit',
    capabilities: ProviderCapabilities(
      supportsStreaming: true,
      supportsNativeToolCalls: true,
      supportsModelRefresh: true,
      supportsCancellation: true,
    ),
  );

  @override
  ProviderCapabilities get capabilities => descriptor.capabilities;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect(Map<String, String> credentials) async {
    _clientId = credentials['client_id'];
    _clientSecret = credentials['client_secret'];
    _appKey = credentials['app_key'];

    if (_clientId == null || _clientSecret == null || _appKey == null) {
      throw ArgumentError('Missing Circuit credentials');
    }

    await _refreshToken();
    _connected = true;
    Logger.info('Connected to Circuit Company AI', 'CiscoProvider');
  }

  @override
  void disconnect() {
    _connected = false;
    _accessToken = null;
    _tokenExpiry = null;
    cancelActiveRequest();
    Logger.info('Disconnected from Circuit Company AI', 'CiscoProvider');
  }

  @override
  Future<ConnectorHealth> checkHealth() async {
    if (_clientId == null || _clientSecret == null || _appKey == null) {
      return ConnectorHealth(
        status: ConnectorHealthStatus.credentialsMissing,
        message: 'Circuit credentials are missing.',
        checkedAt: DateTime.now(),
      );
    }
    try {
      await _getToken();
      return ConnectorHealth(
        status: ConnectorHealthStatus.connected,
        message: 'Circuit connector is ready.',
        checkedAt: DateTime.now(),
      );
    } catch (e) {
      return ConnectorHealth(
        status: ConnectorHealthStatus.tokenFailed,
        message: e.toString().replaceFirst('Exception: ', ''),
        checkedAt: DateTime.now(),
      );
    }
  }

  @override
  void cancelActiveRequest() {
    _activeCancelToken?.cancel('Request cancelled by user.');
    _activeCancelToken = null;
  }

  @override
  Future<List<ConnectorModelInfo>> refreshModels() async {
    if (_clientId == null || _clientSecret == null || _appKey == null) {
      return _bundledConnectorModels();
    }

    try {
      final token = await _getToken();
      final response = await _dio.get(
        AppConstants.ciscoChatBaseUrl,
        queryParameters: {'api-version': AppConstants.ciscoApiVersion},
        options: Options(headers: {'api-key': token}),
      );
      final parsed = _parseModelCatalog(response.data);
      if (parsed.isNotEmpty) return parsed;
    } catch (e) {
      Logger.warning(
        'Circuit model refresh fell back to bundled catalog: $e',
        'CiscoProvider',
      );
    }
    return _bundledConnectorModels();
  }

  List<ConnectorModelInfo> _bundledConnectorModels() {
    return availableModels
        .map(
          (model) => ConnectorModelInfo(
            id: model.id,
            displayName: model.displayName,
            contextWindow: model.contextWindow,
            supportsTools: model.supportsTools,
            inputCostPer1k: model.inputCostPer1k,
            outputCostPer1k: model.outputCostPer1k,
          ),
        )
        .toList();
  }

  List<ConnectorModelInfo> _parseModelCatalog(dynamic data) {
    final items = switch (data) {
      {'data': final List<dynamic> models} => models,
      {'models': final List<dynamic> models} => models,
      final List<dynamic> models => models,
      _ => const <dynamic>[],
    };

    return items
        .whereType<Map<String, dynamic>>()
        .map((json) {
          final id = json['id'] as String? ?? json['model'] as String?;
          if (id == null || id.trim().isEmpty) return null;
          final capabilities = json['capabilities'] as Map<String, dynamic>?;
          final supportsTools =
              capabilities?['tools'] as bool? ??
              capabilities?['tool_calls'] as bool? ??
              _isKnownToolCapableModel(id);
          final contextWindow =
              json['contextWindow'] as int? ??
              json['context_window'] as int? ??
              120000;
          return ConnectorModelInfo(
            id: id,
            displayName:
                json['displayName'] as String? ??
                json['display_name'] as String? ??
                id,
            contextWindow: contextWindow,
            supportsTools: supportsTools,
            inputCostPer1k:
                (json['inputCostPer1k'] as num?)?.toDouble() ??
                (json['input_cost_per_1k'] as num?)?.toDouble() ??
                0,
            outputCostPer1k:
                (json['outputCostPer1k'] as num?)?.toDouble() ??
                (json['output_cost_per_1k'] as num?)?.toDouble() ??
                0,
          );
        })
        .whereType<ConnectorModelInfo>()
        .toList();
  }

  bool _isKnownToolCapableModel(String id) {
    return ModelsConfig.ciscoModels.any(
      (model) => model.id == id && model.supportsTools,
    );
  }

  Future<void> _refreshToken() async {
    if (_clientId == null || _clientSecret == null || _appKey == null) {
      throw StateError(
        'Circuit credentials are missing. Reconnect Circuit Company AI before refreshing the token.',
      );
    }
    final credentials = base64Encode(utf8.encode('$_clientId:$_clientSecret'));

    Exception? lastError;
    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        final response = await _dio.post(
          AppConstants.ciscoTokenUrl,
          data: 'grant_type=client_credentials',
          options: Options(
            headers: {
              'Authorization': 'Basic $credentials',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
          ),
        );

        final data = response.data as Map<String, dynamic>;
        _accessToken = data['access_token'] as String;
        final expiresIn = data['expires_in'] as int;
        // Refresh 5 minutes before expiry
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 300));

        Logger.info(
          'OAuth token refreshed, expires in ${expiresIn}s',
          'CiscoProvider',
        );
        return;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        if (attempt < _maxRetries - 1) {
          final delay = _baseRetryDelay * (1 << attempt);
          Logger.warning(
            'Token refresh failed, retrying in ${delay.inSeconds}s...',
            'CiscoProvider',
          );
          await Future.delayed(delay);
        }
      }
    }
    throw Exception(
      'Failed to obtain OAuth token after $_maxRetries attempts: $lastError',
    );
  }

  Future<String> _getToken() async {
    if (_accessToken == null ||
        _tokenExpiry == null ||
        DateTime.now().isAfter(_tokenExpiry!)) {
      if (_clientId == null || _clientSecret == null || _appKey == null) {
        throw StateError(
          'Circuit credentials are missing. Connect Circuit Company AI before sending a request.',
        );
      }
      await _refreshToken();
    }
    return _accessToken!;
  }

  @override
  Stream<ChatChunk> chat(
    List<ChatMessage> messages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async* {
    final String token;
    try {
      token = await _getToken();
    } catch (error) {
      final errorMsg =
          'Circuit authentication failed: ${_cleanErrorMessage(error)}';
      yield ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.authFailed,
        lifecycleDetail: errorMsg,
      );
      yield ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: errorMsg,
      );
      throw Exception(errorMsg);
    }
    final url =
        '$_chatBaseUrl/$model/chat/completions?api-version=${AppConstants.ciscoApiVersion}';

    final apiMessages = <Map<String, dynamic>>[];
    if (systemPrompt != null) {
      apiMessages.add({'role': 'system', 'content': systemPrompt});
    }
    for (final msg in messages) {
      apiMessages.add(msg.toApiMessage());
    }

    final body = <String, dynamic>{
      'messages': apiMessages,
      'user': jsonEncode({'appkey': _appKey}),
      'temperature': temperature,
      'max_tokens': maxTokens,
      'stream': true,
    };

    if (tools.isNotEmpty) {
      body['tools'] = tools.map((t) => t.toOpenAIFormat()).toList();
      body['tool_choice'] = 'auto';
    }

    Logger.info(
      'Sending chat request to $url (model: $model, messages: ${apiMessages.length})',
      'CiscoProvider',
    );

    Response<ResponseBody> response;
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;
    yield ChatChunk(
      lifecycleKind: ProviderLifecycleEventKind.requestSent,
      lifecycleDetail:
          'Circuit API request sent for $model with ${tools.length} exposed tools.',
    );
    try {
      response = await _dio.post<ResponseBody>(
        url,
        data: jsonEncode(body),
        cancelToken: cancelToken,
        options: Options(
          headers: {'api-key': token, 'Content-Type': 'application/json'},
          responseType: ResponseType.stream,
        ),
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        yield const ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.cancelled,
          lifecycleDetail: 'Circuit API request was cancelled.',
        );
        throw Exception('Request cancelled');
      }
      if (_isTimeout(e)) {
        final errorMsg =
            'Circuit API request timed out: ${e.message ?? e.type.name}';
        yield ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.timeout,
          lifecycleDetail: errorMsg,
        );
        yield ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.failed,
          lifecycleDetail: errorMsg,
        );
        throw Exception(errorMsg);
      }
      final status = e.response?.statusCode;
      if (status == 401) {
        try {
          await _refreshToken();
        } catch (refreshError) {
          final errorMsg =
              'Circuit authentication failed while refreshing an expired token: ${_cleanErrorMessage(refreshError)}';
          yield ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.authFailed,
            lifecycleDetail: errorMsg,
          );
          yield ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.failed,
            lifecycleDetail: errorMsg,
          );
          throw Exception(errorMsg);
        }
        yield* chat(
          messages,
          model: model,
          tools: tools,
          systemPrompt: systemPrompt,
          temperature: temperature,
          maxTokens: maxTokens,
        );
        return;
      }
      if (status != null) {
        yield ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.connected,
          lifecycleDetail: 'Circuit API responded with HTTP $status.',
        );
      }
      final retryAfterDetail = _retryAfterDetail(e.response?.headers);
      if (status == 429) {
        yield ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.rateLimited,
          lifecycleDetail: retryAfterDetail == null
              ? 'Circuit API rate limit reached.'
              : 'Circuit API rate limit reached. $retryAfterDetail',
        );
      }
      String errorMsg = status == null
          ? 'Circuit API request failed: ${e.message ?? e.error ?? e.type}'
          : 'Circuit API error $status';
      if (status == 429) {
        errorMsg = retryAfterDetail == null
            ? 'Circuit API rate limit reached (HTTP 429)'
            : 'Circuit API rate limit reached (HTTP 429). $retryAfterDetail';
      }
      if (e.response?.data != null) {
        try {
          final errBody = await _readStreamBody(e.response!.data);
          if (errBody.isNotEmpty) {
            try {
              final errData = jsonDecode(errBody) as Map<String, dynamic>;
              final inner = errData['error'] as Map<String, dynamic>?;
              final parsedMessage =
                  inner?['message'] as String? ?? errData['message'] as String?;
              if (parsedMessage?.trim().isNotEmpty == true) {
                final parsed = status == 429
                    ? 'Circuit API rate limit reached (HTTP 429): ${parsedMessage!.trim()}'
                    : null;
                errorMsg =
                    parsed ??
                    (status == null
                        ? parsedMessage!.trim()
                        : 'Circuit API error $status: ${parsedMessage!.trim()}');
                if (status == 429 && retryAfterDetail != null) {
                  errorMsg = '$errorMsg. $retryAfterDetail';
                }
              }
            } catch (_) {
              errorMsg = '$errorMsg: ${_truncateErrorBody(errBody)}';
            }
          }
        } catch (bodyError) {
          errorMsg =
              '$errorMsg: unable to read error response body (${_cleanErrorMessage(bodyError)})';
        }
      }
      if (status == null) {
        yield ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.noFirstByte,
          lifecycleDetail:
              'Circuit API request failed before an HTTP response was received: ${_cleanErrorMessage(e)}',
        );
      }
      yield ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: errorMsg,
      );
      throw Exception(errorMsg);
    } catch (e) {
      final errorMsg = 'Circuit API request failed: $e';
      yield ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.noFirstByte,
        lifecycleDetail:
            'Circuit API request failed before a response stream was opened: ${_cleanErrorMessage(e)}',
      );
      yield ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: errorMsg,
      );
      throw Exception(errorMsg);
    }

    yield ChatChunk(
      lifecycleKind: ProviderLifecycleEventKind.connected,
      lifecycleDetail:
          'Circuit API accepted the request (${response.statusCode ?? 'stream'}).',
    );

    final contentType = response.headers
        .value(Headers.contentTypeHeader)
        ?.toLowerCase();
    if (_isJsonContentType(contentType)) {
      yield ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.nonSseJson,
        lifecycleDetail:
            'Circuit returned ${contentType ?? 'JSON'} instead of SSE.',
      );
      final body = StringBuffer();
      var sawFirstByte = false;
      var sawRawFirstByte = false;
      try {
        await for (final text in _decodeUtf8Stream(
          response.data!.stream,
          onFirstByte: () {
            sawRawFirstByte = true;
          },
        )) {
          if (cancelToken.isCancelled) {
            throw Exception('Request cancelled');
          }
          if (!sawFirstByte) {
            sawFirstByte = true;
            yield const ChatChunk(
              lifecycleKind: ProviderLifecycleEventKind.firstByte,
              lifecycleDetail: 'Circuit API returned the first response bytes.',
            );
          }
          body.write(text);
        }
      } catch (error) {
        if (sawRawFirstByte && !sawFirstByte) {
          sawFirstByte = true;
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.firstByte,
            lifecycleDetail:
                'Circuit API returned response bytes before the stream failed.',
          );
        }
        if (_isCancellation(error, cancelToken)) {
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.cancelled,
            lifecycleDetail: 'Circuit API request was cancelled.',
          );
          throw Exception('Request cancelled');
        }
        if (_isMalformedBytes(error)) {
          const detail = 'Circuit API returned malformed UTF-8 response bytes.';
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.malformedBytes,
            lifecycleDetail: detail,
          );
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.failed,
            lifecycleDetail: detail,
          );
          throw Exception(detail);
        }
        if (_isTimeoutError(error)) {
          final detail =
              'Circuit API response stream timed out: ${_timeoutDetail(error)}';
          yield ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.timeout,
            lifecycleDetail: detail,
          );
          yield ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.failed,
            lifecycleDetail: detail,
          );
          throw Exception(detail);
        }
        final detail = 'Circuit API response stream failed: $error';
        if (!sawFirstByte) {
          yield ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.noFirstByte,
            lifecycleDetail:
                'Circuit API response stream failed before returning response bytes: ${_cleanErrorMessage(error)}',
          );
        }
        yield ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.failed,
          lifecycleDetail: detail,
        );
        throw Exception(detail);
      } finally {
        if (identical(_activeCancelToken, cancelToken)) {
          _activeCancelToken = null;
        }
      }
      if (sawRawFirstByte && !sawFirstByte) {
        sawFirstByte = true;
        yield const ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.firstByte,
          lifecycleDetail:
              'Circuit API returned response bytes before decoded text was available.',
        );
      }
      if (!sawFirstByte) {
        const detail = 'Circuit returned a JSON response with no bytes.';
        yield const ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.noFirstByte,
          lifecycleDetail: detail,
        );
        yield const ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.failed,
          lifecycleDetail: detail,
        );
        throw Exception(detail);
      }
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.jsonFallback,
        lifecycleDetail: 'Circuit returned a non-streaming JSON response.',
      );
      yield* _parseJsonFallbackWithDiagnostics(body.toString().trim());
      return;
    }

    // Read the stream as SSE; if no SSE payload appears, fall back to JSON.
    final stream = response.data!.stream;
    String buffer = '';
    int promptTokens = 0;
    int completionTokens = 0;
    String? finishReason;
    bool yieldedAny = false;
    bool sawFirstByte = false;
    bool sawRawFirstByte = false;
    bool sawTextDelta = false;
    bool sawToolDelta = false;
    bool sawMalformedSseChunk = false;
    ChatChunk malformedSseChunk(String detail) {
      sawMalformedSseChunk = true;
      return ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.malformedChunk,
        lifecycleDetail: detail,
      );
    }

    try {
      await for (final text in _decodeUtf8Stream(
        stream,
        onFirstByte: () {
          sawRawFirstByte = true;
        },
      )) {
        if (cancelToken.isCancelled) {
          throw Exception('Request cancelled');
        }
        if (!sawFirstByte) {
          sawFirstByte = true;
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.firstByte,
            lifecycleDetail: 'Circuit API returned the first response bytes.',
          );
        }
        buffer += text;
        // Normalize \r\n to \n for SSE parsing
        buffer = buffer.replaceAll('\r\n', '\n');

        // Process complete SSE events (delimited by blank line)
        while (buffer.contains('\n\n')) {
          final eventEnd = buffer.indexOf('\n\n');
          final eventBlock = buffer.substring(0, eventEnd);
          buffer = buffer.substring(eventEnd + 2);

          String? eventName;
          final payloadParts = <String>[];
          for (final line in eventBlock.split('\n')) {
            if (line.startsWith('event:')) {
              eventName = line.substring(6).trim().toLowerCase();
              continue;
            }
            if (line.startsWith('data:')) {
              payloadParts.add(line.substring(5).trim());
            }
          }
          if (payloadParts.isEmpty) continue;

          final payload = payloadParts.join('\n').trim();

          if (eventName == 'error') {
            final detail =
                'Circuit SSE error event: ${_sseErrorEventMessage(payload)}';
            yield ChatChunk(
              lifecycleKind: ProviderLifecycleEventKind.failed,
              lifecycleDetail: detail,
            );
            throw Exception(detail);
          }

          if (payload == '[DONE]') {
            if (!sawTextDelta && !sawToolDelta && sawMalformedSseChunk) {
              const detail =
                  'Circuit SSE stream completed after malformed chunks without any valid assistant text or tool calls.';
              yield const ChatChunk(
                lifecycleKind: ProviderLifecycleEventKind.noTextOrTool,
                lifecycleDetail:
                    'Circuit SSE completed without valid assistant text or tool calls.',
              );
              yield const ChatChunk(
                lifecycleKind: ProviderLifecycleEventKind.failed,
                lifecycleDetail: detail,
              );
              throw Exception(detail);
            }
            if (!sawTextDelta && !sawToolDelta) {
              const detail =
                  'Circuit SSE stream completed without assistant text or tool calls.';
              yield const ChatChunk(
                lifecycleKind: ProviderLifecycleEventKind.noTextOrTool,
                lifecycleDetail: detail,
              );
              yield const ChatChunk(
                lifecycleKind: ProviderLifecycleEventKind.failed,
                lifecycleDetail: detail,
              );
              throw Exception(detail);
            }
            if (!sawTextDelta && sawToolDelta) {
              yield const ChatChunk(
                lifecycleKind: ProviderLifecycleEventKind.toolOnly,
                lifecycleDetail:
                    'Circuit returned tool calls without assistant text in SSE.',
              );
            }
            yield const ChatChunk(
              lifecycleKind: ProviderLifecycleEventKind.completed,
              lifecycleDetail: 'Circuit provider stream completed.',
            );
            yield ChatChunk(
              finishReason: finishReason ?? 'stop',
              promptTokens: promptTokens,
              completionTokens: completionTokens,
              isDone: true,
            );
            return;
          }

          Map<String, dynamic> json;
          try {
            json = jsonDecode(payload) as Map<String, dynamic>;
          } catch (error) {
            yield malformedSseChunk(
              'Circuit returned a malformed SSE JSON chunk: $error',
            );
            continue;
          }

          final errorMessage = _jsonErrorPayloadMessage(json);
          if (errorMessage != null) {
            final detail =
                'Circuit API returned an error payload: $errorMessage';
            yield ChatChunk(
              lifecycleKind: ProviderLifecycleEventKind.failed,
              lifecycleDetail: detail,
            );
            throw Exception(detail);
          }

          final usage = json['usage'] as Map<String, dynamic>?;
          if (usage != null) {
            promptTokens = usage['prompt_tokens'] as int? ?? promptTokens;
            completionTokens =
                usage['completion_tokens'] as int? ?? completionTokens;
          }

          final choices = json['choices'] as List<dynamic>?;
          if (choices == null || choices.isEmpty) continue;

          final rawChoice = choices[0];
          if (rawChoice is! Map<String, dynamic>) {
            yield malformedSseChunk(
              'Circuit returned a malformed SSE choice entry.',
            );
            continue;
          }
          final choice = rawChoice;
          final rawDelta = choice['delta'];
          if (rawDelta != null && rawDelta is! Map<String, dynamic>) {
            yield malformedSseChunk(
              'Circuit returned a malformed SSE delta field.',
            );
            continue;
          }
          final rawMessage = choice['message'];
          if (rawDelta == null &&
              rawMessage != null &&
              rawMessage is! Map<String, dynamic>) {
            yield malformedSseChunk(
              'Circuit returned a malformed SSE message field.',
            );
            continue;
          }
          final delta = rawDelta as Map<String, dynamic>? ?? {};
          final message = rawMessage as Map<String, dynamic>? ?? {};
          finishReason = choice['finish_reason'] as String? ?? finishReason;

          final content =
              delta['content'] as String? ?? message['content'] as String?;
          if (content != null && content.isNotEmpty) {
            if (!sawTextDelta) {
              yield const ChatChunk(
                lifecycleKind: ProviderLifecycleEventKind.firstTextDelta,
                lifecycleDetail:
                    'Circuit returned the first assistant text delta.',
              );
            }
            yieldedAny = true;
            sawTextDelta = true;
            yield ChatChunk(content: content);
          }

          final rawDeltaToolCalls = delta['tool_calls'];
          final rawMessageToolCalls = message['tool_calls'];
          final rawToolCalls = rawDeltaToolCalls ?? rawMessageToolCalls;
          if (rawToolCalls != null && rawToolCalls is! List<dynamic>) {
            yield malformedSseChunk(
              'Circuit returned a malformed SSE tool_calls field.',
            );
            continue;
          }
          final toolCallsCameFromMessage =
              rawDeltaToolCalls == null && rawMessageToolCalls != null;
          final toolCalls = rawToolCalls as List<dynamic>?;
          if (toolCalls != null) {
            for (var toolIndex = 0; toolIndex < toolCalls.length; toolIndex++) {
              final tc = toolCalls[toolIndex];
              if (tc is! Map<String, dynamic>) {
                yield malformedSseChunk(
                  'Circuit returned a malformed SSE tool-call entry.',
                );
                continue;
              }
              final rawFunction = tc['function'];
              if (rawFunction != null && rawFunction is! Map<String, dynamic>) {
                yield malformedSseChunk(
                  'Circuit returned a malformed SSE tool-call function.',
                );
                continue;
              }
              final rawIndex = tc['index'];
              final resolvedIndex = rawIndex is int
                  ? rawIndex
                  : toolCallsCameFromMessage
                  ? toolIndex
                  : null;
              if (resolvedIndex == null) {
                yield malformedSseChunk(
                  'Circuit returned an SSE tool-call delta without a numeric index.',
                );
                continue;
              }
              final function = rawFunction as Map<String, dynamic>? ?? {};
              final rawName = function['name'];
              final rawArguments = function['arguments'];
              if (rawName != null && rawName is! String) {
                yield malformedSseChunk(
                  'Circuit returned an SSE tool-call name that was not text.',
                );
                continue;
              }
              if (rawArguments != null && rawArguments is! String) {
                yield malformedSseChunk(
                  'Circuit returned SSE tool-call arguments that were not text.',
                );
                continue;
              }
              final name = rawName is String && rawName.trim().isNotEmpty
                  ? rawName
                  : null;
              final arguments = rawArguments is String ? rawArguments : null;
              if (name == null && arguments == null) {
                yield malformedSseChunk(
                  'Circuit returned an empty SSE tool-call delta.',
                );
                continue;
              }
              if (!sawToolDelta) {
                yield const ChatChunk(
                  lifecycleKind: ProviderLifecycleEventKind.firstToolDelta,
                  lifecycleDetail:
                      'Circuit returned the first tool-call delta.',
                );
              }
              yieldedAny = true;
              sawToolDelta = true;
              yield ChatChunk(
                toolCallIndex: resolvedIndex,
                toolCallId: tc['id'] as String?,
                toolCallName: name,
                toolCallArguments: arguments,
              );
            }
          }
        }
      }
    } catch (error) {
      if (sawRawFirstByte && !sawFirstByte) {
        sawFirstByte = true;
        yield const ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.firstByte,
          lifecycleDetail:
              'Circuit API returned response bytes before the stream failed.',
        );
      }
      if (_isCancellation(error, cancelToken)) {
        yield const ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.cancelled,
          lifecycleDetail: 'Circuit API request was cancelled.',
        );
        throw Exception('Request cancelled');
      }
      if (_isMalformedBytes(error)) {
        const detail = 'Circuit API returned malformed UTF-8 response bytes.';
        yield const ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.malformedBytes,
          lifecycleDetail: detail,
        );
        yield const ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.failed,
          lifecycleDetail: detail,
        );
        throw Exception(detail);
      }
      if (_isTimeoutError(error)) {
        final detail =
            'Circuit API response stream timed out: ${_timeoutDetail(error)}';
        yield ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.timeout,
          lifecycleDetail: detail,
        );
        yield ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.failed,
          lifecycleDetail: detail,
        );
        throw Exception(detail);
      }
      final detail = 'Circuit API response stream failed: $error';
      if (!sawFirstByte) {
        yield ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.noFirstByte,
          lifecycleDetail:
              'Circuit API response stream failed before returning response bytes: ${_cleanErrorMessage(error)}',
        );
      }
      yield ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: detail,
      );
      throw Exception(detail);
    } finally {
      if (identical(_activeCancelToken, cancelToken)) {
        _activeCancelToken = null;
      }
    }

    if (sawRawFirstByte && !sawFirstByte) {
      sawFirstByte = true;
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.firstByte,
        lifecycleDetail:
            'Circuit API returned response bytes before decoded text was available.',
      );
    }

    final trailingBuffer = buffer.trim();
    if (trailingBuffer.isNotEmpty && _looksLikeSsePayload(trailingBuffer)) {
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.malformedChunk,
        lifecycleDetail: 'Circuit SSE stream ended with an incomplete event.',
      );
      buffer = '';
    }

    if (!sawFirstByte) {
      const detail = 'Circuit stream closed with no response bytes.';
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.noFirstByte,
        lifecycleDetail: detail,
      );
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: detail,
      );
      throw Exception(detail);
    }

    // Fallback: if no SSE events were parsed, the API likely returned
    // a plain JSON response. Try to parse the buffer as JSON.
    if (!yieldedAny && buffer.trim().isNotEmpty) {
      Logger.info(
        'No SSE events found, attempting JSON fallback parse',
        'CiscoProvider',
      );
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.nonSseJson,
        lifecycleDetail: 'Circuit returned JSON instead of SSE.',
      );
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.jsonFallback,
        lifecycleDetail: 'Circuit returned a non-streaming JSON response.',
      );
      yield* _parseJsonFallbackWithDiagnostics(buffer.trim());
      return;
    }

    const earlyCloseDetail =
        'Circuit SSE stream ended without the [DONE] terminator.';
    yield const ChatChunk(
      lifecycleKind: ProviderLifecycleEventKind.streamEndedWithoutDone,
      lifecycleDetail: earlyCloseDetail,
    );

    yield* _diagnoseSseOutput(
      sawTextDelta: sawTextDelta,
      sawToolDelta: sawToolDelta,
    );
    yield const ChatChunk(
      lifecycleKind: ProviderLifecycleEventKind.failed,
      lifecycleDetail: earlyCloseDetail,
    );
    throw Exception(earlyCloseDetail);
  }

  bool _looksLikeSsePayload(String text) {
    return text.startsWith('data:') ||
        text.startsWith('event:') ||
        text.startsWith('id:') ||
        text.startsWith(':');
  }

  bool _isJsonContentType(String? contentType) {
    if (contentType == null) return false;
    return contentType.contains('application/json') &&
        !contentType.contains('text/event-stream');
  }

  bool _isCancellation(Object error, CancelToken cancelToken) {
    if (cancelToken.isCancelled) return true;
    if (error is DioException && CancelToken.isCancel(error)) return true;
    return error.toString().toLowerCase().contains('cancel');
  }

  Stream<String> _decodeUtf8Stream(
    Stream<Uint8List> byteStream, {
    required void Function() onFirstByte,
  }) {
    return _withBodyIdleTimeout(byteStream)
        .map<List<int>>((bytes) {
          if (bytes.isNotEmpty) onFirstByte();
          return bytes;
        })
        .transform(const Utf8Decoder());
  }

  Stream<Uint8List> _withBodyIdleTimeout(Stream<Uint8List> byteStream) {
    final timeout = _dio.options.receiveTimeout;
    if (timeout == null || timeout <= Duration.zero) return byteStream;
    return byteStream.timeout(
      timeout,
      onTimeout: (sink) {
        sink.addError(
          TimeoutException(
            'no response body data arrived for ${timeout.inMilliseconds}ms',
            timeout,
          ),
        );
      },
    );
  }

  bool _isMalformedBytes(Object error) => error is FormatException;

  bool _isTimeoutError(Object error) {
    return error is TimeoutException ||
        (error is DioException && _isTimeout(error));
  }

  bool _isTimeout(DioException error) {
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout;
  }

  String _timeoutDetail(Object error) {
    if (error is TimeoutException) {
      return error.message ?? 'response stream stalled';
    }
    if (error is DioException) {
      return error.message ?? error.type.name;
    }
    return error.toString();
  }

  String _cleanErrorMessage(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('Bad state: ', '')
        .trim();
  }

  String? _retryAfterDetail(Headers? headers) {
    final value = headers?.value('retry-after')?.trim();
    if (value == null || value.isEmpty) return null;
    final seconds = int.tryParse(value);
    if (seconds != null && seconds >= 0) {
      return 'Retry after ${seconds}s.';
    }
    return 'Retry after $value.';
  }

  Stream<ChatChunk> _parseJsonFallbackWithDiagnostics(String body) async* {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(body) as Map<String, dynamic>;
    } catch (error) {
      Logger.error('Failed to parse Circuit API response as JSON', error);
      const detail = 'Circuit JSON fallback body was malformed.';
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.malformedChunk,
        lifecycleDetail: detail,
      );
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: 'Invalid response from Circuit API: $detail',
      );
      throw const FormatException('Invalid response from Circuit API: $detail');
    }
    yield* CiscoResponseParser.parseJsonData(data);
  }

  Stream<ChatChunk> _diagnoseSseOutput({
    required bool sawTextDelta,
    required bool sawToolDelta,
  }) async* {
    if (!sawTextDelta && sawToolDelta) {
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.toolOnly,
        lifecycleDetail:
            'Circuit returned tool calls without assistant text in SSE.',
      );
    } else if (!sawTextDelta && !sawToolDelta) {
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.noTextOrTool,
        lifecycleDetail:
            'Circuit SSE completed without assistant text or tool calls.',
      );
    }
  }

  /// Read a stream response body into a string (for error responses).
  Future<String> _readStreamBody(dynamic data) async {
    if (data is ResponseBody) {
      final chunks = <int>[];
      await for (final bytes in data.stream) {
        chunks.addAll(bytes);
      }
      return utf8.decode(chunks, allowMalformed: true);
    }
    return data.toString();
  }

  String _truncateErrorBody(String body) {
    final normalized = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= 240) return normalized;
    return '${normalized.substring(0, 240)}...';
  }

  String _sseErrorEventMessage(String payload) {
    final trimmed = payload.trim();
    if (trimmed.isEmpty) return 'error event without a payload';
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return _jsonDiagnosticPayloadMessage(decoded) ?? jsonEncode(decoded);
      }
      if (decoded is String && decoded.trim().isNotEmpty) {
        return decoded.trim();
      }
    } catch (_) {
      // Plain-text SSE error payloads are valid enough to report directly.
    }
    return _truncateErrorBody(trimmed);
  }
}

class CiscoResponseParser {
  const CiscoResponseParser._();

  /// Parse a plain JSON chat completion response (non-streaming fallback).
  static Stream<ChatChunk> parseJsonResponse(String body) async* {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      Logger.error('Failed to parse Circuit API response as JSON', e);
      throw Exception('Invalid response from Circuit API');
    }

    yield* parseJsonData(data);
  }

  static Stream<ChatChunk> parseJsonData(Map<String, dynamic> data) async* {
    final errorMessage = _jsonErrorPayloadMessage(data);
    if (errorMessage != null) {
      final detail =
          'Circuit JSON fallback returned an error payload: $errorMessage';
      yield ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: detail,
      );
      throw Exception(detail);
    }

    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      const detail =
          'Circuit JSON fallback contained no choices with assistant text or tool calls.';
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.noTextOrTool,
        lifecycleDetail: detail,
      );
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: detail,
      );
      throw Exception(detail);
    }

    final rawChoice = choices[0];
    if (rawChoice is! Map<String, dynamic>) {
      const detail =
          'Circuit JSON fallback contained a malformed choice entry.';
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.malformedChunk,
        lifecycleDetail: detail,
      );
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: detail,
      );
      throw Exception(detail);
    }
    final choice = rawChoice;
    final rawMessage = choice['message'];
    if (rawMessage != null && rawMessage is! Map<String, dynamic>) {
      const detail = 'Circuit JSON fallback contained a malformed message.';
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.malformedChunk,
        lifecycleDetail: detail,
      );
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: detail,
      );
      throw Exception(detail);
    }
    final message = rawMessage as Map<String, dynamic>? ?? {};
    final content = message['content'] as String? ?? '';
    final finishReason = choice['finish_reason'] as String? ?? 'stop';

    final usage = data['usage'] as Map<String, dynamic>?;
    final promptTokens = usage?['prompt_tokens'] as int? ?? 0;
    final completionTokens = usage?['completion_tokens'] as int? ?? 0;

    if (content.isNotEmpty) {
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.firstTextDelta,
        lifecycleDetail: 'Circuit returned the first assistant text delta.',
      );
      yield ChatChunk(content: content);
    }

    final rawToolCalls = message['tool_calls'];
    if (rawToolCalls != null && rawToolCalls is! List<dynamic>) {
      const detail =
          'Circuit JSON fallback contained a malformed tool_calls field.';
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.malformedChunk,
        lifecycleDetail: detail,
      );
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: detail,
      );
      throw Exception(detail);
    }
    final toolCalls = rawToolCalls as List<dynamic>?;
    final parsedToolCalls = <Map<String, dynamic>>[];
    if (toolCalls != null) {
      for (final tc in toolCalls) {
        if (tc is! Map<String, dynamic>) {
          const detail =
              'Circuit JSON fallback contained a malformed tool-call entry.';
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.malformedChunk,
            lifecycleDetail: detail,
          );
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.failed,
            lifecycleDetail: detail,
          );
          throw Exception(detail);
        }
        final function = tc['function'];
        if (function is! Map<String, dynamic>) {
          const detail =
              'Circuit JSON fallback contained a malformed tool-call function.';
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.malformedChunk,
            lifecycleDetail: detail,
          );
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.failed,
            lifecycleDetail: detail,
          );
          throw Exception(detail);
        }
        final name = function['name'];
        final arguments = function['arguments'];
        if (name is! String || name.trim().isEmpty || arguments is! String) {
          const detail =
              'Circuit JSON fallback contained an incomplete tool-call function.';
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.malformedChunk,
            lifecycleDetail: detail,
          );
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.failed,
            lifecycleDetail: detail,
          );
          throw Exception(detail);
        }
        parsedToolCalls.add(tc);
      }
    }

    if (parsedToolCalls.isNotEmpty) {
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.firstToolDelta,
        lifecycleDetail: 'Circuit returned the first tool-call delta.',
      );
    }
    if (content.isEmpty && parsedToolCalls.isNotEmpty) {
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.toolOnly,
        lifecycleDetail:
            'Circuit returned tool calls without assistant text in JSON fallback.',
      );
    } else if (content.isEmpty && parsedToolCalls.isEmpty) {
      const detail =
          'Circuit JSON fallback contained no assistant text or tool calls.';
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.noTextOrTool,
        lifecycleDetail: detail,
      );
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: detail,
      );
      throw Exception(detail);
    }
    if (parsedToolCalls.isNotEmpty) {
      for (int i = 0; i < parsedToolCalls.length; i++) {
        final tc = parsedToolCalls[i];
        final function = tc['function'] as Map<String, dynamic>;
        yield ChatChunk(
          toolCallIndex: i,
          toolCallId: tc['id'] as String?,
          toolCallName: function['name'] as String,
          toolCallArguments: function['arguments'] as String,
        );
      }
    }

    yield const ChatChunk(
      lifecycleKind: ProviderLifecycleEventKind.completed,
      lifecycleDetail: 'Circuit provider JSON response completed.',
    );
    yield ChatChunk(
      finishReason: finishReason,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      isDone: true,
    );
  }
}

String? _jsonErrorPayloadMessage(Map<String, dynamic> data) {
  final error = data['error'];
  if (error is Map<String, dynamic>) {
    final message = error['message'] ?? error['detail'] ?? error['error'];
    if (message is String && message.trim().isNotEmpty) {
      return message.trim();
    }
    final code = error['code'];
    if (code is String && code.trim().isNotEmpty) return code.trim();
    return jsonEncode(error);
  }
  if (error is String && error.trim().isNotEmpty) return error.trim();

  final type = data['type'];
  final message = data['message'] ?? data['detail'];
  if (type is String &&
      type.toLowerCase().contains('error') &&
      message is String &&
      message.trim().isNotEmpty) {
    return message.trim();
  }
  return null;
}

String? _jsonDiagnosticPayloadMessage(Map<String, dynamic> data) {
  final errorMessage = _jsonErrorPayloadMessage(data);
  if (errorMessage != null) return errorMessage;

  for (final key in const [
    'message',
    'detail',
    'error_description',
    'description',
    'reason',
  ]) {
    final value = data[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}
