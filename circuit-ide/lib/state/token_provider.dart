import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/token_usage.dart';
import '../models/cost_info.dart';
import 'chat_provider.dart';

final tokenUsageProvider = Provider<TokenUsage>((ref) {
  return ref.watch(chatProvider).tokenUsage;
});

final costInfoProvider = Provider<CostInfo>((ref) {
  return ref.watch(chatProvider).costInfo;
});
