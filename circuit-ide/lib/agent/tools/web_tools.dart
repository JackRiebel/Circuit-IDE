import 'dart:convert';

import 'package:dio/dio.dart';

class WebTools {
  final Dio _dio;

  WebTools({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: {'User-Agent': 'CircuitIDE/1.0'},
            ),
          );

  Future<String> execute(
    String toolName,
    Map<String, dynamic> args, {
    bool allowNetwork = false,
  }) async {
    return switch (toolName) {
      'web_fetch' => _webFetch(args, allowNetwork: allowNetwork),
      'web_search' => _webSearch(args, allowNetwork: allowNetwork),
      _ => throw ArgumentError('Unknown web tool: $toolName'),
    };
  }

  Future<String> _webFetch(
    Map<String, dynamic> args, {
    required bool allowNetwork,
  }) async {
    final url = args['url'] as String?;
    if (url == null || url.isEmpty) {
      return 'Error: url is required';
    }

    try {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) {
        return 'Error: Invalid URL: $url';
      }
      final validationError = _validateFetchUri(uri);
      if (validationError != null) return validationError;
      if (!allowNetwork) {
        return 'Error: Network tool requires review before fetching external URLs';
      }

      final response = await _safeGet(uri);

      if (response.statusCode != null && response.statusCode! >= 400) {
        return 'Error: HTTP ${response.statusCode}';
      }

      final body = response.data ?? '';
      final contentType = response.headers.value('content-type') ?? '';

      if (contentType.contains('application/json')) {
        try {
          final json = jsonDecode(body);
          final pretty = const JsonEncoder.withIndent('  ').convert(json);
          return _truncate(pretty, 50000);
        } catch (_) {
          return _truncate(body, 50000);
        }
      }

      if (contentType.contains('text/html')) {
        return _truncate(_htmlToMarkdown(body), 50000);
      }

      return _truncate(body, 50000);
    } on StateError catch (e) {
      final message = e.message;
      if (message.startsWith('Error: ')) return message;
      return 'Error fetching $url: $message';
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout) {
        return 'Error: Connection timed out for $url';
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        return 'Error: Response timed out for $url';
      }
      return 'Error fetching $url: ${e.message}';
    } catch (e) {
      return 'Error fetching $url: $e';
    }
  }

  Future<String> _webSearch(
    Map<String, dynamic> args, {
    required bool allowNetwork,
  }) async {
    final query = args['query'] as String?;
    if (query == null || query.isEmpty) {
      return 'Error: query is required';
    }
    final queryTargetError = _validateSearchQuery(query);
    if (queryTargetError != null) return queryTargetError;
    if (!allowNetwork) {
      return 'Error: Network tool requires review before searching the web';
    }

    // Use DuckDuckGo HTML endpoint as a simple search fallback
    try {
      final encoded = Uri.encodeComponent(query);
      final response = await _dio.get<String>(
        'https://html.duckduckgo.com/html/?q=$encoded',
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
          },
        ),
      );

      final body = response.data ?? '';
      return _parseSearchResults(body);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout) {
        return 'Error: Search connection timed out';
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        return 'Error: Search response timed out';
      }
      return 'Error searching: ${e.message}';
    } catch (e) {
      return 'Error searching: $e';
    }
  }

  Future<Response<String>> _safeGet(Uri uri) async {
    var current = uri;
    for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
      final response = await _dio.getUri<String>(
        current,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (status) => status != null && status < 400,
        ),
      );
      final status = response.statusCode ?? 0;
      if (!_isRedirectStatus(status)) return response;

      final location = response.headers.value('location');
      if (location == null || location.trim().isEmpty) {
        throw StateError('Redirect response missing Location header');
      }
      final next = current.resolve(location.trim());
      final validationError = _validateFetchUri(next);
      if (validationError != null) {
        throw StateError(validationError);
      }
      current = next;
    }
    throw StateError('Too many redirects');
  }

  bool _isRedirectStatus(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;

  String? _validateFetchUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return 'Error: Network target blocked: only http and https URLs are allowed';
    }
    if (uri.userInfo.isNotEmpty) {
      return 'Error: Network target blocked: credentials in URLs are not allowed';
    }
    final host = _normalizeHost(uri.host);
    if (host.isEmpty) {
      return 'Error: Invalid URL: host is required';
    }
    final blockedReason = _blockedHostReason(host);
    if (blockedReason != null) {
      return 'Error: Network target blocked: $blockedReason ($host)';
    }
    return null;
  }

  String _normalizeHost(String host) {
    var normalized = host.trim().toLowerCase();
    if (normalized.startsWith('[') && normalized.endsWith(']')) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    while (normalized.endsWith('.')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  String? _blockedHostReason(String host) {
    if (host == 'localhost' ||
        host == 'localhost.localdomain' ||
        host.endsWith('.localhost')) {
      return 'localhost access is not allowed';
    }
    if (host.endsWith('.local') ||
        host.endsWith('.internal') ||
        host.endsWith('.lan')) {
      return 'private network hostnames are not allowed';
    }
    if (!host.contains('.') && !_isIpv6Literal(host)) {
      return 'single-label/internal hostnames are not allowed';
    }
    if (_looksLikeAmbiguousIpv4Alias(host)) {
      return 'ambiguous numeric IPv4 hostnames are not allowed';
    }
    final ipv4Reason = _blockedIpv4Reason(host);
    if (ipv4Reason != null) return ipv4Reason;
    final ipv6Reason = _blockedIpv6Reason(host);
    if (ipv6Reason != null) return ipv6Reason;
    return null;
  }

  String? _blockedIpv4Reason(String host) {
    final match = RegExp(
      r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
    ).firstMatch(host);
    if (match == null) return null;
    final octets = [
      for (var i = 1; i <= 4; i++) int.tryParse(match.group(i) ?? ''),
    ];
    if (octets.any((octet) => octet == null || octet < 0 || octet > 255)) {
      return 'invalid IPv4 address';
    }
    final first = octets[0]!;
    final second = octets[1]!;
    if (first == 0) return 'unspecified IPv4 addresses are not allowed';
    if (first == 10) return 'private IPv4 addresses are not allowed';
    if (first == 127) return 'loopback IPv4 addresses are not allowed';
    if (first == 169 && second == 254) {
      return 'link-local and metadata IPv4 addresses are not allowed';
    }
    if (first == 172 && second >= 16 && second <= 31) {
      return 'private IPv4 addresses are not allowed';
    }
    if (first == 192 && second == 168) {
      return 'private IPv4 addresses are not allowed';
    }
    if (first >= 224) {
      return 'multicast/reserved IPv4 addresses are not allowed';
    }
    return null;
  }

  String? _validateSearchQuery(String query) {
    final urlLikePattern = RegExp(
      r'''https?://[^\s<>"')]+''',
      caseSensitive: false,
    );
    for (final match in urlLikePattern.allMatches(query)) {
      final rawUrl = match.group(0);
      if (rawUrl == null) continue;
      final uri = Uri.tryParse(rawUrl);
      if (uri == null) {
        return 'Error: Network search target blocked: invalid URL target';
      }
      final validationError = _validateFetchUri(uri);
      if (validationError != null) {
        return validationError.replaceFirst(
          'Network target blocked:',
          'Network search target blocked:',
        );
      }
    }

    final operatorPattern = RegExp(
      r'\b(?:site|url|inurl):([^\s]+)',
      caseSensitive: false,
    );
    for (final match in operatorPattern.allMatches(query)) {
      final rawTarget = match.group(1)?.trim();
      if (rawTarget == null || rawTarget.isEmpty) continue;
      final host = _hostFromSearchTarget(rawTarget);
      if (host == null || host.isEmpty) continue;
      final blockedReason = _blockedHostReason(_normalizeHost(host));
      if (blockedReason != null) {
        return 'Error: Network search target blocked: $blockedReason ($host)';
      }
    }

    final sensitiveHostPattern = RegExp(
      r'(^|[^A-Za-z0-9_.:-])((?:localhost(?:\.localdomain)?)|(?:(?:\d{1,3}\.){3}\d{1,3})|(?:0x[0-9a-f]+|\d+)(?:\.(?:0x[0-9a-f]+|\d+)){1,3}|\[[0-9a-f:]+\])($|[^A-Za-z0-9_.:-])',
      caseSensitive: false,
    );
    for (final match in sensitiveHostPattern.allMatches(query)) {
      var rawHost = match.group(2);
      if (rawHost == null || rawHost.isEmpty) continue;
      if (rawHost.startsWith('[') && rawHost.endsWith(']')) {
        rawHost = rawHost.substring(1, rawHost.length - 1);
      }
      final host = _normalizeHost(rawHost);
      final blockedReason = _blockedHostReason(host);
      if (blockedReason != null) {
        return 'Error: Network search target blocked: $blockedReason ($host)';
      }
    }

    return null;
  }

  String? _hostFromSearchTarget(String target) {
    final trimmed = target.trim();
    if (trimmed.isEmpty) return null;
    final withScheme =
        RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(trimmed)
        ? trimmed
        : 'http://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.trim().isEmpty) return null;
    return uri.host;
  }

  bool _looksLikeAmbiguousIpv4Alias(String host) {
    if (_isIpv6Literal(host) || !host.contains('.')) return false;
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

  bool _isIpv6Literal(String host) => host.contains(':');

  String? _blockedIpv6Reason(String host) {
    if (!_isIpv6Literal(host)) return null;
    final normalized = host.toLowerCase();
    if (normalized == '::' || normalized == '0:0:0:0:0:0:0:0') {
      return 'unspecified IPv6 addresses are not allowed';
    }
    if (normalized == '::1' || normalized == '0:0:0:0:0:0:0:1') {
      return 'loopback IPv6 addresses are not allowed';
    }
    if (normalized.startsWith('fe80:')) {
      return 'link-local IPv6 addresses are not allowed';
    }
    if (normalized.startsWith('fc') || normalized.startsWith('fd')) {
      return 'unique-local IPv6 addresses are not allowed';
    }
    if (normalized.startsWith('ff')) {
      return 'multicast IPv6 addresses are not allowed';
    }
    if (normalized.startsWith('::ffff:')) {
      return _blockedIpv4Reason(normalized.substring('::ffff:'.length));
    }
    return null;
  }

  String _parseSearchResults(String html) {
    final results = <String>[];
    final linkPattern = RegExp(
      r'<a[^>]+class="result__a"[^>]*>(.*?)</a>',
      dotAll: true,
    );
    final snippetPattern = RegExp(
      r'<a[^>]+class="result__snippet"[^>]*>(.*?)</a>',
      dotAll: true,
    );
    final urlPattern = RegExp(
      r'<a[^>]+class="result__url"[^>]*>(.*?)</a>',
      dotAll: true,
    );

    final titles = linkPattern.allMatches(html).toList();
    final snippets = snippetPattern.allMatches(html).toList();
    final urls = urlPattern.allMatches(html).toList();

    for (var i = 0; i < titles.length && i < 10; i++) {
      final title = _stripHtml(titles[i].group(1) ?? '').trim();
      final snippet = i < snippets.length
          ? _stripHtml(snippets[i].group(1) ?? '').trim()
          : '';
      final url = i < urls.length
          ? _stripHtml(urls[i].group(1) ?? '').trim()
          : '';

      if (title.isNotEmpty) {
        results.add('${i + 1}. $title\n   $url\n   $snippet');
      }
    }

    if (results.isEmpty) {
      return 'No search results found for the query.';
    }

    return results.join('\n\n');
  }

  String _htmlToMarkdown(String html) {
    var text = html;

    // Remove script/style blocks
    text = text.replaceAll(
      RegExp(r'<script[^>]*>.*?</script>', dotAll: true),
      '',
    );
    text = text.replaceAll(
      RegExp(r'<style[^>]*>.*?</style>', dotAll: true),
      '',
    );
    text = text.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

    // Headings
    text = text.replaceAllMapped(
      RegExp(r'<h1[^>]*>(.*?)</h1>', dotAll: true),
      (m) => '\n# ${m[1]}\n',
    );
    text = text.replaceAllMapped(
      RegExp(r'<h2[^>]*>(.*?)</h2>', dotAll: true),
      (m) => '\n## ${m[1]}\n',
    );
    text = text.replaceAllMapped(
      RegExp(r'<h3[^>]*>(.*?)</h3>', dotAll: true),
      (m) => '\n### ${m[1]}\n',
    );

    // Paragraphs and breaks
    text = text.replaceAll(RegExp(r'<br\s*/?>'), '\n');
    text = text.replaceAll(RegExp(r'<p[^>]*>'), '\n');
    text = text.replaceAll('</p>', '\n');

    // Links
    text = text.replaceAllMapped(
      RegExp(r'<a[^>]+href="([^"]*)"[^>]*>(.*?)</a>', dotAll: true),
      (m) => '[${_stripHtml(m[2] ?? '')}](${m[1]})',
    );

    // Bold/italic
    text = text.replaceAllMapped(
      RegExp(r'<(strong|b)>(.*?)</\1>', dotAll: true),
      (m) => '**${m[2]}**',
    );
    text = text.replaceAllMapped(
      RegExp(r'<(em|i)>(.*?)</\1>', dotAll: true),
      (m) => '*${m[2]}*',
    );

    // Code
    text = text.replaceAllMapped(
      RegExp(r'<code>(.*?)</code>', dotAll: true),
      (m) => '`${m[1]}`',
    );
    text = text.replaceAllMapped(
      RegExp(r'<pre[^>]*>(.*?)</pre>', dotAll: true),
      (m) => '\n```\n${m[1]}\n```\n',
    );

    // Lists
    text = text.replaceAllMapped(
      RegExp(r'<li[^>]*>(.*?)</li>', dotAll: true),
      (m) => '- ${m[1]}\n',
    );

    // Strip remaining tags
    text = _stripHtml(text);

    // Decode entities
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');

    // Clean up whitespace
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]+>'), '');
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}\n\n[Content truncated at $maxLength characters]';
  }
}
