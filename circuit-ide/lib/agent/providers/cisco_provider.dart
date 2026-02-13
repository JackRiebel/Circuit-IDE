import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';
import '../../models/chat_message.dart';
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

  /// Retry config
  static const int _maxRetries = 3;
  static const Duration _baseRetryDelay = Duration(seconds: 1);

  CiscoProvider() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 180),
    ));
  }

  @override
  String get name => 'Cisco Circuit';

  @override
  List<ModelInfo> get availableModels => ModelsConfig.ciscoModels;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect(Map<String, String> credentials) async {
    _clientId = credentials['client_id'];
    _clientSecret = credentials['client_secret'];
    _appKey = credentials['app_key'];

    if (_clientId == null || _clientSecret == null || _appKey == null) {
      throw ArgumentError('Missing Cisco credentials');
    }

    await _refreshToken();
    _connected = true;
    Logger.info('Connected to Cisco Circuit API', 'CiscoProvider');
  }

  @override
  void disconnect() {
    _connected = false;
    _accessToken = null;
    _tokenExpiry = null;
    Logger.info('Disconnected from Cisco Circuit API', 'CiscoProvider');
  }

  Future<void> _refreshToken() async {
    final credentials =
        base64Encode(utf8.encode('$_clientId:$_clientSecret'));

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
        _tokenExpiry = DateTime.now().add(
          Duration(seconds: expiresIn - 300),
        );

        Logger.info('OAuth token refreshed, expires in ${expiresIn}s',
            'CiscoProvider');
        return;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        if (attempt < _maxRetries - 1) {
          final delay = _baseRetryDelay * (1 << attempt);
          Logger.warning(
              'Token refresh failed, retrying in ${delay.inSeconds}s...',
              'CiscoProvider');
          await Future.delayed(delay);
        }
      }
    }
    throw Exception(
        'Failed to obtain OAuth token after $_maxRetries attempts: $lastError');
  }

  Future<String> _getToken() async {
    if (_accessToken == null ||
        _tokenExpiry == null ||
        DateTime.now().isAfter(_tokenExpiry!)) {
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
    final token = await _getToken();
    final url =
        '${AppConstants.ciscoChatBaseUrl}/$model/chat/completions?api-version=${AppConstants.ciscoApiVersion}';

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
        'CiscoProvider');

    Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        url,
        data: jsonEncode(body),
        options: Options(
          headers: {
            'api-key': token,
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.stream,
        ),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401) {
        await _refreshToken();
        yield* chat(messages,
            model: model,
            tools: tools,
            systemPrompt: systemPrompt,
            temperature: temperature,
            maxTokens: maxTokens);
        return;
      }
      String errorMsg = 'Cisco API error $status';
      if (e.response?.data != null) {
        try {
          final errBody = await _readStreamBody(e.response!.data);
          if (errBody.isNotEmpty) {
            final errData = jsonDecode(errBody) as Map<String, dynamic>;
            final inner = errData['error'] as Map<String, dynamic>?;
            errorMsg = inner?['message'] as String? ??
                errData['message'] as String? ??
                errorMsg;
          }
        } catch (_) {}
      }
      throw Exception(errorMsg);
    } catch (e) {
      throw Exception('Circuit API request failed: $e');
    }

    // Read the full stream, then decide if it's SSE or plain JSON.
    final stream = response.data!.stream;
    String buffer = '';
    int promptTokens = 0;
    int completionTokens = 0;
    String? finishReason;
    bool yieldedAny = false;

    await for (final bytes in stream) {
      buffer += utf8.decode(bytes, allowMalformed: true);
      // Normalize \r\n to \n for SSE parsing
      buffer = buffer.replaceAll('\r\n', '\n');

      // Process complete SSE events (delimited by blank line)
      while (buffer.contains('\n\n')) {
        final eventEnd = buffer.indexOf('\n\n');
        final eventBlock = buffer.substring(0, eventEnd);
        buffer = buffer.substring(eventEnd + 2);

        for (final line in eventBlock.split('\n')) {
          if (!line.startsWith('data: ')) continue;
          final payload = line.substring(6).trim();

          if (payload == '[DONE]') {
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
          } catch (_) {
            continue;
          }

          final usage = json['usage'] as Map<String, dynamic>?;
          if (usage != null) {
            promptTokens = usage['prompt_tokens'] as int? ?? promptTokens;
            completionTokens =
                usage['completion_tokens'] as int? ?? completionTokens;
          }

          final choices = json['choices'] as List<dynamic>?;
          if (choices == null || choices.isEmpty) continue;

          final choice = choices[0] as Map<String, dynamic>;
          final delta = choice['delta'] as Map<String, dynamic>? ?? {};
          finishReason =
              choice['finish_reason'] as String? ?? finishReason;

          final content = delta['content'] as String?;
          if (content != null && content.isNotEmpty) {
            yieldedAny = true;
            yield ChatChunk(content: content);
          }

          final toolCalls = delta['tool_calls'] as List<dynamic>?;
          if (toolCalls != null) {
            yieldedAny = true;
            for (final tc in toolCalls) {
              final tcMap = tc as Map<String, dynamic>;
              final function =
                  tcMap['function'] as Map<String, dynamic>? ?? {};
              yield ChatChunk(
                toolCallIndex: tcMap['index'] as int?,
                toolCallId: tcMap['id'] as String?,
                toolCallName: function['name'] as String?,
                toolCallArguments: function['arguments'] as String?,
              );
            }
          }
        }
      }
    }

    // Fallback: if no SSE events were parsed, the API likely returned
    // a plain JSON response. Try to parse the buffer as JSON.
    if (!yieldedAny && buffer.trim().isNotEmpty) {
      Logger.info(
          'No SSE events found, attempting JSON fallback parse',
          'CiscoProvider');
      yield* _parseJsonResponse(buffer.trim());
      return;
    }

    yield ChatChunk(
      finishReason: finishReason ?? 'stop',
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      isDone: true,
    );
  }

  /// Parse a plain JSON chat completion response (non-streaming fallback).
  Stream<ChatChunk> _parseJsonResponse(String body) async* {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      Logger.error('Failed to parse Circuit API response as JSON', e);
      throw Exception('Invalid response from Circuit API');
    }

    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      yield const ChatChunk(finishReason: 'stop', isDone: true);
      return;
    }

    final choice = choices[0] as Map<String, dynamic>;
    final message = choice['message'] as Map<String, dynamic>? ?? {};
    final content = message['content'] as String? ?? '';
    final finishReason = choice['finish_reason'] as String? ?? 'stop';

    final usage = data['usage'] as Map<String, dynamic>?;
    final promptTokens = usage?['prompt_tokens'] as int? ?? 0;
    final completionTokens = usage?['completion_tokens'] as int? ?? 0;

    // Emit content
    if (content.isNotEmpty) {
      yield ChatChunk(content: content);
    }

    // Emit tool calls
    final toolCalls = message['tool_calls'] as List<dynamic>?;
    if (toolCalls != null) {
      for (int i = 0; i < toolCalls.length; i++) {
        final tc = toolCalls[i] as Map<String, dynamic>;
        final function = tc['function'] as Map<String, dynamic>?;
        yield ChatChunk(
          toolCallIndex: i,
          toolCallId: tc['id'] as String?,
          toolCallName: function?['name'] as String?,
          toolCallArguments: function?['arguments'] as String?,
        );
      }
    }

    yield ChatChunk(
      finishReason: finishReason,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      isDone: true,
    );
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
}
