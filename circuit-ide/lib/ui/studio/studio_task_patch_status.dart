import 'package:collection/collection.dart';

import '../../models/reviewed_edit.dart';

String? studioPatchStatusDetail(ProposedPatchSet patch) {
  return switch (patch.applyStatus) {
    PatchApplyStatus.applied =>
      'Applied successfully${patch.checkpointId == null ? '' : ' · checkpoint ${patch.checkpointId}'}.',
    PatchApplyStatus.restored =>
      'Checkpoint restored${patch.changedFiles.isEmpty ? '' : ' · ${studioFormatFileCount(patch.changedFiles.length)} reverted'}.',
    PatchApplyStatus.conflict =>
      '${patch.conflictMessage ?? 'Patch has a conflict and was not applied.'} Ask Circuit to rebase the proposal or revise it before applying again.',
    PatchApplyStatus.failed =>
      patch.conflictMessage ?? 'Patch failed and was not applied.',
    PatchApplyStatus.rejected => 'Rejected.',
    PatchApplyStatus.revisionRequested =>
      'Revision requested. Circuit will use the current files and patch context to prepare an updated proposal.',
    null => null,
  };
}

String? studioPatchHeaderStatusNote(ProposedPatchSet patch) {
  return switch (patch.applyStatus) {
    PatchApplyStatus.conflict =>
      'Needs rebase before apply. Review the current file or ask Circuit to rebase.',
    PatchApplyStatus.revisionRequested =>
      'Revision requested. Circuit will prepare an updated proposal.',
    PatchApplyStatus.restored => 'Checkpoint restored.',
    PatchApplyStatus.failed => 'Apply failed. Review the message below.',
    PatchApplyStatus.rejected => 'Rejected.',
    PatchApplyStatus.applied || null => null,
  };
}

String? studioPatchPrimaryConflictPath(ProposedPatchSet patch) {
  final message = patch.conflictMessage?.trim();
  if (message != null && message.isNotEmpty) {
    final match = RegExp(r':\s*([^\n]+)').firstMatch(message);
    final parsed = match?.group(1)?.trim();
    if (parsed != null && parsed.isNotEmpty) return parsed;
  }
  return patch.edits.firstOrNull?.path;
}

String studioFormatFileCount(int count) =>
    '$count ${count == 1 ? 'file' : 'files'}';
