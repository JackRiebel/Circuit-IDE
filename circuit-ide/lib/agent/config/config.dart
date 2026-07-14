import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/app_constants.dart';
import '../../core/utils/platform_utils.dart';
import '../../core/utils/logger.dart';
import '../../enums/ai_provider.dart';
import '../../services/versioned_json_document.dart';
import '../context/flow_analyzer.dart';
import '../context/flow_context_builder.dart';
import '../context/memories_loader.dart';
import '../context/rules_loader.dart';
import '../context/smart_rules_matcher.dart';
import 'models_config.dart';

/// Minimal interface around credential storage so configuration migration can
/// be tested without a platform Keychain implementation.
abstract interface class SecureCredentialStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class FlutterSecureCredentialStore implements SecureCredentialStore {
  final FlutterSecureStorage _storage;
  final SecureCredentialStore? _macosStore;

  /// On macOS, use the app-owned Keychain bridge instead of the plugin's
  /// Data Protection Keychain default. The release bundle is intentionally
  /// usable before distribution signing is configured; that default requires
  /// a signing-team entitlement which an ad-hoc build does not have.
  const FlutterSecureCredentialStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
    SecureCredentialStore? macosStore,
  }) : _storage = storage,
       _macosStore = macosStore;

  SecureCredentialStore get _activeMacosStore =>
      _macosStore ?? const MacosKeychainCredentialStore();

  @override
  Future<void> delete({required String key}) {
    if (Platform.isMacOS) return _activeMacosStore.delete(key: key);
    return _storage.delete(key: key);
  }

  @override
  Future<String?> read({required String key}) {
    if (Platform.isMacOS) return _activeMacosStore.read(key: key);
    return _storage.read(key: key);
  }

  @override
  Future<void> write({required String key, required String value}) {
    if (Platform.isMacOS) {
      return _activeMacosStore.write(key: key, value: value);
    }
    return _storage.write(key: key, value: value);
  }
}

/// The narrow native bridge keeps macOS credentials in the user's login
/// Keychain without depending on a distribution-signing entitlement. It is
/// available only inside the application process and has no file fallback.
class MacosKeychainCredentialStore implements SecureCredentialStore {
  static const _channel = MethodChannel('circuitcode/secure_credentials');

  const MacosKeychainCredentialStore();

  @override
  Future<void> delete({required String key}) async {
    await _channel.invokeMethod<void>('delete', {'key': key});
  }

  @override
  Future<String?> read({required String key}) =>
      _channel.invokeMethod<String>('read', {'key': key});

  @override
  Future<void> write({required String key, required String value}) async {
    await _channel.invokeMethod<void>('write', {'key': key, 'value': value});
  }
}

/// Thrown when the operating-system credential store rejects a save.
///
/// Callers must surface this to the user instead of falling back to a
/// plaintext settings file.
class SecureCredentialStorageException implements Exception {
  final String message;

  const SecureCredentialStorageException(this.message);

  @override
  String toString() => message;
}

class AgentConfig {
  String? ciscoClientId;
  String? ciscoClientSecret;
  String? ciscoAppKey;
  String? githubPat;
  String? workingDir;
  String model;
  bool autoApprove;
  bool thinkingMode;
  bool streamResponses;

  static const _settingsSchemaKind = 'circuit.agent-settings';
  static const _settingsSchemaVersion = 2;

  final SecureCredentialStore _credentialStore;
  final String _configDirectory;
  bool _settingsSchemaUnsupported = false;

  AgentConfig({
    this.ciscoClientId,
    this.ciscoClientSecret,
    this.ciscoAppKey,
    this.githubPat,
    this.workingDir,
    this.model = ModelsConfig.defaultCiscoModel,
    this.autoApprove = false,
    this.thinkingMode = false,
    this.streamResponses = true,
    SecureCredentialStore? credentialStore,
    String? configDirectory,
  }) : _credentialStore =
           credentialStore ?? const FlutterSecureCredentialStore(),
       _configDirectory = configDirectory ?? configDir;

  static String get configDir => PlatformUtils.configDir;
  static String get configFile =>
      p.join(configDir, AppConstants.configFileName);

  String get _instanceConfigFile =>
      p.join(_configDirectory, AppConstants.configFileName);

