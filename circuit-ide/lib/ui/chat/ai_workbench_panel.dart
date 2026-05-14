import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../core/utils/platform_utils.dart';
import '../../enums/connection_status.dart';
import '../../enums/tool_status.dart';
import '../../models/editor_state.dart';
import '../../models/tool_call_info.dart';
import '../../state/ai_context_provider.dart';
import '../../state/chat_provider.dart';
import '../../state/connection_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/terminal_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';

enum _WorkbenchTab { context, activity }

class AiWorkbenchPanel extends ConsumerStatefulWidget {
  const AiWorkbenchPanel({super.key});

  @override
  ConsumerState<AiWorkbenchPanel> createState() => _AiWorkbenchPanelState();
}

class _AiWorkbenchPanelState extends ConsumerState<AiWorkbenchPanel> {
  _WorkbenchTab _tab = _WorkbenchTab.context;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

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
                  selected: _tab == _WorkbenchTab.context,
                  onTap: () => setState(() => _tab = _WorkbenchTab.context),
                ),
                const SizedBox(width: Spacing.sm),
                _SegmentButton(
                  label: 'Activity',
                  selected: _tab == _WorkbenchTab.activity,
                  onTap: () => setState(() => _tab = _WorkbenchTab.activity),
                ),
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: AnimationDurations.smooth,
            child: _tab == _WorkbenchTab.context
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
                  icon: Icons.memory_outlined,
                  title: 'Token mode',
                  subtitle: 'L-SDF index + targeted files',
                  statusColor: tokens.accent,
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
                icon: Icons.auto_awesome,
                label: 'Tools can edit, read, and run',
                color: tokens.accent,
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              _ContextToggle(
                icon: Icons.hub_outlined,
                label: 'L-SDF',
                value: contextState.includeLsdfIndex,
                tokenHint: '~300',
                onTap: () =>
                    ref.read(aiContextProvider.notifier).toggleLsdfIndex(),
              ),
              _ContextToggle(
                icon: Icons.description_outlined,
                label: 'Active file',
                value: contextState.includeActiveFile,
                enabled: activeFile != null,
                tokenHint: activeFile == null
                    ? '0'
                    : '~${_estimateTokens(activeFile.content)}',
                onTap: () =>
                    ref.read(aiContextProvider.notifier).toggleActiveFile(),
              ),
              _ContextToggle(
                icon: Icons.terminal,
                label: 'Terminal',
                value: contextState.includeTerminalOutput,
                enabled: terminalOutput.isNotEmpty,
                tokenHint: '~${_estimateTokens(terminalOutput)}',
                onTap: () =>
                    ref.read(aiContextProvider.notifier).toggleTerminalOutput(),
              ),
              _ContextToggle(
                icon: Icons.account_tree_outlined,
                label: 'Git diff',
                value: contextState.includeGitDiff,
                tokenHint: 'scan',
                onTap: () =>
                    ref.read(aiContextProvider.notifier).toggleGitDiff(),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              _WorkbenchAction(
                icon: Icons.hub_outlined,
                label: 'Map Project',
                onTap: () => _send(
                  ref,
                  'Use the L-SDF code index to map this project. Summarize architecture, key entry points, and the safest next improvements.',
                ),
              ),
              _WorkbenchAction(
                icon: Icons.manage_search,
                label: 'Review File',
                enabled: activeFile != null,
                onTap: () => _sendFilePrompt(
                  ref,
                  activeFile,
                  'Review this file for bugs, edge cases, and maintainability issues. Make focused fixes when appropriate.',
                ),
              ),
              _WorkbenchAction(
                icon: Icons.science_outlined,
                label: 'Test File',
                enabled: activeFile != null,
                onTap: () => _sendFilePrompt(
                  ref,
                  activeFile,
                  'Add or update focused tests for this file. Use existing test patterns in the repo.',
                ),
              ),
              _WorkbenchAction(
                icon: Icons.terminal,
                label: 'Use Terminal',
                enabled: terminalOutput.isNotEmpty,
                onTap: () => _send(
                  ref,
                  'Analyze the recent terminal output below. Identify the issue and fix code or suggest the right command.\n\n```\n$terminalOutput\n```',
                ),
              ),
              _WorkbenchAction(
                icon: Icons.account_tree_outlined,
                label: 'Review Diff',
                onTap: () => _send(
                  ref,
                  'Review the current git diff. Prioritize bugs, regressions, missing tests, and risky UI behavior.',
                ),
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

  static String _estimateTokens(String value) {
    final estimate = (value.length / 4).ceil();
    if (estimate >= 1000) return '${(estimate / 1000).toStringAsFixed(1)}k';
    return '$estimate';
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

  static void _sendFilePrompt(WidgetRef ref, EditorTab? tab, String task) {
    if (tab == null) return;
    _send(
      ref,
      '[Active file: ${tab.filePath}]\n'
      '$task\n\n'
      'Use the current editor contents and the project index before making changes.',
    );
  }

  static void _send(WidgetRef ref, String prompt) {
    ref
        .read(chatProvider.notifier)
        .sendMessage(_withPinnedContext(ref, prompt));
  }

  static String _withPinnedContext(WidgetRef ref, String prompt) {
    final contextState = ref.read(aiContextProvider);
    final activeFile = _activeFile(ref.read(editorProvider).activeTab);
    final terminalOutput = ref
        .read(terminalProvider.notifier)
        .getActiveTerminalOutput(lines: 60)
        .trim();
    final parts = <String>[];

    if (contextState.includeLsdfIndex) {
      parts.add(
        '[Pinned context: use the L-SDF code index before loading broad file context.]',
      );
    }
    if (contextState.includeActiveFile && activeFile != null) {
      parts.add('[Pinned active file: ${activeFile.filePath}]');
    }
    if (contextState.includeTerminalOutput && terminalOutput.isNotEmpty) {
      parts.add('[Pinned terminal output]\n```\n$terminalOutput\n```');
    }
    if (contextState.includeGitDiff) {
      parts.add(
        '[Pinned git diff: inspect the current working tree diff before answering.]',
      );
    }
    parts.add(prompt);
    return parts.join('\n\n');
  }
}

class _ActivityWorkbench extends ConsumerWidget {
  const _ActivityWorkbench({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final chatState = ref.watch(chatProvider);
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
        ],
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

class _ContextToggle extends ConsumerStatefulWidget {
  final IconData icon;
  final String label;
  final bool value;
  final bool enabled;
  final String tokenHint;
  final VoidCallback onTap;

  const _ContextToggle({
    required this.icon,
    required this.label,
    required this.value,
    required this.tokenHint,
    required this.onTap,
    this.enabled = true,
  });

  @override
  ConsumerState<_ContextToggle> createState() => _ContextToggleState();
}

class _ContextToggleState extends ConsumerState<_ContextToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final selected = widget.value && widget.enabled;
    final color = !widget.enabled
        ? tokens.textDisabled
        : selected
        ? tokens.accent
        : tokens.textSecondary;

    return Tooltip(
      message: widget.enabled
          ? '${widget.label} context · ${widget.tokenHint} tokens'
          : '${widget.label} context unavailable',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: widget.enabled ? widget.onTap : null,
          child: AnimatedContainer(
            duration: AnimationDurations.fast,
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            decoration: BoxDecoration(
              color: selected
                  ? tokens.accent.withValues(alpha: 0.12)
                  : _hovered && widget.enabled
                  ? tokens.bgLighter.withValues(alpha: 0.7)
                  : tokens.bgLight.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(Radii.pill),
              border: Border.all(
                color: selected
                    ? tokens.accent.withValues(alpha: 0.28)
                    : tokens.border.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 12, color: color),
                const SizedBox(width: Spacing.sm),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: color,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Text(
                  widget.tokenHint,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.75),
                    fontSize: FontSizes.xxs,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkbenchAction extends ConsumerStatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  const _WorkbenchAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  ConsumerState<_WorkbenchAction> createState() => _WorkbenchActionState();
}

class _WorkbenchActionState extends ConsumerState<_WorkbenchAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final color = widget.enabled
        ? (_hovered ? tokens.accent : tokens.textSecondary)
        : tokens.textDisabled;

    return Tooltip(
      message: widget.enabled ? widget.label : 'Context unavailable',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: widget.enabled ? widget.onTap : null,
          child: AnimatedContainer(
            duration: AnimationDurations.fast,
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            decoration: BoxDecoration(
              color: widget.enabled && _hovered
                  ? tokens.accent.withValues(alpha: 0.1)
                  : tokens.bgLight.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(
                color: widget.enabled && _hovered
                    ? tokens.accent.withValues(alpha: 0.28)
                    : tokens.border.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 13, color: color),
                const SizedBox(width: Spacing.sm),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: color,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
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
