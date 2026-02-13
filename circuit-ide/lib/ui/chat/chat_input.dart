import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../services/file_indexer.dart';
import '../../state/chat_provider.dart';
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
  final List<String> _mentionedFiles = [];
  bool _showMentionPopup = false;
  String _mentionQuery = '';
  int _mentionStartIndex = -1;
  int _selectedMentionIndex = 0;
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

    if (_showMentionPopup) {
      _showMentionPopup = false;
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

    if (!_mentionedFiles.contains(file.relativePath)) {
      setState(() => _mentionedFiles.add(file.relativePath));
    }

    _showMentionPopup = false;
    _removeMentionOverlay();
    _focusNode.requestFocus();
  }

  void _removeMention(String path) {
    setState(() => _mentionedFiles.remove(path));
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

  void _removeMentionOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _toggleFileContext() {
    final activeTab = ref.read(editorProvider).activeTab;
    if (activeTab == null || activeTab.filePath.startsWith('circuit://')) return;
    setState(() => _fileContextAttached = !_fileContextAttached);
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty && _mentionedFiles.isEmpty) return;

    final parts = <String>[];

    // Add @-mentioned files as context
    if (_mentionedFiles.isNotEmpty) {
      final files = _mentionedFiles.join(', ');
      parts.add('[Context files: $files — read these files for context]');
    }

    // Add active file context
    if (_fileContextAttached) {
      final activeTab = ref.read(editorProvider).activeTab;
      if (activeTab != null && !activeTab.filePath.startsWith('circuit://')) {
        parts.add('[Regarding: ${activeTab.fileName}]');
      }
    }

    if (text.isNotEmpty) {
      parts.add(text);
    }

    ref.read(chatProvider.notifier).sendMessage(parts.join('\n'));
    _controller.clear();
    setState(() {
      _fileContextAttached = false;
      _mentionedFiles.clear();
    });
    _removeMentionOverlay();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    if (_showMentionPopup) {
      final results = ref.read(fileIndexerProvider)
              ?.search(_mentionQuery, limit: 8) ??
          [];
      if (results.isEmpty) return false;

      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _selectedMentionIndex =
              (_selectedMentionIndex + 1).clamp(0, results.length - 1);
        });
        _updateMentionOverlay();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _selectedMentionIndex =
              (_selectedMentionIndex - 1).clamp(0, results.length - 1);
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
        !_showMentionPopup) {
      _send();
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
          if (_mentionedFiles.isNotEmpty || (_fileContextAttached && hasFile))
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ..._mentionedFiles.map((path) => _ContextChip(
                        label: path.split('/').last,
                        fullPath: path,
                        icon: Icons.description_outlined,
                        onRemove: () => _removeMention(path),
                      )),
                  if (_fileContextAttached && hasFile)
                    _ContextChip(
                      label: activeTab.fileName,
                      fullPath: activeTab.filePath,
                      icon: Icons.edit_document,
                      onRemove: () =>
                          setState(() => _fileContextAttached = false),
                    ),
                ],
              ),
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
                                        : tokens.textMuted
                                            .withValues(alpha: 0.3),
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
                              : 'Message CircuitCode... (type @ to mention files)',
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
                              hasText: _hasText,
                              onTap: _hasText ? _send : null,
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
}

// ------ Context chip widget ------

class _ContextChip extends ConsumerWidget {
  final String label;
  final String fullPath;
  final IconData icon;
  final VoidCallback onRemove;

  const _ContextChip({
    required this.label,
    required this.fullPath,
    required this.icon,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Tooltip(
      message: fullPath,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 2),
        decoration: BoxDecoration(
          color: tokens.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: tokens.accent.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: tokens.accent),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: tokens.accent,
                fontSize: FontSizes.xxs,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Icon(Icons.close, size: 10,
                    color: tokens.accent.withValues(alpha: 0.6)),
              ),
            ),
          ],
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
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.sm,
              ),
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
            child: Icon(
              Icons.stop_rounded,
              size: 16,
              color: tokens.error,
            ),
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

  const _SendButton({
    required this.tokens,
    required this.hasText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AnimationDurations.fast,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: hasText
            ? tokens.accent
            : tokens.accent.withValues(alpha: 0.3),
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
