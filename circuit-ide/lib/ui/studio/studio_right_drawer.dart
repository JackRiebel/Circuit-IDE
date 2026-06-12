import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/agent_workspace.dart';
import '../../models/command_run.dart';
import '../../models/reviewed_edit.dart';
import '../../models/studio_right_drawer.dart';
import '../../models/studio_shell.dart';
import '../../models/studio_source_artifact.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_view_models.dart';
import '../../state/chat_provider.dart';
import '../../state/command_run_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/git_provider.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_source_artifact_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';

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
      margin: const EdgeInsets.fromLTRB(0, 54, Spacing.lg, Spacing.lg),
      decoration: BoxDecoration(
        color: tokens.studioPanel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.studioDivider),
        boxShadow: Shadows.medium,
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
        Spacing.lg,
        Spacing.md,
        Spacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _titleFor(drawer.mode),
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.base,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: drawer.expanded ? 'Shrink panel' : 'Expand panel',
            onPressed: () =>
                ref.read(studioRightDrawerProvider.notifier).toggleExpanded(),
            icon: Icon(
              drawer.expanded
                  ? Icons.close_fullscreen
                  : Icons.open_in_full_outlined,
              color: tokens.textMuted,
              size: 16,
            ),
          ),
          IconButton(
            tooltip: 'Collapse panel',
            onPressed: () =>
                ref.read(studioRightDrawerProvider.notifier).toggleCollapsed(),
            icon: Icon(Icons.chevron_right, color: tokens.textMuted, size: 18),
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
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: tokens.studioDivider),
          top: BorderSide(color: tokens.studioDivider),
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
          width: compact ? 42 : 36,
          height: 30,
          margin: EdgeInsets.only(right: compact ? 0 : Spacing.xs),
          decoration: BoxDecoration(
            color: active ? tokens.studioHover : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.lg),
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
            hasPendingApproval: chat.pendingConfirmation != null,
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
      if (chat.pendingConfirmation != null)
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
          style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
        ),
        const SizedBox(height: Spacing.md),
        for (final row in rows) _ProgressRow(row: row),
        const SizedBox(height: Spacing.lg),
        Divider(color: tokens.studioDivider, height: 1),
        const SizedBox(height: Spacing.lg),
        Text(
          'Latest event',
          style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
        ),
        const SizedBox(height: Spacing.md),
        _MiniEvent(
          icon: Icons.history,
          title: displayState.label,
          detail: thread?.contextSummary?.detail ?? 'Studio is ready.',
        ),
      ],
    );
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
  int _progress = 0;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final drawer = ref.watch(studioRightDrawerProvider);
    final selected = _selectedArtifact(ref);
    final url = drawer.localUrl ?? selected?.localUrl;
    if (url != null && url != _loadedUrl) _load(url);

    if (url == null) {
      return const _EmptyDrawerState(
        icon: Icons.language,
        title: 'No local preview yet',
        detail:
            'When Circuit sees a localhost URL from a command or tool, it will appear here.',
      );
    }

    return Column(
      children: [
        _BrowserToolbar(
          url: url,
          progress: _progress,
          onReload: () => _controller?.reload(),
          onCopy: () => Clipboard.setData(ClipboardData(text: url)),
          onOpenExternal: () => launchUrl(Uri.parse(url)),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Text(
              _error!,
              style: TextStyle(color: tokens.error, fontSize: FontSizes.sm),
            ),
          ),
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

  void _load(String url) {
    _loadedUrl = url;
    _error = null;
    _progress = 0;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) => setState(() => _progress = progress),
          onWebResourceError: (error) {
            setState(() => _error = error.description);
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
  }
}

class _BrowserToolbar extends ConsumerWidget {
  final String url;
  final int progress;
  final VoidCallback onReload;
  final VoidCallback onCopy;
  final VoidCallback onOpenExternal;

  const _BrowserToolbar({
    required this.url,
    required this.progress,
    required this.onReload,
    required this.onCopy,
    required this.onOpenExternal,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.studioDivider)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
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
            ],
          ),
          if (progress > 0 && progress < 100)
            LinearProgressIndicator(value: progress / 100),
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
    return FutureBuilder<String>(
      future: File(resolved).readAsString(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _EmptyDrawerState(
            icon: Icons.error_outline,
            title: 'Could not open file',
            detail: snapshot.error.toString(),
          );
        }
        return _TextDocumentView(title: path, text: snapshot.data ?? '');
      },
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

class _DiffDrawer extends ConsumerWidget {
  const _DiffDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patch = ref.watch(patchProposalProvider).active;
    if (patch == null) {
      return const _EmptyDrawerState(
        icon: Icons.difference_outlined,
        title: 'No diff ready',
        detail: 'When Circuit proposes changes, the review diff appears here.',
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
    final commands = ref.watch(commandRunProvider).values.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final selected = commands
        .where((command) => command.id == drawer.commandRunId)
        .firstOrNull;
    if (commands.isEmpty) {
      return const _EmptyDrawerState(
        icon: Icons.terminal_outlined,
        title: 'No command output',
        detail: 'Approved command output will stream here.',
      );
    }
    final command = selected ?? commands.first;
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        for (final candidate in commands.take(6))
          _SourceListRow(
            icon: Icons.terminal_outlined,
            title: candidate.command,
            subtitle: candidate.status.name,
            selected: candidate.id == command.id,
            onTap: () => ref
                .read(studioRightDrawerProvider.notifier)
                .openCommand(candidate.id),
          ),
        const SizedBox(height: Spacing.lg),
        _TextDocumentView(
          title: command.command,
          text: command.combinedOutput,
          embedded: true,
        ),
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
      StudioSourceArtifactKind.webSource => Icons.language,
      StudioSourceArtifactKind.file => Icons.description_outlined,
      StudioSourceArtifactKind.diff ||
      StudioSourceArtifactKind.patch => Icons.difference_outlined,
      StudioSourceArtifactKind.command ||
      StudioSourceArtifactKind.terminalLog => Icons.terminal_outlined,
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
      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
      child: Row(
        children: [
          Icon(_iconFor(row.label), color: color, size: 15),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              row.label,
              style: TextStyle(color: color, fontSize: FontSizes.sm),
            ),
          ),
          Text(
            row.value,
            style: TextStyle(
              color: row.accent ? tokens.success : tokens.textMuted,
              fontSize: FontSizes.sm,
              fontWeight: row.accent ? FontWeight.w800 : FontWeight.w500,
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
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: selected ? tokens.studioHover : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tokens.studioDivider),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: tokens.textMuted, size: 16),
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
