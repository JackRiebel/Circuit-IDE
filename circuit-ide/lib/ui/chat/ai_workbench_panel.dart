import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../core/utils/platform_utils.dart';
import '../../enums/connection_status.dart';
import '../../enums/tool_status.dart';
import '../../models/editor_state.dart';
import '../../models/agent_run.dart';
import '../../models/run_diagnostics_summary.dart';
import '../../models/tool_call_info.dart';
import '../../models/workspace_context.dart';
import '../../state/agent_run_provider.dart';
import '../../state/ai_context_provider.dart';
import '../../state/chat_provider.dart';
import '../../state/connection_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/terminal_provider.dart';
import '../../state/theme_provider.dart';
import '../../state/workspace_context_provider.dart';
import '../../theme/theme_tokens.dart';

enum WorkbenchTab { context, activity }

enum RunConsoleFilter { active, recent, failed }

class AiWorkbenchTabNotifier extends Notifier<WorkbenchTab> {
  @override
  WorkbenchTab build() => WorkbenchTab.context;

  void set(WorkbenchTab tab) => state = tab;
}

final aiWorkbenchTabProvider =
    NotifierProvider<AiWorkbenchTabNotifier, WorkbenchTab>(
      AiWorkbenchTabNotifier.new,
    );

final runConsoleFilterProvider =
    NotifierProvider<RunConsoleFilterNotifier, RunConsoleFilter>(
      RunConsoleFilterNotifier.new,
    );

class RunConsoleFilterNotifier extends Notifier<RunConsoleFilter> {
  @override
  RunConsoleFilter build() => RunConsoleFilter.active;

  void set(RunConsoleFilter filter) => state = filter;
}

class AiWorkbenchPanel extends ConsumerWidget {
  const AiWorkbenchPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final tab = ref.watch(aiWorkbenchTabProvider);

    return Container(
      decoration: BoxDecoration(
        color: tokens.bgMain,
        border: Border(
          bottom: BorderSide(color: tokens.border.withValues(alpha: 0.55)),
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: Row(
              children: [
                Icon(
                  Icons.dashboard_customize_outlined,
                  size: 14,
                  color: tokens.accent,
                ),
                const SizedBox(width: Spacing.sm),
                Text(
                  'AI WORKBENCH',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                  ),
                ),
                const Spacer(),
                _SegmentButton(
                  label: 'Context',
                  selected: tab == WorkbenchTab.context,
                  onTap: () => ref
                      .read(aiWorkbenchTabProvider.notifier)
                      .set(WorkbenchTab.context),
                ),
                const SizedBox(width: Spacing.sm),
                _SegmentButton(
                  label: 'Activity',
                  selected: tab == WorkbenchTab.activity,
                  onTap: () => ref
                      .read(aiWorkbenchTabProvider.notifier)
                      .set(WorkbenchTab.activity),
                ),
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: AnimationDurations.smooth,
            child: tab == WorkbenchTab.context
                ? const _ContextWorkbench(key: ValueKey('context'))
                : const _ActivityWorkbench(key: ValueKey('activity')),
          ),
        ],
      ),
    );
  }
}

