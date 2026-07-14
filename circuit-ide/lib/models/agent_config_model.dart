import 'dart:convert';

import '../agent/config/models_config.dart';
import '../enums/ai_provider.dart';
import 'agent_trigger.dart';
import 'turn_intent.dart';

enum AgentContextPolicy { projectOnly, selectedFiles, userProvidedOnly }

enum AgentOutputContract { summary, plan, patchProposal, evidence }

class AgentExecutionLimits {
  final int maxTurns;
  final int maxToolCalls;
  final Duration maxWallTime;

  const AgentExecutionLimits({
    this.maxTurns = 4,
    this.maxToolCalls = 12,
    this.maxWallTime = const Duration(minutes: 5),
  });

  Map<String, dynamic> toJson() => {
    'maxTurns': maxTurns,
    'maxToolCalls': maxToolCalls,
    'maxWallTimeSeconds': maxWallTime.inSeconds,
  };

  factory AgentExecutionLimits.fromJson(Map<String, dynamic>? json) =>
      AgentExecutionLimits(
        maxTurns: json?['maxTurns'] as int? ?? 4,
        maxToolCalls: json?['maxToolCalls'] as int? ?? 12,
        maxWallTime: Duration(
          seconds: json?['maxWallTimeSeconds'] as int? ?? 300,
        ),
      );
}

class AgentAuthorMetadata {
  final String author;
  final String revision;

  const AgentAuthorMetadata({this.author = 'local', this.revision = '1'});

  Map<String, dynamic> toJson() => {'author': author, 'revision': revision};

  factory AgentAuthorMetadata.fromJson(Map<String, dynamic>? json) =>
      AgentAuthorMetadata(
        author: json?['author'] as String? ?? 'local',
        revision: json?['revision'] as String? ?? '1',
      );
}

/// A declarative, package-local regression fixture. It does not run a second
/// unscoped agent: Studio uses it to gate activation before the agent can be
/// selected, and the Agent Library can run its prompt through the normal turn
/// runtime for an operator-visible behavioral check.
class AgentEvaluationCase {
  final String id;
  final String prompt;
  final TurnIntent intent;
  final Set<AgentOutputContract> requiredOutputContracts;
  final int maxToolCalls;
  final bool requiresCitation;

  const AgentEvaluationCase({
    required this.id,
    required this.prompt,
    required this.intent,
    this.requiredOutputContracts = const {AgentOutputContract.summary},
    this.maxToolCalls = 0,
    this.requiresCitation = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'prompt': prompt,
    'intent': intent.name,
    'requiredOutputContracts': requiredOutputContracts
        .map((contract) => contract.name)
        .toList(),
    'maxToolCalls': maxToolCalls,
    'requiresCitation': requiresCitation,
  };

  factory AgentEvaluationCase.fromJson(Map<String, dynamic> json) {
    return AgentEvaluationCase(
      id: json['id'] as String? ?? 'fixture',
      prompt: json['prompt'] as String? ?? '',
      intent: TurnIntent.values.firstWhere(
        (intent) => intent.name == json['intent'],
        orElse: () => TurnIntent.ask,
      ),
      requiredOutputContracts: AgentOutputContract.values
          .where(
            (contract) => (json['requiredOutputContracts'] as List? ?? [])
                .contains(contract.name),
          )
          .toSet(),
      maxToolCalls: json['maxToolCalls'] as int? ?? 0,
      requiresCitation: json['requiresCitation'] as bool? ?? false,
    );
  }
}

class AgentEvaluationSuite {
  final List<AgentEvaluationCase> cases;
  final double minimumPassRate;

  const AgentEvaluationSuite({this.cases = const [], this.minimumPassRate = 1});

  Map<String, dynamic> toJson() => {
    'cases': cases.map((fixture) => fixture.toJson()).toList(),
    'minimumPassRate': minimumPassRate,
  };

