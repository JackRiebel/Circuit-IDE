import 'dart:async';

import 'package:uuid/uuid.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/logger.dart';
import '../enums/event_type.dart';
import '../enums/message_role.dart';
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
  List<ToolDefinition> _mcpTools = [];

  static const _uuid = Uuid();

  CircuitAgent({
    required this.provider,
    required this.workingDir,
    required this.events,
    this.model = 'gpt-4.1',
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
  }) async {
    if (_isProcessing) {
      throw StateError('Agent is already processing a message');
    }

    _isProcessing = true;
    _isCancelled = false;

    try {
      events.emit(EventType.messageStarted);
      try {
        await _auditLogger.logUserInput(userMessage);
      } catch (_) {}

      // Begin a new checkpoint turn
      _toolExecutor.beginTurn();

      // Add user message to history
      final userMsg = ChatMessage(
        id: _uuid.v4(),
        role: MessageRole.user,
        content: userMessage,
        timestamp: DateTime.now(),
      );
      history.add(userMsg);

      String fullResponse = '';
      List<ToolCallInfo> allToolCalls = [];

      // Tool call loop (up to 25 iterations)
      for (
        int iteration = 0;
        iteration < AppConstants.maxToolCallIterations;
        iteration++
      ) {
        final optimized = _contextManager.optimizeContext(history);
        final response = StreamingResponse();

        // Stream the response
        events.emit(EventType.thinkingStarted);

        // Merge MCP tools into the tools list for AI provider
        final allTools = [...ToolRegistry.allTools, ..._mcpTools];

        await for (final chunk in provider.chat(
          optimized,
          model: model,
          tools: allTools,
          systemPrompt: _systemPromptOverride ?? _systemPrompt,
          maxTokens: 4096,
        )) {
          if (_isCancelled) break;

          if (chunk.content != null) {
            response.addContent(chunk.content!);
            onContent?.call(chunk.content!);
            events.emit(EventType.messageChunk, {'content': chunk.content});
          }

          if (chunk.toolCallIndex != null) {
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

        final assistantMsg = ChatMessage(
          id: _uuid.v4(),
          role: MessageRole.assistant,
          content: response.content,
          timestamp: DateTime.now(),
          toolCalls: toolCallInfos,
        );
        history.add(assistantMsg);

        fullResponse += response.content;
        allToolCalls.addAll(toolCallInfos);

        // If no tool calls, we're done
        if (!response.hasToolCalls) break;

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
          history.add(toolMsg);

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
      });
      return fullResponse;
    } catch (e) {
      final errorMsg = e.toString().replaceFirst('Exception: ', '');
      try {
        Logger.error('Chat error', e);
      } catch (_) {}
      events.emit(EventType.messageError, {'error': errorMsg});
      try {
        await _auditLogger.logError('chat_error', errorMsg, {'model': model});
      } catch (_) {}
      rethrow;
    } finally {
      _isProcessing = false;
    }
  }

  Future<bool> _handleConfirmation(ConfirmationRequest request) async {
    events.emit(EventType.confirmationNeeded, {'request': request});

    final result = await request.response;

    events.emit(EventType.confirmationReceived, {
      'id': request.id,
      'approved': result,
    });

    return result;
  }

  void _handleToolCallUpdate(ToolCallInfo toolCall) {
    events.emit(EventType.toolCallStarted, {'toolCall': toolCall});
  }

  void clearHistory() {
    history.clear();
    costTracker.reset();
    events.emit(EventType.historyCleared);
  }
}
