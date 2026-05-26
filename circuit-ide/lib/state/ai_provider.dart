import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/config/models_config.dart';
import '../agent/providers/provider_interface.dart';
import '../enums/ai_provider.dart';
import 'settings_provider.dart';

final currentModelProvider = Provider<String>((ref) {
  final settings = ref.watch(settingsProvider);
  final model = settings.activeProvider == AIProviderType.cisco
      ? settings.ciscoModel
      : settings.anthropicModel;
  return ModelsConfig.coerceModelForProvider(settings.activeProvider, model);
});

final availableModelsProvider = Provider<List<ModelInfo>>((ref) {
  final settings = ref.watch(settingsProvider);
  return ModelsConfig.modelsForProvider(settings.activeProvider);
});
