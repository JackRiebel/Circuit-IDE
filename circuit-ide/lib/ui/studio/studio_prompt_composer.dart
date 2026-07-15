import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../models/studio_shell.dart';
import '../../state/agent_turn_runtime_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/git_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/studio_token_usage_provider.dart';
import '../../state/theme_provider.dart';
import '../../core/config/studio_feature_flags.dart';
import 'studio_composer_image_directives.dart';
import 'studio_composer_selectors.dart';
import 'studio_composer_slash_commands.dart';
import 'studio_composer_utility_controls.dart';
import 'studio_chrome.dart';

class StudioPromptComposer extends ConsumerStatefulWidget {
  final String hintText;
  final String submitTooltip;
  final ValueChanged<String> onSubmit;
  final ValueChanged<String>? onQueueResearch;
  final bool compact;
  final String? taskId;

  const StudioPromptComposer({
    super.key,
    required this.hintText,
    required this.onSubmit,
    this.onQueueResearch,
    this.submitTooltip = 'Start',
    this.compact = false,
    this.taskId,
  });

  @override
  ConsumerState<StudioPromptComposer> createState() =>
      _StudioPromptComposerState();
}

class _StudioPromptComposerState extends ConsumerState<StudioPromptComposer> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(studioShellProvider).composerText,
    );
    _focusNode = FocusNode(debugLabel: 'studio-prompt-composer');
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
    _controller.addListener(() {
      ref.read(studioShellProvider.notifier).setComposerText(_controller.text);
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(
      studioShellProvider.select((state) => state.composerText),
      (previous, next) {
        if (next == _controller.text) return;
        _controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      },
    );
    final tokens = ref.watch(themeProvider);
    final studioControls = ref.watch(
      studioShellProvider.select(
        (state) => (
          promptMode: state.promptMode,
          planModeEnabled: state.planModeEnabled,
          specialistAgentId: state.specialistAgentId,
          customAgentId: state.customAgentId,
          executionMode: state.executionMode,
        ),
      ),
    );
    final rootPath = ref.watch(
      fileTreeProvider.select((state) => state.rootPath),
    );
    final branch = ref.watch(
      gitProvider.select((state) => state.status.branch),
    );
    final settings = ref.watch(settingsProvider);
    final activeRequestId = ref.watch(
      studioThreadProvider.select((state) {
        final thread = state.threadForTaskView(widget.taskId);
        if (thread == null || !thread.isActive) return null;
        final requestId = thread.requestId?.trim();
        return requestId == null || requestId.isEmpty ? null : requestId;
      }),
    );
    final tokenUsage = ref.watch(
      studioTokenUsageForTaskViewProvider(widget.taskId),
    );
    final requestTokenUsage = ref.watch(
      studioLastRequestTokenUsageForTaskViewProvider(widget.taskId),
    );
    final projectLabel = rootPath == null
        ? 'Choose project'
        : p.basename(rootPath);
    final imagePreviews = studioImageDirectivePreviews(_controller.text);
    final hasComposerText = _controller.text.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: tokens.studioComposer,
        borderRadius: BorderRadius.circular(widget.compact ? 16 : 19),
        border: Border.all(
          color: _focusNode.hasFocus
              ? tokens.inputFocusBorder
              : tokens.studioDivider.withValues(alpha: 0.22),
          width: _focusNode.hasFocus ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: widget.compact ? 0.035 : 0.06,
            ),
            blurRadius: widget.compact ? 6 : 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_slashMatches.isNotEmpty)
            StudioSlashCommandMenu(
              commands: _slashMatches,
              onSelect: _applySlashCommand,
            ),
          Container(
            height: imagePreviews.isEmpty
                ? (widget.compact ? 78 : 80)
                : (widget.compact ? 132 : 134),
            padding: const EdgeInsets.fromLTRB(13, 10, 8, 8),
            child: Column(
              children: [
                if (imagePreviews.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      height: 42,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: imagePreviews.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 7),
                        itemBuilder: (context, index) {
                          final preview = imagePreviews[index];
                          return StudioImageDirectivePreview(
                            path: preview.path,
                            role: preview.role,
                            tokens: tokens,
                            onRemove: () => _removeImageDirective(preview.path),
                            onPreview: () => showStudioImageDirectivePreview(
                              context,
                              preview,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {
                      if (settings.sendOnEnter) ...{
                        const SingleActivator(LogicalKeyboardKey.enter):
                            _submit,
                        const SingleActivator(LogicalKeyboardKey.numpadEnter):
                            _submit,
                      } else
                        const SingleActivator(
                          LogicalKeyboardKey.enter,
                          shift: true,
                        ): _submit,
                    },
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: widget.compact ? 3 : 4,
                      textInputAction: TextInputAction.send,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.md,
                        height: 1.22,
                      ),
                      decoration: InputDecoration(
                        hintText: widget.hintText,
                        hintStyle: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FontSizes.md,
                          height: 1.22,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        filled: false,
                        isCollapsed: true,
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            const StudioAddContextButton(),
                            const SizedBox(width: 9),
                            Tooltip(
                              message: 'Attach image',
                              child: StudioFocusableActionSurface(
                                semanticLabel: 'Attach image',
                                onTap: () => unawaited(_attachImage()),
                                borderRadius: BorderRadius.circular(Radii.pill),
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: Icon(
                                    StudioIcons.imageOutlined,
                                    color: tokens.textMuted,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 9),
                            const StudioComposerPermissionsSelector(),
                            const SizedBox(width: 9),
                            StudioComposerModeSelector(
                              value: studioControls.promptMode,
                            ),
                            const SizedBox(width: 9),
                            StudioComposerPlanModeToggle(
                              enabled: studioControls.planModeEnabled,
                            ),
                            const SizedBox(width: 9),
                            if (widget.compact &&
                                StudioFeatureFlags.enterpriseSpecialists) ...[
                              StudioComposerSpecialistAgentSelector(
                                value: studioControls.specialistAgentId,
                              ),
                              const SizedBox(width: 9),
                            ],
                            StudioCustomAgentSelector(
                              selectedAgentId: studioControls.customAgentId,
                            ),
                            const SizedBox(width: 9),
                            StudioModelSelector(
                              selectedModel: settings.ciscoModel,
                            ),
                            const SizedBox(width: 9),
                            StudioTokenRemainingPill(
                              modelId: settings.ciscoModel,
                              threadUsage: tokenUsage,
                              requestUsage: requestTokenUsage,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    if (studioControls.promptMode ==
                            StudioPromptMode.research &&
                        widget.onQueueResearch != null) ...[
                      Tooltip(
                        message:
                            'Queue this research task separately; it will wait for any active work.',
                        child: StudioFocusableActionSurface(
                          semanticLabel: 'Queue research',
                          onTap: hasComposerText ? _queueResearch : null,
                          borderRadius: BorderRadius.circular(Radii.pill),
                          child: Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: !hasComposerText
                                  ? tokens.studioControl.withValues(alpha: 0.52)
                                  : tokens.studioControl.withValues(
                                      alpha: 0.92,
                                    ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: tokens.studioDivider.withValues(
                                  alpha: 0.28,
                                ),
                              ),
                            ),
                            child: Icon(
                              StudioIcons.scheduleOutlined,
                              color: !hasComposerText
                                  ? tokens.textMuted
                                  : tokens.textPrimary,
                              size: 15,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                    ],
                    Tooltip(
                      message: activeRequestId == null
                          ? '${widget.submitTooltip} (${settings.sendOnEnter ? 'Enter' : 'Shift+Enter'} to send)'
                          : 'Cancel active request (Esc)',
                      child: StudioFocusableActionSurface(
                        semanticLabel: activeRequestId == null
                            ? widget.submitTooltip
                            : 'Cancel active request',
                        onTap: activeRequestId == null
                            ? _submit
                            : () => ref
                                  .read(agentTurnRuntimeProvider.notifier)
                                  .cancel(activeRequestId),
                        borderRadius: BorderRadius.circular(Radii.pill),
                        child: Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: activeRequestId != null
                                ? tokens.warning.withValues(alpha: 0.92)
                                : !hasComposerText
                                ? tokens.studioControl.withValues(alpha: 0.52)
                                : tokens.textPrimary.withValues(alpha: 0.94),
                            shape: BoxShape.circle,
                            border: activeRequestId == null && !hasComposerText
                                ? Border.all(
                                    color: tokens.studioDivider.withValues(
                                      alpha: 0.28,
                                    ),
                                  )
                                : null,
                          ),
                          child: Icon(
                            activeRequestId == null
                                ? StudioIcons.arrowUpward
                                : StudioIcons.stopCircleOutlined,
                            color: activeRequestId == null && !hasComposerText
                                ? tokens.textMuted
                                : tokens.bgDark,
                            size: 16,
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
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
              decoration: BoxDecoration(
                color: tokens.surfaceBase.withValues(alpha: 0.16),
                border: Border(
                  top: BorderSide(
                    color: tokens.studioDivider.withValues(alpha: 0.54),
                  ),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StudioProjectPickerPill(
                      icon: StudioIcons.folderCopyOutlined,
                      label: projectLabel,
                    ),
                    const SizedBox(width: Spacing.xl),
                    StudioComposerExecutionModeSelector(
                      value: studioControls.executionMode,
                    ),
                    const SizedBox(width: Spacing.xl),
                    StudioComposerPill(
                      icon: StudioIcons.accountTreeOutlined,
                      label: branch.isEmpty ? 'main' : branch,
                    ),
                    const SizedBox(width: Spacing.xl),
                    if (StudioFeatureFlags.enterpriseSpecialists)
                      StudioComposerSpecialistAgentSelector(
                        value: studioControls.specialistAgentId,
                      ),
                    const StudioCustomAgentRoutingPreview(),
                  ],
                ),
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

  void _queueResearch() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onQueueResearch?.call(text);
    _controller.clear();
    ref.read(studioShellProvider.notifier).clearComposer();
  }

  List<StudioSlashCommand> get _slashMatches =>
      studioSlashCommandMatches(_controller.text);

  void _applySlashCommand(StudioSlashCommand command) {
    command.run?.call(ref);
    if (command.prompt.isNotEmpty) {
      _controller.text = command.prompt;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    } else {
      _controller.clear();
    }
  }

  Future<void> _attachImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.singleOrNull?.path;
    if (path == null || path.trim().isEmpty || !mounted) return;
    final normalized = p.normalize(path);
    if (studioImageDirectivePaths(_controller.text).contains(normalized)) {
      return;
    }
    final existing = _controller.text.trimRight();
    _controller.text = [
      if (existing.isNotEmpty) existing,
      '/image $normalized',
    ].join('\n');
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  void _removeImageDirective(String path) {
    final normalized = p.normalize(path);
    _controller.text = _controller.text
        .split('\n')
        .where((line) => !studioImageDirectiveReferencesPath(line, normalized))
        .join('\n')
        .trim();
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }
}
