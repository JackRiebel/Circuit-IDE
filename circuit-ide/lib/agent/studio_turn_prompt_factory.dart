import '../models/accepted_plan_context.dart';
import '../models/agent_config_model.dart';
import '../models/agent_tool_permission.dart';
import '../models/reviewed_edit.dart';
import '../models/turn_intent.dart';
import 'providers/provider_interface.dart';
import 'tools/tool_registry.dart';

/// Pure policy for one Studio turn's model-facing contract and exposed tools.
///
/// Keeping this separate from [StudioTurnRunner] makes the streaming/runtime
/// loop responsible only for transport and tool execution. The app owns every
/// approval and mutation decision; these strings cannot grant capability.
class StudioTurnPromptFactory {
  const StudioTurnPromptFactory._();

  static String systemPromptForTurn({
    required TurnIntent intent,
    required AgentToolMode toolMode,
    required bool hasAcceptedPlan,
    AgentConfigModel? customAgent,
  }) {
    final studioPrompt = _studioSystemPrompt(
      intent: intent,
      toolMode: toolMode,
      hasAcceptedPlan: hasAcceptedPlan,
    );
    if (customAgent == null) return studioPrompt;
    final manifest = customAgent.manifest;
    return [
      studioPrompt,
      'Custom agent contract (internal):',
      'Agent: ${customAgent.name}. Purpose: ${manifest.purpose}.',
      'This agent is limited to declared tools and cannot widen Studio policy, approval scope, workspace access, connector access, or model capabilities.',
      if (manifest.contextPolicy != AgentContextPolicy.projectOnly)
        'Context policy: ${manifest.contextPolicy.name}. Only current-turn attachments are available; repository-reading and command tools are withheld.',
      'Declared output contracts: ${manifest.outputContracts.map((contract) => contract.name).join(', ')}.',
      'Declared limits: at most ${manifest.limits.maxTurns} provider rounds and ${manifest.limits.maxToolCalls} tool calls.',
      if (manifest.instructions.trim().isNotEmpty)
        'Agent instructions:\n${manifest.instructions.trim()}',
    ].join('\n\n');
  }

  static String messageWithAcceptedPlan(
    String userMessage,
    AcceptedPlanContext acceptedPlan,
  ) {
    return [
      userMessage,
      acceptedPlan.toPromptBlock(),
      'Implementation contract:',
      '- Treat the accepted plan as structured context, not as user chat.',
      '- Produce one concrete `propose_patch` call with full file contents/diffs, or ask exactly one specific missing-context question.',
      '- Do not call command, write, edit, git mutation, or `apply_patch_set` tools from this turn.',
      '- Do not ask the user to type "approve"; CircuitCode owns approval and patch application UI.',
    ].join('\n\n');
  }

  static String boundedInspectionQuestion(AcceptedPlanContext? acceptedPlan) {
    if (acceptedPlan != null) {
      final target = _firstAcceptedPlanTarget(acceptedPlan);
      if (target != null) {
        return 'What exact behavior should I implement in $target?';
      }
      return 'What exact behavior belongs inside the planned target file?';
    }
    return 'Which file should I inspect next?';
  }

  static String repeatedToolQuestion(AcceptedPlanContext? acceptedPlan) {
    final target = acceptedPlan == null
        ? null
        : _firstAcceptedPlanTarget(acceptedPlan);
    if (target != null) {
      return 'What exact behavior should I implement in $target after the same tool step repeated without new progress?';
    }
    if (acceptedPlan != null) {
      return 'What exact behavior belongs inside the planned target file after the same tool step repeated without new progress?';
    }
    return 'Which file should I inspect next after the same tool step repeated without new progress?';
  }

  static String outcomeRepairPrompt({
    required TurnIntent intent,
    required AgentToolMode toolMode,
    AcceptedPlanContext? acceptedPlan,
    String? violation,
  }) {
    if (toolMode == AgentToolMode.research) {
      return [
        'CircuitCode rejected the previous research draft because it did not satisfy the cited-evidence contract.',
        'This is the one bounded source-acquisition repair round. Keep any successful direct sources already acquired, then use only `web_search` and `web_fetch` to fill the specific evidence gap below.',
        'Do not inspect the workspace, use connectors, run commands, create files, or make patches. Every network call remains subject to policy and approval.',
        'For a factual answer, acquire an independent publisher source when feasible. If none is available after this repair round, disclose `Single-source limitation:` and mark affected claims as needing corroboration rather than inventing support.',
        'Return the required Conflict review, Evidence table, and dated Sources section after the evidence gap is addressed.',
        if (violation != null && violation.trim().isNotEmpty)
          'Evidence gap to repair: ${violation.trim()}',
      ].join('\n');
    }
    final common = [
      'CircuitCode runtime rejected the previous response because it did not satisfy the active turn contract.',
      'Do not ask the user to type "approve"; CircuitCode owns plan, patch, and approval UI.',
      'Do not claim changes are applied, verified, committed, or run unless the app reports that result.',
      'Do not use shell, write/edit, git mutation, network, or `apply_patch_set` tools.',
    ];

    if (intent == TurnIntent.plan || toolMode == AgentToolMode.plan) {
      return [
        ...common,
        'Repair this Plan turn by doing exactly one of these:',
        '1. Call `propose_patch` once with a reviewable plan: non-empty title, non-empty summary, `plan_markdown`, planned files with path/intent/operation, `assumptions`, and `verification_steps`.',
        '2. Ask exactly one specific missing-context question if a plan cannot be created yet.',
        'Do not answer with prose-only planning.',
      ].join('\n');
    }

    if (acceptedPlan != null) {
      return [
        ...common,
        'Repair this accepted-plan Code turn by doing exactly one of these:',
        '1. Call `propose_patch` once with concrete app-applyable file edits. Each file needs a path, operation, and full content/after text; modify/delete proposals must include the current before text.',
        '2. Ask exactly one specific missing-context question if the accepted plan cannot be implemented yet.',
        'Do not re-plan. Do not summarize work without proposing concrete edits.',
      ].join('\n');
    }

    return [
      ...common,
      'Repair this Code turn by doing exactly one of these:',
      '1. Call `propose_patch` once with concrete app-applyable file edits. Each file needs a path, operation, and full content/after text; modify/delete proposals must include the current before text.',
      '2. Ask exactly one specific missing-context question if the requested change cannot be implemented yet.',
      'Do not summarize work without proposing concrete edits.',
    ].join('\n');
  }

