import 'dart:async';
import 'dart:convert';

import '../agent/providers/cisco_provider.dart';
import '../agent/providers/provider_interface.dart';
import '../core/constants/app_constants.dart';
import '../enums/message_role.dart';
import '../models/chat_message.dart';
import '../models/provider_lifecycle_event.dart';

/// Explicit acknowledgement is preferred, while a missing header remains the
/// documented version-1 compatibility route for existing provider endpoints.
enum ProviderProtocolAcknowledgement { explicit, legacyV1Compatibility }

class ProviderStagingProbeFailure implements Exception {
  final String message;

  const ProviderStagingProbeFailure(this.message);

  @override
  String toString() => message;
}

/// Protected-environment configuration for the provider protocol/streaming
/// acceptance probe. Credentials are deliberately never serialised.
class ProviderStagingProbeConfig {
  static const defaultModel = 'gpt-5-nano';

  final Uri chatBaseUri;
  final String appKey;
  final String model;
  final Duration timeout;
  final String? accessToken;
  final String? clientId;
  final String? clientSecret;

  const ProviderStagingProbeConfig({
    required this.chatBaseUri,
    required this.appKey,
    required this.model,
    this.timeout = const Duration(seconds: 90),
    this.accessToken,
    this.clientId,
    this.clientSecret,
  });

  /// The preferred mode from the Circuit API guide. It keeps short-lived
  /// access tokens out of protected-environment configuration and lets the
  /// adapter refresh the one-hour token for the bounded staging run.
  bool get usesOAuthClientCredentials =>
      clientId != null && clientSecret != null;

  factory ProviderStagingProbeConfig.fromEnvironment(
    Map<String, String> environment,
  ) {
    final endpoint =
        _optionalEnvironment(environment, 'CIRCUIT_STAGING_CHAT_BASE_URL') ??
        AppConstants.ciscoChatBaseUrl;
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.fragment.isNotEmpty) {
      throw const ProviderStagingProbeFailure(
        'CIRCUIT_STAGING_CHAT_BASE_URL must be an HTTPS base URL without credentials, query, or fragment.',
      );
    }
    final model =
        _optionalEnvironment(environment, 'CIRCUIT_STAGING_MODEL') ??
        defaultModel;
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(model)) {
      throw const ProviderStagingProbeFailure(
        'CIRCUIT_STAGING_MODEL may contain only letters, digits, dot, underscore, and hyphen.',
      );
    }
    final timeoutSeconds = int.tryParse(
      environment['CIRCUIT_STAGING_TIMEOUT_SECONDS'] ?? '',
    );
    if (timeoutSeconds != null &&
        (timeoutSeconds < 10 || timeoutSeconds > 240)) {
      throw const ProviderStagingProbeFailure(
        'CIRCUIT_STAGING_TIMEOUT_SECONDS must be between 10 and 240.',
      );
    }
    final accessToken = _optionalEnvironment(
      environment,
      'CIRCUIT_STAGING_ACCESS_TOKEN',
    );
    final clientId = _optionalEnvironment(
      environment,
      'CIRCUIT_STAGING_CLIENT_ID',
    );
    final clientSecret = _optionalEnvironment(
      environment,
      'CIRCUIT_STAGING_CLIENT_SECRET',
    );
    final usesClientCredentials = clientId != null || clientSecret != null;
    if (accessToken != null && usesClientCredentials) {
      throw const ProviderStagingProbeFailure(
        'Configure either CIRCUIT_STAGING_ACCESS_TOKEN or the CIRCUIT_STAGING_CLIENT_ID/CIRCUIT_STAGING_CLIENT_SECRET pair, not both.',
      );
    }
    if (accessToken == null && (clientId == null || clientSecret == null)) {
      throw const ProviderStagingProbeFailure(
        'Configure CIRCUIT_STAGING_ACCESS_TOKEN or both CIRCUIT_STAGING_CLIENT_ID and CIRCUIT_STAGING_CLIENT_SECRET.',
      );
    }

    return ProviderStagingProbeConfig(
      chatBaseUri: uri.replace(path: uri.path.replaceFirst(RegExp(r'/+$'), '')),
      appKey: _requiredEnvironment(environment, 'CIRCUIT_STAGING_APP_KEY'),
      model: model,
      timeout: Duration(seconds: timeoutSeconds ?? 90),
      accessToken: accessToken,
      clientId: clientId,
      clientSecret: clientSecret,
    );
  }

  static String? _optionalEnvironment(
    Map<String, String> environment,
    String key,
  ) {
    final value = environment[key]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static String _requiredEnvironment(
    Map<String, String> environment,
    String key,
  ) {
    final value = environment[key]?.trim();
    if (value == null || value.isEmpty) {
      throw ProviderStagingProbeFailure('$key is required.');
    }
    return value;
  }
}

