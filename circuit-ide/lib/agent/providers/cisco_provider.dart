import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';
import '../../models/chat_message.dart';
import '../../models/provider_lifecycle_event.dart';
import '../config/models_config.dart';
import 'cisco_chat_request_composer.dart';
import 'cisco_connector_health.dart';
import 'cisco_model_catalog.dart';
import 'cisco_network_client.dart';
import 'cisco_provider_descriptor.dart';
import 'cisco_response_parser.dart';
import 'cisco_stream_support.dart';
import 'cisco_token_authenticator.dart';
import 'cisco_transport_failure.dart';
import 'provider_interface.dart';

export 'cisco_response_parser.dart' show CiscoResponseParser;
export 'cisco_connector_health.dart'
    show classifyConnectorHealthError, connectorHealthRetryAdvice;

class CiscoProvider
    implements
        AIProvider,
        ImageCapableProvider,
        ProviderConnectorNetworkPolicyAware {
  late final Dio _dio;
  late final CiscoTokenAuthenticator _authenticator;
  bool _connected = false;
  CancelToken? _activeCancelToken;
  late final String _chatBaseUrl;

  CiscoProvider({
    Dio? dio,
    CiscoProviderHostAddressResolver? hostAddressResolver,
    String? accessToken,
    DateTime? tokenExpiry,
    String? appKey,
    String? chatBaseUrl,
  }) {
    _dio =
        dio ?? createCiscoProviderDio(hostAddressResolver: hostAddressResolver);
    _authenticator = CiscoTokenAuthenticator(
      _dio,
      accessToken: accessToken,
      tokenExpiry: tokenExpiry,
      appKey: appKey,
    );
    _chatBaseUrl = chatBaseUrl ?? AppConstants.ciscoChatBaseUrl;
    _connected = accessToken != null;
  }

  @override
  String get name => 'Circuit Company AI';

  @override
  List<ModelInfo> get availableModels => ModelsConfig.ciscoModels;

  @override
  ProviderDescriptor get descriptor => CiscoProviderDescriptor.circuit;

  @override
  ProviderCapabilities get capabilities => descriptor.capabilities;

  ProviderProtocol get protocol => descriptor.protocol;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect(Map<String, String> credentials) async {
    _authenticator.configure(credentials);
    await _authenticator.refreshToken();
    _connected = true;
    Logger.info('Connected to Circuit Company AI', 'CiscoProvider');
  }

  @override
  void disconnect() {
    _connected = false;
    _authenticator.clearAccessToken();
    cancelActiveRequest();
    Logger.info('Disconnected from Circuit Company AI', 'CiscoProvider');
  }

  @override
  Future<ConnectorHealth> checkHealth() async {
    return CiscoConnectorHealthReporter.check(
      hasCredentialsOrToken:
          _authenticator.hasCredentials || _authenticator.hasAccessToken,
      endpoint: _healthEndpoint,
      protocol: protocol,
      ensureToken: _authenticator.getToken,
    );
  }

  String get _healthEndpoint {
    final uri = Uri.tryParse(AppConstants.ciscoTokenUrl);
    if (uri == null || uri.host.isEmpty) return 'Configured Circuit endpoint';
    final scheme = uri.scheme.isEmpty ? 'https' : uri.scheme;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '$scheme://${uri.host}$port';
  }

  @override
  void cancelActiveRequest() {
    _activeCancelToken?.cancel('Request cancelled by user.');
    _activeCancelToken = null;
  }

  @override
  Future<List<ConnectorModelInfo>> refreshModels() async {
    if (!_authenticator.hasCredentials) {
      return CiscoModelCatalog.bundled();
    }

    try {
      final token = await _authenticator.getToken();
      final response = await _dio.get(
        AppConstants.ciscoChatBaseUrl,
        queryParameters: {'api-version': AppConstants.ciscoApiVersion},
        options: Options(
          headers: {'api-key': token},
          // Provider redirects could cross a connector trust boundary. A
          // configured connector endpoint is the only allowed destination;
          // surface an unexpected redirect as an actionable request failure.
          followRedirects: false,
          maxRedirects: 0,
        ),
      );
      final parsed = CiscoModelCatalog.parse(response.data);
      if (parsed.isNotEmpty) return parsed;
    } catch (_) {
      Logger.warning(
        'Circuit model refresh fell back to the bundled catalog.',
        'CiscoProvider',
      );
    }
    return CiscoModelCatalog.bundled();
  }

  @override
  List<ProviderConnectorNetworkRequirement> get connectorNetworkRequirements =>
      [
        ProviderConnectorNetworkRequirement(
          url: _chatBaseUrl,
          label: 'Circuit model connector',
          usesWorkspaceUpload: true,
          usesCredentials: true,
        ),
        const ProviderConnectorNetworkRequirement(
          url: AppConstants.ciscoTokenUrl,
          label: 'Circuit OAuth connector',
          usesCredentials: true,
        ),
      ];

  /// Applies the project policy to both configured connector origins before a
  /// token refresh or streamed chat request can leave the workspace boundary.
  /// The policy snapshot belongs to one request, never to this shared provider
  /// instance, so concurrent turns cannot inherit each other's network grant.
  void _enforceConnectorNetworkPolicy(ProviderConnectorNetworkPolicy policy) {
    for (final requirement in connectorNetworkRequirements) {
      final access = policy.evaluate(requirement);
      if (access.decision == ProviderConnectorNetworkDecision.allow) {
        continue;
      }
      final message = access.decision == ProviderConnectorNetworkDecision.ask
          ? '${access.message} Approve this connector request in Studio before sending.'
          : access.message;
      throw ProviderConnectorNetworkPolicyException(message);
    }
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
    yield* _chat(
      messages,
      model: model,
      tools: tools,
      systemPrompt: systemPrompt,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Stream<ChatChunk> chatWithRequest(ProviderChatRequest request) async* {
    if (request.images.isNotEmpty &&
        !CiscoModelCatalog.supportsImageInputFor(request.model)) {
      throw ProviderCapabilityException(
        'Circuit Company AI does not support image input for ${request.model}.',
      );
    }
    if (request.reasoningEnabled &&
        !CiscoModelCatalog.supportsReasoningFor(request.model)) {
      throw ProviderCapabilityException(
        'Circuit Company AI does not support reasoning controls for ${request.model}.',
      );
    }
    yield* _chat(
      request.messages,
      model: request.model,
      tools: request.tools,
      systemPrompt: request.systemPrompt,
      temperature: request.temperature,
      maxTokens: request.maxTokens,
      images: request.images,
      reasoningEnabled: request.reasoningEnabled,
      connectorNetworkPolicy: request.connectorNetworkPolicy,
    );
  }

  Stream<ChatChunk> _chat(
    List<ChatMessage> messages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
    List<ProviderImageInput> images = const [],
    bool reasoningEnabled = false,
    ProviderConnectorNetworkPolicy connectorNetworkPolicy =
        ProviderConnectorNetworkPolicy.unrestricted,
    int authenticationReconnectAttempt = 0,
  }) async* {
    try {
      _enforceConnectorNetworkPolicy(connectorNetworkPolicy);
    } on ProviderConnectorNetworkPolicyException catch (error) {
      yield ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: error.message,
      );
      rethrow;
    }
    final String token;
    try {
      token = await _authenticator.getToken();
    } catch (_) {
      const errorMsg =
          'Circuit authentication failed. Reconnect Circuit Company AI before retrying.';
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.authFailed,
        lifecycleDetail: errorMsg,
      );
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: errorMsg,
      );
      throw Exception(errorMsg);
    }
    final composedRequest = CiscoChatRequestComposer.compose(
      chatBaseUrl: _chatBaseUrl,
      model: model,
      appKey: _authenticator.appKey,
      protocol: protocol,
      messages: messages,
      tools: tools,
      systemPrompt: systemPrompt,
      temperature: temperature,
      maxTokens: maxTokens,
      images: images,
      reasoningEnabled: reasoningEnabled,
    );

    Logger.info(
      'Sending Circuit chat request (model: $model, messages: ${composedRequest.messageCount})',
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
        composedRequest.url,
        data: jsonEncode(composedRequest.body),
        cancelToken: cancelToken,
        options: Options(
          headers: {
            'api-key': token,
            'Content-Type': 'application/json',
            'X-Circuit-Protocol-Version': '${protocol.version}',
          },
          responseType: ResponseType.stream,
          followRedirects: false,
          maxRedirects: 0,
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
      if (CiscoStreamSupport.isTimeout(e)) {
        const errorMsg = 'Circuit API request timed out.';
        yield const ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.timeout,
          lifecycleDetail: errorMsg,
        );
        yield const ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.failed,
          lifecycleDetail: errorMsg,
        );
        throw Exception(errorMsg);
      }
      final status = e.response?.statusCode;
      if (status == 401) {
        if (authenticationReconnectAttempt >= 1) {
          const errorMsg =
              'Circuit authentication was rejected after one reconnect attempt. Reconnect Circuit Company AI before retrying.';
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.authFailed,
            lifecycleDetail: errorMsg,
          );
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.failed,
            lifecycleDetail: errorMsg,
          );
          throw Exception(errorMsg);
        }
        try {
          await _authenticator.refreshToken();
        } catch (_) {
          const errorMsg =
              'Circuit authentication refresh failed. Reconnect Circuit Company AI before retrying.';
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.authFailed,
            lifecycleDetail: errorMsg,
          );
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.failed,
            lifecycleDetail: errorMsg,
          );
          throw Exception(errorMsg);
        }
        // An HTTP 401 does not expose a response stream, so one fresh-token
        // retry cannot duplicate streamed text or tool calls. Bound it to a
        // single attempt so a misconfigured connector never loops forever.
        yield const ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.reconnecting,
          lifecycleDetail:
              'Circuit refreshed authentication and is reconnecting the request once.',
        );
        yield* _chat(
          messages,
          model: model,
          tools: tools,
          systemPrompt: systemPrompt,
          temperature: temperature,
          maxTokens: maxTokens,
          images: images,
          reasoningEnabled: reasoningEnabled,
          connectorNetworkPolicy: connectorNetworkPolicy,
          authenticationReconnectAttempt: authenticationReconnectAttempt + 1,
        );
        return;
      }
      final failure = await CiscoTransportFailure.fromDio(e);
      if (failure.statusCode != null) {
        yield ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.connected,
          lifecycleDetail:
              'Circuit API responded with HTTP ${failure.statusCode}.',
        );
      }
      if (failure.isRateLimited) {
        yield ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.rateLimited,
          lifecycleDetail: failure.retryAfterDetail == null
              ? 'Circuit API rate limit reached.'
              : 'Circuit API rate limit reached. ${failure.retryAfterDetail}',
        );
      }
      if (failure.statusCode == null) {
        yield const ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.noFirstByte,
          lifecycleDetail:
              'Circuit API request failed before an HTTP response was received.',
        );
      }
      yield ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: failure.errorMessage,
      );
      throw Exception(failure.errorMessage);
    } catch (_) {
      const errorMsg = 'Circuit API request failed.';
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.noFirstByte,
        lifecycleDetail:
            'Circuit API request failed before a response stream was opened.',
      );
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: errorMsg,
      );
      throw Exception(errorMsg);
    }

    final protocolAcknowledgement = response.headers.value(
      'x-circuit-protocol-version',
    );
    final int negotiatedProtocolVersion;
    try {
      negotiatedProtocolVersion = protocol.negotiateResponseVersion(
        protocolAcknowledgement,
      );
    } on ProviderProtocolCompatibilityException catch (error) {
      if (identical(_activeCancelToken, cancelToken)) {
        _activeCancelToken = null;
      }
      yield ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: error.message,
      );
      throw Exception(error.message);
    }

    yield ChatChunk(
      lifecycleKind: ProviderLifecycleEventKind.connected,
      lifecycleDetail:
          'Circuit API accepted the request (${response.statusCode ?? 'stream'}; '
          'protocol $negotiatedProtocolVersion, '
          '${protocolAcknowledgement == null ? 'legacy v1 compatibility' : 'explicit acknowledgement'}).',
    );

    final contentType = response.headers
        .value(Headers.contentTypeHeader)
        ?.toLowerCase();
    if (CiscoStreamSupport.isJsonContentType(contentType)) {
      yield ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.nonSseJson,
        lifecycleDetail:
            'Circuit returned ${contentType ?? 'JSON'} instead of SSE.',
      );
      final body = StringBuffer();
      var sawFirstByte = false;
      var sawRawFirstByte = false;
      try {
        await for (final text in CiscoStreamSupport.decodeUtf8Stream(
          response.data!.stream,
          idleTimeout: _dio.options.receiveTimeout,
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
        if (CiscoStreamSupport.isCancellation(error, cancelToken)) {
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.cancelled,
            lifecycleDetail: 'Circuit API request was cancelled.',
          );
          throw Exception('Request cancelled');
        }
        if (CiscoStreamSupport.isMalformedBytes(error)) {
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
        if (CiscoStreamSupport.isTimeoutError(error)) {
          final detail =
              'Circuit API response stream timed out: ${CiscoStreamSupport.timeoutDetail(error)}';
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
        const detail = 'Circuit API response stream failed.';
        if (!sawFirstByte) {
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.noFirstByte,
            lifecycleDetail:
                'Circuit API response stream failed before returning response bytes.',
          );
        }
        yield const ChatChunk(
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
      yield* CiscoStreamSupport.parseJsonFallbackWithDiagnostics(
        body.toString().trim(),
      );
      return;
    }

    // Read the stream as SSE; if no SSE payload appears, fall back to JSON.
    final stream = response.data!.stream;
    String buffer = '';
    int promptTokens = 0;
    int cachedInputTokens = 0;
    int completionTokens = 0;
    int reasoningTokens = 0;
    int toolTokens = 0;
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
      await for (final text in CiscoStreamSupport.decodeUtf8Stream(
        stream,
        idleTimeout: _dio.options.receiveTimeout,
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
                'Circuit SSE error event: ${CiscoStreamSupport.sseErrorEventMessage(payload)}';
            yield ChatChunk(
              lifecycleKind: ProviderLifecycleEventKind.failed,
              lifecycleDetail: detail,
            );
            throw ProviderLifecycleException(detail);
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
              throw const ProviderLifecycleException(
                'Circuit SSE stream completed after malformed chunks without any valid assistant text or tool calls.',
              );
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
              throw const ProviderLifecycleException(
                'Circuit SSE stream completed without assistant text or tool calls.',
              );
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
              cachedInputTokens: cachedInputTokens,
              completionTokens: completionTokens,
              reasoningTokens: reasoningTokens,
              toolTokens: toolTokens,
              isDone: true,
            );
            return;
          }

          Map<String, dynamic> json;
          try {
            json = jsonDecode(payload) as Map<String, dynamic>;
          } catch (_) {
            yield malformedSseChunk(
              'Circuit returned a malformed SSE JSON chunk.',
            );
            continue;
          }

          final errorMessage = ciscoJsonErrorPayloadMessage(json);
          if (errorMessage != null) {
            final detail =
                'Circuit API returned an error payload: $errorMessage';
            yield ChatChunk(
              lifecycleKind: ProviderLifecycleEventKind.failed,
              lifecycleDetail: detail,
            );
            throw ProviderLifecycleException(detail);
          }

          final usage = json['usage'] as Map<String, dynamic>?;
          if (usage != null) {
            promptTokens = usage['prompt_tokens'] as int? ?? promptTokens;
            completionTokens =
                usage['completion_tokens'] as int? ?? completionTokens;
            final promptDetails = usage['prompt_tokens_details'];
            if (promptDetails is Map) {
              cachedInputTokens =
                  promptDetails['cached_tokens'] as int? ?? cachedInputTokens;
            }
            final completionDetails = usage['completion_tokens_details'];
            if (completionDetails is Map) {
              reasoningTokens =
                  completionDetails['reasoning_tokens'] as int? ??
                  reasoningTokens;
            }
            toolTokens = usage['tool_tokens'] as int? ?? toolTokens;
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
      if (error is ProviderLifecycleException) rethrow;
      if (sawRawFirstByte && !sawFirstByte) {
        sawFirstByte = true;
        yield const ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.firstByte,
          lifecycleDetail:
              'Circuit API returned response bytes before the stream failed.',
        );
      }
      if (CiscoStreamSupport.isCancellation(error, cancelToken)) {
        yield const ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.cancelled,
          lifecycleDetail: 'Circuit API request was cancelled.',
        );
        throw Exception('Request cancelled');
      }
      if (CiscoStreamSupport.isMalformedBytes(error)) {
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
      if (CiscoStreamSupport.isTimeoutError(error)) {
        final detail =
            'Circuit API response stream timed out: ${CiscoStreamSupport.timeoutDetail(error)}';
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
      const detail = 'Circuit API response stream failed.';
      if (!sawFirstByte) {
        yield const ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.noFirstByte,
          lifecycleDetail:
              'Circuit API response stream failed before returning response bytes.',
        );
      }
      yield const ChatChunk(
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
    if (trailingBuffer.isNotEmpty &&
        CiscoStreamSupport.looksLikeSsePayload(trailingBuffer)) {
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
      yield* CiscoStreamSupport.parseJsonFallbackWithDiagnostics(buffer.trim());
      return;
    }

    const earlyCloseDetail =
        'Circuit SSE stream ended without the [DONE] terminator.';
    yield const ChatChunk(
      lifecycleKind: ProviderLifecycleEventKind.streamEndedWithoutDone,
      lifecycleDetail: earlyCloseDetail,
    );

    yield* CiscoStreamSupport.diagnoseSseOutput(
      sawTextDelta: sawTextDelta,
      sawToolDelta: sawToolDelta,
    );
    yield const ChatChunk(
      lifecycleKind: ProviderLifecycleEventKind.failed,
      lifecycleDetail: earlyCloseDetail,
    );
    throw Exception(earlyCloseDetail);
  }
}
