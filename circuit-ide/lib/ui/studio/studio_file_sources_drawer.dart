import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/agent_workspace.dart';
import '../../models/studio_source_artifact.dart';
import '../../services/macos_file_reveal_service.dart';
import '../../state/file_tree_provider.dart';
import '../../state/studio_browser_provider.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_source_artifact_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_chrome.dart';

/// Reusable compact row for selectable evidence, files, and Git changes.
class StudioDrawerListRow extends ConsumerStatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onReveal;
  final VoidCallback? onRemove;
  final bool selected;
  final FocusNode? focusNode;

  const StudioDrawerListRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.onReveal,
    this.onRemove,
    this.selected = false,
    this.focusNode,
  });

  @override
  ConsumerState<StudioDrawerListRow> createState() =>
      _StudioDrawerListRowState();
}

class _StudioDrawerListRowState extends ConsumerState<StudioDrawerListRow> {
  FocusNode? _ownedFocusNode;
  FocusNode? _listenedFocusNode;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();
    _configureFocusNode();
  }

  @override
  void didUpdateWidget(covariant StudioDrawerListRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _configureFocusNode();
    }
  }

  @override
  void dispose() {
    _listenedFocusNode?.removeListener(_onFocusChanged);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _configureFocusNode() {
    _listenedFocusNode?.removeListener(_onFocusChanged);
    if (widget.focusNode == null) {
      _ownedFocusNode ??= FocusNode(
        debugLabel: 'studio-drawer-row-${widget.title}',
      );
    } else {
      _ownedFocusNode?.dispose();
      _ownedFocusNode = null;
    }
    _listenedFocusNode = _focusNode..addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (widget.onTap == null || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.space &&
        key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    widget.onTap!.call();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final enabled = widget.onTap != null;
    final focused = _focusNode.hasFocus;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Semantics(
        container: true,
        label: '${widget.title}, ${widget.subtitle}',
        button: enabled,
        selected: widget.selected,
        enabled: enabled,
        onTap: widget.onTap,
        child: Focus(
          focusNode: _focusNode,
          canRequestFocus: enabled,
          skipTraversal: !enabled,
          onKeyEvent: _handleKeyEvent,
          child: InkWell(
            canRequestFocus: false,
            onTap: widget.onTap == null
                ? null
                : () {
                    _focusNode.requestFocus();
                    widget.onTap!.call();
                  },
            borderRadius: BorderRadius.circular(Radii.md),
            child: Container(
              constraints: const BoxConstraints(
                minHeight: StudioChromeIconButton.minimumTargetSize,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: widget.selected
                    ? tokens.studioControl.withValues(alpha: 0.62)
                    : tokens.studioActivityRow.withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(
                  color: focused
                      ? tokens.outlineFocus
                      : tokens.studioDivider.withValues(
                          alpha: widget.selected ? 0.72 : 0.42,
                        ),
                  width: focused ? 1.5 : 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(widget.icon, color: tokens.textMuted, size: 13),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
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
                          widget.subtitle,
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
                  if (widget.onReveal != null)
                    StudioChromeIconButton(
                      tooltip: 'Reveal saved local visual snapshot in Finder',
                      onTap: widget.onReveal,
                      icon: StudioIcons.folderOpenOutlined,
                      width: 28,
                      height: 28,
                      iconSize: 15,
                    ),
                  if (widget.onRemove != null)
                    StudioChromeIconButton(
                      tooltip: 'Delete saved local visual snapshot',
                      onTap: widget.onRemove,
                      icon: StudioIcons.deleteOutline,
                      width: 28,
                      height: 28,
                      iconSize: 15,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The project-file and source-evidence surfaces of the Studio work drawer.
class StudioFilesDrawer extends ConsumerWidget {
  const StudioFilesDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fileTree = ref.watch(fileTreeProvider);
    if (fileTree.rootPath == null) {
      return _FileSourcesEmptyState(
        icon: StudioIcons.folderOutlined,
        title: 'No project selected',
        detail: 'Choose a project to see files here.',
        actionLabel: 'Back to projects',
        onAction: () => ref.read(studioShellProvider.notifier).openHome(),
      );
    }
    final nodes = fileTree.nodes.take(80).toList();
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        for (final node in nodes)
          StudioDrawerListRow(
            icon: node.isDirectory
                ? StudioIcons.folderOutlined
                : StudioIcons.descriptionOutlined,
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

class StudioSourcesDrawer extends ConsumerWidget {
  final AgentTask? task;

  const StudioSourcesDrawer({super.key, this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threadId = ref.watch(
      studioThreadProvider.select(
        (state) => state.threadForTaskView(task?.id)?.id,
      ),
    );
    final artifactView = ref.watch(
      studioSourceArtifactsForThreadProvider(threadId),
    );
    if (artifactView.isEmpty) {
      return _FileSourcesEmptyState(
        icon: StudioIcons.travelExplore,
        title: 'No sources yet',
        detail:
            'Context, local previews, files, diffs, and commands appear here.',
        actionLabel: 'Start a task',
        onAction: () => ref.read(studioShellProvider.notifier).openHome(),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        for (final artifact in artifactView.artifacts)
          StudioDrawerListRow(
            icon: _sourceIcon(artifact.kind),
            title: artifact.title,
            subtitle: artifact.subtitle,
            onTap: () => ref
                .read(studioRightDrawerProvider.notifier)
                .openArtifact(artifact),
            onReveal:
                artifact.kind == StudioSourceArtifactKind.browserVisualSnapshot
                ? () => _revealVisualSnapshot(context, artifact)
                : null,
            onRemove:
                artifact.kind == StudioSourceArtifactKind.browserVisualSnapshot
                ? () => _confirmDeleteVisualSnapshot(context, ref, artifact)
                : null,
          ),
      ],
    );
  }

  Future<void> _confirmDeleteVisualSnapshot(
    BuildContext context,
    WidgetRef ref,
    StudioSourceArtifact artifact,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final tokens = ref.read(themeProvider);
        return AlertDialog(
          backgroundColor: tokens.studioPanel,
          title: const Text('Delete saved visual snapshot?'),
          content: const Text(
            'This permanently removes the local browser image and its task record. It cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete snapshot'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref
        .read(studioBrowserProvider.notifier)
        .deleteVisualSnapshot(artifact.id);
    if (!context.mounted) return;
    final message = switch (result) {
      BrowserVisualSnapshotDeleteResult.deleted =>
        'Deleted the saved local visual snapshot.',
      BrowserVisualSnapshotDeleteResult.unavailable =>
        'That saved visual snapshot is no longer available.',
      BrowserVisualSnapshotDeleteResult.failed =>
        'Could not delete the saved local visual snapshot.',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _revealVisualSnapshot(
    BuildContext context,
    StudioSourceArtifact artifact,
  ) async {
    final filePath = artifact.filePath;
    if (filePath == null || filePath.trim().isEmpty) return;
    final revealed = await MacosFileRevealService.platform.reveal(filePath);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          revealed
              ? 'Revealed the saved local visual snapshot in Finder.'
              : 'Could not reveal the saved local visual snapshot.',
        ),
      ),
    );
  }
}

IconData _sourceIcon(StudioSourceArtifactKind kind) {
  return switch (kind) {
    StudioSourceArtifactKind.localUrl ||
    StudioSourceArtifactKind.webSource ||
    StudioSourceArtifactKind.browserComment ||
    StudioSourceArtifactKind.browserSelection => StudioIcons.language,
    StudioSourceArtifactKind.browserVisualSnapshot =>
      StudioIcons.screenshotMonitorOutlined,
    StudioSourceArtifactKind.file => StudioIcons.descriptionOutlined,
    StudioSourceArtifactKind.generatedArtifact =>
      StudioIcons.filePresentOutlined,
    StudioSourceArtifactKind.diff ||
    StudioSourceArtifactKind.gitChange ||
    StudioSourceArtifactKind.gitHunk ||
    StudioSourceArtifactKind.reviewComment ||
    StudioSourceArtifactKind.patch => StudioIcons.differenceOutlined,
    StudioSourceArtifactKind.command ||
    StudioSourceArtifactKind.terminalLog ||
    StudioSourceArtifactKind.terminalSession => StudioIcons.terminalOutlined,
    StudioSourceArtifactKind.topology => StudioIcons.accountTreeOutlined,
    StudioSourceArtifactKind.sizing => StudioIcons.straightenOutlined,
    StudioSourceArtifactKind.lifecycle => StudioIcons.eventAvailableOutlined,
    StudioSourceArtifactKind.chart => StudioIcons.insertChartOutlined,
    StudioSourceArtifactKind.businessUseCase => StudioIcons.queryStatsOutlined,
    StudioSourceArtifactKind.evidence => StudioIcons.verifiedOutlined,
    StudioSourceArtifactKind.toolResult => StudioIcons.datasetLinkedOutlined,
  };
}

class _FileSourcesEmptyState extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _FileSourcesEmptyState({
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
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
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: Spacing.xs),
                    TextButton(
                      onPressed: onAction,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 24),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: tokens.textSecondary,
                        textStyle: const TextStyle(
                          fontSize: FontSizes.xs,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
