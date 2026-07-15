import 'dart:async';
import 'dart:io';

import 'package:circuit_ide/agent/providers/provider_interface.dart';
import 'package:circuit_ide/agent/studio_turn_runner.dart';
import 'package:circuit_ide/agent/tools/tool_executor.dart';
import 'package:circuit_ide/agent/tools/tool_registry.dart';
import 'package:circuit_ide/models/agent_config_model.dart';
import 'package:circuit_ide/models/chat_message.dart';
import 'package:circuit_ide/models/context_attachment.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:circuit_ide/services/event_bus.dart';
import 'package:circuit_ide/ui/studio/studio_message_sender.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'selected-file custom agents receive only declared attachment-scoped capabilities',
    () async {
      final root = await Directory.systemTemp.createTemp('custom-agent-scope-');
      addTearDown(() => root.delete(recursive: true));
      final provider = _RecordingProvider(const [
        [
          ChatChunk(content: 'I used only the attached evidence.'),
          ChatChunk(finishReason: 'stop', isDone: true),
        ],
      ]);
      final runner = _runner(provider, root.path);
      final agent = _agent(
        contextPolicy: AgentContextPolicy.selectedFiles,
        allowedTools: const {'read_file', 'search_files'},
      );

      final result = await runner.run(
        requestId: 'scoped-request',
        userMessage: 'Review the selected file.',
        history: const [],
        toolMode: AgentToolMode.ask,
        intent: TurnIntent.ask,
        customAgent: agent,
      );

      expect(result.content, contains('attached evidence'));
      expect(provider.exposedTools, [isEmpty]);
      expect(provider.systemPrompts.single, contains('Use the exact evidence'));
      expect(
        provider.systemPrompts.single,
        contains('Context policy: selectedFiles'),
      );
    },
  );

  test(
    'a malicious custom-agent tool call is stopped before execution',
    () async {
      final root = await Directory.systemTemp.createTemp('custom-agent-tool-');
      addTearDown(() => root.delete(recursive: true));
      final provider = _RecordingProvider(const [
        [
          ChatChunk(
            toolCallIndex: 0,
            toolCallId: 'read-secret',
            toolCallName: 'read_file',
            toolCallArguments: '{"path":"private.txt"}',
          ),
          ChatChunk(finishReason: 'tool_calls', isDone: true),
        ],
      ]);
      final runner = _runner(provider, root.path);

      await expectLater(
        runner.run(
          requestId: 'malicious-request',
          userMessage: 'Read a secret.',
          history: const [],
          toolMode: AgentToolMode.ask,
          intent: TurnIntent.ask,
          customAgent: _agent(
            contextPolicy: AgentContextPolicy.userProvidedOnly,
            allowedTools: const {'read_file'},
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('unavailable tool'),
          ),
        ),
      );
      expect(provider.exposedTools, [isEmpty]);
    },
  );

  test('custom-agent tool-call limits stop work before a tool runs', () async {
    final root = await Directory.systemTemp.createTemp('custom-agent-limit-');
    addTearDown(() => root.delete(recursive: true));
    final provider = _RecordingProvider(const [
      [
        ChatChunk(
          toolCallIndex: 0,
          toolCallId: 'read-one',
          toolCallName: 'read_file',
          toolCallArguments: '{"path":"one.txt"}',
        ),
        ChatChunk(finishReason: 'tool_calls', isDone: true),
      ],
    ]);

    await expectLater(
      _runner(provider, root.path).run(
        requestId: 'limited-request',
        userMessage: 'Inspect a file.',
        history: const [],
        toolMode: AgentToolMode.ask,
        intent: TurnIntent.ask,
        customAgent: _agent(
          allowedTools: const {'read_file'},
          limits: const AgentExecutionLimits(maxTurns: 1, maxToolCalls: 0),
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('declared tool-call limit (0)'),
        ),
      ),
    );
  });

  test('custom agents cancel through the shared Studio runner', () async {
    final root = await Directory.systemTemp.createTemp('custom-agent-cancel-');
    addTearDown(() => root.delete(recursive: true));
    final provider = _GatedProvider();
    final runner = _runner(provider, root.path);
    final run = runner.run(
      requestId: 'cancelled-request',
      userMessage: 'Wait for cancellation.',
      history: const [],
      toolMode: AgentToolMode.ask,
      intent: TurnIntent.ask,
      customAgent: _agent(contextPolicy: AgentContextPolicy.userProvidedOnly),
    );

    await provider.started.future;
    runner.cancel();
    provider.controller.add(const ChatChunk(content: 'late response'));
    await provider.controller.close();

    await expectLater(run, throwsA(isA<StudioTurnCancelledException>()));
  });

  test(
    'custom-agent validation blocks unavailable or disallowed selections',
    () {
      final agent = _agent(allowedIntents: const {TurnIntent.review});

      expect(
        customAgentValidationError(
          selectedAgentId: 'missing-agent',
          customAgent: null,
          intent: TurnIntent.ask,
        ),
        contains('unavailable'),
      );
      expect(
        customAgentValidationError(
          selectedAgentId: agent.id,
          customAgent: agent,
          intent: TurnIntent.ask,
        ),
        contains('not allowed'),
      );
    },
  );

  test('custom-agent validation blocks a disabled library agent', () {
    final disabled = _agent().copyWith(enabled: false);

    expect(
      customAgentValidationError(
        selectedAgentId: disabled.id,
        customAgent: disabled,
        intent: TurnIntent.ask,
      ),
      contains('disabled'),
    );
  });

  test(
    'attachment-scoped custom-agent context excludes automatic retrieval',
    () {
      final attachment = ContextAttachment(
        id: 'selection',
        type: ContextAttachmentType.selection,
        label: 'Selected login handler',
        path: 'lib/login.dart',
        content: 'void login() {}',
        resolutionStatus: ContextAttachmentResolutionStatus.resolved,
        estimatedTokens: 8,
        createdAt: DateTime(2026),
      );

      final payload = buildCustomAgentContextPayload(
        rootPath: '/workspace',
        attachments: [attachment],
        contextPolicy: AgentContextPolicy.selectedFiles,
      );

      expect(payload.attachments, [attachment]);
      expect(payload.contextRetrieval, isNull);
      expect(payload.summary.selectedFiles, ['lib/login.dart']);
      expect(
        payload.summary.warnings.join(' '),
        contains('prior-thread context are excluded'),
      );
    },
  );
}

