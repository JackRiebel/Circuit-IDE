enum AgentTriggerType { onFileSave, onGitCommit, onProjectOpen, periodic }

extension AgentTriggerTypeExt on AgentTriggerType {
  String get displayName => switch (this) {
        AgentTriggerType.onFileSave => 'On File Save',
        AgentTriggerType.onGitCommit => 'On Git Commit',
        AgentTriggerType.onProjectOpen => 'On Project Open',
        AgentTriggerType.periodic => 'Periodic',
      };

  String get description => switch (this) {
        AgentTriggerType.onFileSave =>
          'Triggers when a matching file is saved',
        AgentTriggerType.onGitCommit => 'Triggers after a git commit',
        AgentTriggerType.onProjectOpen => 'Triggers when the project opens',
        AgentTriggerType.periodic => 'Triggers at a set interval',
      };
}

class AgentTrigger {
  final AgentTriggerType type;
  final List<String> filePatterns;
  final bool enabled;
  final Duration? interval;

  const AgentTrigger({
    required this.type,
    this.filePatterns = const [],
    this.enabled = true,
    this.interval,
  });

  AgentTrigger copyWith({
    AgentTriggerType? type,
    List<String>? filePatterns,
    bool? enabled,
    Duration? interval,
  }) {
    return AgentTrigger(
      type: type ?? this.type,
      filePatterns: filePatterns ?? this.filePatterns,
      enabled: enabled ?? this.enabled,
      interval: interval ?? this.interval,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'file_patterns': filePatterns,
        'enabled': enabled,
        if (interval != null) 'interval_seconds': interval!.inSeconds,
      };

  factory AgentTrigger.fromJson(Map<String, dynamic> json) {
    return AgentTrigger(
      type: AgentTriggerType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => AgentTriggerType.onFileSave,
      ),
      filePatterns:
          (json['file_patterns'] as List<dynamic>?)?.cast<String>() ?? [],
      enabled: json['enabled'] as bool? ?? true,
      interval: json['interval_seconds'] != null
          ? Duration(seconds: json['interval_seconds'] as int)
          : null,
    );
  }
}
