import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:circuit_ide/agent/providers/cisco_provider.dart';
import 'package:circuit_ide/agent/providers/provider_interface.dart';
import 'package:circuit_ide/core/constants/app_constants.dart';
import 'package:circuit_ide/enums/message_role.dart';
import 'package:circuit_ide/models/chat_message.dart';
import 'package:circuit_ide/models/agent_workspace.dart';
import 'package:circuit_ide/models/provider_lifecycle_event.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Cisco connector health exposes support-safe readiness details',
    () async {
      final provider = _providerWithBody(
        _bodyFromString('{}', contentType: 'application/json'),
      );

      final health = await provider.checkHealth();

      expect(health.status, ConnectorHealthStatus.connected);
      expect(health.endpoint, startsWith('https://'));
      expect(health.protocolVersion, ProviderProtocol.currentVersion);
      expect(health.latency, isNotNull);
      expect(health.errorCategory, ConnectorHealthErrorCategory.none);
      expect(health.retryAdvice, isEmpty);
    },
  );

  test('Cisco connector health classifies actionable transport failures', () {
    final options = RequestOptions(path: 'https://connector.example.test');
    DioException responseError(int statusCode) => DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response(requestOptions: options, statusCode: statusCode),
    );

    expect(
      classifyConnectorHealthError(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: 'network is unreachable',
        ),
      ),
      ConnectorHealthErrorCategory.offline,
    );
    expect(
      classifyConnectorHealthError(
        DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        ),
      ),
      ConnectorHealthErrorCategory.timeout,
    );
    expect(
      classifyConnectorHealthError(responseError(401)),
      ConnectorHealthErrorCategory.authentication,
    );
    expect(
      classifyConnectorHealthError(responseError(429)),
      ConnectorHealthErrorCategory.rateLimited,
    );
    expect(
      classifyConnectorHealthError(responseError(503)),
      ConnectorHealthErrorCategory.server,
    );
    expect(
      classifyConnectorHealthError(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badCertificate,
          error: 'certificate verify failed',
        ),
      ),
      ConnectorHealthErrorCategory.certificate,
    );
    expect(
      classifyConnectorHealthError(const FormatException('invalid JSON')),
      ConnectorHealthErrorCategory.malformedResponse,
    );
    expect(
      connectorHealthRetryAdvice(ConnectorHealthErrorCategory.rateLimited),
      contains('Wait briefly'),
    );
  });

  test(
    'Cisco OAuth and model catalog requests reject redirects before dispatch',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter((options) {
        requests.add(options);
        if (options.path == AppConstants.ciscoTokenUrl) {
          return _bodyFromString(
            '{"access_token":"catalog-token","expires_in":3600}',
            contentType: 'application/json',
          );
        }
        return _bodyFromString(
          '{"data":[{"id":"gpt-5-nano","context_window":120000}]}',
          contentType: 'application/json',
        );
      });
      final provider = CiscoProvider(dio: dio);
      await provider.connect(const {
        'client_id': 'client-id',
        'client_secret': 'client-secret',
        'app_key': 'app-key',
      });

      final models = await provider.refreshModels();

      expect(models.map((model) => model.id), contains('gpt-5-nano'));
      expect(requests, hasLength(2));
      final tokenRequest = requests.singleWhere(
        (request) => request.path == AppConstants.ciscoTokenUrl,
      );
      final catalogRequest = requests.singleWhere(
        (request) => request.path == AppConstants.ciscoChatBaseUrl,
      );
      expect(tokenRequest.followRedirects, isFalse);
      expect(tokenRequest.maxRedirects, 0);
      expect(tokenRequest.headers['Authorization'], startsWith('Basic '));
      expect(catalogRequest.followRedirects, isFalse);
      expect(catalogRequest.maxRedirects, 0);
      expect(catalogRequest.headers['api-key'], 'catalog-token');
    },
  );

  test(
    'CiscoProvider negotiates the typed protocol before streaming',
    () async {
      RequestOptions? captured;
      final provider = _providerWithBody(
        _bodyFromString(
          'data: {"choices":[{"delta":{"content":"Ready"}}]}\n\n'
          'data: [DONE]\n\n',
          contentType: 'text/event-stream',
          extraHeaders: const {
            'x-circuit-protocol-version': ['1'],
          },
        ),
        onRequest: (options) => captured = options,
      );

      final chunks = await _collect(provider);

      expect(captured?.headers['X-Circuit-Protocol-Version'], '1');
      expect(captured?.followRedirects, isFalse);
      expect(captured?.maxRedirects, 0);
      final requestBody =
          jsonDecode(captured?.data as String) as Map<String, dynamic>;
      expect(requestBody['circuit_protocol'], {
        'version': 1,
        'minimumCompatible': 1,
      });
      expect(
        chunks
            .where(
              (chunk) =>
                  chunk.lifecycleKind == ProviderLifecycleEventKind.connected,
            )
            .single
            .lifecycleDetail,
        contains('protocol 1'),
      );
      expect(
        chunks
            .where(
              (chunk) =>
                  chunk.lifecycleKind == ProviderLifecycleEventKind.connected,
            )
            .single
            .lifecycleDetail,
        contains('explicit acknowledgement'),
      );
    },
  );

  test(
    'CiscoProvider applies the request-scoped project policy before connector transport',
    () async {
      var blockedRequests = 0;
      final blockedProvider = _providerWithBody(
        _bodyFromString('data: [DONE]\n\n', contentType: 'text/event-stream'),
        onRequest: (_) => blockedRequests++,
      );
      final blockedChunks = <ChatChunk>[];
      Object? blockedError;
      try {
        await for (final chunk in blockedProvider.chatWithRequest(
          _connectorRequest(
            const ProviderConnectorNetworkPolicy(
              networkDisposition: WorkspacePermissionDisposition.block,
            ),
          ),
        )) {
          blockedChunks.add(chunk);
        }
      } catch (error) {
        blockedError = error;
      }

      expect(blockedRequests, 0);
      expect(blockedError, isA<ProviderConnectorNetworkPolicyException>());
      expect(
        blockedChunks.single.lifecycleKind,
        ProviderLifecycleEventKind.failed,
      );
      expect(blockedChunks.single.lifecycleDetail, contains('blocks'));

      var deniedRequests = 0;
      final deniedProvider = _providerWithBody(
        _bodyFromString('data: [DONE]\n\n', contentType: 'text/event-stream'),
        onRequest: (_) => deniedRequests++,
      );
      await expectLater(
        deniedProvider
            .chatWithRequest(
              _connectorRequest(
                const ProviderConnectorNetworkPolicy(
                  networkRules: [
                    WorkspaceNetworkRule(
                      domain: 'chat-ai.cisco.com',
                      disposition: WorkspaceNetworkRuleDisposition.deny,
                    ),
                  ],
                ),
              ),
            )
            .drain<void>(),
        throwsA(isA<ProviderConnectorNetworkPolicyException>()),
      );
      expect(deniedRequests, 0);

      var reviewRequests = 0;
      final reviewProvider = _providerWithBody(
        _bodyFromString(
          'data: {"choices":[{"delta":{"content":"Reviewed"}}]}\n\n'
          'data: [DONE]\n\n',
          contentType: 'text/event-stream',
        ),
        onRequest: (_) => reviewRequests++,
      );
      const reviewPolicy = ProviderConnectorNetworkPolicy(
        networkDisposition: WorkspacePermissionDisposition.block,
        networkRules: [
          WorkspaceNetworkRule(
            domain: 'chat-ai.cisco.com',
            disposition: WorkspaceNetworkRuleDisposition.ask,
            methods: ['POST'],
            allowUpload: true,
            allowCredentials: true,
          ),
          WorkspaceNetworkRule(
            domain: 'id.cisco.com',
            disposition: WorkspaceNetworkRuleDisposition.allow,
            methods: ['POST'],
            allowCredentials: true,
          ),
        ],
      );
      await expectLater(
        reviewProvider
            .chatWithRequest(_connectorRequest(reviewPolicy))
            .drain<void>(),
        throwsA(isA<ProviderConnectorNetworkPolicyException>()),
      );
      expect(reviewRequests, 0);
      final chatOrigin =
          reviewProvider.connectorNetworkRequirements.first.approvalKey;
      expect(chatOrigin, 'https://chat-ai.cisco.com');
      final reviewedChunks = await reviewProvider
          .chatWithRequest(
            _connectorRequest(
              reviewPolicy.approveConnectorOrigins([chatOrigin!]),
            ),
          )
          .toList();
      expect(reviewRequests, 1);
      expect(
        reviewedChunks.any((chunk) => chunk.content == 'Reviewed'),
        isTrue,
      );

      var allowedRequests = 0;
      final allowedProvider = _providerWithBody(
        _bodyFromString(
          'data: {"choices":[{"delta":{"content":"Allowed"}}]}\n\n'
          'data: [DONE]\n\n',
          contentType: 'text/event-stream',
        ),
        onRequest: (_) => allowedRequests++,
      );
      final allowedChunks = await allowedProvider
          .chatWithRequest(
            _connectorRequest(
              const ProviderConnectorNetworkPolicy(
                networkDisposition: WorkspacePermissionDisposition.block,
                networkRules: [
                  WorkspaceNetworkRule(
                    domain: 'chat-ai.cisco.com',
                    disposition: WorkspaceNetworkRuleDisposition.allow,
                    methods: ['POST'],
                    allowUpload: true,
                    allowCredentials: true,
                  ),
                  WorkspaceNetworkRule(
                    domain: 'id.cisco.com',
                    disposition: WorkspaceNetworkRuleDisposition.allow,
                    methods: ['POST'],
                    allowCredentials: true,
                  ),
                ],
              ),
            ),
          )
          .toList();

      expect(allowedRequests, 1);
      expect(allowedChunks.any((chunk) => chunk.content == 'Allowed'), isTrue);
    },
  );

  test(
    'CiscoProvider sends validated image pixels as typed content parts',
    () async {
      RequestOptions? captured;
      final provider = _providerWithBody(
        _bodyFromString(
          'data: {"choices":[{"delta":{"content":"I can see it"}}]}\n\n'
          'data: [DONE]\n\n',
          contentType: 'text/event-stream',
        ),
        onRequest: (options) => captured = options,
      );

      await provider
          .chatWithRequest(
            ProviderChatRequest(
              messages: [
                ChatMessage(
                  id: 'user',
                  role: MessageRole.user,
                  content: 'Review this screenshot.',
                  timestamp: DateTime(2026),
                ),
              ],
              model: 'gpt-5-nano',
              tools: const [],
              reasoningEnabled: true,
              images: const [
                ProviderImageInput(
                  id: 'image:screen',
                  label: 'screen.png',
                  mimeType: 'image/png',
                  base64Data: 'cGl4ZWxz',
                  byteLength: 6,
                  width: 2,
                  height: 2,
                  estimatedTokens: 85,
                ),
              ],
            ),
          )
          .toList();

      final body = jsonDecode(captured!.data as String) as Map<String, dynamic>;
      final messages = body['messages'] as List<dynamic>;
      final content =
          (messages.single as Map<String, dynamic>)['content'] as List<dynamic>;
      expect(content.first, {
        'type': 'text',
        'text': 'Review this screenshot.',
      });
      expect((content.last as Map<String, dynamic>)['type'], 'image_url');
      expect(
        ((content.last as Map<String, dynamic>)['image_url']
            as Map<String, dynamic>)['url'],
        'data:image/png;base64,cGl4ZWxz',
      );
      expect(body['reasoning_effort'], 'medium');
    },
  );

  test(
    'CiscoProvider preserves detailed usage dimensions from JSON fallback',
    () async {
      final provider = _providerWithBody(
        _bodyFromString(
          '{"choices":[{"message":{"content":"Usage"},"finish_reason":"stop"}],"usage":{"prompt_tokens":100,"completion_tokens":25,"tool_tokens":5,"prompt_tokens_details":{"cached_tokens":40},"completion_tokens_details":{"reasoning_tokens":12}}}',
          contentType: 'application/json',
        ),
      );

      final chunks = await _collect(provider);
      final completed = chunks.lastWhere((chunk) => chunk.isDone);

      expect(completed.promptTokens, 100);
      expect(completed.cachedInputTokens, 40);
      expect(completed.completionTokens, 25);
      expect(completed.reasoningTokens, 12);
      expect(completed.toolTokens, 5);
    },
  );

  test(
    'CiscoProvider rejects an incompatible protocol acknowledgement',
    () async {
      final provider = _providerWithBody(
        _bodyFromString(
          'data: {"choices":[{"delta":{"content":"Never read"}}]}\n\n',
          contentType: 'text/event-stream',
          extraHeaders: const {
            'x-circuit-protocol-version': ['99'],
          },
        ),
      );

      final result = await _collectWithError(provider);

      expect(result.error, contains('protocol 99 is incompatible'));
      expect(
        _lifecycle(result.chunks),
        contains(ProviderLifecycleEventKind.failed),
      );
      expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
    },
  );

  test(
    'CiscoProvider rejects a present but blank protocol acknowledgement before streaming',
    () async {
      final provider = _providerWithBody(
        _bodyFromString(
          'data: {"choices":[{"delta":{"content":"Never read"}}]}\n\n',
          contentType: 'text/event-stream',
          extraHeaders: const {
            'x-circuit-protocol-version': ['   '],
          },
        ),
      );

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('empty protocol acknowledgement'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.connected)));
      expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.firstByte)));
      expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
    },
  );

  test(
    'CiscoProvider redacts an invalid protocol acknowledgement before streaming',
    () async {
      final provider = _providerWithBody(
        _bodyFromString(
          'data: {"choices":[{"delta":{"content":"Never read"}}]}\n\n',
          contentType: 'text/event-stream',
          extraHeaders: const {
            'x-circuit-protocol-version': ['provider-header-secret'],
          },
        ),
      );

      final result = await _collectWithError(provider);

      expect(result.error, contains('invalid protocol acknowledgement'));
      expect(result.error, isNot(contains('provider-header-secret')));
      expect(
        _lifecycle(result.chunks),
        contains(ProviderLifecycleEventKind.failed),
      );
      expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
    },
  );

  test('CiscoProvider diagnoses content-type JSON fallback early', () async {
    final provider = _providerWithBody(
      _bodyFromString(
        '{"choices":[{"message":{"content":"Hello from JSON"},"finish_reason":"stop"}],"usage":{"prompt_tokens":4,"completion_tokens":3}}',
        contentType: 'application/json',
      ),
    );

    final chunks = await _collect(provider);
    final lifecycle = _lifecycle(chunks);

    expect(lifecycle, contains(ProviderLifecycleEventKind.requestSent));
    expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
    expect(lifecycle, contains(ProviderLifecycleEventKind.nonSseJson));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
    expect(lifecycle, contains(ProviderLifecycleEventKind.jsonFallback));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstTextDelta));
    expect(lifecycle, contains(ProviderLifecycleEventKind.completed));
    expect(
      chunks.where((chunk) => chunk.content == 'Hello from JSON'),
      hasLength(1),
    );
    expect(chunks.last.isDone, isTrue);
    expect(chunks.last.promptTokens, 4);
    expect(chunks.last.completionTokens, 3);
  });

  test(
    'CiscoProvider diagnoses empty response streams as no-first-byte',
    () async {
      final provider = _providerWithBody(
        ResponseBody(
          const Stream<Uint8List>.empty(),
          200,
          headers: {
            Headers.contentTypeHeader: ['text/event-stream'],
          },
        ),
      );

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('no response bytes'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
      expect(lifecycle, contains(ProviderLifecycleEventKind.noFirstByte));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.firstByte)));
      expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
    },
  );

  test(
    'CiscoProvider diagnoses malformed SSE chunks and keeps streaming',
    () async {
      final provider = _providerWithBody(
        _bodyFromString(
          'data: {bad json}\n\n'
          'data: {"choices":[{"delta":{"content":"Recovered"},"finish_reason":null}]}\n\n'
          'data: [DONE]\n\n',
          contentType: 'text/event-stream',
        ),
      );

      final chunks = await _collect(provider);
      final lifecycle = _lifecycle(chunks);

      expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
      expect(lifecycle, contains(ProviderLifecycleEventKind.malformedChunk));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstTextDelta));
      expect(
        chunks.where((chunk) => chunk.content == 'Recovered'),
        hasLength(1),
      );
      expect(chunks.last.isDone, isTrue);
    },
  );

  test(
    'CiscoProvider fails malformed-only SSE completion without valid output',
    () async {
      final provider = _providerWithBody(
        _bodyFromString(
          'data: {bad json}\n\n'
          'data: [DONE]\n\n',
          contentType: 'text/event-stream',
        ),
      );

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('malformed chunks'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
      expect(lifecycle, contains(ProviderLifecycleEventKind.malformedChunk));
      expect(lifecycle, contains(ProviderLifecycleEventKind.noTextOrTool));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.completed)));
      expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
    },
  );

  test('CiscoProvider accepts SSE data fields without a space', () async {
    final provider = _providerWithBody(
      _bodyFromString(
        'data:{"choices":[{"delta":{"content":"Compact"},"finish_reason":null}]}\n\n'
        'data:[DONE]\n\n',
        contentType: 'text/event-stream',
      ),
    );

    final chunks = await _collect(provider);
    final lifecycle = _lifecycle(chunks);

    expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstTextDelta));
    expect(lifecycle, contains(ProviderLifecycleEventKind.completed));
    expect(
      lifecycle,
      isNot(contains(ProviderLifecycleEventKind.streamEndedWithoutDone)),
    );
    expect(chunks.where((chunk) => chunk.content == 'Compact'), hasLength(1));
    expect(chunks.last.isDone, isTrue);
  });

  test('CiscoProvider accepts multi-line SSE data events', () async {
    final provider = _providerWithBody(
      _bodyFromString(
        'data: {"choices":[{"delta":{\n'
        'data: "content":"Split"\n'
        'data: },"finish_reason":null}]}\n\n'
        'data: [DONE]\n\n',
        contentType: 'text/event-stream',
      ),
    );

    final chunks = await _collect(provider);
    final lifecycle = _lifecycle(chunks);

    expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstTextDelta));
    expect(
      lifecycle,
      isNot(contains(ProviderLifecycleEventKind.malformedChunk)),
    );
    expect(chunks.where((chunk) => chunk.content == 'Split'), hasLength(1));
    expect(chunks.last.isDone, isTrue);
  });

  test('CiscoProvider ignores SSE comments and keepalive events', () async {
    final provider = _providerWithBody(
      _bodyFromString(
        ': keepalive\n\n'
        'event: ping\n'
        'data: {}\n\n'
        'event: message\n'
        'data: {"choices":[{"delta":{"content":"Ready after ping"},"finish_reason":null}]}\n\n'
        'data: [DONE]\n\n',
        contentType: 'text/event-stream',
      ),
    );

    final chunks = await _collect(provider);
    final lifecycle = _lifecycle(chunks);

    expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstTextDelta));
    expect(lifecycle, contains(ProviderLifecycleEventKind.completed));
    expect(
      lifecycle,
      isNot(contains(ProviderLifecycleEventKind.malformedChunk)),
    );
    expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.noTextOrTool)));
    expect(
      chunks.where((chunk) => chunk.content == 'Ready after ping'),
      hasLength(1),
    );
    expect(chunks.last.isDone, isTrue);
  });

  test('CiscoProvider preserves UTF-8 split across SSE chunks', () async {
    const body =
        'data: {"choices":[{"delta":{"content":"Ready 🚀"},"finish_reason":null}]}\n\n'
        'data: [DONE]\n\n';
    final provider = _providerWithBody(
      _bodyFromSplitUtf8Body(
        body,
        splitAtNeedle: '🚀',
        contentType: 'text/event-stream',
      ),
    );

    final chunks = await _collect(provider);
    final lifecycle = _lifecycle(chunks);

    expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstTextDelta));
    expect(
      lifecycle,
      isNot(contains(ProviderLifecycleEventKind.malformedChunk)),
    );
    expect(chunks.where((chunk) => chunk.content == 'Ready 🚀'), hasLength(1));
    expect(chunks.last.isDone, isTrue);
  });

  test(
    'CiscoProvider preserves UTF-8 split across JSON fallback chunks',
    () async {
      const body =
          '{"choices":[{"message":{"content":"Hello 🚀"},"finish_reason":"stop"}]}';
      final provider = _providerWithBody(
        _bodyFromSplitUtf8Body(
          body,
          splitAtNeedle: '🚀',
          contentType: 'application/json',
        ),
      );

      final chunks = await _collect(provider);
      final lifecycle = _lifecycle(chunks);

      expect(lifecycle, contains(ProviderLifecycleEventKind.nonSseJson));
      expect(lifecycle, contains(ProviderLifecycleEventKind.jsonFallback));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstTextDelta));
      expect(
        chunks.where((chunk) => chunk.content == 'Hello 🚀'),
        hasLength(1),
      );
      expect(chunks.last.isDone, isTrue);
    },
  );

  test(
    'CiscoProvider diagnoses truncated SSE event after parsed output',
    () async {
      final provider = _providerWithBody(
        _bodyFromString(
          'data: {"choices":[{"delta":{"content":"Partial"},"finish_reason":null}]}\n\n'
          'data: {"choices":[{"delta":{"content":"truncated"}',
          contentType: 'text/event-stream',
        ),
      );

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('without the [DONE] terminator'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
      expect(lifecycle, contains(ProviderLifecycleEventKind.malformedChunk));
      expect(
        lifecycle,
        contains(ProviderLifecycleEventKind.streamEndedWithoutDone),
      );
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstTextDelta));
      expect(
        result.chunks.where((chunk) => chunk.content == 'Partial'),
        hasLength(1),
      );
      expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
    },
  );

  test('CiscoProvider diagnoses clean SSE close without done marker', () async {
    final provider = _providerWithBody(
      _bodyFromString(
        'data: {"choices":[{"delta":{"content":"Partial"},"finish_reason":null}]}\n\n',
        contentType: 'text/event-stream',
      ),
    );

    final result = await _collectWithError(provider);
    final lifecycle = _lifecycle(result.chunks);

    expect(result.error, contains('without the [DONE] terminator'));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstTextDelta));
    expect(
      lifecycle,
      contains(ProviderLifecycleEventKind.streamEndedWithoutDone),
    );
    expect(
      lifecycle,
      isNot(contains(ProviderLifecycleEventKind.malformedChunk)),
    );
    expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    expect(
      result.chunks.where((chunk) => chunk.content == 'Partial'),
      hasLength(1),
    );
    expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
  });

  test(
    'CiscoProvider diagnoses truncated SSE event with no parsed output',
    () async {
      final provider = _providerWithBody(
        _bodyFromString(
          'data: {"choices":[{"delta":{"content":"never closed"}',
          contentType: 'text/event-stream',
        ),
      );

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('without the [DONE] terminator'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
      expect(lifecycle, contains(ProviderLifecycleEventKind.malformedChunk));
      expect(
        lifecycle,
        contains(ProviderLifecycleEventKind.streamEndedWithoutDone),
      );
      expect(lifecycle, contains(ProviderLifecycleEventKind.noTextOrTool));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(
        lifecycle,
        isNot(contains(ProviderLifecycleEventKind.jsonFallback)),
      );
      expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
    },
  );

  test(
    'CiscoProvider falls back when SSE content-type carries plain JSON',
    () async {
      final provider = _providerWithBody(
        _bodyFromString(
          '{"choices":[{"message":{"content":"Plain JSON"},"finish_reason":"stop"}]}',
          contentType: 'text/event-stream',
        ),
      );

      final chunks = await _collect(provider);
      final lifecycle = _lifecycle(chunks);

      expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
      expect(lifecycle, contains(ProviderLifecycleEventKind.nonSseJson));
      expect(lifecycle, contains(ProviderLifecycleEventKind.jsonFallback));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstTextDelta));
      expect(
        chunks.where((chunk) => chunk.content == 'Plain JSON'),
        hasLength(1),
      );
      expect(chunks.last.isDone, isTrue);
    },
  );

  test('CiscoProvider diagnoses tool-only JSON fallback responses', () async {
    final provider = _providerWithBody(
      _bodyFromString(
        '{"choices":[{"message":{"tool_calls":[{"id":"tool","function":{"name":"read_file","arguments":"{}"}}]},"finish_reason":"tool_calls"}]}',
        contentType: 'application/json',
      ),
    );

    final chunks = await _collect(provider);
    final lifecycle = _lifecycle(chunks);

    expect(lifecycle, contains(ProviderLifecycleEventKind.toolOnly));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstToolDelta));
    expect(lifecycle, contains(ProviderLifecycleEventKind.completed));
    expect(chunks.any((chunk) => chunk.toolCallName == 'read_file'), isTrue);
    expect(chunks.last.isDone, isTrue);
  });

  test(
    'CiscoProvider fails malformed JSON fallback tool-call shapes clearly',
    () async {
      final provider = _providerWithBody(
        _bodyFromString(
          '{"choices":[{"message":{"tool_calls":[{"id":"tool","function":"not an object"}]},"finish_reason":"tool_calls"}]}',
          contentType: 'application/json',
        ),
      );

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('malformed tool-call function'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.nonSseJson));
      expect(lifecycle, contains(ProviderLifecycleEventKind.jsonFallback));
      expect(lifecycle, contains(ProviderLifecycleEventKind.malformedChunk));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.toolOnly)));
      expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
    },
  );

  test('CiscoProvider fails malformed JSON fallback choices clearly', () async {
    final provider = _providerWithBody(
      _bodyFromString('{"choices":[null]}', contentType: 'application/json'),
    );

    final result = await _collectWithError(provider);
    final lifecycle = _lifecycle(result.chunks);

    expect(result.error, contains('malformed choice entry'));
    expect(lifecycle, contains(ProviderLifecycleEventKind.nonSseJson));
    expect(lifecycle, contains(ProviderLifecycleEventKind.jsonFallback));
    expect(lifecycle, contains(ProviderLifecycleEventKind.malformedChunk));
    expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
  });

  test(
    'CiscoProvider fails malformed JSON fallback messages clearly',
    () async {
      final provider = _providerWithBody(
        _bodyFromString(
          '{"choices":[{"message":"not an object","finish_reason":"stop"}]}',
          contentType: 'application/json',
        ),
      );

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('malformed message'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.nonSseJson));
      expect(lifecycle, contains(ProviderLifecycleEventKind.jsonFallback));
      expect(lifecycle, contains(ProviderLifecycleEventKind.malformedChunk));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
    },
  );

  test('CiscoProvider diagnoses tool-only SSE responses', () async {
    final provider = _providerWithBody(
      _bodyFromString(
        'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"tool","function":{"name":"read_file","arguments":"{}"}}]},"finish_reason":null}]}\n\n'
        'data: [DONE]\n\n',
        contentType: 'text/event-stream',
      ),
    );

    final chunks = await _collect(provider);
    final lifecycle = _lifecycle(chunks);

    expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstToolDelta));
    expect(lifecycle, contains(ProviderLifecycleEventKind.toolOnly));
    expect(chunks.any((chunk) => chunk.toolCallName == 'read_file'), isTrue);
    expect(chunks.last.isDone, isTrue);
  });

  test(
    'CiscoProvider diagnoses malformed SSE tool-call shapes and continues streaming',
    () async {
      final provider = _providerWithBody(
        _bodyFromString(
          'data: {"choices":[{"delta":{"tool_calls":"bad shape"},"finish_reason":null}]}\n\n'
          'data: {"choices":[{"delta":{"content":"Recovered text"},"finish_reason":null}]}\n\n'
          'data: [DONE]\n\n',
          contentType: 'text/event-stream',
        ),
      );

      final chunks = await _collect(provider);
      final lifecycle = _lifecycle(chunks);

      expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
      expect(lifecycle, contains(ProviderLifecycleEventKind.malformedChunk));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstTextDelta));
      expect(
        lifecycle,
        isNot(contains(ProviderLifecycleEventKind.firstToolDelta)),
      );
      expect(
        chunks.where((chunk) => chunk.content == 'Recovered text'),
        hasLength(1),
      );
      expect(chunks.last.isDone, isTrue);
    },
  );

  test('CiscoProvider accepts split SSE tool-call argument deltas', () async {
    final provider = _providerWithBody(
      _bodyFromString(
        'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"tool","function":{"name":"read_file","arguments":"{\\"path\\""}}]},"finish_reason":null}]}\n\n'
        'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":":\\"lib/main.dart\\"}"}}]},"finish_reason":null}]}\n\n'
        'data: [DONE]\n\n',
        contentType: 'text/event-stream',
      ),
    );

    final chunks = await _collect(provider);
    final lifecycle = _lifecycle(chunks);

    expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstToolDelta));
    expect(lifecycle, contains(ProviderLifecycleEventKind.toolOnly));
    expect(lifecycle, contains(ProviderLifecycleEventKind.completed));
    expect(
      lifecycle,
      isNot(contains(ProviderLifecycleEventKind.malformedChunk)),
    );
    final toolChunks = chunks
        .where((chunk) => chunk.toolCallIndex != null)
        .toList(growable: false);
    expect(toolChunks, hasLength(2));
    expect(toolChunks[0].toolCallName, 'read_file');
    expect(toolChunks[0].toolCallArguments, '{"path"');
    expect(toolChunks[1].toolCallName, isNull);
    expect(toolChunks[1].toolCallArguments, ':"lib/main.dart"}');
    expect(chunks.last.isDone, isTrue);
  });

  test('CiscoProvider diagnoses malformed SSE tool-call argument deltas', () async {
    final provider = _providerWithBody(
      _bodyFromString(
        'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"tool","function":{"name":"read_file","arguments":{"path":"lib/main.dart"}}}]},"finish_reason":null}]}\n\n'
        'data: {"choices":[{"delta":{"content":"Recovered text"},"finish_reason":null}]}\n\n'
        'data: [DONE]\n\n',
        contentType: 'text/event-stream',
      ),
    );

    final chunks = await _collect(provider);
    final lifecycle = _lifecycle(chunks);

    expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
    expect(lifecycle, contains(ProviderLifecycleEventKind.malformedChunk));
    expect(
      lifecycle,
      isNot(contains(ProviderLifecycleEventKind.firstToolDelta)),
    );
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstTextDelta));
    expect(
      chunks.where((chunk) => chunk.content == 'Recovered text'),
      hasLength(1),
    );
    expect(chunks.any((chunk) => chunk.toolCallName != null), isFalse);
    expect(chunks.last.isDone, isTrue);
  });

  test(
    'CiscoProvider diagnoses malformed SSE choices and deltas and continues streaming',
    () async {
      final provider = _providerWithBody(
        _bodyFromString(
          'data: {"choices":[null]}\n\n'
          'data: {"choices":[{"delta":"not an object","finish_reason":null}]}\n\n'
          'data: {"choices":[{"delta":{"content":"Recovered after malformed chunks"},"finish_reason":null}]}\n\n'
          'data: [DONE]\n\n',
          contentType: 'text/event-stream',
        ),
      );

      final chunks = await _collect(provider);
      final lifecycle = _lifecycle(chunks);

      expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
      expect(
        lifecycle
            .where((kind) => kind == ProviderLifecycleEventKind.malformedChunk)
            .length,
        greaterThanOrEqualTo(2),
      );
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstTextDelta));
      expect(
        chunks.where(
          (chunk) => chunk.content == 'Recovered after malformed chunks',
        ),
        hasLength(1),
      );
      expect(chunks.last.isDone, isTrue);
    },
  );

  test('CiscoProvider accepts full message payloads inside SSE events', () async {
    final provider = _providerWithBody(
      _bodyFromString(
        'data: {"choices":[{"message":{"content":"Full message over SSE"},"finish_reason":"stop"}]}\n\n'
        'data: [DONE]\n\n',
        contentType: 'text/event-stream',
      ),
    );

    final chunks = await _collect(provider);
    final lifecycle = _lifecycle(chunks);

    expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstTextDelta));
    expect(lifecycle, contains(ProviderLifecycleEventKind.completed));
    expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.noTextOrTool)));
    expect(
      chunks.where((chunk) => chunk.content == 'Full message over SSE'),
      hasLength(1),
    );
    expect(chunks.last.isDone, isTrue);
  });

  test(
    'CiscoProvider accepts full message tool calls inside SSE events',
    () async {
      final provider = _providerWithBody(
        _bodyFromString(
          'data: {"choices":[{"message":{"tool_calls":[{"id":"tool","function":{"name":"read_file","arguments":"{}"}}]},"finish_reason":"tool_calls"}]}\n\n'
          'data: [DONE]\n\n',
          contentType: 'text/event-stream',
        ),
      );

      final chunks = await _collect(provider);
      final lifecycle = _lifecycle(chunks);

      expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstToolDelta));
      expect(lifecycle, contains(ProviderLifecycleEventKind.toolOnly));
      expect(lifecycle, contains(ProviderLifecycleEventKind.completed));
      expect(chunks.any((chunk) => chunk.toolCallName == 'read_file'), isTrue);
      expect(chunks.last.isDone, isTrue);
    },
  );

  test(
    'CiscoProvider diagnoses malformed full message SSE payloads clearly',
    () async {
      final provider = _providerWithBody(
        _bodyFromString(
          'data: {"choices":[{"message":"not an object","finish_reason":"stop"}]}\n\n'
          'data: [DONE]\n\n',
          contentType: 'text/event-stream',
        ),
      );

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('malformed'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
      expect(lifecycle, contains(ProviderLifecycleEventKind.malformedChunk));
      expect(lifecycle, contains(ProviderLifecycleEventKind.noTextOrTool));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.completed)));
    },
  );

  test('CiscoProvider fails SSE completion with no text or tools', () async {
    final provider = _providerWithBody(
      _bodyFromString(
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
        'data: [DONE]\n\n',
        contentType: 'text/event-stream',
      ),
    );

    final result = await _collectWithError(provider);
    final lifecycle = _lifecycle(result.chunks);

    expect(result.error, contains('without assistant text or tool calls'));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
    expect(lifecycle, contains(ProviderLifecycleEventKind.noTextOrTool));
    expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.completed)));
    expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
  });

  test('CiscoProvider fails JSON fallback with no text or tools', () async {
    final provider = _providerWithBody(
      _bodyFromString(
        '{"choices":[{"message":{},"finish_reason":"stop"}]}',
        contentType: 'application/json',
      ),
    );

    final result = await _collectWithError(provider);
    final lifecycle = _lifecycle(result.chunks);

    expect(result.error, contains('no assistant text or tool calls'));
    expect(lifecycle, contains(ProviderLifecycleEventKind.noTextOrTool));
    expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.completed)));
    expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
  });

  test('CiscoProvider fails JSON fallback with empty choices', () async {
    final provider = _providerWithBody(
      _bodyFromString('{"choices":[]}', contentType: 'application/json'),
    );

    final result = await _collectWithError(provider);
    final lifecycle = _lifecycle(result.chunks);

    expect(result.error, contains('no choices'));
    expect(lifecycle, contains(ProviderLifecycleEventKind.noTextOrTool));
    expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.completed)));
    expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
  });

  test('CiscoProvider fails HTTP 200 JSON error payloads clearly', () async {
    final provider = _providerWithBody(
      _bodyFromString(
        '{"error":{"message":"connector returned an upstream model error"}}',
        contentType: 'application/json',
      ),
    );

    final result = await _collectWithError(provider);
    final lifecycle = _lifecycle(result.chunks);

    expect(result.error, contains('error payload'));
    expect(result.error, contains('Circuit provider reported an error.'));
    expect(result.error, isNot(contains('upstream model error')));
    expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
    expect(lifecycle, contains(ProviderLifecycleEventKind.nonSseJson));
    expect(lifecycle, contains(ProviderLifecycleEventKind.jsonFallback));
    expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.completed)));
    expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.noTextOrTool)));
    expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
  });

  test('CiscoProvider fails SSE error payload events clearly', () async {
    final provider = _providerWithBody(
      _bodyFromString(
        'data: {"error":{"message":"streamed connector failure"}}\n\n'
        'data: [DONE]\n\n',
        contentType: 'text/event-stream',
      ),
    );

    final result = await _collectWithError(provider);
    final lifecycle = _lifecycle(result.chunks);

    expect(result.error, contains('error payload'));
    expect(result.error, contains('Circuit provider reported an error.'));
    expect(result.error, isNot(contains('streamed connector failure')));
    expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
    expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.completed)));
    expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.noTextOrTool)));
    expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
  });

  test('CiscoProvider fails SSE event:error JSON messages clearly', () async {
    final provider = _providerWithBody(
      _bodyFromString(
        'event: error\n'
        'data: {"message":"provider stream error event"}\n\n'
        'data: [DONE]\n\n',
        contentType: 'text/event-stream',
      ),
    );

    final result = await _collectWithError(provider);
    final lifecycle = _lifecycle(result.chunks);

    expect(result.error, contains('SSE error event'));
    expect(result.error, isNot(contains('provider stream error event')));
    expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
    expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.completed)));
    expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.noTextOrTool)));
    expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
  });

  test(
    'CiscoProvider fails SSE event:error after partial text without completing',
    () async {
      final provider = _providerWithBody(
        _bodyFromString(
          'data: {"choices":[{"delta":{"content":"partial answer"},"finish_reason":null}]}\n\n'
          'event: error\n'
          'data: {"message":"connector failed after partial text"}\n\n'
          'data: [DONE]\n\n',
          contentType: 'text/event-stream',
        ),
      );

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('SSE error event'));
      expect(
        result.error,
        isNot(contains('connector failed after partial text')),
      );
      expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstTextDelta));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.completed)));
      expect(
        lifecycle,
        isNot(contains(ProviderLifecycleEventKind.noTextOrTool)),
      );
      expect(
        result.chunks.where((chunk) => chunk.content == 'partial answer'),
        hasLength(1),
      );
      expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
    },
  );

  test('CiscoProvider fails SSE event:error text payloads clearly', () async {
    final provider = _providerWithBody(
      _bodyFromString(
        'event: error\n'
        'data: upstream stream exploded\n\n'
        'data: [DONE]\n\n',
        contentType: 'text/event-stream',
      ),
    );

    final result = await _collectWithError(provider);
    final lifecycle = _lifecycle(result.chunks);

    expect(result.error, contains('SSE error event'));
    expect(result.error, isNot(contains('upstream stream exploded')));
    expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
    expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.completed)));
    expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.noTextOrTool)));
    expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
  });

  test(
    'CiscoProvider emits failed diagnostic for malformed JSON fallback',
    () async {
      final provider = _providerWithBody(
        _bodyFromString('this is not json', contentType: 'application/json'),
      );

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('Invalid response from Circuit API'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.jsonFallback));
      expect(lifecycle, contains(ProviderLifecycleEventKind.malformedChunk));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(
        result.chunks
            .where(
              (chunk) =>
                  chunk.lifecycleKind ==
                  ProviderLifecycleEventKind.malformedChunk,
            )
            .single
            .lifecycleDetail,
        contains('JSON fallback body was malformed'),
      );
      expect(
        result.chunks
            .where(
              (chunk) =>
                  chunk.lifecycleKind == ProviderLifecycleEventKind.failed,
            )
            .single
            .lifecycleDetail,
        contains('Invalid response from Circuit API'),
      );
    },
  );

  test(
    'CiscoProvider emits failed diagnostic for malformed SSE JSON fallback',
    () async {
      final provider = _providerWithBody(
        _bodyFromString('{"choices":[', contentType: 'text/event-stream'),
      );

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('Invalid response from Circuit API'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.nonSseJson));
      expect(lifecycle, contains(ProviderLifecycleEventKind.jsonFallback));
      expect(lifecycle, contains(ProviderLifecycleEventKind.malformedChunk));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    },
  );

  test('CiscoProvider emits failed diagnostic for API error bodies', () async {
    final provider = _providerWithBody(
      _bodyFromString(
        '{"error":{"message":"provider-response-secret"}}',
        contentType: 'application/json',
        statusCode: 503,
      ),
    );

    final result = await _collectWithError(provider);
    final lifecycle = _lifecycle(result.chunks);

    expect(result.error, contains('Circuit API error 503'));
    expect(result.error, isNot(contains('provider-response-secret')));
    expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
    expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    expect(
      result.chunks
          .where(
            (chunk) =>
                chunk.lifecycleKind == ProviderLifecycleEventKind.connected,
          )
          .single
          .lifecycleDetail,
      contains('HTTP 503'),
    );
    expect(
      result.chunks
          .where(
            (chunk) => chunk.lifecycleKind == ProviderLifecycleEventKind.failed,
          )
          .single
          .lifecycleDetail,
      isNot(contains('provider-response-secret')),
    );
  });

  test(
    'CiscoProvider emits rate-limit diagnostic with retry-after detail',
    () async {
      final dio = Dio();
      final requestOptions = RequestOptions(path: '/chat');
      dio.httpClientAdapter = _ThrowingAdapter(
        DioException(
          requestOptions: requestOptions,
          response: Response<ResponseBody>(
            requestOptions: requestOptions,
            statusCode: 429,
            headers: Headers.fromMap({
              'retry-after': ['17'],
            }),
            data: _bodyFromString(
              '{"error":{"message":"provider-response-secret"}}',
              contentType: 'application/json',
              statusCode: 429,
            ),
          ),
          type: DioExceptionType.badResponse,
        ),
      );
      final provider = CiscoProvider(
        dio: dio,
        accessToken: 'test-token',
        tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
        appKey: 'test-app',
      );

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
      expect(lifecycle, contains(ProviderLifecycleEventKind.rateLimited));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(result.error, contains('rate limit'));
      expect(result.error, isNot(contains('provider-response-secret')));
      expect(result.error, contains('Retry after 17s'));
      expect(
        result.chunks
            .where(
              (chunk) =>
                  chunk.lifecycleKind == ProviderLifecycleEventKind.rateLimited,
            )
            .single
            .lifecycleDetail,
        contains('Retry after 17s'),
      );
    },
  );

  test(
    'CiscoProvider emits auth failure when 401 token refresh cannot run',
    () async {
      final provider = _providerWithBody(
        _bodyFromString(
          '{"error":{"message":"expired token"}}',
          contentType: 'application/json',
          statusCode: 401,
        ),
      );

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('authentication refresh failed'));
      expect(result.error, contains('authentication refresh failed'));
      expect(result.error, contains('Reconnect Circuit Company AI'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.authFailed));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.connected)));
      expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.firstByte)));
    },
  );

  test(
    'CiscoProvider reconnects once after refreshing a rejected token without duplicate text',
    () async {
      final dio = Dio();
      var tokenRequests = 0;
      var chatRequests = 0;
      dio.httpClientAdapter = _FakeAdapter((options) {
        if (options.path == AppConstants.ciscoTokenUrl) {
          tokenRequests += 1;
          return _bodyFromString(
            '{"access_token":"fresh-token-$tokenRequests","expires_in":3600}',
            contentType: 'application/json',
          );
        }
        chatRequests += 1;
        if (chatRequests == 1) {
          return _bodyFromString(
            '{"error":{"message":"expired token"}}',
            contentType: 'application/json',
            statusCode: 401,
          );
        }
        return _bodyFromString(
          'data: {"choices":[{"delta":{"content":"Recovered exactly once"},"finish_reason":null}]}\n\n'
          'data: [DONE]\n\n',
          contentType: 'text/event-stream',
        );
      });
      final provider = CiscoProvider(dio: dio);
      await provider.connect(const {
        'client_id': 'client',
        'client_secret': 'secret',
        'app_key': 'app',
      });

      final chunks = await _collect(provider);
      final lifecycle = _lifecycle(chunks);

      expect(tokenRequests, 2);
      expect(chatRequests, 2);
      expect(
        lifecycle.where(
          (kind) => kind == ProviderLifecycleEventKind.reconnecting,
        ),
        hasLength(1),
      );
      expect(
        chunks.where((chunk) => chunk.content == 'Recovered exactly once'),
        hasLength(1),
      );
      expect(chunks.where((chunk) => chunk.isDone), hasLength(1));
    },
  );

  test(
    'CiscoProvider stops after one rejected-token reconnect attempt',
    () async {
      final dio = Dio();
      var tokenRequests = 0;
      var chatRequests = 0;
      dio.httpClientAdapter = _FakeAdapter((options) {
        if (options.path == AppConstants.ciscoTokenUrl) {
          tokenRequests += 1;
          return _bodyFromString(
            '{"access_token":"fresh-token-$tokenRequests","expires_in":3600}',
            contentType: 'application/json',
          );
        }
        chatRequests += 1;
        return _bodyFromString(
          '{"error":{"message":"still rejected"}}',
          contentType: 'application/json',
          statusCode: 401,
        );
      });
      final provider = CiscoProvider(dio: dio);
      await provider.connect(const {
        'client_id': 'client',
        'client_secret': 'secret',
        'app_key': 'app',
      });

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(tokenRequests, 2);
      expect(chatRequests, 2);
      expect(result.error, contains('after one reconnect attempt'));
      expect(
        lifecycle.where(
          (kind) => kind == ProviderLifecycleEventKind.reconnecting,
        ),
        hasLength(1),
      );
      expect(lifecycle, contains(ProviderLifecycleEventKind.authFailed));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
    },
  );

  test('CiscoProvider redacts plain-text API error bodies', () async {
    final provider = _providerWithBody(
      _bodyFromString(
        'provider-response-secret',
        contentType: 'text/plain',
        statusCode: 504,
      ),
    );

    final result = await _collectWithError(provider);
    final lifecycle = _lifecycle(result.chunks);

    expect(result.error, contains('Circuit API error 504'));
    expect(result.error, isNot(contains('provider-response-secret')));
    expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
    expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
  });

  test(
    'CiscoProvider never reads an API error body stream into diagnostics',
    () async {
      final dio = Dio();
      final errorStream = Stream<Uint8List>.error(
        Exception('provider-response-secret'),
      );
      dio.httpClientAdapter = _ThrowingAdapter(
        DioException(
          requestOptions: RequestOptions(path: '/chat'),
          response: Response<ResponseBody>(
            requestOptions: RequestOptions(path: '/chat'),
            statusCode: 502,
            data: ResponseBody(
              errorStream,
              502,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            ),
          ),
        ),
      );
      final provider = CiscoProvider(
        dio: dio,
        accessToken: 'test-token',
        tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
        appKey: 'test-app',
      );

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('Circuit API error 502'));
      expect(result.error, isNot(contains('provider-response-secret')));
      expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(
        result.chunks
            .where(
              (chunk) =>
                  chunk.lifecycleKind == ProviderLifecycleEventKind.failed,
            )
            .single
            .lifecycleDetail,
        isNot(contains('provider-response-secret')),
      );
    },
  );

  test('CiscoProvider emits failed diagnostic for transport errors', () async {
    final dio = Dio();
    dio.httpClientAdapter = _ThrowingAdapter(
      DioException(
        requestOptions: RequestOptions(path: '/chat'),
        type: DioExceptionType.connectionError,
        error: 'provider-transport-secret',
      ),
    );
    final provider = CiscoProvider(
      dio: dio,
      accessToken: 'test-token',
      tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
      appKey: 'test-app',
    );

    final result = await _collectWithError(provider);
    final lifecycle = _lifecycle(result.chunks);

    expect(result.error, contains('Circuit API request failed'));
    expect(result.error, isNot(contains('provider-transport-secret')));
    expect(lifecycle, contains(ProviderLifecycleEventKind.noFirstByte));
    expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.connected)));
    expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.firstByte)));
  });

  test('CiscoProvider diagnoses missing credentials before request', () async {
    final provider = CiscoProvider(dio: Dio());

    final result = await _collectWithError(provider);
    final lifecycle = _lifecycle(result.chunks);

    expect(result.error, contains('Circuit authentication failed'));
    expect(result.error, contains('Reconnect Circuit Company AI'));
    expect(lifecycle, contains(ProviderLifecycleEventKind.authFailed));
    expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.connected)));
  });

  test('CiscoProvider emits timeout diagnostic for request timeouts', () async {
    final dio = Dio();
    dio.httpClientAdapter = _ThrowingAdapter(
      DioException(
        requestOptions: RequestOptions(path: '/chat'),
        type: DioExceptionType.receiveTimeout,
        message: 'upstream did not respond in time',
      ),
    );
    final provider = CiscoProvider(
      dio: dio,
      accessToken: 'test-token',
      tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
      appKey: 'test-app',
    );

    final result = await _collectWithError(provider);
    final lifecycle = _lifecycle(result.chunks);

    expect(result.error, contains('timed out'));
    expect(lifecycle, contains(ProviderLifecycleEventKind.timeout));
    expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
  });

  test(
    'CiscoProvider emits cancelled diagnostic when request is cancelled',
    () async {
      final dio = Dio();
      final adapter = _CancellableAdapter();
      dio.httpClientAdapter = adapter;
      final provider = CiscoProvider(
        dio: dio,
        accessToken: 'test-token',
        tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
        appKey: 'test-app',
      );

      final future = _collectWithError(provider);
      await adapter.started.future;
      provider.cancelActiveRequest();
      final result = await future;

      expect(result.error, contains('Request cancelled'));
      expect(
        _lifecycle(result.chunks),
        contains(ProviderLifecycleEventKind.cancelled),
      );
      expect(
        _lifecycle(result.chunks),
        isNot(contains(ProviderLifecycleEventKind.failed)),
      );
    },
  );

  test(
    'CiscoProvider emits cancelled diagnostic when JSON body stream is cancelled',
    () async {
      final dio = Dio();
      final adapter = _StreamingJsonAdapter();
      dio.httpClientAdapter = adapter;
      final provider = CiscoProvider(
        dio: dio,
        accessToken: 'test-token',
        tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
        appKey: 'test-app',
      );

      final future = _collectWithError(provider);
      await adapter.listenerAttached.future;
      provider.cancelActiveRequest();
      final result = await future;

      expect(result.error, contains('Request cancelled'));
      expect(
        _lifecycle(result.chunks),
        contains(ProviderLifecycleEventKind.cancelled),
      );
      expect(
        _lifecycle(result.chunks),
        isNot(contains(ProviderLifecycleEventKind.failed)),
      );
    },
  );

  test(
    'CiscoProvider emits cancelled diagnostic when SSE body stream is cancelled',
    () async {
      final dio = Dio();
      final adapter = _StreamingBodyAdapter(contentType: 'text/event-stream');
      dio.httpClientAdapter = adapter;
      final provider = CiscoProvider(
        dio: dio,
        accessToken: 'test-token',
        tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
        appKey: 'test-app',
      );

      final future = _collectWithError(provider);
      await adapter.listenerAttached.future;
      provider.cancelActiveRequest();
      final result = await future;

      expect(result.error, contains('Request cancelled'));
      expect(
        _lifecycle(result.chunks),
        contains(ProviderLifecycleEventKind.cancelled),
      );
      expect(
        _lifecycle(result.chunks),
        isNot(contains(ProviderLifecycleEventKind.failed)),
      );
    },
  );

  test(
    'CiscoProvider emits failed diagnostic for JSON stream errors',
    () async {
      final dio = Dio();
      final adapter = _StreamingJsonAdapter();
      dio.httpClientAdapter = adapter;
      final provider = CiscoProvider(
        dio: dio,
        accessToken: 'test-token',
        tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
        appKey: 'test-app',
      );

      final future = _collectWithError(provider);
      await adapter.listenerAttached.future;
      adapter.addText('{"choices":[');
      await adapter.fail(Exception('upstream stream closed'));
      final result = await future;
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('response stream failed'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
      expect(lifecycle, contains(ProviderLifecycleEventKind.nonSseJson));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    },
  );

  test(
    'CiscoProvider diagnoses JSON body stream failures before bytes as no-first-byte',
    () async {
      final dio = Dio();
      final adapter = _StreamingJsonAdapter();
      dio.httpClientAdapter = adapter;
      final provider = CiscoProvider(
        dio: dio,
        accessToken: 'test-token',
        tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
        appKey: 'test-app',
      );

      final future = _collectWithError(provider);
      await adapter.listenerAttached.future;
      await adapter.fail(Exception('json body stream opened then failed'));
      final result = await future;
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('response stream failed'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
      expect(lifecycle, contains(ProviderLifecycleEventKind.nonSseJson));
      expect(lifecycle, contains(ProviderLifecycleEventKind.noFirstByte));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.firstByte)));
      expect(
        result.chunks
            .where(
              (chunk) =>
                  chunk.lifecycleKind == ProviderLifecycleEventKind.noFirstByte,
            )
            .single
            .lifecycleDetail,
        contains('before returning response bytes'),
      );
    },
  );

  test('CiscoProvider emits failed diagnostic for SSE stream errors', () async {
    final dio = Dio();
    final adapter = _StreamingBodyAdapter(contentType: 'text/event-stream');
    dio.httpClientAdapter = adapter;
    final provider = CiscoProvider(
      dio: dio,
      accessToken: 'test-token',
      tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
      appKey: 'test-app',
    );

    final future = _collectWithError(provider);
    await adapter.listenerAttached.future;
    adapter.addText(
      'data: {"choices":[{"delta":{"content":"partial"},"finish_reason":null}]}\n\n',
    );
    await adapter.fail(Exception('socket reset by peer'));
    final result = await future;
    final lifecycle = _lifecycle(result.chunks);

    expect(result.error, contains('response stream failed'));
    expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
    expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    expect(
      result.chunks.where((chunk) => chunk.content == 'partial'),
      hasLength(1),
    );
  });

  test(
    'CiscoProvider diagnoses SSE body stream failures before bytes as no-first-byte',
    () async {
      final dio = Dio();
      final adapter = _StreamingBodyAdapter(contentType: 'text/event-stream');
      dio.httpClientAdapter = adapter;
      final provider = CiscoProvider(
        dio: dio,
        accessToken: 'test-token',
        tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
        appKey: 'test-app',
      );

      final future = _collectWithError(provider);
      await adapter.listenerAttached.future;
      await adapter.fail(Exception('sse body stream opened then failed'));
      final result = await future;
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('response stream failed'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
      expect(lifecycle, contains(ProviderLifecycleEventKind.noFirstByte));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.firstByte)));
      expect(
        result.chunks
            .where(
              (chunk) =>
                  chunk.lifecycleKind == ProviderLifecycleEventKind.noFirstByte,
            )
            .single
            .lifecycleDetail,
        contains('before returning response bytes'),
      );
    },
  );

  test(
    'CiscoProvider emits timeout diagnostic for SSE stream timeouts',
    () async {
      final dio = Dio();
      final adapter = _StreamingBodyAdapter(contentType: 'text/event-stream');
      dio.httpClientAdapter = adapter;
      final provider = CiscoProvider(
        dio: dio,
        accessToken: 'test-token',
        tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
        appKey: 'test-app',
      );

      final future = _collectWithError(provider);
      await adapter.listenerAttached.future;
      adapter.addText(
        'data: {"choices":[{"delta":{"content":"partial"},"finish_reason":null}]}\n\n',
      );
      await adapter.fail(
        DioException(
          requestOptions: RequestOptions(path: '/chat'),
          type: DioExceptionType.receiveTimeout,
          message: 'stream stalled',
        ),
      );
      final result = await future;
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('timed out'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.timeout));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    },
  );

  test('CiscoProvider handles real HTTP non-streaming JSON fallback', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));
    unawaited(
      server.forEach((request) async {
        expect(request.method, 'POST');
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'Hello from real JSON'},
                'finish_reason': 'stop',
              },
            ],
            'usage': {'prompt_tokens': 8, 'completion_tokens': 4},
          }),
        );
        await request.response.close();
      }),
    );

    final provider = CiscoProvider(
      accessToken: 'test-token',
      tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
      appKey: 'test-app',
      chatBaseUrl: 'http://${server.address.host}:${server.port}',
    );

    final chunks = await _collect(provider);
    final lifecycle = _lifecycle(chunks);

    expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
    expect(lifecycle, contains(ProviderLifecycleEventKind.nonSseJson));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
    expect(lifecycle, contains(ProviderLifecycleEventKind.jsonFallback));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstTextDelta));
    expect(
      chunks.where((chunk) => chunk.content == 'Hello from real JSON'),
      hasLength(1),
    );
    expect(chunks.last.isDone, isTrue);
    expect(chunks.last.promptTokens, 8);
    expect(chunks.last.completionTokens, 4);
  });

  test(
    'CiscoProvider pins its default transport before opening a model socket',
    () async {
      var resolutionCount = 0;
      final provider = CiscoProvider(
        accessToken: 'test-token',
        tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
        appKey: 'test-app',
        chatBaseUrl: 'https://model.example.test/openai/deployments',
        hostAddressResolver: (_) async {
          resolutionCount++;
          return [InternetAddress.loopbackIPv4];
        },
      );

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(resolutionCount, 1);
      expect(lifecycle, contains(ProviderLifecycleEventKind.requestSent));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    },
  );

  test('CiscoProvider diagnoses real HTTP truncated SSE streams', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));
    unawaited(
      server.forEach((request) async {
        expect(request.method, 'POST');
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'data: {"choices":[{"delta":{"content":"partial"},"finish_reason":null}]}\n\n',
        );
        await request.response.flush();
        request.response.write(
          'data: {"choices":[{"delta":{"content":"truncated"}',
        );
        await request.response.close();
      }),
    );

    final provider = CiscoProvider(
      accessToken: 'test-token',
      tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
      appKey: 'test-app',
      chatBaseUrl: 'http://${server.address.host}:${server.port}',
    );

    final result = await _collectWithError(provider);
    final lifecycle = _lifecycle(result.chunks);

    expect(result.error, contains('without the [DONE] terminator'));
    expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstTextDelta));
    expect(lifecycle, contains(ProviderLifecycleEventKind.malformedChunk));
    expect(
      lifecycle,
      contains(ProviderLifecycleEventKind.streamEndedWithoutDone),
    );
    expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    expect(
      result.chunks.where((chunk) => chunk.content == 'partial'),
      hasLength(1),
    );
    expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
  });

  test('CiscoProvider diagnoses real HTTP SSE error events', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));
    unawaited(
      server.forEach((request) async {
        expect(request.method, 'POST');
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'event: error\n'
          'data: {"message":"provider-response-secret"}\n\n',
        );
        await request.response.flush();
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      }),
    );

    final provider = CiscoProvider(
      accessToken: 'test-token',
      tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
      appKey: 'test-app',
      chatBaseUrl: 'http://${server.address.host}:${server.port}',
    );

    final result = await _collectWithError(provider);
    final lifecycle = _lifecycle(result.chunks);

    expect(result.error, contains('SSE error event'));
    expect(result.error, isNot(contains('provider-response-secret')));
    expect(lifecycle, contains(ProviderLifecycleEventKind.requestSent));
    expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
    expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
    expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.completed)));
    expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.noTextOrTool)));
    expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
  });

  test(
    'CiscoProvider diagnoses real HTTP SSE completion with no useful output',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          expect(request.method, 'POST');
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.write(
            'data: {"choices":[{"delta":{},"finish_reason":null}]}\n\n',
          );
          await request.response.flush();
          request.response.write('data: [DONE]\n\n');
          await request.response.close();
        }),
      );

      final provider = CiscoProvider(
        accessToken: 'test-token',
        tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
        appKey: 'test-app',
        chatBaseUrl: 'http://${server.address.host}:${server.port}',
      );

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('without assistant text or tool calls'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.requestSent));
      expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
      expect(lifecycle, contains(ProviderLifecycleEventKind.noTextOrTool));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.completed)));
      expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.toolOnly)));
      expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
    },
  );

  test('CiscoProvider diagnoses real HTTP connector error responses', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));
    unawaited(
      server.forEach((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, contains('/gpt-5-nano/chat/completions'));
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'error': {'message': 'provider-response-secret'},
          }),
        );
        await request.response.close();
      }),
    );

    final provider = CiscoProvider(
      accessToken: 'test-token',
      tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
      appKey: 'test-app',
      chatBaseUrl: 'http://${server.address.host}:${server.port}',
    );

    final result = await _collectWithError(provider);
    final lifecycle = _lifecycle(result.chunks);

    expect(result.error, contains('Circuit API error 503'));
    expect(result.error, isNot(contains('provider-response-secret')));
    expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
    expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.firstByte)));
    expect(
      result.chunks
          .where(
            (chunk) => chunk.lifecycleKind == ProviderLifecycleEventKind.failed,
          )
          .single
          .lifecycleDetail,
      isNot(contains('provider-response-secret')),
    );
  });

  test(
    'CiscoProvider diagnoses real HTTP rate limits with retry-after detail',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          expect(request.method, 'POST');
          expect(request.uri.path, contains('/gpt-5-nano/chat/completions'));
          request.response.statusCode = HttpStatus.tooManyRequests;
          request.response.headers.contentType = ContentType.json;
          request.response.headers.set('retry-after', '23');
          request.response.write(
            jsonEncode({
              'error': {'message': 'provider-response-secret'},
            }),
          );
          await request.response.close();
        }),
      );

      final provider = CiscoProvider(
        accessToken: 'test-token',
        tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
        appKey: 'test-app',
        chatBaseUrl: 'http://${server.address.host}:${server.port}',
      );

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('rate limit'));
      expect(result.error, isNot(contains('provider-response-secret')));
      expect(result.error, contains('Retry after 23s'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
      expect(lifecycle, contains(ProviderLifecycleEventKind.rateLimited));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(
        result.chunks
            .where(
              (chunk) =>
                  chunk.lifecycleKind == ProviderLifecycleEventKind.rateLimited,
            )
            .single
            .lifecycleDetail,
        contains('Retry after 23s'),
      );
      expect(
        result.chunks
            .where(
              (chunk) =>
                  chunk.lifecycleKind == ProviderLifecycleEventKind.failed,
            )
            .single
            .lifecycleDetail,
        isNot(contains('provider-response-secret')),
      );
    },
  );

  test(
    'CiscoProvider diagnoses real HTTP malformed non-SSE success bodies',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          expect(request.method, 'POST');
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.text;
          request.response.write(
            'proxy returned an HTML/text body instead of SSE or JSON',
          );
          await request.response.close();
        }),
      );

      final provider = CiscoProvider(
        accessToken: 'test-token',
        tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
        appKey: 'test-app',
        chatBaseUrl: 'http://${server.address.host}:${server.port}',
      );

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('Invalid response from Circuit API'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
      expect(lifecycle, contains(ProviderLifecycleEventKind.nonSseJson));
      expect(lifecycle, contains(ProviderLifecycleEventKind.jsonFallback));
      expect(lifecycle, contains(ProviderLifecycleEventKind.malformedChunk));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.completed)));
      expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
    },
  );

  test(
    'CiscoProvider diagnoses real HTTP tool-only JSON fallback responses',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          expect(request.method, 'POST');
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'tool_calls': [
                      {
                        'id': 'real-tool-json',
                        'function': {
                          'name': 'read_file',
                          'arguments': '{"path":"README.md"}',
                        },
                      },
                    ],
                  },
                  'finish_reason': 'tool_calls',
                },
              ],
              'usage': {'prompt_tokens': 9, 'completion_tokens': 5},
            }),
          );
          await request.response.close();
        }),
      );

      final provider = CiscoProvider(
        accessToken: 'test-token',
        tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
        appKey: 'test-app',
        chatBaseUrl: 'http://${server.address.host}:${server.port}',
      );

      final chunks = await _collect(provider);
      final lifecycle = _lifecycle(chunks);

      expect(lifecycle, contains(ProviderLifecycleEventKind.requestSent));
      expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
      expect(lifecycle, contains(ProviderLifecycleEventKind.nonSseJson));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
      expect(lifecycle, contains(ProviderLifecycleEventKind.jsonFallback));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstToolDelta));
      expect(lifecycle, contains(ProviderLifecycleEventKind.toolOnly));
      expect(lifecycle, contains(ProviderLifecycleEventKind.completed));
      expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.failed)));
      expect(
        lifecycle,
        isNot(contains(ProviderLifecycleEventKind.noTextOrTool)),
      );
      expect(chunks.any((chunk) => chunk.content?.isNotEmpty == true), isFalse);
      expect(
        chunks.where((chunk) => chunk.toolCallName == 'read_file'),
        hasLength(1),
      );
      expect(chunks.last.isDone, isTrue);
      expect(chunks.last.promptTokens, 9);
      expect(chunks.last.completionTokens, 5);
    },
  );

  test(
    'CiscoProvider diagnoses real HTTP closed-port transport failures',
    () async {
      final closedServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = closedServer.port;
      await closedServer.close(force: true);

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(milliseconds: 200),
          receiveTimeout: const Duration(milliseconds: 200),
        ),
      );
      final provider = CiscoProvider(
        dio: dio,
        accessToken: 'test-token',
        tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
        appKey: 'test-app',
        chatBaseUrl: 'http://${InternetAddress.loopbackIPv4.host}:$port',
      );

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('Circuit API request failed'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.requestSent));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.connected)));
      expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.firstByte)));
      expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.timeout)));
    },
  );

  test(
    'CiscoProvider diagnoses real HTTP response stalls before bytes as timeout',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          expect(request.method, 'POST');
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          await request.response.flush();
          await Future<void>.delayed(const Duration(seconds: 1));
          await request.response.close();
        }),
      );

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 1),
          receiveTimeout: const Duration(milliseconds: 150),
        ),
      );
      final provider = CiscoProvider(
        dio: dio,
        accessToken: 'test-token',
        tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
        appKey: 'test-app',
        chatBaseUrl: 'http://${server.address.host}:${server.port}',
      );

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('timed out'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.requestSent));
      expect(lifecycle, contains(ProviderLifecycleEventKind.timeout));
      expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.firstByte)));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    },
  );

  test(
    'CiscoProvider diagnoses SSE body idle stalls after text as timeout',
    () async {
      final adapter = _StreamingBodyAdapter(contentType: 'text/event-stream');
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 1),
          receiveTimeout: const Duration(milliseconds: 80),
        ),
      );
      dio.httpClientAdapter = adapter;
      final provider = CiscoProvider(
        dio: dio,
        accessToken: 'test-token',
        tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
        appKey: 'test-app',
      );

      final future = _collectWithError(provider);
      await adapter.listenerAttached.future;
      adapter.addText(
        'data: {"choices":[{"delta":{"content":"partial"},"finish_reason":null}]}\n\n',
      );
      final result = await future;
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('timed out'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.requestSent));
      expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstTextDelta));
      expect(lifecycle, contains(ProviderLifecycleEventKind.timeout));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(
        lifecycle,
        isNot(contains(ProviderLifecycleEventKind.noFirstByte)),
      );
      expect(
        result.chunks.where((chunk) => chunk.content == 'partial'),
        hasLength(1),
      );
    },
  );

  test(
    'CiscoProvider distinguishes malformed raw bytes from no-first-byte',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          expect(request.method, 'POST');
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.add(const [0xff, 0xfe]);
          await request.response.flush();
          await request.response.close();
        }),
      );

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 1),
          receiveTimeout: const Duration(milliseconds: 150),
        ),
      );
      final provider = CiscoProvider(
        dio: dio,
        accessToken: 'test-token',
        tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
        appKey: 'test-app',
        chatBaseUrl: 'http://${server.address.host}:${server.port}',
      );

      final result = await _collectWithError(provider);
      final lifecycle = _lifecycle(result.chunks);

      expect(result.error, contains('malformed UTF-8 response bytes'));
      expect(lifecycle, contains(ProviderLifecycleEventKind.requestSent));
      expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
      expect(lifecycle, contains(ProviderLifecycleEventKind.firstByte));
      expect(lifecycle, contains(ProviderLifecycleEventKind.malformedBytes));
      expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
      expect(
        lifecycle,
        isNot(contains(ProviderLifecycleEventKind.noFirstByte)),
      );
      expect(
        lifecycle,
        isNot(contains(ProviderLifecycleEventKind.jsonFallback)),
      );
    },
  );

  test('CiscoProvider diagnoses real HTTP 204 no-content responses', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));
    unawaited(
      server.forEach((request) async {
        expect(request.method, 'POST');
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      }),
    );

    final provider = CiscoProvider(
      accessToken: 'test-token',
      tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
      appKey: 'test-app',
      chatBaseUrl: 'http://${server.address.host}:${server.port}',
    );

    final result = await _collectWithError(provider);
    final lifecycle = _lifecycle(result.chunks);

    expect(result.error, contains('no response bytes'));
    expect(lifecycle, contains(ProviderLifecycleEventKind.connected));
    expect(lifecycle, contains(ProviderLifecycleEventKind.noFirstByte));
    expect(lifecycle, contains(ProviderLifecycleEventKind.failed));
    expect(lifecycle, isNot(contains(ProviderLifecycleEventKind.firstByte)));
    expect(result.chunks.any((chunk) => chunk.isDone), isFalse);
  });
}

