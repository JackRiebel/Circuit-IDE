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
