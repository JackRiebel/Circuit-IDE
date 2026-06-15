import 'dart:io';

import 'package:circuit_ide/agent/config/config.dart';
import 'package:circuit_ide/agent/security/agent_tool_permission_policy.dart';
import 'package:circuit_ide/agent/tools/tool_registry.dart';
import 'package:circuit_ide/enums/message_role.dart';
import 'package:circuit_ide/models/agent_tool_permission.dart';
import 'package:circuit_ide/models/context_pack.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/tool_call_info.dart';
import 'package:circuit_ide/state/context_pack_provider.dart';
import 'package:circuit_ide/state/editor_provider.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/project_profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('default system prompt is workspace-scoped and review-first', () async {
    final root = await Directory.systemTemp.createTemp('agent_prompt_');
    addTearDown(() => _delete(root));

    final prompt = await AgentConfig(workingDir: root.path).loadSystemPrompt();

    expect(prompt, contains('selected workspace directory'));
    expect(prompt, contains('Prefer patch proposals'));
    expect(prompt, isNot(contains('FULL file system access')));
    expect(prompt, isNot(contains('NOT in a sandboxed')));
  });

  test('tool modes expose only the expected backend capabilities', () {
    final askTools = ToolRegistry.toolsForMode(
      AgentToolMode.ask,
    ).map((tool) => tool.name);
    final planTools = ToolRegistry.toolsForMode(
      AgentToolMode.plan,
    ).map((tool) => tool.name);
    final codeTools = ToolRegistry.toolsForMode(
      AgentToolMode.code,
    ).map((tool) => tool.name);
    final reviewTools = ToolRegistry.toolsForMode(
      AgentToolMode.review,
    ).map((tool) => tool.name);

    expect(askTools, contains('read_file'));
    expect(askTools, isNot(contains('write_file')));
    expect(askTools, isNot(contains('run_command')));
    expect(planTools, contains('propose_patch'));
    expect(planTools, contains('read_file'));
    expect(planTools, isNot(contains('write_file')));
    expect(planTools, isNot(contains('run_command')));
    expect(codeTools, contains('propose_patch'));
    expect(codeTools, contains('run_command'));
    expect(codeTools, isNot(contains('write_file')));
    expect(codeTools, isNot(contains('edit_file')));
    expect(reviewTools, contains('git_diff'));
    expect(reviewTools, isNot(contains('edit_file')));
  });

  test('permission policy blocks unsafe actions and reviews mutations', () {
    const root = '/tmp/circuit-policy-root';
    const policy = AgentToolPermissionPolicy(workingDir: root);

    final read = policy.evaluate(
      const ToolCallInfo(
        id: 'read',
        name: 'read_file',
        arguments: {'path': 'lib/main.dart'},
      ),
    );
    final outside = policy.evaluate(
      const ToolCallInfo(
        id: 'outside',
        name: 'read_file',
        arguments: {'path': '../secret.txt'},
      ),
    );
    final branchDelete = policy.evaluate(
      const ToolCallInfo(
        id: 'branch',
        name: 'git_branch',
        arguments: {'action': 'delete', 'name': 'main'},
      ),
    );
    final dangerous = policy.evaluate(
      const ToolCallInfo(
        id: 'cmd',
        name: 'run_command',
        arguments: {'command': 'rm -rf /'},
      ),
    );
    final mcp = policy.evaluate(
      const ToolCallInfo(
        id: 'mcp',
        name: 'mcp_ticket_update',
        arguments: {'ticket': 'ABC-1'},
      ),
    );

    expect(read.verdict, ToolPermissionVerdict.allow);
    expect(read.isReadOnly, isTrue);
    expect(outside.verdict, ToolPermissionVerdict.deny);
    expect(branchDelete.verdict, ToolPermissionVerdict.ask);
    expect(dangerous.verdict, ToolPermissionVerdict.deny);
    expect(mcp.verdict, ToolPermissionVerdict.ask);
  });

  test(
    'context pack includes active file content, scripts, and instructions',
    () async {
      final root = await Directory.systemTemp.createTemp('context_v2_');
      addTearDown(() => _delete(root));
      await File(
        p.join(root.path, 'package.json'),
      ).writeAsString('{"scripts":{"test":"npm test","lint":"eslint ."}}');
      await File(p.join(root.path, 'AGENTS.md')).writeAsString(
        'Use small focused changes. <!-- private maintainer note -->',
      );
      await File(
        p.join(root.path, 'main.js'),
      ).writeAsString('console.log("hello circuit");\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      await container.read(projectProfileProvider.notifier).refresh();
      await container
          .read(editorProvider.notifier)
          .openFile(p.join(root.path, 'main.js'));

      final pack = container
          .read(contextPackProvider.notifier)
          .buildForCodingTask(prompt: 'review startup');
      final prompt = pack.serializePrompt();

      expect(prompt, contains('console.log("hello circuit")'));
      expect(prompt, contains('test: npm test'));
      expect(prompt, contains('Use small focused changes.'));
      expect(prompt, isNot(contains('private maintainer note')));
      expect(
        pack.visibleItems.map((item) => item.type),
        contains(ContextPackItemType.activeFile),
      );
    },
  );

  test('context pack includes explicitly mentioned file contents', () async {
    final root = await Directory.systemTemp.createTemp('context_mentions_');
    addTearDown(() => _delete(root));
    await File(
      p.join(root.path, 'README.md'),
    ).writeAsString('# Circuit Test\n\nImportant setup notes.');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(fileTreeProvider.notifier).openDirectory(root.path);
    await container.read(projectProfileProvider.notifier).refresh();

    final pack = container
        .read(contextPackProvider.notifier)
        .buildForCodingTask(prompt: 'Please review README.md before planning');

    expect(pack.serializePrompt(), contains('Important setup notes.'));
    expect(
      pack.visibleItems
          .where((item) => item.type == ContextPackItemType.mentionedFile)
          .map((item) => item.source),
      contains('README.md'),
    );
  });

  test('studio thread messages convert to isolated chat history', () {
    final now = DateTime(2026);
    final thread = StudioThread(
      id: 'thread',
      title: 'Thread',
      messages: [
        StudioThreadMessage(
          id: 'u1',
          role: MessageRole.user,
          content: 'project-specific question',
          timestamp: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    final history = thread.messages
        .map((message) => message.toChatMessage())
        .toList(growable: false);

    expect(history, hasLength(1));
    expect(history.single.content, 'project-specific question');
    expect(history.single.role, MessageRole.user);
  });
}

Future<void> _delete(Directory directory) async {
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
}