CiscoProvider _providerWithBody(
  ResponseBody body, {
  void Function(RequestOptions options)? onRequest,
}) {
  final dio = Dio();
  dio.httpClientAdapter = _FakeAdapter((options) {
    onRequest?.call(options);
    return body;
  });
  return CiscoProvider(
    dio: dio,
    accessToken: 'test-token',
    tokenExpiry: DateTime.now().add(const Duration(hours: 1)),
    appKey: 'test-app',
  );
}

ResponseBody _bodyFromString(
  String body, {
  required String contentType,
  int statusCode = 200,
  Map<String, List<String>> extraHeaders = const {},
}) {
  return ResponseBody.fromString(
    body,
    statusCode,
    headers: {
      Headers.contentTypeHeader: [contentType],
      Headers.contentLengthHeader: [utf8.encode(body).length.toString()],
      ...extraHeaders,
    },
  );
}

ResponseBody _bodyFromSplitUtf8Body(
  String body, {
  required String splitAtNeedle,
  required String contentType,
  int statusCode = 200,
}) {
  final bytes = utf8.encode(body);
  final needleBytes = utf8.encode(splitAtNeedle);
  final splitIndex = _indexOfBytes(bytes, needleBytes);
  assert(splitIndex >= 0, 'split needle not found in body');
  final splitInsideNeedle = splitIndex + 1;
  return ResponseBody(
    Stream<Uint8List>.fromIterable([
      Uint8List.fromList(bytes.sublist(0, splitInsideNeedle)),
      Uint8List.fromList(bytes.sublist(splitInsideNeedle)),
    ]),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [contentType],
      Headers.contentLengthHeader: [bytes.length.toString()],
    },
  );
}

