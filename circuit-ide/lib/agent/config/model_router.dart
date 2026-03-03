import '../../enums/ai_provider.dart';
import '../../models/routing_models.dart';
import 'models_config.dart';

class ModelRouter {
  // --- Classification heuristics ---

  static final _simplePatterns = [
    RegExp(r'^(what|who|where|when|how)\s+(is|are|was|were|do|does|did)\b', caseSensitive: false),
    RegExp(r'^(explain|describe|show|list|tell me)\b', caseSensitive: false),
    RegExp(r'^(hi|hello|hey|thanks|thank you)\b', caseSensitive: false),
  ];

  static final _complexPatterns = [
    RegExp(r'\b(refactor|redesign|implement|architect|migrate|rewrite)\b', caseSensitive: false),
    RegExp(r'\b(debug|fix this error|stack trace|traceback)\b', caseSensitive: false),
    RegExp(r'\b(multiple files|across files|entire project|all files)\b', caseSensitive: false),
    RegExp(r'\b(security|vulnerability|performance|optimize)\b', caseSensitive: false),
  ];

  static final _codeBlockRe = RegExp(r'```');
  static final _multiFileRe = RegExp(r'\b\w+\.\w+\b.*\b\w+\.\w+\b');

  /// Classify a user message's complexity.
  static TaskComplexity classify(String message, {String? activeFileContent}) {
    final trimmed = message.trim();
    final length = trimmed.length;

    // Very short messages are likely simple
    if (length < 50) {
      // Unless they contain complex keywords
      for (final pattern in _complexPatterns) {
        if (pattern.hasMatch(trimmed)) return TaskComplexity.moderate;
      }
      return TaskComplexity.simple;
    }

    // Check for complex signals
    int complexScore = 0;

    for (final pattern in _complexPatterns) {
      if (pattern.hasMatch(trimmed)) complexScore += 2;
    }

    if (length > 500) complexScore += 2;
    if (_codeBlockRe.hasMatch(trimmed)) complexScore += 1;
    if (_multiFileRe.hasMatch(trimmed)) complexScore += 1;

    // Check for simple signals
    int simpleScore = 0;
    for (final pattern in _simplePatterns) {
      if (pattern.hasMatch(trimmed)) simpleScore += 2;
    }

    if (length < 100) simpleScore += 1;

    // Active file content adds moderate complexity
    if (activeFileContent != null && activeFileContent.length > 500) {
      complexScore += 1;
    }

    // Determine complexity
    if (complexScore >= 3) return TaskComplexity.complex;
    if (complexScore >= 1 || simpleScore < 2) return TaskComplexity.moderate;
    return TaskComplexity.simple;
  }

  /// Select the best model for the given complexity.
  static String selectModel(
    TaskComplexity complexity,
    AIProviderType provider,
    RoutingConfig config,
  ) {
    ModelTier targetTier = switch (complexity) {
      TaskComplexity.simple => ModelTier.fast,
      TaskComplexity.moderate => ModelTier.balanced,
      TaskComplexity.complex => ModelTier.powerful,
    };

    // Apply preference bias
    if (config.preferSpeed && targetTier.index > 0) {
      targetTier = ModelTier.values[targetTier.index - 1];
    } else if (config.preferQuality && targetTier.index < ModelTier.values.length - 1) {
      targetTier = ModelTier.values[targetTier.index + 1];
    }

    // Enforce minimum tier
    if (targetTier.index < config.minTier.index) {
      targetTier = config.minTier;
    }

    return ModelsConfig.getModelForTier(provider, targetTier);
  }

  /// Estimate cost savings compared to always using the powerful model.
  static double estimateSavings(
    AIProviderType provider,
    String routedModel,
    int estimatedTokens,
  ) {
    final powerfulModel = ModelsConfig.getModelForTier(provider, ModelTier.powerful);
    final powerfulInfo = ModelsConfig.getModel(powerfulModel);
    final routedInfo = ModelsConfig.getModel(routedModel);

    if (powerfulInfo == null || routedInfo == null) return 0;

    final powerfulCost = (estimatedTokens / 1000) *
        ((powerfulInfo.inputCostPer1k + powerfulInfo.outputCostPer1k) / 2);
    final routedCost = (estimatedTokens / 1000) *
        ((routedInfo.inputCostPer1k + routedInfo.outputCostPer1k) / 2);

    return (powerfulCost - routedCost).clamp(0, double.infinity);
  }
}
