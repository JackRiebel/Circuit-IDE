import 'dart:io';

import 'package:dio/dio.dart';

import '../security/pinned_network_http_client.dart';

/// Resolver injection is limited to the provider transport boundary, keeping
/// deterministic DNS-policy tests out of the streaming/runtime implementation.
typedef CiscoProviderHostAddressResolver = NetworkHostAddressResolver;

/// Builds the production Circuit provider client.
///
/// The client pins each newly opened connection to the address it validates at
/// socket-open time. Explicit loopback is supported for deliberate local
/// fixture/development endpoints only; public origins still cannot rebind into
/// a private network target.
Dio createCiscoProviderDio({
  CiscoProviderHostAddressResolver? hostAddressResolver,
}) {
  return createPinnedNetworkDio(
    hostAddressResolver: hostAddressResolver ?? InternetAddress.lookup,
    allowExplicitLoopback: true,
    options: BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 4),
    ),
  );
}
