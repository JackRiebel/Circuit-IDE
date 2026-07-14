import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';

/// Holds the short-lived Circuit OAuth state separately from request streaming.
/// Every credential-bearing request disables redirects so a token can never be
/// forwarded to a different origin by transport defaults.
class CiscoTokenAuthenticator {
  static const _maxRetries = 3;
  static const _baseRetryDelay = Duration(seconds: 1);

  final Dio _dio;
  final Duration _retryDelay;
  String? _clientId;
  String? _clientSecret;
  String? _appKey;
  String? _accessToken;
  DateTime? _tokenExpiry;

  CiscoTokenAuthenticator(
    this._dio, {
    String? accessToken,
    DateTime? tokenExpiry,
    String? appKey,
    Duration retryDelay = _baseRetryDelay,
  }) : _accessToken = accessToken,
       _tokenExpiry = tokenExpiry,
       _appKey = appKey,
       _retryDelay = retryDelay;

  String? get appKey => _appKey;
  bool get hasCredentials =>
      _clientId != null && _clientSecret != null && _appKey != null;
  bool get hasAccessToken => _accessToken != null;

  void configure(Map<String, String> credentials) {
    final clientId = credentials['client_id'];
    final clientSecret = credentials['client_secret'];
    final appKey = credentials['app_key'];
    if (clientId == null || clientSecret == null || appKey == null) {
      throw ArgumentError('Missing Circuit credentials');
    }
    _clientId = clientId;
    _clientSecret = clientSecret;
    _appKey = appKey;
  }

  void clearAccessToken() {
    _accessToken = null;
    _tokenExpiry = null;
  }

  Future<void> refreshToken() async {
    if (!hasCredentials) {
      throw StateError(
        'Circuit credentials are missing. Reconnect Circuit Company AI before refreshing the token.',
      );
    }
    final credentials = base64Encode(utf8.encode('$_clientId:$_clientSecret'));
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        final response = await _dio.post(
          AppConstants.ciscoTokenUrl,
          data: 'grant_type=client_credentials',
          options: Options(
            headers: {
              'Authorization': 'Basic $credentials',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            followRedirects: false,
            maxRedirects: 0,
          ),
        );
        final data = response.data as Map<String, dynamic>;
        _accessToken = data['access_token'] as String;
        final expiresIn = data['expires_in'] as int;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 300));
        Logger.info(
          'OAuth token refreshed, expires in ${expiresIn}s',
          'CiscoTokenAuthenticator',
        );
        return;
      } catch (_) {
        if (attempt < _maxRetries - 1) {
          final delay = _retryDelay * (1 << attempt);
          Logger.warning(
            'Token refresh failed, retrying in ${delay.inSeconds}s...',
            'CiscoTokenAuthenticator',
          );
          await Future<void>.delayed(delay);
        }
      }
    }
    throw StateError(
      'Circuit OAuth token refresh failed after bounded retries. Reconnect Circuit Company AI before retrying.',
    );
  }

  Future<String> getToken() async {
    if (_accessToken == null ||
        _tokenExpiry == null ||
        DateTime.now().isAfter(_tokenExpiry!)) {
      if (!hasCredentials) {
        throw StateError(
          'Circuit credentials are missing. Connect Circuit Company AI before sending a request.',
        );
      }
      await refreshToken();
    }
    return _accessToken!;
  }
}