class _ContextWorkbench extends ConsumerWidget {
  const _ContextWorkbench({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final rootPath = ref.watch(fileTreeProvider).rootPath;
    final activeTab = ref.watch(editorProvider).activeTab;
    final terminalState = ref.watch(terminalProvider);
    final settings = ref.watch(settingsProvider);
    final connectionStatus = ref.watch(connectionStatusProvider);
    final contextState = ref.watch(aiContextProvider);
    final workspaceState = ref.watch(workspaceContextProvider);
    final activeFile = _activeFile(activeTab);
    final terminalOutput = ref
        .read(terminalProvider.notifier)
        .getActiveTerminalOutput(lines: 60)
        .trim();
    final terminalLines = terminalOutput.isEmpty
        ? 0
        : terminalOutput
              .split('\n')
              .where((line) => line.trim().isNotEmpty)
              .length;
    final lineCount = activeFile == null
        ? 0
        : activeFile.content.isEmpty
        ? 1
        : activeFile.content.split('\n').length;

    return Container(
      key: key,
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.sm,
        Spacing.lg,
        Spacing.lg,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _ContextTile(
                  icon: Icons.folder_open_outlined,
                  title: rootPath == null
                      ? 'Scratch workspace'
                      : p.basename(rootPath),
                  subtitle: rootPath ?? PlatformUtils.scratchDir,
                  statusColor: rootPath == null
                      ? tokens.textMuted
                      : tokens.success,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: _ContextTile(
                  icon: _lsdfIcon(contextState.lsdfStatus),
                  title: _lsdfTitle(contextState),
                  subtitle: _lsdfSubtitle(contextState),
                  statusColor: _lsdfColor(contextState.lsdfStatus, tokens),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: _ContextTile(
                  icon: Icons.description_outlined,
                  title: activeFile?.fileName ?? 'No active file',
                  subtitle: activeFile == null
                      ? 'Open a file for editor actions'
                      : '${activeFile.language} · $lineCount lines',
                  statusColor: activeFile == null
                      ? tokens.textMuted
                      : tokens.info,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: _ContextTile(
                  icon: Icons.terminal,
                  title: terminalLines == 0
                      ? 'Terminal ready'
                      : '$terminalLines recent lines',
                  subtitle:
                      'Tab ${terminalState.activeTerminalIndex + 1} · recent output buffer',
                  statusColor: terminalLines == 0
                      ? tokens.textMuted
                      : tokens.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          if (workspaceState.isBusy || workspaceState.error != null) ...[
            _WorkspaceProgressRow(state: workspaceState),
            const SizedBox(height: Spacing.md),
          ],
          Row(
            children: [
              _ContextPill(
                icon: _connectionIcon(connectionStatus),
                label:
                    '${settings.activeProvider.shortName} ${_connectionLabel(connectionStatus)}',
                color: _connectionColor(connectionStatus, tokens),
              ),
              const SizedBox(width: Spacing.sm),
              _ContextPill(
                icon: Icons.hub_outlined,
                label: workspaceState.message ?? _lsdfPillLabel(contextState),
                color: _lsdfColor(contextState.lsdfStatus, tokens),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static EditorTab? _activeFile(EditorTab? tab) {
    if (tab == null || tab.filePath.startsWith('circuit://')) return null;
    return tab;
  }

  static IconData _connectionIcon(ConnectionStatus status) {
    return switch (status) {
      ConnectionStatus.connected => Icons.check_circle_outline,
      ConnectionStatus.connecting => Icons.sync,
      ConnectionStatus.error => Icons.error_outline,
      ConnectionStatus.disconnected => Icons.radio_button_unchecked,
    };
  }

  static String _connectionLabel(ConnectionStatus status) {
    return switch (status) {
      ConnectionStatus.connected => 'connected',
      ConnectionStatus.connecting => 'connecting',
      ConnectionStatus.error => 'error',
      ConnectionStatus.disconnected => 'offline',
    };
  }

  static Color _connectionColor(ConnectionStatus status, ThemeTokens tokens) {
    return switch (status) {
      ConnectionStatus.connected => tokens.success,
      ConnectionStatus.connecting => tokens.warning,
      ConnectionStatus.error => tokens.error,
      ConnectionStatus.disconnected => tokens.textMuted,
    };
  }

  static IconData _lsdfIcon(LsdfIndexStatus status) {
    return switch (status) {
      LsdfIndexStatus.idle => Icons.hub_outlined,
      LsdfIndexStatus.checking => Icons.sync,
      LsdfIndexStatus.building => Icons.sync,
      LsdfIndexStatus.ready => Icons.check_circle_outline,
      LsdfIndexStatus.error => Icons.error_outline,
    };
  }

  static Color _lsdfColor(LsdfIndexStatus status, ThemeTokens tokens) {
    return switch (status) {
      LsdfIndexStatus.idle => tokens.textMuted,
      LsdfIndexStatus.checking => tokens.warning,
      LsdfIndexStatus.building => tokens.warning,
      LsdfIndexStatus.ready => tokens.success,
      LsdfIndexStatus.error => tokens.error,
    };
  }

  static String _lsdfTitle(AiContextState state) {
    return switch (state.lsdfStatus) {
      LsdfIndexStatus.idle => 'L-SDF ready',
      LsdfIndexStatus.checking => 'Checking map',
      LsdfIndexStatus.building => 'Building map',
      LsdfIndexStatus.ready => 'L-SDF map ready',
      LsdfIndexStatus.error => 'Map needs attention',
    };
  }

  static String _lsdfSubtitle(AiContextState state) {
    return switch (state.lsdfStatus) {
      LsdfIndexStatus.idle => 'Open a project to build the index',
      LsdfIndexStatus.checking => 'Looking for project.lsdf and INDEX.lsdf',
      LsdfIndexStatus.building =>
        '${state.lsdfMessage ?? "Creating directory maps"} · ${state.lsdfFilesIndexed} files',
      LsdfIndexStatus.ready =>
        state.lsdfFilesIndexed > 0
            ? '${state.lsdfFilesIndexed} files indexed'
            : 'Code index + targeted files',
      LsdfIndexStatus.error => state.lsdfError ?? 'Could not build index',
    };
  }

  static String _lsdfPillLabel(AiContextState state) {
    return switch (state.lsdfStatus) {
      LsdfIndexStatus.idle => 'L-SDF auto-map idle',
      LsdfIndexStatus.checking => 'Checking L-SDF map',
      LsdfIndexStatus.building =>
        'Building L-SDF map · ${state.lsdfFilesIndexed} files',
      LsdfIndexStatus.ready => 'L-SDF map active',
      LsdfIndexStatus.error => 'L-SDF map failed',
    };
  }
}

class _ActivityWorkbench extends ConsumerWidget {
  const _ActivityWorkbench({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final chatState = ref.watch(chatProvider);
    final runs = ref.watch(agentRunProvider);
    final toolCalls = chatState.messages
        .expand((message) => message.toolCalls)
        .toList()
        .reversed
        .take(5)
        .toList();
    final request = chatState.pendingConfirmation;

    return Container(
      key: key,
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.sm,
        Spacing.lg,
        Spacing.lg,
      ),
      child: Column(
        children: [
          if (request != null) ...[
            _ApprovalCard(requestId: request.id, preview: request.preview),
            const SizedBox(height: Spacing.sm),
          ],
          Row(
            children: [
              _UsageTile(
                icon: Icons.data_usage_outlined,
                label: 'Last Request',
                value: chatState.lastTokenUsage.isNotEmpty
                    ? chatState.lastTokenUsage.formattedInputOutput
                    : chatState.tokenUsage.formattedWithBreakdown,
              ),
              const SizedBox(width: Spacing.sm),
              _UsageTile(
                icon: Icons.payments_outlined,
                label: 'Cost',
                value: chatState.costInfo.formatted,
              ),
              const SizedBox(width: Spacing.sm),
              _UsageTile(
                icon: Icons.forum_outlined,
                label: 'Turns',
                value: '${chatState.messages.length}',
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          if (toolCalls.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Spacing.lg),
              decoration: BoxDecoration(
                color: tokens.bgLight.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(
                  color: tokens.border.withValues(alpha: 0.45),
                ),
              ),
              child: Text(
                'Tool activity will appear here when the AI reads files, edits code, or runs commands.',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                  height: 1.45,
                ),
              ),
            )
          else
            Column(
              children: toolCalls
                  .map(
                    (tool) => Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.sm),
                      child: _ToolActivityRow(tool: tool),
                    ),
                  )
                  .toList(),
            ),
          if (runs.activeRuns.isNotEmpty || runs.recentRuns.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            _RunTimeline(runs: runs),
          ],
        ],
      ),
    );
  }
}

class _WorkspaceProgressRow extends ConsumerWidget {
  final WorkspaceContextState state;

  const _WorkspaceProgressRow({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final isError = state.error != null;
    final progress = state.lsdfProgress ?? state.fileIndexProgress;
    final files = progress?.files ?? 0;
    final directories = progress?.directories ?? 0;

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: isError
            ? tokens.error.withValues(alpha: 0.08)
            : tokens.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: isError
              ? tokens.error.withValues(alpha: 0.18)
              : tokens.warning.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.sync,
            size: 14,
            color: isError ? tokens.error : tokens.warning,
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              isError
                  ? state.error!
                  : '${progress?.label ?? state.message ?? "Preparing workspace"} · $files files · $directories dirs',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isError ? tokens.error : tokens.textSecondary,
                fontSize: FontSizes.xs,
                height: 1.35,
              ),
            ),
          ),
          if (!isError)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: tokens.warning,
              ),
            ),
        ],
      ),
    );
  }
}

class _RunTimeline extends ConsumerWidget {
  final AgentRunState runs;

  const _RunTimeline({required this.runs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final filter = ref.watch(runConsoleFilterProvider);
    final visibleRuns = [...runs.activeRuns.values, ...runs.recentRuns]
        .where((run) {
          return switch (filter) {
            RunConsoleFilter.active =>
              run.status == AgentRunStatus.running ||
                  run.status == AgentRunStatus.streaming ||
                  run.status == AgentRunStatus.waitingForApproval,
            RunConsoleFilter.recent => true,
            RunConsoleFilter.failed => run.status == AgentRunStatus.failed,
          };
        })
        .take(8)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Run console',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xxs,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const Spacer(),
            for (final item in RunConsoleFilter.values) ...[
              _RunFilterChip(
                label: item.name,
                selected: filter == item,
                onTap: () =>
                    ref.read(runConsoleFilterProvider.notifier).set(item),
              ),
              const SizedBox(width: 4),
            ],
          ],
        ),
        const SizedBox(height: Spacing.sm),
        if (visibleRuns.isEmpty)
          Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: tokens.outlineSubtle),
            ),
            child: Text(
              'No ${filter.name} runs yet.',
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
            ),
          )
        else
          ...visibleRuns.map(
            (run) => Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: _RunTimelineRow(run: run),
            ),
          ),
      ],
    );
  }
}

