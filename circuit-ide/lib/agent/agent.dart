import 'dart:async';

import 'package:uuid/uuid.dart';

import '../core/constants/app_constants.dart';
import '../core/config/studio_feature_flags.dart';
import '../core/utils/logger.dart';
import '../enums/event_type.dart';
import '../enums/message_role.dart';
import '../enums/tool_status.dart';
import '../models/chat_message.dart';
import '../models/tool_call_info.dart';
import '../models/confirmation_request.dart';
import '../services/event_bus.dart';
import 'config/config.dart';
import 'context/context_manager.dart';
import 'providers/provider_interface.dart';
import 'security/audit_logger.dart';
import 'security/cost_tracker.dart';
import 'streaming/streaming_response.dart';
import 'checkpoint/checkpoint_manager.dart';
import 'mcp/mcp_client.dart';
import 'tools/tool_executor.dart';
import 'tools/tool_registry.dart';
import 'tools/orchestrate_tool.dart';

class CircuitAgent {
  final AIProvider provider;
  final String workingDir;
  final EventBus events;
  final ContextManager _contextManager = ContextManager();
  final CostTracker costTracker = CostTracker();
  final AuditLogger _auditLogger = AuditLogger();
  late final ToolExecutor _toolExecutor;

  String model;
  bool autoApprove;
  bool streamResponses;
  final List<ChatMessage> history = [];
  String? _systemPrompt;
  String? _systemPromptOverride;
  bool _isProcessing = false;
  bool _isCancelled = false;
  String? _activeRequestId;
  List<ToolDefinition> _mcpTools = [];

  static const _uuid = Uuid();

  CircuitAgent({
    required this.provider,
    required this.workingDir,
    required this.events,
    this.model = 'gpt-5-nano',
    this.autoApprove = false,
    this.streamResponses = true,
  }) {
    _toolExecutor = ToolExecutor(
      workingDir: workingDir,
      autoApprove: autoApprove,
      onConfirmationNeeded: _handleConfirmation,
      onToolCallUpdate: _handleToolCallUpdate,
    );
  }

  bool get isProcessing => _isProcessing;

  /// Expose checkpoint manager for UI access.
  CheckpointManager get checkpointManager => _toolExecutor.checkpointManager;

  /// Expose tool executor for external configuration.
  ToolExecutor get toolExecutor => _toolExecutor;

  /// Set MCP client for tool integration.
  void setMcpClient(McpClient? client) {
    _mcpTools = client?.toolDefinitions ?? [];
    _toolExecutor.setMcpClient(client);
  }

  /// Set orchestration tool executor.
  void setOrchestrateTool(OrchestrateToolExecutor? tool) {
    _toolExecutor.setOrchestrateTool(tool);
  }

  set systemPromptOverride(String? prompt) {
    _systemPromptOverride = prompt;
  }

  /// Cancel the current operation
  void cancel() {
    _isCancelled = true;
    _toolExecutor.cancelActiveCommands();
  }

  Future<void> init() async {
    await _auditLogger.init();
    final config = AgentConfig(workingDir: workingDir);
    _systemPrompt = await config.loadSystemPrompt();

    // Configure GitHub tools if PAT is available
    final fullConfig = await AgentConfig.load();
    if (fullConfig.githubPat != null) {
      _toolExecutor.configureGithub(fullConfig.githubPat!);
    }
  }

