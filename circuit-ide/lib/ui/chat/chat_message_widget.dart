import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/design_tokens.dart';
import '../../enums/message_role.dart';
import '../../models/chat_message.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';
import 'code_block_widget.dart';
import 'tool_call_widget.dart';

class ChatMessageWidget extends ConsumerWidget {
  final ChatMessage message;

  const ChatMessageWidget({super.key, required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    if (message.role == MessageRole.system ||
        message.role == MessageRole.tool) {
      return const SizedBox.shrink();
    }

    final isUser = message.role == MessageRole.user;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.xs,
      ),
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: isUser ? tokens.userMsgBg : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: isUser
            ? Border.all(color: tokens.border.withValues(alpha: 0.3))
            : Border(
                left: BorderSide(
                  color: tokens.accent.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Role label
          Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  color: isUser
                      ? tokens.accent.withValues(alpha: 0.1)
                      : tokens.success.withValues(alpha: 0.1),
                ),
                child: Icon(
                  isUser ? Icons.person_outline : Icons.auto_awesome,
                  size: 11,
                  color: isUser ? tokens.accent : tokens.success,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isUser ? 'You' : 'CircuitCode',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                _formatTime(message.timestamp),
                style: TextStyle(
                  color: tokens.textDisabled,
                  fontSize: FontSizes.xxs,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),

          // Content
          if (message.content.isNotEmpty)
            isUser
                ? SelectableText(
                    message.content,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.md,
                      height: 1.5,
                    ),
                  )
                : MarkdownWidget(
                    data: message.content,
                    shrinkWrap: true,
                    config: buildChatMarkdownConfig(tokens),
                  ),

          // Tool calls
          if (message.toolCalls.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            ...message.toolCalls.map(
              (tc) => ToolCallWidget(toolCall: tc),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Shared markdown config for chat messages and streaming indicator
MarkdownConfig buildChatMarkdownConfig(ThemeTokens tokens) {
  return MarkdownConfig(
    configs: [
      PConfig(textStyle: TextStyle(
        color: tokens.textPrimary,
        fontSize: FontSizes.md,
        height: 1.6,
      )),
      // Fenced code blocks — use our custom CodeBlockWidget
      PreConfig(
        builder: (code, language) => CodeBlockWidget(
          code: code.trimRight(),
          language: language.isNotEmpty ? language : null,
        ),
      ),
      // Inline code
      CodeConfig(style: TextStyle(
        color: tokens.accent,
        fontSize: FontSizes.sm,
        fontFamily: 'JetBrains Mono',
        backgroundColor: tokens.accent.withValues(alpha: 0.08),
      )),
      // Headings
      H1Config(style: TextStyle(
        color: tokens.textPrimary,
        fontSize: FontSizes.xxl,
        fontWeight: FontWeight.bold,
        height: 1.4,
      )),
      H2Config(style: TextStyle(
        color: tokens.textPrimary,
        fontSize: FontSizes.xl,
        fontWeight: FontWeight.w600,
        height: 1.4,
      )),
      H3Config(style: TextStyle(
        color: tokens.textPrimary,
        fontSize: FontSizes.lg,
        fontWeight: FontWeight.w600,
        height: 1.4,
      )),
      // Links
      LinkConfig(
        style: TextStyle(
          color: tokens.accent,
          decoration: TextDecoration.underline,
          decorationColor: tokens.accent.withValues(alpha: 0.4),
        ),
        onTap: (url) {
          final uri = Uri.tryParse(url);
          if (uri != null) launchUrl(uri);
        },
      ),
      // Blockquotes
      BlockquoteConfig(
        sideColor: tokens.accent.withValues(alpha: 0.4),
        textColor: tokens.textSecondary,
      ),
    ],
  );
}