class _RunFilterChip extends ConsumerWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RunFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? tokens.surfaceSelected : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
            color: selected
                ? tokens.accent.withValues(alpha: 0.35)
                : tokens.outlineSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? tokens.accent : tokens.textMuted,
            fontSize: FontSizes.xxs,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _RunTimelineRow extends ConsumerWidget {
  final AgentRun run;

  const _RunTimelineRow({required this.run});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final color = switch (run.status) {
      AgentRunStatus.succeeded => tokens.success,
      AgentRunStatus.failed => tokens.error,
      AgentRunStatus.cancelled => tokens.textMuted,
      AgentRunStatus.streaming => tokens.accent,
      AgentRunStatus.waitingForApproval => tokens.warning,
      AgentRunStatus.queued || AgentRunStatus.running => tokens.warning,
    };
    final latestEvent = run.events.isEmpty ? null : run.events.last.message;

    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.outlineSubtle),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          childrenPadding: const EdgeInsets.fromLTRB(
            Spacing.md,
            0,
            Spacing.md,
            Spacing.md,
          ),
          leading: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          title: Text(
            run.title?.isNotEmpty == true
                ? run.title!
                : '${_kindLabel(run.kind)} · ${run.model}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            [
              _kindLabel(run.kind),
              run.model,
              if (run.contextAttachmentCount > 0)
                '${run.contextAttachmentCount} context',
              if (run.tokenUsage.isNotEmpty)
                run.tokenUsage.formattedInputOutput,
              ?latestEvent,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xxs),
          ),
          iconColor: tokens.textMuted,
          collapsedIconColor: tokens.textMuted,
          children: [
            _RunDetailLine(label: 'Status', value: run.status.name),
            if (run.inputPreview?.isNotEmpty == true)
              _RunDetailLine(label: 'Input', value: run.inputPreview!),
            if (run.outputPreview?.isNotEmpty == true)
              _RunDetailLine(label: 'Output', value: run.outputPreview!),
            if (run.error?.isNotEmpty == true)
              _RunDetailLine(
                label: 'Error',
                value: run.error!,
                color: tokens.error,
              ),
            if (run.events.isNotEmpty) ...[
              const SizedBox(height: Spacing.sm),
              ...run.events.reversed
                  .take(5)
                  .map((event) => _RunEventRow(event: event)),
            ],
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                _RunAction(
                  icon: Icons.assignment_outlined,
                  label: 'Copy diagnostics',
                  onTap: () => Clipboard.setData(
                    ClipboardData(text: RunDiagnosticsSummary(run).serialize()),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                if (run.error != null)
                  _RunAction(
                    icon: Icons.error_outline,
                    label: 'Copy error',
                    onTap: () =>
                        Clipboard.setData(ClipboardData(text: run.error ?? '')),
                  ),
                if (run.retryPrompt != null &&
                    run.kind == AgentRunKind.chat) ...[
                  const SizedBox(width: Spacing.sm),
                  _RunAction(
                    icon: Icons.refresh,
                    label: 'Retry',
                    onTap: () => ref
                        .read(chatProvider.notifier)
                        .sendMessage(
                          run.retryPrompt!,
                          attachments: run.retryAttachments,
                        ),
                  ),
                ],
                if (run.status == AgentRunStatus.running ||
                    run.status == AgentRunStatus.streaming) ...[
                  const SizedBox(width: Spacing.sm),
                  _RunAction(
                    icon: Icons.stop_circle_outlined,
                    label: 'Cancel',
                    onTap: () =>
                        ref.read(chatProvider.notifier).cancelOperation(),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _kindLabel(AgentRunKind kind) {
    return switch (kind) {
      AgentRunKind.chat => 'Chat',
      AgentRunKind.inlineCompletion => 'Inline',
      AgentRunKind.editPrediction => 'Predict',
      AgentRunKind.backgroundTask => 'Task',
    };
  }
}

class _RunDetailLine extends ConsumerWidget {
  final String label;
  final String value;
  final Color? color;

  const _RunDetailLine({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xxs,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color ?? tokens.textSecondary,
                fontSize: FontSizes.xs,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RunEventRow extends ConsumerWidget {
  final AgentRunEvent event;

  const _RunEventRow({required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Row(
        children: [
          Icon(Icons.fiber_manual_record, size: 6, color: tokens.textMuted),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              event.message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xxs,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RunAction extends ConsumerWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _RunAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
        decoration: BoxDecoration(
          color: tokens.surfaceHover,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: tokens.outlineSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: tokens.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xxs,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentButton extends ConsumerWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? tokens.accent.withValues(alpha: 0.14) : null,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: selected
                ? tokens.accent.withValues(alpha: 0.28)
                : tokens.border.withValues(alpha: 0.45),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? tokens.accent : tokens.textSecondary,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ContextTile extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color statusColor;

  const _ContextTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Container(
      height: 62,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: tokens.bgLight.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.border.withValues(alpha: 0.48)),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Icon(icon, size: 14, color: statusColor),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xxs,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextPill extends ConsumerWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ContextPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: Spacing.sm),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageTile extends ConsumerWidget {
  final IconData icon;
  final String label;
  final String value;

  const _UsageTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Expanded(
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        decoration: BoxDecoration(
          color: tokens.bgLight.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: tokens.border.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: tokens.textMuted),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.xs,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xxs,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovalCard extends ConsumerWidget {
  final String requestId;
  final String preview;

  const _ApprovalCard({required this.requestId, required this.preview});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: tokens.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.warning.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, size: 15, color: tokens.warning),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: Spacing.md),
          _MiniDecisionButton(
            label: 'Reject',
            color: tokens.error,
            onTap: () =>
                ref.read(chatProvider.notifier).rejectConfirmation(requestId),
          ),
          const SizedBox(width: Spacing.sm),
          _MiniDecisionButton(
            label: 'Approve',
            color: tokens.success,
            onTap: () =>
                ref.read(chatProvider.notifier).approveConfirmation(requestId),
          ),
        ],
      ),
    );
  }
}

class _MiniDecisionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MiniDecisionButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ToolActivityRow extends ConsumerWidget {
  final ToolCallInfo tool;

  const _ToolActivityRow({required this.tool});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final color = _toolColor(tool.status, tokens);

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: tokens.bgLight.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.border.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Icon(_toolIcon(tool.status), size: 13, color: color),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tool.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  _toolSummary(tool),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xxs,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.md),
          Text(
            tool.status.name,
            style: TextStyle(
              color: color,
              fontSize: FontSizes.xxs,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  static IconData _toolIcon(ToolStatus status) {
    return switch (status) {
      ToolStatus.pending => Icons.schedule,
      ToolStatus.running => Icons.sync,
      ToolStatus.success => Icons.check,
      ToolStatus.error => Icons.error_outline,
      ToolStatus.cancelled => Icons.block,
    };
  }

  static Color _toolColor(ToolStatus status, ThemeTokens tokens) {
    return switch (status) {
      ToolStatus.pending => tokens.textMuted,
      ToolStatus.running => tokens.warning,
      ToolStatus.success => tokens.success,
      ToolStatus.error => tokens.error,
      ToolStatus.cancelled => tokens.textDisabled,
    };
  }

  static String _toolSummary(ToolCallInfo tool) {
    final filePath =
        tool.arguments['file_path'] ??
        tool.arguments['path'] ??
        tool.arguments['target_file'] ??
        tool.arguments['command'];
    if (filePath != null) return '$filePath';
    if (tool.error != null && tool.error!.isNotEmpty) return tool.error!;
    if (tool.result != null && tool.result!.isNotEmpty) return tool.result!;
    if (tool.arguments.isNotEmpty) return tool.argumentsJson;
    return 'No details';
  }
}
