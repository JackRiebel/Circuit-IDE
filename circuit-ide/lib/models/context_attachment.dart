enum ContextAttachmentType {
  lsdfIndex,
  file,
  selection,
  terminal,
  gitDiff,
  diagnostics,
  symbols,
  url,
  image,
  note,
}

enum ContextAttachmentResolutionStatus {
  pending,
  resolved,
  tooLarge,
  missing,
  skipped,
}

class ContextAttachment {
  final String id;
  final ContextAttachmentType type;
  final String label;
  final String? path;
  final String? content;
  final ContextAttachmentResolutionStatus resolutionStatus;
  final int estimatedTokens;
  final String? truncationMessage;
  final DateTime createdAt;

  const ContextAttachment({
    required this.id,
    required this.type,
    required this.label,
    this.path,
    this.content,
    this.resolutionStatus = ContextAttachmentResolutionStatus.pending,
    this.estimatedTokens = 0,
    this.truncationMessage,
    required this.createdAt,
  });

  ContextAttachment copyWith({
    String? id,
    ContextAttachmentType? type,
    String? label,
    Object? path = _sentinel,
    Object? content = _sentinel,
    ContextAttachmentResolutionStatus? resolutionStatus,
    int? estimatedTokens,
    Object? truncationMessage = _sentinel,
    DateTime? createdAt,
  }) {
    return ContextAttachment(
      id: id ?? this.id,
      type: type ?? this.type,
      label: label ?? this.label,
      path: identical(path, _sentinel) ? this.path : path as String?,
      content: identical(content, _sentinel)
          ? this.content
          : content as String?,
      resolutionStatus: resolutionStatus ?? this.resolutionStatus,
      estimatedTokens: estimatedTokens ?? this.estimatedTokens,
      truncationMessage: identical(truncationMessage, _sentinel)
          ? this.truncationMessage
          : truncationMessage as String?,
      createdAt: createdAt ?? this.createdAt,
    );
  }

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
      ContextAttachmentType.image => '[Context image: $label$source]',
      ContextAttachmentType.note => '[Context note: $label]',
    };
  }

  String toPromptBlock() {
    final body = content?.trim();
    if (body == null || body.isEmpty) return promptHeader;
    final note = truncationMessage == null ? '' : '\n$truncationMessage';
    return '$promptHeader\n$body$note';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'label': label,
      'path': path,
      'content': content,
      'resolutionStatus': resolutionStatus.name,
      'estimatedTokens': estimatedTokens,
      'truncationMessage': truncationMessage,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static ContextAttachment? fromJson(Map<String, dynamic> json) {
    try {
      return ContextAttachment(
        id: json['id'] as String,
        type: ContextAttachmentType.values.firstWhere(
          (value) => value.name == json['type'],
        ),
        label: json['label'] as String,
        path: json['path'] as String?,
        content: json['content'] as String?,
        resolutionStatus: ContextAttachmentResolutionStatus.values.firstWhere(
          (value) => value.name == json['resolutionStatus'],
          orElse: () => ContextAttachmentResolutionStatus.pending,
        ),
        estimatedTokens: json['estimatedTokens'] as int? ?? 0,
        truncationMessage: json['truncationMessage'] as String?,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}

const _sentinel = Object();
