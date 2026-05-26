import '../../enums/ai_provider.dart';
import '../../models/routing_models.dart';
import '../providers/provider_interface.dart';

class ModelsConfig {
  static const defaultCiscoModel = 'gpt-5-nano';
  static const defaultAnthropicModel = 'claude-sonnet-4-20250514';

  static const ciscoModels = [
    ModelInfo(
      id: 'gpt-5-nano',
      displayName: 'GPT-5-nano - Free tier (120K context)',
      contextWindow: 120000,
      inputCostPer1k: 0,
      outputCostPer1k: 0,
    ),
    ModelInfo(
      id: 'gemini-3.1-flash-lite',
      displayName: 'Gemini 3.1 Flash Lite - Free tier (120K context)',
      contextWindow: 120000,
      inputCostPer1k: 0,
      outputCostPer1k: 0,
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

  /// Tier mappings for each provider.
  static const _ciscoTierMap = {
    ModelTier.fast: 'gemini-3.1-flash-lite',
    ModelTier.balanced: defaultCiscoModel,
    ModelTier.powerful: defaultCiscoModel,
  };

  static const _anthropicTierMap = {
    ModelTier.fast: 'claude-3-5-haiku-20241022',
    ModelTier.balanced: 'claude-sonnet-4-20250514',
    ModelTier.powerful: 'claude-opus-4-20250514',
  };

  static ModelInfo? getModel(String id) {
    for (final m in [...ciscoModels, ...anthropicModels]) {
      if (m.id == id) return m;
    }
    return null;
  }

  static List<ModelInfo> modelsForProvider(AIProviderType provider) {
    return switch (provider) {
      AIProviderType.cisco => ciscoModels,
      AIProviderType.anthropic => anthropicModels,
    };
  }

  static String defaultModelForProvider(AIProviderType provider) {
    return switch (provider) {
      AIProviderType.cisco => defaultCiscoModel,
      AIProviderType.anthropic => defaultAnthropicModel,
    };
  }

  static String coerceModelForProvider(AIProviderType provider, String? model) {
    final models = modelsForProvider(provider);
    if (model != null && models.any((m) => m.id == model)) {
      return model;
    }
    return defaultModelForProvider(provider);
  }

  /// Get the model ID for a given provider and tier.
  static String getModelForTier(AIProviderType provider, ModelTier tier) {
    return switch (provider) {
      AIProviderType.cisco => _ciscoTierMap[tier]!,
      AIProviderType.anthropic => _anthropicTierMap[tier]!,
    };
  }

  /// Get the tier for a given model ID.
  static ModelTier? getTierForModel(String modelId) {
    for (final entry in _ciscoTierMap.entries) {
      if (entry.value == modelId) return entry.key;
    }
    for (final entry in _anthropicTierMap.entries) {
      if (entry.value == modelId) return entry.key;
    }
    return null;
  }
}
