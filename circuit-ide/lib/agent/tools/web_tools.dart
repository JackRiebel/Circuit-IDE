import 'dart:convert';

import 'package:dio/dio.dart';

class WebTools {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'User-Agent': 'CircuitIDE/1.0',
    },
  ));

  Future<String> execute(String toolName, Map<String, dynamic> args) async {
    return switch (toolName) {
      'web_fetch' => _webFetch(args),
      'web_search' => _webSearch(args),
      _ => throw ArgumentError('Unknown web tool: $toolName'),
    };
  }

  Future<String> _webFetch(Map<String, dynamic> args) async {
    final url = args['url'] as String?;
    if (url == null || url.isEmpty) {
      return 'Error: url is required';
    }

    try {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) {
        return 'Error: Invalid URL: $url';
      }

      final response = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          maxRedirects: 5,
        ),
      );

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

  Future<String> _webSearch(Map<String, dynamic> args) async {
    final query = args['query'] as String?;
    if (query == null || query.isEmpty) {
      return 'Error: query is required';
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
    } catch (e) {
      return 'Error searching: $e';
    }
  }

  String _parseSearchResults(String html) {
    final results = <String>[];
    final linkPattern =
        RegExp(r'<a[^>]+class="result__a"[^>]*>(.*?)</a>', dotAll: true);
    final snippetPattern =
        RegExp(r'<a[^>]+class="result__snippet"[^>]*>(.*?)</a>', dotAll: true);
    final urlPattern =
        RegExp(r'<a[^>]+class="result__url"[^>]*>(.*?)</a>', dotAll: true);

    final titles = linkPattern.allMatches(html).toList();
    final snippets = snippetPattern.allMatches(html).toList();
    final urls = urlPattern.allMatches(html).toList();

    for (var i = 0; i < titles.length && i < 10; i++) {
      final title = _stripHtml(titles[i].group(1) ?? '').trim();
      final snippet =
          i < snippets.length ? _stripHtml(snippets[i].group(1) ?? '').trim() : '';
      final url =
          i < urls.length ? _stripHtml(urls[i].group(1) ?? '').trim() : '';

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
    text = text.replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '');
    text = text.replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '');
    text = text.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

    // Headings
    text = text.replaceAllMapped(
        RegExp(r'<h1[^>]*>(.*?)</h1>', dotAll: true), (m) => '\n# ${m[1]}\n');
    text = text.replaceAllMapped(
        RegExp(r'<h2[^>]*>(.*?)</h2>', dotAll: true), (m) => '\n## ${m[1]}\n');
    text = text.replaceAllMapped(
        RegExp(r'<h3[^>]*>(.*?)</h3>', dotAll: true), (m) => '\n### ${m[1]}\n');

    // Paragraphs and breaks
    text = text.replaceAll(RegExp(r'<br\s*/?>'), '\n');
    text = text.replaceAll(RegExp(r'<p[^>]*>'), '\n');
    text = text.replaceAll('</p>', '\n');

    // Links
    text = text.replaceAllMapped(
        RegExp(r'<a[^>]+href="([^"]*)"[^>]*>(.*?)</a>', dotAll: true),
        (m) => '[${_stripHtml(m[2] ?? '')}](${m[1]})');

    // Bold/italic
    text = text.replaceAllMapped(
        RegExp(r'<(strong|b)>(.*?)</\1>', dotAll: true), (m) => '**${m[2]}**');
    text = text.replaceAllMapped(
        RegExp(r'<(em|i)>(.*?)</\1>', dotAll: true), (m) => '*${m[2]}*');

    // Code
    text = text.replaceAllMapped(
        RegExp(r'<code>(.*?)</code>', dotAll: true), (m) => '`${m[1]}`');
    text = text.replaceAllMapped(
        RegExp(r'<pre[^>]*>(.*?)</pre>', dotAll: true),
        (m) => '\n```\n${m[1]}\n```\n');

    // Lists
    text = text.replaceAllMapped(
        RegExp(r'<li[^>]*>(.*?)</li>', dotAll: true), (m) => '- ${m[1]}\n');

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
