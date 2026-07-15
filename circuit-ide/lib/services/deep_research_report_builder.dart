import '../models/studio_source_artifact.dart';
import '../models/studio_turn.dart';
import '../models/tool_result_envelope.dart';
import 'research_evidence_evaluator.dart';

/// Builds a durable, inspectable evidence artifact from a completed Research
/// turn. Only successful `web_fetch` results with Circuit's provenance footer
/// become source records; search snippets and model-supplied URLs do not.
class DeepResearchReportBuilder {
  static const _maxReportCharacters = 32000;
  static const _maxSources = 12;

  const DeepResearchReportBuilder();

  static bool isResearchTurn(StudioTurn turn) =>
      turn.modelPrompt.contains('Research Mode is enabled.');

  DeepResearchReport? build({
    required StudioTurn turn,
    required String content,
    DateTime? now,
  }) {
    if (!isResearchTurn(turn)) return null;
    final capturedAt = (now ?? DateTime.now()).toUtc();
    final sources = _sourcesFrom(turn.toolResults, capturedAt);
    final sanitizedContent = _sanitizeUrlReferences(content);
    final claims = ResearchEvidenceEvaluator.claimsFromContent(
      sanitizedContent,
    );
    final assessment = const ResearchEvidenceEvaluator().assess(
      claims: claims,
      sources: sources.map((source) => source.record).toList(growable: false),
      now: capturedAt,
    );
    final artifact = StudioSourceArtifact(
      id: 'research-evidence-${turn.id}',
      kind: StudioSourceArtifactKind.evidence,
      title: 'Research evidence: ${_titleFor(turn.taskTitle)}',
      subtitle: _subtitle(
        sourceCount: sources.length,
        publisherScopeCount: sources
            .map((source) => source.record.publisherScope)
            .where((scope) => scope.isNotEmpty)
            .toSet()
            .length,
        unsupportedCount: assessment.unsupportedClaims.length,
        freshnessGapCount: assessment.freshnessGaps.length,
        singlePublisherClaimCount: assessment.singlePublisherClaims.length,
      ),
      value: _markdown(
        turn: turn,
        content: sanitizedContent,
        capturedAt: capturedAt,
        sources: sources,
        assessment: assessment,
      ),
      threadId: turn.threadId,
      requestId: turn.requestId,
      relatedMessageId: turn.userMessageId,
      createdAt: capturedAt,
    );
    return DeepResearchReport(
      artifact: artifact,
      directSourceCount: sources.length,
      publisherScopeCount: sources
          .map((source) => source.record.publisherScope)
          .where((scope) => scope.isNotEmpty)
          .toSet()
          .length,
      unsupportedClaimCount: assessment.unsupportedClaims.length,
      freshnessGapCount: assessment.freshnessGaps.length,
      singlePublisherClaimCount: assessment.singlePublisherClaims.length,
    );
  }

  List<_CollectedResearchSource> _sourcesFrom(
    List<ToolResultEnvelope> results,
    DateTime fallbackCheckedAt,
  ) {
    final sourcesByUrl = <String, _CollectedResearchSource>{};
    for (final result in results) {
      if (result.toolName != 'web_fetch' ||
          result.status != ToolResultStatus.success) {
        continue;
      }
      final raw = result.data['rawResult'] as String? ?? result.summary;
      final uri = _sourceUri(raw);
      if (uri == null) continue;
      final checkedAt = _checkedAt(raw) ?? fallbackCheckedAt;
      final record = ResearchSourceRecord(
        uri: uri,
        checkedAt: checkedAt,
        publishedAt: _publishedAt(raw),
        title: _sourceTitle(raw, uri),
      );
      sourcesByUrl.putIfAbsent(
        record.citationUrl,
        () => _CollectedResearchSource(record: record),
      );
      if (sourcesByUrl.length >= _maxSources) break;
    }
    return sourcesByUrl.values.toList(growable: false);
  }

