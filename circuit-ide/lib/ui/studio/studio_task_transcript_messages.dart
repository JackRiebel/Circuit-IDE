import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../core/constants/design_tokens.dart';
import '../../core/constants/studio_layout_contract.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';
import '../chat/chat_message_widget.dart';
import 'studio_chrome.dart';

enum _AssistantFeedback { helpful, needsWork }

class StudioTaskChatTranscriptLine extends ConsumerWidget {
  final bool isUser;
  final String text;
  final bool isStreaming;

  const StudioTaskChatTranscriptLine({
    super.key,
    required this.isUser,
    required this.text,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    if (!isUser) {
      return Semantics(
        container: true,
        label: 'Circuit response',
        child: Align(
          alignment: Alignment.centerLeft,
          child: _AssistantMessageBlock(
            text: text,
            tokens: tokens,
            isStreaming: isStreaming,
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: 'Your message',
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: tokens.studioBubble,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: FontSizes.md,
              height: 1.28,
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantMessageBlock extends StatefulWidget {
  final String text;
  final ThemeTokens tokens;
  final bool isStreaming;

  const _AssistantMessageBlock({
    required this.text,
    required this.tokens,
    required this.isStreaming,
  });

  @override
  State<_AssistantMessageBlock> createState() => _AssistantMessageBlockState();
}

class _AssistantMessageBlockState extends State<_AssistantMessageBlock> {
  _AssistantFeedback? _feedback;

  @override
  Widget build(BuildContext context) {
    final wideLayout = _assistantNeedsReviewWidth(widget.text);
    return Container(
      key: ValueKey(
        'studio-assistant-${wideLayout ? 'review' : 'prose'}-${widget.isStreaming ? 'streaming' : widget.text.hashCode}',
      ),
      constraints: BoxConstraints(
        maxWidth: wideLayout
            ? StudioLayoutContract.reviewWidth
            : StudioLayoutContract.proseWidth,
      ),
      margin: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.isStreaming &&
              _StreamingAssistantText.shouldUseChunkedRendering(widget.text))
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: _StreamingAssistantText(
                text: widget.text,
                tokens: widget.tokens,
              ),
            )
          else
            MarkdownWidget(
              data: widget.text,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              config: buildChatMarkdownConfig(widget.tokens),
            ),
          const SizedBox(height: 1),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AssistantActionButton(
                tooltip: 'Copy response',
                icon: StudioIcons.copyOutlined,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.text));
                  _showQuietSnack(context, 'Copied response');
                },
              ),
              _AssistantActionButton(
                tooltip: 'Mark helpful',
                icon: StudioIcons.thumbUpAltOutlined,
                selected: _feedback == _AssistantFeedback.helpful,
                onPressed: () =>
                    _setAssistantFeedback(context, _AssistantFeedback.helpful),
              ),
              _AssistantActionButton(
                tooltip: 'Mark needs work',
                icon: StudioIcons.thumbDownAltOutlined,
                selected: _feedback == _AssistantFeedback.needsWork,
                onPressed: () => _setAssistantFeedback(
                  context,
                  _AssistantFeedback.needsWork,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _setAssistantFeedback(BuildContext context, _AssistantFeedback next) {
    setState(() => _feedback = next);
    _showQuietSnack(
      context,
      next == _AssistantFeedback.helpful
          ? 'Marked helpful'
          : 'Marked needs work',
    );
  }

  void _showQuietSnack(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1100),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

/// Keeps an active response responsive without repeatedly parsing and laying
/// out an ever-growing Markdown document. Frozen chunks are ordinary text only
/// while a response is active; the complete, correctly formatted Markdown is
/// rendered as soon as the turn finalizes. This also bounds pathological
/// unbroken streamed content to a small mutable tail.
class _StreamingAssistantText extends StatefulWidget {
  static const activationCharacterLimit = 1024;

  final String text;
  final ThemeTokens tokens;

  const _StreamingAssistantText({required this.text, required this.tokens});

  @override
  State<_StreamingAssistantText> createState() =>
      _StreamingAssistantTextState();

  static bool shouldUseChunkedRendering(String text) =>
      text.length > activationCharacterLimit;
}

class _StreamingAssistantTextState extends State<_StreamingAssistantText> {
  static const _tailCharacterLimit = 768;
  static const _frozenChunkCharacterTarget = 640;

  final List<String> _frozenChunks = [];
  String _observedText = '';
  String _tail = '';

  @override
  void initState() {
    super.initState();
    _replace(widget.text);
  }

  @override
  void didUpdateWidget(covariant _StreamingAssistantText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text == _observedText) return;
    if (widget.text.startsWith(_observedText)) {
      _tail += widget.text.substring(_observedText.length);
      _observedText = widget.text;
      _freezeStableTailPrefix();
      return;
    }
    _replace(widget.text);
  }

  void _replace(String value) {
    _frozenChunks.clear();
    _tail = value;
    _observedText = value;
    _freezeStableTailPrefix();
  }

  void _freezeStableTailPrefix() {
    while (_tail.length > _tailCharacterLimit) {
      final surplus = _tail.length - _tailCharacterLimit;
      final target = math.min(_frozenChunkCharacterTarget, surplus);
      final cut = _preferredCut(_tail, target);
      _frozenChunks.add(_tail.substring(0, cut));
      _tail = _tail.substring(cut);
    }
  }

  int _preferredCut(String value, int target) {
    for (var index = target; index > target ~/ 2; index--) {
      final codeUnit = value.codeUnitAt(index - 1);
      if (codeUnit == 0x20 ||
          codeUnit == 0x0a ||
          codeUnit == 0x09 ||
          codeUnit == 0x0d) {
        return index;
      }
    }
    // Some providers can stream a very long token without whitespace. Keep
    // that exceptional content bounded rather than forcing one giant layout.
    return target;
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: widget.tokens.textPrimary,
      fontSize: FontSizes.md,
      height: 1.48,
    );
    return Column(
      key: const ValueKey('studio-streaming-assistant-text'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < _frozenChunks.length; index++)
          RepaintBoundary(
            key: ValueKey('studio-streaming-frozen-$index'),
            child: Text(_frozenChunks[index], style: style, softWrap: true),
          ),
        Text(
          _tail,
          key: const ValueKey('studio-streaming-tail'),
          style: style,
          softWrap: true,
        ),
      ],
    );
  }
}

bool _assistantNeedsReviewWidth(String markdown) {
  if (RegExp(r'(^|\n)\s*```').hasMatch(markdown)) return true;

  var tableRows = 0;
  for (final line in markdown.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.contains('|') && trimmed.split('|').length >= 3) {
      tableRows++;
      if (tableRows >= 2) return true;
    } else if (tableRows > 0) {
      tableRows = 0;
    }
  }
  return false;
}

class _AssistantActionButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  const _AssistantActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return StudioChromeIconButton(
      tooltip: tooltip,
      icon: icon,
      iconSize: 12,
      width: 24,
      height: 24,
      active: selected,
      onTap: onPressed,
    );
  }
}
