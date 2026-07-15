import 'dart:convert';

import '../enums/tool_status.dart';

class ToolCallInfo {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final ToolStatus status;
  final String? result;
  final String? error;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final bool requiresConfirmation;

  const ToolCallInfo({
    required this.id,
    required this.name,
    this.arguments = const {},
    this.status = ToolStatus.pending,
    this.result,
    this.error,
    this.startedAt,
    this.completedAt,
    this.requiresConfirmation = false,
  });

  String get argumentsJson => jsonEncode(arguments);

  ToolCallInfo copyWith({
    ToolStatus? status,
    String? result,
    String? error,
    DateTime? startedAt,
    DateTime? completedAt,
    bool? requiresConfirmation,
  }) {
    return ToolCallInfo(
      id: id,
      name: name,
      arguments: arguments,
      status: status ?? this.status,
      result: result ?? this.result,
      error: error ?? this.error,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
    );
  }
}
