import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';
import '../../models/chat_message.dart';
import '../../enums/message_role.dart';
import '../config/models_config.dart';
import '../streaming/sse_parser.dart';
import 'provider_interface.dart';

class AnthropicProvider implements AIProvider {
  late final Dio _dio;
  String? _apiKey;
  bool _connected = false;

  AnthropicProvider() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.anthropicBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
    ));
  }

  @override
  String get name => 'Anthropic Claude';

  @override
  List<ModelInfo> get availableModels => ModelsConfig.anthropicModels;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect(Map<String, String> credentials) async {
    _apiKey = credentials['api_key'];
    if (_apiKey == null) {
      throw ArgumentError('Missing Anthropic API key');
    }

    // Verify connectivity with a minimal request
    try {
      await _dio.post(
        '/v1/messages',
        data: jsonEncode({
          'model': 'claude-3-5-haiku-20241022',
          'max_tokens': 1,
          'messages': [
            {'role': 'user', 'content': 'hi'}
          ],
        }),
        options: Options(
          headers: _headers,
        ),
      );
      _connected = true;
      Logger.info('Connected to Anthropic API', 'AnthropicProvider');
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception('Invalid Anthropic API key');
      }
      // Other errors might be fine (rate limit etc.)
      _connected = true;
      Logger.info(
          'Connected to Anthropic API (verification skipped)', 'AnthropicProvider');
    }
  }

  @override
  void disconnect() {
    _connected = false;
    _apiKey = null;
    Logger.info('Disconnected from Anthropic API', 'AnthropicProvider');
  }

  Map<String, String> get _headers => {
        'x-api-key': _apiKey ?? '',
        'anthropic-version': AppConstants.anthropicApiVersion,
        'content-type': 'application/json',
      };

  @override
  Stream<ChatChunk> chat(
    List<ChatMessage> messages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async* {
    // Convert messages to Anthropic format
    final apiMessages = <Map<String, dynamic>>[];

    for (final msg in messages) {
      if (msg.role == MessageRole.system) continue; // System is separate

      if (msg.role == MessageRole.tool) {
        // Tool results in Anthropic format
        apiMessages.add({
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': msg.toolCallId,
              'content': msg.content,
            },
          ],
        });
      } else if (msg.role == MessageRole.assistant && msg.toolCalls.isNotEmpty) {
        // Assistant message with tool use
        final content = <Map<String, dynamic>>[];
        if (msg.content.isNotEmpty) {
          content.add({'type': 'text', 'text': msg.content});
        }
        for (final tc in msg.toolCalls) {
          content.add({
            'type': 'tool_use',
            'id': tc.id,
            'name': tc.name,
            'input': tc.arguments,
          });
        }
        apiMessages.add({'role': 'assistant', 'content': content});
      } else {
        apiMessages.add({
          'role': msg.role.value,
          'content': msg.content,
        });
      }
    }

    final body = <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens,
      'messages': apiMessages,
      'stream': true,
    };

    if (systemPrompt != null) {
      body['system'] = systemPrompt;
    }

    if (tools.isNotEmpty) {
      body['tools'] = tools.map((t) => t.toAnthropicFormat()).toList();
    }

    // Non-o-series models support temperature
    if (!model.startsWith('o')) {
      body['temperature'] = temperature;
    }

    try {
      final response = await _dio.post<ResponseBody>(
        '/v1/messages',
        data: jsonEncode(body),
        options: Options(
          headers: _headers,
          responseType: ResponseType.stream,
        ),
      );

      final sseParser = SSEParser();
      String currentToolId = '';
      String currentToolName = '';
      int toolIndex = -1;

      final stream = response.data!.stream.cast<List<int>>().transform(utf8.decoder);

      // Process SSE stream inline
      String buffer = '';
      await for (final chunk in stream) {
        buffer += chunk;

        while (buffer.contains('\n\n')) {
          final eventEnd = buffer.indexOf('\n\n');
          final eventBlock = buffer.substring(0, eventEnd);
          buffer = buffer.substring(eventEnd + 2);

          for (final line in eventBlock.split('\n')) {
            if (!line.startsWith('data: ')) continue;
            final data = line.substring(6).trim();

            Map<String, dynamic>? parsed;
            try {
              parsed = jsonDecode(data) as Map<String, dynamic>;
            } catch (_) {
              continue;
            }

            final type = parsed['type'] as String?;

            switch (type) {
              case 'content_block_start':
                final contentBlock =
                    parsed['content_block'] as Map<String, dynamic>?;
                if (contentBlock?['type'] == 'tool_use') {
                  toolIndex++;
                  currentToolId = contentBlock!['id'] as String? ?? '';
                  currentToolName = contentBlock['name'] as String? ?? '';
                  yield ChatChunk(
                    toolCallIndex: toolIndex,
                    toolCallId: currentToolId,
                    toolCallName: currentToolName,
                  );
                }
                break;

              case 'content_block_delta':
                final delta = parsed['delta'] as Map<String, dynamic>?;
                if (delta == null) break;

                final deltaType = delta['type'] as String?;
                if (deltaType == 'text_delta') {
                  yield ChatChunk(content: delta['text'] as String?);
                } else if (deltaType == 'input_json_delta') {
                  yield ChatChunk(
                    toolCallIndex: toolIndex,
                    toolCallArguments:
                        delta['partial_json'] as String?,
                  );
                }
                break;

              case 'message_delta':
                final delta = parsed['delta'] as Map<String, dynamic>?;
                final usage = parsed['usage'] as Map<String, dynamic>?;
                yield ChatChunk(
                  finishReason: delta?['stop_reason'] as String?,
                  completionTokens:
                      usage?['output_tokens'] as int? ?? 0,
                );
                break;

              case 'message_start':
                final message = parsed['message'] as Map<String, dynamic>?;
                final usage = message?['usage'] as Map<String, dynamic>?;
                if (usage != null) {
                  yield ChatChunk(
                    promptTokens:
                        usage['input_tokens'] as int? ?? 0,
                  );
                }
                break;

              case 'message_stop':
                yield const ChatChunk(isDone: true);
                break;
            }
          }
        }
      }

      sseParser.close();
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final responseData = e.response?.data;
      throw Exception(
          'Anthropic API error $statusCode: $responseData');
    }
  }
}
