import 'dart:io';

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
        'http://999.0.0.1/status',
        'http://10.1.2.3/status',
        'http://100.64.0.1/status',
        'http://172.16.0.10/status',
        'http://172.31.255.255/status',
        'http://192.168.1.10/status',
        'http://192.0.0.1/status',
        'http://192.0.2.1/status',
        'http://198.18.0.1/status',
        'http://198.51.100.1/status',
        'http://203.0.113.1/status',
        'http://169.254.169.254/latest/meta-data',
        'http://224.0.0.1/status',
        'http://[::1]/status',
        'http://[::ffff:7f00:1]/status',
        'http://[fe80::1]/status',
        'http://[fd00::1]/status',
        'http://[2001:db8::1]/status',
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
          'Error: Invalid URL',
        );
      },
    );

    test('web_fetch redacts query values and raw transport errors', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                message:
                    'transport refused https://example.com/secured?access_token=provider-secret',
              ),
            );
          },
        ),
      );
      final tools = WebTools(
        dio: dio,
        hostAddressResolver: (_) async => [InternetAddress('93.184.216.34')],
      );

      final result = await tools.execute('web_fetch', {
        'url': 'https://example.com/secured?access_token=request-secret#retry',
      }, allowNetwork: true);

      expect(
        result,
        'Error fetching https://example.com/secured: request failed',
      );
      expect(result, isNot(contains('access_token')));
      expect(result, isNot(contains('request-secret')));
      expect(result, isNot(contains('provider-secret')));
    });

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
      'web_fetch pins the DNS answer used when opening a connection',
      () async {
        var resolutionCount = 0;
        final tools = WebTools(
          hostAddressResolver: (_) async {
            resolutionCount++;
            return [
              InternetAddress(
                resolutionCount == 1 ? '93.184.216.34' : '127.0.0.1',
              ),
            ];
          },
        );

        final result = await tools.execute('web_fetch', {
          'url': 'https://rebind.example.test/report',
        }, allowNetwork: true);

        // The first lookup is the preflight policy guard. A second lookup is
        // performed by the pinned connection factory, which rejects the
        // rebinding answer before any socket can be opened.
        expect(resolutionCount, 2);
        expect(
          result,
          'Error fetching https://rebind.example.test/report: request failed',
        );
      },
    );

    test('web_fetch appends a citation-safe source and checked date', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<String>(
                requestOptions: options,
                statusCode: 200,
                data: 'Primary source body',
                headers: Headers.fromMap({
                  'content-type': ['text/plain'],
                }),
              ),
            );
          },
        ),
      );
      final tools = WebTools(
        dio: dio,
        hostAddressResolver: (_) async => [InternetAddress('93.184.216.34')],
      );

      final result = await tools.execute('web_fetch', {
        'url': 'https://example.com/report?tracking=private#summary',
      }, allowNetwork: true);

      expect(result, contains('Primary source body'));
      expect(result, contains('Source: https://example.com/report'));
      expect(result, isNot(contains('tracking=private')));
      expect(result, matches(RegExp(r'Checked: \d{4}-\d{2}-\d{2}')));
    });

    test(
      'web_fetch sanitizes reflected source URLs in fetched content',
      () async {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  headers: Headers.fromMap({
                    'content-type': ['text/plain'],
                  }),
                  data:
                      'Canonical link: https://example.com/report?session_token=reflected-secret#detail',
                ),
              );
            },
          ),
        );
        final tools = WebTools(
          dio: dio,
          hostAddressResolver: (_) async => [InternetAddress('93.184.216.34')],
        );

        final result = await tools.execute('web_fetch', {
          'url': 'https://example.com/report?session_token=request-secret',
        }, allowNetwork: true);

        expect(result, contains('Canonical link: https://example.com/report'));
        expect(result, isNot(contains('session_token')));
        expect(result, isNot(contains('reflected-secret')));
        expect(result, isNot(contains('request-secret')));
      },
    );

    test('web_fetch cites the final validated redirect target', () async {
      var requests = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests += 1;
            if (requests == 1) {
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 302,
                  headers: Headers.fromMap({
                    'location': [
                      'https://evidence.example.test/final?tracking=private#claim',
                    ],
                  }),
                ),
              );
              return;
            }
            handler.resolve(
              Response<String>(
                requestOptions: options,
                statusCode: 200,
                data: 'Canonical evidence',
                headers: Headers.fromMap({
                  'content-type': ['text/plain'],
                }),
              ),
            );
          },
        ),
      );
      final tools = WebTools(
        dio: dio,
        hostAddressResolver: (_) async => [InternetAddress('93.184.216.34')],
      );

      final result = await tools.execute('web_fetch', {
        'url': 'https://search.example.test/result?query=private',
      }, allowNetwork: true);

      expect(requests, 2);
      expect(result, contains('Canonical evidence'));
      expect(result, contains('Source: https://evidence.example.test/final'));
      expect(result, isNot(contains('search.example.test/result')));
      expect(result, isNot(contains('tracking=private')));
    });

    test('web_fetch rejects DNS rebinding before every redirect hop', () async {
      var requests = 0;
      final resolvedHosts = <String>[];
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
                  'location': ['https://rebound.example.test/private'],
                }),
              ),
            );
          },
        ),
      );
      final tools = WebTools(
        dio: dio,
        hostAddressResolver: (host) async {
          resolvedHosts.add(host);
          return [
            InternetAddress(
              host == 'rebound.example.test' ? '127.0.0.1' : '93.184.216.34',
            ),
          ];
        },
      );

      final result = await tools.execute('web_fetch', {
        'url': 'https://public.example.test/start',
      }, allowNetwork: true);

      expect(result, startsWith('Error: Network target blocked:'));
      expect(result, contains('resolved address 127.0.0.1'));
      expect(resolvedHosts, ['public.example.test', 'rebound.example.test']);
      expect(requests, 1);
    });

    test(
      'web_fetch blocks hexadecimal IPv4-mapped loopback DNS answers before dispatch',
      () async {
        var requests = 0;
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests += 1;
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: 'This request must not be sent.',
                ),
              );
            },
          ),
        );
        final tools = WebTools(
          dio: dio,
          hostAddressResolver: (_) async => [InternetAddress('::ffff:7f00:1')],
        );

        final result = await tools.execute('web_fetch', {
          'url': 'https://public.example.test/evidence',
        }, allowNetwork: true);

        expect(result, startsWith('Error: Network target blocked:'));
        expect(result, contains('loopback IPv4 addresses are not allowed'));
        expect(requests, 0);
      },
    );

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
        final tools = WebTools(
          dio: dio,
          hostAddressResolver: (_) async => [InternetAddress('93.184.216.34')],
        );

        final result = await tools.execute('web_search', {
          'query': 'circuit code',
        }, allowNetwork: true);

        expect(result, 'Error: Search connection timed out');
        expect(result, isNot(contains('DioException')));
      },
    );

    test('web_search redacts raw transport diagnostics', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                message:
                    'search refused q=customer-private-question&token=provider-secret',
              ),
            );
          },
        ),
      );
      final tools = WebTools(
        dio: dio,
        hostAddressResolver: (_) async => [InternetAddress('93.184.216.34')],
      );

      final result = await tools.execute('web_search', {
        'query': 'Customer private question',
      }, allowNetwork: true);

      expect(result, 'Error searching: request failed');
      expect(result, isNot(contains('customer-private-question')));
      expect(result, isNot(contains('provider-secret')));
    });

    test('web_search uses the guarded transport for public results', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.followRedirects, isFalse);
            expect(options.maxRedirects, 0);
            expect(options.headers['User-Agent'], contains('Mozilla/5.0'));
            handler.resolve(
              Response<String>(
                requestOptions: options,
                statusCode: 200,
                data: '''
<a class="result__a">Circuit source</a>
<a class="result__url">https://example.com/source</a>
<a class="result__snippet">Validated result.</a>
''',
              ),
            );
          },
        ),
      );
      final resolvedHosts = <String>[];
      final tools = WebTools(
        dio: dio,
        hostAddressResolver: (host) async {
          resolvedHosts.add(host);
          return [InternetAddress('93.184.216.34')];
        },
      );

      final result = await tools.execute('web_search', {
        'query': 'Circuit source',
      }, allowNetwork: true);

      expect(resolvedHosts, ['html.duckduckgo.com']);
      expect(result, contains('1. Circuit source'));
      expect(result, contains('https://example.com/source'));
    });

    test('web_search exposes only canonical safe result candidates', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<String>(
                requestOptions: options,
                statusCode: 200,
                data: '''
<a class="result__a">Canonical public record</a>
<a class="result__url">https://research.example.test/report?campaign=private#summary</a>
<a class="result__snippet">Public source candidate.</a>
<a class="result__a">Unsafe local record</a>
<a class="result__url">http://localhost/private</a>
<a class="result__snippet">Must never reach research provenance.</a>
''',
              ),
            );
          },
        ),
      );
      final tools = WebTools(
        dio: dio,
        hostAddressResolver: (_) async => [InternetAddress('93.184.216.34')],
      );

      final result = await tools.execute('web_search', {
        'query': 'Canonical public record',
      }, allowNetwork: true);

      expect(result, contains('https://research.example.test/report'));
      expect(result, isNot(contains('campaign=private')));
      expect(result, isNot(contains('Unsafe local record')));
      expect(result, isNot(contains('localhost/private')));
    });

    test('web_search blocks redirects to a private network target', () async {
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
                  'location': ['http://127.0.0.1:8080/private'],
                }),
              ),
            );
          },
        ),
      );
      final resolvedHosts = <String>[];
      final tools = WebTools(
        dio: dio,
        hostAddressResolver: (host) async {
          resolvedHosts.add(host);
          return [InternetAddress('93.184.216.34')];
        },
      );

      final result = await tools.execute('web_search', {
        'query': 'Circuit source',
      }, allowNetwork: true);

      expect(result, startsWith('Error: Network target blocked:'));
      expect(result, contains('loopback IPv4 addresses are not allowed'));
      expect(resolvedHosts, ['html.duckduckgo.com']);
      expect(requests, 1);
    });

    test(
      'web_search blocks rebinding of its configured search origin',
      () async {
        var requests = 0;
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests += 1;
              handler.resolve(
                Response<String>(requestOptions: options, statusCode: 200),
              );
            },
          ),
        );
        final tools = WebTools(
          dio: dio,
          hostAddressResolver: (_) async => [InternetAddress('127.0.0.1')],
        );

        final result = await tools.execute('web_search', {
          'query': 'Circuit source',
        }, allowNetwork: true);

        expect(result, startsWith('Error: Network target blocked:'));
        expect(result, contains('resolved address 127.0.0.1'));
        expect(requests, 0);
      },
    );
  });
}
