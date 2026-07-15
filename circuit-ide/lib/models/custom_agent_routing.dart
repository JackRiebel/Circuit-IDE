import 'agent_config_model.dart';
import 'turn_intent.dart';

/// A deterministic, inspectable custom-agent routing decision. The router
/// never grants capabilities: it only chooses from already enabled and valid
/// Agent Library records, and Studio validates the result again before send.
class CustomAgentSelection {
  final String? requestedAgentId;
  final AgentConfigModel? agent;
  final bool isAuto;
  final double confidence;
  final String rationale;
  final List<String> matchedTerms;

  const CustomAgentSelection({
    this.requestedAgentId,
    this.agent,
    required this.isAuto,
    required this.confidence,
    required this.rationale,
    this.matchedTerms = const [],
  });

  bool get usesGeneralAgent => agent == null;

  String get label => agent?.name ?? 'General';

  String get confidenceLabel => '${(confidence * 100).round()}%';
}

class CustomAgentRouter {
  static const _minimumConfidence = 0.60;

  const CustomAgentRouter();

  CustomAgentSelection route({
    required String prompt,
    required TurnIntent intent,
    required Iterable<AgentConfigModel> configs,
    String? explicitAgentId,
    bool auto = false,
  }) {
    final normalizedExplicit = explicitAgentId?.trim();
    if (normalizedExplicit != null && normalizedExplicit.isNotEmpty) {
      final agent = _byId(configs, normalizedExplicit);
      return CustomAgentSelection(
        requestedAgentId: normalizedExplicit,
        agent: agent,
        isAuto: false,
        confidence: agent == null ? 0 : 1,
        rationale: agent == null
            ? 'The explicitly selected agent is unavailable.'
            : 'User explicitly selected ${agent.name}; automatic routing was not used.',
      );
    }
    if (!auto) {
      return const CustomAgentSelection(
        isAuto: false,
        confidence: 1,
        rationale: 'General Studio agent selected by the user.',
      );
    }

    final candidates = configs
        .where(
          (config) =>
              config.enabled &&
              config.validate().isEmpty &&
              config.allowedIntents.contains(intent),
        )
        .toList(growable: false);
    if (candidates.isEmpty) {
      return const CustomAgentSelection(
        isAuto: true,
        confidence: 0,
        rationale:
            'Auto kept the General Studio agent because no enabled agent supports this request type.',
      );
    }

    final promptTerms = _terms(prompt);
    final scored =
        candidates
            .map((config) => _ScoredCandidate(config, promptTerms))
            .where((candidate) => candidate.score > 0)
            .toList()
          ..sort((left, right) {
            final byScore = right.score.compareTo(left.score);
            return byScore != 0
                ? byScore
                : left.config.name.compareTo(right.config.name);
          });
    if (scored.isEmpty) {
      return const CustomAgentSelection(
        isAuto: true,
        confidence: 0,
        rationale:
            'Auto kept the General Studio agent because no agent profile matched the request.',
      );
    }

    final winner = scored.first;
    final runnerUpScore = scored.length > 1 ? scored[1].score : 0;
    final confidence = _confidence(winner.score, runnerUpScore);
    if (confidence < _minimumConfidence) {
      return CustomAgentSelection(
        isAuto: true,
        confidence: confidence,
        rationale:
            'Auto kept the General Studio agent at ${_percent(confidence)} confidence. '
            'The best candidate was ${winner.config.name} (${winner.matchedTerms.join(', ')}); choose it explicitly if that is intended.',
        matchedTerms: winner.matchedTerms,
      );
    }
    return CustomAgentSelection(
      agent: winner.config,
      isAuto: true,
      confidence: confidence,
      rationale:
          'Auto selected ${winner.config.name} at ${_percent(confidence)} confidence '
          'from matching terms: ${winner.matchedTerms.join(', ')}.',
      matchedTerms: winner.matchedTerms,
    );
  }

  AgentConfigModel? _byId(Iterable<AgentConfigModel> configs, String id) {
    for (final config in configs) {
      if (config.id == id) return config;
    }
    return null;
  }

  static double _confidence(int winnerScore, int runnerUpScore) {
    if (winnerScore < 2) return 0.45;
    final margin = winnerScore - runnerUpScore;
    final raw = 0.52 + winnerScore * 0.10 + margin * 0.08;
    return raw.clamp(0.0, 0.95).toDouble();
  }

  static String _percent(double confidence) => '${(confidence * 100).round()}%';
}

class _ScoredCandidate {
  final AgentConfigModel config;
  final List<String> matchedTerms;
  final int score;

  factory _ScoredCandidate(AgentConfigModel config, Set<String> promptTerms) {
    final profileTerms = _terms(
      '${config.name} ${config.description} ${config.systemPrompt}',
    );
    final nameTerms = _terms(config.name);
    final matched = promptTerms.intersection(profileTerms).toList()..sort();
    final nameMatches = promptTerms.intersection(nameTerms).length;
    return _ScoredCandidate._(
      config: config,
      matchedTerms: matched,
      score: matched.length + nameMatches,
    );
  }

  const _ScoredCandidate._({
    required this.config,
    required this.matchedTerms,
    required this.score,
  });
}

Set<String> _terms(String value) {
  const stopWords = {
    'a',
    'an',
    'and',
    'are',
    'as',
    'at',
    'be',
    'by',
    'can',
    'current',
    'do',
    'for',
    'from',
    'help',
    'i',
    'in',
    'is',
    'it',
    'my',
    'of',
    'on',
    'or',
    'please',
    'the',
    'this',
    'to',
    'use',
    'with',
    'you',
    'your',
  };
  return value
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((term) => term.length >= 3 && !stopWords.contains(term))
      .toSet();
}
