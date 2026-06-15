import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/app_constants.dart';
import '../../core/utils/platform_utils.dart';
import '../../core/utils/logger.dart';
import '../../enums/ai_provider.dart';
import '../context/flow_analyzer.dart';
import '../context/flow_context_builder.dart';
import '../context/memories_loader.dart';
import '../context/rules_loader.dart';
import '../context/smart_rules_matcher.dart';
import 'models_config.dart';

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

  static const _secureStorage = FlutterSecureStorage();

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
  });

  static String get configDir => PlatformUtils.configDir;
  static String get configFile =>
      p.join(configDir, AppConstants.configFileName);

  /// Load credentials from secure storage, then fall back to config file
  static Future<AgentConfig> load() async {
    final config = AgentConfig();

    // Try environment variables first
    config.ciscoClientId = Platform.environment['CIRCUIT_CLIENT_ID'];
    config.ciscoClientSecret = Platform.environment['CIRCUIT_CLIENT_SECRET'];
    config.ciscoAppKey = Platform.environment['CIRCUIT_APP_KEY'];
    config.githubPat =
        Platform.environment['GITHUB_PERSONAL_ACCESS_TOKEN'] ??
        Platform.environment['GITHUB_TOKEN'];

    // Try secure storage
    try {
      config.ciscoClientId ??= await _secureStorage.read(
        key: 'cisco_client_id',
      );
      config.ciscoClientSecret ??= await _secureStorage.read(
        key: 'cisco_client_secret',
      );
      config.ciscoAppKey ??= await _secureStorage.read(key: 'cisco_app_key');
      config.githubPat ??= await _secureStorage.read(key: 'github_pat');
    } catch (e) {
      Logger.warning('Could not read secure storage: $e', 'Config');
    }

    // Try config file as fallback
    try {
      final file = File(configFile);
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        config.ciscoClientId ??= json['client_id'] as String?;
        config.ciscoClientSecret ??= json['client_secret'] as String?;
        config.ciscoAppKey ??= json['app_key'] as String?;
        config.githubPat ??= json['github_pat'] as String?;
        config.model = ModelsConfig.coerceModelForProvider(
          AIProviderType.cisco,
          json['model'] as String?,
        );
        config.autoApprove = json['auto_approve'] as bool? ?? false;
      }
    } catch (e) {
      Logger.warning('Could not read config file: $e', 'Config');
    }

    return config;
  }

  /// Save credentials to secure storage
  Future<void> save() async {
    try {
      await _writeOrDeleteSecure('cisco_client_id', ciscoClientId);
      await _writeOrDeleteSecure('cisco_client_secret', ciscoClientSecret);
      await _writeOrDeleteSecure('cisco_app_key', ciscoAppKey);
      await _writeOrDeleteSecure('github_pat', githubPat);
      await _saveToFile();
    } catch (e) {
      Logger.error('Could not save to secure storage', e);
      // Fall back to config file
      await _saveToFile();
    }
  }

  Future<void> _writeOrDeleteSecure(String key, String? value) async {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      await _secureStorage.delete(key: key);
      return;
    }
    await _secureStorage.write(key: key, value: normalized);
  }

  Future<void> _saveToFile() async {
    final dir = Directory(configDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(configFile);
    final json = {
      if (ciscoClientId != null) 'client_id': ciscoClientId,
      if (ciscoClientSecret != null) 'client_secret': ciscoClientSecret,
      if (ciscoAppKey != null) 'app_key': ciscoAppKey,
      if (githubPat != null) 'github_pat': githubPat,
      'model': model,
      'auto_approve': autoApprove,
    };
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
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
