import 'dart:async';

import 'package:circuit_ide/agent/intent/intent_model_classifier.dart';
import 'package:circuit_ide/agent/providers/provider_interface.dart';
import 'package:circuit_ide/enums/message_role.dart';
import 'package:circuit_ide/models/chat_message.dart';
import 'package:circuit_ide/models/studio_shell.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('offline intent-routing evaluation', () {
    const corpus = [
      _IntentEvalCase(
        category: 'greeting',
        prompt: 'Good morning, Circuit!',
        expected: TurnIntent.chat,
      ),
      _IntentEvalCase(
        category: 'discovery',
        prompt: 'We need a portal to help field technicians manage repairs.',
        expected: TurnIntent.ask,
      ),
      _IntentEvalCase(
        category: 'direct edit',
        prompt: 'Fix the login redirect bug.',
        expected: TurnIntent.code,
      ),
      _IntentEvalCase(
        category: 'research',
        prompt: 'Research Acme Corp use cases and summarize them in chat.',
        expected: TurnIntent.ask,
      ),
      _IntentEvalCase(
        category: 'plan',
        prompt: 'Create an implementation plan for the auth refactor.',
        expected: TurnIntent.plan,
      ),
      _IntentEvalCase(
        category: 'review',
        prompt: 'Review the current git diff for regressions.',
        expected: TurnIntent.review,
      ),
      _IntentEvalCase(
        category: 'file generation',
        prompt:
            'Create lib/settings_screen.dart with an accessible Settings widget.',
        expected: TurnIntent.code,
      ),
      _IntentEvalCase(
        category: 'verification',
        prompt: 'Run flutter analyze.',
        expected: TurnIntent.verify,
      ),
      _IntentEvalCase(
        category: 'ambiguous',
        prompt: 'Something feels off in this app.',
        expected: TurnIntent.ask,
        expectsModelCandidate: true,
      ),
    ];

    test('meets the CI precision and recall contract across every category', () {
      final results = [
        for (final item in corpus)
          (
            item: item,
            decision: IntentClassifier.classifyDecision(
              item.prompt,
              promptMode: StudioPromptMode.code,
              planModeEnabled: false,
            ),
          ),
      ];
      final report = _IntentEvalReport.fromResults(results);

      // ignore: avoid_print
      print(
        results
            .map(
              (result) =>
                  '${result.item.category}: expected ${result.item.expected.name}, got ${result.decision.intent.name}',
            )
            .join('\n'),
      );

      // This is a single-label routing task, so micro precision and recall
      // both equal exact-match accuracy. Keep the thresholds explicit rather
      // than claiming that every future corpus expansion is automatically 100%.
      expect(report.microPrecision, greaterThanOrEqualTo(0.95));
      expect(report.microRecall, greaterThanOrEqualTo(0.95));
      expect(report.categories, hasLength(corpus.length));
      for (final result in results) {
        expect(
          result.decision.intent,
          result.item.expected,
          reason: '${result.item.category}: ${result.item.prompt}',
        );
        expect(
          result.decision.requiresModelClassifier,
          result.item.expectsModelCandidate,
          reason: '${result.item.category} model-candidate contract',
        );
      }
      // Keep a compact report in CI/stdout for release evidence.
      // ignore: avoid_print
      print(report.toCiReport());
    });

    test(
      'typed model output can resolve only ambiguity at high confidence',
      () async {
        final initial = IntentClassifier.classifyDecision(
          'Something feels off in this app.',
          promptMode: StudioPromptMode.code,
          planModeEnabled: false,
        );
        final provider = _IntentRoutingProvider(
          '{"intent":"review","confidence":0.91,"reason":"The request asks to assess a current surface."}',
        );

        final resolved = await const IntentModelClassifier().resolve(
          deterministicDecision: initial,
          prompt: 'Something feels off in this app.',
          provider: provider,
          model: 'intent-test-model',
        );

        expect(resolved.intent, TurnIntent.review);
        expect(resolved.source, IntentRoutingSource.model);
        expect(resolved.confidence, 0.91);
        expect(provider.calls, 1);
        expect(provider.lastTools, isEmpty);
        expect(provider.lastMessages, hasLength(1));
        expect(provider.lastMessages.single.role, MessageRole.user);
        expect(provider.lastSystemPrompt, contains('additionalProperties'));
      },
    );

    test('low-confidence, malformed, and deterministic cases stay safe', () async {
      final ambiguous = IntentClassifier.classifyDecision(
        'Something feels off in this app.',
        promptMode: StudioPromptMode.code,
        planModeEnabled: false,
      );
      final lowConfidence = await const IntentModelClassifier().resolve(
        deterministicDecision: ambiguous,
        prompt: 'Something feels off in this app.',
        provider: _IntentRoutingProvider(
          '{"intent":"code","confidence":0.51,"reason":"Maybe edit something."}',
        ),
        model: 'intent-test-model',
      );
      expect(lowConfidence.intent, TurnIntent.ask);
      expect(lowConfidence.source, IntentRoutingSource.safeFallback);
      expect(lowConfidence.reason, contains('below'));

      expect(
        IntentModelClassifier.parse(
          '{"intent":"code","confidence":0.9,"reason":"x","unsafe":true}',
        ),
        isNull,
      );
      expect(
        IntentModelClassifier.parse(
          '```json\n{"intent":"plan","confidence":0.9,"reason":"Explicit plan request."}\n```',
        )?.intent,
        TurnIntent.plan,
      );

      final deterministic = IntentClassifier.classifyDecision(
        'Run flutter test.',
        promptMode: StudioPromptMode.code,
        planModeEnabled: false,
      );
      final provider = _IntentRoutingProvider(
        '{"intent":"code","confidence":1,"reason":"Ignored."}',
      );
      final preserved = await const IntentModelClassifier().resolve(
        deterministicDecision: deterministic,
        prompt: 'Run flutter test.',
        provider: provider,
        model: 'intent-test-model',
      );
      expect(preserved.intent, TurnIntent.verify);
      expect(provider.calls, 0);
    });

    test('intent diagnostics persist with the turn for inspection', () {
      const routing = IntentRoutingDecision(
        intent: TurnIntent.ask,
        confidence: 0.42,
        reason: 'Need a safe clarification.',
        source: IntentRoutingSource.safeFallback,
        requiresModelClassifier: true,
      );
      final timestamp = DateTime.utc(2026, 7, 11);
      final turn = StudioTurn(
        id: 'turn',
        threadId: 'thread',
        requestId: 'request',
        userMessageId: 'message',
        prompt: 'Something feels off.',
        model: 'intent-test-model',
        intent: TurnIntent.ask,
        intentRouting: routing,
        contextSummary: const StudioContextSummary(projectLabel: 'project'),
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      final restored = StudioTurn.fromJson(turn.toJson());
      expect(restored?.intentRouting?.intent, TurnIntent.ask);
      expect(restored?.intentRouting?.confidence, 0.42);
      expect(restored?.intentRouting?.source, IntentRoutingSource.safeFallback);
      expect(restored?.intentRouting?.reason, 'Need a safe clarification.');
    });
  });
}

