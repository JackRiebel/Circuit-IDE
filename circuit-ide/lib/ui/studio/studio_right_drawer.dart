import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/agent_workspace.dart';
import '../../models/command_run.dart';
import '../../models/context_pack.dart';
import '../../models/git_models.dart';
import '../../models/provider_lifecycle_event.dart';
import '../../models/reviewed_edit.dart';
import '../../models/studio_browser.dart';
import '../../models/studio_right_drawer.dart';
import '../../models/studio_shell.dart';
import '../../models/studio_source_artifact.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_turn.dart';
import '../../models/studio_view_models.dart';
import '../../state/command_run_provider.dart';
import '../../state/context_pack_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/git_provider.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/studio_browser_provider.dart';
import '../../state/studio_code_edit_provider.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_source_artifact_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_chrome.dart';

class StudioRightDrawer extends ConsumerWidget {
  final AgentTask? task;

  const StudioRightDrawer({super.key, this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final drawer = ref.watch(studioRightDrawerProvider);
    final width = drawer.width;

    return AnimatedContainer(
      duration: AnimationDurations.panel,
      curve: AnimationCurves.smooth,
      width: width,
      margin: const EdgeInsets.fromLTRB(0, 66, Spacing.md, Spacing.lg),
      decoration: BoxDecoration(
        color: tokens.studioDrawer,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.52)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: drawer.collapsed
          ? const _CollapsedDrawer()
          : Column(
              children: [
                _DrawerHeader(task: task),
                _DrawerModeTabs(active: drawer.mode),
                Expanded(child: _DrawerBody(task: task)),
              ],
            ),
    );
  }
}

const _visibleDrawerModes = <StudioDrawerMode>[
  StudioDrawerMode.progress,
  StudioDrawerMode.code,
  StudioDrawerMode.diff,
  StudioDrawerMode.files,
  StudioDrawerMode.terminal,
  StudioDrawerMode.sources,
  StudioDrawerMode.context,
];

class _CollapsedDrawer extends ConsumerWidget {
  const _CollapsedDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Column(
      children: [
        IconButton(
          tooltip: 'Expand right panel',
          onPressed: () =>
              ref.read(studioRightDrawerProvider.notifier).toggleCollapsed(),
          icon: Icon(Icons.chevron_left, color: tokens.textMuted, size: 18),
        ),
        for (final mode in _visibleDrawerModes)
          _ModeIconButton(mode: mode, active: false, compact: true),
      ],
    );
  }
}

class _DrawerHeader extends ConsumerWidget {
  final AgentTask? task;

  const _DrawerHeader({this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final drawer = ref.watch(studioRightDrawerProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 13, 8, 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _titleFor(drawer.mode),
              style: TextStyle(
                color: tokens.textSecondary.withValues(alpha: 0.96),
                fontSize: FontSizes.base,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          StudioChromeIconButton(
            tooltip: drawer.expanded ? 'Shrink panel' : 'Expand panel',
            onTap: () =>
                ref.read(studioRightDrawerProvider.notifier).toggleExpanded(),
            icon: drawer.expanded
                ? Icons.close_fullscreen
                : Icons.open_in_full_outlined,
          ),
          StudioChromeIconButton(
            tooltip: 'Collapse panel',
            onTap: () =>
                ref.read(studioRightDrawerProvider.notifier).toggleCollapsed(),
            icon: Icons.chevron_right,
          ),
        ],
      ),
    );
  }

  String _titleFor(StudioDrawerMode mode) {
    return switch (mode) {
      StudioDrawerMode.progress => 'Progress',
      StudioDrawerMode.browser => 'Preview',
      StudioDrawerMode.code => 'Code',
      StudioDrawerMode.diff => 'Diff',
      StudioDrawerMode.files => 'Files',
      StudioDrawerMode.terminal => 'Terminal',
      StudioDrawerMode.sources => 'Sources',
      StudioDrawerMode.context => 'Context',
    };
  }
}

class _DrawerModeTabs extends ConsumerWidget {
  final StudioDrawerMode active;

  const _DrawerModeTabs({required this.active});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: tokens.studioDivider.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          for (final mode in _visibleDrawerModes)
            _ModeIconButton(mode: mode, active: mode == active),
        ],
      ),
    );
  }
}

class _ModeIconButton extends ConsumerWidget {
  final StudioDrawerMode mode;
  final bool active;
  final bool compact;

  const _ModeIconButton({
    required this.mode,
    required this.active,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final color = active ? tokens.textSecondary : tokens.textMuted;
    return Tooltip(
      message: _label(mode),
      child: InkWell(
        onTap: () =>
            ref.read(studioRightDrawerProvider.notifier).openMode(mode),
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          width: compact ? 38 : 30,
          height: 28,
          margin: EdgeInsets.only(right: compact ? 0 : 5),
          decoration: BoxDecoration(
            color: active
                ? tokens.studioControl.withValues(alpha: 0.66)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.md),
            border: active
                ? Border.all(color: tokens.studioDivider.withValues(alpha: 0.5))
                : null,
          ),
          child: Icon(_icon(mode), color: color, size: 14),
        ),
      ),
    );
  }

  IconData _icon(StudioDrawerMode mode) {
    return switch (mode) {
      StudioDrawerMode.progress => Icons.radio_button_checked,
      StudioDrawerMode.browser => Icons.language,
      StudioDrawerMode.code => Icons.code,
      StudioDrawerMode.diff => Icons.difference_outlined,
      StudioDrawerMode.files => Icons.folder_outlined,
      StudioDrawerMode.terminal => Icons.terminal_outlined,
      StudioDrawerMode.sources => Icons.travel_explore,
      StudioDrawerMode.context => Icons.inventory_2_outlined,
    };
  }

  String _label(StudioDrawerMode mode) {
    return switch (mode) {
      StudioDrawerMode.progress => 'Progress',
      StudioDrawerMode.browser => 'Browser preview',
      StudioDrawerMode.code => 'Code',
      StudioDrawerMode.diff => 'Diff',
      StudioDrawerMode.files => 'Files',
      StudioDrawerMode.terminal => 'Terminal output',
      StudioDrawerMode.sources => 'Sources',
      StudioDrawerMode.context => 'Context details',
    };
  }
}

