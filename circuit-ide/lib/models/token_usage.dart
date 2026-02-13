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

  String get formatted {
    if (totalTokens >= 1000000) {
      return '${(totalTokens / 1000000).toStringAsFixed(1)}M';
    } else if (totalTokens >= 1000) {
      return '${(totalTokens / 1000).toStringAsFixed(1)}K';
    }
    return '$totalTokens';
  }
}
