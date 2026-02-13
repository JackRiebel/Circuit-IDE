import 'dart:convert';

class AgentConfigModel {
  final String id;
  final String name;
  final String description;
  final String systemPrompt;
  final Set<String> allowedTools; // empty = all tools
  final String model;
  final bool autoApprove;
  final DateTime createdAt;

  const AgentConfigModel({
    required this.id,
    required this.name,
    this.description = '',
    this.systemPrompt = '',
    this.allowedTools = const {},
    this.model = 'gpt-4.1',
    this.autoApprove = false,
    required this.createdAt,
  });

  AgentConfigModel copyWith({
    String? id,
    String? name,
    String? description,
    String? systemPrompt,
    Set<String>? allowedTools,
    String? model,
    bool? autoApprove,
    DateTime? createdAt,
  }) {
    return AgentConfigModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      allowedTools: allowedTools ?? this.allowedTools,
      model: model ?? this.model,
      autoApprove: autoApprove ?? this.autoApprove,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'system_prompt': systemPrompt,
        'allowed_tools': allowedTools.toList(),
        'model': model,
        'auto_approve': autoApprove,
        'created_at': createdAt.toIso8601String(),
      };

  factory AgentConfigModel.fromJson(Map<String, dynamic> json) {
    return AgentConfigModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      systemPrompt: json['system_prompt'] as String? ?? '',
      allowedTools: (json['allowed_tools'] as List<dynamic>?)
              ?.cast<String>()
              .toSet() ??
          {},
      model: json['model'] as String? ?? 'gpt-4o',
      autoApprove: json['auto_approve'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}
