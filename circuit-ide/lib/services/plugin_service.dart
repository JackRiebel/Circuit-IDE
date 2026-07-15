import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/constants/app_constants.dart';
import '../core/utils/logger.dart';
import '../core/utils/platform_utils.dart';
import 'versioned_json_document.dart';

class PluginComponentPaths {
  final List<String> agents;
  final List<String> skills;
  final List<String> connectors;
  final List<String> mcpServers;
  final List<String> commands;
  final List<String> artifactTemplates;
  final List<String> hooks;

  const PluginComponentPaths({
    this.agents = const [],
    this.skills = const [],
    this.connectors = const [],
    this.mcpServers = const [],
    this.commands = const [],
    this.artifactTemplates = const [],
    this.hooks = const [],
  });

  List<String> get allPaths => [
    ...agents,
    ...skills,
    ...connectors,
    ...mcpServers,
    ...commands,
    ...artifactTemplates,
    ...hooks,
  ];

  Map<String, dynamic> toJson() => {
    'agents': agents,
    'skills': skills,
    'connectors': connectors,
    'mcpServers': mcpServers,
    'commands': commands,
    'artifactTemplates': artifactTemplates,
    'hooks': hooks,
  };

  factory PluginComponentPaths.fromJson(Map<String, dynamic>? json) {
    List<String> values(String key) =>
        (json?[key] as List<dynamic>? ?? const []).whereType<String>().toList(
          growable: false,
        );
    return PluginComponentPaths(
      agents: values('agents'),
      skills: values('skills'),
      connectors: values('connectors'),
      mcpServers: values('mcpServers'),
      commands: values('commands'),
      artifactTemplates: values('artifactTemplates'),
      hooks: values('hooks'),
    );
  }
}

/// The current package signature is an HMAC verified against a locally
/// trusted publisher key. The publisher key is never carried by a package.
/// The format is deliberately explicit so it can later add public-key
/// algorithms without accepting an unverifiable package in the meantime.
class PluginSignature {
  static const algorithmHmacSha256 = 'hmac-sha256';

  final String algorithm;
  final String signerId;
  final String value;

  const PluginSignature({
    required this.algorithm,
    required this.signerId,
    required this.value,
  });

  Map<String, dynamic> toJson() => {
    'algorithm': algorithm,
    'signerId': signerId,
    'value': value,
  };

  factory PluginSignature.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      throw const FormatException('Plugin package is missing a signature.');
    }
    final algorithm = json['algorithm'];
    final signerId = json['signerId'];
    final value = json['value'];
    if (algorithm is! String || signerId is! String || value is! String) {
      throw const FormatException('Plugin signature is malformed.');
    }
    return PluginSignature(
      algorithm: algorithm,
      signerId: signerId,
      value: value,
    );
  }
}

class PluginManifest {
  static const kind = 'circuit.plugin';
  static const schemaVersion = 1;

  final String id;
  final String name;
  final String version;
  final String description;
  final String? author;
  final PluginComponentPaths components;
  final PluginSignature signature;

  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    this.author,
    this.components = const PluginComponentPaths(),
    required this.signature,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'description': description,
    if (author != null) 'author': author,
    'components': components.toJson(),
    'signature': signature.toJson(),
  };

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    const supportedKeys = {
      'id',
      'name',
      'version',
      'description',
      'author',
      'components',
      'signature',
    };
    final unknown = json.keys.where((key) => !supportedKeys.contains(key));
    if (unknown.isNotEmpty) {
      throw FormatException(
        'Plugin manifest has unsupported fields: ${unknown.join(', ')}.',
      );
    }
    final id = json['id'];
    final name = json['name'];
    final version = json['version'];
    if (id is! String || name is! String || version is! String) {
      throw const FormatException('Plugin id, name, and version are required.');
    }
    return PluginManifest(
      id: id,
      name: name,
      version: version,
      description: json['description'] as String? ?? '',
      author: json['author'] as String?,
      components: PluginComponentPaths.fromJson(
        json['components'] as Map<String, dynamic>?,
      ),
      signature: PluginSignature.fromJson(
        json['signature'] as Map<String, dynamic>?,
      ),
    );
  }

  List<String> validate() {
    final errors = <String>[];
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{1,63}$').hasMatch(id)) {
      errors.add('Plugin id must be a lowercase identifier.');
    }
    if (name.trim().isEmpty) errors.add('Plugin name is required.');
    if (!RegExp(r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$').hasMatch(version)) {
      errors.add('Plugin version must use semantic versioning.');
    }
    if (signature.algorithm != PluginSignature.algorithmHmacSha256) {
      errors.add('Plugin signature algorithm is unsupported.');
    }
    if (signature.signerId.trim().isEmpty || signature.value.trim().isEmpty) {
      errors.add('Plugin signature signer and value are required.');
    }
    final paths = components.allPaths;
    if (paths.toSet().length != paths.length) {
      errors.add('Plugin component paths must not be duplicated.');
    }
    for (final path in paths) {
      if (!_isSafePackagePath(path)) {
        errors.add('Plugin component path is unsafe: $path');
      }
    }
    return errors;
  }
}

