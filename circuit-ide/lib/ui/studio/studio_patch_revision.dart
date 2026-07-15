import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../models/accepted_plan_context.dart';
import '../../models/context_attachment.dart';
import '../../models/reviewed_edit.dart';
import '../../state/patch_proposal_provider.dart';

/// The bounded revision context attached to a follow-up patch request.
class StudioPatchRevisionContext {
  final ProposedPatchSet patch;
  final ContextAttachment attachment;
  final Set<String> filePaths;

  const StudioPatchRevisionContext({
    required this.patch,
    required this.attachment,
    required this.filePaths,
  });
}

Set<String> acceptedPlanFileContextPaths(AcceptedPlanContext? acceptedPlan) {
  if (acceptedPlan == null) return const {};
  final targets = acceptedPlan.plannedTargets.isNotEmpty
      ? acceptedPlan.plannedTargets
      : [
          for (final file in acceptedPlan.plannedFiles)
            PlannedFileTarget.fromDisplayString(file),
        ];
  return {
    for (final target in targets)
      if (target.path.trim().isNotEmpty)
        p.normalize(target.path.trim()).replaceAll('\\', '/'),
  };
}

ContextAttachment debugPatchRevisionContextAttachment(ProposedPatchSet patch) {
  final content = _patchRevisionPromptBlock(patch);
  return ContextAttachment(
    id: 'patch-revision-context-${patch.id}',
    type: ContextAttachmentType.note,
    label: 'Patch revision context',
    content: content,
    resolutionStatus: ContextAttachmentResolutionStatus.resolved,
    estimatedTokens: (content.length / 4).ceil(),
    createdAt: DateTime.now(),
  );
}

String debugPatchRevisionOutboundPrompt(
  String userPrompt,
  ProposedPatchSet patch,
) {
  return patchRevisionOutboundPrompt(
    userPrompt,
    StudioPatchRevisionContext(
      patch: patch,
      attachment: debugPatchRevisionContextAttachment(patch),
      filePaths: _patchRevisionFilePaths(patch),
    ),
  );
}

StudioPatchRevisionContext? activePatchRevisionContext(
  WidgetRef ref,
  String text,
) {
  final patch = ref.read(patchProposalProvider).active;
  if (patch == null ||
      patch.approvalStatus != PatchApprovalStatus.revisionRequested) {
    return null;
  }
  final revisionPrompt = patch.revisionPrompt?.trim();
  if (revisionPrompt == null || revisionPrompt.isEmpty) return null;
  if (!_sameRevisionRequest(text, revisionPrompt)) return null;

  final filePaths = _patchRevisionFilePaths(patch);
  return StudioPatchRevisionContext(
    patch: patch,
    attachment: debugPatchRevisionContextAttachment(patch),
    filePaths: filePaths,
  );
}

String patchRevisionOutboundPrompt(
  String userPrompt,
  StudioPatchRevisionContext context,
) {
  final patch = context.patch;
  return '''
The user is asking Circuit to revise a previously proposed patch:
$userPrompt

Use the attached "Patch revision context" as the source of truth.

Revision contract:
- Refresh the proposal against the current workspace files.
- Preserve the accepted plan or original task intent.
- Produce exactly one concrete `propose_patch` result with app-applyable file contents, or ask exactly one specific missing-context question.
- Do not run commands, write files directly, mutate git, apply patches, or ask the user to type approval text.
- Avoid unplanned files unless the revision request explicitly requires them.

Patch to revise: ${patch.title}
''';
}

bool _sameRevisionRequest(String text, String revisionPrompt) {
  final normalizedText = _normalizeRevisionText(text);
  final normalizedPrompt = _normalizeRevisionText(revisionPrompt);
  if (normalizedText == normalizedPrompt) return true;
  if (normalizedText.contains(normalizedPrompt) ||
      normalizedPrompt.contains(normalizedText)) {
    return normalizedText.length > 24 && normalizedPrompt.length > 24;
  }
  return false;
}

String _normalizeRevisionText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9/._\-\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Set<String> _patchRevisionFilePaths(ProposedPatchSet patch) {
  return {
    for (final edit in patch.edits)
      if (edit.path.trim().isNotEmpty)
        p.normalize(edit.path.trim()).replaceAll('\\', '/'),
    for (final target in patch.effectivePlannedTargets)
      if (target.path.trim().isNotEmpty)
        p.normalize(target.path.trim()).replaceAll('\\', '/'),
  };
}

String _patchRevisionPromptBlock(ProposedPatchSet patch) {
  final edits = patch.edits
      .map(
        (edit) =>
            '- ${edit.path} — ${edit.type.name}${edit.conflictMessage == null ? '' : ' (${edit.conflictMessage})'}',
      )
      .join('\n');
  final targets = patch.effectivePlannedTargets
      .where((target) => target.path.trim().isNotEmpty)
      .map((target) => '- ${target.contractString}')
      .join('\n');
  final suggestions = patch.verificationSuggestions
      .map((suggestion) => '- $suggestion')
      .join('\n');
  return [
    'Patch revision request',
    'Patch id: ${patch.id}',
    'Patch title: ${patch.title}',
    if (patch.comparisonSummary?.trim().isNotEmpty == true)
      'Patch summary: ${patch.comparisonSummary!.trim()}',
    if (patch.conflictMessage?.trim().isNotEmpty == true)
      'Current conflict: ${patch.conflictMessage!.trim()}',
    if (patch.revisionPrompt?.trim().isNotEmpty == true)
      'Revision request: ${patch.revisionPrompt!.trim()}',
    if (edits.trim().isNotEmpty) 'Current proposed files:\n$edits',
    if (targets.trim().isNotEmpty) 'Accepted/planned targets:\n$targets',
    if (suggestions.trim().isNotEmpty)
      'Existing verification suggestions:\n$suggestions',
  ].where((part) => part.trim().isNotEmpty).join('\n\n');
}
