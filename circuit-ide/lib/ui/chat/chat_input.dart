import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/agent_preflight.dart';
import '../../models/context_attachment.dart';
import '../../services/file_indexer.dart';
import '../../state/chat_provider.dart';
import '../../state/chat_context_draft_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/file_indexer_provider.dart';
import '../../state/theme_provider.dart';

class ChatInput extends ConsumerStatefulWidget {
  const ChatInput({super.key});

  @override
  ConsumerState<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends ConsumerState<ChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  bool _hasText = false;
  bool _fileContextAttached = false;

  // @-mention state
  bool _showMentionPopup = false;
  bool _showSlashPopup = false;
  String _mentionQuery = '';
  String _slashQuery = '';
  int _mentionStartIndex = -1;
  int _selectedMentionIndex = 0;
  int _selectedSlashIndex = 0;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _removeMentionOverlay();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final has = _controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);

    // Detect @-mention trigger
    final text = _controller.text;
    final cursor = _controller.selection.baseOffset;
    if (cursor < 0 || cursor > text.length) return;

    // Find the @ sign before cursor
    final beforeCursor = text.substring(0, cursor);
    final atIndex = beforeCursor.lastIndexOf('@');

    if (atIndex >= 0) {
      // Check there's no space between @ and cursor (allow paths with /)
      final query = beforeCursor.substring(atIndex + 1);
      if (!query.contains(' ') && !query.contains('\n')) {
        _mentionStartIndex = atIndex;
        _mentionQuery = query;
        _selectedMentionIndex = 0;
        _showMentionPopup = true;
        _updateMentionOverlay();
        return;
      }
    }

    final slashIndex = beforeCursor.lastIndexOf('/');
    if (slashIndex >= 0) {
      final query = beforeCursor.substring(slashIndex);
      final startsCommand =
          slashIndex == 0 ||
          beforeCursor.substring(0, slashIndex).endsWith('\n') ||
          beforeCursor.substring(0, slashIndex).endsWith(' ');
      if (startsCommand && !query.contains('\n')) {
        _mentionStartIndex = slashIndex;
        _slashQuery = query;
        _selectedSlashIndex = 0;
        _showSlashPopup = true;
        _updateSlashOverlay();
        return;
      }
    }

    if (_showMentionPopup) {
      _showMentionPopup = false;
      _removeMentionOverlay();
    }
    if (_showSlashPopup) {
      _showSlashPopup = false;
      _removeMentionOverlay();
    }
  }

  void _selectMention(IndexedFile file) {
    // Replace @query with just the text (we track mentioned files separately)
    final text = _controller.text;
    final before = text.substring(0, _mentionStartIndex);
    final after = _controller.selection.baseOffset < text.length
        ? text.substring(_controller.selection.baseOffset)
        : '';

    _controller.text = '$before$after';
    _controller.selection = TextSelection.collapsed(offset: before.length);

    ref.read(chatContextDraftProvider.notifier).addMention(file);

    _showMentionPopup = false;
    _removeMentionOverlay();
    _focusNode.requestFocus();
  }

  void _updateMentionOverlay() {
    _removeMentionOverlay();
    _overlayEntry = OverlayEntry(
      builder: (context) => _MentionPopup(
        layerLink: _layerLink,
        query: _mentionQuery,
        selectedIndex: _selectedMentionIndex,
        onSelect: _selectMention,
        onDismiss: () {
          _showMentionPopup = false;
          _removeMentionOverlay();
        },
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _updateSlashOverlay() {
    _removeMentionOverlay();
    _overlayEntry = OverlayEntry(
      builder: (context) => _SlashPopup(
        layerLink: _layerLink,
        query: _slashQuery,
        selectedIndex: _selectedSlashIndex,
        onSelect: _selectSlashCommand,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _selectSlashCommand(SlashCommandSpec spec) {
    final text = _controller.text;
    final before = text.substring(0, _mentionStartIndex);
    final after = _controller.selection.baseOffset < text.length
        ? text.substring(_controller.selection.baseOffset)
        : '';
    final suffix = spec.command == '/file' ? ' ' : '\n';

    _controller.text = '$before${spec.command}$suffix$after';
    _controller.selection = TextSelection.collapsed(
      offset: before.length + spec.command.length + suffix.length,
    );
    _showSlashPopup = false;
    _removeMentionOverlay();
    _focusNode.requestFocus();
  }

  List<SlashCommandSpec> _slashResults() {
    final query = _slashQuery.toLowerCase();
    return ChatContextDraftNotifier.slashCommands
        .where(
          (spec) =>
              spec.command.startsWith(query) ||
              spec.label.toLowerCase().contains(query.replaceFirst('/', '')),
        )
        .take(8)
        .toList();
  }

  void _removeMentionOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _toggleFileContext() {
    ref.read(chatContextDraftProvider.notifier).toggleActiveFileAttachment();
    setState(() => _fileContextAttached = !_fileContextAttached);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final draftNotifier = ref.read(chatContextDraftProvider.notifier);
    final slashResult = await draftNotifier.parseSlashCommands(text);
    for (final attachment in slashResult.attachments) {
      draftNotifier.addAttachment(attachment);
    }
    final attachments = ref.read(chatContextDraftProvider).attachments;
    if (slashResult.message.isEmpty && attachments.isEmpty) return;
    final preflight = await ref
        .read(chatProvider.notifier)
        .preflightMessage(slashResult.message, attachments);
    ref.read(chatProvider.notifier).setPreflight(preflight);
    if (!preflight.canSend) return;
    unawaited(
      ref
          .read(chatProvider.notifier)
          .sendMessage(slashResult.message, attachments: attachments),
    );
    _controller.clear();
    setState(() {
      _fileContextAttached = false;
    });
    draftNotifier.clearAfterSend();
    _removeMentionOverlay();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    if (_showSlashPopup) {
      final results = _slashResults();
      if (results.isEmpty) return false;

      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _selectedSlashIndex = (_selectedSlashIndex + 1).clamp(
            0,
            results.length - 1,
          );
        });
        _updateSlashOverlay();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _selectedSlashIndex = (_selectedSlashIndex - 1).clamp(
            0,
            results.length - 1,
          );
        });
        _updateSlashOverlay();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.tab) {
        _selectSlashCommand(results[_selectedSlashIndex]);
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _showSlashPopup = false;
        _removeMentionOverlay();
        return true;
      }
    }

    if (_showMentionPopup) {
      final results =
          ref.read(fileIndexerProvider)?.search(_mentionQuery, limit: 8) ?? [];
      if (results.isEmpty) return false;

      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _selectedMentionIndex = (_selectedMentionIndex + 1).clamp(
            0,
            results.length - 1,
          );
        });
        _updateMentionOverlay();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _selectedMentionIndex = (_selectedMentionIndex - 1).clamp(
            0,
            results.length - 1,
          );
        });
        _updateMentionOverlay();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.tab) {
        if (_selectedMentionIndex < results.length) {
          _selectMention(results[_selectedMentionIndex]);
          return true;
        }
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _showMentionPopup = false;
        _removeMentionOverlay();
        return true;
      }
    }

    // Normal enter to send
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed &&
        !_showMentionPopup &&
        !_showSlashPopup) {
      unawaited(_send());
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final chatState = ref.watch(chatProvider);
    final activeTab = ref.watch(editorProvider).activeTab;
    final hasFile =
        activeTab != null && !activeTab.filePath.startsWith('circuit://');
    final draft = ref.watch(chatContextDraftProvider);
    final attachments = draft.attachments;
    final preflight = chatState.preflight;
    final hasDraft = _hasText || attachments.isNotEmpty;

    // Ensure indexer is alive
    ref.watch(fileIndexerProvider);

    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: tokens.bgLight,
        border: Border(
          top: BorderSide(color: tokens.border.withValues(alpha: 0.6)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Context chips row
          if (attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ...attachments.map(
                    (attachment) => _ContextChip(
                      attachment: attachment,
                      label: attachment.label,
                      fullPath: attachment.path ?? attachment.promptHeader,
                      icon: _attachmentIcon(attachment.type),
                      muted: draft.pinnedAttachments.any(
                        (pinned) => pinned.id == attachment.id,
                      ),
                      onRemove: () => ref
                          .read(chatContextDraftProvider.notifier)
                          .removeAttachment(attachment.id),
                    ),
                  ),
                ],
              ),
            ),
          if (preflight?.primaryIssue != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: _PreflightBanner(result: preflight!),
            ),

          // Input row
          CompositedTransformTarget(
            link: _layerLink,
            child: KeyboardListener(
              focusNode: FocusNode(),
              onKeyEvent: (event) => _handleKeyEvent(event),
              child: Container(
                decoration: BoxDecoration(
                  color: tokens.inputBg,
                  borderRadius: BorderRadius.circular(Radii.lg),
                  border: Border.all(
                    color: _focusNode.hasFocus
                        ? tokens.inputFocusBorder
                        : tokens.inputBorder,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Attach file context button
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: MouseRegion(
                        cursor: hasFile
                            ? SystemMouseCursors.click
                            : SystemMouseCursors.basic,
                        child: GestureDetector(
                          onTap: hasFile ? _toggleFileContext : null,
                          child: AnimatedContainer(
                            duration: AnimationDurations.fast,
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: _fileContextAttached
                                  ? tokens.accent.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(Radii.md),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.attach_file_rounded,
                                size: 15,
                                color: _fileContextAttached
                                    ? tokens.accent
                                    : hasFile
                                    ? tokens.textMuted
                                    : tokens.textMuted.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        maxLines: 5,
                        minLines: 1,
                        enabled: !chatState.isProcessing,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: FontSizes.md,
                        ),
                        decoration: InputDecoration(
                          hintText: chatState.isProcessing
                              ? 'Waiting for response...'
                              : 'Message CircuitCode... (type @ or / for context)',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: Spacing.sm,
                            vertical: Spacing.lg,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: chatState.isProcessing
                          ? _StopButton(tokens: tokens)
                          : _SendButton(
                              tokens: tokens,
                              hasText: hasDraft,
                              onTap: hasDraft ? () => unawaited(_send()) : null,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _attachmentIcon(ContextAttachmentType type) {
    return switch (type) {
      ContextAttachmentType.lsdfIndex => Icons.hub_outlined,
      ContextAttachmentType.file => Icons.description_outlined,
      ContextAttachmentType.selection => Icons.select_all,
      ContextAttachmentType.terminal => Icons.terminal,
      ContextAttachmentType.gitDiff => Icons.account_tree_outlined,
      ContextAttachmentType.diagnostics => Icons.error_outline,
      ContextAttachmentType.symbols => Icons.data_object,
      ContextAttachmentType.url => Icons.link,
      ContextAttachmentType.note => Icons.notes,
    };
  }
}

// ------ Context chip widget ------

class _ContextChip extends ConsumerWidget {
  final ContextAttachment attachment;
  final String label;
  final String fullPath;
  final IconData icon;
  final VoidCallback onRemove;
  final bool muted;

  const _ContextChip({
    required this.attachment,
    required this.label,
    required this.fullPath,
    required this.icon,
    required this.onRemove,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Tooltip(
      message: 'Click to preview context',
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => _ContextPreviewDialog(attachment: attachment),
        ),
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: muted
                ? tokens.surfaceRaised
                : tokens.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(
              color: muted
                  ? tokens.outlineSubtle
                  : tokens.accent.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 11,
                color: muted ? tokens.textMuted : tokens.accent,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: muted ? tokens.textSecondary : tokens.accent,
                  fontSize: FontSizes.xxs,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onRemove,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(
                    Icons.close,
                    size: 10,
                    color: tokens.accent.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreflightBanner extends ConsumerWidget {
  final AgentPreflightResult result;

  const _PreflightBanner({required this.result});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final issue = result.primaryIssue;
    if (issue == null) return const SizedBox.shrink();
    final isBlocking = issue.severity == AgentPreflightSeverity.blocking;
    final color = isBlocking ? tokens.error : tokens.warning;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(
            isBlocking ? Icons.block_outlined : Icons.info_outline,
            size: 14,
            color: color,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              '${result.statusLabel} · ${issue.message}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: FontSizes.xs,
              ),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            '${result.estimatedTokens}/${result.contextWindow}',
            style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xxs),
          ),
        ],
      ),
    );
  }
}

class _ContextPreviewDialog extends ConsumerWidget {
  final ContextAttachment attachment;

  const _ContextPreviewDialog({required this.attachment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final preview = attachment.toPromptBlock();
    final status = attachment.resolutionStatus.name;

    return Dialog(
      backgroundColor: tokens.surfaceOverlay,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: tokens.outlineStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.attachment_outlined,
                    size: 16,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      attachment.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.md,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, size: 16, color: tokens.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                [
                  'Source: ${attachment.path ?? attachment.promptHeader}',
                  'Status: $status',
                  'Estimated tokens: ${attachment.estimatedTokens}',
                  if (attachment.truncationMessage != null)
                    attachment.truncationMessage!,
                ].join(' · '),
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                ),
              ),
              const SizedBox(height: Spacing.md),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(Spacing.md),
                  decoration: BoxDecoration(
                    color: tokens.bgMain,
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: tokens.outlineSubtle),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      preview,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: FontSizes.xs,
                        height: 1.45,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------ @-mention popup ------

class _MentionPopup extends ConsumerWidget {
  final LayerLink layerLink;
  final String query;
  final int selectedIndex;
  final void Function(IndexedFile) onSelect;
  final VoidCallback onDismiss;

  const _MentionPopup({
    required this.layerLink,
    required this.query,
    required this.selectedIndex,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final results =
        ref.watch(fileIndexerProvider)?.search(query, limit: 8) ?? [];

    if (results.isEmpty) {
      return CompositedTransformFollower(
        link: layerLink,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.bottomLeft,
        offset: const Offset(0, -4),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(Spacing.lg),
            decoration: BoxDecoration(
              color: tokens.bgLight,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: tokens.border),
              boxShadow: Shadows.medium,
            ),
            child: Text(
              'No files found',
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
            ),
          ),
        ),
      );
    }

    return CompositedTransformFollower(
      link: layerLink,
      targetAnchor: Alignment.topLeft,
      followerAnchor: Alignment.bottomLeft,
      offset: const Offset(0, -4),
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 360,
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            color: tokens.bgLight,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: tokens.border),
            boxShadow: Shadows.medium,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.md),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: results.length,
              itemBuilder: (context, index) {
                final file = results[index];
                final isSelected = index == selectedIndex;

                return InkWell(
                  onTap: () => onSelect(file),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.lg,
                      vertical: Spacing.md,
                    ),
                    color: isSelected
                        ? tokens.accent.withValues(alpha: 0.1)
                        : Colors.transparent,
                    child: Row(
                      children: [
                        Icon(
                          file.isDirectory
                              ? Icons.folder_outlined
                              : Icons.description_outlined,
                          size: 14,
                          color: isSelected
                              ? tokens.accent
                              : tokens.textSecondary,
                        ),
                        const SizedBox(width: Spacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                file.fileName,
                                style: TextStyle(
                                  color: isSelected
                                      ? tokens.accent
                                      : tokens.textPrimary,
                                  fontSize: FontSizes.sm,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (file.relativePath != file.fileName)
                                Text(
                                  file.relativePath,
                                  style: TextStyle(
                                    color: tokens.textMuted,
                                    fontSize: FontSizes.xxs,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SlashPopup extends ConsumerWidget {
  final LayerLink layerLink;
  final String query;
  final int selectedIndex;
  final void Function(SlashCommandSpec) onSelect;

  const _SlashPopup({
    required this.layerLink,
    required this.query,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final normalized = query.toLowerCase();
    final results = ChatContextDraftNotifier.slashCommands
        .where(
          (spec) =>
              spec.command.startsWith(normalized) ||
              spec.label.toLowerCase().contains(
                normalized.replaceFirst('/', ''),
              ),
        )
        .take(8)
        .toList();

    return CompositedTransformFollower(
      link: layerLink,
      targetAnchor: Alignment.topLeft,
      followerAnchor: Alignment.bottomLeft,
      offset: const Offset(0, -4),
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 340,
          constraints: const BoxConstraints(maxHeight: 260),
          decoration: BoxDecoration(
            color: tokens.surfaceOverlay,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: tokens.outlineStrong),
            boxShadow: Shadows.medium,
          ),
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
            itemCount: results.length,
            itemBuilder: (context, index) {
              final spec = results[index];
              final selected = index == selectedIndex;
              return InkWell(
                onTap: () => onSelect(spec),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? tokens.surfaceSelected : null,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _iconForType(spec.type),
                        size: 14,
                        color: selected ? tokens.accent : tokens.textMuted,
                      ),
                      const SizedBox(width: Spacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${spec.command} · ${spec.label}',
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: FontSizes.xs,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              spec.description,
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
            },
          ),
        ),
      ),
    );
  }

  static IconData _iconForType(ContextAttachmentType type) {
    return switch (type) {
      ContextAttachmentType.lsdfIndex => Icons.hub_outlined,
      ContextAttachmentType.file => Icons.description_outlined,
      ContextAttachmentType.selection => Icons.select_all,
      ContextAttachmentType.terminal => Icons.terminal,
      ContextAttachmentType.gitDiff => Icons.account_tree_outlined,
      ContextAttachmentType.diagnostics => Icons.error_outline,
      ContextAttachmentType.symbols => Icons.data_object,
      ContextAttachmentType.url => Icons.link,
      ContextAttachmentType.note => Icons.notes,
    };
  }
}

// ------ Stop / Send buttons ------

class _StopButton extends ConsumerWidget {
  final dynamic tokens;

  const _StopButton({required this.tokens});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnimatedContainer(
      duration: AnimationDurations.fast,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: tokens.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.error.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => ref.read(chatProvider.notifier).cancelOperation(),
          borderRadius: BorderRadius.circular(Radii.md),
          child: Center(
            child: Icon(Icons.stop_rounded, size: 16, color: tokens.error),
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final dynamic tokens;
  final bool hasText;
  final VoidCallback? onTap;

  const _SendButton({required this.tokens, required this.hasText, this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AnimationDurations.fast,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: hasText ? tokens.accent : tokens.accent.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.md),
          child: const Center(
            child: Icon(
              Icons.arrow_upward_rounded,
              size: 16,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
