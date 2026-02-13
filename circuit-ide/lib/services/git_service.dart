import 'dart:io';

class GitService {
  final String workingDir;

  GitService({required this.workingDir});

  Future<(bool, String)> run(List<String> args, {int timeout = 30}) async {
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
    } catch (e) {
      return (false, e.toString());
    }
  }

  Future<bool> isGitRepo() async {
    final (ok, _) = await run(['rev-parse', '--git-dir']);
    return ok;
  }

  Future<String?> getCurrentBranch() async {
    final (ok, output) = await run(['branch', '--show-current']);
    return ok ? output : null;
  }

  Future<String?> getRemoteUrl() async {
    final (ok, output) = await run(['remote', 'get-url', 'origin']);
    return ok ? output : null;
  }
}
