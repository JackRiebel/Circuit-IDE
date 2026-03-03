import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/logger.dart';

class ProjectRule {
  final String name;
  final String content;
  final String filePath;
  final List<String> patterns;

  const ProjectRule({
    required this.name,
    required this.content,
    required this.filePath,
    this.patterns = const [],
  });
}

class RulesLoader {
  /// Load all project rules from `.circuit/rules/` in the given directory.
  static Future<List<ProjectRule>> loadRules(String workingDir) async {
    final rulesDir = Directory(p.join(workingDir, '.circuit', 'rules'));
    if (!await rulesDir.exists()) return [];

    final rules = <ProjectRule>[];

    try {
      await for (final entity in rulesDir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.endsWith('.md')) continue;

        try {
          final rawContent = await entity.readAsString();
          if (rawContent.trim().isNotEmpty) {
            final parsed = _parseFrontmatter(rawContent.trim());
            rules.add(ProjectRule(
              name: name.replaceAll('.md', ''),
              content: parsed.content,
              filePath: entity.path,
              patterns: parsed.patterns,
            ));
          }
        } catch (e) {
          Logger.warning('Could not read rule file $name: $e', 'Rules');
        }
      }
    } catch (e) {
      Logger.warning('Could not list rules directory: $e', 'Rules');
    }

    rules.sort((a, b) => a.name.compareTo(b.name));
    return rules;
  }

  /// Format rules into a system prompt section.
  static String formatRulesPrompt(List<ProjectRule> rules) {
    if (rules.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('\n\n## Project Rules\n');
    buffer.writeln(
        'The following project-specific rules MUST be followed:\n');

    for (final rule in rules) {
      buffer.writeln('### ${rule.name}\n');
      buffer.writeln(rule.content);
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Create the rules directory and an example rule file.
  static Future<void> initRulesDir(String workingDir) async {
    final rulesDir = Directory(p.join(workingDir, '.circuit', 'rules'));
    if (!await rulesDir.exists()) {
      await rulesDir.create(recursive: true);
    }
  }

  /// Save a rule file, including optional patterns as YAML frontmatter.
  static Future<void> saveRule(
    String workingDir,
    String name,
    String content, {
    List<String> patterns = const [],
  }) async {
    final rulesDir = Directory(p.join(workingDir, '.circuit', 'rules'));
    if (!await rulesDir.exists()) {
      await rulesDir.create(recursive: true);
    }

    final buffer = StringBuffer();
    if (patterns.isNotEmpty) {
      buffer.writeln('---');
      buffer.writeln('patterns:');
      for (final pattern in patterns) {
        buffer.writeln('  - "$pattern"');
      }
      buffer.writeln('---');
    }
    buffer.write(content);

    final file = File(p.join(rulesDir.path, '$name.md'));
    await file.writeAsString(buffer.toString());
  }

  /// Delete a rule file.
  static Future<void> deleteRule(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Parse YAML frontmatter from a rule file.
  /// Returns the content body and any patterns defined in the frontmatter.
  static _ParsedRule _parseFrontmatter(String raw) {
    if (!raw.startsWith('---')) {
      return _ParsedRule(content: raw, patterns: []);
    }

    final endIndex = raw.indexOf('---', 3);
    if (endIndex == -1) {
      return _ParsedRule(content: raw, patterns: []);
    }

    final frontmatter = raw.substring(3, endIndex).trim();
    final body = raw.substring(endIndex + 3).trim();

    // Simple YAML parsing for patterns list
    final patterns = <String>[];
    final patternRegex = RegExp(r"""^\s*-\s*["']?(.+?)["']?\s*$""", multiLine: true);
    bool inPatterns = false;

    for (final line in frontmatter.split('\n')) {
      if (line.trim().startsWith('patterns:')) {
        inPatterns = true;
        continue;
      }
      if (inPatterns) {
        final match = patternRegex.firstMatch(line);
        if (match != null) {
          patterns.add(match.group(1)!);
        } else if (line.trim().isNotEmpty && !line.startsWith(' ') && !line.startsWith('\t')) {
          inPatterns = false;
        }
      }
    }

    return _ParsedRule(content: body, patterns: patterns);
  }
}

class _ParsedRule {
  final String content;
  final List<String> patterns;
  const _ParsedRule({required this.content, required this.patterns});
}
