import 'dart:async';

import 'package:uuid/uuid.dart';

import '../core/utils/logger.dart';
import '../enums/event_type.dart';
import '../enums/message_role.dart';
import '../models/chat_message.dart';
import '../models/provider_lifecycle_event.dart';
import '../models/reviewed_edit.dart';
import '../models/studio_turn.dart';
import '../models/token_usage.dart';
import '../models/tool_call_info.dart';
import '../models/tool_result_envelope.dart';
import '../models/agent_tool_permission.dart';
import '../models/accepted_plan_context.dart';
import '../models/turn_intent.dart';
import '../services/event_bus.dart';
import 'context/context_manager.dart';
import 'providers/provider_interface.dart';
import 'streaming/streaming_response.dart';
import 'tools/tool_executor.dart';
import 'tools/tool_registry.dart';
import 'turn_outcome_validator.dart';

class StudioTurnRunnerResult {
  final String content;
  final TokenUsage usage;
  final List<ToolCallInfo> toolCalls;
  final AcceptedPlanState acceptedPlanState;

  const StudioTurnRunnerResult({
    required this.content,
    required this.usage,
    required this.toolCalls,
    this.acceptedPlanState = AcceptedPlanState.none,
  });
}

/// Request-local Studio runner. It intentionally does not mutate
/// `CircuitAgent.history`; Studio threads provide the request history.
class StudioTurnRunner {
  final AIProvider provider;
  final String workingDir;
  final EventBus events;
  final String model;
  final ToolExecutor toolExecutor;
  final ApprovalGrant Function()? approvalGrantProvider;
  final ContextManager _contextManager = ContextManager();
  final TurnOutcomeValidator _outcomeValidator = const TurnOutcomeValidator();

  static const _uuid = Uuid();
  bool _isCancelled = false;

  StudioTurnRunner({
    required this.provider,
    required this.workingDir,
    required this.events,
    required this.model,
    required this.toolExecutor,
    this.approvalGrantProvider,
  });

  void cancel() {
    _isCancelled = true;
    provider.cancelActiveRequest();
    toolExecutor.cancelActiveCommands();
  }