class InstalledPlugin {
  final PluginManifest manifest;
  final bool enabled;
  final DateTime installedAt;
  final DateTime? enabledAt;

  const InstalledPlugin({
    required this.manifest,
    required this.enabled,
    required this.installedAt,
    this.enabledAt,
  });
}

class PluginSignatureException implements Exception {
  final String message;

  const PluginSignatureException(this.message);

  @override
  String toString() => message;
}

/// Deterministic signing helper used by package publishers and package tests.
/// HMAC keys are configured by the receiving installation, never written into
/// a package directory.
abstract final class PluginPackageSigner {
  static String signPayload(
    Map<String, dynamic> payload,
    List<int> publisherKey,
  ) {
    return Hmac(
      sha256,
      publisherKey,
    ).convert(utf8.encode(_canonicalPayload(payload))).toString();
  }

  static bool verifies(
    Map<String, dynamic> payload,
    PluginSignature signature,
    Map<String, List<int>> trustedPublisherKeys,
  ) {
    final key = trustedPublisherKeys[signature.signerId];
    if (key == null ||
        signature.algorithm != PluginSignature.algorithmHmacSha256) {
      return false;
    }
    return signPayload(payload, key) == signature.value;
  }
}

class PluginService {
  static const _manifestFileName = 'manifest.json';
  static const _stateFileName = '.circuit-plugin-state.json';

  final String pluginPackagesDir;
  final Map<String, List<int>> trustedPublisherKeys;
  final List<InstalledPlugin> _plugins = [];

  PluginService({
    String? pluginPackagesDir,
    Map<String, List<int>> trustedPublisherKeys = const {},
  }) : pluginPackagesDir =
           pluginPackagesDir ??
           p.join(PlatformUtils.configDir, AppConstants.pluginsDirName),
       trustedPublisherKeys = Map.unmodifiable(trustedPublisherKeys);

  List<InstalledPlugin> get plugins => List.unmodifiable(_plugins);

  Future<void> loadPlugins() async {
    _plugins.clear();
    final root = Directory(pluginPackagesDir);
    if (!await root.exists()) return;

    await for (final entity in root.list()) {
      if (entity is! Directory || _isLifecycleDirectory(entity.path)) continue;
      try {
        final manifest = await _readManifest(entity);
        _verify(manifest);
        _plugins.add(await _installedPluginFor(entity, manifest));
      } catch (error) {
        Logger.error('Failed to load plugin from ${entity.path}', error);
      }
    }
    _plugins.sort(
      (left, right) => left.manifest.name.compareTo(right.manifest.name),
    );
  }

