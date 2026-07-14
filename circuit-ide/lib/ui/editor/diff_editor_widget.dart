import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/diff_models.dart';
import '../../services/diff_engine.dart';
import '../../services/worker_cancellation.dart';
import '../../state/editor_provider.dart';
import '../../state/theme_provider.dart';
import 'diff_toolbar.dart';

class DiffEditorWidget extends ConsumerStatefulWidget {
  final String diffId;

  const DiffEditorWidget({super.key, required this.diffId});

  @override
  ConsumerState<DiffEditorWidget> createState() => _DiffEditorWidgetState();
}

class _DiffEditorWidgetState extends ConsumerState<DiffEditorWidget> {
  late final ScrollController _leftScroll;
  late final ScrollController _rightScroll;
  DiffResult? _diffResult;
  List<int> _changeIndices = [];
  int _currentChangeIndex = -1;
  bool _syncing = false;
  int _diffGeneration = 0;
  WorkerCancellationToken? _diffCancellation;

  @override
  void initState() {
    super.initState();
    _leftScroll = ScrollController();
    _rightScroll = ScrollController();
    _leftScroll.addListener(_syncLeft);
    _rightScroll.addListener(_syncRight);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _computeDiff();
    });
  }

  @override
  void dispose() {
    _diffGeneration++;
    _diffCancellation?.cancel('Diff editor disposed.');
    _leftScroll.removeListener(_syncLeft);
    _rightScroll.removeListener(_syncRight);
    _leftScroll.dispose();
    _rightScroll.dispose();
    super.dispose();
  }

  void _syncLeft() {
    if (_syncing) return;
    _syncing = true;
    if (_rightScroll.hasClients) {
      _rightScroll.jumpTo(_leftScroll.offset);
    }
    _syncing = false;
  }

  void _syncRight() {
    if (_syncing) return;
    _syncing = true;
    if (_leftScroll.hasClients) {
      _leftScroll.jumpTo(_rightScroll.offset);
    }
    _syncing = false;
  }

  Future<void> _computeDiff() async {
    final generation = ++_diffGeneration;
    _diffCancellation?.cancel('Superseded by a newer diff.');
    final cancellation = WorkerCancellationToken();
    _diffCancellation = cancellation;
    final editor = ref.read(editorProvider.notifier);
    final diffData = editor.getDiffData(widget.diffId);
    if (diffData == null) return;

    DiffResult result;
    try {
      result = await DiffEngine.diffInWorker(
        leftContent: diffData.leftContent,
        rightContent: diffData.rightContent,
        leftTitle: diffData.leftTitle,
        rightTitle: diffData.rightTitle,
        cancellationToken: cancellation,
      );
    } on WorkerCancelledException {
      return;
    }
    if (!mounted || generation != _diffGeneration) return;

    // Build change index list for navigation
    final changes = <int>[];
    for (int i = 0; i < result.lines.length; i++) {
      if (result.lines[i].type != DiffType.unchanged) {
        changes.add(i);
      }
    }

    setState(() {
      _diffResult = result;
      _changeIndices = changes;
    });
  }

  void _navigateToChange(int direction) {
    if (_changeIndices.isEmpty) return;

    setState(() {
      _currentChangeIndex = (_currentChangeIndex + direction).clamp(
        0,
        _changeIndices.length - 1,
      );
    });

    final lineIndex = _changeIndices[_currentChangeIndex];
    final offset = lineIndex * 22.0; // approximate line height
    if (_leftScroll.hasClients) {
      _leftScroll.animateTo(
        offset,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    if (_diffResult == null) {
      return Center(child: CircularProgressIndicator(color: tokens.accent));
    }

    final result = _diffResult!;

    return Column(
      children: [
        DiffToolbar(
          diffResult: result,
          onPrevChange: _changeIndices.isEmpty
              ? null
              : () => _navigateToChange(-1),
          onNextChange: _changeIndices.isEmpty
              ? null
              : () => _navigateToChange(1),
        ),
        Expanded(
          child: Row(
            children: [
              // Left panel
              Expanded(
                child: _DiffPanel(
                  scrollController: _leftScroll,
                  lines: result.lines,
                  isLeft: true,
                  tokens: tokens,
                ),
              ),
              // Divider
              Container(width: 1, color: tokens.border),
              // Right panel
              Expanded(
                child: _DiffPanel(
                  scrollController: _rightScroll,
                  lines: result.lines,
                  isLeft: false,
                  tokens: tokens,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DiffPanel extends StatelessWidget {
  final ScrollController scrollController;
  final List<DiffLine> lines;
  final bool isLeft;
  final dynamic tokens;

  const _DiffPanel({
    required this.scrollController,
    required this.lines,
    required this.isLeft,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      itemCount: lines.length,
      itemExtent: 22,
      itemBuilder: (context, index) {
        final line = lines[index];
        final lineNum = isLeft ? line.leftLineNum : line.rightLineNum;
        final content = isLeft ? line.leftContent : line.rightContent;

        Color bgColor;
        switch (line.type) {
          case DiffType.added:
            bgColor = isLeft
                ? Colors.transparent
                : tokens.success.withValues(alpha: 0.08);
          case DiffType.removed:
            bgColor = isLeft
                ? tokens.error.withValues(alpha: 0.08)
                : Colors.transparent;
          case DiffType.modified:
            bgColor = tokens.warning.withValues(alpha: 0.08);
          case DiffType.unchanged:
            bgColor = Colors.transparent;
        }

        final showContent =
            (isLeft && line.type != DiffType.added) ||
            (!isLeft && line.type != DiffType.removed);

        return Container(
          color: bgColor,
          height: 22,
          child: Row(
            children: [
              // Line number gutter
              Container(
                width: 48,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  lineNum?.toString() ?? '',
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
                    fontFamily: EditorDefaults.fontFamily,
                  ),
                ),
              ),
              // Change indicator
              SizedBox(
                width: 16,
                child: Center(
                  child: Text(
                    line.type == DiffType.added && !isLeft
                        ? '+'
                        : line.type == DiffType.removed && isLeft
                        ? '-'
                        : line.type == DiffType.modified
                        ? '~'
                        : '',
                    style: TextStyle(
                      color: line.type == DiffType.added
                          ? tokens.success
                          : line.type == DiffType.removed
                          ? tokens.error
                          : tokens.warning,
                      fontSize: FontSizes.xs,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: showContent
                    ? Text(
                        content ?? '',
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: FontSizes.sm,
                          fontFamily: EditorDefaults.fontFamily,
                        ),
                        overflow: TextOverflow.clip,
                        maxLines: 1,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }
}