  /// Load credentials from secure storage and non-sensitive settings from
  /// disk. Older plaintext credential files are migrated only after every
  /// value has been written to the operating-system credential store.
  static Future<AgentConfig> load({
    SecureCredentialStore? credentialStore,
    String? configDirectory,
    Map<String, String>? environment,
  }) async {
    final config = AgentConfig(
      credentialStore: credentialStore,
      configDirectory: configDirectory,
    );
    final processEnvironment = environment ?? Platform.environment;

    // Try environment variables first
    config.ciscoClientId = processEnvironment['CIRCUIT_CLIENT_ID'];
    config.ciscoClientSecret = processEnvironment['CIRCUIT_CLIENT_SECRET'];
    config.ciscoAppKey = processEnvironment['CIRCUIT_APP_KEY'];
    config.githubPat =
        processEnvironment['GITHUB_PERSONAL_ACCESS_TOKEN'] ??
        processEnvironment['GITHUB_TOKEN'];

    // Try secure storage
    try {
      config.ciscoClientId ??= await config._credentialStore.read(
        key: _CredentialKey.ciscoClientId,
      );
      config.ciscoClientSecret ??= await config._credentialStore.read(
        key: _CredentialKey.ciscoClientSecret,
      );
      config.ciscoAppKey ??= await config._credentialStore.read(
        key: _CredentialKey.ciscoAppKey,
      );
      config.githubPat ??= await config._credentialStore.read(
        key: _CredentialKey.githubPat,
      );
    } catch (_) {
      Logger.warning('Could not read secure storage.', 'Config');
    }

    // The settings file is intentionally non-sensitive. Its previous format
    // contained credentials, so migrate those fields when secure storage is
    // available and remove them only after a successful secure write.
    try {
      final file = File(config._instanceConfigFile);
      if (await file.exists()) {
        final contents = await file.readAsString();
        final document = VersionedJsonDocument.decode(
          jsonDecode(contents),
          expectedKind: _settingsSchemaKind,
          currentSchemaVersion: _settingsSchemaVersion,
        );
        if (document.payload is! Map) {
          throw const FormatException(
            'Agent settings payload is not an object.',
          );
        }
        final json = Map<String, dynamic>.from(document.payload as Map);
        config.model = ModelsConfig.coerceModelForProvider(
          AIProviderType.cisco,
          json['model'] as String?,
        );
        config.autoApprove = json['auto_approve'] as bool? ?? false;
        final credentialsMigrated = await config._migrateLegacyCredentials(
          json,
        );
        if (document.schemaVersion < _settingsSchemaVersion &&
            credentialsMigrated) {
          await config._migrateSettingsFile(
            originalContents: contents,
            previousSchemaVersion: document.schemaVersion,
          );
        }
      }
    } on UnsupportedRuntimeSchemaVersion catch (error) {
      config._settingsSchemaUnsupported = true;
      Logger.warning(error.toString(), 'Config');
    } catch (_) {
      Logger.warning('Could not read configuration settings.', 'Config');
    }

    return config;
  }

  /// Save credentials exclusively to secure storage.
  ///
  /// Preferences still persist on disk, but a secure-storage failure never
  /// causes a plaintext credential fallback.
  Future<void> save() async {
    if (_settingsSchemaUnsupported) {
      throw const SecureCredentialStorageException(
        'Agent settings use a newer schema. Update CircuitCode before changing credentials or settings.',
      );
    }
    try {
      await _writeOrDeleteSecure(_CredentialKey.ciscoClientId, ciscoClientId);
      await _writeOrDeleteSecure(
        _CredentialKey.ciscoClientSecret,
        ciscoClientSecret,
      );
      await _writeOrDeleteSecure(_CredentialKey.ciscoAppKey, ciscoAppKey);
      await _writeOrDeleteSecure(_CredentialKey.githubPat, githubPat);
    } catch (_) {
      Logger.error('Could not save credentials to secure storage.', null);
      throw const SecureCredentialStorageException(
        'Credentials could not be saved securely. Check Keychain access and try again.',
      );
    }
    try {
      await _saveToFile();
    } catch (_) {
      Logger.error('Could not save non-sensitive settings.', null);
      throw const SecureCredentialStorageException(
        'Credentials were saved securely, but app preferences could not be saved.',
      );
    }
  }

