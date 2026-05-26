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
import '../context/lsdf_context_loader.dart';
import '../context/memories_loader.dart';
import '../context/rules_loader.dart';
import '../context/smart_rules_matcher.dart';
import 'models_config.dart';

class AgentConfig {
  String? ciscoClientId;
  String? ciscoClientSecret;
  String? ciscoAppKey;
  String? anthropicApiKey;
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
    this.anthropicApiKey,
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
    config.anthropicApiKey = Platform.environment['ANTHROPIC_API_KEY'];
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
      config.anthropicApiKey ??= await _secureStorage.read(
        key: 'anthropic_api_key',
      );
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
        config.anthropicApiKey ??= json['anthropic_api_key'] as String?;
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
      await _writeOrDeleteSecure('anthropic_api_key', anthropicApiKey);
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
      if (anthropicApiKey != null) 'anthropic_api_key': anthropicApiKey,
      if (githubPat != null) 'github_pat': githubPat,
      'model': model,
      'auto_approve': autoApprove,
    };
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  }

  bool get hasCiscoCredentials =>
      ciscoClientId != null && ciscoClientSecret != null && ciscoAppKey != null;

  bool get hasAnthropicCredentials => anthropicApiKey != null;

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

    // Generate and inject compact L-SDF maps so the agent can navigate the
    // workspace without repeatedly opening full source files.
    if (workingDir != null) {
      try {
        final lsdfSection = await LsdfContextLoader.load(workingDir!);
        if (lsdfSection.isNotEmpty) {
          prompts.add(lsdfSection);
        }
      } catch (_) {
        // L-SDF indexing is best-effort and should never block chat startup.
      }
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
You are Circuit Agent, an AI coding assistant running inside Circuit IDE — a desktop application with FULL file system access.

IMPORTANT: You are NOT in a sandboxed or read-only environment. You have real, working tools that directly interact with the user's file system. You MUST use these tools to complete tasks. Never tell the user you cannot create, write, or edit files — you CAN and SHOULD by calling the appropriate tool.

## Your Tools (use them!)

You have the following tools available as function calls. Always use them when the user asks you to perform an action:

- **write_file** — Create or overwrite files. Use this to create new files.
- **edit_file** — Edit existing files by replacing exact text matches.
- **read_file** — Read file contents with line numbers.
- **lsdf_read_index** — Read compact L-SDF indexes for low-token codebase navigation before reading source.
- **list_files** — List files matching a glob pattern.
- **search_files** — Search for regex patterns across files.
- **run_command** — Execute shell commands (e.g., python, npm, git, etc.).
- **git_status** / **git_diff** / **git_log** / **git_commit** / **git_branch** — Full Git operations.
- **web_fetch** — Fetch content from URLs.
- **web_search** — Search the web.

## Guidelines

- When asked to create a file, call `write_file` with the path and content. Do NOT say you cannot do it.
- When asked to edit a file, first `read_file` to see the current content, then `edit_file` to change it.
- When asked to run code, use `run_command` to execute it.
- Be concise and focused in your responses.
- Explain what you're doing and why.
- Write clean, well-structured code following project conventions.
''';
}