/// Machine-readable, redacted staging evidence. It intentionally preserves
/// event kinds and counts, never the probe prompt, model response, access
/// token, app key, endpoint path, or provider diagnostic text.
class ProviderStagingProbeResult {
  final int protocolVersion;
  final ProviderProtocolAcknowledgement acknowledgement;
  final List<ProviderLifecycleEventKind> lifecycle;
  final int responseCharacterCount;
  final int elapsedMilliseconds;

  const ProviderStagingProbeResult({
    required this.protocolVersion,
    required this.acknowledgement,
    required this.lifecycle,
    required this.responseCharacterCount,
    required this.elapsedMilliseconds,
  });

  Map<String, Object> toJson() => {
    'schemaVersion': 1,
    'protocolVersion': protocolVersion,
    'protocolAcknowledgement': acknowledgement.name,
    'lifecycle': lifecycle.map((kind) => kind.name).toList(growable: false),
    'responseCharacterCount': responseCharacterCount,
    'elapsedMilliseconds': elapsedMilliseconds,
  };

  String toRedactedJsonLine() => jsonEncode(toJson());
}

/// Runs the real Circuit adapter against protected staging credentials. The
/// fixed probe prompt asks only for a tiny textual response; no workspace,
/// image, tool, or user data crosses the provider boundary.
class ProviderStagingProbe {
  static const _probePrompt =
      'Reply with a short textual confirmation for this connector lifecycle probe.';

  final ProviderStagingProbeConfig config;
  final CiscoProvider Function(ProviderStagingProbeConfig config) _provider;

  ProviderStagingProbe({
    required this.config,
    CiscoProvider Function(ProviderStagingProbeConfig config)? provider,
  }) : _provider = provider ?? _createProvider;

  Future<ProviderStagingProbeResult> run() async {
    final provider = _provider(config);
    try {
      await connectProviderForStaging(provider, config);
      return await inspectProviderStagingStream(
        provider.chat(
          [
            ChatMessage(
              id: 'provider-staging-probe',
              role: MessageRole.user,
              content: _probePrompt,
              timestamp: DateTime.now().toUtc(),
            ),
          ],
          model: config.model,
          tools: const [],
          temperature: 0,
          maxTokens: 32,
        ),
        expectedProtocolVersion: provider.protocol.version,
        timeout: config.timeout,
      );
    } on ProviderStagingProbeFailure {
      rethrow;
    } catch (_) {
      throw const ProviderStagingProbeFailure(
        'The staging provider did not complete a valid protocol and streaming lifecycle.',
      );
    } finally {
      provider.cancelActiveRequest();
    }
  }

  static CiscoProvider _createProvider(ProviderStagingProbeConfig config) =>
      CiscoProvider(
        accessToken: config.accessToken,
        tokenExpiry: config.accessToken == null
            ? null
            : DateTime.now().add(const Duration(minutes: 5)),
        appKey: config.appKey,
        chatBaseUrl: config.chatBaseUri.toString(),
      );
}

/// Configures a real staging provider with the documented OAuth client flow.
/// Static-token mode is already configured in the provider constructor.
Future<void> connectProviderForStaging(
  CiscoProvider provider,
  ProviderStagingProbeConfig config,
) async {
  if (!config.usesOAuthClientCredentials) return;
  await provider.connect({
    'client_id': config.clientId!,
    'client_secret': config.clientSecret!,
    'app_key': config.appKey,
  });
}

