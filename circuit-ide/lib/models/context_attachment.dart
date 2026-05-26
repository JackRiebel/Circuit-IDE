enum ContextAttachmentType {
  lsdfIndex,
  file,
  selection,
  terminal,
  gitDiff,
  diagnostics,
  symbols,
  url,
  note,
}

class ContextAttachment {
  final String id;
  final ContextAttachmentType type;
  final String label;
  final String? path;
  final String? content;
  final DateTime createdAt;

  const ContextAttachment({
    required this.id,
    required this.type,
    required this.label,
    this.path,
    this.content,
    required this.createdAt,
  });

  String get promptHeader {
    final source = path == null ? '' : ' ($path)';
    return switch (type) {
      ContextAttachmentType.lsdfIndex => '[Context: L-SDF code map]',
      ContextAttachmentType.file => '[Context file: $label$source]',
      ContextAttachmentType.selection => '[Context selection: $label$source]',
      ContextAttachmentType.terminal => '[Context terminal output: $label]',
      ContextAttachmentType.gitDiff => '[Context git diff]',
      ContextAttachmentType.diagnostics => '[Context diagnostics: $label]',
      ContextAttachmentType.symbols => '[Context symbols: $label$source]',
      ContextAttachmentType.url => '[Context URL: $label$source]',
      ContextAttachmentType.note => '[Context note: $label]',
    };
  }

  String toPromptBlock() {
    final body = content?.trim();
    if (body == null || body.isEmpty) return promptHeader;
    return '$promptHeader\n$body';
  }
}
