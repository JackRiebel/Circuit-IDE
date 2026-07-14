import '../models/tool_call_info.dart';

class StudioRequestToolActivity {
  final String title;
  final String detail;

  const StudioRequestToolActivity(this.title, this.detail);
}

StudioRequestToolActivity describeStudioRequestToolActivity(
  ToolCallInfo? tool, {
  required bool running,
  bool failed = false,
}) {
  if (tool == null) {
    return StudioRequestToolActivity(
      failed
          ? 'Tool failed'
          : running
          ? 'Using tool'
          : 'Used tool',
      failed
          ? 'failed'
          : running
          ? 'running'
          : 'completed',
    );
  }
  final action = failed
      ? _failedToolTitle(tool.name)
      : running
      ? _runningToolTitle(tool.name)
      : _completedToolTitle(tool.name);
  return StudioRequestToolActivity(action, _toolDetail(tool, failed: failed));
}

String? studioRequestToolPath(ToolCallInfo tool) {
  final value =
      tool.arguments['path'] ??
      tool.arguments['file'] ??
      tool.arguments['directory'];
  return value is String && value.trim().isNotEmpty ? value : null;
}

String _runningToolTitle(String name) => switch (name) {
  'read_file' => 'Reading file',
  'list_files' => 'Listing files',
  'search_files' => 'Searching files',
  'git_status' => 'Checking git status',
  'git_diff' => 'Reviewing diff',
  'run_command' => 'Running command',
  'write_file' || 'edit_file' => 'Editing file',
  'propose_patch' => 'Preparing changes',
  _ => 'Using ${_prettyToolName(name)}',
};

String _completedToolTitle(String name) => switch (name) {
  'read_file' => 'Read file',
  'list_files' => 'Listed files',
  'search_files' => 'Searched files',
  'git_status' => 'Checked git status',
  'git_diff' => 'Reviewed diff',
  'run_command' => 'Ran command',
  'write_file' || 'edit_file' => 'Edited file',
  'propose_patch' => 'Prepared changes',
  _ => 'Used ${_prettyToolName(name)}',
};

String _failedToolTitle(String name) => switch (name) {
  'run_command' => 'Command failed',
  'write_file' || 'edit_file' => 'Edit failed',
  _ => '${_prettyToolName(name)} failed',
};

String _toolDetail(ToolCallInfo tool, {required bool failed}) {
  final args = tool.arguments;
  final status = failed ? 'failed' : tool.status.name;
  final path = studioRequestToolPath(tool);
  if (path != null) return '$path · $status';
  if (tool.name == 'run_command') {
    return '${args['command'] ?? 'command'} · $status';
  }
  if (tool.name == 'search_files') {
    return '${args['query'] ?? 'search'} · $status';
  }
  if (tool.name == 'propose_patch') {
    return '${args['title'] ?? 'Patch proposal'} · $status';
  }
  return status;
}

String _prettyToolName(String name) => name.replaceAll('_', ' ');
