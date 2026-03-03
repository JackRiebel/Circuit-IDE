import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
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

import '../../models/editor_state.dart';
import '../../state/editor_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme/syntax_theme.dart';

class CodeEditorWidget extends ConsumerStatefulWidget {
  final EditorTab tab;
  final int tabIndex;
  final CodeScrollController? scrollController;

  const CodeEditorWidget({
    super.key,
    required this.tab,
    required this.tabIndex,
    this.scrollController,
  });

  @override
  ConsumerState<CodeEditorWidget> createState() => _CodeEditorWidgetState();
}

class _CodeEditorWidgetState extends ConsumerState<CodeEditorWidget> {
  late CodeLineEditingController _controller;
  late CodeFindController _findController;

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController.fromText(widget.tab.content);
    _findController = CodeFindController(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    _findController.dispose();
    super.dispose();
  }

  Mode? _getLanguageMode(String language) {
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
      'xml' || 'html' => langXml,
      'sql' => langSql,
      'go' => langGo,
      'rust' => langRust,
      'java' || 'kotlin' => langJava,
      'cpp' || 'c' => langCpp,
      'ruby' => langRuby,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final syntaxTheme = SyntaxTheme.fromThemeTokens(tokens);
    final editorState = ref.watch(editorProvider);

    final mode = _getLanguageMode(widget.tab.language);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          ref.read(editorProvider.notifier).saveActiveFile();
        },
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
          _findController.findMode();
        },
      },
      child: Focus(
        child: CodeEditor(
          controller: _controller,
          findController: _findController,
          scrollController: widget.scrollController,
          indicatorBuilder: (context, editingController, chunkController, notifier) {
            return Row(
              children: [
                DefaultCodeLineNumber(
                  controller: editingController,
                  notifier: notifier,
                  textStyle: TextStyle(
                    color: tokens.textMuted.withValues(alpha: 0.5),
                    fontSize: editorState.fontSize,
                    fontFamily: 'JetBrains Mono',
                  ),
                  focusedTextStyle: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: editorState.fontSize,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
                DefaultCodeChunkIndicator(
                  width: 20,
                  controller: chunkController,
                  notifier: notifier,
                ),
              ],
            );
          },
          style: CodeEditorStyle(
            fontSize: editorState.fontSize,
            fontFamily: 'JetBrains Mono',
            codeTheme: CodeHighlightTheme(
              languages: {
                if (mode != null)
                  widget.tab.language: CodeHighlightThemeMode(mode: mode),
              },
              theme: _buildHighlightTheme(syntaxTheme, tokens),
            ),
            backgroundColor: tokens.editorBg,
            textColor: tokens.textPrimary,
            cursorColor: tokens.editorCursor,
            selectionColor: tokens.editorSelection,
            cursorLineColor: tokens.editorLineHighlight,
          ),
          wordWrap: editorState.wordWrap,
          readOnly: false,
          onChanged: (value) {
            ref.read(editorProvider.notifier).updateContent(
                  widget.tabIndex,
                  _controller.text,
                );
          },
        ),
      ),
    );
  }

  Map<String, TextStyle> _buildHighlightTheme(
    SyntaxTheme syntax,
    dynamic tokens,
  ) {
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
      'params': TextStyle(color: syntax.variable),
      'variable': TextStyle(color: syntax.variable),
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
      'regexp': TextStyle(color: syntax.string),
      'symbol': TextStyle(color: syntax.constant),
    };
  }
}
