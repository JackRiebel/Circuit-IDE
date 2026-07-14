import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/config/models_config.dart';
import '../../agent/providers/provider_interface.dart';
import '../../models/settings_model.dart';
import '../../theme/theme_tokens.dart';
import 'studio_workspace_opening.dart';

/// Lists connector-provided models or the built-in fallback catalog.
List<ModelInfo> studioComposerAvailableModels(SettingsModel settings) {
  if (settings.connectorModels.isNotEmpty) {
    return settings.connectorModels
        .map((model) => model.toModelInfo())
        .toList();
  }
  return ModelsConfig.ciscoModels;
}

/// Lets the user choose and open a project for the Studio session.
Future<void> chooseStudioComposerProjectRoot(WidgetRef ref) =>
    chooseStudioProjectRoot(ref);

/// Shared compact shape used by composer popup menus.
ShapeBorder studioComposerSoftMenuShape(ThemeTokens tokens) {
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(10),
    side: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.64)),
  );
}
