import 'dart:convert';
import 'dart:typed_data';

import 'package:circuit_ide/agent/providers/cisco_provider.dart';
import 'package:circuit_ide/agent/providers/provider_interface.dart';
import 'package:circuit_ide/core/constants/app_constants.dart';
import 'package:circuit_ide/models/provider_lifecycle_event.dart';
import 'package:dio/dio.dart';
import 'package:circuit_ide/services/provider_staging_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'records redacted explicit protocol and incremental-stream evidence',
    () async {
      final observedResponse = StringBuffer();
      final result = await inspectProviderStagingStream(
        Stream.fromIterable([
          const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.requestSent,
          ),
          const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.connected,
            lifecycleDetail:
                'Circuit API accepted the request (200; protocol 1, explicit acknowledgement).',
          ),
          const ChatChunk(lifecycleKind: ProviderLifecycleEventKind.firstByte),
          const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.firstTextDelta,
          ),
          const ChatChunk(content: 'okay'),
          const ChatChunk(lifecycleKind: ProviderLifecycleEventKind.completed),
          const ChatChunk(isDone: true),
        ]),
        expectedProtocolVersion: 1,
        onContent: observedResponse.write,
      );

      expect(result.protocolVersion, 1);
      expect(result.acknowledgement, ProviderProtocolAcknowledgement.explicit);
      expect(result.responseCharacterCount, 4);
      expect(result.lifecycle, contains(ProviderLifecycleEventKind.firstByte));
      final evidence = result.toRedactedJsonLine();
      expect(observedResponse.toString(), 'okay');
      expect(evidence, contains('responseCharacterCount'));
      expect(evidence, isNot(contains('okay')));
      expect(evidence, isNot(contains('acknowledgement).')));
    },
  );

  test('accepts documented legacy version-one negotiation', () async {
    final result = await inspectProviderStagingStream(
      Stream.fromIterable([
        const ChatChunk(lifecycleKind: ProviderLifecycleEventKind.requestSent),
        const ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.connected,
          lifecycleDetail:
              'Circuit API accepted the request (stream; protocol 1, legacy v1 compatibility).',
        ),
        const ChatChunk(lifecycleKind: ProviderLifecycleEventKind.firstByte),
        const ChatChunk(
          lifecycleKind: ProviderLifecycleEventKind.firstTextDelta,
        ),
        const ChatChunk(content: 'ok'),
        const ChatChunk(lifecycleKind: ProviderLifecycleEventKind.completed),
        const ChatChunk(isDone: true),
      ]),
      expectedProtocolVersion: 1,
    );

    expect(
      result.acknowledgement,
      ProviderProtocolAcknowledgement.legacyV1Compatibility,
    );
  });

  test(
    'accepts one authentication reconnect before the stream connects',
    () async {
      final result = await inspectProviderStagingStream(
        Stream.fromIterable([
          const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.requestSent,
          ),
          const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.reconnecting,
          ),
          const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.requestSent,
          ),
          const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.connected,
            lifecycleDetail:
                'Circuit API accepted the request (200; protocol 1, explicit acknowledgement).',
          ),
          const ChatChunk(lifecycleKind: ProviderLifecycleEventKind.firstByte),
          const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.firstTextDelta,
          ),
          const ChatChunk(content: 'ok'),
          const ChatChunk(lifecycleKind: ProviderLifecycleEventKind.completed),
          const ChatChunk(isDone: true),
        ]),
        expectedProtocolVersion: 1,
      );

      expect(
        result.lifecycle,
        contains(ProviderLifecycleEventKind.reconnecting),
      );
    },
  );

  test('rejects text emitted after completion', () async {
    await expectLater(
      inspectProviderStagingStream(
        Stream.fromIterable([
          const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.requestSent,
          ),
          const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.connected,
            lifecycleDetail:
                'Circuit API accepted the request (200; protocol 1, explicit acknowledgement).',
          ),
          const ChatChunk(lifecycleKind: ProviderLifecycleEventKind.firstByte),
          const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.firstTextDelta,
          ),
          const ChatChunk(content: 'first'),
          const ChatChunk(lifecycleKind: ProviderLifecycleEventKind.completed),
          const ChatChunk(content: 'late'),
          const ChatChunk(isDone: true),
        ]),
        expectedProtocolVersion: 1,
      ),
      throwsA(isA<ProviderStagingProbeFailure>()),
    );
  });

  test('rejects a duplicate terminal completion signal', () async {
    await expectLater(
      inspectProviderStagingStream(
        Stream.fromIterable([
          const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.requestSent,
          ),
          const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.connected,
            lifecycleDetail:
                'Circuit API accepted the request (200; protocol 1, explicit acknowledgement).',
          ),
          const ChatChunk(lifecycleKind: ProviderLifecycleEventKind.firstByte),
          const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.firstTextDelta,
          ),
          const ChatChunk(content: 'complete'),
          const ChatChunk(lifecycleKind: ProviderLifecycleEventKind.completed),
          const ChatChunk(isDone: true),
          const ChatChunk(isDone: true),
        ]),
        expectedProtocolVersion: 1,
      ),
      throwsA(isA<ProviderStagingProbeFailure>()),
    );
  });

  test('rejects a non-incremental or failed staging lifecycle', () async {
    await expectLater(
      inspectProviderStagingStream(
        Stream.fromIterable([
          const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.requestSent,
          ),
          const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.connected,
            lifecycleDetail:
                'Circuit API accepted the request (200; protocol 1, explicit acknowledgement).',
          ),
          const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.firstTextDelta,
          ),
          const ChatChunk(content: 'late'),
          const ChatChunk(lifecycleKind: ProviderLifecycleEventKind.completed),
          const ChatChunk(isDone: true),
        ]),
        expectedProtocolVersion: 1,
      ),
      throwsA(isA<ProviderStagingProbeFailure>()),
    );
  });

  test('requires safe protected-environment configuration', () {
    expect(
      () => ProviderStagingProbeConfig.fromEnvironment({
        'CIRCUIT_STAGING_CHAT_BASE_URL': 'http://example.test',
        'CIRCUIT_STAGING_ACCESS_TOKEN': 'token',
        'CIRCUIT_STAGING_APP_KEY': 'app',
        'CIRCUIT_STAGING_MODEL': 'model',
      }),
      throwsA(isA<ProviderStagingProbeFailure>()),
    );
    expect(
      () => ProviderStagingProbeConfig.fromEnvironment({
        'CIRCUIT_STAGING_CHAT_BASE_URL': 'https://staging.example.test/models',
        'CIRCUIT_STAGING_ACCESS_TOKEN': 'token',
        'CIRCUIT_STAGING_APP_KEY': 'app',
        'CIRCUIT_STAGING_MODEL': '../unsafe',
      }),
      throwsA(isA<ProviderStagingProbeFailure>()),
    );
  });

  test(
    'uses the documented OAuth client credentials without a static token',
    () {
      final config = ProviderStagingProbeConfig.fromEnvironment(const {
        'CIRCUIT_STAGING_CLIENT_ID': 'protected-client-id',
        'CIRCUIT_STAGING_CLIENT_SECRET': 'protected-client-secret',
        'CIRCUIT_STAGING_APP_KEY': 'protected-app-key',
      });

      expect(config.usesOAuthClientCredentials, isTrue);
      expect(config.accessToken, isNull);
      expect(
        config.chatBaseUri.toString(),
        'https://chat-ai.cisco.com/openai/deployments',
      );
      expect(config.model, ProviderStagingProbeConfig.defaultModel);
    },
  );

  test(
    'retains static-token staging configuration for protected legacy jobs',
    () {
      final config = ProviderStagingProbeConfig.fromEnvironment(const {
        'CIRCUIT_STAGING_ACCESS_TOKEN': 'protected-access-token',
        'CIRCUIT_STAGING_APP_KEY': 'protected-app-key',
      });

      expect(config.usesOAuthClientCredentials, isFalse);
      expect(config.accessToken, 'protected-access-token');
    },
  );

  test(
    'obtains an OAuth token before running the protected staging probe',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio()
        ..httpClientAdapter = _StagingAdapter((options) {
          requests.add(options);
          if (options.path == AppConstants.ciscoTokenUrl) {
            return _responseBody(
              '{"access_token":"probe-token","expires_in":3600}',
              contentType: 'application/json',
            );
          }
          return _responseBody(
            'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n'
            'data: [DONE]\n\n',
            contentType: 'text/event-stream',
            extraHeaders: const {
              'x-circuit-protocol-version': ['1'],
            },
          );
        });
      final config = ProviderStagingProbeConfig.fromEnvironment(const {
        'CIRCUIT_STAGING_CLIENT_ID': 'protected-client-id',
        'CIRCUIT_STAGING_CLIENT_SECRET': 'protected-client-secret',
        'CIRCUIT_STAGING_APP_KEY': 'protected-app-key',
      });

      final result = await ProviderStagingProbe(
        config: config,
        provider: (_) =>
            CiscoProvider(dio: dio, chatBaseUrl: config.chatBaseUri.toString()),
      ).run();

      expect(result.responseCharacterCount, 2);
      expect(requests, hasLength(2));
      final tokenRequest = requests.first;
      final chatRequest = requests.last;
      expect(tokenRequest.path, AppConstants.ciscoTokenUrl);
      expect(tokenRequest.headers['Authorization'], startsWith('Basic '));
      expect(
        chatRequest.path,
        'https://chat-ai.cisco.com/openai/deployments/gpt-5-nano/chat/completions?api-version=2025-04-01-preview',
      );
      expect(chatRequest.headers['api-key'], 'probe-token');
    },
  );

  test('rejects incomplete or ambiguous protected credential modes', () {
    expect(
      () => ProviderStagingProbeConfig.fromEnvironment(const {
        'CIRCUIT_STAGING_CLIENT_ID': 'protected-client-id',
        'CIRCUIT_STAGING_APP_KEY': 'protected-app-key',
      }),
      throwsA(isA<ProviderStagingProbeFailure>()),
    );
    expect(
      () => ProviderStagingProbeConfig.fromEnvironment(const {
        'CIRCUIT_STAGING_ACCESS_TOKEN': 'protected-access-token',
        'CIRCUIT_STAGING_CLIENT_ID': 'protected-client-id',
        'CIRCUIT_STAGING_CLIENT_SECRET': 'protected-client-secret',
        'CIRCUIT_STAGING_APP_KEY': 'protected-app-key',
      }),
      throwsA(isA<ProviderStagingProbeFailure>()),
    );
  });
}

ResponseBody _responseBody(
  String body, {
  required String contentType,
  Map<String, List<String>> extraHeaders = const {},
}) => ResponseBody.fromString(
  body,
  200,
  headers: {
    Headers.contentTypeHeader: [contentType],
    Headers.contentLengthHeader: [utf8.encode(body).length.toString()],
    ...extraHeaders,
  },
);

class _StagingAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;

  const _StagingAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => handler(options);

  @override
  void close({bool force = false}) {}
}
