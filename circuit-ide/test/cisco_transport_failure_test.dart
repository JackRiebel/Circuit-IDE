import 'dart:convert';
import 'dart:typed_data';

import 'package:circuit_ide/agent/providers/cisco_transport_failure.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DioException responseFailure({
    required int statusCode,
    required String body,
    Map<String, List<String>> headers = const {},
  }) {
    final options = RequestOptions(path: 'https://connector.example.test/chat');
    return DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<ResponseBody>(
        requestOptions: options,
        statusCode: statusCode,
        headers: Headers.fromMap(headers),
        data: ResponseBody(
          Stream.value(Uint8List.fromList(utf8.encode(body))),
          statusCode,
        ),
      ),
    );
  }

  test(
    'normalizes a JSON rate limit without retaining response content',
    () async {
      final failure = await CiscoTransportFailure.fromDio(
        responseFailure(
          statusCode: 429,
          body: jsonEncode({
            'error': {'message': 'provider-response-secret'},
          }),
          headers: {
            'retry-after': ['17'],
          },
        ),
      );

      expect(failure.statusCode, 429);
      expect(failure.isRateLimited, isTrue);
      expect(failure.retryAfterDetail, 'Retry after 17s.');
      expect(failure.errorMessage, isNot(contains('provider-response-secret')));
      expect(failure.errorMessage, contains('Retry after 17s.'));
    },
  );

  test('does not retain a non-JSON error response diagnostic', () async {
    final failure = await CiscoTransportFailure.fromDio(
      responseFailure(statusCode: 503, body: 'provider-response-secret' * 30),
    );

    expect(failure.statusCode, 503);
    expect(failure.isRateLimited, isFalse);
    expect(failure.errorMessage, 'Circuit API error 503.');
    expect(failure.errorMessage, isNot(contains('provider-response-secret')));
  });
}