  Future<void> _writeOrDeleteSecure(String key, String? value) async {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      await _credentialStore.delete(key: key);
      return;
    }
    await _credentialStore.write(key: key, value: normalized);
  }

  Future<void> _saveToFile() async {
    final dir = Directory(_configDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(_instanceConfigFile);
    final payload = {'model': model, 'auto_approve': autoApprove};
    await writeVersionedJsonAtomically(
      file,
      VersionedJsonDocument(
        kind: _settingsSchemaKind,
        schemaVersion: _settingsSchemaVersion,
        payload: payload,
      ).encode(pretty: true),
    );
  }

  Future<void> _migrateSettingsFile({
    required String originalContents,
    required int previousSchemaVersion,
  }) {
    return migrateVersionedJsonFile(
      file: File(_instanceConfigFile),
      originalContents: originalContents,
      migratedContents: VersionedJsonDocument(
        kind: _settingsSchemaKind,
        schemaVersion: _settingsSchemaVersion,
        payload: {'model': model, 'auto_approve': autoApprove},
      ).encode(pretty: true),
      previousSchemaVersion: previousSchemaVersion,
    );
  }

  Future<bool> _migrateLegacyCredentials(Map<String, dynamic> json) async {
    final legacy = <String, String?>{
      _CredentialKey.ciscoClientId: json['client_id'] as String?,
      _CredentialKey.ciscoClientSecret: json['client_secret'] as String?,
      _CredentialKey.ciscoAppKey: json['app_key'] as String?,
      _CredentialKey.githubPat: json['github_pat'] as String?,
    };
    if (legacy.values.every((value) => value == null || value.trim().isEmpty)) {
      return true;
    }

    try {
      for (final entry in legacy.entries) {
        final legacyValue = entry.value?.trim() ?? '';
        if (legacyValue.isEmpty) continue;
        final secureValue = await _credentialStore.read(key: entry.key);
        if (secureValue == null || secureValue.trim().isEmpty) {
          await _credentialStore.write(key: entry.key, value: legacyValue);
        }
      }

      ciscoClientId ??= await _credentialStore.read(
        key: _CredentialKey.ciscoClientId,
      );
      ciscoClientSecret ??= await _credentialStore.read(
        key: _CredentialKey.ciscoClientSecret,
      );
      ciscoAppKey ??= await _credentialStore.read(
        key: _CredentialKey.ciscoAppKey,
      );
      githubPat ??= await _credentialStore.read(key: _CredentialKey.githubPat);
      Logger.info(
        'Migrated legacy credential settings to secure storage.',
        'Config',
      );
    } catch (_) {
      // Keep the old file intact if any secret could not be secured. This is
      // the only safe recovery path: never discard a credential before it has
      // been confirmed in Keychain, and never log its value.
      Logger.warning(
        'Legacy plaintext credentials require Keychain access before they can be migrated.',
        'Config',
      );
      return false;
    }
    return true;
  }

  bool get hasCiscoCredentials =>
      ciscoClientId != null && ciscoClientSecret != null && ciscoAppKey != null;

  /// Load CIRCUIT.md system prompt from working dir or global config.
  /// [activeFilePath] is used to filter smart rules by pattern.
  Future<String> loadSystemPrompt({String? activeFilePath}) async {
    final prompts = <String>[];

    // Global CIRCUIT.md
    final globalFile = File(p.join(configDir, 'CIRCUIT.md'));
    if (await globalFile.exists()) {
      prompts.add(await globalFile.readAsString());
    }

    // Project CIRCUIT.md
    if (workingDir != null) {
      final projectFile = File(p.join(workingDir!, 'CIRCUIT.md'));
      if (await projectFile.exists()) {
        prompts.add(await projectFile.readAsString());
      }
    }

    if (prompts.isEmpty) {
      prompts.add(_defaultSystemPrompt);
    }

    // Load project rules from .circuit/rules/ (filtered by active file patterns)
    if (workingDir != null) {
      final rules = await RulesLoader.loadRules(workingDir!);
      final activeRules = activeFilePath != null
          ? SmartRulesMatcher.filterRules(rules, activeFilePath)
          : rules;
      final rulesSection = RulesLoader.formatRulesPrompt(activeRules);
      if (rulesSection.isNotEmpty) {
        prompts.add(rulesSection);
      }
    }

    // Load project + global memories
    if (workingDir != null) {
      final projectMemories = await MemoriesLoader.loadMemories(workingDir!);
      final globalMemories = await MemoriesLoader.loadGlobalMemories();
      final allMemories = [...globalMemories, ...projectMemories];
      final memoriesSection = MemoriesLoader.formatMemoriesPrompt(allMemories);
      if (memoriesSection.isNotEmpty) {
        prompts.add(memoriesSection);
      }
    }

    // Inject flow-aware context (connected file signatures)
    if (activeFilePath != null && workingDir != null) {
      try {
        final analyzer = FlowAnalyzer(rootPath: workingDir!);
        final flowCtx = await analyzer.analyze(activeFilePath);
        final flowSection = FlowContextBuilder.format(flowCtx);
        if (flowSection.isNotEmpty) {
          prompts.add(flowSection);
        }
      } catch (_) {
        // Flow analysis is best-effort — don't block on failure
      }
    }

    return prompts.join('\n\n---\n\n');
  }

  static const _defaultSystemPrompt = '''
You are Circuit Agent, an AI coding assistant running inside CircuitCode.

You operate inside the currently selected workspace directory. Treat that directory as the project root for file reads, searches, commands, and proposed edits. Use relative paths in explanations and tool arguments unless the user explicitly asks for an absolute path.

## Safety and authority

- Instructions, project rules, and memories guide your behavior, but CircuitCode enforces permissions in the client.
- Inspect before editing. Read relevant files, project configuration, and git diff before making coding claims.
- Prefer patch proposals and reviewable diffs over direct exact-text edits.
- When proposing code changes, call `propose_patch` with a clear `plan_markdown` and file list. Do not ask the user to reply with "approve"; CircuitCode will show review controls.
- Writes, shell commands, git mutations, network access, and unknown MCP tools may require approval. If a tool is blocked or awaits approval, explain what is needed.
- Do not access or modify paths outside the active workspace.
- Do not read secret files such as `.env`, credentials, or private keys unless the user explicitly provides safe content in chat.
- Do not claim a task is complete unless you have evidence from file reads, diffs, command output, or tests.

## Working style

- Be concise and focused in your responses.
- State assumptions when context is missing.
- Write clean, well-structured code following project conventions.
- When planning, produce concrete steps tied to files, commands, and verification checks.
''';
}

abstract final class _CredentialKey {
  static const ciscoClientId = 'cisco_client_id';
  static const ciscoClientSecret = 'cisco_client_secret';
  static const ciscoAppKey = 'cisco_app_key';
  static const githubPat = 'github_pat';
}
