import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../agent/tools/tool_registry.dart';
import '../../models/agent_config_model.dart';
import '../../models/context_attachment.dart';
import '../../models/generated_artifact.dart';
import '../../models/specialist_agent.dart';
import '../../models/studio_shell.dart';
import '../../models/studio_thread.dart';
import '../../models/turn_intent.dart';
import '../../services/artifact_type_registry.dart';
import '../../state/file_tree_provider.dart';
import 'studio_context_payload.dart';

bool studioIntentRequiresWorkspace(TurnIntent intent) {
  return switch (intent) {
    TurnIntent.chat => false,
    TurnIntent.ask => false,
    TurnIntent.plan => true,
    TurnIntent.code => true,
    TurnIntent.review => true,
    TurnIntent.verify => true,
  };
}

String studioOutboundPromptForIntent({
  required String text,
  required TurnIntent intent,
  required bool planModeEnabled,
  StudioPromptMode? promptMode,
}) {
  if (intent == TurnIntent.chat) return _conversationalPrompt(text);
  if (promptMode == StudioPromptMode.research) {
    return _citedResearchPrompt(text);
  }
  if (IntentClassifier.requestsBuildDiscovery(text)) {
    return _buildDiscoveryPrompt(text);
  }
  if (intent == TurnIntent.ask &&
      IntentClassifier.requestsStructuredAdvisoryOutput(text)) {
    return _structuredAdvisoryPrompt(text);
  }
  if (planModeEnabled || intent == TurnIntent.plan) {
    return _planModePrompt(text);
  }
  if (intent == TurnIntent.code &&
      IntentClassifier.requestsVerification(text)) {
    return _codeWithDeferredVerificationPrompt(text);
  }
  return text;
}

String studioOutboundPromptWithArtifactContract({
  required String text,
  required TurnIntent intent,
  required bool planModeEnabled,
  StudioPromptMode? promptMode,
}) {
  final prompt = studioOutboundPromptForIntent(
    text: text,
    intent: intent,
    planModeEnabled: planModeEnabled,
    promptMode: promptMode,
  );
  if (!isGeneratedArtifactRequest(text) ||
      intent == TurnIntent.chat ||
      intent == TurnIntent.review ||
      intent == TurnIntent.verify) {
    return prompt;
  }
  final artifactLabel = const ArtifactTypeRegistry()
      .routeForPrompt(text)
      .contractLabel;
  return '''
$prompt

Artifact output contract:
- The user asked for a generated $artifactLabel artifact.
- Produce concise assistant text plus clean machine-readable content when needed.
- For spreadsheet/Excel/CSV outputs, include one complete Markdown table with all required rows and columns; Circuit will save it as a workspace artifact instead of making chat the final output surface. Excel requests become real .xlsx files when table data is available.
- For solution sizing workbook outputs, include requirements, recommendations, validation checks, assumptions, and any source tables; Circuit will organize those into multi-sheet .xlsx workbooks.
- For product comparison matrix outputs, include candidate products/models, capabilities, constraints, lifecycle risk, fit score, recommendation, assumptions, and source tables; Circuit will organize those into multi-sheet .xlsx workbooks.
- For Lifecycle/EoX outputs, include product/PID, lifecycle status, end-of-sale date, last-date-of-support, risk, migration/replacement hints, assumptions, and official-source notes; Circuit will organize those into multi-sheet .xlsx workbooks and treat replacement PIDs as migration clues only.
- For PowerPoint/deck outputs, use clear Markdown headings and concise bullets; Circuit will save that structure as a .pptx deck.
- For Word/DOCX/report outputs, use clear Markdown headings, bullets, assumptions, sources, and any useful tables; Circuit will save that structure as a .docx report.
- For business use case brief outputs, include executive summary, company/industry context, pain points, priority use cases, recommended solutions, value/impact, next steps, assumptions, and cited sources; Circuit will save it as a .docx report unless another artifact format is explicitly requested.
- For evidence pack outputs, include an evidence summary, claim register, source inventory, checked dates, assumptions/unknowns, confidence/risk, unsupported claims, and follow-up validation items; Circuit will save it as a .docx evidence pack unless JSON is explicitly requested.
- For PDF/report outputs, use clear Markdown headings, concise paragraphs, bullets, assumptions, sources, and any useful tables; Circuit will save it as a .pdf handoff report.
- For topology/network diagram outputs, include one valid Mermaid diagram fenced as ```mermaid plus a short assumptions section; Circuit will save it as an .svg diagram artifact.
- For chart/graph outputs, include at least one complete Markdown table where the first column is the label and one later column is numeric; Circuit will save it as an .svg chart artifact.
- Do not say you cannot create files unless the requested data is missing. If data is missing, ask one specific missing-data question.
- Keep the human-facing explanation short because Circuit will render a file artifact card after the turn.
''';
}