  Future<StudioTurnRunnerResult> run({
    required String requestId,
    String? turnId,
    required String userMessage,
    required List<ChatMessage> history,
    required AgentToolMode toolMode,
    required TurnIntent intent,
    AcceptedPlanContext? acceptedPlan,
  }) async {
    _isCancelled = false;
    final systemPrompt = _studioSystemPrompt(
      intent: intent,
      toolMode: toolMode,
      hasAcceptedPlan: acceptedPlan != null,
    );
    final effectiveUserMessage = acceptedPlan == null
        ? userMessage
        : _messageWithAcceptedPlan(userMessage, acceptedPlan);
    final requestHistory = List<ChatMessage>.of(history)
      ..add(
        ChatMessage(
          id: _uuid.v4(),
          role: MessageRole.user,
          content: effectiveUserMessage,
          timestamp: DateTime.now(),
        ),
      );

    events.emit(EventType.messageStarted, {'requestId': requestId});
    toolExecutor.beginTurn();

    var fullResponse = '';
    var usage = const TokenUsage();
    var totalUsage = const TokenUsage();
    final allToolCalls = <ToolCallInfo>[];
    final allToolResults = <ToolResultEnvelope>[];
    final seenToolRounds = <String>{};
    var noProgressRounds = 0;
    var sawAnyText = false;
    var sawAnyTool = false;
    var sawAnyFirstByte = false;
    var sawCancelledDiagnostic = false;
    var sawTimeoutDiagnostic = false;
    var emittedNoFirstByteDiagnostic = false;
    var toolOnlyNonTerminalRounds = 0;
    String? pendingRepairValidationMessage;

    try {
      final maxOutcomeAttempts =
          _allowsOutcomeRepair(intent: intent, toolMode: toolMode) ? 2 : 1;
      for (
        var outcomeAttempt = 0;
        outcomeAttempt < maxOutcomeAttempts;
        outcomeAttempt++
      ) {
        if (outcomeAttempt > 0) {
          fullResponse = '';
          usage = const TokenUsage();
          allToolCalls.clear();
          allToolResults.clear();
          seenToolRounds.clear();
          noProgressRounds = 0;
          sawAnyText = false;
          sawAnyTool = false;
          requestHistory.add(
            ChatMessage(
              id: _uuid.v4(),
              role: MessageRole.user,
              content: _outcomeRepairPrompt(
                intent: intent,
                toolMode: toolMode,
                acceptedPlan: acceptedPlan,
              ),
              timestamp: DateTime.now(),
            ),
          );
          toolOnlyNonTerminalRounds = 0;
        }

        final maxIterations = toolMode == AgentToolMode.plan ? 4 : 6;
        for (var iteration = 0; iteration < maxIterations; iteration++) {
          final response = StreamingResponse();
          final phase = _phaseFor(
            toolMode,
            iteration + (outcomeAttempt > 0 ? 1 : 0),
            hasAcceptedPlan: acceptedPlan != null,
          );
          final tools = ToolRegistry.toolsForModeAndPhase(toolMode, phase);
          toolExecutor.setPermissionRequest(
            ToolPermissionRequest(
              intent: intent,
              phase: _permissionPhaseFor(phase),
              approvalGrant:
                  approvalGrantProvider?.call() ?? ApprovalGrant.none,
              hasAcceptedPlan: acceptedPlan != null,
            ),
          );
          _emitLifecycle(
            requestId,
            turnId,
            ProviderLifecycleEventKind.toolExposure,
            detail:
                'Exposed ${tools.length} ${toolMode.name}/${phase.name} tools for this turn.',
          );

          var sawFirstByte = false;
          var sawFirstText = false;
          var sawFirstTool = false;
          await for (final chunk in provider.chat(
            _contextManager.optimizeContext(requestHistory),
            model: model,
            tools: tools,
            systemPrompt: systemPrompt,
            maxTokens: 4096,
          )) {
            if (_isCancelled) break;
            final lifecycleOnly =
                chunk.lifecycleKind != null &&
                chunk.content == null &&
                chunk.toolCallIndex == null &&
                chunk.finishReason == null &&
                !chunk.isDone &&
                chunk.promptTokens == 0 &&
                chunk.completionTokens == 0;
            if (!sawFirstByte &&
                !lifecycleOnly &&
                !chunk.isDone &&
                chunk.lifecycleKind != ProviderLifecycleEventKind.firstByte) {
              sawFirstByte = true;
              sawAnyFirstByte = true;
              _emitLifecycle(
                requestId,
                turnId,
                ProviderLifecycleEventKind.firstByte,
              );
            }
            if (chunk.lifecycleKind != null) {
              if (chunk.lifecycleKind == ProviderLifecycleEventKind.firstByte) {
                sawFirstByte = true;
                sawAnyFirstByte = true;
              } else if (chunk.lifecycleKind ==
                  ProviderLifecycleEventKind.noFirstByte) {
                emittedNoFirstByteDiagnostic = true;
              } else if (chunk.lifecycleKind ==
                  ProviderLifecycleEventKind.cancelled) {
                sawCancelledDiagnostic = true;
              } else if (chunk.lifecycleKind ==
                  ProviderLifecycleEventKind.timeout) {
                sawTimeoutDiagnostic = true;
              } else if (chunk.lifecycleKind ==
                  ProviderLifecycleEventKind.firstTextDelta) {
                sawFirstText = true;
                sawAnyText = true;
              } else if (chunk.lifecycleKind ==
                  ProviderLifecycleEventKind.firstToolDelta) {
                sawFirstTool = true;
                sawAnyTool = true;
              }
              _emitLifecycle(
                requestId,
                turnId,
                chunk.lifecycleKind!,
                detail: chunk.lifecycleDetail,
              );
            }
            final content = chunk.content;
            if (content != null && content.isNotEmpty) {
              if (!sawFirstText) {
                sawFirstText = true;
                sawAnyText = true;
                _emitLifecycle(
                  requestId,
                  turnId,
                  ProviderLifecycleEventKind.firstTextDelta,
                );
              }
              response.addContent(content);
              events.emit(EventType.messageChunk, {
                'content': content,
                'requestId': requestId,
              });
            }
            if (chunk.toolCallIndex != null) {
              if (!sawFirstTool) {
                sawFirstTool = true;
                sawAnyTool = true;
                _emitLifecycle(
                  requestId,
                  turnId,
                  ProviderLifecycleEventKind.firstToolDelta,
                );
              }
              response.addToolCallChunk(
                index: chunk.toolCallIndex!,
                id: chunk.toolCallId,
                name: chunk.toolCallName,
                arguments: chunk.toolCallArguments,
              );
            }
            if (chunk.promptTokens > 0 || chunk.completionTokens > 0) {
              response.updateUsage(chunk.promptTokens, chunk.completionTokens);
            }
            if (chunk.finishReason != null) {
              response.finishReason = chunk.finishReason;
            }
          }

          if (_isCancelled) {
            _emitLifecycle(
              requestId,
              turnId,
              ProviderLifecycleEventKind.cancelled,
            );
            events.emit(EventType.messageError, {
              'error': 'Request cancelled.',
              'requestId': requestId,
            });
            throw const StudioTurnCancelledException();
          }
          if (!sawFirstByte &&
              outcomeAttempt > 0 &&
              pendingRepairValidationMessage != null) {
            throw StudioTurnOutcomeValidationException(
              pendingRepairValidationMessage,
            );
          }
          if (!sawFirstByte) {
            if (!emittedNoFirstByteDiagnostic) {
              _emitLifecycle(
                requestId,
                turnId,
                ProviderLifecycleEventKind.noFirstByte,
                detail:
                    'Circuit AI returned no bytes before the request completed.',
              );
              emittedNoFirstByteDiagnostic = true;
            }
            throw StateError(
              'Circuit AI returned no bytes for this request. Check the connector connection or retry.',
            );
          }

          usage = TokenUsage(
            promptTokens: response.promptTokens,
            completionTokens: response.completionTokens,
            totalTokens: response.totalTokens,
          );
          if (usage.isNotEmpty) {
            totalUsage = totalUsage.add(
              prompt: usage.promptTokens,
              completion: usage.completionTokens,
            );
            events.emit(EventType.tokensUpdated, {
              'lastUsage': totalUsage,
              'requestId': requestId,
            });
          }

          final malformedToolCalls = response.toolCalls
              .where(
                (toolCall) =>
                    toolCall.name.trim().isNotEmpty &&
                    toolCall.argumentsBuffer.trim().isNotEmpty &&
                    !toolCall.isComplete,
              )
              .toList(growable: false);
          if (malformedToolCalls.isNotEmpty) {
            final names = malformedToolCalls
                .map((call) => call.name.trim())
                .join(', ');
            final message =
                'Circuit AI returned malformed tool arguments for: $names. I stopped before running any tool.';
            _emitLifecycle(
              requestId,
              turnId,
              ProviderLifecycleEventKind.malformedChunk,
              detail: message,
            );
            throw StateError(message);
          }

          final toolCallInfos = response.toolCalls
              .where((toolCall) => toolCall.name.trim().isNotEmpty)
              .map(
                (toolCall) => ToolCallInfo(
                  id: toolCall.id.isEmpty ? _uuid.v4() : toolCall.id,
                  name: toolCall.name,
                  arguments: toolCall.arguments,
                ),
              )
              .toList();
          final unavailableToolCalls = _unavailableToolCalls(
            toolCallInfos,
            tools,
          );
          if (unavailableToolCalls.isNotEmpty) {
            final names = unavailableToolCalls
                .map((call) => call.name)
                .join(', ');
            final message =
                'Circuit AI requested unavailable tool(s) for this ${toolMode.name}/${phase.name} phase: $names. I stopped the turn before any unavailable action could run.';
            _emitLifecycle(
              requestId,
              turnId,
              ProviderLifecycleEventKind.unavailableTool,
              detail: message,
            );
            throw StateError(message);
          }
          if (response.content.trim().isEmpty && toolCallInfos.isEmpty) {
            if (fullResponse.trim().isEmpty) {
              _emitLifecycle(
                requestId,
                turnId,
                ProviderLifecycleEventKind.noTextOrTool,
                detail:
                    'Circuit AI completed without text deltas or tool calls.',
              );
              throw StateError(
                'Circuit AI completed without text or tool calls. The connector may have returned an unsupported response.',
              );
            }
            break;
          }

          requestHistory.add(
            ChatMessage(
              id: _uuid.v4(),
              role: MessageRole.assistant,
              content: response.content,
              timestamp: DateTime.now(),
              toolCalls: toolCallInfos,
            ),
          );
          fullResponse += response.content;
          allToolCalls.addAll(toolCallInfos);

          if (toolCallInfos.isEmpty) break;

          final roundKey = toolCallInfos
              .map((call) => '${call.name}:${call.arguments}')
              .join('|');
          final repeatedRound = !seenToolRounds.add(roundKey);
          if (response.content.trim().isEmpty && repeatedRound) {
            noProgressRounds++;
          } else {
            noProgressRounds = 0;
          }
          if (noProgressRounds >= 2) {
            const stopMessage =
                'I’m stopping because the same tool step repeated without new progress. Tell me what to inspect next, or switch to Plan mode for a smaller reviewable plan.';
            fullResponse = fullResponse.trim().isEmpty
                ? stopMessage
                : '$fullResponse\n\n$stopMessage';
            requestHistory.add(
              ChatMessage(
                id: _uuid.v4(),
                role: MessageRole.assistant,
                content: stopMessage,
                timestamp: DateTime.now(),
              ),
            );
            break;
          }

          final results = await toolExecutor.executeToolCalls(toolCallInfos);
          for (final result in results) {
            final envelope = result.structured;
            if (result.wasCancelled ||
                envelope.status == ToolResultStatus.cancelled) {
              throw StateError(envelope.summary);
            }
            if (envelope.status == ToolResultStatus.denied) {
              throw StateError(envelope.summary);
            }
            events.emit(EventType.toolResultRecorded, {
              'requestId': requestId,
              'result': envelope,
            });
            allToolResults.add(envelope);
            requestHistory.add(
              ChatMessage(
                id: _uuid.v4(),
                role: MessageRole.tool,
                content: envelope.toPromptBlock(),
                timestamp: DateTime.now(),
                toolCallId: result.toolCallId,
              ),
            );
          }
          Logger.info(
            'Studio turn tool calls completed, iteration ${iteration + 1}',
            'StudioTurnRunner',
          );
          final terminalProposal = _hasTerminalProposalResult(
            intent: intent,
            toolMode: toolMode,
            results: results,
          );
          if (terminalProposal) {
            break;
          }
          if (response.content.trim().isEmpty) {
            toolOnlyNonTerminalRounds++;
          } else {
            toolOnlyNonTerminalRounds = 0;
          }
          if (toolOnlyNonTerminalRounds >= 3) {
            final question = _boundedInspectionQuestion(acceptedPlan);
            fullResponse = question;
            requestHistory.add(
              ChatMessage(
                id: _uuid.v4(),
                role: MessageRole.assistant,
                content: question,
                timestamp: DateTime.now(),
              ),
            );
            break;
          }
        }

        final successfulPatchProposal = _hasSuccessfulPatchProposal(
          allToolResults,
        );
        if (!sawAnyText && sawAnyTool && !successfulPatchProposal) {
          _emitLifecycle(
            requestId,
            turnId,
            ProviderLifecycleEventKind.toolOnly,
            detail: 'Circuit AI returned tool calls without assistant text.',
          );
        } else if (!sawAnyText && !sawAnyTool) {
          _emitLifecycle(
            requestId,
            turnId,
            ProviderLifecycleEventKind.noTextOrTool,
            detail: 'Circuit AI returned no assistant text or tool calls.',
          );
        }
        if (fullResponse.trim().isEmpty &&
            (allToolResults.isNotEmpty || allToolCalls.isNotEmpty) &&
            !_hasSuccessfulPatchProposal(allToolResults) &&
            intent == TurnIntent.code &&
            (toolMode == AgentToolMode.code || toolMode == AgentToolMode.fix)) {
          final question = _boundedInspectionQuestion(acceptedPlan);
          fullResponse = question;
          requestHistory.add(
            ChatMessage(
              id: _uuid.v4(),
              role: MessageRole.assistant,
              content: question,
              timestamp: DateTime.now(),
            ),
          );
        }
        var validation = _outcomeValidator.validate(
          intent: intent,
          toolMode: toolMode,
          content: fullResponse,
          toolCalls: allToolCalls,
          toolResults: allToolResults,
          acceptedPlan: acceptedPlan,
          taskPrompt: userMessage,
        );
        if (!validation.canComplete &&
            fullResponse.trim().isEmpty &&
            sawAnyTool &&
            intent == TurnIntent.code &&
            (toolMode == AgentToolMode.code || toolMode == AgentToolMode.fix)) {
          final question = _boundedInspectionQuestion(acceptedPlan);
          fullResponse = question;
          requestHistory.add(
            ChatMessage(
              id: _uuid.v4(),
              role: MessageRole.assistant,
              content: question,
              timestamp: DateTime.now(),
            ),
          );
          validation = _outcomeValidator.validate(
            intent: intent,
            toolMode: toolMode,
            content: fullResponse,
            toolCalls: allToolCalls,
            toolResults: allToolResults,
            acceptedPlan: acceptedPlan,
            taskPrompt: userMessage,
          );
        }
        if (!validation.canComplete) {
          if (outcomeAttempt + 1 < maxOutcomeAttempts &&
              _canRepairOutcome(
                validation,
                content: fullResponse,
                toolCalls: allToolCalls,
                toolResults: allToolResults,
              )) {
            _emitLifecycle(
              requestId,
              turnId,
              ProviderLifecycleEventKind.outcomeRepair,
              detail:
                  'Runtime rejected the model outcome and requested one structured repair attempt: ${validation.userMessage ?? 'invalid outcome'}',
            );
            pendingRepairValidationMessage = validation.userMessage;
            continue;
          }
          throw StudioTurnOutcomeValidationException(
            _failedOutcomeMessage(
              validation,
              pendingRepairValidationMessage: pendingRepairValidationMessage,
            ),
          );
        }
        if (validation.status == TurnOutcomeValidationStatus.blockingQuestion &&
            (validation.userMessage?.trim().isNotEmpty ?? false)) {
          fullResponse = validation.userMessage!.trim();
        }
        _emitLifecycle(
          requestId,
          turnId,
          ProviderLifecycleEventKind.completed,
          detail: [
            if (!sawAnyText && successfulPatchProposal)
              'Patch proposal produced through structured tool output'
            else if (!sawAnyText)
              'No text delta received',
            if (!sawAnyTool) 'No tool delta received',
          ].join(' · '),
        );
        events.emit(EventType.messageCompleted, {
          'content': fullResponse,
          'toolCalls': allToolCalls,
          'lastUsage': usage,
          'requestId': requestId,
        });
        return StudioTurnRunnerResult(
          content: fullResponse,
          usage: totalUsage,
          toolCalls: allToolCalls,
          acceptedPlanState: validation.acceptedPlanState,
        );
      }
      throw const StudioTurnOutcomeValidationException(
        'Turn outcome was invalid after a repair attempt.',
      );
    } catch (error) {
      if (sawCancelledDiagnostic || _isCancellationError(error)) {
        throw const StudioTurnCancelledException();
      }
      if (error is! StudioTurnCancelledException) {
        final message = error.toString().replaceFirst('Exception: ', '');
        final isOutcomeValidationError =
            error is StudioTurnOutcomeValidationException;
        if (!isOutcomeValidationError &&
            !sawAnyFirstByte &&
            !emittedNoFirstByteDiagnostic &&
            !sawTimeoutDiagnostic) {
          _emitLifecycle(
            requestId,
            turnId,
            ProviderLifecycleEventKind.noFirstByte,
            detail:
                'Circuit AI failed before returning response bytes: $message',
          );
        }
        _emitLifecycle(
          requestId,
          turnId,
          ProviderLifecycleEventKind.failed,
          detail: isOutcomeValidationError
              ? 'Runtime rejected the model outcome: $message'
              : message,
        );
        if (!isOutcomeValidationError) {
          events.emit(EventType.messageError, {
            'error': message,
            'requestId': requestId,
          });
        }
      }
      rethrow;
    }
  }

