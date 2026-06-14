enum StudioSourceArtifactKind {
  localUrl,
  file,
  diff,
  command,
  patch,
  terminalLog,
  webSource,
  toolResult,
  browserComment,
  gitChange,
  gitHunk,
  terminalSession,
  reviewComment,
  topology,
  sizing,
  lifecycle,
  chart,
  businessUseCase,
  evidence,
}

class StudioSourceArtifact {
  final String id;
  final StudioSourceArtifactKind kind;
  final String title;
  final String subtitle;
  final String value;
  final String? threadId;
  final String? requestId;
  final String? relatedMessageId;
  final String? filePath;
  final String? localUrl;
  final String? commandRunId;
  final String? patchSetId;
  final DateTime createdAt;

  const StudioSourceArtifact({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.value,
    this.threadId,
    this.requestId,
    this.relatedMessageId,
    this.filePath,
    this.localUrl,
    this.commandRunId,
    this.patchSetId,
    required this.createdAt,
  });

  StudioSourceArtifact copyWith({
    String? title,
    String? subtitle,
    String? value,
    Object? threadId = _sentinel,
    Object? requestId = _sentinel,
    Object? relatedMessageId = _sentinel,
    Object? filePath = _sentinel,
    Object? localUrl = _sentinel,
    Object? commandRunId = _sentinel,
    Object? patchSetId = _sentinel,
  }) {
    return StudioSourceArtifact(
      id: id,
      kind: kind,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      value: value ?? this.value,
      threadId: identical(threadId, _sentinel)
          ? this.threadId
          : threadId as String?,
      requestId: identical(requestId, _sentinel)
          ? this.requestId
          : requestId as String?,
      relatedMessageId: identical(relatedMessageId, _sentinel)
          ? this.relatedMessageId
          : relatedMessageId as String?,
      filePath: identical(filePath, _sentinel)
          ? this.filePath
          : filePath as String?,
      localUrl: identical(localUrl, _sentinel)
          ? this.localUrl
          : localUrl as String?,
      commandRunId: identical(commandRunId, _sentinel)
          ? this.commandRunId
          : commandRunId as String?,
      patchSetId: identical(patchSetId, _sentinel)
          ? this.patchSetId
          : patchSetId as String?,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind.name,
      'title': title,
      'subtitle': subtitle,
      'value': value,
      'threadId': threadId,
      'requestId': requestId,
      'relatedMessageId': relatedMessageId,
      'filePath': filePath,
      'localUrl': localUrl,
      'commandRunId': commandRunId,
      'patchSetId': patchSetId,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static StudioSourceArtifact? fromJson(Map<String, dynamic> json) {
    try {
      return StudioSourceArtifact(
        id: json['id'] as String,
        kind: StudioSourceArtifactKind.values.firstWhere(
          (value) => value.name == json['kind'],
          orElse: () => StudioSourceArtifactKind.toolResult,
        ),
        title: json['title'] as String? ?? 'Source',
        subtitle: json['subtitle'] as String? ?? '',
        value: json['value'] as String? ?? '',
        threadId: json['threadId'] as String?,
        requestId: json['requestId'] as String?,
        relatedMessageId: json['relatedMessageId'] as String?,
        filePath: json['filePath'] as String?,
        localUrl: json['localUrl'] as String?,
        commandRunId: json['commandRunId'] as String?,
        patchSetId: json['patchSetId'] as String?,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}

List<String> detectLocalUrls(String text) {
  final pattern = RegExp(
    r"""https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\]|[A-Za-z0-9.-]+\.local|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3})(?::\d+)?(?:/[^\s<>"\')\]]*)?""",
  );
  return pattern
      .allMatches(text)
      .map((match) => _cleanUrl(match.group(0)!))
      .where((url) {
        final uri = Uri.tryParse(url);
        return uri != null && uri.hasScheme && uri.host.isNotEmpty;
      })
      .toSet()
      .toList();
}

String _cleanUrl(String url) {
  var cleaned = url;
  while (cleaned.isNotEmpty && '.,);]'.contains(cleaned[cleaned.length - 1])) {
    cleaned = cleaned.substring(0, cleaned.length - 1);
  }
  return cleaned;
}

const _sentinel = Object();
