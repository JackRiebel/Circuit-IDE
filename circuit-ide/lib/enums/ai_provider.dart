enum AIProviderType {
  cisco('Circuit Company AI', 'Circuit');

  const AIProviderType(this.displayName, this.shortName);
  final String displayName;
  final String shortName;
}
