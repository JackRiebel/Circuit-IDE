import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../core/utils/platform_utils.dart';
import '../../state/chat_provider.dart';
import '../../state/theme_provider.dart';
import '../../state/connection_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/terminal_provider.dart';
import '../../enums/connection_status.dart';
import 'chat_message_widget.dart';
import 'chat_input.dart';
import 'ai_workbench_panel.dart';
import 'streaming_indicator.dart';
import 'confirmation_dialog.dart';
import 'provider_switcher.dart';
import 'session_list.dart';
import 'token_tracker.dart';
import '../common/circuit_primitives.dart';

enum _ChatHeaderAction { save, history, clear }

class ChatPanel extends ConsumerStatefulWidget {
  const ChatPanel({super.key});

  @override
  ConsumerState<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<ChatPanel> {
  final _scrollController = ScrollController();
  bool _showHistory = false;
  bool _showWorkbench = true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _reconnect(WidgetRef ref) async {
    ref
        .read(connectionStatusProvider.notifier)
        .set(ConnectionStatus.connecting);

    final service = ref.read(agentServiceProvider);
    final workingDir =
        ref.read(fileTreeProvider).rootPath ?? PlatformUtils.scratchDir;
    final provider = ref.read(settingsProvider).activeProvider;

    try {
      final success = await service.connectWithSavedCredentials(
        workingDir: workingDir,
        preferredProvider: provider,
      );
      if (!mounted) return;
      ref
          .read(connectionStatusProvider.notifier)
          .set(success ? ConnectionStatus.connected : ConnectionStatus.error);
    } catch (_) {
      if (!mounted) return;
      ref.read(connectionStatusProvider.notifier).set(ConnectionStatus.error);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final chatState = ref.watch(chatProvider);
    final connectionStatus = ref.watch(connectionStatusProvider);

    if (chatState.isStreaming || chatState.messages.isNotEmpty) {
      _scrollToBottom();
    }

    return Container(
      color: tokens.bgMain,
      child: Column(
        children: [
          // Header
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
            decoration: BoxDecoration(
              color: tokens.bgLight,
              border: Border(
                bottom: BorderSide(color: tokens.border.withValues(alpha: 0.6)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 13,
                  color: tokens.accent.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 6),
                Text(
                  'AI ASSISTANT',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: connectionStatus == ConnectionStatus.connected
                        ? const Color(0xFF4ADE80)
                        : connectionStatus == ConnectionStatus.connecting
                        ? tokens.warning
                        : tokens.error,
                    boxShadow: connectionStatus == ConnectionStatus.connected
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFF4ADE80,
                              ).withValues(alpha: 0.4),
                              blurRadius: 4,
                            ),
                          ]
                        : null,
                  ),
                ),
                const Spacer(),
                const ProviderSwitcher(),
                const SizedBox(width: Spacing.sm),
                CircuitIconButton(
                  icon: Icons.dashboard_customize_outlined,
                  tooltip: _showWorkbench
                      ? 'Hide AI workbench'
                      : 'Show AI workbench',
                  selected: _showWorkbench,
                  onPressed: () =>
                      setState(() => _showWorkbench = !_showWorkbench),
                ),
                CircuitActionMenu<_ChatHeaderAction>(
                  tooltip: 'Chat actions',
                  items: [
                    PopupMenuItem(
                      value: _ChatHeaderAction.save,
                      enabled: chatState.messages.isNotEmpty,
                      child: const Text('Save session'),
                    ),
                    PopupMenuItem(
                      value: _ChatHeaderAction.history,
                      child: Text(
                        _showHistory ? 'Hide history' : 'Show history',
                      ),
                    ),
                    PopupMenuItem(
                      value: _ChatHeaderAction.clear,
                      enabled: chatState.messages.isNotEmpty,
                      child: const Text('Clear chat'),
                    ),
                  ],
                  onSelected: (action) async {
                    switch (action) {
                      case _ChatHeaderAction.save:
                        final name = await ref
                            .read(chatProvider.notifier)
                            .saveSession();
                        if (name != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Session saved'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                        break;
                      case _ChatHeaderAction.history:
                        setState(() => _showHistory = !_showHistory);
                        break;
                      case _ChatHeaderAction.clear:
                        ref.read(chatProvider.notifier).clearHistory();
                        break;
                    }
                  },
                ),
              ],
            ),
          ),

          if (_showWorkbench)
            const AiWorkbenchPanel()
          else
            const _ChatContextStrip(),

          // Connection status
          if (connectionStatus != ConnectionStatus.connected)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.xl,
                vertical: Spacing.md,
              ),
              decoration: BoxDecoration(
                color: connectionStatus == ConnectionStatus.error
                    ? tokens.error.withValues(alpha: 0.08)
                    : tokens.warning.withValues(alpha: 0.08),
                border: Border(
                  bottom: BorderSide(
                    color: connectionStatus == ConnectionStatus.error
                        ? tokens.error.withValues(alpha: 0.15)
                        : tokens.warning.withValues(alpha: 0.15),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    connectionStatus == ConnectionStatus.connecting
                        ? Icons.sync
                        : Icons.info_outline,
                    size: 13,
                    color: connectionStatus == ConnectionStatus.error
                        ? tokens.error
                        : tokens.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      switch (connectionStatus) {
                        ConnectionStatus.disconnected =>
                          'Not connected — configure credentials in Settings.',
                        ConnectionStatus.connecting => 'Connecting...',
                        ConnectionStatus.error => 'Connection error',
                        _ => '',
                      },
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: FontSizes.xs,
                      ),
                    ),
                  ),
                  if (connectionStatus == ConnectionStatus.disconnected ||
                      connectionStatus == ConnectionStatus.error)
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => _reconnect(ref),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.md,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(Radii.sm),
                            border: Border.all(
                              color: tokens.accent.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Text(
                            'Connect',
                            style: TextStyle(
                              color: tokens.accent,
                              fontSize: FontSizes.xs,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // Error banner
          if (chatState.error != null)
            GestureDetector(
              onTap: () => ref.read(chatProvider.notifier).clearError(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.xl,
                  vertical: Spacing.md,
                ),
                decoration: BoxDecoration(
                  color: tokens.error.withValues(alpha: 0.08),
                  border: Border(
                    bottom: BorderSide(
                      color: tokens.error.withValues(alpha: 0.15),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 13, color: tokens.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        chatState.error!,
                        style: TextStyle(
                          color: tokens.error,
                          fontSize: FontSizes.xs,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.close,
                      size: 12,
                      color: tokens.error.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
            ),

          // Session history panel
          if (_showHistory)
            SessionList(
              onClose: () => setState(() => _showHistory = false),
              onSessionLoaded: () => setState(() => _showHistory = false),
            ),

          // Messages
          Expanded(
            child: chatState.messages.isEmpty
                ? _EmptyChat()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                    itemCount:
                        chatState.messages.length +
                        ((chatState.isProcessing || chatState.isStreaming)
                            ? 1
                            : 0),
                    itemBuilder: (context, index) {
                      if (index < chatState.messages.length) {
                        return _FadeInMessage(
                          key: ValueKey(chatState.messages[index].id),
                          child: ChatMessageWidget(
                            message: chatState.messages[index],
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.xl,
                          vertical: Spacing.sm,
                        ),
                        child: StreamingIndicator(
                          content: chatState.streamingContent,
                        ),
                      );
                    },
                  ),
          ),

          if (chatState.pendingConfirmation != null)
            ConfirmationDialog(request: chatState.pendingConfirmation!),

          const TokenTracker(),
          const ChatInput(),
        ],
      ),
    );
  }
}

class _ChatContextStrip extends ConsumerWidget {
  const _ChatContextStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final rootPath = ref.watch(fileTreeProvider).rootPath;
    final activeTab = ref.watch(editorProvider).activeTab;
    final terminalState = ref.watch(terminalProvider);
    final activeFile =
        activeTab != null && !activeTab.filePath.startsWith('circuit://')
        ? activeTab
        : null;
    final outputLines = terminalState.terminals.isEmpty
        ? 0
        : terminalState
              .terminals[terminalState.activeTerminalIndex]
              .outputBuffer
              .length;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.xl,
        vertical: Spacing.md,
      ),
      decoration: BoxDecoration(
        color: tokens.bgMain,
        border: Border(
          bottom: BorderSide(color: tokens.border.withValues(alpha: 0.4)),
        ),
      ),
      child: Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.sm,
        children: [
          _ContextBadge(
            icon: Icons.folder_open_outlined,
            label: rootPath == null
                ? 'Scratch workspace'
                : p.basename(rootPath),
            tooltip: rootPath ?? PlatformUtils.scratchDir,
            muted: rootPath == null,
          ),
          _ContextBadge(
            icon: Icons.description_outlined,
            label: activeFile == null ? 'No active file' : activeFile.fileName,
            tooltip: activeFile?.filePath,
            muted: activeFile == null,
          ),
          _ContextBadge(
            icon: Icons.terminal,
            label: outputLines == 0
                ? 'Terminal ready'
                : '$outputLines terminal lines',
            muted: outputLines == 0,
          ),
        ],
      ),
    );
  }
}