  factory AgentEvaluationSuite.fromJson(Map<String, dynamic>? json) =>
      AgentEvaluationSuite(
        cases: (json?['cases'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map(
              (fixture) => AgentEvaluationCase.fromJson(
                Map<String, dynamic>.from(fixture),
              ),
            )
            .toList(growable: false),
        minimumPassRate: (json?['minimumPassRate'] as num?)?.toDouble() ?? 1,
      );

  AgentEvaluationReport evaluate(AgentConfigModel config) {
    final failures = <String>[];
    if (cases.isEmpty) {
      failures.add(
        'At least one evaluation fixture is required before enablement.',
      );
    }
    if (minimumPassRate <= 0 || minimumPassRate > 1) {
      failures.add(
        'Evaluation minimumPassRate must be greater than 0 and at most 1.',
      );
    }
    var passed = 0;
    for (final fixture in cases) {
      final fixtureErrors = <String>[];
      if (fixture.id.trim().isEmpty || fixture.prompt.trim().isEmpty) {
        fixtureErrors.add('fixture id and prompt are required');
      }
      if (!config.allowedIntents.contains(fixture.intent)) {
        fixtureErrors.add('${fixture.intent.name} is not an allowed intent');
      }
      if (!config.outputContracts.containsAll(
        fixture.requiredOutputContracts,
      )) {
        fixtureErrors.add('required output contract is not declared');
      }
      if (fixture.maxToolCalls < 0 ||
          fixture.maxToolCalls > config.limits.maxToolCalls) {
        fixtureErrors.add('tool-call limit exceeds the declared agent limit');
      }
      if (fixture.requiresCitation &&
          !config.outputContracts.contains(AgentOutputContract.evidence)) {
        fixtureErrors.add(
          'citation fixture requires the evidence output contract',
        );
      }
      if (fixtureErrors.isEmpty) {
        passed++;
      } else {
        failures.add('Fixture ${fixture.id}: ${fixtureErrors.join(', ')}.');
      }
    }
    final passRate = cases.isEmpty ? 0.0 : passed / cases.length;
    if (passRate < minimumPassRate) {
      failures.add(
        'Evaluation pass rate ${(passRate * 100).round()}% is below the required ${(minimumPassRate * 100).round()}%.',
      );
    }
    return AgentEvaluationReport(
      total: cases.length,
      passed: passed,
      minimumPassRate: minimumPassRate,
      failures: failures,
    );
  }
}

class AgentEvaluationReport {
  final int total;
  final int passed;
  final double minimumPassRate;
  final List<String> failures;

  const AgentEvaluationReport({
    required this.total,
    required this.passed,
    required this.minimumPassRate,
    this.failures = const [],
  });

  bool get passedGate => failures.isEmpty;
}

/// Declarative, importable custom-agent contract. It deliberately contains
/// only declared capabilities; an empty set grants no connector or tool access.
class AgentManifest {
  static const currentVersion = 1;
  static const supportedTools = {
    'read_file',
    'list_files',
    'search_files',
    'git_status',
    'git_diff',
    'git_log',
    'propose_patch',
    'run_command',
    'delegate_subagent',
  };

  final int version;
  final String id;
  final String purpose;
  final String instructions;
  final Set<TurnIntent> allowedIntents;
  final Set<String> allowedTools;
  final Set<String> allowedConnectors;
  final AgentContextPolicy contextPolicy;
  final String requiredModel;
  final Set<AgentOutputContract> outputContracts;
  final AgentExecutionLimits limits;
  final AgentAuthorMetadata author;

  const AgentManifest({
    this.version = currentVersion,
    required this.id,
    required this.purpose,
    this.instructions = '',
    this.allowedIntents = const {TurnIntent.ask},
    this.allowedTools = const {},
    this.allowedConnectors = const {},
    this.contextPolicy = AgentContextPolicy.projectOnly,
    this.requiredModel = ModelsConfig.defaultCiscoModel,
    this.outputContracts = const {AgentOutputContract.summary},
    this.limits = const AgentExecutionLimits(),
    this.author = const AgentAuthorMetadata(),
  });

  List<String> validate() {
    final errors = <String>[];
    if (version != currentVersion) {
      errors.add('Unsupported manifest version $version.');
    }
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{1,63}$').hasMatch(id)) {
      errors.add('Agent id must be a lowercase identifier.');
    }
    if (purpose.trim().isEmpty) {
      errors.add('Agent purpose is required.');
    }
    if (allowedIntents.isEmpty) {
      errors.add('At least one allowed intent is required.');
    }
    if (outputContracts.isEmpty) {
      errors.add('At least one output contract is required.');
    }
    if (allowedIntents.contains(TurnIntent.chat) && allowedTools.isNotEmpty) {
      errors.add('Chat-only agents cannot declare tools.');
    }
    if (allowedIntents.contains(TurnIntent.plan) &&
        !outputContracts.contains(AgentOutputContract.plan)) {
      errors.add('Plan agents must declare the plan output contract.');
    }
    if (allowedIntents.contains(TurnIntent.code) &&
        !outputContracts.contains(AgentOutputContract.patchProposal)) {
      errors.add('Code agents must declare the patchProposal output contract.');
    }
    if ((allowedIntents.contains(TurnIntent.plan) ||
            allowedIntents.contains(TurnIntent.code)) &&
        !allowedTools.contains('propose_patch')) {
      errors.add('Plan and Code agents must declare propose_patch.');
    }
    final unknownTools = allowedTools.difference(supportedTools);
    if (unknownTools.isNotEmpty) {
      errors.add(
        'Undeclared or unsupported tools: ${unknownTools.join(', ')}.',
      );
    }
    if (allowedConnectors.isNotEmpty) {
      errors.add('Connectors are not available to custom agents yet.');
    }
    if (limits.maxTurns < 1 || limits.maxTurns > 12) {
      errors.add('maxTurns must be between 1 and 12.');
    }
    if (limits.maxToolCalls < 0 || limits.maxToolCalls > 48) {
      errors.add('maxToolCalls must be between 0 and 48.');
    }
    if (limits.maxWallTime.inSeconds < 10 ||
        limits.maxWallTime.inMinutes > 30) {
      errors.add('maxWallTime must be between 10 seconds and 30 minutes.');
    }
    return errors;
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'id': id,
    'purpose': purpose,
    'instructions': instructions,
    'allowedIntents': allowedIntents.map((value) => value.name).toList(),
    'allowedTools': allowedTools.toList(),
    'allowedConnectors': allowedConnectors.toList(),
    'contextPolicy': contextPolicy.name,
    'requiredModel': requiredModel,
    'outputContracts': outputContracts.map((value) => value.name).toList(),
    'limits': limits.toJson(),
    'author': author.toJson(),
  };

  factory AgentManifest.fromJson(Map<String, dynamic> json) => AgentManifest(
    version: json['version'] as int? ?? currentVersion,
    id: json['id'] as String? ?? '',
    purpose: json['purpose'] as String? ?? '',
    instructions: json['instructions'] as String? ?? '',
    allowedIntents: _intents(json['allowedIntents']),
    allowedTools: _strings(json['allowedTools']),
    allowedConnectors: _strings(json['allowedConnectors']),
    contextPolicy: AgentContextPolicy.values.firstWhere(
      (value) => value.name == json['contextPolicy'],
      orElse: () => AgentContextPolicy.projectOnly,
    ),
    requiredModel: ModelsConfig.coerceModelForProvider(
      AIProviderType.cisco,
      json['requiredModel'] as String?,
    ),
    outputContracts: _contracts(json['outputContracts']),
    limits: AgentExecutionLimits.fromJson(
      json['limits'] as Map<String, dynamic>?,
    ),
    author: AgentAuthorMetadata.fromJson(
      json['author'] as Map<String, dynamic>?,
    ),
  );

  static Set<String> _strings(Object? value) =>
      (value as List<dynamic>? ?? const []).whereType<String>().toSet();
  static Set<TurnIntent> _intents(Object? value) =>
      (value as List<dynamic>? ?? const [])
          .whereType<String>()
          .map(
            (name) => TurnIntent.values
                .where((value) => value.name == name)
                .firstOrNull,
          )
          .whereType<TurnIntent>()
          .toSet();
  static Set<AgentOutputContract> _contracts(Object? value) =>
      (value as List<dynamic>? ?? const [])
          .whereType<String>()
          .map(
            (name) => AgentOutputContract.values
                .where((value) => value.name == name)
                .firstOrNull,
          )
          .whereType<AgentOutputContract>()
          .toSet();
}

class AgentConfigModel {
  final String id;
  final String name;
  final String description;
  final String systemPrompt;
  final Set<String> allowedTools; // empty = no tools
  final String model;
  final bool autoApprove;