int _indexOfBytes(List<int> haystack, List<int> needle) {
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var matches = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        matches = false;
        break;
      }
    }
    if (matches) return i;
  }
  return -1;
}

Future<List<ChatChunk>> _collect(CiscoProvider provider) {
  return provider
      .chat(
        [
          ChatMessage(
            id: 'user',
            role: MessageRole.user,
            content: 'hello',
            timestamp: DateTime(2026),
          ),
        ],
        model: 'gpt-5-nano',
        tools: const [],
      )
      .toList();
}

ProviderChatRequest _connectorRequest(
  ProviderConnectorNetworkPolicy connectorNetworkPolicy,
) => ProviderChatRequest(
  messages: [
    ChatMessage(
      id: 'connector-policy-user',
      role: MessageRole.user,
      content: 'hello',
      timestamp: DateTime(2026),
    ),
  ],
  model: 'gpt-5-nano',
  tools: const [],
  connectorNetworkPolicy: connectorNetworkPolicy,
);

Future<_CollectedProviderError> _collectWithError(
  CiscoProvider provider,
) async {
  final chunks = <ChatChunk>[];
  Object? error;
  try {
    await for (final chunk in provider.chat(
      [
        ChatMessage(
          id: 'user',
          role: MessageRole.user,
          content: 'hello',
          timestamp: DateTime(2026),
        ),
      ],
      model: 'gpt-5-nano',
      tools: const [],
    )) {
      chunks.add(chunk);
    }
  } catch (caught) {
    error = caught;
  }
  return _CollectedProviderError(chunks: chunks, error: error.toString());
}