class _DrawerBody extends ConsumerWidget {
  final AgentTask? task;

  const _DrawerBody({this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(studioRightDrawerProvider).mode;
    return switch (mode) {
      StudioDrawerMode.progress => _ProgressDrawer(task: task),
      StudioDrawerMode.browser => const _BrowserDrawer(),
      StudioDrawerMode.code => const _CodeDrawer(),
      StudioDrawerMode.diff => const _DiffDrawer(),
      StudioDrawerMode.files => const _FilesDrawer(),
      StudioDrawerMode.terminal => const _TerminalDrawer(),
      StudioDrawerMode.sources => _SourcesDrawer(task: task),
      StudioDrawerMode.context => _ContextDrawer(task: task),
    };
  }
}

class _ProgressDrawer extends ConsumerWidget {
  final AgentTask? task;

  const _ProgressDrawer({this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final threadState = ref.watch(studioThreadProvider);
    final thread = threadState.threadForTaskView(task?.id);
    final latestTurn = _latestTurn(thread);
    final latestEvent = _latestEvent(latestTurn);
    final latestDiagnostic = _latestDiagnostic(latestTurn);
    final outcomeRepairCount = _diagnosticCount(
      latestTurn,
      ProviderLifecycleEventKind.outcomeRepair,
    );
    final hasPendingApproval = _hasPendingApproval(latestTurn);
    final git = ref.watch(gitProvider).status;
    final patch = ref.watch(patchProposalProvider).active;
    final commands = ref.watch(commandRunProvider).values.toList();
    final runningCommand = commands
        .where((command) => command.status == CommandRunStatus.running)
        .firstOrNull;
    final displayState = TaskDisplayState.fromLifecycle(
      StudioTaskLifecycleState.fromThread(thread),
    );
    final rows = <StudioProgressRow>[
      StudioProgressRow(
        label: 'Task',
        value: displayState.label,
        accent: displayState.isActive || displayState.needsAttention,
      ),
      if (hasPendingApproval)
        const StudioProgressRow(
          label: 'Approval',
          value: 'Required',
          accent: true,
        ),
      if (runningCommand != null)
        StudioProgressRow(
          label: 'Command',
          value: '${runningCommand.elapsed.inSeconds}s',
          accent: true,
        ),
      if (outcomeRepairCount > 0)
        StudioProgressRow(
          label: 'Repair',
          value: outcomeRepairCount == 1
              ? '1 model retry'
              : '$outcomeRepairCount model retries',
          accent: true,
        ),
      StudioProgressRow(
        label: 'Changes',
        value: patch == null ? 'No pending changes' : '+${patch.fileCount}',
        accent: patch != null,
      ),
      const StudioProgressRow(label: 'Local', value: 'Ready'),
      StudioProgressRow(
        label: 'Branch',
        value: git.branch.isEmpty ? 'main' : git.branch,
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      children: [
        Text(
          'Environment',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Spacing.md),
        for (final row in rows) _ProgressRow(row: row),
        const SizedBox(height: Spacing.xl),
        Divider(color: tokens.studioDivider.withValues(alpha: 0.52), height: 1),
        const SizedBox(height: Spacing.xl),
        Text(
          'Latest event',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Spacing.md),
        _MiniEvent(
          icon: Icons.history,
          title:
              _diagnosticTitle(latestDiagnostic) ??
              latestEvent?.title ??
              displayState.label,
          detail:
              latestDiagnostic?.detail ??
              _diagnosticDetail(latestDiagnostic) ??
              latestEvent?.detail ??
              thread?.contextSummary?.detail ??
              'Studio is ready.',
        ),
      ],
    );
  }

  StudioTurn? _latestTurn(StudioThread? thread) {
    if (thread == null || thread.turns.isEmpty) return null;
    final turns = thread.turns.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return turns.first;
  }

  StudioTurnEvent? _latestEvent(StudioTurn? turn) {
    if (turn == null || turn.events.isEmpty) return null;
    final events = turn.events.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return events.first;
  }

  ProviderLifecycleEvent? _latestDiagnostic(StudioTurn? turn) {
    if (turn == null || turn.providerDiagnostics.isEmpty) return null;
    final diagnostics = turn.providerDiagnostics.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (turn.status == StudioTurnStatus.failed ||
        turn.status == StudioTurnStatus.cancelled) {
      return diagnostics.where(_isRootCauseDiagnostic).firstOrNull ??
          diagnostics.first;
    }
    return diagnostics.first;
  }

  bool _isRootCauseDiagnostic(ProviderLifecycleEvent diagnostic) {
    return switch (diagnostic.kind) {
      ProviderLifecycleEventKind.authFailed ||
      ProviderLifecycleEventKind.noFirstByte ||
      ProviderLifecycleEventKind.noTextOrTool ||
      ProviderLifecycleEventKind.unavailableTool ||
      ProviderLifecycleEventKind.rateLimited ||
      ProviderLifecycleEventKind.malformedChunk ||
      ProviderLifecycleEventKind.malformedBytes ||
      ProviderLifecycleEventKind.streamEndedWithoutDone ||
      ProviderLifecycleEventKind.timeout ||
      ProviderLifecycleEventKind.cancelled => true,
      _ => false,
    };
  }

  int _diagnosticCount(StudioTurn? turn, ProviderLifecycleEventKind kind) {
    if (turn == null) return 0;
    return turn.providerDiagnostics
        .where((diagnostic) => diagnostic.kind == kind)
        .length;
  }

  String? _diagnosticTitle(ProviderLifecycleEvent? diagnostic) {
    if (diagnostic == null) return null;
    return switch (diagnostic.kind) {
      ProviderLifecycleEventKind.requestSent => 'Request sent',
      ProviderLifecycleEventKind.toolExposure => 'Tools exposed',
      ProviderLifecycleEventKind.authFailed => 'Authentication failed',
      ProviderLifecycleEventKind.connected => 'Provider connected',
      ProviderLifecycleEventKind.firstByte => 'Response started',
      ProviderLifecycleEventKind.noFirstByte => 'No provider response bytes',
      ProviderLifecycleEventKind.firstTextDelta => 'Writing response',
      ProviderLifecycleEventKind.firstToolDelta => 'Tool call started',
      ProviderLifecycleEventKind.nonSseJson => 'Non-streaming response',
      ProviderLifecycleEventKind.jsonFallback => 'JSON fallback',
      ProviderLifecycleEventKind.toolOnly => 'Tool-only response',
      ProviderLifecycleEventKind.noTextOrTool => 'No model output',
      ProviderLifecycleEventKind.unavailableTool => 'Unavailable tool',
      ProviderLifecycleEventKind.rateLimited => 'Rate limited',
      ProviderLifecycleEventKind.malformedChunk => 'Malformed stream chunk',
      ProviderLifecycleEventKind.malformedBytes => 'Malformed response bytes',
      ProviderLifecycleEventKind.streamEndedWithoutDone => 'Stream ended early',
      ProviderLifecycleEventKind.outcomeRepair => 'Repairing response',
      ProviderLifecycleEventKind.completed => 'Provider completed',
      ProviderLifecycleEventKind.failed => 'Provider failed',
      ProviderLifecycleEventKind.cancelled => 'Provider cancelled',
      ProviderLifecycleEventKind.timeout => 'Provider timed out',
    };
  }

  String? _diagnosticDetail(ProviderLifecycleEvent? diagnostic) {
    if (diagnostic == null) return null;
    return switch (diagnostic.kind) {
      ProviderLifecycleEventKind.outcomeRepair =>
        'Circuit rejected a vague draft and requested one structured repair.',
      ProviderLifecycleEventKind.toolOnly =>
        'Circuit returned tool calls without assistant text.',
      ProviderLifecycleEventKind.noTextOrTool =>
        'Circuit returned neither assistant text nor tool calls.',
      ProviderLifecycleEventKind.noFirstByte =>
        'Circuit did not return response bytes before the request ended.',
      ProviderLifecycleEventKind.nonSseJson ||
      ProviderLifecycleEventKind.jsonFallback =>
        'Circuit returned a non-streaming JSON response.',
      ProviderLifecycleEventKind.malformedChunk =>
        'Circuit returned a malformed stream chunk.',
      ProviderLifecycleEventKind.malformedBytes =>
        'Circuit returned response bytes that were not valid UTF-8.',
      ProviderLifecycleEventKind.streamEndedWithoutDone =>
        'Circuit closed the SSE stream without the normal completion marker.',
      ProviderLifecycleEventKind.unavailableTool =>
        'Circuit requested a tool that is hidden for this mode or phase.',
      ProviderLifecycleEventKind.rateLimited =>
        'Circuit API is rate limited. Wait for the retry window or try again later.',
      ProviderLifecycleEventKind.authFailed =>
        'Circuit credentials or token refresh failed.',
      ProviderLifecycleEventKind.timeout =>
        'Circuit did not finish before the timeout.',
      ProviderLifecycleEventKind.cancelled => 'The request was cancelled.',
      ProviderLifecycleEventKind.failed => 'The provider reported a failure.',
      _ => null,
    };
  }

  bool _hasPendingApproval(StudioTurn? turn) {
    return turn?.events.any(
          (event) =>
              event.type == StudioTurnEventType.approvalRequest &&
              event.approvalState == ApprovalRequestState.pending,
        ) ??
        false;
  }
}

class _BrowserDrawer extends ConsumerStatefulWidget {
  const _BrowserDrawer();

  @override
  ConsumerState<_BrowserDrawer> createState() => _BrowserDrawerState();
}

class _BrowserDrawerState extends ConsumerState<_BrowserDrawer> {
  WebViewController? _controller;
  String? _loadedUrl;
  int _loadedReloadNonce = 0;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final drawer = ref.watch(studioRightDrawerProvider);
    final session = ref.watch(studioBrowserProvider);
    final selected = _selectedArtifact(ref);
    final url = drawer.localUrl ?? selected?.localUrl ?? session.currentUrl;
    if (url != null && session.currentUrl != url) {
      ref.read(studioBrowserProvider.notifier).open(url);
    }
    final activeUrl = session.currentUrl ?? url;
    if (activeUrl != null &&
        (activeUrl != _loadedUrl ||
            session.reloadNonce != _loadedReloadNonce)) {
      _load(activeUrl, session.reloadNonce);
    }

    if (activeUrl == null) {
      return const _EmptyDrawerState(
        icon: Icons.language,
        title: 'No local preview yet',
        detail: 'Enter a URL or open a localhost source from the task.',
      );
    }

    return Column(
      children: [
        _BrowserToolbar(
          session: session,
          onBack: () {
            ref.read(studioBrowserProvider.notifier).goBack();
          },
          onForward: () {
            ref.read(studioBrowserProvider.notifier).goForward();
          },
          onNavigate: (value) {
            ref.read(studioBrowserProvider.notifier).open(value);
          },
          onReload: () {
            ref.read(studioBrowserProvider.notifier).reload();
          },
          onCopy: () => Clipboard.setData(ClipboardData(text: activeUrl)),
          onOpenExternal: () => launchUrl(Uri.parse(activeUrl)),
          onAllow: () => ref.read(studioBrowserProvider.notifier).allowSite(),
          onBlock: () => ref.read(studioBrowserProvider.notifier).blockSite(),
          onComment: () => _showCommentDialog(activeUrl),
        ),
        if (session.error != null)
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Text(
              session.error!,
              style: TextStyle(color: tokens.error, fontSize: FontSizes.sm),
            ),
          ),
        if (session.permission == BrowserSitePermission.blocked)
          const Expanded(
            child: _EmptyDrawerState(
              icon: Icons.block,
              title: 'Site blocked',
              detail: 'Allow this site from the browser toolbar to load it.',
            ),
          )
        else
          Expanded(
            child: _controller == null
                ? const Center(child: CircularProgressIndicator())
                : WebViewWidget(controller: _controller!),
          ),
      ],
    );
  }

