import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/agent/mcp/mcp_client.dart';
import 'package:circuit_ide/agent/mcp/mcp_config.dart';
import 'package:circuit_ide/agent/tools/tool_registry.dart';
import 'package:circuit_ide/agent/turn_outcome_validator.dart';
import 'package:circuit_ide/models/tool_call_info.dart';
import 'package:circuit_ide/models/tool_result_envelope.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'MCP results include redacted, citation-safe connector provenance',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        final rpc =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        final response = switch (rpc['method']) {
          'initialize' => {
            'jsonrpc': '2.0',
            'id': rpc['id'],
            'result': {'protocolVersion': '2024-11-05'},
          },
          'tools/list' => {
            'jsonrpc': '2.0',
            'id': rpc['id'],
            'result': {
              'tools': [
                {'name': 'read_record', 'inputSchema': <String, dynamic>{}},
              ],
            },
          },
          _ => {
            'jsonrpc': '2.0',
            'id': rpc['id'],
            'result': {
              'content': [
                {'type': 'text', 'text': 'Customer plan. token=private-value'},
              ],
            },
          },
        };
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
        await request.response.close();
      });
      final used = <String>[];
      final client = McpClient(onServerUsed: used.add);
      final config = McpServerConfig(
        name: 'records',
        url: 'http://${server.address.address}:${server.port}/mcp',
        requestedScopes: const ['records:read'],
      );
      await client.connectServer(config);

      final result = await client.callToolOnServer(
        'records',
        'read_record',
        {},
      );

      expect(result, contains('Source: mcp:records:read_record:'));
      expect(result, contains('Permissions: records:read'));
      expect(result, contains('/mcp'));
      expect(result, isNot(contains('private-value')));
      expect(used, ['records']);
      expect(
        client.recentProvenance.single.objectReference,
        isNot(contains('?')),
      );
    },
  );

  test(
    'connector-backed factual answers need a source citation or assumption label',
    () {
      const validator = TurnOutcomeValidator();
      const call = ToolCallInfo(
        id: 'connector-call',
        name: 'mcp_records_read_record',
      );
      const result = ToolResultEnvelope(
        toolCallId: 'connector-call',
        toolName: 'mcp_records_read_record',
        status: ToolResultStatus.success,
        summary: 'Connector record returned.',
      );

      final missingCitation = validator.validate(
        intent: TurnIntent.ask,
        toolMode: AgentToolMode.ask,
        content: 'The customer plan is active.',
        toolCalls: const [call],
        toolResults: const [result],
      );
      final cited = validator.validate(
        intent: TurnIntent.ask,
        toolMode: AgentToolMode.ask,
        content:
            'The customer plan is active. Source: mcp:records:read_record:123',
        toolCalls: const [call],
        toolResults: const [result],
      );

      expect(missingCitation.status, TurnOutcomeValidationStatus.invalid);
      expect(missingCitation.userMessage, contains('provenance'));
      expect(cited.status, TurnOutcomeValidationStatus.valid);
    },
  );
}
