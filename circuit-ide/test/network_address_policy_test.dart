import 'package:circuit_ide/agent/security/network_address_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects IPv6 spellings that can route through IPv4 translation', () {
    final blocked = <String, String>{
      // Deprecated IPv4-compatible forms must not bypass an IPv4 loopback or
      // private-range check. They are deliberately not sidecar aliases.
      '::127.0.0.1': 'loopback IPv4 addresses are not allowed',
      '::192.168.1.8': 'private IPv4 addresses are not allowed',
      '::8.8.8.8': 'IPv4-compatible IPv6 addresses are not allowed',
      // These special-purpose prefixes can tunnel or translate to an IPv4
      // peer, so an outbound product request must not use them at all.
      '2002:7f00:1::': '6to4 IPv6 addresses are not allowed',
      '2001:0:7f00:1::': 'Teredo IPv6 addresses are not allowed',
      '64:ff9b::7f00:1': 'NAT64 IPv6 addresses are not allowed',
      '64:ff9b:1::7f00:1': 'NAT64 IPv6 addresses are not allowed',
    };

    for (final entry in blocked.entries) {
      expect(
        NetworkAddressPolicy.publicHostBlockReason(entry.key),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('keeps only canonical loopback forms eligible for local sidecars', () {
    expect(NetworkAddressPolicy.isExplicitLoopbackHost('127.0.0.1'), isTrue);
    expect(NetworkAddressPolicy.isExplicitLoopbackHost('::1'), isTrue);
    expect(NetworkAddressPolicy.isExplicitLoopbackHost('::127.0.0.1'), isFalse);
  });

  test('rejects IANA special-purpose targets consistently with the broker', () {
    final blocked = <String, String>{
      '192.0.0.8': 'reserved IPv4 addresses are not allowed',
      '192.88.99.2': 'reserved IPv4 addresses are not allowed',
      '100::': 'special-purpose IPv6 addresses are not allowed',
      '2001:2::': 'special-purpose IPv6 addresses are not allowed',
      '3fff::': 'special-purpose IPv6 addresses are not allowed',
      '5f00::': 'special-purpose IPv6 addresses are not allowed',
    };

    for (final entry in blocked.entries) {
      expect(
        NetworkAddressPolicy.publicHostBlockReason(entry.key),
        entry.value,
        reason: entry.key,
      );
    }
  });
}