  bool _allowsOutcomeRepair({
    required TurnIntent intent,
    required AgentToolMode toolMode,
  }) {
    if (intent == TurnIntent.plan) return true;
    if (intent == TurnIntent.code &&
        (toolMode == AgentToolMode.code || toolMode == AgentToolMode.fix)) {
      return true;
    }
    return false;
  }

  bool _canRepairOutcome(
    TurnOutcomeValidationResult validation, {
    required String content,
    required List<ToolCallInfo> toolCalls,
    required List<ToolResultEnvelope> toolResults,
  }) {
    if (validation.status != TurnOutcomeValidationStatus.invalid ||
        !(validation.userMessage?.trim().isNotEmpty ?? false)) {
      return false;
    }
    if (validation.userMessage!.toLowerCase().contains('approval')) {
      return false;
    }
    if (validation.userMessage!.toLowerCase().contains('plan-only')) {
      return false;
    }
    final toolNames = {
      ...toolCalls.map((call) => call.name),
      ...toolResults.map((result) => result.toolName),
    };
    if (toolNames.isNotEmpty &&
        !toolNames.every(_isRepairableAfterInvalidOutcome)) {
      return false;
    }
    if (content.trim().isEmpty && toolNames.isEmpty) return false;
    return !_containsApprovalLanguage(content);
  }

