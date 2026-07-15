import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cost_info.dart';
import '../models/token_usage.dart';
import 'chat_provider.dart';

/// Legacy Advanced Editor token state.
///
/// Studio must use `studio_token_usage_provider.dart` so its visible runtime
/// data comes from persisted Studio turns instead of the global chat runtime.
final legacyChatTokenUsageProvider = Provider<TokenUsage>((ref) {
  return ref.watch(chatProvider).tokenUsage;
});

final legacyChatLastTokenUsageProvider = Provider<TokenUsage>((ref) {
  return ref.watch(chatProvider).lastTokenUsage;
});

final legacyChatCostInfoProvider = Provider<CostInfo>((ref) {
  return ref.watch(chatProvider).costInfo;
});
