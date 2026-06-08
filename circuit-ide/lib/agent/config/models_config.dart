import '../../enums/ai_provider.dart';
import '../../models/routing_models.dart';
import '../providers/provider_interface.dart';

class ModelsConfig {
  static const defaultCiscoModel = 'gpt-5-nano';

  static const ciscoModels = [
    ModelInfo(
      id: 'gpt-5-nano',
      displayName: 'GPT-5-nano - Free tier (120K context)',
      contextWindow: 120000,
      inputCostPer1k: 0,
      outputCostPer1k: 0,
      supportsTools: true,
    ),
    ModelInfo(
      id: 'gemini-3.1-flash-lite',
      displayName: 'Gemini 3.1 Flash Lite - Free tier (120K context)',
      contextWindow: 120000,
      inputCostPer1k: 0,
      outputCostPer1k: 0,
      supportsTools: true,
    ),
  ];

  static const _ciscoTierMap = {
    ModelTier.fast: 'gemini-3.1-flash-lite',
    ModelTier.balanced: defaultCiscoModel,
    ModelTier.powerful: defaultCiscoModel,
  };

  static ModelInfo? getModel(String id) {
    for (final m in ciscoModels) {
      if (m.id == id) return m;
    }
    return null;
  }

  static List<ModelInfo> modelsForProvider(AIProviderType provider) {
    return switch (provider) {
      AIProviderType.cisco => ciscoModels,
    };
  }

  static String defaultModelForProvider(AIProviderType provider) {
    return switch (provider) {
      AIProviderType.cisco => defaultCiscoModel,
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
    };
  }

  /// Get the tier for a given model ID.
  static ModelTier? getTierForModel(String modelId) {
    for (final entry in _ciscoTierMap.entries) {
      if (entry.value == modelId) return entry.key;
    }
    return null;
  }
}
