import 'package:circuit_ide/agent/tools/web_tools.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebTools', () {
    test('web_fetch blocks unsafe network targets before fetching', () async {
      final tools = WebTools();
      final blockedUrls = [
        'file:///etc/passwd',
        'ftp://example.com/file.txt',
        'http://user:pass@example.com',
        'http://localhost:3000',
        'http://localhost.localdomain/status',
        'http://service.local/status',
        'http://internal-service/health',
        'http://127.0.0.1:8000/health',
        'http://127.1/status',
        'http://0177.0.0.1/status',
        'http://0x7f.0.0.1/status',
        'http://0.0.0.0:8080',
        'http://10.1.2.3/status',
        'http://172.16.0.10/status',
        'http://172.31.255.255/status',
        'http://192.168.1.10/status',
        'http://169.254.169.254/latest/meta-data',
        'http://224.0.0.1/status',
        'http://[::1]/status',
        'http://[fe80::1]/status',
        'http://[fd00::1]/status',
      ];

      for (final url in blockedUrls) {
        final result = await tools.execute('web_fetch', {'url': url});

        expect(
          result,
          startsWith('Error: Network target blocked:'),
          reason: url,
        );
      }
    });

    test(
      'web_fetch reports invalid and missing URLs without fetching',
      () async {
        final tools = WebTools();

        expect(
          await tools.execute('web_fetch', const {}),
          'Error: url is required',
        );
        expect(
          await tools.execute('web_fetch', {'url': 'not a url'}),
          'Error: Invalid URL: not a url',
        );
      },
    );

    test('web_fetch blocks redirects to unsafe network targets', () async {
      var requests = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests += 1;
            handler.resolve(
              Response<String>(
                requestOptions: options,
                statusCode: 302,
                headers: Headers.fromMap({
                  'location': ['http://127.0.0.1:8000/latest/meta-data'],
                }),
              ),
            );
          },
        ),
      );
      final tools = WebTools(dio: dio);

      final result = await tools.execute('web_fetch', {
        'url': 'https://example.com/redirect',
      }, allowNetwork: true);

      expect(result, startsWith('Error: Network target blocked:'));
      expect(result, contains('loopback IPv4 addresses are not allowed'));
      expect(requests, 1);
    });

    test(
      'network tools require explicit review before external access',
      () async {
        final tools = WebTools();

        expect(
          await tools.execute('web_fetch', {'url': 'https://example.com'}),
          'Error: Network tool requires review before fetching external URLs',
        );
        expect(
          await tools.execute('web_search', {'query': 'circuit code'}),
          'Error: Network tool requires review before searching the web',
        );
      },
    );

    test(
      'web_search blocks internal network targets embedded in queries',
      () async {
        final tools = WebTools();
        final blockedQueries = [
          'site:localhost.localdomain health check',
          'url:http://service.local/status',
          'debug http://127.0.0.1:3000/login',
          'metadata 169.254.169.254 latest user-data',
          'ipv6 http://[::1]/status',
        ];

        for (final query in blockedQueries) {
          final result = await tools.execute('web_search', {
            'query': query,
          }, allowNetwork: true);

          expect(
            result,
            startsWith('Error: Network search target blocked:'),
            reason: query,
          );
        }
      },
    );

    test(
      'web_search reports timeout diagnostics without raw exceptions',
      () async {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionTimeout,
                  message: 'simulated timeout',
                ),
              );
            },
          ),
        );
        final tools = WebTools(dio: dio);

        final result = await tools.execute('web_search', {
          'query': 'circuit code',
        }, allowNetwork: true);

        expect(result, 'Error: Search connection timed out');
        expect(result, isNot(contains('DioException')));
      },
    );
  });
}
