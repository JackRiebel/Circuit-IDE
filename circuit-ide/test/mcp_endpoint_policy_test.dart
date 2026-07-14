import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/agent/mcp/mcp_config.dart';
import 'package:circuit_ide/agent/mcp/mcp_transport.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'remote MCP DNS rebinding is blocked before a credentialed request',
    () async {
      var resolutionCount = 0;
      var requestCount = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://mcp.example.test/rpc'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestCount++;
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
          name: 'rebind-fixture',
          url: 'https://mcp.example.test/rpc',
        ),
        dio: dio,
        hostAddressResolver: (_) async {
          resolutionCount++;
          return [
            InternetAddress(resolutionCount == 1 ? '8.8.8.8' : '127.0.0.1'),
          ];
        },
      );
      addTearDown(transport.dispose);

      final response = await transport.initialize();

      expect(resolutionCount, 2);
      expect(requestCount, 0);
      expect(response.isError, isTrue);
      expect(response.error?['message'], contains('non-public address'));
    },
  );

  test(
    'default remote MCP transport pins the DNS answer used for its socket',
    () async {
      var resolutionCount = 0;
      final transport = await McpHttpTransport.create(
        const McpServerConfig(
          name: 'pinned-default-transport',
          url: 'https://mcp.example.test/rpc',
        ),
        hostAddressResolver: (_) async {
          resolutionCount++;
          return [
            InternetAddress(resolutionCount < 3 ? '8.8.8.8' : '127.0.0.1'),
          ];
        },
      );
      addTearDown(transport.dispose);

      final response = await transport.initialize();

      // Creation validates once, send validates again, and the connection
      // factory resolves a third time before opening the credentialed socket.
      expect(resolutionCount, 3);
      expect(response.isError, isTrue);
    },
  );

  test(
    'default loopback MCP transport connects directly to its approved peer',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final message = jsonDecode(body) as Map<String, dynamic>;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': message['id'],
            'result': <String, dynamic>{},
          }),
        );
        await request.response.close();
      });

      var resolutionCount = 0;
      final transport = await McpHttpTransport.create(
        McpServerConfig(
          name: 'default-loopback-transport',
          url: 'http://127.0.0.1:${server.port}/mcp',
        ),
        hostAddressResolver: (_) async {
          resolutionCount++;
          return [InternetAddress.loopbackIPv4];
        },
      );
      addTearDown(transport.dispose);

      final response = await transport.initialize();

      expect(response.isError, isFalse);
      expect(response.id, 1);
      expect(resolutionCount, 3);
    },
  );

  test(
    'remote MCP DNS rebinding blocks hexadecimal IPv4-mapped loopback before a credentialed request',
    () async {
      var resolutionCount = 0;
      var requestCount = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://mcp.example.test/rpc'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestCount++;
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
          name: 'mapped-rebind-fixture',
          url: 'https://mcp.example.test/rpc',
        ),
        dio: dio,
        hostAddressResolver: (_) async {
          resolutionCount++;
          return [
            InternetAddress(resolutionCount == 1 ? '8.8.8.8' : '::ffff:7f00:1'),
          ];
        },
      );
      addTearDown(transport.dispose);

      final response = await transport.initialize();

      expect(resolutionCount, 2);
      expect(requestCount, 0);
      expect(response.isError, isTrue);
      expect(response.error?['message'], contains('non-public address'));
    },
  );

  test(
    'remote MCP endpoints require HTTPS before resolving or loading them',
    () async {
      var resolutionCount = 0;

      await expectLater(
        McpHttpTransport.create(
          const McpServerConfig(
            name: 'insecure-remote',
            url: 'http://mcp.example.test/rpc',
          ),
          hostAddressResolver: (_) async {
            resolutionCount++;
            return [InternetAddress('8.8.8.8')];
          },
        ),
        throwsA(isA<McpEndpointPolicyException>()),
      );

      expect(resolutionCount, 0);
    },
  );

  test('explicit loopback MCP sidecars remain supported', () async {
    var resolutionCount = 0;
    var requestCount = 0;
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost:5001/mcp'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestCount++;
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
        name: 'local-sidecar',
        url: 'http://localhost:5001/mcp',
      ),
      dio: dio,
      hostAddressResolver: (_) async {
        resolutionCount++;
        return [InternetAddress('127.0.0.1')];
      },
    );
    addTearDown(transport.dispose);

    final response = await transport.initialize();

    expect(response.isError, isFalse);
    expect(requestCount, 1);
    expect(resolutionCount, 2);
  });

  test('a loopback MCP hostname cannot resolve outside loopback', () async {
    await expectLater(
      McpHttpTransport.create(
        const McpServerConfig(
          name: 'misdirected-sidecar',
          url: 'http://localhost:5001/mcp',
        ),
        hostAddressResolver: (_) async => [InternetAddress('8.8.8.8')],
      ),
      throwsA(isA<McpEndpointPolicyException>()),
    );
  });

  test(
    'MCP endpoints refuse query strings and fragments before resolution',
    () async {
      for (final endpoint in const [
        'https://mcp.example.test/rpc?access_token=query-secret',
        'https://mcp.example.test/rpc#private-fragment',
      ]) {
        var resolutionCount = 0;

        await expectLater(
          McpHttpTransport.create(
            McpServerConfig(name: 'query-fixture', url: endpoint),
            hostAddressResolver: (_) async {
              resolutionCount++;
              return [InternetAddress('8.8.8.8')];
            },
          ),
          throwsA(isA<McpEndpointPolicyException>()),
        );

        expect(resolutionCount, 0);
      }
    },
  );

  test(
    'MCP transport redacts unexpected credentialed HTTP diagnostics',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://mcp.example.test/rpc'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                message: 'connector diagnostic included mcp-response-secret',
                error: StateError('mcp-response-secret'),
              ),
            );
          },
        ),
      );
      final transport = await McpHttpTransport.create(
        const McpServerConfig(
          name: 'connector-name-secret',
          url: 'https://mcp.example.test/rpc',
        ),
        dio: dio,
        hostAddressResolver: (_) async => [InternetAddress('8.8.8.8')],
      );
      addTearDown(transport.dispose);

      final response = await transport.initialize();
      final message = response.error?['message'] as String?;

      expect(response.isError, isTrue);
      expect(message, 'MCP request failed.');
      expect(message, isNot(contains('mcp-response-secret')));
      expect(message, isNot(contains('connector-name-secret')));
    },
  );
}