  /// Send a user message and get the AI response
  Future<String> chat(
    String userMessage, {
    void Function(String chunk)? onContent,
    String? requestId,
    List<ChatMessage>? historyOverride,
    AgentToolMode toolMode = AgentToolMode.code,
  }) async {
    if (_isProcessing) {
      throw StateError('Agent is already processing a message');
    }

    _isProcessing = true;
    _isCancelled = false;
    _activeRequestId = requestId;

    try {
      final eventData = requestId == null ? null : {'requestId': requestId};
      events.emit(EventType.messageStarted, eventData);
      try {
        await _auditLogger.logUserInput(userMessage);
      } catch (_) {}

      // Begin a new checkpoint turn
      _toolExecutor.beginTurn();
      final requestHistory = historyOverride == null
          ? history
          : List<ChatMessage>.of(historyOverride);

      // Add user message to history
      final userMsg = ChatMessage(
        id: _uuid.v4(),
        role: MessageRole.user,
        content: userMessage,
        timestamp: DateTime.now(),
      );
      requestHistory.add(userMsg);

      String fullResponse = '';
      List<ToolCallInfo> allToolCalls = [];
      final seenToolRounds = <String>{};
      var noProgressRounds = 0;

      // Tool call loop. Keep this bounded so weak or slow models cannot
      // inspect forever without returning useful status to the user.
      for (
        int iteration = 0;
        iteration < AppConstants.maxToolCallIterations;
        iteration++
      ) {
        final optimized = _contextManager.optimizeContext(requestHistory);
        final response = StreamingResponse();

        // Stream the response
        events.emit(EventType.thinkingStarted);

        final phase = _phaseForToolMode(toolMode, iteration);
        final baseTools = ToolRegistry.toolsForModeAndPhase(toolMode, phase);
        final allTools = [
          ...baseTools,
          if (StudioFeatureFlags.advancedStudioSurfaces &&
              phase == AgentToolPhase.verify)
            ..._mcpTools,
        ];
        events.emit(EventType.agentRunEvent, {
          'requestId': ?requestId,
          'event': 'tool_exposure',
          'mode': toolMode.name,
          'phase': phase.name,
          'tools': allTools.map((tool) => tool.name).toList(),
        });
        events.emit(EventType.agentRunEvent, {
          'requestId': ?requestId,
          'event': 'provider_lifecycle',
          'kind': 'request_sent',
          'model': model,
        });

        var sawFirstDelta = false;
        var sawFirstText = false;
        var sawFirstTool = false;
        await for (final chunk in provider.chat(
          optimized,
          model: model,
          tools: allTools,
          systemPrompt: _systemPromptOverride ?? _systemPrompt,
          maxTokens: 4096,
        )) {
          if (_isCancelled) break;

          if (!sawFirstDelta) {
            sawFirstDelta = true;
            events.emit(EventType.agentRunEvent, {
              'requestId': ?requestId,
              'event': 'provider_lifecycle',
              'kind': 'first_delta',
              'model': model,
            });
          }

          if (chunk.content != null) {
            if (!sawFirstText && chunk.content!.isNotEmpty) {
              sawFirstText = true;
              events.emit(EventType.agentRunEvent, {
                'requestId': ?requestId,
                'event': 'provider_lifecycle',
                'kind': 'first_text_delta',
                'model': model,
              });
            }
            response.addContent(chunk.content!);
            onContent?.call(chunk.content!);
            events.emit(EventType.messageChunk, {
              'content': chunk.content,
              'requestId': ?requestId,
            });
          }

          if (chunk.toolCallIndex != null) {
            if (!sawFirstTool) {
              sawFirstTool = true;
              events.emit(EventType.agentRunEvent, {
                'requestId': ?requestId,
                'event': 'provider_lifecycle',
                'kind': 'first_tool_delta',
                'model': model,
              });
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

        events.emit(EventType.thinkingCompleted);

        if (_isCancelled) break;

        // Track usage
        costTracker.addUsage(
          model,
          response.promptTokens,
          response.completionTokens,
        );
        await _auditLogger.logApiCall(
          model,
          response.promptTokens,
          response.completionTokens,
        );
        events.emit(EventType.tokensUpdated, {
          'usage': costTracker.totalUsage,
          'lastUsage': costTracker.lastUsage,
          'cost': costTracker.costInfo,
          'requestId': ?requestId,
        });

        // Add assistant message to history
        final toolCallInfos = response.toolCalls
            .map(
              (tc) => ToolCallInfo(
                id: tc.id,
                name: tc.name,
                arguments: tc.arguments,
              ),
            )
            .toList();
        final unavailableToolCalls = _unavailableToolCalls(
          toolCallInfos,
          allTools,
        );
        if (unavailableToolCalls.isNotEmpty) {
          final names = unavailableToolCalls
              .map((call) => call.name)
              .join(', ');
          final message =
              'Circuit AI requested unavailable tool(s) for this ${toolMode.name}/${phase.name} phase: $names. I stopped before running any unavailable action.';
          events.emit(EventType.agentRunEvent, {
            'requestId': ?requestId,
            'event': 'provider_lifecycle',
            'kind': 'unavailable_tool',
            'model': model,
            'detail': message,
          });
          throw StateError(message);
        }

        final assistantMsg = ChatMessage(
          id: _uuid.v4(),
          role: MessageRole.assistant,
          content: response.content,
          timestamp: DateTime.now(),
          toolCalls: toolCallInfos,
        );
        requestHistory.add(assistantMsg);

        fullResponse += response.content;
        allToolCalls.addAll(toolCallInfos);

        // If no tool calls, we're done
        if (!response.hasToolCalls) break;

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
              'I’m stopping here because the same tool step repeated without new progress. Tell me what to inspect next, or switch to Plan mode for a smaller reviewable plan.';
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

        // Execute tool calls
        _toolExecutor.autoApprove = autoApprove;
        final results = await _toolExecutor.executeToolCalls(toolCallInfos);

        // Add tool results to history
        for (final result in results) {
          final toolMsg = ChatMessage(
            id: _uuid.v4(),
            role: MessageRole.tool,
            content: result.result,
            timestamp: DateTime.now(),
            toolCallId: result.toolCallId,
          );
          requestHistory.add(toolMsg);

          await _auditLogger.logToolCall(
            toolCallInfos.firstWhere((tc) => tc.id == result.toolCallId).name,
            toolCallInfos
                .firstWhere((tc) => tc.id == result.toolCallId)
                .arguments,
            result.result,
            result.success,
          );
        }

        // Continue loop to get next response
        Logger.info(
          'Tool calls completed, iteration ${iteration + 1}',
          'Agent',
        );
      }

      // Commit checkpoint for this turn (if any files were modified)
      final editedFiles = allToolCalls
          .where((tc) => tc.name == 'write_file' || tc.name == 'edit_file')
          .map((tc) => tc.arguments['path'] as String? ?? '?')
          .toSet();
      if (editedFiles.isNotEmpty) {
        final desc = editedFiles.length == 1
            ? 'Edited ${editedFiles.first}'
            : 'Edited ${editedFiles.length} files';
        final checkpoint = _toolExecutor.commitTurn(desc);
        if (checkpoint != null) {
          events.emit(EventType.checkpointCreated, {'checkpoint': checkpoint});
          events.emit(EventType.vericodeTriggered, {
            'editedFiles': editedFiles.toList(),
          });
        }
      }

      events.emit(EventType.messageCompleted, {
        'content': fullResponse,
        'toolCalls': allToolCalls,
        'requestId': ?requestId,
      });
      return fullResponse;
    } catch (e) {
      final errorMsg = e.toString().replaceFirst('Exception: ', '');
      try {
        Logger.error('Chat error', e);
      } catch (_) {}
      events.emit(EventType.messageError, {
        'error': errorMsg,
        'requestId': ?requestId,
      });
      try {
        await _auditLogger.logError('chat_error', errorMsg, {'model': model});
      } catch (_) {}
      rethrow;
    } finally {
      _activeRequestId = null;
      _isProcessing = false;
    }
  }

  Future<bool> _handleConfirmation(ConfirmationRequest request) async {
    events.emit(EventType.confirmationNeeded, {
      'request': request,
      if (_activeRequestId != null) 'requestId': _activeRequestId,
    });

    final result = await request.response;

    events.emit(EventType.confirmationReceived, {
      'id': request.id,
      'approved': result,
      if (_activeRequestId != null) 'requestId': _activeRequestId,
    });

    return result;
  }

  void _handleToolCallUpdate(ToolCallInfo toolCall) {
    final type = switch (toolCall.status) {
      ToolStatus.success => EventType.toolCallCompleted,
      ToolStatus.error => EventType.toolCallError,
      ToolStatus.cancelled => EventType.toolCallError,
      _ => EventType.toolCallStarted,
    };
    events.emit(type, {
      'toolCall': toolCall,
      if (_activeRequestId != null) 'requestId': _activeRequestId,
    });
  }

  AgentToolPhase _phaseForToolMode(AgentToolMode mode, int iteration) {
    return switch (mode) {
      AgentToolMode.chat ||
      AgentToolMode.ask ||
      AgentToolMode.review ||
      AgentToolMode.handoff => AgentToolPhase.inspect,
      AgentToolMode.plan => AgentToolPhase.propose,
      AgentToolMode.verify => AgentToolPhase.verify,
      AgentToolMode.code || AgentToolMode.fix =>
        iteration == 0 ? AgentToolPhase.inspect : AgentToolPhase.propose,
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

  void clearHistory() {
    history.clear();
    costTracker.reset();
    events.emit(EventType.historyCleared);
  }
}
