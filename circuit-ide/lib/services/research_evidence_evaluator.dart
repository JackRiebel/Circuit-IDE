/// A deterministic, source-safe assessment layer for Studio Research mode.
///
/// It intentionally ranks URL signals and explicit checked/published dates; it
/// never treats a host name as proof that a claim is true. The model must still
/// cite the direct source and label gaps or inferences in its answer.
enum ResearchSourceAuthority {
  primary,
  institutional,
  secondary,
  lowConfidence,
}

enum ResearchSourceFreshness { current, aging, stale, publicationUnknown }

class ResearchSourceRecord {
  final Uri uri;
  final DateTime checkedAt;
  final DateTime? publishedAt;
  final String? title;

  const ResearchSourceRecord({
    required this.uri,
    required this.checkedAt,
    this.publishedAt,
    this.title,
  });

  Uri get citationUri => Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path.isEmpty ? '/' : uri.path,
  );

  ResearchSourceAuthority authority() {
    final host = uri.host.toLowerCase();
    if (host.endsWith('.gov') ||
        host.endsWith('.mil') ||
        host.startsWith('docs.') ||
        host.startsWith('developer.')) {
      return ResearchSourceAuthority.primary;
    }
    if (host.endsWith('.edu') || host.endsWith('.ac.uk')) {
      return ResearchSourceAuthority.institutional;
    }
    if (host == 'wikipedia.org' ||
        host.endsWith('.wikipedia.org') ||
        host.contains('medium.com') ||
        host.contains('substack.com') ||
        host.contains('reddit.com') ||
        host.contains('x.com')) {
      return ResearchSourceAuthority.lowConfidence;
    }
    return ResearchSourceAuthority.secondary;
  }

  ResearchSourceFreshness freshness(DateTime now) {
    final published = publishedAt;
    if (published == null) return ResearchSourceFreshness.publicationUnknown;
    final age = now.toUtc().difference(published.toUtc());
    if (age <= const Duration(days: 31)) {
      return ResearchSourceFreshness.current;
    }
    if (age <= const Duration(days: 365)) {
      return ResearchSourceFreshness.aging;
    }
    return ResearchSourceFreshness.stale;
  }

  String get citationUrl => citationUri.toString();

  /// A conservative publisher grouping for corroboration checks. This is not
  /// a claim about ownership; it simply prevents multiple subdomains of the
  /// same registered domain from looking like independent sources.
  String get publisherScope => researchPublisherScope(uri);
}

/// Returns a registrable-domain-like grouping suitable for transparent source
/// diversity checks. It intentionally keeps IP literals and localhost exact,
/// and knows the small set of multi-label public suffixes common in product
/// research. Unknown suffixes fall back to the final two DNS labels.
String researchPublisherScope(Uri uri) {
  final host = uri.host.trim().toLowerCase();
  if (host.isEmpty || host == 'localhost' || host.contains(':')) return host;
  final labels = host.split('.').where((label) => label.isNotEmpty).toList();
  if (labels.length <= 2 ||
      labels.every((label) => int.tryParse(label) != null)) {
    return host;
  }
  const multiLabelSuffixes = {
    'ac.uk',
    'co.uk',
    'gov.uk',
    'org.uk',
    'com.au',
    'net.au',
    'org.au',
    'co.jp',
    'co.nz',
    'com.br',
    'com.mx',
  };
  final twoLabelSuffix = labels.sublist(labels.length - 2).join('.');
  final suffixLength = multiLabelSuffixes.contains(twoLabelSuffix) ? 2 : 1;
  final start = labels.length - suffixLength - 1;
  return labels.sublist(start).join('.');
}

class ResearchClaimRecord {
  final String id;
  final String text;
  final List<String> citedUrls;
  final bool dateSensitive;

  const ResearchClaimRecord({
    required this.id,
    required this.text,
    this.citedUrls = const [],
    this.dateSensitive = true,
  });
}

class ResearchClaimAssessment {
  final ResearchClaimRecord claim;
  final List<ResearchSourceRecord> sources;
  final bool needsDirectSource;
  final bool needsFreshnessReview;
  final bool needsIndependentCorroboration;

  const ResearchClaimAssessment({
    required this.claim,
    required this.sources,
    required this.needsDirectSource,
    required this.needsFreshnessReview,
    required this.needsIndependentCorroboration,
  });
}

class ResearchEvidenceAssessment {
  final List<ResearchClaimAssessment> claims;

  const ResearchEvidenceAssessment({required this.claims});

  List<ResearchClaimAssessment> get unsupportedClaims => claims
      .where((assessment) => assessment.needsDirectSource)
      .toList(growable: false);

  List<ResearchClaimAssessment> get freshnessGaps => claims
      .where((assessment) => assessment.needsFreshnessReview)
      .toList(growable: false);

