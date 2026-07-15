import 'package:uuid/uuid.dart';

import '../../models/agent_config_model.dart';
import '../../models/chat_message.dart';
import '../../models/subagent_delegation.dart';
import '../../models/tool_result_envelope.dart';
import '../../models/turn_intent.dart';
import '../../services/event_bus.dart';
import '../studio_turn_runner.dart';
import '../providers/provider_interface.dart';
import '../tools/tool_executor.dart';
import '../tools/tool_registry.dart';

/// Runs a deliberately isolated, request-local child turn. It takes a task
/// envelope rather than a parent runner or transcript so history cannot leak
/// by construction. The child EventBus is never wired to the main turn.
class SubagentDelegationService {
  static const _uuid = Uuid();

  final AIProvider provider;
  final String workingDir;
  final String model;
  final ProviderConnectorNetworkPolicy connectorNetworkPolicy;
  StudioTurnRunner? _activeRunner;

  SubagentDelegationService({
    required this.provider,
    required this.workingDir,
    required this.model,
    this.connectorNetworkPolicy = ProviderConnectorNetworkPolicy.unrestricted,
  });

  void cancel() => _activeRunner?.cancel();

  Future<SubagentDelegationResult> delegate(
    SubagentDelegationRequest request,
  ) async {
    final validationErrors = request.validate();
    if (validationErrors.isNotEmpty) {
      throw ArgumentError(validationErrors.join(' '));
    }

    final intent = request.allowReviewedPatchProposal
        ? TurnIntent.plan
        : TurnIntent.ask;
    final toolMode = request.allowReviewedPatchProposal
        ? AgentToolMode.plan
        : AgentToolMode.ask;
    final childEvents = EventBus();
    final runner = StudioTurnRunner(
      provider: provider,
      workingDir: workingDir,
      events: childEvents,
      model: model,
      toolExecutor: ToolExecutor(workingDir: workingDir),
      connectorNetworkPolicy: connectorNetworkPolicy,
    );
    _activeRunner = runner;

    try {
      final result = await runner.run(
        requestId: 'subagent-${_uuid.v4()}',
        userMessage: _childTaskPrompt(request),
        history: const <ChatMessage>[],
        toolMode: toolMode,
        intent: intent,
        customAgent: _childContract(request, intent),
      );
      final toolResults = result.toolResults;
      return SubagentDelegationResult(
        summary: result.content,
        evidence: toolResults
            .where((item) => item.status == ToolResultStatus.success)
            .map(SubagentEvidence.fromToolResult)
            .toList(growable: false),
        artifacts: toolResults
            .expand((item) => item.artifacts)
            .toSet()
            .toList(growable: false),
        unresolved: _unresolvedLines(result.content),
      );
    } finally {
      if (identical(_activeRunner, runner)) _activeRunner = null;
      childEvents.dispose();
    }
  }

  AgentConfigModel _childContract(
    SubagentDelegationRequest request,
    TurnIntent intent,
  ) {
    final tools = <String>{...request.toolGrant};
    return AgentConfigModel(
      id: 'delegated-subagent',
      name: 'Delegated subagent',
      description: 'A bounded child task that returns one compact report.',
      systemPrompt: [
        'This is an isolated delegated task. You have no parent transcript, no hidden history, and no authority beyond the declared tool grant.',
        'Use only the supplied bounded context and tool evidence. Do not infer omitted conversation details.',
        'Do not write files, run commands, call connectors, or delegate again. A permitted propose_patch call is a reviewable artifact only; it never applies changes.',
        'Finish with a concise final answer. If blocked, state the unresolved issue explicitly.',
      ].join('\n'),
      allowedIntents: {intent},
      allowedTools: tools,
      outputContracts: {
        AgentOutputContract.summary,
        AgentOutputContract.evidence,
        if (request.allowReviewedPatchProposal) AgentOutputContract.plan,
      },
      limits: const AgentExecutionLimits(
        maxTurns: 2,
        maxToolCalls: 6,
        maxWallTime: Duration(minutes: 2),
      ),
      createdAt: DateTime.now(),
    );
  }

  String _childTaskPrompt(SubagentDelegationRequest request) => [
    'Bounded delegated task:',
    request.task.trim(),
    'Bounded context (this is the complete supplied context; do not assume any other parent history):',
    request.context.trim().isEmpty ? '(none)' : request.context.trim(),
    'Declared tool grant: ${request.toolGrant.isEmpty ? 'none' : request.toolGrant.join(', ')}.',
    if (request.allowReviewedPatchProposal)
      'A reviewable patch proposal is explicitly permitted, but applying a patch is not.',
  ].join('\n\n');

  List<String> _unresolvedLines(String content) {
    final lines = content
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where(
          (line) => RegExp(
            r'^(unresolved|blocked|missing|cannot|unable|need)\\b',
            caseSensitive: false,
          ).hasMatch(line),
        )
        .take(5)
        .toList(growable: false);
    return lines;
  }
}
