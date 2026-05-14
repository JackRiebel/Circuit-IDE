import '../config/models_config.dart';
import '../../models/cost_info.dart';
import '../../models/token_usage.dart';

class CostTracker {
  TokenUsage _totalUsage = const TokenUsage();
  TokenUsage _lastUsage = const TokenUsage();
  CostInfo _costInfo = const CostInfo();

  TokenUsage get totalUsage => _totalUsage;
  TokenUsage get lastUsage => _lastUsage;
  CostInfo get costInfo => _costInfo;

  void addUsage(String model, int promptTokens, int completionTokens) {
    _lastUsage = TokenUsage(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: promptTokens + completionTokens,
    );
    _totalUsage = _totalUsage.add(
      prompt: promptTokens,
      completion: completionTokens,
    );

    final modelInfo = ModelsConfig.getModel(model);
    if (modelInfo != null) {
      final cost =
          (promptTokens / 1000 * modelInfo.inputCostPer1k) +
          (completionTokens / 1000 * modelInfo.outputCostPer1k);
      _costInfo = _costInfo.add(cost);
    }
  }

  void reset() {
    _totalUsage = const TokenUsage();
    _lastUsage = const TokenUsage();
    _costInfo = const CostInfo();
  }
}
