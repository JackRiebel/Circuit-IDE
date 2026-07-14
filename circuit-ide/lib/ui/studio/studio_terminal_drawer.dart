import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/agent_workspace.dart';
import '../../models/command_run.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_turn.dart';
import '../../state/command_run_provider.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';
import 'studio_chrome.dart';

/// Read-only command history for the selected Studio task.
///
/// Command execution and the active selection remain owned by their existing
/// providers. This module only projects live and persisted command evidence.
class StudioTerminalDrawer extends ConsumerWidget {
  final AgentTask? task;

  const StudioTerminalDrawer({super.key, this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drawer = ref.watch(studioRightDrawerProvider);
    final tokens = ref.watch(themeProvider);
    final thread = ref.watch(studioThreadProvider).threadForTaskView(task?.id);
    final commands = terminalCommandRunsForThread(
      liveCommands: ref.watch(commandRunProvider).values,
      thread: thread,
      taskId: task?.id,
    )..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final selected = commands
        .where((command) => command.id == drawer.commandRunId)
        .firstOrNull;
    final command = selected ?? commands.firstOrNull;
    if (commands.isEmpty) {
      return _TerminalEmptyState(
        icon: StudioIcons.terminalOutlined,
        title: 'No command logs',
        detail:
            'Approved verification commands and tool-run output will appear here. Studio does not expose an interactive terminal in the core agent loop.',
        actionLabel: 'Start a task',
        onAction: () => ref.read(studioShellProvider.notifier).openHome(),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        Text(
          'Command logs',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        for (final candidate in commands.take(12))
          _TerminalCommandRow(
            command: candidate,
            selected: candidate.id == command?.id,
            onTap: () => ref
                .read(studioRightDrawerProvider.notifier)
                .openCommand(candidate.id),
          ),
        if (command != null) ...[
          const SizedBox(height: Spacing.md),
          _TerminalDocumentView(
            title: command.command,
            text: command.combinedOutput.isEmpty
                ? 'No output captured yet.'
                : command.combinedOutput,
          ),
        ],
      ],
    );
  }
}

bool _commandBelongsToThread(
  CommandRun command,
  StudioThread? thread,
  String? taskId,
) {
  if (thread == null && taskId == null) return false;
  if (taskId != null && command.taskId == taskId) return true;
  if (thread == null) return false;
  if (command.taskId != null && command.taskId == thread.taskId) return true;
  final turnIds = thread.turns.map((turn) => turn.id).toSet();
  final requestIds = thread.turns.map((turn) => turn.requestId).toSet();
  return command.turnId != null && turnIds.contains(command.turnId) ||
      command.requestId != null && requestIds.contains(command.requestId);
}

List<CommandRun> terminalCommandRunsForThread({
  required Iterable<CommandRun> liveCommands,
  required StudioThread? thread,
  required String? taskId,
}) {
  final commands = <String, CommandRun>{};
  for (final command in liveCommands) {
    if (!_commandBelongsToThread(command, thread, taskId)) continue;
    commands[command.id] = command;
  }
  if (thread != null) {
    for (final command in _persistedCommandRunsForThread(thread)) {
      commands.putIfAbsent(command.id, () => command);
    }
  }
  return commands.values.toList();
}

Iterable<CommandRun> _persistedCommandRunsForThread(StudioThread thread) sync* {
  for (final turn in thread.turns) {
    for (final event in turn.events) {
      if (event.type != StudioTurnEventType.completionSummary) continue;
      if (!event.id.startsWith('command-run-')) continue;
      final command = _commandRunFromTurnEvent(thread, turn, event);
      if (command != null) yield command;
    }
  }
}

CommandRun? _commandRunFromTurnEvent(
  StudioThread thread,
  StudioTurn turn,
  StudioTurnEvent event,
) {
  final detail = event.detail.trim();
  final command = _commandLineFromDetail(detail);
  if (command == null) return null;
  final status = _commandRunStatusFromTitle(event.title);
  final commandRunId = _commandRunIdFromEvent(turn, event);
  return CommandRun(
    id: commandRunId,
    requestId: event.requestId,
    turnId: turn.id,
    taskId: thread.taskId,
    command: command,
    status: status,
    startedAt: event.timestamp,
    endedAt: event.timestamp,
    exitCode: _exitCodeFromDetail(detail),
    stdout: _commandOutputFromDetail(detail),
    events: [
      CommandRunEvent(
        type: CommandRunEventType.started,
        timestamp: event.timestamp,
        text: command,
      ),
      CommandRunEvent(
        type: status == CommandRunStatus.cancelled
            ? CommandRunEventType.cancelled
            : status == CommandRunStatus.timedOut
            ? CommandRunEventType.timedOut
            : CommandRunEventType.exited,
        timestamp: event.timestamp,
        text: event.title,
      ),
    ],
  );
}

String _commandRunIdFromEvent(StudioTurn turn, StudioTurnEvent event) {
  final prefix = 'command-run-${turn.id}-';
  if (event.id.startsWith(prefix) && event.id.length > prefix.length) {
    return event.id.substring(prefix.length);
  }
  return event.id;
}

String? _commandLineFromDetail(String detail) {
  for (final line in detail.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.toLowerCase().startsWith('command:')) {
      final command = trimmed.substring('command:'.length).trim();
      return command.isEmpty ? null : command;
    }
  }
  return null;
}

int? _exitCodeFromDetail(String detail) {
  final match = RegExp(
    r'^Exit code:\s*(-?\d+)$',
    multiLine: true,
  ).firstMatch(detail);
  if (match == null) return null;
  return int.tryParse(match.group(1) ?? '');
}

String _commandOutputFromDetail(String detail) {
  final output = detail
      .split('\n')
      .where((line) {
        final trimmed = line.trimLeft().toLowerCase();
        return !trimmed.startsWith('command:') &&
            !trimmed.startsWith('exit code:');
      })
      .join('\n')
      .trim();
  return output;
}

CommandRunStatus _commandRunStatusFromTitle(String title) {
  final normalized = title.toLowerCase();
  if (normalized.contains('cancel')) return CommandRunStatus.cancelled;
  if (normalized.contains('timeout') || normalized.contains('timed out')) {
    return CommandRunStatus.timedOut;
  }
  if (normalized.contains('blocked')) return CommandRunStatus.blocked;
  if (normalized.contains('failed') || normalized.contains('error')) {
    return CommandRunStatus.failed;
  }
  return CommandRunStatus.succeeded;
}

class _TerminalCommandRow extends ConsumerWidget {
  final CommandRun command;
  final bool selected;
  final VoidCallback onTap;

