import 'package:circuit_ide/agent/providers/company_connector_provider.dart';
import 'package:circuit_ide/agent/providers/provider_registry.dart';
import 'package:circuit_ide/enums/ai_provider.dart';
import 'package:circuit_ide/models/agent_request.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/state/agent_request_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProviderRegistry', () {
    test('exposes only the Circuit company connector', () {
      const registry = ProviderRegistry();

      expect(registry.descriptors, hasLength(1));
      expect(registry.descriptors.single.id, 'circuit');
      expect(registry.descriptors.single.displayName, 'Circuit Company AI');
      expect(
        registry.create(AIProviderType.cisco),
        isA<CompanyConnectorProvider>(),
      );
    });

    test('company connector falls back to bundled free-tier models', () async {
      final provider = CompanyConnectorProvider();

      final models = await provider.refreshModels();

      expect(models.map((model) => model.id), [
        'gpt-5-nano',
        'gemini-3.1-flash-lite',
      ]);
      expect(models.every((model) => model.supportsTools), isTrue);
      expect(models.every((model) => model.contextWindow == 120000), isTrue);
    });
  });

  group('AgentRequestController', () {
    test('tracks lanes independently', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(agentRequestProvider.notifier);

      controller.start(
        lane: AgentRequestLane.chat,
        requestId: 'chat-1',
        model: 'gpt-5-nano',
      );
      controller.start(
        lane: AgentRequestLane.inlineCompletion,
        requestId: 'completion-1',
        model: 'gemini-3.1-flash-lite',
      );

      final state = container.read(agentRequestProvider);
      expect(state[AgentRequestLane.chat]?.requestId, 'chat-1');
      expect(
        state[AgentRequestLane.inlineCompletion]?.requestId,
        'completion-1',
      );
      expect(controller.isBusy(AgentRequestLane.chat), isTrue);
      expect(controller.isBusy(AgentRequestLane.backgroundTask), isFalse);
    });
  });

  group('Reviewed edits', () {
    test('patch set exposes review metadata', () {
      final patchSet = ProposedPatchSet(
        id: 'patch-1',
        title: 'Update README',
        createdAt: DateTime(2026),
        edits: const [
          ProposedFileEdit(
            path: 'README.md',
            type: ProposedFileEditType.modify,
            before: 'old',
            after: 'new',
            unifiedDiff: '-old\n+new',
          ),
        ],
      );

      expect(patchSet.isEmpty, isFalse);
      expect(patchSet.fileCount, 1);
      expect(patchSet.edits.single.requiresApproval, isTrue);
      expect(
        const PatchApplyResult(status: PatchApplyStatus.applied).applied,
        isTrue,
      );
    });
  });
}
