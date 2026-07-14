import 'studio_failure_taxonomy.dart';
import 'studio_turn.dart';

/// Aggregates only typed outcomes for support/release health. No prompt,
/// error text, workspace path, provider body, or tool output is retained.
class StudioFailureSloReport {
  final int totalTurns;
  final int failedTurns;
  final int stuckTurns;
  final Map<StudioFailureCategory, int> failuresByCategory;

  const StudioFailureSloReport({
    required this.totalTurns,
    required this.failedTurns,
    required this.stuckTurns,
    required this.failuresByCategory,
  });

  double get successRate =>
      totalTurns == 0 ? 1 : (totalTurns - failedTurns) / totalTurns;

  Map<String, dynamic> toJson() => {
    'totalTurns': totalTurns,
    'failedTurns': failedTurns,
    'stuckTurns': stuckTurns,
    'successRate': successRate,
    'failuresByCategory': {
      for (final entry in failuresByCategory.entries)
        entry.key.name: entry.value,
    },
  };

  factory StudioFailureSloReport.fromTurns(
    Iterable<StudioTurn> turns, {
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    final values = turns.toList(growable: false);
    final failures = <StudioFailureCategory, int>{};
    var failed = 0;
    var stuck = 0;
    for (final turn in values) {
      final category = turn.effectiveFailureCategory;
      if (category != null) {
        failed++;
        failures.update(category, (count) => count + 1, ifAbsent: () => 1);
      }
      if (!StudioTurnStateMachine.isTerminal(turn.status) &&
          timestamp.difference(turn.updatedAt) >
              StudioFailureTaxonomy.targetFor(
                StudioFailureCategory.unknown,
              ).maximumStuckDuration) {
        stuck++;
      }
    }
    return StudioFailureSloReport(
      totalTurns: values.length,
      failedTurns: failed,
      stuckTurns: stuck,
      failuresByCategory: failures,
    );
  }
}