  /// Installs or updates a signed package. The staged package is validated
  /// before it is activated, and every new version begins disabled so changed
  /// components receive an explicit operator review.
  Future<InstalledPlugin> installFromDirectory(String sourcePath) async {
    final source = Directory(sourcePath);
    if (!await source.exists()) {
      throw ArgumentError.value(
        sourcePath,
        'sourcePath',
        'Plugin package directory does not exist.',
      );
    }
    final manifest = await _readTrustedManifest(source);
    _verify(manifest);
    await _verifyDeclaredFiles(source, manifest);

    final root = Directory(pluginPackagesDir);
    if (!await root.exists()) await root.create(recursive: true);
    final target = Directory(p.join(root.path, manifest.id));
    final staging = Directory(
      '${target.path}.staging-${DateTime.now().microsecondsSinceEpoch}',
    );
    final backup = Directory(
      '${target.path}.backup-${DateTime.now().microsecondsSinceEpoch}',
    );
    await _copyDirectory(source, staging);
    try {
      final stagedManifest = await _readTrustedManifest(staging);
      _verify(stagedManifest);
      await _verifyDeclaredFiles(staging, stagedManifest);
      await _writeState(staging, enabled: false, installedAt: DateTime.now());
      if (await target.exists()) await target.rename(backup.path);
      await staging.rename(target.path);
      final installed = await _installedPluginFor(target, stagedManifest);
      await loadPlugins();
      return installed;
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      if (!await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    }
  }

  Future<void> setEnabled(String pluginId, bool enabled) async {
    final directory = _pluginDirectory(pluginId);
    final manifest = await _readManifest(directory);
    _verify(manifest);
    final current = await _readState(directory);
    await _writeState(
      directory,
      enabled: enabled,
      installedAt: current.installedAt,
      enabledAt: enabled ? DateTime.now() : current.enabledAt,
    );
    await loadPlugins();
  }

  /// Restores the most recently retained package directory. No package hooks,
  /// commands, servers, or connectors are launched by lifecycle operations.
  Future<void> rollback(String pluginId) async {
    final root = Directory(pluginPackagesDir);
    final target = _pluginDirectory(pluginId);
    if (!await target.exists()) {
      throw StateError('Plugin $pluginId is not installed.');
    }
    final backups = <Directory>[];
    await for (final entity in root.list()) {
      if (entity is Directory &&
          p.basename(entity.path).startsWith('$pluginId.backup-')) {
        backups.add(entity);
      }
    }
    if (backups.isEmpty) {
      throw StateError(
        'Plugin $pluginId has no version available to roll back to.',
      );
    }
    backups.sort((left, right) => right.path.compareTo(left.path));
    final selected = backups.first;
    final displaced = Directory(
      '${target.path}.backup-${DateTime.now().microsecondsSinceEpoch}',
    );
    await target.rename(displaced.path);
    try {
      await selected.rename(target.path);
    } catch (_) {
      if (!await target.exists() && await displaced.exists()) {
        await displaced.rename(target.path);
      }
      rethrow;
    }
    await loadPlugins();
  }

  Future<void> uninstall(String pluginId) async {
    final directory = _pluginDirectory(pluginId);
    if (await directory.exists()) await directory.delete(recursive: true);
    final root = Directory(pluginPackagesDir);
    if (await root.exists()) {
      await for (final entity in root.list()) {
        if (entity is Directory &&
            p.basename(entity.path).startsWith('$pluginId.backup-')) {
          await entity.delete(recursive: true);
        }
      }
    }
    _plugins.removeWhere((plugin) => plugin.manifest.id == pluginId);
  }

  Future<PluginManifest> _readManifest(Directory packageDir) async {
    final file = File(p.join(packageDir.path, _manifestFileName));
    if (!await file.exists()) {
      throw const FormatException('Plugin package is missing manifest.json.');
    }
    final original = await file.readAsString();
    final decoded = jsonDecode(original);
    final document = VersionedJsonDocument.decode(
      decoded,
      expectedKind: PluginManifest.kind,
      currentSchemaVersion: PluginManifest.schemaVersion,
    );
    if (document.payload is! Map) {
      throw const FormatException('Plugin manifest payload must be an object.');
    }
    if (document.isLegacy &&
        !(document.payload as Map).containsKey('signature')) {
      final legacy = Map<String, dynamic>.from(document.payload as Map);
      final quarantined = <String, dynamic>{
        'id': legacy['id'] ?? 'legacy-plugin',
        'name': legacy['name'] ?? 'Legacy plugin',
        'version': legacy['version'] ?? '0.0.0',
        'description': legacy['description'] ?? '',
        if (legacy['author'] is String) 'author': legacy['author'],
        'components': const <String, dynamic>{},
        'signature': const <String, dynamic>{
          'algorithm': 'untrusted-legacy',
          'signerId': 'legacy',
          'value': 'requires-signed-reinstall',
        },
      };
      await migrateVersionedJsonFile(
        file: file,
        originalContents: original,
        migratedContents: VersionedJsonDocument(
          kind: PluginManifest.kind,
          schemaVersion: PluginManifest.schemaVersion,
          payload: quarantined,
        ).encode(pretty: true),
        previousSchemaVersion: document.schemaVersion,
      );
      throw const PluginSignatureException(
        'Legacy plugin was quarantined. Reinstall a signed package from a trusted publisher.',
      );
    }
    final manifest = PluginManifest.fromJson(
      Map<String, dynamic>.from(document.payload as Map),
    );
    final errors = manifest.validate();
    if (errors.isNotEmpty) throw FormatException(errors.join(' '));
    if (document.isLegacy) {
      await migrateVersionedJsonFile(
        file: file,
        originalContents: original,
        migratedContents: _encodeManifest(manifest),
        previousSchemaVersion: document.schemaVersion,
      );
    }
    return manifest;
  }

  /// Treat malformed signed package metadata as an integrity failure at the
  /// install boundary. Callers never need a raw parser detail to distinguish a
  /// bad package from an untrusted one, and both must fail closed.
  Future<PluginManifest> _readTrustedManifest(Directory packageDir) async {
    try {
      return await _readManifest(packageDir);
    } on PluginSignatureException {
      rethrow;
    } on FormatException {
      throw const PluginSignatureException(
        'Plugin package manifest failed its integrity check.',
      );
    }
  }

  void _verify(PluginManifest manifest) {
    if (!PluginPackageSigner.verifies(
      manifest.toJson(),
      manifest.signature,
      trustedPublisherKeys,
    )) {
      throw PluginSignatureException(
        'Plugin ${manifest.id} is not signed by a trusted publisher.',
      );
    }
  }

  Future<void> _verifyDeclaredFiles(
    Directory packageDir,
    PluginManifest manifest,
  ) async {
    for (final relativePath in manifest.components.allPaths) {
      final file = File(p.join(packageDir.path, relativePath));
      if (!await file.exists()) {
        throw FormatException(
          'Plugin component is missing from the package: $relativePath',
        );
      }
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw FormatException(
          'Plugin component must be a regular file: $relativePath',
        );
      }
    }
  }

