import 'dart:async';

import 'agent_tool_permission.dart';
import 'tool_call_info.dart';

class ConfirmationRequest {
  static const defaultLifetime = Duration(minutes: 5);

  final String id;
  final ToolCallInfo toolCall;
  final String preview;
  final List<String> warnings;
  final ToolPermissionReason risk;

  /// Stable, non-secret authorization key for the exact reviewed action.
  final String normalizedAction;
  final DateTime timestamp;
  final DateTime expiresAt;
  ApprovalGrant? grantedScope;
  bool _expired = false;
  final Completer<bool> _completer = Completer<bool>();

  ConfirmationRequest({
    required this.id,
    required this.toolCall,
    required this.preview,
    this.warnings = const [],
    this.risk = ToolPermissionReason.unknownTool,
    this.normalizedAction = '',
    DateTime? timestamp,
    DateTime? expiresAt,
  }) : timestamp = timestamp ?? DateTime.now(),
       expiresAt =
           expiresAt ?? (timestamp ?? DateTime.now()).add(defaultLifetime);

  Future<bool> get response => _completer.future;

  bool get isExpired => _expired || DateTime.now().isAfter(expiresAt);

  void approve({ApprovalGrant scope = ApprovalGrant.once}) {
    if (isExpired) {
      expire();
      return;
    }
    grantedScope = scope;
    if (!_completer.isCompleted) _completer.complete(true);
  }

  void reject() {
    if (!_completer.isCompleted) _completer.complete(false);
  }

  void expire() {
    _expired = true;
    if (!_completer.isCompleted) _completer.complete(false);
  }
}
