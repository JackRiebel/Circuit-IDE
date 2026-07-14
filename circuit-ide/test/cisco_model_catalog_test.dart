import 'package:circuit_ide/agent/providers/cisco_model_catalog.dart';
import 'package:circuit_ide/agent/providers/provider_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Cisco model catalog preserves explicit remote capabilities', () {
    final models = CiscoModelCatalog.parse({
      'data': [
        {
          'id': 'gpt-5-nano',
          'display_name': 'Managed nano',
          'context_window': 240000,
          'capabilities': {
            'tools': false,
            'vision': false,
            'structured_output': false,
            'thinking': false,
            'token_semantics': 'aggregate',
          },
          'input_cost_per_1k': 0.12,
          'output_cost_per_1k': 0.34,
        },
      ],
    });

    final model = models.single;
    expect(model.id, 'gpt-5-nano');
    expect(model.displayName, 'Managed nano');
    expect(model.contextWindow, 240000);
    expect(model.supportsTools, isFalse);
    expect(model.supportsImageInput, isFalse);
    expect(model.supportsJsonSchema, isFalse);
    expect(model.supportsReasoning, isFalse);
    expect(model.tokenSemantics, ProviderTokenSemantics.aggregateOnly);
    expect(model.inputCostPer1k, 0.12);
    expect(model.outputCostPer1k, 0.34);
  });

  test('Cisco model catalog uses built-in capability defaults safely', () {
    final models = CiscoModelCatalog.parse({
      'models': [
        {'id': 'gpt-5-nano'},
        {'model': 'unknown-managed-model'},
        {'id': '  '},
        <String, dynamic>{},
      ],
    });

    expect(models, hasLength(2));
    final known = models.first;
    expect(known.supportsTools, isTrue);
    expect(known.supportsImageInput, isTrue);
    expect(known.supportsJsonSchema, isTrue);
    expect(known.supportsReasoning, isTrue);
    expect(known.tokenSemantics, ProviderTokenSemantics.inputAndOutput);

    final unknown = models.last;
    expect(unknown.supportsTools, isFalse);
    expect(unknown.supportsImageInput, isFalse);
    expect(unknown.supportsJsonSchema, isFalse);
    expect(unknown.supportsReasoning, isFalse);
    expect(unknown.contextWindow, 120000);
  });

  test('Cisco bundled catalog remains the declared product fallback', () {
    final bundled = CiscoModelCatalog.bundled();

    expect(bundled.map((model) => model.id), contains('gpt-5-nano'));
    expect(CiscoModelCatalog.supportsImageInputFor('gpt-5-nano'), isTrue);
    expect(CiscoModelCatalog.supportsReasoningFor('gpt-5-nano'), isTrue);
    expect(
      CiscoModelCatalog.supportsToolsFor('unknown-managed-model'),
      isFalse,
    );
  });
}
