import 'package:dio/dio.dart';

/// A bounded, credential-free description of an HTTP failure from Circuit.
///
/// Connection ownership, authentication refresh, and lifecycle emission stay
/// in [CiscoProvider]. This value object only turns an already-rejected Dio
/// request into safe status and body diagnostics, so the same response cannot
/// produce subtly different rate-limit or error messages at separate call
/// sites.
final class CiscoTransportFailure {
  const CiscoTransportFailure({
    required this.statusCode,
    required this.errorMessage,
    required this.retryAfterDetail,
  });

  final int? statusCode;
  final String errorMessage;
  final String? retryAfterDetail;

  bool get isRateLimited => statusCode == 429;

  static Future<CiscoTransportFailure> fromDio(DioException error) async {
    final status = error.response?.statusCode;
    final retryAfterDetail = _retryAfterDetail(error.response?.headers);
    String errorMessage = status == null
        ? 'Circuit API request failed.'
        : 'Circuit API error $status.';
    if (status == 429) {
      errorMessage = retryAfterDetail == null
          ? 'Circuit API rate limit reached (HTTP 429)'
          : 'Circuit API rate limit reached (HTTP 429). $retryAfterDetail';
    }

    return CiscoTransportFailure(
      statusCode: status,
      errorMessage: errorMessage,
      retryAfterDetail: retryAfterDetail,
    );
  }

  static String? _retryAfterDetail(Headers? headers) {
    final value = headers?.value('retry-after')?.trim();
    if (value == null || value.isEmpty) return null;
    final seconds = int.tryParse(value);
    if (seconds != null && seconds >= 0) return 'Retry after ${seconds}s.';
    return 'Retry after $value.';
  }
}
