import 'dart:io';

import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/ui/studio/studio_message_sender.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  StudioTurn buildTurn({
    String displayPrompt = 'Verify the release build.',
    String modelPrompt =
        'INTERNAL: execute a scoped verification workflow without exposing this instruction.',
    String taskTitle = 'Verify release build',
  }) {
    final now = DateTime(2026, 7, 10);
    return StudioTurn(
      id: 'turn-prompt-separation',
      threadId: 'thread-prompt-separation',
      requestId: 'request-prompt-separation',
      userMessageId: 'message-prompt-separation',
      prompt: displayPrompt,
      modelPrompt: modelPrompt,
      taskTitle: taskTitle,
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      createdAt: now,
      updatedAt: now,
    );
  }

  test(
    'StudioTurn persists display, model, and title prompts independently',
    () {
      final turn = buildTurn();

      final decoded = StudioTurn.fromJson(turn.toJson());
      expect(decoded, isNotNull);
      expect(decoded!.displayPrompt, 'Verify the release build.');
      expect(
        decoded.modelPrompt,
        contains('INTERNAL: execute a scoped verification workflow'),
      );
      expect(decoded.taskTitle, 'Verify release build');
    },
  );

  test('legacy prompt-only turns migrate without data loss', () {
    final json = buildTurn().toJson()
      ..remove('displayPrompt')
      ..remove('modelPrompt')
      ..remove('taskTitle')
      ..['prompt'] = 'Legacy visible prompt';

    final migrated = StudioTurn.fromJson(json);
    expect(migrated, isNotNull);
    expect(migrated!.displayPrompt, 'Legacy visible prompt');
    expect(migrated.modelPrompt, 'Legacy visible prompt');
    expect(migrated.taskTitle, 'Legacy visible prompt');
  });

  test('provider history only receives the display prompt', () {
    final now = DateTime(2026, 7, 10);
    final thread = StudioThread(
      id: 'thread-prompt-separation',
      title: 'Verify release build',
      turns: [buildTurn()],
      createdAt: now,
      updatedAt: now,
    );

    final history = studioModelHistoryForThread(thread);
    expect(history.single.content, 'Verify the release build.');
    expect(
      history.single.content,
      isNot(contains('INTERNAL: execute a scoped verification workflow')),
    );
  });

  test('Studio UI never reads the model-only prompt field', () async {
    final files = await Directory('lib/ui/studio')
        .list(recursive: true)
        .where(
          (entity) =>
              entity is File &&
              entity.path.endsWith('.dart') &&
              !entity.path.endsWith('studio_message_sender.dart'),
        )
        .cast<File>()
        .toList();
    expect(files, isNotEmpty);
    for (final file in files) {
      expect(
        await file.readAsString(),
        isNot(contains('modelPrompt')),
        reason: '${file.path} must render only display prompt/event data.',
      );
    }
  });

  test('message sender stores each prompt in its intended boundary', () async {
    final sender = await File(
      'lib/ui/studio/studio_message_sender.dart',
    ).readAsString();

    expect(sender, contains('prompt: visibleText'));
    expect(sender, contains('modelPrompt: outboundText'));
    expect(sender, contains('taskTitle: threadTitle ?? visibleText'));
    expect(sender, contains("modelPrompt: ''"));
    expect(sender, contains('taskTitle: patch.title'));
  });
}
