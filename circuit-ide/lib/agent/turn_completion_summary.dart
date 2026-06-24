import '../models/provider_lifecycle_event.dart';
import '../models/studio_turn.dart';
import '../models/tool_result_envelope.dart';

class TurnCompletionSummaryBuilder {
  const TurnCompletionSummaryBuilder();

  String build({
    required List<ToolResultEnvelope> toolResults,
    required List<ProviderLifecycleEvent> providerDiagnostics,
    AcceptedPlanState acceptedPlanState = AcceptedPlanState.none,
    String? gitChangeSummary,
  }) {
    final lines = <String>[];
    final patchApply = _latest(toolResults, 'apply_patch_set');
    final patchProposal = _latest(toolResults, 'propose_patch');
    final commands = toolResults
        .where((result) => result.toolName == 'run_command')
        .toList(growable: false);
    final denied = toolResults
        .where((result) => result.status == ToolResultStatus.denied)
        .toList(growable: false);
    final failed = toolResults
        .where(
          (result) =>
              result.status == ToolResultStatus.error &&
              result.toolName != 'run_command' &&
              result.toolName != 'apply_patch_set',
        )
        .toList(growable: false);

    if (patchApply != null) {
      lines.add(_patchApplyLine(patchApply));
      final verification = _verificationSuggestions(patchApply);
      if (verification.isNotEmpty) {
        lines.add('Suggested verification: ${verification.join('; ')}');
      }
    } else if (patchProposal != null) {
      lines.add(_patchProposalLine(patchProposal, acceptedPlanState));
    }

    if (commands.isNotEmpty) {
      lines.add(_commandLine(commands));
    }
    if (denied.isNotEmpty) {
      final names = denied.map((result) => result.toolName).toSet().join(', ');
      lines.add('Approval or policy stopped: $names.');
    }
    if (failed.isNotEmpty) {
      final latest = failed.last;
      lines.add('${_toolLabel(latest.toolName)} failed: ${latest.summary}');
    }

    final providerLine = _providerDiagnosticLine(providerDiagnostics);
    if (providerLine != null) {
      lines.add(providerLine);
    }

    if (gitChangeSummary != null &&
        gitChangeSummary.trim().isNotEmpty &&
        !_isNoFileChangeSummary(gitChangeSummary) &&
        !lines.any((line) => line.toLowerCase().contains('file'))) {
      lines.add(gitChangeSummary.trim());
    }

    if (lines.isEmpty) {
      return gitChangeSummary?.trim().isNotEmpty == true
          ? gitChangeSummary!.trim()
          : 'Ready for the next prompt.';
    }

    return lines.join('\n');
  }

  ToolResultEnvelope? _latest(
    List<ToolResultEnvelope> results,
    String toolName,
  ) {
    for (final result in results.reversed) {
      if (result.toolName == toolName) return result;
    }
    return null;
  }

  String _patchApplyLine(ToolResultEnvelope result) {
    if (result.status != ToolResultStatus.success) {
      return 'Patch apply failed: ${result.summary}';
    }
    final count = result.changedFiles.length;
    final label = count == 1 ? '1 file' : '$count files';
    final checkpoint = result.data['checkpointId'] as String?;
    return [
      'Applied $label.',
      if (checkpoint != null && checkpoint.trim().isNotEmpty)
        'Checkpoint: $checkpoint.',
    ].join(' ');
  }

  String _patchProposalLine(
    ToolResultEnvelope result,
    AcceptedPlanState acceptedPlanState,
  ) {
    if (result.status != ToolResultStatus.success) {
      return 'Patch proposal failed: ${result.summary}';
    }
    final files = result.data['files'];
    final count = files is List ? files.length : result.changedFiles.length;
    final label = count == 1
        ? '1 file'
        : count > 1
        ? '$count files'
        : 'changes';
    final planPrefix = acceptedPlanState == AcceptedPlanState.patchProposed
        ? 'Accepted plan produced'
        : 'Prepared';
    return '$planPrefix a reviewable patch for $label.';
  }

  String _commandLine(List<ToolResultEnvelope> commands) {
    final failed = commands
        .where((result) => result.status != ToolResultStatus.success)
        .toList(growable: false);
    if (failed.isEmpty) {
      final label = commands.length == 1
          ? '1 verification command'
          : '${commands.length} verification commands';
      return '$label completed successfully.';
    }
    final latest = failed.last;
    final exitCode = latest.data['exitCode'];
    final suffix = exitCode is int ? ' (exit $exitCode)' : '';
    return 'Verification failed$suffix: ${latest.summary}';
  }

  List<String> _verificationSuggestions(ToolResultEnvelope result) {
    final raw = result.data['verificationSuggestions'];
    if (raw is! List) return const [];
    return raw
        .whereType<String>()
        .map((value) => value.trim())
        .where(_isRunnableVerificationCommand)
        .take(3)
        .toList(growable: false);
  }

  bool _isRunnableVerificationCommand(String value) {
    final command = value.trim();
    if (command.isEmpty) return false;
    if (command.contains('\n')) return false;
    final first = command.split(RegExp(r'\s+')).first.toLowerCase();
    const knownCommands = {
      'cargo',
      'dart',
      'flutter',
      'go',
      'make',
      'npm',
      'pnpm',
      'python',
      'python3',
      'swift',
      'yarn',
      'xcodebuild',
    };
    return knownCommands.contains(first);
  }

  String? _providerDiagnosticLine(List<ProviderLifecycleEvent> diagnostics) {
    final terminal = diagnostics.reversed.where((event) {
      return event.kind == ProviderLifecycleEventKind.toolOnly ||
          event.kind == ProviderLifecycleEventKind.noTextOrTool ||
          event.kind == ProviderLifecycleEventKind.outcomeRepair;
    }).firstOrNull;
    if (terminal == null) return null;
    return switch (terminal.kind) {
      ProviderLifecycleEventKind.toolOnly =>
        'Provider returned tool calls without assistant text; outcome was built from tool results.',
      ProviderLifecycleEventKind.noTextOrTool =>
        'Provider returned no text or tool calls.',
      ProviderLifecycleEventKind.outcomeRepair =>
        'Runtime repaired an invalid model outcome before completion.',
      _ => null,
    };
  }

  String _toolLabel(String toolName) {
    return toolName
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  bool _isNoFileChangeSummary(String summary) {
    final normalized = summary.trim().toLowerCase();
    return normalized == 'no file changes detected.' ||
        normalized == 'ready for the next prompt.';
  }
}
