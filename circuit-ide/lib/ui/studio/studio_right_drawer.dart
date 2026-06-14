import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/agent_workspace.dart';
import '../../models/command_run.dart';
import '../../models/git_models.dart';
import '../../models/reviewed_edit.dart';
import '../../models/studio_browser.dart';
import '../../models/studio_right_drawer.dart';
import '../../models/studio_shell.dart';
import '../../models/studio_source_artifact.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_turn.dart';
import '../../models/studio_view_models.dart';
import '../../state/chat_provider.dart';
import '../../state/command_run_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/git_provider.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/studio_browser_provider.dart';
import '../../state/studio_code_edit_provider.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_source_artifact_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';
import '../terminal/terminal_panel.dart';
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
      margin: const EdgeInsets.fromLTRB(0, 52, Spacing.md, Spacing.md),
      decoration: BoxDecoration(
        color: tokens.studioDrawer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.78)),
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
        for (final mode in StudioDrawerMode.values)
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
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.md,
        Spacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _titleFor(drawer.mode),
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.lg,
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
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: tokens.studioDivider.withValues(alpha: 0.72),
          ),
          top: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.72)),
        ),
      ),
      child: Row(
        children: [
          for (final mode in StudioDrawerMode.values)
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
    final color = active ? tokens.textPrimary : tokens.textMuted;
    return Tooltip(
      message: _label(mode),
      child: InkWell(
        onTap: () =>
            ref.read(studioRightDrawerProvider.notifier).openMode(mode),
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Container(
          width: compact ? 40 : 34,
          height: 28,
          margin: EdgeInsets.only(right: compact ? 0 : Spacing.xs),
          decoration: BoxDecoration(
            color: active ? tokens.studioControl : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Icon(_icon(mode), color: color, size: 16),
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
      StudioDrawerMode.sources => const _SourcesDrawer(),
    };
  }
}

class _ProgressDrawer extends ConsumerWidget {
  final AgentTask? task;

  const _ProgressDrawer({this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final chat = ref.watch(chatProvider);
    final thread = ref.watch(studioThreadProvider).threadForTask(task?.id);
    final latestTurn = _latestTurn(thread);
    final latestEvent = _latestEvent(latestTurn);
    final hasPendingApproval = _hasPendingApproval(latestTurn);
    final git = ref.watch(gitProvider).status;
    final patch = ref.watch(patchProposalProvider).active;
    final commands = ref.watch(commandRunProvider).values.toList();
    final runningCommand = commands
        .where((command) => command.status == CommandRunStatus.running)
        .firstOrNull;
    final displayState = thread == null
        ? TaskDisplayState.derive(
            task: task,
            isChatProcessing: chat.isProcessing,
            isChatStreaming: chat.isStreaming,
            hasAssistantResponse: false,
            hasPendingApproval:
                chat.pendingConfirmation != null || hasPendingApproval,
            commands: commands,
            chatError: chat.error,
          )
        : TaskDisplayState.fromLifecycle(
            StudioTaskLifecycleState.fromThread(thread),
          );
    final rows = <StudioProgressRow>[
      StudioProgressRow(
        label: 'Task',
        value: displayState.label,
        accent: displayState.isActive || displayState.needsAttention,
      ),
      if (chat.pendingConfirmation != null || hasPendingApproval)
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
      padding: const EdgeInsets.all(Spacing.lg),
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
        const SizedBox(height: Spacing.lg),
        Divider(color: tokens.studioDivider, height: 1),
        const SizedBox(height: Spacing.lg),
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
          title: latestEvent?.title ?? displayState.label,
          detail:
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
    return _EditableCodeView(
      title: path,
      resolvedPath: resolved,
      state: editor,
    );
  }

  StudioSourceArtifact? _selectedArtifact(WidgetRef ref) {
    final drawer = ref.watch(studioRightDrawerProvider);
    final artifacts = ref.watch(studioSourceArtifactProvider).artifacts;
    return artifacts
        .where((artifact) => artifact.id == drawer.selectedArtifactId)
        .firstOrNull;
  }
}

class _EditableCodeView extends ConsumerWidget {
  final String title;
  final String resolvedPath;
  final StudioCodeEditState state;

  const _EditableCodeView({
    required this.title,
    required this.resolvedPath,
    required this.state,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.surfaceInset,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tokens.studioDivider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: resolvedPath,
                      child: Text(
                        state.isDirty ? '$title *' : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: FontSizes.xs,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  if (state.isEditing) ...[
                    TextButton(
                      onPressed: state.isSaving
                          ? null
                          : ref.read(studioCodeEditProvider.notifier).revert,
                      child: const Text('Revert'),
                    ),
                    FilledButton(
                      onPressed: state.isSaving || !state.isDirty
                          ? null
                          : () => ref
                                .read(studioCodeEditProvider.notifier)
                                .save(),
                      child: Text(state.isSaving ? 'Saving' : 'Save'),
                    ),
                  ] else
                    TextButton.icon(
                      onPressed: ref
                          .read(studioCodeEditProvider.notifier)
                          .startEditing,
                      icon: const Icon(Icons.edit_outlined, size: 14),
                      label: const Text('Edit'),
                    ),
                  IconButton(
                    tooltip: 'Copy',
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: state.draft)),
                    icon: const Icon(Icons.copy, size: 15),
                  ),
                ],
              ),
            ),
            Divider(color: tokens.studioDivider, height: 1),
            Expanded(
              child: state.isEditing
                  ? TextField(
                      controller: TextEditingController(text: state.draft)
                        ..selection = TextSelection.collapsed(
                          offset: state.draft.length,
                        ),
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      keyboardType: TextInputType.multiline,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: FontSizes.xs,
                        height: 1.42,
                        fontFamily: EditorDefaults.fallbackFontFamily,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(Spacing.md),
                      ),
                      onChanged: ref
                          .read(studioCodeEditProvider.notifier)
                          .updateDraft,
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(Spacing.md),
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
    return _TextDocumentView(title: patch.title, text: _diffPreview(patch));
  }

  String _diffPreview(ProposedPatchSet patch) {
    return patch.edits
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
        _GitFileActions(change: selected),
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

class _GitFileActions extends ConsumerWidget {
  final _ReviewChange change;

  const _GitFileActions({required this.change});

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
              change.change.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (change.staged)
            TextButton(
              onPressed: () => ref
                  .read(gitProvider.notifier)
                  .unstageFile(change.change.path),
              child: const Text('Unstage'),
            )
          else
            TextButton(
              onPressed: () =>
                  ref.read(gitProvider.notifier).stageFile(change.change.path),
              child: const Text('Stage'),
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
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: const TerminalPanel(),
          ),
        ),
        if (commands.isNotEmpty) ...[
          Divider(color: tokens.studioDivider, height: 1),
          SizedBox(
            height: 220,
            child: ListView(
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
                for (final candidate in commands.take(4))
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
                  const SizedBox(height: Spacing.sm),
                  _TextDocumentView(
                    title: command.command,
                    text: command.combinedOutput,
                    embedded: true,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SourcesDrawer extends ConsumerWidget {
  const _SourcesDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thread = ref.watch(studioThreadProvider).selectedThread;
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
          Icon(_iconFor(row.label), color: color, size: 14),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              row.label,
              style: TextStyle(
                color: color,
                fontSize: FontSizes.sm,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            row.value,
            style: TextStyle(
              color: row.accent ? tokens.success : tokens.textMuted,
              fontSize: FontSizes.sm,
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
    return _SourceListRow(icon: icon, title: title, subtitle: detail);
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
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? tokens.studioControl : tokens.studioActivityRow,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(
              color: tokens.studioDivider.withValues(alpha: 0.78),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: tokens.textMuted, size: 15),
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
                        fontSize: FontSizes.sm,
                        fontWeight: FontWeight.w600,
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
                        height: 1.3,
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
        color: tokens.surfaceInset,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.studioDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
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
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  onPressed: () => Clipboard.setData(ClipboardData(text: text)),
                  icon: const Icon(Icons.copy, size: 15),
                ),
              ],
            ),
          ),
          Divider(color: tokens.studioDivider, height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Spacing.md),
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
    return Padding(padding: const EdgeInsets.all(Spacing.lg), child: view);
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
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: tokens.textMuted, size: 28),
            const SizedBox(height: Spacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.base,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.sm,
                height: 1.35,
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