  const _TerminalCommandRow({
    required this.command,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: StudioFocusableActionSurface(
        key: ValueKey('studio-terminal-command-${command.id}'),
        semanticLabel:
            'Open ${command.status.name} command: ${command.command}',
        selected: selected,
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: selected
                ? tokens.studioControl.withValues(alpha: 0.62)
                : tokens.studioActivityRow.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: tokens.studioDivider.withValues(
                alpha: selected ? 0.72 : 0.42,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  StudioIcons.terminalOutlined,
                  color: tokens.textMuted,
                  size: 13,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      command.command,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: FontSizes.xs,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      command.status.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: FontSizes.xs,
                        height: 1.22,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalDocumentView extends ConsumerWidget {
  final String title;
  final String text;

  const _TerminalDocumentView({required this.title, required this.text});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return SizedBox(
      height: 280,
      child: Container(
        decoration: BoxDecoration(
          color: tokens.surfaceInset.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: tokens.studioDivider.withValues(alpha: 0.68),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.sm,
                Spacing.sm,
                Spacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: FontSizes.xs,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  StudioChromeIconButton(
                    tooltip: 'Copy',
                    onTap: () => Clipboard.setData(ClipboardData(text: text)),
                    icon: StudioIcons.copy,
                    iconSize: 14,
                  ),
                ],
              ),
            ),
            Divider(
              color: tokens.studioDivider.withValues(alpha: 0.72),
              height: 1,
            ),
            Expanded(
              child: RepaintBoundary(
                child: _TerminalVirtualizedTextBody(
                  text,
                  padding: const EdgeInsets.all(Spacing.md),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalVirtualizedTextBody extends ConsumerStatefulWidget {
  final String text;
  final EdgeInsets padding;

  const _TerminalVirtualizedTextBody(this.text, {required this.padding});

  @override
  ConsumerState<_TerminalVirtualizedTextBody> createState() =>
      _TerminalVirtualizedTextBodyState();
}

class _TerminalVirtualizedTextBodyState
    extends ConsumerState<_TerminalVirtualizedTextBody> {
  late List<String> _lines;
  late int _maxLineLength;

  @override
  void initState() {
    super.initState();
    _prepareLines();
  }

  @override
  void didUpdateWidget(covariant _TerminalVirtualizedTextBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _prepareLines();
  }

  void _prepareLines() {
    final text = widget.text.isEmpty ? '(empty)' : widget.text;
    _lines = text.split('\n');
    _maxLineLength = 0;
    for (final line in _lines) {
      if (line.length > _maxLineLength) _maxLineLength = line.length;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final lineNumberWidth = (_lines.length + 1).toString().length * 7.0 + 28;
    return LayoutBuilder(
      builder: (context, constraints) {
        final estimatedTextWidth =
            (_maxLineLength * 7.1) + lineNumberWidth + 48;
        final contentWidth = estimatedTextWidth
            .clamp(constraints.maxWidth, 2200.0)
            .toDouble();
        return Scrollbar(
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth,
              child: ListView.builder(
                key: const ValueKey('studio-terminal-virtualized-text-lines'),
                padding: widget.padding,
                itemCount: _lines.length,
                itemBuilder: (context, index) => _TerminalVirtualizedTextLine(
                  lineNumber: index + 1,
                  lineNumberWidth: lineNumberWidth,
                  line: _lines[index],
                  tokens: tokens,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TerminalVirtualizedTextLine extends StatelessWidget {
  final int lineNumber;
  final double lineNumberWidth;
  final String line;
  final ThemeTokens tokens;

  const _TerminalVirtualizedTextLine({
    required this.lineNumber,
    required this.lineNumberWidth,
    required this.line,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final color = _lineColor();
    return SizedBox(
      height: 19,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: lineNumberWidth,
            child: Text(
              '$lineNumber',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: tokens.textMuted.withValues(alpha: 0.56),
                fontSize: FontSizes.xs,
                height: 1.42,
                fontFamily: EditorDefaults.studioMonospaceFontFamily,
              ),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              line.isEmpty ? ' ' : line,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: color,
                fontSize: FontSizes.xs,
                height: 1.42,
                fontFamily: EditorDefaults.studioMonospaceFontFamily,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _lineColor() {
    if (line.startsWith('+') && !line.startsWith('+++')) {
      return tokens.success.withValues(alpha: 0.92);
    }
    if (line.startsWith('-') && !line.startsWith('---')) {
      return tokens.error.withValues(alpha: 0.92);
    }
    if (line.startsWith('@@')) return tokens.accent.withValues(alpha: 0.9);
    if (line.startsWith('diff ') ||
        line.startsWith('index ') ||
        line.startsWith('+++') ||
        line.startsWith('---')) {
      return tokens.textMuted;
    }
    return tokens.textSecondary;
  }
}

class _TerminalEmptyState extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String detail;
  final String actionLabel;
  final VoidCallback onAction;

  const _TerminalEmptyState({
    required this.icon,
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: tokens.textMuted, size: 24),
            const SizedBox(height: Spacing.md),
            Text(
              title,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.sm,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
            ),
            const SizedBox(height: Spacing.md),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
