class ConnectorResultProvenance {
  final String sourceId;
  final String objectReference;
  final DateTime fetchedAt;
  final List<String> permissions;
  final String citationSafeExcerpt;

  const ConnectorResultProvenance({
    required this.sourceId,
    required this.objectReference,
    required this.fetchedAt,
    this.permissions = const [],
    required this.citationSafeExcerpt,
  });

  Map<String, dynamic> toJson() => {
    'sourceId': sourceId,
    'objectReference': objectReference,
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'permissions': permissions,
    'citationSafeExcerpt': citationSafeExcerpt,
  };

  String toPromptBlock() => [
    '[Connector provenance]',
    'Source: $sourceId',
    'Reference: $objectReference',
    'Fetched: ${fetchedAt.toUtc().toIso8601String()}',
    'Permissions: ${permissions.isEmpty ? 'not declared' : permissions.join(', ')}',
    'Citation-safe excerpt:',
    citationSafeExcerpt,
    '[/Connector provenance]',
  ].join('\n');
}
