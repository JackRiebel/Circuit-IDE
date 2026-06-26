import 'package:circuit_ide/agent/mcp/mcp_client.dart';
import 'package:circuit_ide/agent/tools/tool_executor.dart';
import 'package:circuit_ide/models/agent_tool_permission.dart';
import 'package:circuit_ide/models/tool_call_info.dart';
import 'package:circuit_ide/models/tool_result_envelope.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MCP client dispatch guard', () {
    test(
      'blocks mutation-looking direct calls before server dispatch',
      () async {
        final client = McpClient();

        final result = await client.callToolOnServer('jira', 'update_issue', {
          'issue': 'ABC-1',
        });

        expect(result, contains('MCP tool blocked'));
        expect(result, contains('MCP mutation'));
      },
    );

    test(
      'blocks network-looking direct calls before server dispatch',
      () async {
        final client = McpClient();

        final result = await client.callToolOnServer('browser', 'get_status', {
          'target': 'https://example.com/status',
        });

        expect(result, contains('MCP tool blocked'));
        expect(result, contains('network tools'));
      },
    );

    test(
      'blocks network-looking server names before direct dispatch',
      () async {
        final client = McpClient();

        final result = await client.callToolOnServer('browser', 'get_status', {
          'page': 'current',
        });

        expect(result, contains('MCP tool blocked'));
        expect(result, contains('network tools'));
      },
    );

    test('blocks embedded URL arguments before direct dispatch', () async {
      final client = McpClient();

      final result = await client.callToolOnServer('status', 'get_status', {
        'query': 'check https://example.com/status before returning',
      });

      expect(result, contains('MCP tool blocked'));
      expect(result, contains('network tools'));
    });

    test('blocks network-key host arguments before direct dispatch', () async {
      final client = McpClient();

      final result = await client.callToolOnServer('status', 'get_status', {
        'endpoint': 'api.example.com',
      });

      expect(result, contains('MCP tool blocked'));
      expect(result, contains('network tools'));
    });

    test('blocks unknown-risk direct calls before server dispatch', () async {
      final client = McpClient();

      final result = await client.callTool('magic', {'input': 'value'});

      expect(result, contains('MCP tool blocked'));
      expect(result, contains('Unknown MCP tools'));
    });

    test('allows explicit unsafe legacy dispatch opt-out', () async {
      final client = McpClient(allowUnsafeMcpCalls: true);

      final result = await client.callToolOnServer('jira', 'update_issue', {
        'issue': 'ABC-1',
      });

      expect(result, 'Error: MCP server jira is not connected');
    });
  });

  group('MCP tool execution', () {
    test('dispatch pins MCP calls to the parsed server name', () async {
      final client = _FakeMcpClient();
      final executor = ToolExecutor(workingDir: '.')..setMcpClient(client);

      final results = await executor.executeToolCalls([
        const ToolCallInfo(
          id: 'mcp-read',
          name: 'mcp_jira_get_issue',
          arguments: {'issue': 'ABC-1'},
        ),
      ]);

      expect(results.single.success, isTrue);
      expect(results.single.result, 'jira/get_issue');
      expect(client.calls, 1);
      expect(client.serverName, 'jira');
      expect(client.toolName, 'get_issue');
      expect(client.arguments, {'issue': 'ABC-1'});
    });

    test(
      'mutation-looking MCP calls are denied before client dispatch',
      () async {
        final client = _FakeMcpClient();
        final executor = ToolExecutor(workingDir: '.')..setMcpClient(client);

        final results = await executor.executeToolCalls([
          const ToolCallInfo(
            id: 'mcp-write',
            name: 'mcp_jira_update_issue',
            arguments: {'issue': 'ABC-1', 'summary': 'change'},
          ),
        ]);

        expect(results.single.success, isFalse);
        expect(results.single.structured.status, ToolResultStatus.denied);
        expect(results.single.result, contains('Action blocked'));
        expect(client.calls, 0);
      },
    );

    test('unknown-risk MCP calls are denied before client dispatch', () async {
      final client = _FakeMcpClient();
      final executor = ToolExecutor(workingDir: '.')..setMcpClient(client);

      final results = await executor.executeToolCalls([
        const ToolCallInfo(
          id: 'mcp-unknown',
          name: 'mcp_vendor_magic',
          arguments: {'input': 'value'},
        ),
      ]);

      expect(results.single.success, isFalse);
      expect(results.single.structured.status, ToolResultStatus.denied);
      expect(results.single.result, contains('Action blocked'));
      expect(client.calls, 0);
    });

    test(
      'network-looking read-only MCP calls are denied before dispatch',
      () async {
        final client = _FakeMcpClient();
        final executor = ToolExecutor(workingDir: '.')..setMcpClient(client);

        final results = await executor.executeToolCalls([
          const ToolCallInfo(
            id: 'mcp-browser-fetch',
            name: 'mcp_browser_fetch_url',
            arguments: {'url': 'https://example.com/status'},
          ),
        ]);

        expect(results.single.success, isFalse);
        expect(results.single.structured.status, ToolResultStatus.denied);
        expect(results.single.structured.diagnostic, 'mcpRequiresReview');
        expect(results.single.result, contains('MCP browser, web, URL'));
        expect(client.calls, 0);
      },
    );

    test(
      'declared read-only MCP calls are still denied when arguments include network targets',
      () async {
        final client = _FakeMcpClient();
        final executor = ToolExecutor(workingDir: '.')
          ..setMcpClient(client)
          ..setPermissionRequest(
            const ToolPermissionRequest(
              intent: TurnIntent.ask,
              phase: ToolPermissionPhase.inspect,
              mcpToolRisk: McpToolRisk.readOnly,
              mcpToolName: 'get_status',
            ),
          );

        final results = await executor.executeToolCalls([
          const ToolCallInfo(
            id: 'mcp-read-url-arg',
            name: 'mcp_status_get_status',
            arguments: {'target': 'https://example.com/status'},
          ),
        ]);

        expect(results.single.success, isFalse);
        expect(results.single.structured.status, ToolResultStatus.denied);
        expect(results.single.structured.diagnostic, 'mcpRequiresReview');
        expect(results.single.result, contains('MCP browser, web, URL'));
        expect(client.calls, 0);
      },
    );

    test(
      'declared read-only MCP calls are denied when arguments contain embedded network URLs',
      () async {
        final client = _FakeMcpClient();
        final executor = ToolExecutor(workingDir: '.')
          ..setMcpClient(client)
          ..setPermissionRequest(
            const ToolPermissionRequest(
              intent: TurnIntent.ask,
              phase: ToolPermissionPhase.inspect,
              mcpToolRisk: McpToolRisk.readOnly,
              mcpToolName: 'get_status',
            ),
          );

        final results = await executor.executeToolCalls([
          const ToolCallInfo(
            id: 'mcp-read-embedded-url',
            name: 'mcp_status_get_status',
            arguments: {
              'query': 'check https://example.com/status before returning',
            },
          ),
        ]);

        expect(results.single.success, isFalse);
        expect(results.single.structured.status, ToolResultStatus.denied);
        expect(results.single.structured.diagnostic, 'mcpRequiresReview');
        expect(results.single.result, contains('MCP browser, web, URL'));
        expect(client.calls, 0);
      },
    );

    test(
      'declared read-only MCP calls are denied when nested arguments include network targets',
      () async {
        final client = _FakeMcpClient();
        final executor = ToolExecutor(workingDir: '.')
          ..setMcpClient(client)
          ..setPermissionRequest(
            const ToolPermissionRequest(
              intent: TurnIntent.ask,
              phase: ToolPermissionPhase.inspect,
              mcpToolRisk: McpToolRisk.readOnly,
              mcpToolName: 'get_status',
            ),
          );

        final results = await executor.executeToolCalls([
          const ToolCallInfo(
            id: 'mcp-read-nested-url-arg',
            name: 'mcp_status_get_status',
            arguments: {
              'filters': {
                'checks': [
                  {'endpoint': 'https://example.com/status'},
                ],
              },
            },
          ),
        ]);

        expect(results.single.success, isFalse);
        expect(results.single.structured.status, ToolResultStatus.denied);
        expect(results.single.structured.diagnostic, 'mcpRequiresReview');
        expect(results.single.result, contains('MCP browser, web, URL'));
        expect(client.calls, 0);
      },
    );

    test(
      'declared mutation MCP metadata denies harmless-looking tool names',
      () async {
        final client = _FakeMcpClient();
        final executor = ToolExecutor(workingDir: '.')
          ..setMcpClient(client)
          ..setPermissionRequest(
            const ToolPermissionRequest(
              intent: TurnIntent.ask,
              phase: ToolPermissionPhase.inspect,
              mcpToolRisk: McpToolRisk.mutation,
              mcpToolName: 'get_issue',
            ),
          );

        final results = await executor.executeToolCalls([
          const ToolCallInfo(
            id: 'mcp-mutating-metadata',
            name: 'mcp_jira_get_issue',
            arguments: {'issue': 'ABC-1'},
          ),
        ]);

        expect(results.single.success, isFalse);
        expect(results.single.structured.status, ToolResultStatus.denied);
        expect(results.single.structured.diagnostic, 'mcpRequiresReview');
        expect(results.single.result, contains('MCP mutation'));
        expect(client.calls, 0);
      },
    );

    test('chat intent denies read-only MCP before client dispatch', () async {
      final client = _FakeMcpClient();
      final executor = ToolExecutor(workingDir: '.')
        ..setMcpClient(client)
        ..setPermissionRequest(
          const ToolPermissionRequest(
            intent: TurnIntent.chat,
            phase: ToolPermissionPhase.inspect,
            mcpToolRisk: McpToolRisk.readOnly,
            mcpToolName: 'get_issue',
          ),
        );

      final results = await executor.executeToolCalls([
        const ToolCallInfo(
          id: 'mcp-chat-read',
          name: 'mcp_jira_get_issue',
          arguments: {'issue': 'ABC-1'},
        ),
      ]);

      expect(results.single.success, isFalse);
      expect(results.single.structured.status, ToolResultStatus.denied);
      expect(results.single.result, contains('Tools are not available'));
      expect(client.calls, 0);
    });
  });
}

class _FakeMcpClient extends McpClient {
  int calls = 0;
  String? serverName;
  String? toolName;
  Map<String, dynamic>? arguments;

  @override
  (String serverName, String toolName)? parseMcpToolName(String fullName) {
    if (!fullName.startsWith('mcp_')) return null;
    final rest = fullName.substring(4);
    final idx = rest.indexOf('_');
    if (idx == -1) return null;
    return (rest.substring(0, idx), rest.substring(idx + 1));
  }

  @override
  Future<String> callToolOnServer(
    String serverName,
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    calls++;
    this.serverName = serverName;
    this.toolName = toolName;
    this.arguments = Map<String, dynamic>.from(arguments);
    return '$serverName/$toolName';
  }
}