StudioTurnRunner _runner(_RecordingProvider provider, String rootPath) {
  return StudioTurnRunner(
    provider: provider,
    workingDir: rootPath,
    events: EventBus(),
    model: 'gpt-5-nano',
    toolExecutor: ToolExecutor(workingDir: rootPath),
  );
}

AgentConfigModel _agent({
  AgentContextPolicy contextPolicy = AgentContextPolicy.projectOnly,
  Set<TurnIntent> allowedIntents = const {TurnIntent.ask},
  Set<String> allowedTools = const {},
  AgentExecutionLimits limits = const AgentExecutionLimits(),
}) {
  return AgentConfigModel(
    id: 'scoped-reviewer',
    name: 'Scoped reviewer',
    description: 'Review only the evidence supplied in this Studio turn.',
    systemPrompt: 'Use the exact evidence attached to this request.',
    allowedIntents: allowedIntents,
    allowedTools: allowedTools,
    contextPolicy: contextPolicy,
    limits: limits,
    createdAt: DateTime(2026),
  );
}

class _RecordingProvider implements AIProvider {
  final List<List<ChatChunk>> _rounds;
  final List<Set<String>> exposedTools = [];
  final List<String> systemPrompts = [];
  var _nextRound = 0;

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
    List<ChatMessage> messages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async* {
    exposedTools.add(tools.map((tool) => tool.name).toSet());
    systemPrompts.add(systemPrompt ?? '');
    final round = _nextRound < _rounds.length
        ? _rounds[_nextRound++]
        : const <ChatChunk>[];
    yield* Stream<ChatChunk>.fromIterable(round);
  }
}

class _GatedProvider extends _RecordingProvider {
  final started = Completer<void>();
  final controller = StreamController<ChatChunk>();

  _GatedProvider() : super(const []);

  @override
  Stream<ChatChunk> chat(
    List<ChatMessage> messages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async* {
    exposedTools.add(tools.map((tool) => tool.name).toSet());
    systemPrompts.add(systemPrompt ?? '');
    started.complete();
    yield* controller.stream;
  }
}
