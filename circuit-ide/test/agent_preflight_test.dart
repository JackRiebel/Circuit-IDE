import 'package:circuit_ide/models/agent_preflight.dart';
import 'package:circuit_ide/models/context_attachment.dart';
import 'package:circuit_ide/state/chat_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preflight blocks when AI is disconnected', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final result = await container
        .read(chatProvider.notifier)
        .preflightMessage('hello', const []);

    expect(result.canSend, isFalse);
    expect(
      result.issues.map((issue) => issue.severity),
      contains(AgentPreflightSeverity.blocking),
    );
    expect(result.primaryIssue?.recoveryAction, isNotNull);
  });

  test('preflight reports oversized context', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final attachment = ContextAttachment(
      id: 'huge',
      type: ContextAttachmentType.note,
      label: 'Huge context',
      content: List.filled(500000, 'x').join(),
      createdAt: DateTime(2026, 5, 25),
    );

    final result = await container.read(chatProvider.notifier).preflightMessage(
      'summarize',
      [attachment],
    );

    expect(result.estimatedTokens, greaterThan(result.contextWindow));
    expect(
      result.issues.any(
        (issue) =>
            issue.recoveryAction == AgentPreflightRecoveryAction.reduceContext,
      ),
      isTrue,
    );
  });
}
