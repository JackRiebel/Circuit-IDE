import 'dart:io';

import 'package:circuit_ide/agent/mcp/mcp_config.dart';
import 'package:circuit_ide/agent/mcp/mcp_transport.dart';
import 'package:circuit_ide/agent/tools/github_tools.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GitHub API transport never follows a credentialed redirect', () async {
    var requests = 0;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.github.com'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests += 1;
          expect(options.followRedirects, isFalse);
          expect(options.maxRedirects, 0);
          expect(options.headers['Authorization'], 'Bearer test-token');
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: const {
                'login': 'circuit-test',
                'name': 'Circuit Test',
                'email': null,
                'public_repos': 1,
                'followers': 0,
              },
            ),
          );
        },
      ),
    );
    final tools = GitHubTools(dio: dio)..configure(token: 'test-token');

    final result = await tools.execute('github_whoami', const {});

    expect(requests, 1);
    expect(result, contains('Authenticated as: circuit-test'));
  });

  test(
    'default GitHub transport blocks a private DNS answer before its token-bearing request',
    () async {
      var resolutionCount = 0;
      final tools = GitHubTools(
        hostAddressResolver: (_) async {
          resolutionCount++;
          return [InternetAddress.loopbackIPv4];
        },
      )..configure(token: 'test-token');

      final result = await tools.execute('github_whoami', const {});

      expect(resolutionCount, 1);
      expect(result, isNot(contains('Authenticated as:')));
    },
  );

  test('GitHub tools never reflect an unexpected credentialed error', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.github.com'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          throw StateError(
            'connector diagnostic included provider-response-secret',
          );
        },
      ),
    );
    final tools = GitHubTools(dio: dio)..configure(token: 'test-token');

    final result = await tools.execute('github_whoami', const {});

    expect(result, 'Error: GitHub request failed.');
    expect(result, isNot(contains('provider-response-secret')));
    expect(result, isNot(contains('test-token')));
  });

  test('GitHub tools do not reflect unregistered tool names', () async {
    final tools = GitHubTools()..configure(token: 'test-token');

    final result = await tools.execute(
      'github_unregistered_operation',
      const {},
    );

    expect(result, 'Error: Unknown GitHub tool.');
    expect(result, isNot(contains('github_unregistered_operation')));
  });

  test(
    'remote MCP HTTP transport never follows a credentialed redirect',
    () async {
      var requests = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://mcp.example.test/rpc'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests += 1;
            expect(options.followRedirects, isFalse);
            expect(options.maxRedirects, 0);
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {'jsonrpc': '2.0', 'id': 1, 'result': {}},
              ),
            );
          },
        ),
      );
      final transport = await McpHttpTransport.create(
        const McpServerConfig(
          name: 'test',
          url: 'https://mcp.example.test/rpc',
        ),
        dio: dio,
        hostAddressResolver: (_) async => [InternetAddress('8.8.8.8')],
      );
      addTearDown(transport.dispose);

      final response = await transport.initialize();

      expect(requests, 1);
      expect(response.isError, isFalse);
      expect(response.id, 1);
    },
  );
}
