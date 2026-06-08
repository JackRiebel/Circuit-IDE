import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../agent/config/models_config.dart';
import '../../core/constants/design_tokens.dart';
import '../../models/studio_shell.dart';
import '../../state/file_tree_provider.dart';
import '../../state/git_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/theme_provider.dart';

class StudioPromptComposer extends ConsumerStatefulWidget {
  final String hintText;
  final String submitTooltip;
  final ValueChanged<String> onSubmit;
  final bool compact;

  const StudioPromptComposer({
    super.key,
    required this.hintText,
    required this.onSubmit,
    this.submitTooltip = 'Start',
    this.compact = false,
  });

  @override
  ConsumerState<StudioPromptComposer> createState() =>
      _StudioPromptComposerState();
}

class _StudioPromptComposerState extends ConsumerState<StudioPromptComposer> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(studioShellProvider).composerText,
    );
    _controller.addListener(() {
      ref.read(studioShellProvider.notifier).setComposerText(_controller.text);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final studio = ref.watch(studioShellProvider);
    final rootPath = ref.watch(fileTreeProvider).rootPath;
    final branch = ref.watch(gitProvider).status.branch;
    final settings = ref.watch(settingsProvider);
    final projectLabel = rootPath == null
        ? 'Choose project'
        : p.basename(rootPath);

    return Container(
      decoration: BoxDecoration(
        color: tokens.studioComposer,
        borderRadius: BorderRadius.circular(widget.compact ? 18 : 22),
        border: Border.all(color: tokens.studioDivider),
        boxShadow: Shadows.elevated,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: widget.compact ? 92 : 96,
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.md,
              Spacing.sm,
              Spacing.sm,
            ),
            child: Column(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: widget.compact ? 3 : 4,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.base,
                      height: 1.35,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      hintStyle: TextStyle(color: tokens.textMuted),
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                Row(
                  children: [
                    const _ComposerIcon(
                      icon: Icons.add,
                      tooltip: 'Add context',
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            const _ComposerPill(
                              icon: Icons.back_hand_outlined,
                              label: 'Default permissions',
                            ),
                            const SizedBox(width: Spacing.lg),
                            _ComposerModeSelector(value: studio.promptMode),
                            const SizedBox(width: Spacing.md),
                            _ComposerPill(
                              label: _modelLabel(settings.ciscoModel),
                              trailing: Icons.expand_more,
                            ),
                            const SizedBox(width: Spacing.sm),
                            const _ComposerIcon(
                              icon: Icons.mic_none,
                              tooltip: 'Voice input',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Tooltip(
                      message: widget.submitTooltip,
                      child: InkWell(
                        onTap: _submit,
                        borderRadius: BorderRadius.circular(Radii.pill),
                        child: Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _controller.text.trim().isEmpty
                                ? tokens.textMuted.withValues(alpha: 0.18)
                                : tokens.textPrimary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_upward,
                            color: tokens.bgDark,
                            size: 17,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!widget.compact)
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              decoration: BoxDecoration(
                color: tokens.surfaceBase.withValues(alpha: 0.36),
                border: Border(top: BorderSide(color: tokens.studioDivider)),
              ),
              child: Row(
                children: [
                  _ComposerPill(
                    icon: Icons.folder_copy_outlined,
                    label: projectLabel,
                    trailing: Icons.expand_more,
                  ),
                  const SizedBox(width: Spacing.lg),
                  const _ComposerPill(
                    icon: Icons.computer_outlined,
                    label: 'Work locally',
                    trailing: Icons.expand_more,
                  ),
                  const SizedBox(width: Spacing.lg),
                  _ComposerPill(
                    icon: Icons.account_tree_outlined,
                    label: branch.isEmpty ? 'main' : branch,
                    trailing: Icons.expand_more,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit(text);
    _controller.clear();
    ref.read(studioShellProvider.notifier).clearComposer();
  }

  String _modelLabel(String model) {
    if (model == ModelsConfig.defaultCiscoModel) return '5.5 High';
    return model;
  }
}

class _ComposerModeSelector extends ConsumerWidget {
  final StudioPromptMode value;

  const _ComposerModeSelector({required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<StudioPromptMode>(
      tooltip: 'Task mode',
      color: ref.watch(themeProvider).studioPanel,
      onSelected: (mode) =>
          ref.read(studioShellProvider.notifier).setPromptMode(mode),
      itemBuilder: (context) => [
        for (final mode in StudioPromptMode.values)
          PopupMenuItem(value: mode, child: Text(mode.label)),
      ],
      child: _ComposerPill(
        icon: Icons.route_outlined,
        label: value.label,
        trailing: Icons.expand_more,
      ),
    );
  }
}

class _ComposerIcon extends ConsumerWidget {
  final IconData icon;
  final String tooltip;

  const _ComposerIcon({required this.icon, required this.tooltip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 28,
        height: 28,
        child: Icon(icon, color: tokens.textMuted, size: 18),
      ),
    );
  }
}

class _ComposerPill extends ConsumerWidget {
  final IconData? icon;
  final String label;
  final IconData? trailing;

  const _ComposerPill({this.icon, required this.label, this.trailing});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: tokens.textMuted, size: 14),
          const SizedBox(width: Spacing.sm),
        ],
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
        ),
        if (trailing != null) ...[
          const SizedBox(width: Spacing.xs),
          Icon(trailing, color: tokens.textMuted, size: 14),
        ],
      ],
    );
  }
}
