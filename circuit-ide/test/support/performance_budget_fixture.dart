import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Loads the checked-in deterministic performance budgets used by scale tests.
///
/// These budgets are deliberately separate from the release-profile budgets in
/// `docs/PERFORMANCE_BUDGETS.md`: widget-test timing establishes a regression
/// guard for store and state work, but cannot prove frame pacing or memory use
/// in a packaged macOS application.
class PerformanceBudgetFixture {
  final Map<String, Map<String, Object?>> _metrics;

  const PerformanceBudgetFixture._(this._metrics);

  static Future<PerformanceBudgetFixture> load() async {
    final fixture = File(
      '${Directory.current.path}${Platform.pathSeparator}test${Platform.pathSeparator}fixtures${Platform.pathSeparator}performance_budgets.json',
    );
    final decoded = jsonDecode(await fixture.readAsString());
    if (decoded is! Map<String, dynamic> || decoded['schemaVersion'] != 1) {
      throw const FormatException(
        'Performance budget fixture must use schema version 1.',
      );
    }
    final metrics = decoded['metrics'];
    if (metrics is! Map<String, dynamic>) {
      throw const FormatException('Performance budget fixture has no metrics.');
    }
    return PerformanceBudgetFixture._({
      for (final entry in metrics.entries)
        if (entry.value is Map<String, dynamic>)
          entry.key: Map<String, Object?>.from(entry.value as Map),
    });
  }

  void expectDuration(String metric, Duration elapsed) {
    final value = _metric(metric)['maxMilliseconds'];
    if (value is! int || value <= 0) {
      throw StateError(
        '$metric must define a positive maxMilliseconds budget.',
      );
    }
    final limit = Duration(milliseconds: value);
    _report(metric, observed: elapsed.inMilliseconds, limit: value, unit: 'ms');
    expect(
      elapsed,
      lessThanOrEqualTo(limit),
      reason: '$metric exceeded its deterministic CI budget of ${value}ms.',
    );
  }

  void expectCount(String metric, int observed) {
    final value = _metric(metric)['maxCount'];
    if (value is! int || value < 0) {
      throw StateError('$metric must define a non-negative maxCount budget.');
    }
    _report(metric, observed: observed, limit: value, unit: 'updates');
    expect(
      observed,
      lessThanOrEqualTo(value),
      reason: '$metric exceeded its deterministic CI budget of $value updates.',
    );
  }

  Map<String, Object?> _metric(String metric) {
    final definition = _metrics[metric];
    if (definition == null) {
      throw StateError('No performance budget is defined for $metric.');
    }
    return definition;
  }

  void _report(
    String metric, {
    required int observed,
    required int limit,
    required String unit,
  }) {
    // This line is intentionally machine-readable in CI logs and in the
    // named performance suite. It is evidence, not a release-profile result.
    print(
      'PERFORMANCE_BUDGET metric=$metric observed=$observed$unit limit=$limit$unit',
    );
  }
}
