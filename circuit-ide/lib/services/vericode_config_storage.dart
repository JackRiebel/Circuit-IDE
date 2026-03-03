import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/utils/logger.dart';
import '../core/utils/platform_utils.dart';
import '../models/vericoding_models.dart';
import 'vericode_engine.dart';

class VericodeConfigStorage {
  static String get _configPath =>
      p.join(PlatformUtils.configDir, 'vericode.json');

  Future<bool> hasSavedConfig() async {
    return File(_configPath).exists();
  }

  Future<VericodeConfig> load() async {
    try {
      final file = File(_configPath);
      if (!await file.exists()) {
        return VericodeConfig(checks: VericodeEngine.defaultChecks());
      }

      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return VericodeConfig.fromJson(json);
    } catch (e) {
      Logger.error('Failed to load vericode config', e);
      return VericodeConfig(checks: VericodeEngine.defaultChecks());
    }
  }

  Future<void> save(VericodeConfig config) async {
    try {
      final file = File(_configPath);
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(config.toJson()));
      Logger.info('Vericode config saved', 'VericodeConfigStorage');
    } catch (e) {
      Logger.error('Failed to save vericode config', e);
    }
  }
}
