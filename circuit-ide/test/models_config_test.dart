import 'package:circuit_ide/agent/config/models_config.dart';
import 'package:circuit_ide/enums/ai_provider.dart';
import 'package:circuit_ide/models/routing_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModelsConfig', () {
    test('Circuit models only include current free-tier IDs', () {
      expect(ModelsConfig.ciscoModels.map((model) => model.id), [
        'gpt-5-nano',
        'gemini-3.1-flash-lite',
      ]);
      expect(
        ModelsConfig.ciscoModels.every(
          (model) => model.contextWindow == 120000,
        ),
        isTrue,
      );
      expect(
        ModelsConfig.ciscoModels.every((model) => model.inputCostPer1k == 0),
        isTrue,
      );
      expect(
        ModelsConfig.ciscoModels.every((model) => model.outputCostPer1k == 0),
        isTrue,
      );
    });

    test('legacy Circuit model IDs fall back to GPT-5-nano', () {
      expect(
        ModelsConfig.coerceModelForProvider(AIProviderType.cisco, 'gpt-4.1'),
        'gpt-5-nano',
      );
      expect(
        ModelsConfig.coerceModelForProvider(AIProviderType.cisco, 'gpt-4o'),
        'gpt-5-nano',
      );
      expect(
        ModelsConfig.coerceModelForProvider(
          AIProviderType.cisco,
          'gemini-3.1-flash-lite',
        ),
        'gemini-3.1-flash-lite',
      );
    });

    test('Circuit routing stays on available models', () {
      expect(
        ModelsConfig.getModelForTier(AIProviderType.cisco, ModelTier.fast),
        'gemini-3.1-flash-lite',
      );
      expect(
        ModelsConfig.getModelForTier(AIProviderType.cisco, ModelTier.balanced),
        'gpt-5-nano',
      );
      expect(
        ModelsConfig.getModelForTier(AIProviderType.cisco, ModelTier.powerful),
        'gpt-5-nano',
      );
    });
  });
}
