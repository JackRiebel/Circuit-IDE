import 'package:circuit_ide/services/research_evidence_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('source records sanitize citations and rank URL authority signals', () {
    final source = ResearchSourceRecord(
      uri: Uri.parse('https://developer.example.gov/api?tracking=private#top'),
      checkedAt: DateTime.utc(2026, 7, 12),
      publishedAt: DateTime.utc(2026, 7, 1),
    );

    expect(source.citationUrl, 'https://developer.example.gov/api');
    expect(source.authority(), ResearchSourceAuthority.primary);
    expect(
      source.freshness(DateTime.utc(2026, 7, 12)),
      ResearchSourceFreshness.current,
    );
  });

  test('claim assessment surfaces unsupported and stale evidence gaps', () {
    final current = ResearchSourceRecord(
      uri: Uri.parse('https://agency.gov/current'),
      checkedAt: DateTime.utc(2026, 7, 12),
      publishedAt: DateTime.utc(2026, 7, 1),
    );
    final stale = ResearchSourceRecord(
      uri: Uri.parse('https://example.com/old'),
      checkedAt: DateTime.utc(2026, 7, 12),
      publishedAt: DateTime.utc(2023, 1, 1),
    );
    final result = const ResearchEvidenceEvaluator().assess(
      now: DateTime.utc(2026, 7, 12),
      sources: [current, stale],
      claims: const [
        ResearchClaimRecord(
          id: 'supported',
          text: 'The program is active.',
          citedUrls: ['https://agency.gov/current'],
        ),
        ResearchClaimRecord(
          id: 'stale',
          text: 'The old pricing still applies.',
          citedUrls: ['https://example.com/old'],
        ),
        ResearchClaimRecord(id: 'missing', text: 'No source is attached.'),
      ],
    );

    expect(result.unsupportedClaims.map((claim) => claim.claim.id), [
      'missing',
    ]);
    expect(result.freshnessGaps.map((claim) => claim.claim.id), ['stale']);
    expect(result.toMarkdownTable(), contains('Needs freshness review'));
    expect(
      result.toMarkdownTable(),
      contains('Unsupported — add direct source'),
    );
  });

  test('publisher grouping avoids treating subdomains as corroboration', () {
    final docs = ResearchSourceRecord(
      uri: Uri.parse('https://docs.example.co.uk/guide'),
      checkedAt: DateTime.utc(2026, 7, 13),
      publishedAt: DateTime.utc(2026, 7, 12),
    );
    final api = ResearchSourceRecord(
      uri: Uri.parse('https://developer.example.co.uk/api'),
      checkedAt: DateTime.utc(2026, 7, 13),
      publishedAt: DateTime.utc(2026, 7, 12),
    );
    final regulator = ResearchSourceRecord(
      uri: Uri.parse('https://regulator.gov.uk/status'),
      checkedAt: DateTime.utc(2026, 7, 13),
      publishedAt: DateTime.utc(2026, 7, 12),
    );
    final result = const ResearchEvidenceEvaluator().assess(
      now: DateTime.utc(2026, 7, 13),
      sources: [docs, api, regulator],
      claims: const [
        ResearchClaimRecord(
          id: 'same-publisher',
          text: 'The current API behavior is documented.',
          citedUrls: [
            'https://docs.example.co.uk/guide',
            'https://developer.example.co.uk/api',
          ],
        ),
        ResearchClaimRecord(
          id: 'independent',
          text: 'The current status is independently corroborated.',
          citedUrls: [
            'https://docs.example.co.uk/guide',
            'https://regulator.gov.uk/status',
          ],
        ),
      ],
    );

    expect(docs.publisherScope, 'example.co.uk');
    expect(api.publisherScope, 'example.co.uk');
    expect(regulator.publisherScope, 'regulator.gov.uk');
    expect(
      result.singlePublisherClaims.map((assessment) => assessment.claim.id),
      ['same-publisher'],
    );
    expect(
      result.toMarkdownTable(),
      contains('Single publisher — corroborate or state limitation'),
    );
  });
}