  Future<InstalledPlugin> _installedPluginFor(
    Directory directory,
    PluginManifest manifest,
  ) async {
    final state = await _readState(directory);
    return InstalledPlugin(
      manifest: manifest,
      enabled: state.enabled,
      installedAt: state.installedAt,
      enabledAt: state.enabledAt,
    );
  }

  Future<_PluginState> _readState(Directory directory) async {
    final file = File(p.join(directory.path, _stateFileName));
    if (!await file.exists()) {
      return _PluginState(enabled: false, installedAt: DateTime.now());
    }
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return _PluginState(
        enabled: json['enabled'] as bool? ?? false,
        installedAt:
            DateTime.tryParse(json['installedAt'] as String? ?? '') ??
            DateTime.now(),
        enabledAt: DateTime.tryParse(json['enabledAt'] as String? ?? ''),
      );
    } catch (_) {
      return _PluginState(enabled: false, installedAt: DateTime.now());
    }
  }

  Future<void> _writeState(
    Directory directory, {
    required bool enabled,
    required DateTime installedAt,
    DateTime? enabledAt,
  }) {
    final file = File(p.join(directory.path, _stateFileName));
    return writeVersionedJsonAtomically(
      file,
      const JsonEncoder.withIndent('  ').convert({
        'enabled': enabled,
        'installedAt': installedAt.toUtc().toIso8601String(),
        'enabledAt': enabledAt?.toUtc().toIso8601String(),
      }),
    );
  }

  Directory _pluginDirectory(String pluginId) {
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{1,63}$').hasMatch(pluginId)) {
      throw ArgumentError.value(pluginId, 'pluginId', 'Invalid plugin id.');
    }
    return Directory(p.join(pluginPackagesDir, pluginId));
  }
}

class _PluginState {
  final bool enabled;
  final DateTime installedAt;
  final DateTime? enabledAt;

  const _PluginState({
    required this.enabled,
    required this.installedAt,
    this.enabledAt,
  });
}

bool _isSafePackagePath(String value) {
  if (value.trim().isEmpty || p.isAbsolute(value)) return false;
  final normalized = p.normalize(value);
  return normalized == value &&
      normalized != '.' &&
      !normalized.startsWith('../') &&
      !normalized.contains('/../');
}

bool _isLifecycleDirectory(String path) {
  final basename = p.basename(path);
  return basename.contains('.backup-') || basename.contains('.staging-');
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  if (await destination.exists()) await destination.delete(recursive: true);
  await destination.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final target = p.join(destination.path, p.basename(entity.path));
    if (entity is File) {
      await entity.copy(target);
    } else if (entity is Directory) {
      await _copyDirectory(entity, Directory(target));
    } else {
      throw const FormatException(
        'Plugin packages cannot contain symbolic links.',
      );
    }
  }
}

String _encodeManifest(PluginManifest manifest) => VersionedJsonDocument(
  kind: PluginManifest.kind,
  schemaVersion: PluginManifest.schemaVersion,
  payload: manifest.toJson(),
).encode(pretty: true);

String _canonicalPayload(Map<String, dynamic> payload) {
  final withoutSignature = Map<String, dynamic>.from(payload)
    ..remove('signature');
  return jsonEncode(_canonicalize(withoutSignature));
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final sortedKeys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in sortedKeys) key: _canonicalize(value[key])};
  }
  if (value is Iterable) {
    return value.map(_canonicalize).toList(growable: false);
  }
  return value;
}