  List<ResearchClaimAssessment> get singlePublisherClaims => claims
      .where((assessment) => assessment.needsIndependentCorroboration)
      .toList(growable: false);

  String toMarkdownTable() {
    final rows = <String>[
      '| Claim | Sources | Evidence status |',
      '| --- | --- | --- |',
    ];
    for (final assessment in claims) {
      final sourceLabels = assessment.sources.isEmpty
          ? 'None'
          : assessment.sources.map((source) => source.citationUrl).join('<br>');
      final status = assessment.needsDirectSource
          ? 'Unsupported — add direct source'
          : assessment.needsFreshnessReview
          ? 'Needs freshness review'
          : assessment.needsIndependentCorroboration
          ? 'Single publisher — corroborate or state limitation'
          : 'Direct source attached';
      rows.add(
        '| ${_cell(assessment.claim.text)} | ${_cell(sourceLabels)} | $status |',
      );
    }
    return rows.join('\n');
  }

  String _cell(String value) =>
      value.replaceAll('|', r'\|').replaceAll('\n', ' ').trim();
}

class ResearchEvidenceEvaluator {
  const ResearchEvidenceEvaluator();

  /// Extracts bounded material claims from the answer portion of a research
  /// response. Evidence, conflict, and source sections describe review
  /// metadata rather than new factual claims, so they are excluded from the
  /// direct-source matching contract.
  static List<ResearchClaimRecord> claimsFromContent(String content) {
    const maxClaims = 12;
    final answer = content
        .split(
          RegExp(
            r'^##\s+(?:Evidence\s+table|(?:Source\s+)?Conflict\s+review|Sources)\b.*$',
            multiLine: true,
            caseSensitive: false,
          ),
        )
        .first;
    final claims = <ResearchClaimRecord>[];
    for (final rawLine in answer.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('|')) {
        continue;
      }
      final text = line.replaceFirst(RegExp(r'^[-*]\s+'), '').trim();
      if (text.length < 24 || _isMethodLabel(text)) continue;
      final urls = RegExp(r'https?://[^\s)<\]]+')
          .allMatches(text)
          .map((match) => match.group(0)!)
          .toList(growable: false);
      final claim = text
          .replaceAll(RegExp(r'https?://[^\s)<\]]+'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (claim.length < 12) continue;
      claims.add(
        ResearchClaimRecord(
          id: 'claim-${claims.length + 1}',
          text: _shortenClaim(claim),
          citedUrls: urls,
          dateSensitive: _looksDateSensitive(claim),
        ),
      );
      if (claims.length >= maxClaims) break;
    }
    return claims;
  }

  ResearchEvidenceAssessment assess({
    required List<ResearchClaimRecord> claims,
    required List<ResearchSourceRecord> sources,
    required DateTime now,
  }) {
    final sourcesByUrl = {
      for (final source in sources) source.citationUrl: source,
    };
    return ResearchEvidenceAssessment(
      claims: [
        for (final claim in claims)
          () {
            final linked = claim.citedUrls
                .map(Uri.tryParse)
                .whereType<Uri>()
                .where((uri) => uri.hasScheme && uri.host.isNotEmpty)
                .map((uri) => sourcesByUrl[_citationUrl(uri)])
                .whereType<ResearchSourceRecord>()
                .toList(growable: false);
            final freshnessGap =
                claim.dateSensitive &&
                linked.any(
                  (source) => switch (source.freshness(now)) {
                    ResearchSourceFreshness.current => false,
                    ResearchSourceFreshness.aging ||
                    ResearchSourceFreshness.stale ||
                    ResearchSourceFreshness.publicationUnknown => true,
                  },
                );
            final publisherScopes = linked
                .map((source) => source.publisherScope)
                .where((scope) => scope.isNotEmpty)
                .toSet();
            return ResearchClaimAssessment(
              claim: claim,
              sources: linked,
              needsDirectSource: linked.isEmpty,
              needsFreshnessReview: freshnessGap,
              needsIndependentCorroboration:
                  claim.dateSensitive &&
                  linked.isNotEmpty &&
                  publisherScopes.length < 2,
            );
          }(),
      ],
    );
  }

  String _citationUrl(Uri uri) => Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path.isEmpty ? '/' : uri.path,
  ).toString();

  static bool _isMethodLabel(String text) {
    final normalized = text.toLowerCase();
    return normalized.startsWith('research mode') ||
        normalized.startsWith('sources:') ||
        normalized.startsWith('evidence table:');
  }

  static bool _looksDateSensitive(String text) => RegExp(
    r'\b(current|currently|latest|today|now|as of|recent|\d{4})\b',
    caseSensitive: false,
  ).hasMatch(text);

  static String _shortenClaim(String value) {
    const maxLength = 240;
    final normalized = value.trim();
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength - 1).trimRight()}…';
  }
}