  StudioSourceArtifact? _selectedArtifact(WidgetRef ref) {
    final drawer = ref.watch(studioRightDrawerProvider);
    final artifacts = ref.watch(studioSourceArtifactProvider).artifacts;
    return artifacts
        .where((artifact) => artifact.id == drawer.selectedArtifactId)
        .firstOrNull;
  }

  void _load(String url, int reloadNonce) {
    _loadedUrl = url;
    _loadedReloadNonce = reloadNonce;
    ref.read(studioBrowserProvider.notifier).setError(null);
    ref.read(studioBrowserProvider.notifier).setProgress(0);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            ref.read(studioBrowserProvider.notifier).setProgress(progress);
          },
          onWebResourceError: (error) {
            ref
                .read(studioBrowserProvider.notifier)
                .setError(error.description);
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
    setState(() {});
  }

  Future<void> _showCommentDialog(String url) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) {
        final tokens = ref.read(themeProvider);
        return AlertDialog(
          backgroundColor: tokens.studioPanel,
          title: const Text('Comment on preview'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: 'Describe what Circuit should notice or change...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Add comment'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (note == null || note.trim().isEmpty) return;
    ref.read(studioBrowserProvider.notifier).addAnnotation(note);
  }
}

class _BrowserToolbar extends ConsumerWidget {
  final StudioBrowserSession session;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final ValueChanged<String> onNavigate;
  final VoidCallback onReload;
  final VoidCallback onCopy;
  final VoidCallback onOpenExternal;
  final VoidCallback onAllow;
  final VoidCallback onBlock;
  final VoidCallback onComment;

  const _BrowserToolbar({
    required this.session,
    required this.onBack,
    required this.onForward,
    required this.onNavigate,
    required this.onReload,
    required this.onCopy,
    required this.onOpenExternal,
    required this.onAllow,
    required this.onBlock,
    required this.onComment,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final url = session.currentUrl ?? session.addressDraft;
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.studioDivider)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: session.canGoBack ? onBack : null,
                icon: const Icon(Icons.chevron_left, size: 16),
              ),
              IconButton(
                tooltip: 'Forward',
                onPressed: session.canGoForward ? onForward : null,
                icon: const Icon(Icons.chevron_right, size: 16),
              ),
              Expanded(
                child: TextFormField(
                  initialValue: url,
                  onFieldSubmitted: onNavigate,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: Spacing.md,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      borderSide: BorderSide(color: tokens.studioDivider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      borderSide: BorderSide(color: tokens.studioDivider),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Reload',
                onPressed: onReload,
                icon: const Icon(Icons.refresh, size: 16),
              ),
              IconButton(
                tooltip: 'Copy URL',
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 16),
              ),
              IconButton(
                tooltip: 'Open external',
                onPressed: onOpenExternal,
                icon: const Icon(Icons.open_in_new, size: 16),
              ),
              PopupMenuButton<BrowserSitePermission>(
                tooltip: 'Site permission',
                color: tokens.studioPanel,
                onSelected: (value) {
                  if (value == BrowserSitePermission.allowed) onAllow();
                  if (value == BrowserSitePermission.blocked) onBlock();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: BrowserSitePermission.allowed,
                    child: Text('Allow site'),
                  ),
                  PopupMenuItem(
                    value: BrowserSitePermission.blocked,
                    child: Text('Block site'),
                  ),
                ],
                child: Icon(
                  session.permission == BrowserSitePermission.blocked
                      ? Icons.block
                      : Icons.security_outlined,
                  size: 16,
                  color: tokens.textMuted,
                ),
              ),
              IconButton(
                tooltip: 'Add browser comment',
                onPressed: onComment,
                icon: const Icon(Icons.add_comment_outlined, size: 16),
              ),
            ],
          ),
          if (session.loadingProgress > 0 && session.loadingProgress < 100)
            LinearProgressIndicator(value: session.loadingProgress / 100),
          if (session.annotations.isNotEmpty) ...[
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${session.annotations.length} preview comments attached',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CodeDrawer extends ConsumerWidget {
  const _CodeDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drawer = ref.watch(studioRightDrawerProvider);
    final selected = _selectedArtifact(ref);
    final rootPath = ref.watch(fileTreeProvider).rootPath;
    final path = drawer.filePath ?? selected?.filePath;
    if (path == null) {
      return const _EmptyDrawerState(
        icon: Icons.code,
        title: 'No file selected',
        detail: 'Open a file or source row to inspect code here.',
      );
    }
    final resolved = _resolvePath(rootPath, path);
    final editor = ref.watch(studioCodeEditProvider);
    if (editor.filePath != path && !editor.isLoading) {
      Future.microtask(
        () => ref.read(studioCodeEditProvider.notifier).open(path),
      );
    }
    if (editor.isLoading || editor.filePath != path) {
      return const Center(child: CircularProgressIndicator());
    }
    if (editor.error != null) {
      return _EmptyDrawerState(
        icon: Icons.error_outline,
        title: 'Could not open file',
        detail: editor.error!,
      );
    }
    return _CodePreviewView(title: path, resolvedPath: resolved, state: editor);
  }