  String _failedOutcomeMessage(
    TurnOutcomeValidationResult validation, {
    String? pendingRepairValidationMessage,
  }) {
    final message = validation.userMessage ?? 'Turn outcome was invalid.';
    if (pendingRepairValidationMessage == null ||
        pendingRepairValidationMessage.trim().isEmpty) {
      return message;
    }
    final normalized = message.toLowerCase();
    final repairMaskedOriginalReason =
        normalized.contains('approval') ||
        normalized.contains('type approval') ||
        normalized.contains('type approve') ||
        normalized.contains('approval text');
    return repairMaskedOriginalReason
        ? pendingRepairValidationMessage
        : message;
  }

  bool _containsApprovalLanguage(String content) {
    final normalized = content.toLowerCase();
    return normalized.contains('reply with "approve"') ||
        normalized.contains("reply with 'approve'") ||
        normalized.contains('type "approve"') ||
        normalized.contains("type 'approve'") ||
        normalized.contains('say "approve"') ||
        normalized.contains("say 'approve'");
  }

  bool _isRepairableAfterInvalidOutcome(String toolName) {
    return ToolRegistry.isReadOnlyIncludingMcp(toolName) ||
        toolName == 'propose_patch';
  }

  bool _hasTerminalProposalResult({
    required TurnIntent intent,
    required AgentToolMode toolMode,
    required List<ToolExecutionResult> results,
  }) {
    if (intent != TurnIntent.plan &&
        intent != TurnIntent.code &&
        toolMode != AgentToolMode.plan &&
        toolMode != AgentToolMode.code &&
        toolMode != AgentToolMode.fix) {
      return false;
    }
    return results.any(
      (result) =>
          result.toolName == 'propose_patch' &&
          result.structured.status == ToolResultStatus.success,
    );
  }

