import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/utils/logger.dart';
import '../../models/provider_lifecycle_event.dart';
import 'cisco_response_parser.dart';
import 'provider_interface.dart';

/// Stateless decoding and diagnostic helpers for an already-open Circuit
/// response. The provider retains connection, token, retry, and cancellation
/// ownership; this module never starts a request or owns a credential.
abstract final class CiscoStreamSupport {
  static bool looksLikeSsePayload(String text) {
    return text.startsWith('data:') ||
        text.startsWith('event:') ||
        text.startsWith('id:') ||
        text.startsWith(':');
  }

  static bool isJsonContentType(String? contentType) {
    if (contentType == null) return false;
    return contentType.contains('application/json') &&
        !contentType.contains('text/event-stream');
  }

  static bool isCancellation(Object error, CancelToken cancelToken) {
    if (cancelToken.isCancelled) return true;
    if (error is DioException && CancelToken.isCancel(error)) return true;
    return error.toString().toLowerCase().contains('cancel');
  }

  static Stream<String> decodeUtf8Stream(
    Stream<Uint8List> byteStream, {
    required Duration? idleTimeout,
    required void Function() onFirstByte,
  }) {
    return _withBodyIdleTimeout(byteStream, idleTimeout: idleTimeout)
        .map<List<int>>((bytes) {
          if (bytes.isNotEmpty) onFirstByte();
          return bytes;
        })
        .transform(const Utf8Decoder());
  }

  static Stream<Uint8List> _withBodyIdleTimeout(
    Stream<Uint8List> byteStream, {
    required Duration? idleTimeout,
  }) {
    if (idleTimeout == null || idleTimeout <= Duration.zero) return byteStream;
    return byteStream.timeout(
      idleTimeout,
      onTimeout: (sink) {
        sink.addError(
          TimeoutException(
            'no response body data arrived for ${idleTimeout.inMilliseconds}ms',
            idleTimeout,
          ),
        );
      },
    );
  }

  static bool isMalformedBytes(Object error) => error is FormatException;

  static bool isTimeoutError(Object error) {
    return error is TimeoutException ||
        (error is DioException && isTimeout(error));
  }

  static bool isTimeout(DioException error) {
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout;
  }

  static String timeoutDetail(Object error) {
    if (error is TimeoutException) return 'response stream stalled.';
    if (error is DioException) return 'provider transport timed out.';
    return 'provider response timed out.';
  }

  static String cleanErrorMessage(Object error) {
    if (error is TimeoutException) return 'provider response timed out.';
    if (error is DioException) {
      if (isTimeout(error)) return 'provider transport timed out.';
      final status = error.response?.statusCode;
      return status == null
          ? 'provider transport request failed.'
          : 'provider returned HTTP $status.';
    }
    if (error is FormatException) return 'provider returned malformed data.';
    return 'provider request failed.';
  }

  static Stream<ChatChunk> parseJsonFallbackWithDiagnostics(
    String body,
  ) async* {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      Logger.error('Failed to parse Circuit API response as JSON.');
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

  static Stream<ChatChunk> diagnoseSseOutput({
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

  /// Provider SSE error payloads are untrusted response content. Preserve the
  /// fact that the stream failed, but never copy a server diagnostic into a
  /// durable Studio lifecycle event where it could expose credentials or
  /// customer data reflected by an upstream service.
  static String sseErrorEventMessage(String payload) =>
      'provider reported an SSE error.';
}
