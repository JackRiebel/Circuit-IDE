import 'dart:io';

import 'package:circuit_ide/agent/security/agent_tool_permission_policy.dart';
import 'package:circuit_ide/models/agent_tool_permission.dart';
import 'package:circuit_ide/models/tool_call_info.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'sensitive credential paths are denied across reads patches and commands',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'agent_sensitive_permission_boundary_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final inspectPolicy = AgentToolPermissionPolicy(
        workingDir: root.path,
        request: const ToolPermissionRequest(
          intent: TurnIntent.ask,
          phase: ToolPermissionPhase.inspect,
        ),
      );
      final applyPolicy = AgentToolPermissionPolicy(
        workingDir: root.path,
        request: const ToolPermissionRequest(
          intent: TurnIntent.code,
          phase: ToolPermissionPhase.apply,
          allowPatchTransaction: true,
        ),
      );
      final verifyPolicy = AgentToolPermissionPolicy(
        workingDir: root.path,
        request: const ToolPermissionRequest(
          intent: TurnIntent.verify,
          phase: ToolPermissionPhase.verify,
        ),
      );

      final sensitiveReads = [
        const ToolCallInfo(
          id: 'read-client-secret',
          name: 'read_file',
          arguments: {'path': 'config/client_secret.json'},
        ),
        const ToolCallInfo(
          id: 'read-service-account',
          name: 'read_file',
          arguments: {'path': 'keys/service-account.json'},
        ),
        const ToolCallInfo(
          id: 'read-pypirc',
          name: 'read_file',
          arguments: {'path': '.pypirc'},
        ),
        const ToolCallInfo(
          id: 'read-gh-hosts',
          name: 'read_file',
          arguments: {'path': '.config/gh/hosts.yml'},
        ),
      ];
      for (final toolCall in sensitiveReads) {
        final decision = inspectPolicy.evaluate(toolCall);
        expect(
          decision.verdict,
          ToolPermissionVerdict.deny,
          reason: toolCall.id,
        );
        expect(
          decision.reason,
          ToolPermissionReason.secretPath,
          reason: toolCall.id,
        );
      }

      final patchPrivateKey = applyPolicy.evaluate(
        const ToolCallInfo(
          id: 'patch-private-key',
          name: 'apply_patch_set',
          arguments: {
            'files': [
              {'path': 'certs/customer-private-key.pem', 'content': 'secret'},
            ],
          },
        ),
      );
      expect(patchPrivateKey.verdict, ToolPermissionVerdict.deny);
      expect(patchPrivateKey.reason, ToolPermissionReason.secretPath);

      final commandSecretRead = verifyPolicy.evaluate(
        const ToolCallInfo(
          id: 'command-secret-read',
          name: 'run_command',
          arguments: {
            'command': 'python3 scripts/inspect.py keys/firebase-adminsdk.json',
          },
        ),
      );
      expect(commandSecretRead.verdict, ToolPermissionVerdict.deny);
      expect(commandSecretRead.reason, ToolPermissionReason.dangerousCommand);

      final normalTokenSource = inspectPolicy.evaluate(
        const ToolCallInfo(
          id: 'read-design-tokens',
          name: 'read_file',
          arguments: {'path': 'lib/core/constants/design_tokens.dart'},
        ),
      );
      expect(normalTokenSource.verdict, ToolPermissionVerdict.allow);
    },
  );

  test('command path boundaries include assigned absolute arguments', () async {
    final root = await Directory.systemTemp.createTemp(
      'agent_permission_boundary_',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    const assignedAbsolutePath = ToolCallInfo(
      id: 'assigned-absolute',
      name: 'run_command',
      arguments: {'command': 'python scripts/check.py --input=/etc/passwd'},
    );
    const assignedWindowsPath = ToolCallInfo(
      id: 'assigned-windows',
      name: 'run_command',
      arguments: {
        r'command': r'node scripts/audit.js --path=C:\Users\me\Documents',
      },
    );
    const assignedUncPath = ToolCallInfo(
      id: 'assigned-unc',
      name: 'run_command',
      arguments: {r'command': r'python scripts/check.py --path=\\server\share'},
    );
    final basePolicy = AgentToolPermissionPolicy(
      workingDir: root.path,
      request: const ToolPermissionRequest(
        intent: TurnIntent.verify,
        phase: ToolPermissionPhase.verify,
      ),
    );
    final grantedPolicy = AgentToolPermissionPolicy(
      workingDir: root.path,
      request: ToolPermissionRequest(
        intent: TurnIntent.verify,
        phase: ToolPermissionPhase.verify,
        approvalGrant: ApprovalGrant.turn,
        approvalGrantKey: basePolicy.approvalGrantKeyFor(assignedAbsolutePath),
      ),
    );

    for (final decision in [
      basePolicy.evaluate(assignedAbsolutePath),
      grantedPolicy.evaluate(assignedAbsolutePath),
      basePolicy.evaluate(assignedWindowsPath),
      basePolicy.evaluate(assignedUncPath),
    ]) {
      expect(decision.verdict, ToolPermissionVerdict.deny);
      expect(decision.reason, ToolPermissionReason.pathOutsideWorkspace);
    }
  });

  test(
    'git commit path arguments are validated before approval grants',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'agent_git_permission_boundary_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final basePolicy = AgentToolPermissionPolicy(
        workingDir: root.path,
        request: const ToolPermissionRequest(
          intent: TurnIntent.verify,
          phase: ToolPermissionPhase.verify,
        ),
      );
      const outsideCommit = ToolCallInfo(
        id: 'git-commit-outside',
        name: 'git_commit',
        arguments: {
          'message': 'commit outside',
          'files': ['../outside.txt'],
        },
      );
      const secretCommit = ToolCallInfo(
        id: 'git-commit-secret',
        name: 'git_commit',
        arguments: {
          'message': 'commit secret',
          'files': ['.env.local'],
        },
      );
      const optionCommit = ToolCallInfo(
        id: 'git-commit-option',
        name: 'git_commit',
        arguments: {
          'message': 'commit option',
          'files': ['--all'],
        },
      );
      const pathspecCommit = ToolCallInfo(
        id: 'git-commit-pathspec',
        name: 'git_commit',
        arguments: {
          'message': 'commit pathspec',
          'files': [':(glob)**/*.dart'],
        },
      );
      const validCommit = ToolCallInfo(
        id: 'git-commit-valid',
        name: 'git_commit',
        arguments: {
          'message': 'commit valid',
          'files': ['lib/main.dart'],
        },
      );

      final validGrantKey = basePolicy.approvalGrantKeyFor(validCommit);
      final grantedPolicy = AgentToolPermissionPolicy(
        workingDir: root.path,
        request: ToolPermissionRequest(
          intent: TurnIntent.verify,
          phase: ToolPermissionPhase.verify,
          approvalGrant: ApprovalGrant.turn,
          approvalGrantKey: validGrantKey,
        ),
      );

      expect(
        basePolicy.evaluate(outsideCommit).reason,
        ToolPermissionReason.pathOutsideWorkspace,
      );
      expect(
        grantedPolicy.evaluate(outsideCommit).reason,
        ToolPermissionReason.pathOutsideWorkspace,
      );
      expect(
        basePolicy.evaluate(secretCommit).reason,
        ToolPermissionReason.secretPath,
      );
      expect(
        basePolicy.evaluate(optionCommit).reason,
        ToolPermissionReason.pathOutsideWorkspace,
      );
      expect(
        basePolicy.evaluate(pathspecCommit).reason,
        ToolPermissionReason.pathOutsideWorkspace,
      );

      final validBeforeGrant = basePolicy.evaluate(validCommit);
      expect(validBeforeGrant.verdict, ToolPermissionVerdict.ask);
      expect(
        validBeforeGrant.reason,
        ToolPermissionReason.gitMutationRequiresReview,
      );

      final validAfterGrant = grantedPolicy.evaluate(validCommit);
      expect(validAfterGrant.verdict, ToolPermissionVerdict.allow);
      expect(validAfterGrant.reason, ToolPermissionReason.approvalGranted);
    },
  );

  test(
    'git branch mutation names are validated before approval grants',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'agent_git_branch_permission_boundary_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final basePolicy = AgentToolPermissionPolicy(
        workingDir: root.path,
        request: const ToolPermissionRequest(
          intent: TurnIntent.verify,
          phase: ToolPermissionPhase.verify,
        ),
      );
      const branchList = ToolCallInfo(
        id: 'git-branch-list',
        name: 'git_branch',
        arguments: {'action': 'list'},
      );
      const validSwitch = ToolCallInfo(
        id: 'git-branch-switch-valid',
        name: 'git_branch',
        arguments: {'action': 'switch', 'name': 'feature/codex-pass-7'},
      );
      const optionSwitch = ToolCallInfo(
        id: 'git-branch-switch-option',
        name: 'git_branch',
        arguments: {'action': 'switch', 'name': '--force'},
      );

      final validGrantKey = basePolicy.approvalGrantKeyFor(validSwitch);
      final grantedPolicy = AgentToolPermissionPolicy(
        workingDir: root.path,
        request: ToolPermissionRequest(
          intent: TurnIntent.verify,
          phase: ToolPermissionPhase.verify,
          approvalGrant: ApprovalGrant.turn,
          approvalGrantKey: validGrantKey,
        ),
      );

      final branchListDecision = basePolicy.evaluate(branchList);
      expect(branchListDecision.verdict, ToolPermissionVerdict.allow);
      expect(
        branchListDecision.reason,
        ToolPermissionReason.readOnlyInsideWorkspace,
      );

      final validBeforeGrant = basePolicy.evaluate(validSwitch);
      expect(validBeforeGrant.verdict, ToolPermissionVerdict.ask);
      expect(
        validBeforeGrant.reason,
        ToolPermissionReason.gitMutationRequiresReview,
      );

      final validAfterGrant = grantedPolicy.evaluate(validSwitch);
      expect(validAfterGrant.verdict, ToolPermissionVerdict.allow);
      expect(validAfterGrant.reason, ToolPermissionReason.approvalGranted);

      for (final toolCall in [
        const ToolCallInfo(
          id: 'git-branch-create-empty',
          name: 'git_branch',
          arguments: {'action': 'create', 'name': ''},
        ),
        optionSwitch,
        const ToolCallInfo(
          id: 'git-branch-create-traversal',
          name: 'git_branch',
          arguments: {'action': 'create', 'name': '../main'},
        ),
        const ToolCallInfo(
          id: 'git-branch-create-double-slash',
          name: 'git_branch',
          arguments: {'action': 'create', 'name': 'feature//bad'},
        ),
        const ToolCallInfo(
          id: 'git-branch-create-space',
          name: 'git_branch',
          arguments: {'action': 'create', 'name': 'feature name'},
        ),
        const ToolCallInfo(
          id: 'git-branch-create-reflog',
          name: 'git_branch',
          arguments: {'action': 'create', 'name': 'feature@{1}'},
        ),
        const ToolCallInfo(
          id: 'git-branch-create-lock',
          name: 'git_branch',
          arguments: {'action': 'create', 'name': 'release.lock'},
        ),
        const ToolCallInfo(
          id: 'git-branch-create-colon',
          name: 'git_branch',
          arguments: {'action': 'create', 'name': 'bugfix:prod'},
        ),
        const ToolCallInfo(
          id: 'git-branch-unknown-action',
          name: 'git_branch',
          arguments: {'action': 'rename', 'name': 'safe-name'},
        ),
      ]) {
        final decision = basePolicy.evaluate(toolCall);
        expect(
          decision.verdict,
          ToolPermissionVerdict.deny,
          reason: toolCall.id,
        );
        expect(
          decision.reason,
          ToolPermissionReason.gitMutationRequiresReview,
          reason: toolCall.id,
        );
      }

      final optionWithGrant = grantedPolicy.evaluate(optionSwitch);
      expect(optionWithGrant.verdict, ToolPermissionVerdict.deny);
      expect(
        optionWithGrant.reason,
        ToolPermissionReason.gitMutationRequiresReview,
      );
    },
  );

  test(
    'network approval grants are scoped to domain or exact arguments',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'agent_network_permission_boundary_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final basePolicy = AgentToolPermissionPolicy(
        workingDir: root.path,
        request: const ToolPermissionRequest(
          intent: TurnIntent.verify,
          phase: ToolPermissionPhase.verify,
        ),
      );
      const exampleFetch = ToolCallInfo(
        id: 'web-fetch-example',
        name: 'web_fetch',
        arguments: {'url': 'https://example.com/docs'},
      );
      const openAiFetch = ToolCallInfo(
        id: 'web-fetch-openai',
        name: 'web_fetch',
        arguments: {'url': 'https://openai.com/docs'},
      );
      const localFetch = ToolCallInfo(
        id: 'web-fetch-localhost',
        name: 'web_fetch',
        arguments: {'url': 'http://localhost:3000'},
      );
      const ciscoSearch = ToolCallInfo(
        id: 'web-search-cisco',
        name: 'web_search',
        arguments: {'query': 'cisco switching guide'},
      );
      const merakiSearch = ToolCallInfo(
        id: 'web-search-meraki',
        name: 'web_search',
        arguments: {'query': 'meraki firewall guide'},
      );

      final exampleGrantPolicy = AgentToolPermissionPolicy(
        workingDir: root.path,
        request: ToolPermissionRequest(
          intent: TurnIntent.verify,
          phase: ToolPermissionPhase.verify,
          approvalGrant: ApprovalGrant.turn,
          approvalGrantKey: basePolicy.approvalGrantKeyFor(exampleFetch),
        ),
      );
      final searchGrantPolicy = AgentToolPermissionPolicy(
        workingDir: root.path,
        request: ToolPermissionRequest(
          intent: TurnIntent.verify,
          phase: ToolPermissionPhase.verify,
          approvalGrant: ApprovalGrant.turn,
          approvalGrantKey: basePolicy.approvalGrantKeyFor(ciscoSearch),
        ),
      );

      final exampleBeforeGrant = basePolicy.evaluate(exampleFetch);
      expect(exampleBeforeGrant.verdict, ToolPermissionVerdict.ask);
      expect(
        exampleBeforeGrant.reason,
        ToolPermissionReason.networkRequiresReview,
      );

      final exampleAfterGrant = exampleGrantPolicy.evaluate(exampleFetch);
      expect(exampleAfterGrant.verdict, ToolPermissionVerdict.allow);
      expect(exampleAfterGrant.reason, ToolPermissionReason.approvalGranted);

      final differentDomainWithGrant = exampleGrantPolicy.evaluate(openAiFetch);
      expect(differentDomainWithGrant.verdict, ToolPermissionVerdict.ask);
      expect(
        differentDomainWithGrant.reason,
        ToolPermissionReason.networkRequiresReview,
      );

      final localWithGrant = exampleGrantPolicy.evaluate(localFetch);
      expect(localWithGrant.verdict, ToolPermissionVerdict.deny);
      expect(localWithGrant.reason, ToolPermissionReason.networkRequiresReview);

      final searchAfterGrant = searchGrantPolicy.evaluate(ciscoSearch);
      expect(searchAfterGrant.verdict, ToolPermissionVerdict.allow);
      expect(searchAfterGrant.reason, ToolPermissionReason.approvalGranted);

      final differentSearchWithGrant = searchGrantPolicy.evaluate(merakiSearch);
      expect(differentSearchWithGrant.verdict, ToolPermissionVerdict.ask);
      expect(
        differentSearchWithGrant.reason,
        ToolPermissionReason.networkRequiresReview,
      );
    },
  );
}