class _ContextBadge extends ConsumerWidget {
  final IconData icon;
  final String label;
  final String? tooltip;
  final bool muted;

  const _ContextBadge({
    required this.icon,
    required this.label,
    this.tooltip,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final color = muted ? tokens.textMuted : tokens.textSecondary;

    return Tooltip(
      message: tooltip ?? label,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 180),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: tokens.bgLight.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: tokens.border.withValues(alpha: 0.5)),
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
                  color: color,
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

class _FadeInMessage extends StatefulWidget {
  final Widget child;

  const _FadeInMessage({super.key, required this.child});

  @override
  State<_FadeInMessage> createState() => _FadeInMessageState();
}

class _FadeInMessageState extends State<_FadeInMessage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AnimationDurations.smooth,
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(position: _slideAnimation, child: widget.child),
    );
  }
}

class _EmptyChat extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.xl),
              color: tokens.accent.withValues(alpha: 0.08),
              border: Border.all(color: tokens.accent.withValues(alpha: 0.15)),
            ),
            child: Icon(
              Icons.auto_awesome,
              size: 22,
              color: tokens.accent.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: Spacing.xl),
          Text(
            'Start a conversation',
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.base,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'Ask about your code, request changes,\nor get help with debugging.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.sm,
              height: 1.5,
            ),
          ),
          const SizedBox(height: Spacing.xxl),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 330),
            child: Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.md,
              alignment: WrapAlignment.center,
              children: [
                _QuickChip(
                  icon: Icons.manage_search,
                  label: 'Review open file',
                  prompt:
                      'Review the active editor file for bugs, edge cases, and maintainability issues. Make fixes if appropriate.',
                  tokens: tokens,
                  ref: ref,
                ),
                _QuickChip(
                  icon: Icons.terminal,
                  label: 'Diagnose terminal',
                  prompt:
                      'Inspect the recent terminal output and explain any errors. Fix the code or suggest the correct command.',
                  tokens: tokens,
                  ref: ref,
                ),
                _QuickChip(
                  icon: Icons.science_outlined,
                  label: 'Add tests',
                  prompt:
                      'Find the best place to add tests for the active work and implement focused coverage.',
                  tokens: tokens,
                  ref: ref,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? prompt;
  final dynamic tokens;
  final WidgetRef ref;

  const _QuickChip({
    required this.icon,
    required this.label,
    this.prompt,
    required this.tokens,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          final prompt = this.prompt;
          if (prompt == null || prompt.isEmpty) return;
          ref.read(chatProvider.notifier).sendMessage(prompt);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.sm + 2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(color: tokens.accent.withValues(alpha: 0.3)),
            color: tokens.accent.withValues(alpha: 0.05),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: tokens.accent),
              const SizedBox(width: Spacing.sm),
              Text(
                label,
                style: TextStyle(
                  color: tokens.accent,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
