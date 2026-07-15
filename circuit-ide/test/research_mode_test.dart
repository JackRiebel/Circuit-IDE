import 'package:circuit_ide/agent/tools/tool_registry.dart';
import 'package:circuit_ide/agent/turn_outcome_validator.dart';
import 'package:circuit_ide/models/studio_shell.dart';
import 'package:circuit_ide/models/tool_call_info.dart';
import 'package:circuit_ide/models/tool_result_envelope.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:circuit_ide/ui/studio/studio_turn_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Research mode exposes only policy-gated web tools without a workspace',
    () {
      final mode = studioToolModeForIntent(
        intent: TurnIntent.ask,
        promptMode: StudioPromptMode.research,
        hasWorkspace: false,
        planModeEnabled: false,
      );

      expect(mode, AgentToolMode.research);
      expect(StudioPromptMode.research.label, 'Research');
      expect(ToolRegistry.toolsForMode(mode).map((tool) => tool.name).toSet(), {
        'web_search',
        'web_fetch',
      });
      final prompt = studioOutboundPromptForIntent(
        text: 'Research current implementation guidance.',
        intent: TurnIntent.ask,
        planModeEnabled: false,
        promptMode: StudioPromptMode.research,
      );
      expect(prompt, contains('Research Mode is enabled'));
      expect(prompt, contains('## Sources'));
      expect(prompt, contains('## Evidence table'));
      expect(prompt, contains('## Conflict review'));
      expect(prompt, contains('Checked: YYYY-MM-DD'));
      expect(prompt, contains('two independent publisher sources'));
    },
  );

  test('Research results require a dated direct-source section', () {
    const validator = TurnOutcomeValidator();
    const call = ToolCallInfo(
      id: 'research-fetch',
      name: 'web_fetch',
      arguments: {'url': 'https://example.com/report'},
    );
    const result = ToolResultEnvelope(
      toolCallId: 'research-fetch',
      toolName: 'web_fetch',
      status: ToolResultStatus.success,
      summary: 'Fetched report.',
    );
    const corroboratingCall = ToolCallInfo(
      id: 'research-fetch-2',
      name: 'web_fetch',
      arguments: {'url': 'https://agency.gov/rollout'},
    );
    const corroboratingResult = ToolResultEnvelope(
      toolCallId: 'research-fetch-2',
      toolName: 'web_fetch',
      status: ToolResultStatus.success,
      summary: 'Fetched agency rollout record.',
    );

    final missingSources = validator.validate(
      intent: TurnIntent.ask,
      toolMode: AgentToolMode.research,
      content: 'The report confirms the rollout is approved.',
      toolCalls: const [call],
      toolResults: const [result],
    );
    final cited = validator.validate(
      intent: TurnIntent.ask,
      toolMode: AgentToolMode.research,
      content: '''
The report confirms the rollout is approved. https://example.com/report https://agency.gov/rollout

## Evidence table
| Claim | Sources | Evidence status |
| --- | --- | --- |
| The rollout is approved. | https://example.com/report<br>https://agency.gov/rollout | Direct source attached |

## Conflict review
No material conflicts identified after comparing the direct source statements.

## Sources
- https://example.com/report — Checked: 2026-07-12
- https://agency.gov/rollout — Checked: 2026-07-12
''',
      toolCalls: const [call, corroboratingCall],
      toolResults: const [result, corroboratingResult],
    );

    expect(missingSources.status, TurnOutcomeValidationStatus.invalid);
    expect(missingSources.userMessage, contains('Sources section'));
    expect(cited.status, TurnOutcomeValidationStatus.valid);
  });

  test('Research mode requires an explicit direct-source conflict review', () {
    const validator = TurnOutcomeValidator();
    const calls = [
      ToolCallInfo(
        id: 'source-a',
        name: 'web_fetch',
        arguments: {'url': 'https://agency.gov/record'},
      ),
      ToolCallInfo(
        id: 'source-b',
        name: 'web_fetch',
        arguments: {'url': 'https://independent.example/report'},
      ),
    ];
    const results = [
      ToolResultEnvelope(
        toolCallId: 'source-a',
        toolName: 'web_fetch',
        status: ToolResultStatus.success,
        summary: 'Fetched agency record.',
      ),
      ToolResultEnvelope(
        toolCallId: 'source-b',
        toolName: 'web_fetch',
        status: ToolResultStatus.success,
        summary: 'Fetched independent report.',
      ),
    ];
    const baseContent = '''
The rollout has a disputed state. https://agency.gov/record https://independent.example/report

## Evidence table
| Claim | Sources | Evidence status |
| --- | --- | --- |
| The rollout state is disputed. | https://agency.gov/record<br>https://independent.example/report | Requires conflict review |

## Sources
- https://agency.gov/record — Checked: 2026-07-13
- https://independent.example/report — Checked: 2026-07-13
''';

    final missing = validator.validate(
      intent: TurnIntent.ask,
      toolMode: AgentToolMode.research,
      content: baseContent,
      toolCalls: calls,
      toolResults: results,
    );
    final unresolved = validator.validate(
      intent: TurnIntent.ask,
      toolMode: AgentToolMode.research,
      content:
          '''
${baseContent.replaceFirst('## Sources', '## Conflict review\n- Conflict: the agency record calls the rollout active, while the independent report calls it paused. https://agency.gov/record https://independent.example/report Resolution: unresolved pending a newer direct record.\n\n## Sources')}
''',
      toolCalls: calls,
      toolResults: results,
    );

    expect(missing.status, TurnOutcomeValidationStatus.invalid);
    expect(missing.userMessage, contains('Conflict review'));
    expect(unresolved.status, TurnOutcomeValidationStatus.valid);
  });

  test('Research mode makes a single-source exception explicit', () {
    const validator = TurnOutcomeValidator();
    const call = ToolCallInfo(
      id: 'research-fetch',
      name: 'web_fetch',
      arguments: {'url': 'https://agency.gov/rollout'},
    );
    const result = ToolResultEnvelope(
      toolCallId: 'research-fetch',
      toolName: 'web_fetch',
      status: ToolResultStatus.success,
      summary: 'Fetched official record.',
    );
    const baseContent = '''
The official record says the rollout is active. https://agency.gov/rollout

## Evidence table
| Claim | Sources | Evidence status |
| --- | --- | --- |
| The rollout is active. | https://agency.gov/rollout | Single publisher — needs corroboration |

## Conflict review
No material conflicts identified after comparing the available direct source statement.

## Sources
- https://agency.gov/rollout — Checked: 2026-07-13
''';

    final missingLimitation = validator.validate(
      intent: TurnIntent.ask,
      toolMode: AgentToolMode.research,
      content: baseContent,
      toolCalls: const [call],
      toolResults: const [result],
    );
    final disclosed = validator.validate(
      intent: TurnIntent.ask,
      toolMode: AgentToolMode.research,
      content:
          '''
$baseContent
Single-source limitation: only the official direct record was available; this claim still needs independent corroboration.
''',
      toolCalls: const [call],
      toolResults: const [result],
    );

    expect(missingLimitation.status, TurnOutcomeValidationStatus.invalid);
    expect(missingLimitation.userMessage, contains('independent publisher'));
    expect(disclosed.status, TurnOutcomeValidationStatus.valid);
  });

  test(
    'Research source diversity uses persisted fetch provenance as fallback',
    () {
      const validator = TurnOutcomeValidator();
      const results = [
        ToolResultEnvelope(
          toolCallId: 'lost-call-1',
          toolName: 'web_fetch',
          status: ToolResultStatus.success,
          summary: 'Fetched source one.',
          data: {
            'rawResult':
                'Source: https://docs.example.com/guide\nChecked: 2026-07-13',
          },
        ),
        ToolResultEnvelope(
          toolCallId: 'lost-call-2',
          toolName: 'web_fetch',
          status: ToolResultStatus.success,
          summary: 'Fetched source two.',
          data: {
            'rawResult':
                'Source: https://agency.gov/record\nChecked: 2026-07-13',
          },
        ),
      ];

      final outcome = validator.validate(
        intent: TurnIntent.ask,
        toolMode: AgentToolMode.research,
        content: '''
The direct records support the current conclusion. https://docs.example.com/guide https://agency.gov/record

## Evidence table
| Claim | Sources | Evidence status |
| --- | --- | --- |
| The conclusion is supported. | https://docs.example.com/guide<br>https://agency.gov/record | Direct source attached |

## Conflict review
No material conflicts identified after comparing the direct source statements.

## Sources
- https://docs.example.com/guide — Checked: 2026-07-13
- https://agency.gov/record — Checked: 2026-07-13
''',
        toolCalls: const [],
        toolResults: results,
      );

      expect(outcome.status, TurnOutcomeValidationStatus.valid);
    },
  );

  test('Research mode refuses an uncited answer with no fetched source', () {
    const validator = TurnOutcomeValidator();

    final result = validator.validate(
      intent: TurnIntent.ask,
      toolMode: AgentToolMode.research,
      content: 'The rollout is approved.',
      toolCalls: const [],
      toolResults: const [],
    );

    expect(result.status, TurnOutcomeValidationStatus.invalid);
    expect(result.userMessage, contains('fetch at least one direct source'));
  });

  test(
    'Research mode requires every material claim to use fetched evidence',
    () {
      const validator = TurnOutcomeValidator();
      const calls = [
        ToolCallInfo(
          id: 'source-a',
          name: 'web_fetch',
          arguments: {'url': 'https://agency.gov/record'},
        ),
        ToolCallInfo(
          id: 'source-b',
          name: 'web_fetch',
          arguments: {'url': 'https://independent.example/report'},
        ),
      ];
      const results = [
        ToolResultEnvelope(
          toolCallId: 'source-a',
          toolName: 'web_fetch',
          status: ToolResultStatus.success,
          summary: 'Fetched agency record.',
        ),
        ToolResultEnvelope(
          toolCallId: 'source-b',
          toolName: 'web_fetch',
          status: ToolResultStatus.success,
          summary: 'Fetched independent report.',
        ),
      ];
      const base = '''
The official record says the rollout is active. https://agency.gov/record
An unfetched blog claims a separate deadline. https://unfetched.example/deadline

## Evidence table
| Claim | Sources | Evidence status |
| --- | --- | --- |
| The rollout is active. | https://agency.gov/record | Direct source attached |
| Separate deadline claim. | https://unfetched.example/deadline | Direct source attached |

## Conflict review
No material conflicts identified after comparing the direct source statements.

## Sources
- https://agency.gov/record — Checked: 2026-07-13
- https://independent.example/report — Checked: 2026-07-13
''';

      final overstated = validator.validate(
        intent: TurnIntent.ask,
        toolMode: AgentToolMode.research,
        content: base,
        toolCalls: calls,
        toolResults: results,
      );
      final disclosed = validator.validate(
        intent: TurnIntent.ask,
        toolMode: AgentToolMode.research,
        content: base.replaceFirst(
          'Direct source attached |\n\n## Conflict review',
          'Unsupported — needs direct source |\n\n## Conflict review',
        ),
        toolCalls: calls,
        toolResults: results,
      );

      expect(overstated.status, TurnOutcomeValidationStatus.invalid);
      expect(overstated.userMessage, contains('matching successfully fetched'));
      expect(disclosed.status, TurnOutcomeValidationStatus.valid);
    },
  );
}