List<ProviderLifecycleEventKind> _lifecycle(List<ChatChunk> chunks) {
  return chunks
      .map((chunk) => chunk.lifecycleKind)
      .whereType<ProviderLifecycleEventKind>()
      .toList();
}

class _FakeAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;

  const _FakeAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class _ThrowingAdapter implements HttpClientAdapter {
  final DioException error;

  const _ThrowingAdapter(this.error);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw error;
  }

  @override
  void close({bool force = false}) {}
}

class _CancellableAdapter implements HttpClientAdapter {
  final started = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    started.complete();
    await cancelFuture;
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.cancel,
      error: 'cancelled by test',
    );
  }

  @override
  void close({bool force = false}) {}
}

class _StreamingBodyAdapter implements HttpClientAdapter {
  final String contentType;
  final listenerAttached = Completer<void>();
  final _controller = StreamController<Uint8List>();

  _StreamingBodyAdapter({required this.contentType});

  void addText(String text) {
    _controller.add(Uint8List.fromList(utf8.encode(text)));
  }

  Future<void> fail(Object error) async {
    _controller.addError(error);
    await _controller.close();
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    cancelFuture?.then((_) {
      if (!_controller.isClosed) {
        _controller.addError(Exception('cancelled by test'));
        _controller.close();
      }
    });
    return ResponseBody(
      _controller.stream
          .transform(
            StreamTransformer<Uint8List, Uint8List>.fromHandlers(
              handleData: (data, sink) {
                sink.add(data);
              },
              handleDone: (sink) {
                sink.close();
              },
            ),
          )
          .asBroadcastStream(
            onListen: (_) {
              if (!listenerAttached.isCompleted) listenerAttached.complete();
            },
          ),
      200,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {
    if (!_controller.isClosed) _controller.close();
  }
}

class _StreamingJsonAdapter extends _StreamingBodyAdapter {
  _StreamingJsonAdapter() : super(contentType: 'application/json');
}

class _CollectedProviderError {
  final List<ChatChunk> chunks;
  final String error;

  const _CollectedProviderError({required this.chunks, required this.error});
}
