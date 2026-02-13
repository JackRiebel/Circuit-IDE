import '../providers/provider_interface.dart';

class ModelsConfig {
  static const ciscoModels = [
    ModelInfo(
      id: 'gpt-4.1',
      displayName: 'GPT-4.1 - Complex reasoning (1M context)',
      contextWindow: 1000000,
      inputCostPer1k: 0.002,
      outputCostPer1k: 0.008,
    ),
    ModelInfo(
      id: 'gpt-4.1-mini',
      displayName: 'GPT-4.1 Mini - Fast & efficient (1M context)',
      contextWindow: 1000000,
      inputCostPer1k: 0.0004,
      outputCostPer1k: 0.0016,
    ),
    ModelInfo(
      id: 'gpt-4.1-nano',
      displayName: 'GPT-4.1 Nano - Ultra fast (1M context)',
      contextWindow: 1000000,
      inputCostPer1k: 0.0001,
      outputCostPer1k: 0.0004,
    ),
  ];

  static const anthropicModels = [
    ModelInfo(
      id: 'claude-sonnet-4-20250514',
      displayName: 'Claude Sonnet 4 - Fast & capable',
      contextWindow: 200000,
      inputCostPer1k: 0.003,
      outputCostPer1k: 0.015,
    ),
    ModelInfo(
      id: 'claude-opus-4-20250514',
      displayName: 'Claude Opus 4 - Most capable',
      contextWindow: 200000,
      inputCostPer1k: 0.015,
      outputCostPer1k: 0.075,
    ),
    ModelInfo(
      id: 'claude-3-5-sonnet-20241022',
      displayName: 'Claude 3.5 Sonnet - Balanced',
      contextWindow: 200000,
      inputCostPer1k: 0.003,
      outputCostPer1k: 0.015,
    ),
    ModelInfo(
      id: 'claude-3-5-haiku-20241022',
      displayName: 'Claude 3.5 Haiku - Fast & efficient',
      contextWindow: 200000,
      inputCostPer1k: 0.001,
      outputCostPer1k: 0.005,
    ),
  ];

  static ModelInfo? getModel(String id) {
    for (final m in [...ciscoModels, ...anthropicModels]) {
      if (m.id == id) return m;
    }
    return null;
  }
}
