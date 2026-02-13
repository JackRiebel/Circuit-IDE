import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/logger.dart';

class ProjectRule {
  final String name;
  final String content;
  final String filePath;

  const ProjectRule({
    required this.name,
    required this.content,
    required this.filePath,
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
          final content = await entity.readAsString();
          if (content.trim().isNotEmpty) {
            rules.add(ProjectRule(
              name: name.replaceAll('.md', ''),
              content: content.trim(),
              filePath: entity.path,
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

  /// Save a rule file.
  static Future<void> saveRule(
    String workingDir,
    String name,
    String content,
  ) async {
    final rulesDir = Directory(p.join(workingDir, '.circuit', 'rules'));
    if (!await rulesDir.exists()) {
      await rulesDir.create(recursive: true);
    }
    final file = File(p.join(rulesDir.path, '$name.md'));
    await file.writeAsString(content);
  }

  /// Delete a rule file.
  static Future<void> deleteRule(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
