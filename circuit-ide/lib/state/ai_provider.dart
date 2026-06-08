import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/config/models_config.dart';
import '../agent/providers/provider_interface.dart';
import '../enums/ai_provider.dart';
import 'settings_provider.dart';

final currentModelProvider = Provider<String>((ref) {
  final settings = ref.watch(settingsProvider);
  return ModelsConfig.coerceModelForProvider(
    AIProviderType.cisco,
    settings.ciscoModel,
  );
});

final availableModelsProvider = Provider<List<ModelInfo>>((ref) {
  final settings = ref.watch(settingsProvider);
  final cached = settings.connectorModels.map((model) => model.toModelInfo());
  return cached.isEmpty ? ModelsConfig.ciscoModels : cached.toList();
});
