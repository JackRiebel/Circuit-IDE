import 'dart:async';

import 'tool_call_info.dart';

class ConfirmationRequest {
  final String id;
  final ToolCallInfo toolCall;
  final String preview;
  final List<String> warnings;
  final DateTime timestamp;
  final Completer<bool> _completer = Completer<bool>();

  ConfirmationRequest({
    required this.id,
    required this.toolCall,
    required this.preview,
    this.warnings = const [],
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Future<bool> get response => _completer.future;

  void approve() {
    if (!_completer.isCompleted) _completer.complete(true);
  }

  void reject() {
    if (!_completer.isCompleted) _completer.complete(false);
  }
}