  Uri? _sourceUri(String value) {
    final match = RegExp(
      r'^Source:\s*(https?://[^\s]+)',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(value);
    final uri = Uri.tryParse(match?.group(1)?.trim() ?? '');
    return uri != null && uri.hasScheme && uri.host.isNotEmpty ? uri : null;
  }

  DateTime? _checkedAt(String value) => _dateFrom(
    RegExp(
      r'^Checked:\s*(\d{4}-\d{2}-\d{2})',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(value)?.group(1),
  );

  DateTime? _publishedAt(String value) => _dateFrom(
    RegExp(
      r'^(?:Published|Updated|Date):\s*(\d{4}-\d{2}-\d{2})',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(value)?.group(1),
  );

  DateTime? _dateFrom(String? value) {
    final parsed = DateTime.tryParse(value ?? '');
    return parsed?.toUtc();
  }

  String _sourceTitle(String raw, Uri uri) {
    final heading = RegExp(
      r'^#{1,3}\s+(.+)$',
      multiLine: true,
    ).firstMatch(raw)?.group(1)?.trim();
    if (heading != null && heading.isNotEmpty) return _shorten(heading, 120);
    return uri.host;
  }

  String? _conflictReviewFrom(String content) {
    final heading = RegExp(
      r'^\s*#{1,6}\s*(?:source\s+)?conflict\s+review\s*$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(content);
    if (heading == null) return null;
    final remainder = content.substring(heading.end);
    final nextHeading = RegExp(
      r'^\s*#{1,6}\s+',
      multiLine: true,
    ).firstMatch(remainder);
    final review = nextHeading == null
        ? remainder
        : remainder.substring(0, nextHeading.start);
    final normalized = review.trim();
    return normalized.isEmpty ? null : _shorten(normalized, 6000);
  }

  String _markdown({
    required StudioTurn turn,
    required String content,
    required DateTime capturedAt,
    required List<_CollectedResearchSource> sources,
    required ResearchEvidenceAssessment assessment,
  }) {
    final conflictReview = _conflictReviewFrom(content);
    final sourceRows = sources.isEmpty
        ? '| No direct source was captured | — | — | — |'
        : sources
              .map(
                (source) =>
                    '| ${_cell(source.record.title ?? source.record.citationUrl)} '
                    '| ${source.record.citationUrl} '
                    '| ${source.record.authority().name} '
                    '| ${_dateLabel(source.record.checkedAt)} |',
              )
              .join('\n');
    final gaps = <String>[
      if (sources.isEmpty)
        'No successful direct fetch was persisted. This report cannot support factual conclusions.',
      if (sources.length == 1)
        'Only one direct source was acquired; seek an independent publisher source when the question permits it, or disclose a single-source limitation.',
      if (sources.length > 1 &&
          sources
                  .map((source) => source.record.publisherScope)
                  .where((scope) => scope.isNotEmpty)
                  .toSet()
                  .length <
              2)
        'Multiple direct pages came from one publisher scope; this is not independent corroboration.',
      if (assessment.unsupportedClaims.isNotEmpty)
        '${assessment.unsupportedClaims.length} report statement(s) have no matching fetched direct source.',
      if (assessment.freshnessGaps.isNotEmpty)
        '${assessment.freshnessGaps.length} date-sensitive statement(s) need a publication-date or freshness review.',
      if (assessment.singlePublisherClaims.isNotEmpty)
        '${assessment.singlePublisherClaims.length} date-sensitive statement(s) rely on one publisher and need corroboration or an explicit limitation.',
      if (conflictReview == null)
        'The completed answer omitted a conflict review. Compare direct-source statements before treating this report as final.',
      'Conflict resolution is a sourced human/model judgement; source authority is not treated as proof of truth.',
    ];
    return '''
# Deep research evidence report

## Research question
${_shorten(turn.displayPrompt, 1200)}

## Research plan
1. Decompose the question into material sub-questions.
2. Search broadly, then fetch direct sources subject to the project network policy and per-call approval.
3. Compare source coverage, preserve unsupported or date-sensitive gaps, and do not promote search snippets to evidence.
4. Synthesize the report with direct citations and keep the evidence table reviewable outside chat.

## Source acquisition
| Source | Direct URL | Authority signal | Checked (UTC) |
| --- | --- | --- | --- |
$sourceRows

## Evidence gaps and review
${gaps.map((gap) => '- $gap').join('\n')}

## Conflict review
${conflictReview ?? '_Missing. Compare direct-source statements, cite any disagreement, and state whether it is unresolved or why one record is preferred._'}

## Evidence table
${assessment.claims.isEmpty ? '_No report statements were suitable for deterministic claim extraction._' : assessment.toMarkdownTable()}

## Sourced report
${_shorten(content.trim(), _maxReportCharacters)}

_Evidence artifact assembled ${_dateLabel(capturedAt)} from persisted tool results. URLs are citation-sanitized; query and fragment values are excluded._
''';
  }

  String _sanitizeUrlReferences(String value) {
    return value.replaceAllMapped(RegExp(r'https?://[^\s)\]]+'), (match) {
      final raw = match.group(0)!;
      var url = raw;
      var suffix = '';
      while (url.isNotEmpty && '.,;:'.contains(url[url.length - 1])) {
        suffix = '${url[url.length - 1]}$suffix';
        url = url.substring(0, url.length - 1);
      }
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) return raw;
      final citation = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: uri.path.isEmpty ? '/' : uri.path,
      );
      return '${citation.toString()}$suffix';
    });
  }

  String _subtitle({
    required int sourceCount,
    required int publisherScopeCount,
    required int unsupportedCount,
    required int freshnessGapCount,
    required int singlePublisherClaimCount,
  }) =>
      '$sourceCount direct ${sourceCount == 1 ? 'source' : 'sources'} · '
      '$publisherScopeCount independent ${publisherScopeCount == 1 ? 'publisher' : 'publishers'} · '
      '$unsupportedCount unsupported ${unsupportedCount == 1 ? 'statement' : 'statements'} · '
      '$freshnessGapCount freshness ${freshnessGapCount == 1 ? 'review' : 'reviews'} · '
      '$singlePublisherClaimCount single-publisher ${singlePublisherClaimCount == 1 ? 'claim' : 'claims'}';

  String _titleFor(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'Untitled research' : _shorten(trimmed, 96);
  }

  String _dateLabel(DateTime value) =>
      value.toUtc().toIso8601String().substring(0, 10);

  String _cell(String value) =>
      value.replaceAll('|', r'\|').replaceAll('\n', ' ').trim();

  String _shorten(String value, int maxLength) {
    final normalized = value.trim();
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength - 1).trimRight()}…';
  }
}

class DeepResearchReport {
  final StudioSourceArtifact artifact;
  final int directSourceCount;
  final int publisherScopeCount;
  final int unsupportedClaimCount;
  final int freshnessGapCount;
  final int singlePublisherClaimCount;

  const DeepResearchReport({
    required this.artifact,
    required this.directSourceCount,
    required this.publisherScopeCount,
    required this.unsupportedClaimCount,
    required this.freshnessGapCount,
    required this.singlePublisherClaimCount,
  });
}

class _CollectedResearchSource {
  final ResearchSourceRecord record;

  const _CollectedResearchSource({required this.record});
}
