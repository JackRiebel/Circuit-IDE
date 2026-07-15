import 'dart:convert';

import 'package:circuit_ide/models/studio_failure_slo_report.dart';
import 'package:circuit_ide/models/studio_failure_taxonomy.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/models/studio_turn_trace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('taxonomy assigns every product failure family to an owner and SLO', () {
    final cases = <(String, StudioFailureCategory)>[
      ('Provider connection timed out', StudioFailureCategory.provider),
      ('Permission denied by policy', StudioFailureCategory.policy),
      ('Workspace context index is unavailable', StudioFailureCategory.context),
      ('Tool invocation failed', StudioFailureCategory.tool),
      ('Patch conflict needs rebase', StudioFailureCategory.patch),
      ('Command exit code: 1', StudioFailureCategory.command),
      ('History storage journal failed', StudioFailureCategory.persistence),
      ('Artifact render failed', StudioFailureCategory.artifact),
      ('Widget focus disappeared', StudioFailureCategory.ui),
      ('Unexpected failure', StudioFailureCategory.unknown),
    ];

    for (final entry in cases) {
      final category = StudioFailureTaxonomy.classify(
        statusName: 'failed',
        error: entry.$1,
      );
      expect(category, entry.$2);
      final target = StudioFailureTaxonomy.targetFor(category!);
      expect(target.owner, isNotEmpty);
      expect(target.maximumStuckDuration, const Duration(minutes: 5));
    }
    expect(
      StudioFailureTaxonomy.classify(statusName: 'completed', error: 'timeout'),
      isNull,
    );
  });

  test(
    'failure category persists and support trace/report keep only typed data',
    () {
      final now = DateTime.utc(2026, 7, 11, 12);
      final failed = _turn(
        id: 'failed',
        status: StudioTurnStatus.failed,
        error: 'Patch conflict in /private/customer/secret.dart',
        updatedAt: now,
      );
      final stuck = _turn(
        id: 'stuck',
        status: StudioTurnStatus.streaming,
        updatedAt: now.subtract(const Duration(minutes: 6)),
      );
      final restored = StudioTurn.fromJson(failed.toJson());
      expect(restored?.effectiveFailureCategory, StudioFailureCategory.patch);

      final thread = StudioThread(
        id: 'thread',
        title: 'Customer secret task',
        status: StudioThreadStatus.failed,
        turns: [failed],
        createdAt: now,
        updatedAt: now,
      );
      final trace = StudioTurnTraceBuilder.build(thread: thread, turn: failed);
      final report = StudioFailureSloReport.fromTurns([
        failed,
        stuck,
      ], now: now);
      expect(trace.failureCategory, 'patch');
      expect(report.failuresByCategory[StudioFailureCategory.patch], 1);
      expect(report.stuckTurns, 1);
      final encoded = jsonEncode({
        'trace': trace.toJson(),
        'report': report.toJson(),
      });
      expect(encoded, contains('patch'));
      expect(encoded, isNot(contains('/private/customer')));
      expect(encoded, isNot(contains('Customer secret task')));
    },
  );
}

StudioTurn _turn({
  required String id,
  required StudioTurnStatus status,
  String? error,
  required DateTime updatedAt,
}) {
  return StudioTurn(
    id: id,
    threadId: 'thread',
    requestId: 'request-$id',
    userMessageId: 'message-$id',
    prompt: 'Sensitive prompt',
    model: 'model',
    contextSummary: const StudioContextSummary(projectLabel: 'Project'),
    status: status,
    createdAt: updatedAt.subtract(const Duration(minutes: 1)),
    updatedAt: updatedAt,
    lastError: error,
  );
}
