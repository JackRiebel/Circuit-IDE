class TokenUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  const TokenUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
  });

  TokenUsage add({int prompt = 0, int completion = 0}) {
    return TokenUsage(
      promptTokens: promptTokens + prompt,
      completionTokens: completionTokens + completion,
      totalTokens: totalTokens + prompt + completion,
    );
  }

  bool get isEmpty => totalTokens == 0;
  bool get isNotEmpty => !isEmpty;

  String get formattedInputOutput {
    return 'In ${formatCount(promptTokens)} / Out ${formatCount(completionTokens)}';
  }

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
