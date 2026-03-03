import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/utils/platform_utils.dart';
import '../models/routing_models.dart';

class ModelRoutingNotifier extends Notifier<RoutingConfig> {
  static String get _configFile =>
      p.join(PlatformUtils.configDir, 'routing_config.json');

  @override
  RoutingConfig build() {
    Future.microtask(_load);
    return const RoutingConfig();
  }

  Future<void> _load() async {
    try {
      final file = File(_configFile);
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        state = RoutingConfig.fromJson(json);
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final dir = Directory(PlatformUtils.configDir);
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File(_configFile);
      await file.writeAsString(state.toJsonString());
    } catch (_) {}
  }

  void setEnabled(bool enabled) {
    state = state.copyWith(enabled: enabled);
    _save();
  }

  void setMinTier(ModelTier tier) {
    state = state.copyWith(minTier: tier);
    _save();
  }

  void setPreferSpeed(bool value) {
    state = state.copyWith(
      preferSpeed: value,
      preferQuality: value ? false : state.preferQuality,
    );
    _save();
  }

  void setPreferQuality(bool value) {
    state = state.copyWith(
      preferQuality: value,
      preferSpeed: value ? false : state.preferSpeed,
    );
    _save();
  }

  void addSavings(double amount) {
    state = state.copyWith(
      costSavings: state.costSavings + amount,
      routedRequests: state.routedRequests + 1,
    );
    _save();
  }
}

final modelRoutingProvider =
    NotifierProvider<ModelRoutingNotifier, RoutingConfig>(
  ModelRoutingNotifier.new,
);
