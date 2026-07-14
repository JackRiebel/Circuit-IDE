class TokenUsage {
  final int promptTokens;
  final int cachedInputTokens;
  final int completionTokens;
  final int reasoningTokens;
  final int toolTokens;
  final int totalTokens;

  const TokenUsage({
    this.promptTokens = 0,
    this.cachedInputTokens = 0,
    this.completionTokens = 0,
    this.reasoningTokens = 0,
    this.toolTokens = 0,
    this.totalTokens = 0,
  });

  TokenUsage add({
    int prompt = 0,
    int cachedInput = 0,
    int completion = 0,
    int reasoning = 0,
    int tool = 0,
  }) {
    return TokenUsage(
      promptTokens: promptTokens + prompt,
      cachedInputTokens: cachedInputTokens + cachedInput,
      completionTokens: completionTokens + completion,
      reasoningTokens: reasoningTokens + reasoning,
      toolTokens: toolTokens + tool,
      // Cached, reasoning, and tool counts are provider-specific dimensions
      // of input/output usage. They are deliberately not added again here,
      // otherwise a provider total would be double counted.
      totalTokens: totalTokens + prompt + completion,
    );
  }

  TokenUsage plus(TokenUsage other) => add(
    prompt: other.promptTokens,
    cachedInput: other.cachedInputTokens,
    completion: other.completionTokens,
    reasoning: other.reasoningTokens,
    tool: other.toolTokens,
  );

  bool get isEmpty => totalTokens == 0;
  bool get isNotEmpty => !isEmpty;

  String get formattedInputOutput {
    return 'In ${formatCount(promptTokens)} / Out ${formatCount(completionTokens)}';
  }

  String get formattedDetailedBreakdown => [
    'In ${formatCount(promptTokens)}',
    if (cachedInputTokens > 0) 'cached ${formatCount(cachedInputTokens)}',
    'Out ${formatCount(completionTokens)}',
    if (reasoningTokens > 0) 'reasoning ${formatCount(reasoningTokens)}',
    if (toolTokens > 0) 'tools ${formatCount(toolTokens)}',
  ].join(' · ');

  String get formattedWithBreakdown {
    return '${formatCount(totalTokens)} · $formattedInputOutput';
  }

  String get formatted {
    return formatCount(totalTokens);
  }

  static String formatCount(int tokens) {
    if (tokens >= 1000000) {
      return '${(tokens / 1000000).toStringAsFixed(1)}M';
    } else if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1)}K';
    }
    return '$tokens';
  }
}
