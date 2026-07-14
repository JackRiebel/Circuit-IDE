import 'dart:io';

class GitTools {
  final String workingDir;

  GitTools({required this.workingDir});

  Future<(bool, String)> _runGit(List<String> args, {int timeout = 30}) async {
    try {
      final result = await Process.run(
        'git',
        args,
        workingDirectory: workingDir,
      ).timeout(Duration(seconds: timeout));

      final stdout = (result.stdout as String).trim();
      final stderr = (result.stderr as String).trim();

      if (result.exitCode != 0) {
        return (false, stderr.isNotEmpty ? stderr : stdout);
      }
      return (true, stdout);
    } on ProcessException catch (e) {
      return (false, 'Git error: ${e.message}');
    } catch (e) {
      return (false, 'Error: $e');
    }
  }

  Future<String> gitStatus(Map<String, dynamic> args) async {
    final (success, output) = await _runGit(['status', '--short', '-b']);
    if (!success) return 'Error: $output';
    return output.isEmpty ? 'Working tree clean' : output;
  }

  Future<String> gitDiff(Map<String, dynamic> args) async {
    final gitArgs = ['diff'];
    if (args['cached'] == true) gitArgs.add('--cached');
    if (args['commit'] is String) gitArgs.add(args['commit'] as String);

    final (success, output) = await _runGit(gitArgs);
    if (!success) return 'Error: $output';
    return output.isEmpty ? 'No changes' : output;
  }

  Future<String> gitLog(Map<String, dynamic> args) async {
    final count = args['count'] as int? ?? 10;
    final (success, output) = await _runGit([
      'log',
      '--oneline',
      '--graph',
      '-$count',
    ]);
    if (!success) return 'Error: $output';
    return output.isEmpty ? 'No commits' : output;
  }

  Future<String> gitCommit(Map<String, dynamic> args) async {
    final message = args['message'] as String;
    final files = (args['files'] as List<dynamic>?)?.cast<String>() ?? [];

    // Stage files
    if (files.isEmpty) {
      final (ok, err) = await _runGit(['add', '-A']);
      if (!ok) return 'Error staging files: $err';
    } else {
      for (final file in files) {
        final (ok, err) = await _runGit(['add', file]);
        if (!ok) return 'Error staging $file: $err';
      }
    }

    // Commit
    final (success, output) = await _runGit(['commit', '-m', message]);
    if (!success) return 'Error: $output';
    return 'Committed: $output';
  }

  Future<String> gitBranch(Map<String, dynamic> args) async {
    final action = args['action'] as String;
    final name = args['name'] as String?;

    switch (action) {
      case 'list':
        final (ok, output) = await _runGit(['branch', '-a']);
        return ok ? output : 'Error: $output';

      case 'create':
        if (name == null) return 'Error: Branch name required';
        final (ok, output) = await _runGit(['checkout', '-b', name]);
        return ok ? 'Created and switched to branch: $name' : 'Error: $output';

      case 'switch':
        if (name == null) return 'Error: Branch name required';
        final (ok, output) = await _runGit(['checkout', name]);
        return ok ? 'Switched to branch: $name' : 'Error: $output';

      case 'delete':
        if (name == null) return 'Error: Branch name required';
        final (ok, output) = await _runGit(['branch', '-d', name]);
        return ok ? 'Deleted branch: $name' : 'Error: $output';

      default:
        return 'Unknown branch action: $action';
    }
  }
}