  /// Disabled agents remain importable and editable, but cannot be selected
  /// for a Studio request until the operator has reviewed their declared
  /// capabilities in the Agent Library.
  final bool enabled;
  final DateTime? enabledAt;
  final DateTime createdAt;
  final List<AgentTrigger> triggers;
  final Set<TurnIntent> allowedIntents;
  final Set<String> allowedConnectors;
  final AgentContextPolicy contextPolicy;
  final Set<AgentOutputContract> outputContracts;
  final AgentExecutionLimits limits;
  final AgentAuthorMetadata author;
  final AgentEvaluationSuite evaluationSuite;

  const AgentConfigModel({
    required this.id,
    required this.name,
    this.description = '',
    this.systemPrompt = '',
    this.allowedTools = const {},
    this.model = ModelsConfig.defaultCiscoModel,
    this.autoApprove = false,
    this.enabled = true,
    this.enabledAt,
    required this.createdAt,
    this.triggers = const [],
    this.allowedIntents = const {TurnIntent.ask},
    this.allowedConnectors = const {},
    this.contextPolicy = AgentContextPolicy.projectOnly,
    this.outputContracts = const {AgentOutputContract.summary},
    this.limits = const AgentExecutionLimits(),
    this.author = const AgentAuthorMetadata(),
    this.evaluationSuite = const AgentEvaluationSuite(),
  });

