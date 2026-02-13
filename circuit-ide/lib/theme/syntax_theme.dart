import 'package:flutter/material.dart';

import 'theme_tokens.dart';

class SyntaxTheme {
  final Color keyword;
  final Color string;
  final Color number;
  final Color comment;
  final Color type;
  final Color function;
  final Color variable;
  final Color operator;
  final Color punctuation;
  final Color constant;
  final Color tag;
  final Color attribute;

  const SyntaxTheme({
    required this.keyword,
    required this.string,
    required this.number,
    required this.comment,
    required this.type,
    required this.function,
    required this.variable,
    required this.operator,
    required this.punctuation,
    required this.constant,
    required this.tag,
    required this.attribute,
  });

  static SyntaxTheme fromThemeTokens(ThemeTokens tokens) {
    if (tokens.brightness == Brightness.light) {
      return const SyntaxTheme(
        keyword: Color(0xFFAF00DB),
        string: Color(0xFFA31515),
        number: Color(0xFF098658),
        comment: Color(0xFF008000),
        type: Color(0xFF267F99),
        function: Color(0xFF795E26),
        variable: Color(0xFF001080),
        operator: Color(0xFF000000),
        punctuation: Color(0xFF000000),
        constant: Color(0xFF0000FF),
        tag: Color(0xFF800000),
        attribute: Color(0xFFFF0000),
      );
    }

    return const SyntaxTheme(
      keyword: Color(0xFF569CD6),
      string: Color(0xFFCE9178),
      number: Color(0xFFB5CEA8),
      comment: Color(0xFF6A9955),
      type: Color(0xFF4EC9B0),
      function: Color(0xFFDCDCAA),
      variable: Color(0xFF9CDCFE),
      operator: Color(0xFFD4D4D4),
      punctuation: Color(0xFFD4D4D4),
      constant: Color(0xFF4FC1FF),
      tag: Color(0xFF569CD6),
      attribute: Color(0xFF9CDCFE),
    );
  }
}
