import 'dart:io';

import 'package:circuit_ide/agent/delegation/subagent_delegation_service.dart';
import 'package:circuit_ide/agent/providers/provider_interface.dart';
import 'package:circuit_ide/agent/tools/tool_executor.dart';
import 'package:circuit_ide/models/agent_tool_permission.dart';
import 'package:circuit_ide/models/chat_message.dart';
import 'package:circuit_ide/models/subagent_delegation.dart';
import 'package:circuit_ide/models/tool_call_info.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('delegation supplies only the bounded task and context', () async {
    final root = await Directory.systemTemp.createTemp('delegation-scope-');
    addTearDown(() => root.delete(recursive: true));
    final provider = _RecordingProvider([
      const [
        ChatChunk(content: 'I reviewed only the supplied excerpt.'),
        ChatChunk(finishReason: 'stop', isDone: true),
      ],
    ]);
    final service = SubagentDelegationService(
      provider: provider,
      workingDir: root.path,
      model: 'gpt-5-nano',
    );

    final result = await service.delegate(
      const SubagentDelegationRequest(
        task: 'Review the selected error handler.',
        context:
            'Selected file: lib/error_handler.dart\nOnly this method is in scope.',
        toolGrant: {'read_file'},
      ),
    );

    expect(result.summary, contains('supplied excerpt'));
    expect(provider.messages, hasLength(1));
    expect(provider.messages.single, hasLength(1));
    final prompt = provider.messages.single.single.content;
    expect(prompt, contains('Review the selected error handler'));
    expect(prompt, contains('Only this method is in scope'));
    expect(prompt, isNot(contains('parent private history')));
    expect(provider.exposedTools.single, {'read_file'});
    expect(provider.systemPrompts.single, contains('no parent transcript'));
  });

  test(
    'delegation returns compact evidence instead of child chatter',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'delegation-evidence-',
      );
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/evidence.txt').writeAsString('A bounded fact.');
      final provider = _RecordingProvider([
        const [
          ChatChunk(
            toolCallIndex: 0,
            toolCallId: 'read-evidence',
            toolCallName: 'read_file',
            toolCallArguments: '{"path":"evidence.txt"}',
          ),
          ChatChunk(finishReason: 'tool_calls', isDone: true),
        ],
        const [
          ChatChunk(
            content: 'The delegated inspection found the bounded fact.',
          ),
          ChatChunk(finishReason: 'stop', isDone: true),
        ],
      ]);
      final service = SubagentDelegationService(
        provider: provider,
        workingDir: root.path,
        model: 'gpt-5-nano',
      );

      final result = await service.delegate(
        const SubagentDelegationRequest(
          task: 'Inspect the supplied evidence file.',
          toolGrant: {'read_file'},
        ),
      );

      expect(result.summary, contains('delegated inspection'));
      expect(result.evidence, hasLength(1));
      expect(result.evidence.single.source, 'read_file');
      expect(result.toPromptBlock(), contains('Delegated subagent report'));
      expect(result.toPromptBlock(), contains('Evidence:'));
      expect(result.toPromptBlock(), contains('Artifacts:'));
      expect(result.toPromptBlock(), contains('Unresolved:'));
    },
  );

  test(
    'subagent mutation is denied without an explicit reviewed proposal grant',
    () {
      const implicitProposal = SubagentDelegationRequest(
        task: 'Draft a patch.',
        toolGrant: {'propose_patch'},
      );
      const missingToolGrant = SubagentDelegationRequest(
        task: 'Draft a patch.',
        allowReviewedPatchProposal: true,
      );

      expect(implicitProposal.validate().join(' '), contains('require'));
      expect(missingToolGrant.validate().join(' '), contains('tool_grant'));
    },
  );

  test(
    'parent receives one structured delegation result after approval',
    () async {
      final root = await Directory.systemTemp.createTemp('delegation-parent-');
      addTearDown(() => root.delete(recursive: true));
      final executor =
          ToolExecutor(
            workingDir: root.path,
            onConfirmationNeeded: (_) async => true,
            onSubagentDelegation: (_) async => const SubagentDelegationResult(
              summary: 'Reviewed the bounded task.',
              evidence: [
                SubagentEvidence(source: 'read_file', summary: '1 file'),
              ],
              artifacts: ['proposal:review'],
              unresolved: ['Missing one decision.'],
            ),
          )..setPermissionRequest(
            const ToolPermissionRequest(
              intent: TurnIntent.ask,
              phase: ToolPermissionPhase.inspect,
            ),
          );

      final results = await executor.executeToolCalls(const [
        ToolCallInfo(
          id: 'delegate',
          name: 'delegate_subagent',
          arguments: {'task': 'Review the focused scope.'},
        ),
      ]);

      final envelope = results.single.structured;
      expect(envelope.status.name, 'success');
      expect(envelope.data['delegation'], isA<Map<String, dynamic>>());
      expect(envelope.artifacts, ['proposal:review']);
      expect(results.single.result, contains('Unresolved:'));
    },
  );
}

class _RecordingProvider implements AIProvider {
  final List<List<ChatChunk>> _rounds;
  final List<List<ChatMessage>> messages = [];
  final List<Set<String>> exposedTools = [];
  final List<String> systemPrompts = [];
  var _round = 0;

  _RecordingProvider(this._rounds);

  @override
  String get name => 'Recording provider';

  @override
  List<ModelInfo> get availableModels => const [
    ModelInfo(
      id: 'gpt-5-nano',
      displayName: 'GPT-5 nano',
      contextWindow: 120000,
    ),
  ];

  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
    id: 'recording',
    displayName: 'Recording',
    shortName: 'Recording',
  );

  @override
  ProviderCapabilities get capabilities => descriptor.capabilities;

  @override
  bool get isConnected => true;

  @override
  Future<void> connect(Map<String, String> credentials) async {}

  @override
  void disconnect() {}

  @override
  void cancelActiveRequest() {}

  @override
  Future<ConnectorHealth> checkHealth() async => ConnectorHealth(
    status: ConnectorHealthStatus.connected,
    message: 'ok',
    checkedAt: DateTime(2026),
  );

  @override
  Future<List<ConnectorModelInfo>> refreshModels() async => const [
    ConnectorModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano'),
  ];

  @override
  Stream<ChatChunk> chat(
    List<ChatMessage> requestMessages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async* {
    messages.add(List.of(requestMessages));
    exposedTools.add(tools.map((tool) => tool.name).toSet());
    systemPrompts.add(systemPrompt ?? '');
    final response = _round < _rounds.length
        ? _rounds[_round++]
        : const <ChatChunk>[];
    yield* Stream<ChatChunk>.fromIterable(response);
  }
}
