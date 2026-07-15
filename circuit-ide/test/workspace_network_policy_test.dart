import 'dart:io';

import 'package:circuit_ide/agent/security/agent_tool_permission_policy.dart';
import 'package:circuit_ide/agent/tools/tool_executor.dart';
import 'package:circuit_ide/models/agent_tool_permission.dart';
import 'package:circuit_ide/models/agent_workspace.dart';
import 'package:circuit_ide/models/tool_call_info.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:circuit_ide/state/agent_workspace_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ToolPermissionDecision evaluate({
    required List<WorkspaceNetworkRule> rules,
    String method = 'GET',
    bool upload = false,
    bool redirect = false,
    bool credentials = false,
    String domain = 'api.example.com',
    WorkspacePermissionDisposition disposition =
        WorkspacePermissionDisposition.review,
  }) =>
      AgentToolPermissionPolicy(
        workingDir: '/workspace',
        networkRules: rules,
        networkDisposition: disposition,
        request: ToolPermissionRequest(
          intent: TurnIntent.verify,
          phase: ToolPermissionPhase.verify,
          networkDomain: domain,
          networkAccessKind: NetworkAccessKind.publicInternet,
          networkMethod: method,
          networkUpload: upload,
          networkFollowsRedirect: redirect,
          networkUsesCredentials: credentials,
        ),
      ).evaluate(
        ToolCallInfo(
          id: 'network',
          name: 'web_fetch',
          arguments: {'url': 'https://$domain/resource'},
        ),
      );

  test('rules serialize and preserve default-deny sensitive settings', () {
    const rule = WorkspaceNetworkRule(domain: '*.example.com');
    final restored = WorkspaceNetworkRule.fromJson(rule.toJson());

    expect(restored, isNotNull);
    expect(restored!.domain, '*.example.com');
    expect(restored.methods, ['GET']);
    expect(restored.allowUpload, isFalse);
    expect(restored.allowRedirects, isFalse);
    expect(restored.allowCredentials, isFalse);
  });

  test('rules reject URLs, IPs, localhost, and private-name suffixes', () {
    for (final domain in [
      'https://api.example.com',
      '127.0.0.1',
      '169.254.169.254',
      'localhost',
      'service.internal',
      'cache.local',
      'device.lan',
    ]) {
      expect(
        WorkspaceNetworkRule.fromJson({'domain': domain}),
        isNull,
        reason: domain,
      );
    }
    expect(
      WorkspaceNetworkRule.fromJson({'domain': 'API.Example.com.'})?.domain,
      'api.example.com',
    );
  });

  test(
    'project network policy persists separately from task history',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'circuit-project-network-policy-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = AgentWorkspaceStore(baseDir: directory.path);
      const policy = WorkspacePermissionConfiguration(
        externalNetwork: WorkspacePermissionDisposition.block,
        networkRules: [
          WorkspaceNetworkRule(
            domain: '*.example.com',
            disposition: WorkspaceNetworkRuleDisposition.ask,
            methods: ['GET', 'POST'],
            allowCredentials: true,
          ),
        ],
      );

      await store.saveProjectPolicy('/workspace/project-a', policy);
      final restored = await store.loadProjectPolicy('/workspace/project-a');

      expect(restored.externalNetwork, WorkspacePermissionDisposition.block);
      expect(restored.networkRules, hasLength(1));
      expect(restored.networkRules.single.domain, '*.example.com');
      expect(
        restored.networkRules.single.disposition,
        WorkspaceNetworkRuleDisposition.ask,
      );
      expect(restored.networkRules.single.allowCredentials, isTrue);
    },
  );

  test('task persistence retains its network policy across restart', () {
    final task = AgentTask(
      id: 'network-task',
      mascotAlias: 'Benny',
      profile: AgentTaskProfile.verify,
      goal: 'Verify network policy',
      policy: const WorkspacePermissionConfiguration(
        networkRules: [
          WorkspaceNetworkRule(
            domain: 'api.example.com',
            disposition: WorkspaceNetworkRuleDisposition.allow,
            methods: ['GET', 'POST'],
            allowCredentials: true,
          ),
        ],
      ),
      createdAt: DateTime(2026),
    );

    final restored = AgentTask.fromJson(task.toJson());
    expect(restored, isNotNull);
    expect(restored!.policy.networkRules, hasLength(1));
    expect(restored.policy.networkRules.single.methods, ['GET', 'POST']);
    expect(restored.policy.networkRules.single.allowCredentials, isTrue);
  });

  test('allow rules are domain and method scoped', () {
    const rule = WorkspaceNetworkRule(
      domain: '*.example.com',
      disposition: WorkspaceNetworkRuleDisposition.allow,
      methods: ['GET'],
    );
    expect(evaluate(rules: [rule]).allowed, isTrue);
    expect(evaluate(rules: [rule], method: 'POST').denied, isTrue);
    expect(
      evaluate(rules: [rule], domain: 'other.example.net').requiresApproval,
      isTrue,
    );
  });

  test('an explicit review rule overrides the project default block', () {
    const rule = WorkspaceNetworkRule(
      domain: 'api.example.com',
      disposition: WorkspaceNetworkRuleDisposition.ask,
    );
    expect(
      evaluate(
        rules: [rule],
        disposition: WorkspacePermissionDisposition.block,
      ).requiresApproval,
      isTrue,
    );
  });

  test(
    'unlisted public access fails closed when the project blocks network',
    () {
      expect(
        evaluate(
          rules: const [],
          disposition: WorkspacePermissionDisposition.block,
        ).denied,
        isTrue,
      );
    },
  );

  test(
    'executor enforces the project network disposition at dispatch time',
    () async {
      final executor =
          ToolExecutor(
            workingDir: '/workspace',
            networkDisposition: WorkspacePermissionDisposition.block,
          )..setPermissionRequest(
            const ToolPermissionRequest(
              intent: TurnIntent.verify,
              phase: ToolPermissionPhase.verify,
            ),
          );

      final result = await executor.executeToolCalls(const [
        ToolCallInfo(
          id: 'blocked-network-fetch',
          name: 'web_fetch',
          arguments: {'url': 'https://api.example.com/status'},
        ),
      ]);

      expect(result.single.success, isFalse);
      expect(result.single.result, contains('Project network policy blocks'));
      expect(result.single.envelope?.status.name, 'denied');
    },
  );

  test(
    'rule constraints deny upload redirect and credentials independently',
    () {
      const rule = WorkspaceNetworkRule(
        domain: 'api.example.com',
        disposition: WorkspaceNetworkRuleDisposition.allow,
        methods: ['GET', 'POST'],
      );
      expect(evaluate(rules: [rule], upload: true).denied, isTrue);
      expect(evaluate(rules: [rule], redirect: true).denied, isTrue);
      expect(evaluate(rules: [rule], credentials: true).denied, isTrue);
    },
  );

  test('deny rules override the normal approval path', () {
    const rule = WorkspaceNetworkRule(
      domain: 'api.example.com',
      disposition: WorkspaceNetworkRuleDisposition.deny,
    );
    final decision = evaluate(rules: [rule]);
    expect(decision.denied, isTrue);
    expect(decision.message, contains('denies'));
  });

  test('a specific deny wins over an earlier wildcard allow', () {
    const rules = [
      WorkspaceNetworkRule(
        domain: '*.example.com',
        disposition: WorkspaceNetworkRuleDisposition.allow,
      ),
      WorkspaceNetworkRule(
        domain: 'api.example.com',
        disposition: WorkspaceNetworkRuleDisposition.deny,
      ),
    ];
    expect(evaluate(rules: rules).denied, isTrue);
  });
}
