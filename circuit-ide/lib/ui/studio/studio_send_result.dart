import '../../models/agent_preflight.dart';
import '../../models/studio_thread.dart';

enum StudioSendStatus { sent, blocked, failed, completed }

class StudioSendResult {
  final StudioSendStatus status;
  final String? requestId;
  final String? threadId;
  final String? taskId;
  final AgentPreflightResult? preflight;
  final StudioContextSummary? contextSummary;
  final String? error;
  final bool registeredRequest;
  final bool blockedByActiveRequest;

  const StudioSendResult._(
    this.status, {
    this.requestId,
    this.threadId,
    this.taskId,
    this.preflight,
    this.contextSummary,
    this.error,
    this.registeredRequest = false,
    this.blockedByActiveRequest = false,
  });

  const StudioSendResult.sent({
    String? requestId,
    String? threadId,
    String? taskId,
    StudioContextSummary? contextSummary,
    bool registeredRequest = false,
  }) : this._(
         StudioSendStatus.sent,
         requestId: requestId,
         threadId: threadId,
         taskId: taskId,
         contextSummary: contextSummary,
         registeredRequest: registeredRequest,
       );

  const StudioSendResult.blocked(
    String message, {
    String? requestId,
    String? threadId,
    String? taskId,
    AgentPreflightResult? preflight,
    StudioContextSummary? contextSummary,
    bool blockedByActiveRequest = false,
  }) : this._(
         StudioSendStatus.blocked,
         requestId: requestId,
         threadId: threadId,
         taskId: taskId,
         preflight: preflight,
         contextSummary: contextSummary,
         error: message,
         blockedByActiveRequest: blockedByActiveRequest,
       );

  const StudioSendResult.failed(
    String message, {
    String? requestId,
    String? threadId,
    String? taskId,
    StudioContextSummary? contextSummary,
  }) : this._(
         StudioSendStatus.failed,
         requestId: requestId,
         threadId: threadId,
         taskId: taskId,
         contextSummary: contextSummary,
         error: message,
       );

  const StudioSendResult.completed({
    String? requestId,
    String? threadId,
    String? taskId,
    StudioContextSummary? contextSummary,
    bool registeredRequest = false,
  }) : this._(
         StudioSendStatus.completed,
         requestId: requestId,
         threadId: threadId,
         taskId: taskId,
         contextSummary: contextSummary,
         registeredRequest: registeredRequest,
       );
}
