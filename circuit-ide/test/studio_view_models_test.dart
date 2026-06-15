import 'package:circuit_ide/enums/message_role.dart';
import 'package:circuit_ide/models/agent_workspace.dart';
import 'package:circuit_ide/models/chat_message.dart';
import 'package:circuit_ide/models/command_run.dart';
import 'package:circuit_ide/models/studio_view_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TaskDisplayState.derive', () {
    test('prioritizes waiting for approval', () {
      final state = TaskDisplayState.derive(
        task: _task(status: AgentTaskStatus.running),
        isChatProcessing: true,
        isChatStreaming: false,
        hasAssistantResponse: false,
        hasPendingApproval: true,
        commands: const [],
      );

      expect(state.kind, TaskDisplayKind.waitingForApproval);
      expect(state.label, 'Waiting');
      expect(state.needsAttention, isTrue);
    });

    test('shows active command runs', () {
      final state = TaskDisplayState.derive(
        task: _task(status: AgentTaskStatus.running),
        isChatProcessing: false,
        isChatStreaming: false,
        hasAssistantResponse: false,
        hasPendingApproval: false,
        commands: [
          CommandRun(
            id: 'cmd-1',
            command: 'flutter test',
            status: CommandRunStatus.running,
            startedAt: DateTime(2026),
          ),
        ],
      );

      expect(state.kind, TaskDisplayKind.runningCommand);
      expect(state.label, 'Running');
      expect(state.isActive, isTrue);
    });

    test('marks completed chat responses as done', () {
      final messages = [
        ChatMessage(
          id: 'assistant-1',
          role: MessageRole.assistant,
          content: 'Done.',
          timestamp: DateTime(2026),
        ),
      ];

      final state = TaskDisplayState.derive(
        task: _task(status: AgentTaskStatus.running),
        isChatProcessing: false,
        isChatStreaming: false,
        hasAssistantResponse: hasAssistantResponse(messages),
        hasPendingApproval: false,
        commands: const [],
      );

      expect(state.kind, TaskDisplayKind.done);
      expect(state.label, 'Done');
    });

    test(
      'treats persisted completed tasks as done even if status is stale',
      () {
        final state = TaskDisplayState.derive(
          task: _task(
            status: AgentTaskStatus.running,
            completedAt: DateTime(2026, 1, 2),
          ),
          isChatProcessing: false,
          isChatStreaming: false,
          hasAssistantResponse: false,
          hasPendingApproval: false,
          commands: const [],
        );

        expect(state.kind, TaskDisplayKind.done);
        expect(state.label, 'Done');
      },
    );

    test('treats persisted task results as done even if status is stale', () {
      final state = TaskDisplayState.derive(
        task: _task(status: AgentTaskStatus.running, result: 'Finished.'),
        isChatProcessing: false,
        isChatStreaming: false,
        hasAssistantResponse: false,
        hasPendingApproval: false,
        commands: const [],
      );

      expect(state.kind, TaskDisplayKind.done);
    });

    test('marks provider errors as failed', () {
      final state = TaskDisplayState.derive(
        task: _task(status: AgentTaskStatus.running),
        isChatProcessing: false,
        isChatStreaming: false,
        hasAssistantResponse: false,
        hasPendingApproval: false,
        commands: const [],
        chatError: 'Request failed',
      );

      expect(state.kind, TaskDisplayKind.failed);
      expect(state.needsAttention, isTrue);
    });
  });
}

AgentTask _task({
  required AgentTaskStatus status,
  DateTime? completedAt,
  String? result,
}) {
  return AgentTask(
    id: 'task-1',
    mascotAlias: 'Benny',
    profile: AgentTaskProfile.investigate,
    status: status,
    goal: 'Review the project',
    result: result,
    createdAt: DateTime(2026),
    completedAt: completedAt,
  );
}