  bool _hasSuccessfulPatchProposal(List<ToolResultEnvelope> results) {
    return results.any(
      (result) =>
          result.toolName == 'propose_patch' &&
          result.status == ToolResultStatus.success,
    );
  }

  String _boundedInspectionQuestion(AcceptedPlanContext? acceptedPlan) {
    if (acceptedPlan != null) {
      final target = _firstAcceptedPlanTarget(acceptedPlan);
      if (target != null) {
        return 'What exact behavior should I implement in $target?';
      }
      return 'What exact behavior belongs inside the planned target file?';
    }
    return 'Which file should I inspect next?';
  }

  String? _firstAcceptedPlanTarget(AcceptedPlanContext acceptedPlan) {
    final structuredTargets = acceptedPlan.plannedTargets
        .map((target) => target.path.trim())
        .where((path) => path.isNotEmpty);
    if (structuredTargets.isNotEmpty) return structuredTargets.first;
    for (final display in acceptedPlan.plannedFiles) {
      final target = PlannedFileTarget.fromDisplayString(display).path.trim();
      if (target.isNotEmpty) return target;
    }
    return null;
  }

  String _outcomeRepairPrompt({
    required TurnIntent intent,
    required AgentToolMode toolMode,
    AcceptedPlanContext? acceptedPlan,
  }) {
    final common = [
      'CircuitCode runtime rejected the previous response because it did not satisfy the active turn contract.',
      'Do not ask the user to type "approve"; CircuitCode owns plan, patch, and approval UI.',
      'Do not claim changes are applied, verified, committed, or run unless the app reports that result.',
      'Do not use shell, write/edit, git mutation, network, or `apply_patch_set` tools.',
    ];

    if (intent == TurnIntent.plan || toolMode == AgentToolMode.plan) {
      return [
        ...common,
        'Repair this Plan turn by doing exactly one of these:',
        '1. Call `propose_patch` once with a reviewable plan: non-empty title, non-empty summary, `plan_markdown`, planned files with path/intent/operation, `assumptions`, and `verification_steps`.',
        '2. Ask exactly one specific missing-context question if a plan cannot be created yet.',
        'Do not answer with prose-only planning.',
      ].join('\n');
    }

    if (acceptedPlan != null) {
      return [
        ...common,
        'Repair this accepted-plan Code turn by doing exactly one of these:',
        '1. Call `propose_patch` once with concrete app-applyable file edits. Each file needs a path, operation, and full content/after text; modify/delete proposals must include the current before text.',
        '2. Ask exactly one specific missing-context question if the accepted plan cannot be implemented yet.',
        'Do not re-plan. Do not summarize work without proposing concrete edits.',
      ].join('\n');
    }

    return [
      ...common,
      'Repair this Code turn by doing exactly one of these:',
      '1. Call `propose_patch` once with concrete app-applyable file edits. Each file needs a path, operation, and full content/after text; modify/delete proposals must include the current before text.',
      '2. Ask exactly one specific missing-context question if the requested change cannot be implemented yet.',
      'Do not summarize work without proposing concrete edits.',
    ].join('\n');
  }