/// Checks the lifecycle emitted by the real adapter without retaining model
/// content. This is public so the contract can be fixture-tested without
/// connecting to staging.
Future<ProviderStagingProbeResult> inspectProviderStagingStream(
  Stream<ChatChunk> stream, {
  required int expectedProtocolVersion,
  Duration timeout = const Duration(seconds: 90),
  void Function(String content)? onContent,
}) async {
  final stopwatch = Stopwatch()..start();
  final lifecycle = <ProviderLifecycleEventKind>[];
  var responseCharacterCount = 0;
  var requestSentCount = 0;
  var doneCount = 0;
  var chunkIndex = 0;
  int? connectedIndex;
  int? firstByteIndex;
  int? firstTextIndex;
  int? firstContentIndex;
  int? completionIndex;
  int? negotiatedProtocolVersion;
  ProviderProtocolAcknowledgement? acknowledgement;
  var sawCompletion = false;
  var sawDone = false;

  try {
    await for (final chunk in stream.timeout(timeout)) {
      final currentIndex = chunkIndex++;
      if (sawDone) {
        throw const ProviderStagingProbeFailure(
          'The staging provider emitted data after its terminal completion signal.',
        );
      }
      final kind = chunk.lifecycleKind;
      if (kind != null) {
        lifecycle.add(kind);
        switch (kind) {
          case ProviderLifecycleEventKind.requestSent:
            if (connectedIndex != null) {
              throw const ProviderStagingProbeFailure(
                'The staging provider sent a new request after the stream connected.',
              );
            }
            requestSentCount++;
          case ProviderLifecycleEventKind.connected:
            if (requestSentCount == 0 || connectedIndex != null) {
              throw const ProviderStagingProbeFailure(
                'The staging provider emitted an invalid connection lifecycle.',
              );
            }
            connectedIndex = currentIndex;
          case ProviderLifecycleEventKind.firstByte:
            if (connectedIndex == null || firstByteIndex != null) {
              throw const ProviderStagingProbeFailure(
                'The staging provider emitted an invalid first-byte lifecycle.',
              );
            }
            firstByteIndex = currentIndex;
          case ProviderLifecycleEventKind.firstTextDelta:
            if (firstByteIndex == null || firstTextIndex != null) {
              throw const ProviderStagingProbeFailure(
                'The staging provider emitted an invalid first-text lifecycle.',
              );
            }
            firstTextIndex = currentIndex;
          case ProviderLifecycleEventKind.completed:
            if (firstTextIndex == null ||
                firstContentIndex == null ||
                completionIndex != null) {
              throw const ProviderStagingProbeFailure(
                'The staging provider emitted an invalid completion lifecycle.',
              );
            }
            completionIndex = currentIndex;
            sawCompletion = true;
          default:
            break;
        }
        if (kind == ProviderLifecycleEventKind.connected) {
          final negotiation = _parseNegotiation(chunk.lifecycleDetail);
          negotiatedProtocolVersion ??= negotiation?.$1;
          acknowledgement ??= negotiation?.$2;
        }
      }
      final content = chunk.content;
      if (content != null && content.isNotEmpty) {
        if (firstTextIndex == null || completionIndex != null) {
          throw const ProviderStagingProbeFailure(
            'The staging provider emitted text outside its active streaming lifecycle.',
          );
        }
        firstContentIndex ??= currentIndex;
        onContent?.call(content);
        responseCharacterCount += content.length;
      }
      if (chunk.isDone) {
        if (completionIndex == null || doneCount != 0) {
          throw const ProviderStagingProbeFailure(
            'The staging provider emitted an invalid terminal completion signal.',
          );
        }
        doneCount++;
        sawDone = true;
      }
    }
  } on TimeoutException {
    throw const ProviderStagingProbeFailure(
      'The staging provider exceeded the bounded probe timeout.',
    );
  }

  const requiredLifecycle = {
    ProviderLifecycleEventKind.requestSent,
    ProviderLifecycleEventKind.connected,
    ProviderLifecycleEventKind.firstByte,
    ProviderLifecycleEventKind.firstTextDelta,
    ProviderLifecycleEventKind.completed,
  };
  final missing = requiredLifecycle.where((kind) => !lifecycle.contains(kind));
  if (missing.isNotEmpty ||
      responseCharacterCount == 0 ||
      !sawCompletion ||
      !sawDone) {
    throw const ProviderStagingProbeFailure(
      'The staging provider did not emit the required text streaming lifecycle.',
    );
  }
  if (lifecycle.any(
    (kind) =>
        kind == ProviderLifecycleEventKind.failed ||
        kind == ProviderLifecycleEventKind.cancelled ||
        kind == ProviderLifecycleEventKind.timeout ||
        kind == ProviderLifecycleEventKind.noFirstByte,
  )) {
    throw const ProviderStagingProbeFailure(
      'The staging provider emitted a failing lifecycle event.',
    );
  }
  if (firstByteIndex == null ||
      firstTextIndex == null ||
      firstContentIndex == null ||
      completionIndex == null ||
      connectedIndex == null ||
      connectedIndex >= firstByteIndex ||
      firstByteIndex >= firstTextIndex ||
      firstTextIndex >= firstContentIndex ||
      firstContentIndex >= completionIndex ||
      doneCount != 1) {
    throw const ProviderStagingProbeFailure(
      'The staging provider did not emit one ordered incremental text lifecycle.',
    );
  }
  if (negotiatedProtocolVersion != expectedProtocolVersion ||
      acknowledgement == null) {
    throw const ProviderStagingProbeFailure(
      'The staging provider did not report the expected protocol negotiation.',
    );
  }
  return ProviderStagingProbeResult(
    protocolVersion: negotiatedProtocolVersion!,
    acknowledgement: acknowledgement,
    lifecycle: List.unmodifiable(lifecycle),
    responseCharacterCount: responseCharacterCount,
    elapsedMilliseconds: stopwatch.elapsedMilliseconds,
  );
}

(int, ProviderProtocolAcknowledgement)? _parseNegotiation(String? detail) {
  if (detail == null) return null;
  final match = RegExp(
    r'\bprotocol\s+(\d+)\b',
    caseSensitive: false,
  ).firstMatch(detail);
  final version = int.tryParse(match?.group(1) ?? '');
  if (version == null) return null;
  if (detail.contains('explicit acknowledgement')) {
    return (version, ProviderProtocolAcknowledgement.explicit);
  }
  if (detail.contains('legacy v1 compatibility')) {
    return (version, ProviderProtocolAcknowledgement.legacyV1Compatibility);
  }
  return null;
}
