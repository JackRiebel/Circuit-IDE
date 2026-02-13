import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/utils/platform_utils.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/logger.dart';

class PluginManifest {
  final String id;
  final String name;
  final String version;
  final String description;
  final String? author;
  final List<String> capabilities;

  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    this.author,
    this.capabilities = const [],
  });

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    return PluginManifest(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      description: json['description'] as String? ?? '',
      author: json['author'] as String?,
      capabilities:
          (json['capabilities'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }
}

class PluginService {
  final List<PluginManifest> _plugins = [];

  List<PluginManifest> get plugins => List.unmodifiable(_plugins);

  static String get pluginsDir =>
      p.join(PlatformUtils.configDir, AppConstants.pluginsDirName);

  Future<void> loadPlugins() async {
    _plugins.clear();
    final dir = Directory(pluginsDir);
    if (!await dir.exists()) return;

    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;

      final manifestFile =
          File(p.join(entity.path, 'manifest.json'));
      if (!await manifestFile.exists()) continue;

      try {
        final json = jsonDecode(await manifestFile.readAsString())
            as Map<String, dynamic>;
        _plugins.add(PluginManifest.fromJson(json));
        Logger.info('Loaded plugin: ${json['name']}', 'PluginService');
      } catch (e) {
        Logger.error('Failed to load plugin from ${entity.path}', e);
      }
    }
  }
}
