import 'dart:io';

/// Fail-closed address classification shared by outbound network boundaries.
///
/// A hostname allow-list alone is insufficient because DNS can rebind between
/// requests. Call [publicHostBlockReason] on both a configured hostname and
/// every resolved answer immediately before a request. Loopback sidecars use
/// [isExplicitLoopbackHost] as their deliberately narrower exception.
class NetworkAddressPolicy {
  const NetworkAddressPolicy._();

  static String normalizeHost(String host) {
    var normalized = host.trim().toLowerCase();
    if (normalized.startsWith('[') && normalized.endsWith(']')) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    while (normalized.endsWith('.')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  /// Returns a reason whenever [host] is not a valid public network target.
  static String? publicHostBlockReason(String host) {
    final normalized = normalizeHost(host);
    if (normalized == 'localhost' ||
        normalized == 'localhost.localdomain' ||
        normalized.endsWith('.localhost')) {
      return 'localhost access is not allowed';
    }
    if (normalized.endsWith('.local') ||
        normalized.endsWith('.internal') ||
        normalized.endsWith('.lan')) {
      return 'private network hostnames are not allowed';
    }
    if (!normalized.contains('.') && !normalized.contains(':')) {
      return 'single-label/internal hostnames are not allowed';
    }
    if (_looksLikeAmbiguousIpv4Alias(normalized)) {
      return 'ambiguous numeric IPv4 hostnames are not allowed';
    }
    return _blockedIpv4Reason(normalized) ?? _blockedIpv6Reason(normalized);
  }

  /// A loopback sidecar must be named or addressed explicitly; a public host
  /// that later resolves to loopback is still rejected by [publicHostBlockReason].
  static bool isExplicitLoopbackHost(String host) {
    final normalized = normalizeHost(host);
    if (normalized == 'localhost' ||
        normalized == 'localhost.localdomain' ||
        normalized.endsWith('.localhost')) {
      return true;
    }
    final ipv4 = _ipv4Octets(normalized);
    if (ipv4 != null) return ipv4.first == 127;
    final bytes = _ipv6Bytes(normalized);
    if (bytes == null) return false;
    if (_isIpv4Mapped(bytes)) return bytes[12] == 127;
    return _isIpv6Loopback(bytes);
  }

  static List<int>? _ipv4Octets(String host) {
    final match = RegExp(
      r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
    ).firstMatch(host);
    if (match == null) return null;
    final octets = [
      for (var index = 1; index <= 4; index++)
        int.tryParse(match.group(index) ?? ''),
    ];
    if (octets.any((octet) => octet == null || octet < 0 || octet > 255)) {
      return null;
    }
    return octets.cast<int>();
  }

  static String? _blockedIpv4Reason(String host) {
    final isDottedDecimal = RegExp(
      r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
    ).hasMatch(host);
    final octets = _ipv4Octets(host);
    if (octets == null) {
      return isDottedDecimal ? 'invalid IPv4 address' : null;
    }
    return _blockedIpv4OctetsReason(octets);
  }

  static String? _blockedIpv4OctetsReason(List<int> octets) {
    final first = octets[0];
    final second = octets[1];
    final third = octets[2];
    if (first == 0) return 'unspecified IPv4 addresses are not allowed';
    if (first == 10 ||
        first == 172 && second >= 16 && second <= 31 ||
        first == 192 && second == 168) {
      return 'private IPv4 addresses are not allowed';
    }
    if (first == 100 && second >= 64 && second <= 127) {
      return 'shared IPv4 addresses are not allowed';
    }
    if (first == 127) return 'loopback IPv4 addresses are not allowed';
    if (first == 169 && second == 254) {
      return 'link-local and metadata IPv4 addresses are not allowed';
    }
    if (first == 192 && second == 0 && third == 0 ||
        first == 192 && second == 0 && third == 2 ||
        first == 192 && second == 88 && third == 99 ||
        first == 198 && (second == 18 || second == 19) ||
        first == 198 && second == 51 && third == 100 ||
        first == 203 && second == 0 && third == 113 ||
        first >= 224) {
      return 'reserved IPv4 addresses are not allowed';
    }
    return null;
  }

  static List<int>? _ipv6Bytes(String host) {
    final address = InternetAddress.tryParse(host);
    if (address == null || address.type != InternetAddressType.IPv6) {
      return null;
    }
    return address.rawAddress;
  }

  static String? _blockedIpv6Reason(String host) {
    if (!host.contains(':')) return null;
    final bytes = _ipv6Bytes(host);
    if (bytes == null) return 'invalid IPv6 address';
    if (bytes.every((byte) => byte == 0)) {
      return 'unspecified IPv6 addresses are not allowed';
    }
    if (_isIpv6Loopback(bytes)) {
      return 'loopback IPv6 addresses are not allowed';
    }
    if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) {
      return 'link-local IPv6 addresses are not allowed';
    }
    if ((bytes[0] & 0xfe) == 0xfc) {
      return 'unique-local IPv6 addresses are not allowed';
    }
    if (bytes[0] == 0xff) {
      return 'multicast IPv6 addresses are not allowed';
    }
    if (_isIpv4Mapped(bytes)) {
      return _blockedIpv4OctetsReason(bytes.sublist(12));
    }
    // IPv4-compatible IPv6 forms (for example, ::127.0.0.1) are deprecated,
    // but some socket stacks still accept them. Do not let that alternate
    // spelling bypass the IPv4 private/loopback policy, and do not treat it as
    // an explicit loopback sidecar address.
    if (_isIpv4Compatible(bytes)) {
      return _blockedIpv4OctetsReason(bytes.sublist(12)) ??
          'IPv4-compatible IPv6 addresses are not allowed';
    }
    // 6to4, Teredo, and NAT64 prefixes can tunnel or translate to an IPv4
    // peer outside the address that the URI appears to name. Circuit's
    // outbound product paths have no requirement for these legacy/special
    // routes, so fail closed rather than attempting to infer their eventual
    // IPv4 destination.
    if (_isSixToFour(bytes)) {
      return '6to4 IPv6 addresses are not allowed';
    }
    if (_isTeredo(bytes)) {
      return 'Teredo IPv6 addresses are not allowed';
    }
    if (_isWellKnownNat64(bytes) || _isLocalUseNat64(bytes)) {
      return 'NAT64 IPv6 addresses are not allowed';
    }
    // Outbound product paths use ordinary globally reachable unicast only.
    // Reject IANA special-purpose allocations as a class, even where a more
    // specific protocol anycast address is globally routable: those
    // exceptions are not valid targets for a model-selected request and would
    // make the policy differ from the brokered-command boundary.
    if (_isIetfProtocolAllocation(bytes) ||
        _isDiscardOnly(bytes) ||
        _isDocumentationIpv6(bytes) ||
        _isSrv6Sid(bytes)) {
      return 'special-purpose IPv6 addresses are not allowed';
    }
    return null;
  }

  static bool _isIpv6Loopback(List<int> bytes) =>
      bytes.sublist(0, 15).every((byte) => byte == 0) && bytes[15] == 1;

  static bool _isIpv4Mapped(List<int> bytes) =>
      bytes.sublist(0, 10).every((byte) => byte == 0) &&
      bytes[10] == 0xff &&
      bytes[11] == 0xff;

  static bool _isIpv4Compatible(List<int> bytes) =>
      bytes.sublist(0, 12).every((byte) => byte == 0);

  static bool _isSixToFour(List<int> bytes) =>
      bytes[0] == 0x20 && bytes[1] == 0x02;

  static bool _isTeredo(List<int> bytes) =>
      bytes[0] == 0x20 &&
      bytes[1] == 0x01 &&
      bytes[2] == 0x00 &&
      bytes[3] == 0x00;

  static bool _isIetfProtocolAllocation(List<int> bytes) =>
      bytes[0] == 0x20 && bytes[1] == 0x01 && (bytes[2] & 0xfe) == 0;

  static bool _isDiscardOnly(List<int> bytes) =>
      bytes[0] == 0x01 &&
      bytes[1] == 0x00 &&
      bytes[2] == 0x00 &&
      bytes[3] == 0x00 &&
      bytes[4] == 0x00 &&
      bytes[5] == 0x00;

  static bool _isDocumentationIpv6(List<int> bytes) =>
      bytes[0] == 0x20 &&
          bytes[1] == 0x01 &&
          bytes[2] == 0x0d &&
          bytes[3] == 0xb8 ||
      bytes[0] == 0x3f && bytes[1] == 0xff && (bytes[2] & 0xf0) == 0;

  static bool _isSrv6Sid(List<int> bytes) =>
      bytes[0] == 0x5f && bytes[1] == 0x00;

  static bool _isWellKnownNat64(List<int> bytes) =>
      bytes[0] == 0x00 &&
      bytes[1] == 0x64 &&
      bytes[2] == 0xff &&
      bytes[3] == 0x9b &&
      bytes.sublist(4, 12).every((byte) => byte == 0);

  static bool _isLocalUseNat64(List<int> bytes) =>
      bytes[0] == 0x00 &&
      bytes[1] == 0x64 &&
      bytes[2] == 0xff &&
      bytes[3] == 0x9b &&
      bytes[4] == 0x00 &&
      bytes[5] == 0x01;

  static bool _looksLikeAmbiguousIpv4Alias(String host) {
    if (host.contains(':') || !host.contains('.')) return false;
    final labels = host.split('.');
    final allNumericOrHex = labels.every((label) {
      if (label.isEmpty) return false;
      return RegExp(r'^\d+$').hasMatch(label) ||
          RegExp(r'^0x[0-9a-f]+$', caseSensitive: false).hasMatch(label);
    });
    if (!allNumericOrHex) return false;
    if (labels.length != 4) return true;
    return labels.any((label) {
      if (RegExp(r'^0x[0-9a-f]+$', caseSensitive: false).hasMatch(label)) {
        return true;
      }
      return label.length > 1 && label.startsWith('0');
    });
  }
}
