import '../../models/reviewed_edit.dart';
import '../../models/studio_thread.dart';
import '../../models/turn_intent.dart';
import '../../state/patch_proposal_provider.dart';

bool isConversationalOnlyPrompt(String text) {
  return IntentClassifier.isConversational(text);
}

bool isPlanImplementationContinuationText(String text) {
  final normalized = text
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9\s']"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  const exactPhrases = {
    'do it',
    'implement',
    'implement it',
    'implement this',
    'implement this plan',
    'start implementation',
    'build it',
    'make it',
    'apply it',
    'apply this',
    'apply the plan',
    'apply this plan',
    'yes implement this plan',
    'yes apply this plan',
    'yes apply the plan',
    'can you do that',
    'could you do that',
    'would you do that',
    'please do that',
    'make that happen',
    'can you make that happen',
    'could you make that happen',
    'yes please do that',
    'sounds good do that',
    'that works do that',
    "let's do it",
    'lets do it',
  };
  if (exactPhrases.contains(normalized)) return true;
  if (RegExp(
    r'^(yes|yeah|yep|yup|sure|ok|okay|sounds\s+good|that\s+works|looks\s+good)(\s+please)?\s+(do|apply|implement|continue|proceed|start|begin|ship|make)\s+(it|this|that|the\s+plan|this\s+plan|the\s+changes|those\s+changes|these\s+changes|same\s+thing)(\s+happen)?$',
  ).hasMatch(normalized)) {
    return true;
  }
  if (RegExp(
    r'^(can|could|would|will)\s+you\s+(please\s+)?(do|apply|implement|continue|proceed|start|begin|ship|make)\s+(it|this|that|the\s+plan|this\s+plan|the\s+changes|those\s+changes|these\s+changes|what\s+you\s+suggested|what\s+you\s+recommended)(\s+happen)?(\s+please)?$',
  ).hasMatch(normalized)) {
    return true;
  }
  if (RegExp(
    r'^(please\s+)?(do|make|apply|implement)\s+(it|this|that|the\s+same\s+thing|same\s+thing)(\s+happen)?$',
  ).hasMatch(normalized)) {
    return true;
  }
  if (RegExp(
    r"^(let's|lets)\s+(do|ship|apply|implement)\s+(it|this|that|the\s+plan)?$",
  ).hasMatch(normalized)) {
    return true;
  }
  if (RegExp(
    r'^(please\s+)?(start|begin|do|apply|implement|make)\s+((with|on|from)\s+)?(the\s+changes|those\s+changes|these\s+changes|the\s+edits|those\s+edits|the\s+patch|that\s+patch|the\s+plan|that\s+plan|what\s+you\s+suggested|what\s+you\s+recommended|your\s+suggestion|your\s+recommendation|the\s+same\s+thing|same\s+as\s+above)(\s+(you\s+suggested|you\s+recommended|from\s+above|please|now))?$',
  ).hasMatch(normalized)) {
    return true;
  }
  return RegExp(
    r'^(please\s+)?(do|make|apply|implement)\s+(what\s+you\s+said|what\s+you\s+planned|what\s+you\s+proposed|those\s+suggestions|these\s+suggestions|the\s+suggested\s+changes|your\s+recommended\s+changes)(\s+(please|now))?$',
  ).hasMatch(normalized);
}

bool isPlanApprovalOnlyText(String text) {
  final normalized = text
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9\s']"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  const exactPhrases = {
    'approve',
    'approved',
    'approve it',
    'please approve',
    'please approve it',
    'approve this',
    'approve that',
    'approve the plan',
    'approve this plan',
    'approve as described',
    'please approve as described',
    'accept',
    'accepted',
    'accept it',
    'please accept',
    'please accept it',
    'accept this',
    'accept that',
    'accept the plan',
    'accept this plan',
    'accept as described',
    'please accept as described',
    'yes',
    'y',
    'yeah',
    'yep',
    'yup',
    'sure',
    'ok',
    'okay',
    'sounds good',
    'that works',
    'looks good',
    'looks good to me',
    'go ahead',
    'please proceed',
    'proceed',
    'continue',
    'continue please',
    'next',
    'next step',
    'ship it',
    'yes please',
  };
  return exactPhrases.contains(normalized);
}

ProposedPatchSet? actionablePlanForContinuation(
  PatchProposalState state, {
  StudioThread? thread,
  String? taskId,
}) {
  bool isActionablePlan(ProposedPatchSet patch) {
    final hasPlanBody =
        (patch.planMarkdown ?? '').trim().isNotEmpty ||
        patch.plannedFiles.isNotEmpty;
    if (!(patch.edits.isEmpty &&
        hasPlanBody &&
        patch.approvalStatus == PatchApprovalStatus.proposed &&
        patch.applyStatus == null)) {
      return false;
    }
    if (thread == null && taskId == null) return true;
    if (patch.agentTaskId != null) {
      return patch.agentTaskId == taskId || patch.agentTaskId == thread?.taskId;
    }
    if (patch.runId != null && thread != null) {
      return thread.turns.any((turn) => turn.requestId == patch.runId);
    }
    return false;
  }

  final active = state.active;
  if (active != null && isActionablePlan(active)) return active;
  final matches = state.history.where(isActionablePlan).toList(growable: false)
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return matches.firstOrNull;
}