AgentToolMode studioToolModeForIntent({
  required TurnIntent intent,
  required StudioPromptMode promptMode,
  required bool hasWorkspace,
  required bool planModeEnabled,
}) {
  if (intent == TurnIntent.chat) return AgentToolMode.chat;
  if (promptMode == StudioPromptMode.research) {
    return AgentToolMode.research;
  }
  if (planModeEnabled) return AgentToolMode.plan;
  if (!hasWorkspace && !studioIntentRequiresWorkspace(intent)) {
    return AgentToolMode.chat;
  }
  if (intent == TurnIntent.ask) return AgentToolMode.ask;
  if (intent == TurnIntent.plan) return AgentToolMode.plan;
  if (intent == TurnIntent.review) return AgentToolMode.review;
  if (intent == TurnIntent.verify) return AgentToolMode.verify;
  return switch (promptMode) {
    StudioPromptMode.ask => AgentToolMode.ask,
    StudioPromptMode.research => AgentToolMode.research,
    StudioPromptMode.code => AgentToolMode.code,
    StudioPromptMode.fix => AgentToolMode.fix,
    StudioPromptMode.review => AgentToolMode.review,
  };
}

StudioContextPayload buildConversationalContextPayload(
  WidgetRef ref, {
  List<ContextAttachment> extraAttachments = const [],
}) {
  final rootPath = ref.read(fileTreeProvider).rootPath;
  const selection = SpecialistAgentSelection(
    requestedAgentId: SpecialistAgentId.auto,
    resolvedAgentIds: [],
    isAuto: true,
    rationale: 'Specialist routing is disabled for conversational turns.',
  );
  return StudioContextPayload(
    attachments: List.unmodifiable(extraAttachments),
    summary: StudioContextSummary(
      rootPath: rootPath,
      projectLabel: rootPath == null
          ? 'No project selected'
          : p.basename(rootPath),
      includedItemCount: extraAttachments.length,
      estimatedTokens: extraAttachments.fold<int>(
        0,
        (sum, attachment) => sum + attachment.estimatedTokens,
      ),
      selectedFiles: const [],
      includesGit: false,
      includesTerminal: false,
      warnings: [
        'conversational turn: no project context attached',
        if (extraAttachments.isNotEmpty)
          'explicit user-provided browser context attached',
      ],
    ),
    specialistSelection: selection,
  );
}

StudioContextPayload buildCustomAgentContextPayload({
  required String? rootPath,
  required List<ContextAttachment> attachments,
  required AgentContextPolicy contextPolicy,
}) {
  assert(contextPolicy != AgentContextPolicy.projectOnly);
  const selection = SpecialistAgentSelection(
    requestedAgentId: SpecialistAgentId.auto,
    resolvedAgentIds: [],
    isAuto: true,
    rationale: 'Specialist routing is disabled for a scoped custom-agent turn.',
  );
  final policyLabel = switch (contextPolicy) {
    AgentContextPolicy.selectedFiles => 'selected files',
    AgentContextPolicy.userProvidedOnly => 'user-provided attachments',
    AgentContextPolicy.projectOnly => 'project context',
  };
  final selectedFiles = attachments
      .map((attachment) => attachment.path ?? attachment.label)
      .where((value) => value.trim().isNotEmpty)
      .toSet()
      .toList(growable: false);
  return StudioContextPayload(
    attachments: List.unmodifiable(attachments),
    summary: StudioContextSummary(
      rootPath: rootPath,
      projectLabel: rootPath == null
          ? 'No project selected'
          : p.basename(rootPath),
      includedItemCount: attachments.length,
      estimatedTokens: attachments.fold<int>(
        0,
        (sum, attachment) => sum + attachment.estimatedTokens,
      ),
      selectedFiles: selectedFiles,
      includesGit: attachments.any(
        (attachment) => attachment.type == ContextAttachmentType.gitDiff,
      ),
      includesTerminal: attachments.any(
        (attachment) => attachment.type == ContextAttachmentType.terminal,
      ),
      warnings: [
        'custom agent context policy: $policyLabel',
        'automatic project retrieval and prior-thread context are excluded',
      ],
    ),
    specialistSelection: selection,
  );
}

String _buildDiscoveryPrompt(String userPrompt) =>
    '''
The user described a broad product/build idea:
$userPrompt

Treat this as a product-discovery turn, not an implementation turn.
Do not create files, do not propose patches, do not inspect the workspace unless the user explicitly asks, do not run commands, and do not infer a framework or file structure.
If the user mentioned a technology or framework, treat it as a preference to validate during discovery, not permission to start coding.

Respond like a Codex-style coding partner before implementation:
- Briefly restate the likely goal in plain language.
- Identify the key decisions needed before code exists: users, inputs, outputs, workflow, data model, integrations, validation rules, and success criteria.
- Ask 3-6 concise questions that would materially change the first implementation.
- Suggest a safe next step, such as turning the answers into a plan.

Do not say that anything was built or saved.
''';

