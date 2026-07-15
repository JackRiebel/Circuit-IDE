import 'package:circuit_ide/agent/providers/cisco_token_authenticator.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Cisco token authenticator uses a valid seeded token and clears it safely',
    () async {
      final authenticator = CiscoTokenAuthenticator(
        Dio(),
        accessToken: 'seeded-token',
        tokenExpiry: DateTime.now().add(const Duration(minutes: 10)),
        appKey: 'app-key',
      );

      expect(authenticator.hasAccessToken, isTrue);
      expect(await authenticator.getToken(), 'seeded-token');

      authenticator.clearAccessToken();
      expect(authenticator.hasAccessToken, isFalse);
      await expectLater(authenticator.getToken(), throwsA(isA<StateError>()));
    },
  );

  test(
    'Cisco token authenticator validates credentials before retaining them',
    () {
      final authenticator = CiscoTokenAuthenticator(Dio());

      expect(
        () => authenticator.configure(const {'client_id': 'client'}),
        throwsA(isA<ArgumentError>()),
      );
      expect(authenticator.hasCredentials, isFalse);

      authenticator.configure(const {
        'client_id': 'client',
        'client_secret': 'secret',
        'app_key': 'app-key',
      });
      expect(authenticator.hasCredentials, isTrue);
      expect(authenticator.appKey, 'app-key');
    },
  );

  test(
    'Cisco token refresh never reflects a credentialed transport error',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                message: 'oauth-response-secret',
                error: StateError('oauth-response-secret'),
              ),
            );
          },
        ),
      );
      final authenticator =
          CiscoTokenAuthenticator(dio, retryDelay: Duration.zero)
            ..configure(const {
              'client_id': 'client-id',
              'client_secret': 'client-secret',
              'app_key': 'app-key',
            });

      Object? failure;
      try {
        await authenticator.refreshToken();
      } catch (error) {
        failure = error;
      }

      expect(failure, isA<StateError>());
      final detail = failure.toString();
      expect(
        detail,
        contains('OAuth token refresh failed after bounded retries'),
      );
      expect(detail, isNot(contains('oauth-response-secret')));
      expect(detail, isNot(contains('client-secret')));
      expect(authenticator.hasAccessToken, isFalse);
    },
  );
}
