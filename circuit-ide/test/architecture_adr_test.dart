import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const adrFiles = [
    '0001-studio-turn-runtime-ownership.md',
    '0002-durable-state-schema-and-recovery.md',
    '0003-execution-security-boundary.md',
    '0004-provider-protocol-boundary.md',
    '0005-artifact-lifecycle.md',
    '0006-agent-platform-boundary.md',
    '0007-studio-ui-state-ownership.md',
  ];

  test('accepted ADR inventory covers every major runtime boundary', () async {
    final index = await File('../docs/adr/README.md').readAsString();
    for (final file in adrFiles) {
      final contents = await File('../docs/adr/$file').readAsString();
      expect(contents, contains('Status: Accepted'));
      expect(index, contains(file));
    }
  });

  test('owning implementation modules link to their ADR constraints', () async {
    const expectedLinks = {
      'lib/models/studio_turn.dart': 'ADR-0001',
      'lib/state/studio_thread_provider.dart': 'ADR-0002',
      'lib/agent/security/agent_tool_permission_policy.dart': 'ADR-0003',
      'lib/agent/providers/provider_interface.dart': 'ADR-0004',
      'lib/services/generated_artifact_writer.dart': 'ADR-0005',
      'lib/state/agent_turn_runtime_provider.dart': 'ADR-0006',
      'lib/ui/studio/studio_shell.dart': 'ADR-0007',
    };
    for (final entry in expectedLinks.entries) {
      expect(await File(entry.key).readAsString(), contains(entry.value));
    }
  });
}
