import 'package:circuit_ide/agent/security/cost_tracker.dart';
import 'package:circuit_ide/agent/streaming/streaming_response.dart';
import 'package:circuit_ide/models/token_usage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TokenUsage', () {
    test('formats total and input/output breakdowns', () {
      const usage = TokenUsage(
        promptTokens: 1200,
        completionTokens: 345,
        totalTokens: 1545,
      );

      expect(usage.formatted, '1.5K');
      expect(usage.formattedInputOutput, 'In 1.2K / Out 345');
      expect(usage.formattedWithBreakdown, '1.5K · In 1.2K / Out 345');
    });

    test('keeps provider-specific dimensions out of the total', () {
      const request = TokenUsage(
        promptTokens: 100,
        cachedInputTokens: 40,
        completionTokens: 25,
        reasoningTokens: 10,
        toolTokens: 5,
        totalTokens: 125,
      );
      final session = const TokenUsage().plus(request).plus(request);

      expect(session.totalTokens, 250);
      expect(session.cachedInputTokens, 80);
      expect(session.reasoningTokens, 20);
      expect(session.toolTokens, 10);
      expect(session.formattedDetailedBreakdown, contains('cached 80'));
    });
  });

  group('StreamingResponse', () {
    test('preserves prompt tokens when completion arrives separately', () {
      final response = StreamingResponse();

      response.updateUsage(500, 0);
      response.updateUsage(0, 125);

      expect(response.promptTokens, 500);
      expect(response.completionTokens, 125);
      expect(response.totalTokens, 625);
    });

    test('preserves cached reasoning and tool usage dimensions', () {
      final response = StreamingResponse();
      response.updateUsage(500, 125, cachedInput: 300, reasoning: 40, tool: 12);

      expect(response.cachedInputTokens, 300);
      expect(response.reasoningTokens, 40);
      expect(response.toolTokens, 12);
      expect(response.totalTokens, 625);
    });
  });

  group('CostTracker', () {
    test('tracks last request separately from session total', () {
      final tracker = CostTracker();

      tracker.addUsage('unknown-model', 100, 25);
      tracker.addUsage('unknown-model', 40, 10);

      expect(tracker.lastUsage.promptTokens, 40);
      expect(tracker.lastUsage.completionTokens, 10);
      expect(tracker.lastUsage.totalTokens, 50);
      expect(tracker.totalUsage.promptTokens, 140);
      expect(tracker.totalUsage.completionTokens, 35);
      expect(tracker.totalUsage.totalTokens, 175);
    });
  });
}
