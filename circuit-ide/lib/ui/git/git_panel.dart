import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../core/utils/platform_utils.dart';
import '../../models/git_models.dart';
import '../../state/connection_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/git_provider.dart';
import '../../state/code_review_provider.dart';
import '../../state/theme_provider.dart';
import 'branch_picker.dart';
import 'code_review_button.dart';
import 'review_summary_panel.dart';

class GitPanel extends ConsumerStatefulWidget {
  const GitPanel({super.key});

  @override
  ConsumerState<GitPanel> createState() => _GitPanelState();
}

class _GitPanelState extends ConsumerState<GitPanel> {
  final _commitMsgController = TextEditingController();
  bool _isGeneratingCommitMsg = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(gitProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _commitMsgController.dispose();
    super.dispose();
  }

  Future<void> _generateCommitMessage() async {
    if (_isGeneratingCommitMsg) return;
    setState(() => _isGeneratingCommitMsg = true);

    try {
      final workingDir =
          ref.read(fileTreeProvider).rootPath ?? PlatformUtils.scratchDir;
      final git = ref.read(gitProvider);

      // Use staged diff if there are staged changes, otherwise unstaged diff
      final diffArg = git.status.staged.isNotEmpty ? '--cached' : '';
      final result = await Process.run('git', [
        'diff',
        if (diffArg.isNotEmpty) diffArg,
      ], workingDirectory: workingDir);

      final diff = (result.stdout as String).trim();
      if (diff.isEmpty) {
        if (mounted) setState(() => _isGeneratingCommitMsg = false);
        return;
      }

      // Truncate diff to avoid token limits
      final truncatedDiff = diff.length > 4000 ? diff.substring(0, 4000) : diff;

      final service = ref.read(agentServiceProvider);
      final response = await service.sendOneShot(
        'Generate a concise git commit message for these changes. '
        'Return ONLY the commit message, no explanation or formatting.\n\n$truncatedDiff',
      );

      if (mounted && response != null && response.isNotEmpty) {
        // Strip quotes and whitespace from the response
        final cleaned = response.replaceAll(RegExp(r'^["`\s]+|["`\s]+$'), '');
        _commitMsgController.text = cleaned;
      }
    } catch (_) {
      // Silently fail — user can write manually
    } finally {
      if (mounted) setState(() => _isGeneratingCommitMsg = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final git = ref.watch(gitProvider);
    final reviewState = ref.watch(codeReviewProvider);

    if (git.error != null && git.error!.contains('not a git repository')) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.source_outlined,
              size: 32,
              color: tokens.textMuted.withValues(alpha: 0.3),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'Not a Git repository',
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Branch picker
        const BranchPicker(),
        Container(height: 1, color: tokens.border.withValues(alpha: 0.3)),

        // Commit input
        Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commitMsgController,
                      maxLines: 3,
                      minLines: 1,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.sm,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Commit message',
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Tooltip(
                    message: 'Generate commit message with AI',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: _isGeneratingCommitMsg
                            ? null
                            : _generateCommitMessage,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: tokens.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(Radii.sm),
                            border: Border.all(
                              color: tokens.accent.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Center(
                            child: _isGeneratingCommitMsg
                                ? SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: tokens.accent,
                                    ),
                                  )
                                : Icon(
                                    Icons.auto_awesome,
                                    size: 14,
                                    color: tokens.accent,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              SizedBox(
                width: double.infinity,
                height: 30,
                child: ElevatedButton.icon(
                  onPressed: git.status.staged.isEmpty
                      ? null
                      : () async {
                          final msg = _commitMsgController.text.trim();
                          if (msg.isEmpty) return;
                          await ref.read(gitProvider.notifier).commit(msg);
                          _commitMsgController.clear();
                        },
                  icon: const Icon(Icons.check, size: 14),
                  label: const Text('Commit'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.sm),
        const CodeReviewButton(),
        const SizedBox(height: Spacing.sm),
        Container(height: 1, color: tokens.border.withValues(alpha: 0.3)),

        // Changes list or Review summary
        Expanded(
          child: reviewState.currentReview != null
              ? const ReviewSummaryPanel()
              : git.isLoading
              ? Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: tokens.accent,
                    ),
                  ),
                )
              : ListView(
                  children: [
                    if (git.status.staged.isNotEmpty)
                      _ChangeSection(
                        title: 'Staged Changes (${git.status.staged.length})',
                        changes: git.status.staged,
                        isStaged: true,
                      ),
                    if (git.status.unstaged.isNotEmpty)
                      _ChangeSection(
                        title: 'Changes (${git.status.unstaged.length})',
                        changes: git.status.unstaged,
                        isStaged: false,
                      ),
                    if (git.status.untracked.isNotEmpty)
                      _ChangeSection(
                        title: 'Untracked (${git.status.untracked.length})',
                        changes: git.status.untracked,
                        isStaged: false,
                      ),
                    if (git.status.isClean)
                      Padding(
                        padding: const EdgeInsets.all(Spacing.xl),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 24,
                                color: tokens.success.withValues(alpha: 0.4),
                              ),
                              const SizedBox(height: Spacing.sm),
                              Text(
                                'No changes',
                                style: TextStyle(
                                  color: tokens.textMuted,
                                  fontSize: FontSizes.sm,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ChangeSection extends ConsumerWidget {
  final String title;
  final List<GitFileChange> changes;
  final bool isStaged;

  const _ChangeSection({
    required this.title,
    required this.changes,
    required this.isStaged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.md,
          ),
          child: Text(
            title,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xxs,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...changes.map(
          (change) => _ChangeItem(change: change, isStaged: isStaged),
        ),
      ],
    );
  }
}

class _ChangeItem extends ConsumerStatefulWidget {
  final GitFileChange change;
  final bool isStaged;

  const _ChangeItem({required this.change, required this.isStaged});

  @override
  ConsumerState<_ChangeItem> createState() => _ChangeItemState();
}

class _ChangeItemState extends ConsumerState<_ChangeItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final typeColor = switch (widget.change.type) {
      GitChangeType.added => tokens.success,
      GitChangeType.deleted => tokens.error,
      GitChangeType.modified => tokens.warning,
      GitChangeType.untracked => tokens.textMuted,
      _ => tokens.info,
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          if (widget.isStaged) {
            ref.read(gitProvider.notifier).unstageFile(widget.change.path);
          } else {
            ref.read(gitProvider.notifier).stageFile(widget.change.path);
          }
        },
        child: AnimatedContainer(
          duration: AnimationDurations.instant,
          color: _isHovered
              ? tokens.accent.withValues(alpha: 0.05)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: 3,
          ),
          child: Row(
            children: [
              Container(
                width: 16,
                alignment: Alignment.center,
                child: Text(
                  widget.change.type.code,
                  style: TextStyle(
                    color: typeColor,
                    fontSize: FontSizes.xxs,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.change.path,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                    letterSpacing: 0,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AnimatedOpacity(
                duration: AnimationDurations.fast,
                opacity: _isHovered ? 1.0 : 0.0,
                child: Icon(
                  widget.isStaged
                      ? Icons.remove_circle_outline
                      : Icons.add_circle_outline,
                  size: 14,
                  color: tokens.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
