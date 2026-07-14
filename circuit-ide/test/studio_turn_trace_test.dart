import 'dart:convert';

import 'package:circuit_ide/models/provider_lifecycle_event.dart';
import 'package:circuit_ide/models/studio_source_artifact.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/models/studio_turn_trace.dart';
import 'package:circuit_ide/models/tool_result_envelope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'request trace reconstructs every lifecycle category without content',
    () {
      final startedAt = DateTime.utc(2026, 7, 11, 12);
      final completedAt = startedAt.add(const Duration(minutes: 2));
      final steps = [
        for (final step in TurnStep.values)
          TurnStepRecord(
            step: step,
            status: TurnStepStatus.completed,
            title: 'secret title',
            detail: 'token=super-secret-value',
            startedAt: startedAt,
            completedAt: completedAt,
          ),
      ];
      final turn = StudioTurn(
        id: 'turn-1',
        threadId: 'thread-1',
        requestId: 'request-1',
        userMessageId: 'message-1',
        prompt: 'Prompt with api_key=super-secret-value',
        modelPrompt: 'Internal customer content: never export',
        taskTitle: 'Sensitive task title',
        model: 'gpt-5',
        contextSummary: const StudioContextSummary(
          rootPath: '/Users/example/customer-project',
          projectLabel: 'Customer project',
          includedItemCount: 3,
          omittedCandidateCount: 2,
          estimatedTokens: 1200,
          includesGit: true,
        ),
        status: StudioTurnStatus.completed,
        steps: steps,
        events: [
          StudioTurnEvent(
            id: 'approval-event',
            turnId: 'turn-1',
            requestId: 'request-1',
            threadId: 'thread-1',
            type: StudioTurnEventType.approvalRequest,
            title: 'Approval preview with secret',
            detail: 'rm -rf /Users/example/customer-project',
            timestamp: startedAt,
            approvalId: 'approval-1',
            approvalState: ApprovalRequestState.approved,
            approvalPreview: 'token=super-secret-value',
          ),
        ],
        toolResults: const [
          ToolResultEnvelope(
            toolCallId: 'command-1',
            toolName: 'run_command',
            status: ToolResultStatus.success,
            summary: 'super-secret-value',
            data: {'command': 'rm -rf /Users/example/customer-project'},
            stdout: 'customer data',
            artifacts: ['artifact-1'],
            changedFiles: ['customer.dart'],
          ),
        ],
        providerDiagnostics: [
          ProviderLifecycleEvent(
            requestId: 'request-1',
            turnId: 'turn-1',
            kind: ProviderLifecycleEventKind.firstTextDelta,
            timestamp: startedAt,
            model: 'gpt-5',
            detail: 'Bearer super-secret-value',
          ),
        ],
        planTargetProgress: [
          PlanTargetProgress(
            path: 'lib/customer_secret.dart',
            intent: 'change secret',
            state: PlanTargetProgressState.applied,
            patchSetId: 'patch-1',
            detail: 'api_key=super-secret-value',
            updatedAt: completedAt,
          ),
        ],
        createdAt: startedAt,
        updatedAt: completedAt,
        completedAt: completedAt,
        finalOutcome: StudioTurnOutcome.verified,
      );
      final thread = StudioThread(
        id: 'thread-1',
        title: 'Sensitive customer task',
        status: StudioThreadStatus.done,
        turns: [turn],
        sourceArtifacts: [
          StudioSourceArtifact(
            id: 'artifact-1',
            kind: StudioSourceArtifactKind.generatedArtifact,
            title: 'Customer report',
            subtitle: 'super-secret-value',
            value: '/Users/example/customer-project/report.pdf',
            requestId: 'request-1',
            createdAt: completedAt,
          ),
        ],
        createdAt: startedAt,
        updatedAt: completedAt,
      );

      final trace = StudioTurnTraceBuilder.build(thread: thread, turn: turn);
      final encoded = jsonEncode(trace.toJson());

      expect(trace.spans.map((span) => span.kind), StudioTraceSpanKind.values);
      expect(encoded, contains('request-1'));
      expect(encoded, contains('command-1'));
      expect(encoded, contains('artifact-1'));
      expect(encoded, contains('patch-1'));
      expect(encoded, isNot(contains('super-secret-value')));
      expect(encoded, isNot(contains('/Users/example')));
      expect(encoded, isNot(contains('customer_secret.dart')));
      expect(encoded, isNot(contains('rm -rf')));
      expect(encoded, isNot(contains('Sensitive customer task')));
    },
  );
}
