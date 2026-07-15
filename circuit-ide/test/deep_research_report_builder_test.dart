import 'package:circuit_ide/models/studio_source_artifact.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/models/tool_result_envelope.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:circuit_ide/services/deep_research_report_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 7, 13);

  StudioTurn turn({
    String modelPrompt =
        'Research Mode is enabled.\nResearch question: rollout',
    List<ToolResultEnvelope> toolResults = const [],
  }) => StudioTurn(
    id: 'turn-1',
    threadId: 'thread-1',
    requestId: 'request-1',
    userMessageId: 'message-1',
    prompt: 'Research the current rollout status.',
    modelPrompt: modelPrompt,
    taskTitle: 'Current rollout status',
    model: 'test-model',
    intent: TurnIntent.ask,
    contextSummary: const StudioContextSummary(
      projectLabel: 'No project selected',
    ),
    toolResults: toolResults,
    createdAt: createdAt,
    updatedAt: createdAt,
  );

  test('persists only fetched direct sources and surfaces evidence gaps', () {
    final report = const DeepResearchReportBuilder().build(
      turn: turn(
        toolResults: const [
          ToolResultEnvelope(
            toolCallId: 'fetch-1',
            toolName: 'web_fetch',
            status: ToolResultStatus.success,
            summary: 'Fetched agency record.',
            data: {
              'rawResult': '''
# Rollout record
Published: 2026-07-10
Source: https://agency.gov/rollout?tracking=private#section
Checked: 2026-07-13
''',
            },
          ),
          ToolResultEnvelope(
            toolCallId: 'fetch-2',
            toolName: 'web_fetch',
            status: ToolResultStatus.success,
            summary: 'Fetched implementation record.',
            data: {
              'rawResult': '''
# Implementation record
Source: https://developer.example.gov/implementation
Checked: 2026-07-13
''',
            },
          ),
          ToolResultEnvelope(
            toolCallId: 'search-1',
            toolName: 'web_search',
            status: ToolResultStatus.success,
            summary: 'Search snippets are not evidence.',
            data: {'rawResult': 'https://unfetched.example/search-result'},
          ),
        ],
      ),
      content: '''
The official rollout is active. https://agency.gov/rollout?tracking=private
The implementation record is current. https://developer.example.gov/implementation
The scope remains unclear and needs confirmation.
The model-only claim cites https://unfetched.example/search-result.

## Evidence table
| Claim | Sources | Evidence status |
| --- | --- | --- |
| Example | https://agency.gov/rollout | Direct source attached |

## Conflict review
- Conflict: the official and implementation records use different rollout terminology. https://agency.gov/rollout https://developer.example.gov/implementation Resolution: unresolved until the records define the same scope.

## Sources
- https://agency.gov/rollout — Checked: 2026-07-13
- https://developer.example.gov/implementation — Checked: 2026-07-13
''',
      now: createdAt,
    );

    expect(report, isNotNull);
    expect(report!.artifact.kind, StudioSourceArtifactKind.evidence);
    expect(report.directSourceCount, 2);
    expect(report.publisherScopeCount, 2);
    expect(report.unsupportedClaimCount, greaterThanOrEqualTo(2));
    expect(report.artifact.value, contains('## Research plan'));
    expect(report.artifact.value, contains('## Source acquisition'));
    expect(report.artifact.value, contains('## Conflict review'));
    expect(
      report.artifact.value,
      contains('implementation records use different rollout terminology'),
    );
    expect(report.artifact.value, contains('## Evidence table'));
    expect(report.artifact.value, contains('https://agency.gov/rollout'));
    expect(report.artifact.value, isNot(contains('tracking=private')));
    expect(report.artifact.value, contains('Unsupported — add direct source'));
    expect(report.artifact.subtitle, contains('2 independent publishers'));
  });

  test('does not materialize an evidence artifact for a non-research turn', () {
    final report = const DeepResearchReportBuilder().build(
      turn: turn(modelPrompt: 'Answer this from workspace context.'),
      content: 'A normal answer.',
      now: createdAt,
    );

    expect(report, isNull);
  });
}
