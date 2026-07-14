import 'package:dio/dio.dart';

import 'provider_interface.dart';

/// Categorizes connector failures without retaining raw response text. The
/// resulting value is suitable for the visible health panel and support bundle.
ConnectorHealthErrorCategory classifyConnectorHealthError(Object error) {
  if (error is FormatException) {
    return ConnectorHealthErrorCategory.malformedResponse;
  }
  if (error is DioException) {
    final raw = '${error.message ?? ''} ${error.error ?? ''}'.toLowerCase();
    if (raw.contains('certificate') || raw.contains('ssl')) {
      return ConnectorHealthErrorCategory.certificate;
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => ConnectorHealthErrorCategory.timeout,
      DioExceptionType.connectionError => ConnectorHealthErrorCategory.offline,
      DioExceptionType.badCertificate =>
        ConnectorHealthErrorCategory.certificate,
      DioExceptionType.badResponse => switch (error.response?.statusCode) {
        401 || 403 => ConnectorHealthErrorCategory.authentication,
        429 => ConnectorHealthErrorCategory.rateLimited,
        final status? when status >= 500 => ConnectorHealthErrorCategory.server,
        _ => ConnectorHealthErrorCategory.unknown,
      },
      _ => ConnectorHealthErrorCategory.unknown,
    };
  }
  final raw = error.toString().toLowerCase();
  if (raw.contains('credential') || raw.contains('authentication')) {
    return ConnectorHealthErrorCategory.credentials;
  }
  if (raw.contains('certificate') || raw.contains('ssl')) {
    return ConnectorHealthErrorCategory.certificate;
  }
  return ConnectorHealthErrorCategory.unknown;
}

String connectorHealthRetryAdvice(ConnectorHealthErrorCategory category) {
  return switch (category) {
    ConnectorHealthErrorCategory.none => '',
    ConnectorHealthErrorCategory.credentials ||
    ConnectorHealthErrorCategory.authentication =>
      'Update the Circuit credentials, reconnect, then retry the check.',
    ConnectorHealthErrorCategory.offline =>
      'Check your network or VPN connection, then retry.',
    ConnectorHealthErrorCategory.timeout =>
      'Retry after confirming the network and any required VPN are available.',
    ConnectorHealthErrorCategory.rateLimited =>
      'Wait briefly, then retry. Avoid sending several connection checks at once.',
    ConnectorHealthErrorCategory.server =>
      'Retry later. If this persists, share the redacted support bundle with support.',
    ConnectorHealthErrorCategory.malformedResponse =>
      'Retry once. If it repeats, update the provider or share the redacted support bundle.',
    ConnectorHealthErrorCategory.certificate =>
      'Verify the managed device certificate or contact your network administrator.',
    ConnectorHealthErrorCategory.unknown =>
      'Retry the connection check. If it repeats, share the redacted support bundle.',
  };
}

/// Builds one redacted readiness result around the adapter's token check.
/// Transport and credential ownership remain in the caller.
abstract final class CiscoConnectorHealthReporter {
  static Future<ConnectorHealth> check({
    required bool hasCredentialsOrToken,
    required String endpoint,
    required ProviderProtocol protocol,
    required Future<void> Function() ensureToken,
  }) async {
    final stopwatch = Stopwatch()..start();
    if (!hasCredentialsOrToken) {
      return ConnectorHealth(
        status: ConnectorHealthStatus.credentialsMissing,
        message: 'Circuit credentials are missing.',
        checkedAt: DateTime.now(),
        endpoint: endpoint,
        protocolVersion: protocol.version,
        latency: stopwatch.elapsed,
        errorCategory: ConnectorHealthErrorCategory.credentials,
        retryAdvice:
            'Add valid Circuit credentials in Settings, then run the connection check again.',
      );
    }
    try {
      await ensureToken();
      return ConnectorHealth(
        status: ConnectorHealthStatus.connected,
        message: 'Circuit connector is ready.',
        checkedAt: DateTime.now(),
        endpoint: endpoint,
        protocolVersion: protocol.version,
        latency: stopwatch.elapsed,
      );
    } catch (error) {
      final category = classifyConnectorHealthError(error);
      return ConnectorHealth(
        status: _healthStatusFor(category),
        message: _healthMessageFor(category),
        checkedAt: DateTime.now(),
        endpoint: endpoint,
        protocolVersion: protocol.version,
        latency: stopwatch.elapsed,
        errorCategory: category,
        retryAdvice: connectorHealthRetryAdvice(category),
      );
    }
  }
}

ConnectorHealthStatus _healthStatusFor(ConnectorHealthErrorCategory category) {
  return switch (category) {
    ConnectorHealthErrorCategory.credentials =>
      ConnectorHealthStatus.credentialsMissing,
    ConnectorHealthErrorCategory.authentication =>
      ConnectorHealthStatus.tokenFailed,
    ConnectorHealthErrorCategory.rateLimited ||
    ConnectorHealthErrorCategory.server => ConnectorHealthStatus.degraded,
    _ => ConnectorHealthStatus.requestFailed,
  };
}

String _healthMessageFor(ConnectorHealthErrorCategory category) {
  return switch (category) {
    ConnectorHealthErrorCategory.credentials =>
      'Circuit credentials are missing.',
    ConnectorHealthErrorCategory.authentication =>
      'Circuit authentication failed.',
    ConnectorHealthErrorCategory.offline =>
      'Circuit could not be reached from this network.',
    ConnectorHealthErrorCategory.timeout =>
      'Circuit connection check timed out.',
    ConnectorHealthErrorCategory.rateLimited =>
      'Circuit rate limited the connection check.',
    ConnectorHealthErrorCategory.server =>
      'Circuit service is temporarily unavailable.',
    ConnectorHealthErrorCategory.malformedResponse =>
      'Circuit returned an invalid health response.',
    ConnectorHealthErrorCategory.certificate =>
      'Circuit certificate validation failed.',
    ConnectorHealthErrorCategory.none ||
    ConnectorHealthErrorCategory.unknown => 'Circuit connection check failed.',
  };
}