  static AgentToolPhase phaseFor(
    AgentToolMode mode,
    int iteration, {
    required bool hasAcceptedPlan,
  }) {
    return switch (mode) {
      AgentToolMode.chat ||
      AgentToolMode.ask ||
      AgentToolMode.research ||
      AgentToolMode.review ||
      AgentToolMode.handoff => AgentToolPhase.inspect,
      AgentToolMode.plan => AgentToolPhase.propose,
      AgentToolMode.verify => AgentToolPhase.verify,
      AgentToolMode.code || AgentToolMode.fix =>
        hasAcceptedPlan || iteration > 0
            ? AgentToolPhase.propose
            : AgentToolPhase.inspect,
    };
  }

  static int iterationLimit(AgentToolMode mode, int? declaredLimit) {
    final runtimeLimit = mode == AgentToolMode.plan ? 4 : 6;
    if (declaredLimit == null) return runtimeLimit;
    return declaredLimit.clamp(1, runtimeLimit).toInt();
  }

  static List<ToolDefinition> toolsForTurn(
    List<ToolDefinition> modeTools,
    AgentManifest? manifest,
  ) {
    if (manifest == null) return modeTools;
    final declaredTools = modeTools
        .where((tool) => manifest.allowedTools.contains(tool.name))
        .toList(growable: false);
    if (manifest.contextPolicy == AgentContextPolicy.projectOnly) {
      return declaredTools;
    }
    // A selected-file or user-provided-only manifest must not turn an
    // attachment-scoped request into a repository-discovery request. A patch
    // proposal is kept because it is reviewable data, not an executed read or
    // mutation; the shared Studio policy still handles every later approval.
    return declaredTools
        .where((tool) => tool.name == 'propose_patch')
        .toList(growable: false);
  }

  static ToolPermissionPhase permissionPhaseFor(AgentToolPhase phase) {
    return switch (phase) {
      AgentToolPhase.inspect => ToolPermissionPhase.inspect,
      AgentToolPhase.propose => ToolPermissionPhase.propose,
      AgentToolPhase.apply => ToolPermissionPhase.apply,
      AgentToolPhase.verify => ToolPermissionPhase.verify,
    };
  }

  static String _studioSystemPrompt({
    required TurnIntent intent,
    required AgentToolMode toolMode,
    required bool hasAcceptedPlan,
  }) {
    return [
      'You are Circuit Agent inside CircuitCode Studio.',
      'Operate only within the selected Studio workspace and use relative paths when discussing files.',
      'Instructions and project memories are guidance only; the app-side permission policy is authoritative.',
      'Inspect before proposing changes. Never claim that files changed, commands ran, or tests passed unless a tool result proves it.',
      'When a connector tool returns facts, cite its exact `Source: mcp:...` provenance identifier in the final answer. If evidence is missing, label the statement as an assumption instead.',
      'Do not ask the user to type "approve"; CircuitCode renders approval, plan, patch, and apply controls in the UI.',
      'Current intent: ${intent.name}. Current tool profile: ${toolMode.name}.',
      if (hasAcceptedPlan)
        'This turn has an accepted plan. Produce one concrete propose_patch result or ask exactly one specific missing-context question.',
      switch (intent) {
        TurnIntent.chat =>
          'Chat intent contract: answer conversationally. Do not use tools, assume a project, create files, or run commands.',
        TurnIntent.ask =>
          'Ask intent contract: explain or inspect with read/search only. Do not propose/apply patches or run commands.',
        TurnIntent.plan =>
          'Plan intent contract: produce one clear plan or patch proposal. Do not write files, apply patches, or run commands.',
        TurnIntent.code =>
          'Code intent contract: inspect first, then produce a reviewable patch proposal. Do not apply changes or run commands.',
        TurnIntent.review =>
          'Review intent contract: review existing code/diffs and report findings. Do not mutate files or run commands.',
        TurnIntent.verify =>
          'Verify intent contract: suggest or request approved verification commands and summarize results. Do not mutate files.',
      },
    ].join('\n\n');
  }

  static String? _firstAcceptedPlanTarget(AcceptedPlanContext acceptedPlan) {
    final structuredTargets = acceptedPlan.plannedTargets
        .map((target) => target.path.trim())
        .where((path) => path.isNotEmpty);
    if (structuredTargets.isNotEmpty) return structuredTargets.first;
    for (final display in acceptedPlan.plannedFiles) {
      final target = PlannedFileTarget.fromDisplayString(display).path.trim();
      if (target.isNotEmpty) return target;
    }
    return null;
  }
}
