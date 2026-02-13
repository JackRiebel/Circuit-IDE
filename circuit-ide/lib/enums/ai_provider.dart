enum AIProviderType {
  cisco('Cisco Circuit', 'Circuit AI'),
  anthropic('Anthropic', 'Claude');

  const AIProviderType(this.displayName, this.shortName);
  final String displayName;
  final String shortName;
}
