import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'network_address_policy.dart';

/// Resolves an origin hostname at the point a connection is opened.
typedef NetworkHostAddressResolver =
    Future<List<InternetAddress>> Function(String host);

/// Raised when a network transport would otherwise connect outside its
/// explicitly approved address boundary.
///
/// This deliberately contains only an origin or address classification. It
/// must be safe to surface in redacted diagnostics and never includes headers,
/// request bodies, credentials, or query values.
class NetworkTargetBlockedException implements Exception {
  final String message;

  const NetworkTargetBlockedException(this.message);

  @override
  String toString() => message;
}

/// Creates a Dio client that pins every newly opened connection to the DNS
/// answer it validates at connection time.
///
/// Checking a hostname before calling a normal HTTP client is not sufficient:
/// that client can resolve the hostname again while opening its socket. This
/// factory resolves, classifies, and then connects directly to an approved
/// [InternetAddress]. HTTPS performs TLS over that already-connected socket
/// with the original hostname, preserving both SNI and certificate validation
/// without triggering another DNS lookup.
///
/// Explicit loopback is deliberately opt-in for local sidecars only. A public
/// hostname that later resolves to loopback remains blocked.
Dio createPinnedNetworkDio({
  required NetworkHostAddressResolver hostAddressResolver,
  required bool allowExplicitLoopback,
  BaseOptions? options,
}) {
  final dio = Dio(options);
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => createPinnedNetworkHttpClient(
      hostAddressResolver: hostAddressResolver,
      allowExplicitLoopback: allowExplicitLoopback,
    ),
  );
  return dio;
}

/// Creates the underlying direct-only HTTP client used by [createPinnedNetworkDio].
///
/// Environment proxy settings are intentionally ignored. The network policy
/// validates the actual peer address, and a proxy would make that policy apply
/// to the proxy instead of the requested origin.
HttpClient createPinnedNetworkHttpClient({
  required NetworkHostAddressResolver hostAddressResolver,
  required bool allowExplicitLoopback,
}) {
  final client = HttpClient()
    ..idleTimeout = const Duration(seconds: 3)
    ..findProxy = (_) => 'DIRECT';
  client.connectionFactory = (uri, proxyHost, proxyPort) {
    return _connectToPinnedAddress(
      uri,
      proxyHost: proxyHost,
      proxyPort: proxyPort,
      hostAddressResolver: hostAddressResolver,
      allowExplicitLoopback: allowExplicitLoopback,
    );
  };
  return client;
}

Future<ConnectionTask<Socket>> _connectToPinnedAddress(
  Uri uri, {
  required String? proxyHost,
  required int? proxyPort,
  required NetworkHostAddressResolver hostAddressResolver,
  required bool allowExplicitLoopback,
}) async {
  if (proxyHost != null || proxyPort != null) {
    throw const NetworkTargetBlockedException(
      'Network target blocked: proxy connections are not allowed.',
    );
  }

  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    throw const NetworkTargetBlockedException(
      'Network target blocked: only HTTP and HTTPS connections are allowed.',
    );
  }
  if (uri.userInfo.isNotEmpty) {
    throw const NetworkTargetBlockedException(
      'Network target blocked: URL credentials are not allowed.',
    );
  }

  final host = NetworkAddressPolicy.normalizeHost(uri.host);
  if (host.isEmpty) {
    throw const NetworkTargetBlockedException(
      'Network target blocked: host is required.',
    );
  }
  final loopback = NetworkAddressPolicy.isExplicitLoopbackHost(host);
  if (loopback && !allowExplicitLoopback) {
    throw const NetworkTargetBlockedException(
      'Network target blocked: loopback connections are not allowed.',
    );
  }
  if (!loopback) {
    final blockedReason = NetworkAddressPolicy.publicHostBlockReason(host);
    if (blockedReason != null) {
      throw NetworkTargetBlockedException(
        'Network target blocked: $blockedReason ($host).',
      );
    }
  }

  final List<InternetAddress> addresses;
  try {
    addresses = await hostAddressResolver(host);
  } on SocketException {
    throw NetworkTargetBlockedException(
      'Network target blocked: $host could not be resolved safely.',
    );
  } catch (_) {
    throw NetworkTargetBlockedException(
      'Network target blocked: $host could not be resolved safely.',
    );
  }
  if (addresses.isEmpty) {
    throw NetworkTargetBlockedException(
      'Network target blocked: $host did not resolve to an allowed address.',
    );
  }

  for (final address in addresses) {
    final resolved = NetworkAddressPolicy.normalizeHost(address.address);
    if (loopback) {
      if (!NetworkAddressPolicy.isExplicitLoopbackHost(resolved)) {
        throw const NetworkTargetBlockedException(
          'Network target blocked: loopback origin resolved outside the loopback boundary.',
        );
      }
    } else {
      final blockedReason = NetworkAddressPolicy.publicHostBlockReason(
        resolved,
      );
      if (blockedReason != null) {
        throw NetworkTargetBlockedException(
          'Network target blocked: resolved address $resolved is not allowed ($blockedReason).',
        );
      }
    }
  }

  // Connect to the validated address rather than the hostname. The host name
  // is retained only for TLS SNI/certificate validation below, where
  // SecureSocket.secure is documented not to perform a DNS lookup.
  final connection = await Socket.startConnect(addresses.first, uri.port);
  if (scheme != 'https') return connection;

  return ConnectionTask.fromSocket<Socket>(
    connection.socket.then<Socket>(
      (socket) => SecureSocket.secure(socket, host: uri.host),
    ),
    connection.cancel,
  );
}