  AgentConfigModel copyWith({
    String? id,
    String? name,
    String? description,
    String? systemPrompt,
    Set<String>? allowedTools,
    String? model,
    bool? autoApprove,
    bool? enabled,
    DateTime? enabledAt,
    DateTime? createdAt,
    List<AgentTrigger>? triggers,
    Set<TurnIntent>? allowedIntents,
    Set<String>? allowedConnectors,
    AgentContextPolicy? contextPolicy,
    Set<AgentOutputContract>? outputContracts,
    AgentExecutionLimits? limits,
    AgentAuthorMetadata? author,
    AgentEvaluationSuite? evaluationSuite,
  }) {
    return AgentConfigModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      allowedTools: allowedTools ?? this.allowedTools,
      model: model ?? this.model,
      autoApprove: autoApprove ?? this.autoApprove,
      enabled: enabled ?? this.enabled,
      enabledAt: enabledAt ?? this.enabledAt,
      createdAt: createdAt ?? this.createdAt,
      triggers: triggers ?? this.triggers,
      allowedIntents: allowedIntents ?? this.allowedIntents,
      allowedConnectors: allowedConnectors ?? this.allowedConnectors,
      contextPolicy: contextPolicy ?? this.contextPolicy,
      outputContracts: outputContracts ?? this.outputContracts,
      limits: limits ?? this.limits,
      author: author ?? this.author,
      evaluationSuite: evaluationSuite ?? this.evaluationSuite,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'system_prompt': systemPrompt,
    'allowed_tools': allowedTools.toList(),
    'model': model,
    'auto_approve': autoApprove,
    'enabled': enabled,
    'enabled_at': enabledAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'triggers': triggers.map((t) => t.toJson()).toList(),
    'manifest': manifest.toJson(),
    'evaluation_suite': evaluationSuite.toJson(),
  };

  AgentManifest get manifest => AgentManifest(
    id: id,
    purpose: description.trim().isEmpty ? name : description,
    instructions: systemPrompt,
    allowedTools: allowedTools,
    requiredModel: model,
    allowedIntents: allowedIntents,
    allowedConnectors: allowedConnectors,
    contextPolicy: contextPolicy,
    outputContracts: outputContracts,
    limits: limits,
    author: author,
  );

