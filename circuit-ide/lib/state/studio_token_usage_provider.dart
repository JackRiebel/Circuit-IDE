import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/token_usage.dart';
import 'studio_thread_provider.dart';

final studioTokenUsageProvider = Provider<TokenUsage>((ref) {
  final thread = ref.watch(studioThreadProvider).selectedThread;
  return thread?.tokenUsage ?? const TokenUsage();
});

final studioTokenUsageForTaskViewProvider =
    Provider.family<TokenUsage, String?>((ref, taskId) {
      final threadState = ref.watch(studioThreadProvider);
      final thread = threadState.threadForTaskView(taskId);
      return thread?.tokenUsage ?? const TokenUsage();
    });