String _conversationalPrompt(String userPrompt) =>
    '''
The user sent a greeting or small-talk message:
$userPrompt

Respond briefly and conversationally. Do not inspect the project, do not mention current files or previous implementation details, do not run tools, do not propose changes, and do not infer that the user wants code written.
''';

String _citedResearchPrompt(String userPrompt) =>
    '''
Research Mode is enabled.

Research question:
$userPrompt

Use only the supplied `web_search` and `web_fetch` tools. Every network call
is subject to CircuitCode's project policy and user approval; do not try to
work around a denial, use connectors, inspect the workspace, run commands, or
claim that a source was fetched when it was not.

Workflow:
1. Make a brief research plan: identify the material sub-questions and what
   evidence would answer each one. Do not present the plan as a final answer.
2. Search broadly, then fetch the direct sources that support material claims.
   For a factual answer, acquire two independent publisher sources whenever
   possible; multiple pages from one publisher are not corroboration. If one
   direct source is genuinely the only appropriate record, write a visible
   `Single-source limitation:` statement and mark the affected claim as needing
   corroboration rather than padding the source list.
3. Prefer primary/official sources. Compare the direct source statements for
   material conflicts and stale information; do not treat search snippets as
   evidence.
4. Perform a gap review before synthesis. Separate facts, inferences, and
   unsupported claims. If evidence is absent, say so plainly instead of filling
   the gap from model knowledge.
5. Put a direct URL citation immediately after each material factual claim.
6. Include a `## Conflict review` section before Sources. Write `No material
   conflicts identified` only after comparing the direct statements. Otherwise
   add a `Conflict:` bullet naming the disagreement, citing at least two direct
   URLs, and state whether it is unresolved or why one record is preferred.
7. Include a `## Evidence table` with `Claim`, `Sources`, and `Evidence status`
   columns. Mark unsupported or freshness-sensitive statements explicitly.
8. End with a `## Sources` section. Each bullet must include the exact direct
   URL and `Checked: YYYY-MM-DD` date copied from a fetched source result.

Return a concise evidence-backed answer, followed by explicit open
questions/limitations when the available sources cannot support a claim.
Circuit persists a reviewable evidence artifact from completed fetched sources,
so keep chat focused on the answer rather than reproducing long source text.
Do not create files or patches in this mode.
''';

String _structuredAdvisoryPrompt(String userPrompt) =>
    '''
The user asked for an advisory or visual output:
$userPrompt

Produce the answer directly in chat. Do not create files, do not propose patches, do not ask the user to type "approve", do not run shell commands, and do not claim that anything was saved.

Output contract:
- Start with the direct answer, not a plan to answer later.
- For topology, architecture, or network diagram requests, include a valid Mermaid diagram fenced as ```mermaid and label assumptions.
- For sizing, lifecycle, replacement, or architecture validation requests, include a compact comparison/requirements table and explicit assumptions.
- For business-case or company-use-case requests, include a concise use-case table, chart-ready metrics or categories when useful, and cite only sources actually available in the provided context. If live research is needed but not available in this turn, say what needs to be researched instead of inventing citations.
- End with missing inputs or follow-up questions only when they would materially change the answer.
''';

String _planModePrompt(String userPrompt) =>
    '''
Plan Mode is enabled for this turn.

User request:
$userPrompt

Create a reviewable implementation plan before making changes. Inspect the project as needed, then call the `propose_patch` tool with:
- `title`
- `summary`
- `plan_markdown`
- `assumptions`
- `verification_steps`
- `files` containing planned workspace-relative paths, intents, and `operation` (`create`, `modify`, or `delete`)

Do not ask the user to type "approve". Do not call write, edit, command, or git mutation tools in this planning turn. CircuitCode will render the plan with Implement / Revise / Dismiss controls.
''';

String _codeWithDeferredVerificationPrompt(String userPrompt) =>
    '''
The user requested an implementation and verification:
$userPrompt

This is a Code turn. Code turns may inspect files and produce a concrete `propose_patch` result only.
- Do not run shell commands, tests, builds, git mutation, write/edit tools, or `apply_patch_set` from this turn.
- First produce app-applyable file edits with `propose_patch`, or ask exactly one specific missing-context question.
- Preserve the user's verification request in the patch summary / verification suggestions.
- After the patch is reviewed and applied, CircuitCode will handle verification in a separate Verify turn with command approval.
''';
