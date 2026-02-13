import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/re_highlight.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';
import '../../theme/syntax_theme.dart';

class CodeBlockWidget extends ConsumerStatefulWidget {
  final String code;
  final String? language;

  const CodeBlockWidget({
    super.key,
    required this.code,
    this.language,
  });

  @override
  ConsumerState<CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends ConsumerState<CodeBlockWidget> {
  bool _copied = false;

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final syntaxTheme = SyntaxTheme.fromThemeTokens(tokens);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: Spacing.sm),
      decoration: BoxDecoration(
        color: tokens.codeBlockBg,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.codeBlockBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with language badge and copy button
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: Spacing.sm,
            ),
            decoration: BoxDecoration(
              color: tokens.codeBlockBorder.withValues(alpha: 0.15),
              border: Border(
                bottom: BorderSide(color: tokens.codeBlockBorder),
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(Radii.md),
                topRight: Radius.circular(Radii.md),
              ),
            ),
            child: Row(
              children: [
                if (widget.language != null && widget.language!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(Radii.xs),
                    ),
                    child: Text(
                      widget.language!,
                      style: TextStyle(
                        color: tokens.accent,
                        fontSize: FontSizes.xxs,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const Spacer(),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _copyToClipboard,
                    child: AnimatedSwitcher(
                      duration: AnimationDurations.fast,
                      child: _copied
                          ? Row(
                              key: const ValueKey('copied'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check, size: 12, color: tokens.success),
                                const SizedBox(width: 4),
                                Text(
                                  'Copied!',
                                  style: TextStyle(
                                    color: tokens.success,
                                    fontSize: FontSizes.xs,
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              key: const ValueKey('copy'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.copy, size: 12, color: tokens.textMuted),
                                const SizedBox(width: 4),
                                Text(
                                  'Copy',
                                  style: TextStyle(
                                    color: tokens.textMuted,
                                    fontSize: FontSizes.xs,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Syntax-highlighted code content
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: SelectableText.rich(
              buildHighlightedCode(widget.code, widget.language, syntaxTheme, tokens),
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: FontSizes.sm,
                fontFamily: 'JetBrains Mono',
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Build syntax-highlighted TextSpan from code using re_highlight
TextSpan buildHighlightedCode(
  String code,
  String? language,
  SyntaxTheme syntaxTheme,
  dynamic tokens,
) {
  final baseStyle = TextStyle(
    color: tokens.textPrimary,
    fontSize: FontSizes.sm,
    fontFamily: 'JetBrains Mono',
    height: 1.5,
  );

  final normalizedLang = _normalizeLanguage(language);
  final mode = _getLanguageMode(normalizedLang);
  if (mode == null || normalizedLang == null) {
    return TextSpan(text: code, style: baseStyle);
  }

  try {
    final highlight = Highlight();
    highlight.registerLanguage(normalizedLang, mode);
    final result = highlight.highlight(code: code, language: normalizedLang);
    final themeMap = _buildThemeMap(syntaxTheme);
    final renderer = TextSpanRenderer(baseStyle, themeMap);
    result.render(renderer);
    return renderer.span ?? TextSpan(text: code, style: baseStyle);
  } catch (_) {
    return TextSpan(text: code, style: baseStyle);
  }
}

/// Normalize language aliases to canonical names
String? _normalizeLanguage(String? language) {
  if (language == null || language.isEmpty) return null;
  return switch (language.toLowerCase()) {
    'dart' => 'dart',
    'python' || 'py' => 'python',
    'javascript' || 'js' => 'javascript',
    'typescript' || 'ts' => 'typescript',
    'json' => 'json',
    'yaml' || 'yml' => 'yaml',
    'markdown' || 'md' => 'markdown',
    'bash' || 'sh' || 'shell' || 'zsh' => 'bash',
    'css' => 'css',
    'xml' || 'html' || 'htm' || 'svg' => 'xml',
    'sql' => 'sql',
    'go' || 'golang' => 'go',
    'rust' || 'rs' => 'rust',
    'java' || 'kotlin' || 'kt' => 'java',
    'cpp' || 'c' || 'c++' || 'cc' || 'h' || 'hpp' => 'cpp',
    'ruby' || 'rb' => 'ruby',
    _ => null,
  };
}

Mode? _getLanguageMode(String? language) {
  if (language == null) return null;
  return switch (language) {
    'dart' => langDart,
    'python' => langPython,
    'javascript' => langJavascript,
    'typescript' => langTypescript,
    'json' => langJson,
    'yaml' => langYaml,
    'markdown' => langMarkdown,
    'bash' => langBash,
    'css' => langCss,
    'xml' => langXml,
    'sql' => langSql,
    'go' => langGo,
    'rust' => langRust,
    'java' => langJava,
    'cpp' => langCpp,
    'ruby' => langRuby,
    _ => null,
  };
}

Map<String, TextStyle> _buildThemeMap(SyntaxTheme syntax) {
  return {
    'keyword': TextStyle(color: syntax.keyword, fontWeight: FontWeight.bold),
    'built_in': TextStyle(color: syntax.type),
    'type': TextStyle(color: syntax.type),
    'literal': TextStyle(color: syntax.constant),
    'number': TextStyle(color: syntax.number),
    'string': TextStyle(color: syntax.string),
    'comment': TextStyle(color: syntax.comment, fontStyle: FontStyle.italic),
    'doctag': TextStyle(color: syntax.comment),
    'function': TextStyle(color: syntax.function),
    'title': TextStyle(color: syntax.function),
    'title.function': TextStyle(color: syntax.function),
    'title.class': TextStyle(color: syntax.type),
    'params': TextStyle(color: syntax.variable),
    'variable': TextStyle(color: syntax.variable),
    'variable.language': TextStyle(color: syntax.keyword),
    'attr': TextStyle(color: syntax.attribute),
    'attribute': TextStyle(color: syntax.attribute),
    'tag': TextStyle(color: syntax.tag),
    'name': TextStyle(color: syntax.tag),
    'selector-tag': TextStyle(color: syntax.tag),
    'selector-class': TextStyle(color: syntax.type),
    'selector-id': TextStyle(color: syntax.type),
    'operator': TextStyle(color: syntax.operator),
    'punctuation': TextStyle(color: syntax.punctuation),
    'meta': TextStyle(color: syntax.comment),
    'meta keyword': TextStyle(color: syntax.keyword),
    'meta string': TextStyle(color: syntax.string),
    'regexp': TextStyle(color: syntax.string),
    'symbol': TextStyle(color: syntax.constant),
    'section': TextStyle(color: syntax.function),
    'subst': TextStyle(color: syntax.variable),
    'template-variable': TextStyle(color: syntax.variable),
    'addition': TextStyle(color: syntax.string),
    'deletion': TextStyle(color: syntax.tag),
  };
}