  StudioSourceArtifact? _selectedArtifact(WidgetRef ref) {
    final drawer = ref.watch(studioRightDrawerProvider);
    final artifacts = ref.watch(studioSourceArtifactProvider).artifacts;
    return artifacts
        .where((artifact) => artifact.id == drawer.selectedArtifactId)
        .firstOrNull;
  }
}

class _CodePreviewView extends ConsumerWidget {
  final String title;
  final String resolvedPath;
  final StudioCodeEditState state;

  const _CodePreviewView({
    required this.title,
    required this.resolvedPath,
    required this.state,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
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
                    child: Tooltip(
                      message: resolvedPath,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: FontSizes.xs,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.studioControl.withValues(alpha: 0.44),
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Text(
                      'Read only',
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: FontSizes.xs,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.xs),
                  IconButton(
                    tooltip: 'Copy',
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: state.draft)),
                    icon: const Icon(Icons.copy, size: 15),
                  ),
                ],
              ),
            ),
            Divider(
              color: tokens.studioDivider.withValues(alpha: 0.72),
              height: 1,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  Spacing.sm,
                  Spacing.md,
                  Spacing.lg,
                ),
                child: SelectableText(
                  state.draft.isEmpty ? '(empty)' : state.draft,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    height: 1.42,
                    fontFamily: EditorDefaults.fallbackFontFamily,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiffDrawer extends ConsumerStatefulWidget {
  const _DiffDrawer();

  @override
  ConsumerState<_DiffDrawer> createState() => _DiffDrawerState();
}

class _DiffDrawerState extends ConsumerState<_DiffDrawer> {
  String? _selectedPath;
  bool _selectedStaged = false;

  @override
  Widget build(BuildContext context) {
    final drawer = ref.watch(studioRightDrawerProvider);
    final patch = ref.watch(patchProposalProvider).active;
    if (patch == null) {
      return _GitReviewDrawer(
        selectedPath: _selectedPath,
        selectedStaged: _selectedStaged,
        onSelect: (path, staged) {
          setState(() {
            _selectedPath = path;
            _selectedStaged = staged;
          });
        },
      );
    }
    final selectedPath = drawer.patchFilePath;
    return _TextDocumentView(
      title: selectedPath ?? patch.title,
      text: _diffPreview(patch, selectedPath),
    );
  }

  String _diffPreview(ProposedPatchSet patch, String? selectedPath) {
    final edits = selectedPath == null
        ? patch.edits
        : patch.edits.where((edit) => edit.path == selectedPath).toList();
    if (edits.isEmpty) {
      if (patch.isPlanOnly) {
        return patch.planMarkdown ??
            patch.comparisonSummary ??
            'This plan does not include a file diff yet.';
      }
      return selectedPath == null
          ? 'No diff available yet.'
          : 'No diff available for $selectedPath.';
    }
    return edits
        .map((edit) {
          return [
            '--- ${edit.path}',
            '+++ ${edit.path}',
            if (edit.unifiedDiff?.isNotEmpty == true)
              edit.unifiedDiff!
            else ...[
              if ((edit.before ?? '').trim().isNotEmpty)
                '- ${(edit.before ?? '').trim()}',
              if ((edit.after ?? '').trim().isNotEmpty)
                '+ ${(edit.after ?? '').trim()}',
            ],
          ].join('\n');
        })
        .join('\n\n');
  }
}

class _GitReviewDrawer extends ConsumerWidget {
  final String? selectedPath;
  final bool selectedStaged;
  final void Function(String path, bool staged) onSelect;

  const _GitReviewDrawer({
    required this.selectedPath,
    required this.selectedStaged,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final git = ref.watch(gitProvider).status;
    final changes = <_ReviewChange>[
      for (final change in git.staged)
        _ReviewChange(change: change, staged: true),
      for (final change in git.unstaged)
        _ReviewChange(change: change, staged: false),
      for (final change in git.untracked)
        _ReviewChange(change: change, staged: false),
    ];
    if (changes.isEmpty) {
      return const _EmptyDrawerState(
        icon: Icons.difference_outlined,
        title: 'No changes',
        detail: 'Repo changes and AI patch reviews appear here.',
      );
    }
    final selected =
        changes
            .where((change) => change.change.path == selectedPath)
            .firstOrNull ??
        changes.first;
    final staged = selectedPath == null ? selected.staged : selectedStaged;
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Repository changes',
                style: TextStyle(
                  color: ref.watch(themeProvider).textSecondary,
                  fontSize: FontSizes.sm,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => ref.read(gitProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        for (final change in changes)
          _GitChangeRow(
            change: change,
            selected: change.change.path == selected.change.path,
            onTap: () => onSelect(change.change.path, change.staged),
          ),
        const SizedBox(height: Spacing.lg),
        _GitReviewNotice(path: selected.change.path),
        const SizedBox(height: Spacing.md),
        FutureBuilder<String>(
          future: ref
              .read(gitProvider.notifier)
              .getDiff(path: selected.change.path, staged: staged),
          builder: (context, snapshot) {
            return _TextDocumentView(
              title: selected.change.path,
              text: snapshot.data ?? 'Loading diff...',
              embedded: true,
            );
          },
        ),
      ],
    );
  }
}

class _ReviewChange {
  final GitFileChange change;
  final bool staged;

  const _ReviewChange({required this.change, required this.staged});
}

class _GitChangeRow extends ConsumerWidget {
  final _ReviewChange change;
  final bool selected;
  final VoidCallback onTap;

  const _GitChangeRow({
    required this.change,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SourceListRow(
      icon: change.staged ? Icons.check_box : Icons.check_box_outline_blank,
      title: change.change.path,
      subtitle:
          '${change.change.type.label}${change.staged ? ' · staged' : ''}',
      selected: selected,
      onTap: onTap,
    );
  }
}

class _GitReviewNotice extends ConsumerWidget {
  final String path;

  const _GitReviewNotice({required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: tokens.studioHover.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.studioDivider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: Spacing.md),
          Flexible(
            child: Text(
              'Review only',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilesDrawer extends ConsumerWidget {
  const _FilesDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fileTree = ref.watch(fileTreeProvider);
    if (fileTree.rootPath == null) {
      return const _EmptyDrawerState(
        icon: Icons.folder_outlined,
        title: 'No project selected',
        detail: 'Choose a project to see files here.',
      );
    }
    final nodes = fileTree.nodes.take(80).toList();
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        for (final node in nodes)
          _SourceListRow(
            icon: node.isDirectory
                ? Icons.folder_outlined
                : Icons.description_outlined,
            title: node.name,
            subtitle: node.path,
            onTap: node.isDirectory
                ? null
                : () => ref
                      .read(studioRightDrawerProvider.notifier)
                      .openFile(node.path),
          ),
      ],
    );
  }
}

class _TerminalDrawer extends ConsumerWidget {
  const _TerminalDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drawer = ref.watch(studioRightDrawerProvider);
    final tokens = ref.watch(themeProvider);
    final commands = ref.watch(commandRunProvider).values.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final selected = commands
        .where((command) => command.id == drawer.commandRunId)
        .firstOrNull;
    final command = selected ?? commands.firstOrNull;
    if (commands.isEmpty) {
      return const _EmptyDrawerState(
        icon: Icons.terminal_outlined,
        title: 'No command logs',
        detail:
            'Approved verification commands and tool-run output will appear here. Studio does not expose an interactive terminal in the core agent loop.',
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
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        for (final candidate in commands.take(12))
          _SourceListRow(
            icon: Icons.terminal_outlined,
            title: candidate.command,
            subtitle: candidate.status.name,
            selected: candidate.id == command?.id,
            onTap: () => ref
                .read(studioRightDrawerProvider.notifier)
                .openCommand(candidate.id),
          ),
        if (command != null) ...[
          const SizedBox(height: Spacing.md),
          _TextDocumentView(
            title: command.command,
            text: command.combinedOutput.isEmpty
                ? 'No output captured yet.'
                : command.combinedOutput,
            embedded: true,
          ),
        ],
      ],
    );
  }
}

class _SourcesDrawer extends ConsumerWidget {
  final AgentTask? task;

  const _SourcesDrawer({this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thread = ref.watch(studioThreadProvider).threadForTaskView(task?.id);
    final artifacts = ref
        .watch(studioSourceArtifactProvider)
        .forThread(thread?.id);
    if (artifacts.isEmpty) {
      return const _EmptyDrawerState(
        icon: Icons.travel_explore,
        title: 'No sources yet',
        detail:
            'Context, local previews, files, diffs, and commands appear here.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        for (final artifact in artifacts)
          _SourceListRow(
            icon: _sourceIcon(artifact.kind),
            title: artifact.title,
            subtitle: artifact.subtitle,
            onTap: () => ref
                .read(studioRightDrawerProvider.notifier)
                .openArtifact(artifact),
          ),
      ],
    );
  }

  IconData _sourceIcon(StudioSourceArtifactKind kind) {
    return switch (kind) {
      StudioSourceArtifactKind.localUrl ||
      StudioSourceArtifactKind.webSource ||
      StudioSourceArtifactKind.browserComment => Icons.language,
      StudioSourceArtifactKind.file => Icons.description_outlined,
      StudioSourceArtifactKind.diff ||
      StudioSourceArtifactKind.gitChange ||
      StudioSourceArtifactKind.gitHunk ||
      StudioSourceArtifactKind.reviewComment ||
      StudioSourceArtifactKind.patch => Icons.difference_outlined,
      StudioSourceArtifactKind.command ||
      StudioSourceArtifactKind.terminalLog ||
      StudioSourceArtifactKind.terminalSession => Icons.terminal_outlined,
      StudioSourceArtifactKind.topology => Icons.account_tree_outlined,
      StudioSourceArtifactKind.sizing => Icons.straighten_outlined,
      StudioSourceArtifactKind.lifecycle => Icons.event_available_outlined,
      StudioSourceArtifactKind.chart => Icons.insert_chart_outlined,
      StudioSourceArtifactKind.businessUseCase => Icons.query_stats_outlined,
      StudioSourceArtifactKind.evidence => Icons.verified_outlined,
      StudioSourceArtifactKind.toolResult => Icons.dataset_linked_outlined,
    };
  }
}

class _ContextDrawer extends ConsumerWidget {
  final AgentTask? task;

  const _ContextDrawer({this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final thread = ref.watch(studioThreadProvider).threadForTaskView(task?.id);
    final pack = task == null || thread != null
        ? ref.watch(contextPackProvider)
        : null;
    final persistedRetrieval = thread?.latestContextRetrieval;
    final retrieval = pack?.retrievalResult ?? persistedRetrieval;
    final canPersistContextPreference =
        ref.watch(fileTreeProvider).rootPath != null;
    if (pack == null && retrieval == null) {
      return const _EmptyDrawerState(
        icon: Icons.inventory_2_outlined,
        title: 'No context yet',
        detail:
            'Context details appear here after Circuit builds a task context.',
      );
    }

    final removedIds = pack?.removedItemIds.toSet() ?? const <String>{};
    final included =
        retrieval?.includedCandidates
            .where((candidate) => !removedIds.contains(candidate.id))
            .toList() ??
        const [];
    final omitted = retrieval?.omittedCandidates ?? const [];
    final visibleIds =
        pack?.visibleItems.map((item) => item.id).toSet() ?? const <String>{};
    final visibleItems = pack?.visibleItems ?? const <ContextPackItem>[];

    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        Text(
          'Context budget',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        if (pack != null)
          _ContextBudgetCard(pack: pack)
        else
          _ContextBudgetSnapshot(retrieval: retrieval!),
        if (retrieval?.warnings.isNotEmpty == true) ...[
          const SizedBox(height: Spacing.md),
          for (final warning in retrieval!.warnings)
            _ContextWarning(message: warning.message),
        ],
        const SizedBox(height: Spacing.lg),
        _ContextSectionTitle(
          title: 'Included',
          count: included.isEmpty ? visibleItems.length : included.length,
        ),
        const SizedBox(height: Spacing.sm),
        if (included.isEmpty)
          for (final item in visibleItems)
            _ContextItemRow(
              title: item.title,
              subtitle: _contextSubtitle(
                path: item.source,
                reason: item.sourceKind.name,
                tokens: item.estimatedTokens,
              ),
              score: null,
              removable: item.removable,
              onRemove: item.removable && pack != null
                  ? () => ref
                        .read(contextPackProvider.notifier)
                        .removeItem(item.id)
                  : null,
            )
        else
          for (final candidate in included)
            _ContextItemRow(
              title: candidate.title,
              subtitle: _contextSubtitle(
                path: candidate.path,
                reason: candidate.reason,
                tokens: candidate.estimatedTokens,
              ),
              score: candidate.score,
              removable: visibleIds.contains(candidate.id),
              onRemove: visibleIds.contains(candidate.id)
                  ? () => ref
                        .read(contextPackProvider.notifier)
                        .removeItem(candidate.id)
                  : null,
            ),
        if (omitted.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          _ContextSectionTitle(title: 'Omitted', count: omitted.length),
          const SizedBox(height: Spacing.sm),
          for (final candidate in omitted.take(20))
            _ContextItemRow(
              title: candidate.title,
              subtitle: _contextSubtitle(
                path: candidate.path,
                reason: candidate.reason,
                tokens: candidate.estimatedTokens,
              ),
              score: candidate.score,
              removable: false,
              muted: true,
              actionLabel: candidate.path != null && canPersistContextPreference
                  ? 'Include next'
                  : null,
              onAction: candidate.path != null && canPersistContextPreference
                  ? () => ref
                        .read(contextPackProvider.notifier)
                        .includeNextTime(candidate.path!)
                  : null,
            ),
        ],
      ],
    );
  }

  String _contextSubtitle({
    required String? path,
    required String reason,
    required int tokens,
  }) {
    return [
      if (path != null && path.trim().isNotEmpty) path,
      reason,
      '~$tokens tokens',
    ].join(' · ');
  }
}

class _ContextBudgetCard extends ConsumerWidget {
  final ContextPack pack;

  const _ContextBudgetCard({required this.pack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final budget = pack.retrievalResult?.budget;
    final used = pack.estimatedTokens;
    final available = budget?.availableForContext;
    final label = available == null
        ? '~$used tokens'
        : '~$used / ~$available context tokens';
    final percent = available == null || available == 0
        ? 0.0
        : (used / available).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: tokens.studioPanel.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.studioDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.sm,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: percent,
              backgroundColor: tokens.surfaceInset,
              color: percent > 0.92 ? tokens.warning : tokens.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextBudgetSnapshot extends ConsumerWidget {
  final ContextRetrievalResult retrieval;

  const _ContextBudgetSnapshot({required this.retrieval});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final budget = retrieval.budget;
    final label =
        '~${budget.usedTokens} / ~${budget.availableForContext} context tokens';
    final percent = budget.availableForContext == 0
        ? 0.0
        : (budget.usedTokens / budget.availableForContext).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: tokens.studioPanel.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.studioDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label · saved with turn',
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.sm,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: percent,
              backgroundColor: tokens.surfaceInset,
              color: percent > 0.92 ? tokens.warning : tokens.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextSectionTitle extends ConsumerWidget {
  final String title;
  final int count;

  const _ContextSectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          '$count',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ContextWarning extends ConsumerWidget {
  final String message;

  const _ContextWarning({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: tokens.warning),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: tokens.warning, fontSize: FontSizes.xs),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextItemRow extends ConsumerWidget {
  final String title;
  final String subtitle;
  final int? score;
  final bool removable;
  final bool muted;
  final VoidCallback? onRemove;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _ContextItemRow({
    required this.title,
    required this.subtitle,
    required this.score,
    required this.removable,
    this.muted = false,
    this.onRemove,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final color = muted ? tokens.textMuted : tokens.textSecondary;
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: tokens.studioHover.withValues(alpha: muted ? 0.22 : 0.42),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.72)),
      ),
      child: Row(
        children: [
          Icon(
            muted ? Icons.remove_circle_outline : Icons.check_circle_outline,
            color: muted ? tokens.textMuted : tokens.success,
            size: 14,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          if (score != null)
            Padding(
              padding: const EdgeInsets.only(left: Spacing.sm),
              child: Text(
                '$score',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (removable)
            IconButton(
              tooltip: 'Remove from next send',
              onPressed: onRemove,
              icon: Icon(Icons.close, color: tokens.textMuted, size: 14),
              visualDensity: VisualDensity.compact,
            ),
          if (actionLabel != null && onAction != null)
            Padding(
              padding: const EdgeInsets.only(left: Spacing.sm),
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: tokens.textSecondary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: 0,
                  ),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(actionLabel!),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProgressRow extends ConsumerWidget {
  final StudioProgressRow row;

  const _ProgressRow({required this.row});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final color = row.enabled ? tokens.textSecondary : tokens.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(_iconFor(row.label), color: color, size: 12),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              row.label,
              style: TextStyle(
                color: color,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            row.value,
            style: TextStyle(
              color: row.accent ? tokens.success : tokens.textMuted,
              fontSize: FontSizes.xs,
              fontWeight: row.accent ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String label) {
    return switch (label) {
      'Task' => Icons.radio_button_checked,
      'Approval' => Icons.shield_outlined,
      'Command' => Icons.terminal_outlined,
      'Changes' => Icons.inventory_2_outlined,
      'Local' => Icons.computer_outlined,
      'Branch' => Icons.account_tree_outlined,
      _ => Icons.data_object_outlined,
    };
  }
}

class _MiniEvent extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _MiniEvent({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: tokens.studioActivityRow.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tokens.textMuted, size: 14),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
                if (detail.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceListRow extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool selected;

  const _SourceListRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: InkWell(
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
                child: Icon(icon, color: tokens.textMuted, size: 13),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
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
                      subtitle,
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

class _TextDocumentView extends ConsumerWidget {
  final String title;
  final String text;
  final bool embedded;

  const _TextDocumentView({
    required this.title,
    required this.text,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final view = Container(
      decoration: BoxDecoration(
        color: tokens.surfaceInset.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.68)),
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
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: tokens.bgDark.withValues(alpha: 0.48),
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Icon(
                    Icons.difference_outlined,
                    color: tokens.textMuted,
                    size: 13,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: FontSizes.xs,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.studioControl.withValues(alpha: 0.44),
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Text(
                    'Read only',
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.xs),
                IconButton(
                  tooltip: 'Copy',
                  onPressed: () => Clipboard.setData(ClipboardData(text: text)),
                  icon: const Icon(Icons.copy, size: 15),
                ),
              ],
            ),
          ),
          Divider(
            color: tokens.studioDivider.withValues(alpha: 0.72),
            height: 1,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.md,
                Spacing.md,
                Spacing.lg,
              ),
              child: SelectableText(
                text.isEmpty ? '(empty)' : text,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.xs,
                  height: 1.42,
                  fontFamily: EditorDefaults.fallbackFontFamily,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (embedded) return SizedBox(height: 280, child: view);
    return Padding(padding: const EdgeInsets.all(Spacing.md), child: view);
  }
}

class _EmptyDrawerState extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _EmptyDrawerState({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                icon,
                color: tokens.textMuted.withValues(alpha: 0.72),
                size: 14,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: FontSizes.xs,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                      height: 1.28,
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

String _resolvePath(String? rootPath, String path) {
  if (p.isAbsolute(path)) return path;
  if (rootPath == null) return path;
  return p.normalize(p.join(rootPath, path));
}
