import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../security/network_address_policy.dart';
import '../security/pinned_network_http_client.dart';
import '../../services/research_evidence_evaluator.dart';

typedef HostAddressResolver = NetworkHostAddressResolver;

class WebTools {
  final Dio _dio;
  final HostAddressResolver _hostAddressResolver;

  WebTools({Dio? dio, HostAddressResolver? hostAddressResolver})
    : _dio =
          dio ??
          createPinnedNetworkDio(
            hostAddressResolver: hostAddressResolver ?? InternetAddress.lookup,
            allowExplicitLoopback: false,
            options: BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: {'User-Agent': 'CircuitIDE/1.0'},
            ),
          ),
      _hostAddressResolver = hostAddressResolver ?? InternetAddress.lookup;

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
    var safeTarget = 'the requested URL';
    if (url == null || url.isEmpty) {
      return 'Error: url is required';
    }

    try {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) {
        return 'Error: Invalid URL';
      }
      final validationError = _validateFetchUri(uri);
      if (validationError != null) return validationError;
      safeTarget = _citationSafeUrl(uri);
      if (!allowNetwork) {
        return 'Error: Network tool requires review before fetching external URLs';
      }

      final fetched = await _safeGet(uri);
      final response = fetched.response;

      if (response.statusCode != null && response.statusCode! >= 400) {
        return 'Error: HTTP ${response.statusCode}';
      }

      final body = response.data ?? '';
      final contentType = response.headers.value('content-type') ?? '';
      final formatted = contentType.contains('application/json')
          ? () {
              try {
                final json = jsonDecode(body);
                final pretty = const JsonEncoder.withIndent('  ').convert(json);
                return _truncate(pretty, 50000);
              } catch (_) {
                return _truncate(body, 50000);
              }
            }()
          : contentType.contains('text/html')
          ? _truncate(_htmlToMarkdown(body), 50000)
          : _truncate(body, 50000);
      // Cite the final, validated response URL rather than the request URL.
      // A redirect can legitimately move a source to its canonical location;
      // retaining the first URL would make the provenance line misleading.
      return _withResearchSource(
        _sanitizeUrlReferences(formatted),
        fetched.uri,
      );
    } on StateError catch (e) {
      final message = e.message;
      if (message.startsWith('Error: ')) return message;
      return 'Error fetching $safeTarget: request failed';
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout) {
        return 'Error: Connection timed out for $safeTarget';
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        return 'Error: Response timed out for $safeTarget';
      }
      return 'Error fetching $safeTarget: request failed';
    } catch (_) {
      return 'Error fetching $safeTarget: request failed';
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

    // The fixed search endpoint has the same network boundary as arbitrary
    // fetches. Search-origin DNS can be rebound and the endpoint can redirect,
    // so never let Dio follow either path outside the per-hop validation used
    // for `web_fetch`.
    try {
      final fetched = await _safeGet(
        Uri.https('html.duckduckgo.com', '/html/', {'q': query}),
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        },
      );
      final body = fetched.response.data ?? '';
      return _parseSearchResults(body);
    } on StateError catch (e) {
      final message = e.message;
      return message.startsWith('Error: ')
          ? message
          : 'Error searching: $message';
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout) {
        return 'Error: Search connection timed out';
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        return 'Error: Search response timed out';
      }
      return 'Error searching: request failed';
    } catch (_) {
      return 'Error searching: request failed';
    }
  }

  Future<_SafeWebResponse> _safeGet(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    var current = uri;
    for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
      final resolutionError = await _validateResolvedFetchUri(current);
      if (resolutionError != null) {
        throw StateError(resolutionError);
      }
      final response = await _dio.getUri<String>(
        current,
        options: Options(
          responseType: ResponseType.plain,
          headers: headers,
          followRedirects: false,
          maxRedirects: 0,
          validateStatus: (status) => status != null && status < 400,
        ),
      );
      final status = response.statusCode ?? 0;
      if (!_isRedirectStatus(status)) {
        return _SafeWebResponse(response: response, uri: current);
      }

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

  /// Hostname validation alone does not defend against DNS rebinding. Resolve
  /// every hop immediately before the request and reject the whole fetch if
  /// any answer is local, private, link-local, metadata, or reserved space.
  /// Redirects re-enter this guard rather than inheriting the first target's
  /// approval.
  Future<String?> _validateResolvedFetchUri(Uri uri) async {
    final host = _normalizeHost(uri.host);
    try {
      final addresses = await _hostAddressResolver(host);
      if (addresses.isEmpty) {
        return 'Error: Network target blocked: $host did not resolve to a public address';
      }
      for (final address in addresses) {
        final normalizedAddress = _normalizeHost(address.address);
        final blockedReason = _blockedHostReason(normalizedAddress);
        if (blockedReason != null) {
          return 'Error: Network target blocked: resolved address $normalizedAddress is not allowed ($blockedReason)';
        }
      }
      return null;
    } on SocketException {
      return 'Error: Network target blocked: $host could not be resolved safely';
    } catch (_) {
      return 'Error: Network target blocked: $host could not be resolved safely';
    }
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

  String _normalizeHost(String host) =>
      NetworkAddressPolicy.normalizeHost(host);

  String? _blockedHostReason(String host) =>
      NetworkAddressPolicy.publicHostBlockReason(host);

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
      final rawUrl = i < urls.length
          ? _stripHtml(urls[i].group(1) ?? '').trim()
          : '';
      final url = _researchCandidateUrl(rawUrl);

      // A search result is only a candidate. Keep it canonical and fetchable
      // before exposing it to the model, so tracking parameters and unsafe
      // schemes/hosts cannot be carried from a result page into provenance.
      if (title.isNotEmpty && url.isNotEmpty) {
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

  String _citationSafeUrl(Uri uri) => Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path.isEmpty ? '/' : uri.path,
  ).toString();

  /// Remote content can reflect its requested URL or include tracking links.
  /// Normalize HTTP(S) references before that content reaches the research
  /// transcript, matching the provenance footer and evidence-artifact rule.
  String _sanitizeUrlReferences(String value) {
    return value.replaceAllMapped(
      RegExp(r'''https?://[^\s<>"')\]]+''', caseSensitive: false),
      (match) {
        final uri = Uri.tryParse(match.group(0)!);
        return uri == null || _validateFetchUri(uri) != null
            ? '[unsafe URL omitted]'
            : _citationSafeUrl(uri);
      },
    );
  }

  String _researchCandidateUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || _validateFetchUri(uri) != null) return '';
    return _citationSafeUrl(uri);
  }

  /// Web research answers need a citation-safe, stable source line. Query and
  /// fragment values are intentionally removed so copied citations cannot
  /// carry accidental tracking identifiers or user-supplied sensitive values.
  String _withResearchSource(String content, Uri uri) {
    final checkedAt = DateTime.now().toUtc();
    final record = ResearchSourceRecord(uri: uri, checkedAt: checkedAt);
    final checked = checkedAt.toIso8601String().substring(0, 10);
    return '$content\n\nSource: ${record.citationUrl}\nChecked: $checked\nURL authority signal: ${record.authority().name}\nPublication date: unknown — verify freshness before relying on date-sensitive claims.';
  }
}

class _SafeWebResponse {
  final Response<String> response;
  final Uri uri;

  const _SafeWebResponse({required this.response, required this.uri});
}