class _IntentEvalCase {
  final String category;
  final String prompt;
  final TurnIntent expected;
  final bool expectsModelCandidate;

  const _IntentEvalCase({
    required this.category,
    required this.prompt,
    required this.expected,
    this.expectsModelCandidate = false,
  });
}

class _IntentEvalReport {
  final int total;
  final int correct;
  final Set<String> categories;

  const _IntentEvalReport({
    required this.total,
    required this.correct,
    required this.categories,
  });

  double get microPrecision => total == 0 ? 0 : correct / total;
  double get microRecall => total == 0 ? 0 : correct / total;

  factory _IntentEvalReport.fromResults(
    List<({_IntentEvalCase item, IntentRoutingDecision decision})> results,
  ) {
    return _IntentEvalReport(
      total: results.length,
      correct: results
          .where((result) => result.item.expected == result.decision.intent)
          .length,
      categories: results.map((result) => result.item.category).toSet(),
    );
  }

  String toCiReport() => [
    'Intent routing offline evaluation',
    'cases=$total categories=${categories.length}',
    'micro_precision=${microPrecision.toStringAsFixed(2)} (threshold 0.95)',
    'micro_recall=${microRecall.toStringAsFixed(2)} (threshold 0.95)',
  ].join('\n');
}

class _IntentRoutingProvider implements AIProvider {
  final String response;
  int calls = 0;
  List<ChatMessage> lastMessages = const [];
  List<ToolDefinition> lastTools = const [];
  String? lastSystemPrompt;

  _IntentRoutingProvider(this.response);

  @override
  List<ModelInfo> get availableModels => const [];

  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
    id: 'intent-test',
    displayName: 'Intent test provider',
    shortName: 'Intent test',
  );

  @override
  ProviderCapabilities get capabilities => descriptor.capabilities;

  @override
  bool get isConnected => true;

  @override
  String get name => 'Intent test provider';

  @override
  Stream<ChatChunk> chat(
    List<ChatMessage> messages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) {
    calls++;
    lastMessages = messages;
    lastTools = tools;
    lastSystemPrompt = systemPrompt;
    return Stream.fromIterable([
      ChatChunk(content: response),
      const ChatChunk(isDone: true),
    ]);
  }

  @override
  Future<void> connect(Map<String, String> credentials) async {}

  @override
  void cancelActiveRequest() {}

  @override
  Future<ConnectorHealth> checkHealth() async => ConnectorHealth(
    status: ConnectorHealthStatus.connected,
    message: 'Connected',
    checkedAt: DateTime.now(),
  );

  @override
  void disconnect() {}

  @override
  Future<List<ConnectorModelInfo>> refreshModels() async => const [];
}