  bool _isCancellationError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('request cancelled') ||
        message.contains('request canceled') ||
        message.contains('cancelled by user') ||
        message.contains('canceled by user');
  }

  AgentToolPhase _phaseFor(
    AgentToolMode mode,
    int iteration, {
    required bool hasAcceptedPlan,
  }) {
    return switch (mode) {
      AgentToolMode.chat ||
      AgentToolMode.ask ||
      AgentToolMode.review ||
      AgentToolMode.handoff => AgentToolPhase.inspect,
      AgentToolMode.plan => AgentToolPhase.propose,
      AgentToolMode.verify => AgentToolPhase.verify,
      AgentToolMode.code || AgentToolMode.fix =>
        hasAcceptedPlan || iteration > 0
            ? AgentToolPhase.propose
            : AgentToolPhase.inspect,
    };
  }

  String _messageWithAcceptedPlan(
    String userMessage,
    AcceptedPlanContext acceptedPlan,
  ) {
    return [
      userMessage,
      acceptedPlan.toPromptBlock(),
      'Implementation contract:',
      '- Treat the accepted plan as structured context, not as user chat.',
      '- Produce one concrete `propose_patch` call with full file contents/diffs, or ask exactly one specific missing-context question.',
      '- Do not call command, write, edit, git mutation, or `apply_patch_set` tools from this turn.',
      '- Do not ask the user to type "approve"; CircuitCode owns approval and patch application UI.',
    ].join('\n\n');
  }

  String _studioSystemPrompt({
    required TurnIntent intent,
    required AgentToolMode toolMode,
    required bool hasAcceptedPlan,
  }) {
    return [
      'You are Circuit Agent inside CircuitCode Studio.',
      'Operate only within the selected Studio workspace and use relative paths when discussing files.',
      'Instructions and project memories are guidance only; the app-side permission policy is authoritative.',
      'Inspect before proposing changes. Never claim that files changed, commands ran, or tests passed unless a tool result proves it.',
      'Do not ask the user to type "approve"; CircuitCode renders approval, plan, patch, and apply controls in the UI.',
      'Current intent: ${intent.name}. Current tool profile: ${toolMode.name}.',
      if (hasAcceptedPlan)
        'This turn has an accepted plan. Produce one concrete propose_patch result or ask exactly one specific missing-context question.',
      switch (intent) {
        TurnIntent.chat =>
          'Chat intent contract: answer conversationally. Do not use tools, assume a project, create files, or run commands.',
        TurnIntent.ask =>
          'Ask intent contract: explain or inspect with read/search only. Do not propose/apply patches or run commands.',
        TurnIntent.plan =>
          'Plan intent contract: produce one clear plan or patch proposal. Do not write files, apply patches, or run commands.',
        TurnIntent.code =>
          'Code intent contract: inspect first, then produce a reviewable patch proposal. Do not apply changes or run commands.',
        TurnIntent.review =>
          'Review intent contract: review existing code/diffs and report findings. Do not mutate files or run commands.',
        TurnIntent.verify =>
          'Verify intent contract: suggest or request approved verification commands and summarize results. Do not mutate files.',
      },
    ].join('\n\n');
  }

  ToolPermissionPhase _permissionPhaseFor(AgentToolPhase phase) {
    return switch (phase) {
      AgentToolPhase.inspect => ToolPermissionPhase.inspect,
      AgentToolPhase.propose => ToolPermissionPhase.propose,
      AgentToolPhase.apply => ToolPermissionPhase.apply,
      AgentToolPhase.verify => ToolPermissionPhase.verify,
    };
  }

  List<ToolCallInfo> _unavailableToolCalls(
    List<ToolCallInfo> toolCalls,
    List<ToolDefinition> exposedTools,
  ) {
    final exposedNames = exposedTools.map((tool) => tool.name).toSet();
    return toolCalls
        .where((call) => !exposedNames.contains(call.name))
        .toList(growable: false);
  }

  void _emitLifecycle(
    String requestId,
    String? turnId,
    ProviderLifecycleEventKind kind, {
    String? detail,
  }) {
    events.emit(EventType.providerLifecycle, {
      'event': ProviderLifecycleEvent(
        requestId: requestId,
        turnId: turnId,
        kind: kind,
        timestamp: DateTime.now(),
        model: model,
        detail: detail,
      ),
      'requestId': requestId,
    });
  }
}

class StudioTurnCancelledException implements Exception {
  const StudioTurnCancelledException();

  @override
  String toString() => 'Request cancelled.';
}

class StudioTurnOutcomeValidationException implements Exception {
  final String message;

  const StudioTurnOutcomeValidationException(this.message);

  @override
  String toString() => message;
}
