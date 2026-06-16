import 'dart:async';

import 'package:uuid/uuid.dart';

import '../core/utils/logger.dart';
import '../enums/event_type.dart';
import '../enums/message_role.dart';
import '../models/chat_message.dart';
import '../models/provider_lifecycle_event.dart';
import '../models/token_usage.dart';
import '../models/tool_call_info.dart';
import '../services/event_bus.dart';
import 'config/config.dart';
import 'context/context_manager.dart';
import 'providers/provider_interface.dart';
import 'streaming/streaming_response.dart';
import 'tools/tool_executor.dart';
import 'tools/tool_registry.dart';

class StudioTurnRunnerResult {
  final String content;
  final TokenUsage usage;
  final List<ToolCallInfo> toolCalls;

  const StudioTurnRunnerResult({
    required this.content,
    required this.usage,
    required this.toolCalls,
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
  final ContextManager _contextManager = ContextManager();

  static const _uuid = Uuid();
  bool _isCancelled = false;

  StudioTurnRunner({
    required this.provider,
    required this.workingDir,
    required this.events,
    required this.model,
    required this.toolExecutor,
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
  }) async {
    _isCancelled = false;
    final systemPrompt = await AgentConfig(
      workingDir: workingDir,
    ).loadSystemPrompt();
    final requestHistory = List<ChatMessage>.of(history)
      ..add(
        ChatMessage(
          id: _uuid.v4(),
          role: MessageRole.user,
          content: userMessage,
          timestamp: DateTime.now(),
        ),
      );

    events.emit(EventType.messageStarted, {'requestId': requestId});
    toolExecutor.beginTurn();

    var fullResponse = '';
    var usage = const TokenUsage();
    final allToolCalls = <ToolCallInfo>[];
    final seenToolRounds = <String>{};
    var noProgressRounds = 0;
    var sawAnyText = false;
    var sawAnyTool = false;

    try {
      final maxIterations = toolMode == AgentToolMode.plan ? 4 : 6;
      for (var iteration = 0; iteration < maxIterations; iteration++) {
        final response = StreamingResponse();
        final tools = ToolRegistry.toolsForMode(toolMode);
        _emitLifecycle(
          requestId,
          turnId,
          ProviderLifecycleEventKind.requestSent,
          detail:
              'Exposed ${tools.length} ${toolMode.name} tools for this turn.',
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
          if (!sawFirstByte) {
            sawFirstByte = true;
            _emitLifecycle(
              requestId,
              turnId,
              ProviderLifecycleEventKind.firstByte,
            );
          }
          if (chunk.lifecycleKind != null) {
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
        if (!sawFirstByte) {
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
          events.emit(EventType.tokensUpdated, {
            'lastUsage': usage,
            'requestId': requestId,
          });
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
        if (response.content.trim().isEmpty && toolCallInfos.isEmpty) {
          if (fullResponse.trim().isEmpty) {
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
          requestHistory.add(
            ChatMessage(
              id: _uuid.v4(),
              role: MessageRole.tool,
              content: result.result,
              timestamp: DateTime.now(),
              toolCallId: result.toolCallId,
            ),
          );
        }
        Logger.info(
          'Studio turn tool calls completed, iteration ${iteration + 1}',
          'StudioTurnRunner',
        );
      }

      _emitLifecycle(
        requestId,
        turnId,
        ProviderLifecycleEventKind.completed,
        detail: [
          if (!sawAnyText) 'No text delta received',
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
        usage: usage,
        toolCalls: allToolCalls,
      );
    } catch (error) {
      if (error is! StudioTurnCancelledException) {
        final message = error.toString().replaceFirst('Exception: ', '');
        _emitLifecycle(
          requestId,
          turnId,
          ProviderLifecycleEventKind.failed,
          detail: message,
        );
        events.emit(EventType.messageError, {
          'error': message,
          'requestId': requestId,
        });
      }
      rethrow;
    }
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