  List<String> validate() {
    final errors = manifest.validate();
    if (autoApprove) errors.add('Custom agents cannot auto-approve actions.');
    return errors;
  }

  AgentEvaluationReport get evaluationReport => evaluationSuite.evaluate(this);

  factory AgentConfigModel.fromJson(Map<String, dynamic> json) {
    final manifestJson = json['manifest'];
    final manifest = manifestJson is Map<String, dynamic>
        ? AgentManifest.fromJson(manifestJson)
        : null;
    return AgentConfigModel(
      id: manifest?.id.isNotEmpty == true ? manifest!.id : json['id'] as String,
      name: json['name'] as String,
      description:
          manifest?.purpose ??
          json['description'] as String? ??
          json['name'] as String? ??
          '',
      systemPrompt:
          manifest?.instructions ?? json['system_prompt'] as String? ?? '',
      allowedTools:
          manifest?.allowedTools ??
          (json['allowed_tools'] as List<dynamic>?)?.cast<String>().toSet() ??
          {},
      model: ModelsConfig.coerceModelForProvider(
        AIProviderType.cisco,
        manifest?.requiredModel ?? json['model'] as String?,
      ),
      autoApprove: json['auto_approve'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? false,
      enabledAt: DateTime.tryParse(json['enabled_at'] as String? ?? ''),
      createdAt: DateTime.parse(json['created_at'] as String),
      triggers:
          (json['triggers'] as List<dynamic>?)
              ?.map((t) => AgentTrigger.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      allowedIntents: manifest?.allowedIntents ?? const {TurnIntent.ask},
      allowedConnectors: manifest?.allowedConnectors ?? const {},
      contextPolicy: manifest?.contextPolicy ?? AgentContextPolicy.projectOnly,
      outputContracts:
          manifest?.outputContracts ?? const {AgentOutputContract.summary},
      limits: manifest?.limits ?? const AgentExecutionLimits(),
      author: manifest?.author ?? const AgentAuthorMetadata(),
      evaluationSuite: AgentEvaluationSuite.fromJson(
        json['evaluation_suite'] as Map<String, dynamic>?,
      ),
    );
  }

  /// Check if this agent has any enabled triggers of the given type.
  bool hasEnabledTrigger(AgentTriggerType type) {
    return triggers.any((t) => t.type == type && t.enabled);
  }

  AgentRiskAssessment get riskAssessment => AgentRiskAssessment.forConfig(this);

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// Human-readable risk facts surfaced before an operator enables an agent.
/// This is descriptive only: Studio's shared permission policy remains the
/// enforcement point for every tool call.
class AgentRiskAssessment {
  final String level;
  final List<String> reasons;

  const AgentRiskAssessment({required this.level, required this.reasons});

  factory AgentRiskAssessment.forConfig(AgentConfigModel config) {
    final reasons = <String>[];
    if (config.allowedTools.contains('run_command')) {
      reasons.add(
        'Can request shell commands; each command still needs Studio review.',
      );
    }
    if (config.allowedTools.contains('propose_patch')) {
      reasons.add(
        'Can prepare patch proposals; applying a patch still needs review.',
      );
    }
    if (config.contextPolicy == AgentContextPolicy.projectOnly) {
      reasons.add(
        'Can use project-scoped retrieval within the current Studio request.',
      );
    }
    if (config.allowedConnectors.isNotEmpty) {
      reasons.add(
        'Requests connectors, which are currently blocked for custom agents.',
      );
    }
    if (reasons.isEmpty) {
      reasons.add(
        'No command, patch, connector, or project-retrieval capability is requested.',
      );
    }
    final level = config.allowedConnectors.isNotEmpty
        ? 'Blocked'
        : (config.allowedTools.contains('run_command') ||
              config.allowedTools.contains('propose_patch'))
        ? 'High'
        : config.contextPolicy == AgentContextPolicy.projectOnly
        ? 'Medium'
        : 'Low';
    return AgentRiskAssessment(level: level, reasons: reasons);
  }
}
