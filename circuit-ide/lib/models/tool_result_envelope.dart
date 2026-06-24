enum ToolResultStatus { success, error, cancelled, denied, waitingForApproval }

class ToolResultEnvelope {
  final String toolCallId;
  final String toolName;
  final ToolResultStatus status;
  final String summary;
  final Map<String, dynamic> data;
  final String? stdout;
  final String? stderr;
  final List<String> artifacts;
  final List<String> changedFiles;
  final String? diagnostic;
  final bool retryable;

  const ToolResultEnvelope({
    required this.toolCallId,
    required this.toolName,
    required this.status,
    required this.summary,
    this.data = const {},
    this.stdout,
    this.stderr,
    this.artifacts = const [],
    this.changedFiles = const [],
    this.diagnostic,
    this.retryable = false,
  });

  Map<String, dynamic> toJson() => {
    'toolCallId': toolCallId,
    'toolName': toolName,
    'status': status.name,
    'summary': summary,
    'data': data,
    'stdout': stdout,
    'stderr': stderr,
    'artifacts': artifacts,
    'changedFiles': changedFiles,
    'diagnostic': diagnostic,
    'retryable': retryable,
  };

  String toPromptBlock() {
    return [
      'Tool result: $toolName (${status.name})',
      summary,
      if (changedFiles.isNotEmpty) 'Changed files: ${changedFiles.join(', ')}',
      if (stdout?.trim().isNotEmpty == true) 'stdout:\n$stdout',
      if (stderr?.trim().isNotEmpty == true) 'stderr:\n$stderr',
      if (diagnostic?.trim().isNotEmpty == true) 'diagnostic: $diagnostic',
    ].join('\n');
  }

  static ToolResultEnvelope fromJson(Map<String, dynamic> json) {
    return ToolResultEnvelope(
      toolCallId: json['toolCallId'] as String? ?? '',
      toolName: json['toolName'] as String? ?? '',
      status: ToolResultStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => ToolResultStatus.error,
      ),
      summary: json['summary'] as String? ?? '',
      data: (json['data'] as Map<String, dynamic>?) ?? const {},
      stdout: json['stdout'] as String?,
      stderr: json['stderr'] as String?,
      artifacts:
          (json['artifacts'] as List<dynamic>?)?.cast<String>() ?? const [],
      changedFiles:
          (json['changedFiles'] as List<dynamic>?)?.cast<String>() ?? const [],
      diagnostic: json['diagnostic'] as String?,
      retryable: json['retryable'] as bool? ?? false,
    );
  }
}
