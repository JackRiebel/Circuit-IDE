import 'package:circuit_ide/agent/providers/cisco_connector_health.dart';
import 'package:circuit_ide/agent/providers/provider_interface.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'connector health reports missing credentials without a token request',
    () async {
      var requestedToken = false;
      final health = await CiscoConnectorHealthReporter.check(
        hasCredentialsOrToken: false,
        endpoint: 'https://connector.example.test',
        protocol: const ProviderProtocol(),
        ensureToken: () async {
          requestedToken = true;
        },
      );

      expect(requestedToken, isFalse);
      expect(health.status, ConnectorHealthStatus.credentialsMissing);
      expect(health.errorCategory, ConnectorHealthErrorCategory.credentials);
      expect(health.retryAdvice, contains('Add valid Circuit credentials'));
    },
  );

  test(
    'connector health keeps rate-limited details redacted and actionable',
    () async {
      final health = await CiscoConnectorHealthReporter.check(
        hasCredentialsOrToken: true,
        endpoint: 'https://connector.example.test',
        protocol: const ProviderProtocol(),
        ensureToken: () async {
          throw DioException(
            requestOptions: RequestOptions(
              path: 'https://connector.example.test',
            ),
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: RequestOptions(
                path: 'https://connector.example.test',
              ),
              statusCode: 429,
            ),
          );
        },
      );

      expect(health.status, ConnectorHealthStatus.degraded);
      expect(health.errorCategory, ConnectorHealthErrorCategory.rateLimited);
      expect(health.message, 'Circuit rate limited the connection check.');
      expect(health.retryAdvice, startsWith('Wait briefly'));
    },
  );
}
