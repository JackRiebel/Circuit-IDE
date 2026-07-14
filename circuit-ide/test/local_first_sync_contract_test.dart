import 'package:circuit_ide/services/local_first_sync_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const projectId = 'project-6d995c3f';
  const projectAuthority = LocalFirstSyncProjectAuthority(
    projectId: projectId,
    projectOwnerActorId: 'device-owner',
  );

  LocalFirstSyncTimestamp clock(int tick, String actor) =>
      LocalFirstSyncTimestamp(
        wallTimeMillis: 1736776800000 + tick,
        logicalCounter: tick,
        actorId: actor,
      );

  LocalFirstSyncOperation operation({
    required String id,
    required String actor,
    required int tick,
    required String entity,
    required LocalFirstSyncEntityKind kind,
    Map<String, Object?> payload = const {},
    List<String> predecessors = const [],
    int schema = localFirstSyncSchemaVersion,
  }) => LocalFirstSyncOperation(
    operationId: id,
    projectId: projectId,
    actorId: actor,
    predecessorIds: predecessors,
    entityId: entity,
    kind: kind,
    payloadSchemaVersion: schema,
    timestamp: clock(tick, actor),
    payload: payload,
  );

  test(
    'legacy migration retains opaque aliases but never serializes bindings',
    () {
      final migrated = LocalFirstSyncMigration.migrateLegacyMetadata(
        operationId: 'op-migrate-thread',
        projectId: projectId,
        actorId: 'device-a',
        entityId: 'thread-immutable-17',
        legacyAlias: 'legacy-thread-local-17',
        label: 'Customer handoff discussion',
        timestamp: clock(1, 'device-a'),
        localWorkspaceBinding: '/Users/example/private/customer-project',
      );

      expect(migrated.entityId, 'thread-immutable-17');
      expect(migrated.payload['legacyAlias'], 'legacy-thread-local-17');
      expect(migrated.payload['label'], 'Customer handoff discussion');
      final envelopeText = [
        migrated.operationId,
        migrated.projectId,
        migrated.actorId,
        migrated.entityId,
        migrated.payload.toString(),
      ].join('|');
      expect(envelopeText, isNot(contains('/Users/')));
      expect(envelopeText, isNot(contains('customer-project')));
    },
  );

  test('legacy migration rejects a non-opaque alias', () {
    expect(
      () => LocalFirstSyncMigration.migrateLegacyMetadata(
        operationId: 'op-migrate-invalid',
        projectId: projectId,
        actorId: 'device-a',
        entityId: 'thread-immutable-17',
        legacyAlias: 'operator@example.test',
        label: 'Customer handoff discussion',
        timestamp: clock(1, 'device-a'),
        localWorkspaceBinding: '/Users/example/private/customer-project',
      ),
      throwsA(isA<LocalFirstSyncValidationException>()),
    );
  });

  test(
    'secret, path, diagnostics, and execution classes never enter envelopes',
    () {
      final forbiddenPayloads = [
        {'workspacePath': '/Users/example/project'},
        {'clientSecret': 'seeded-secret'},
        {'commandOutput': 'private output'},
        {'rawProviderBody': '{"token":"seeded-secret"}'},
        {'note': 'Authorization: Bearer seeded-secret'},
        {'note': 'C:\\Users\\example\\private.txt'},
      ];
      for (var index = 0; index < forbiddenPayloads.length; index++) {
        expect(
          () => LocalFirstSyncContract.validate(
            operation(
              id: 'op-forbidden-$index',
              actor: 'device-a',
              tick: index + 1,
              entity: 'thread-$index',
              kind: LocalFirstSyncEntityKind.event,
              payload: forbiddenPayloads[index],
            ),
          ),
          throwsA(isA<LocalFirstSyncValidationException>()),
        );
      }
      expect(
        () => LocalFirstSyncContract.validate(
          operation(
            id: 'op-execution',
            actor: 'device-a',
            tick: 9,
            entity: 'command-1',
            kind: LocalFirstSyncEntityKind.executionEvidence,
          ),
        ),
        throwsA(isA<LocalFirstSyncValidationException>()),
      );
    },
  );

  test('two-device append replay is ordered, causal, and duplicate-safe', () {
    final first = operation(
      id: 'op-event-first',
      actor: 'device-a',
      tick: 1,
      entity: 'thread-event-1',
      kind: LocalFirstSyncEntityKind.event,
      payload: const {'kind': 'message', 'content': 'First event'},
    );
    final second = operation(
      id: 'op-event-second',
      actor: 'device-b',
      tick: 2,
      entity: 'thread-event-1',
      kind: LocalFirstSyncEntityKind.event,
      predecessors: const ['op-event-first'],
      payload: const {'kind': 'message', 'content': 'Second event'},
    );

    final merged = LocalFirstSyncContract.merge([
      second,
      first,
      first,
    ], authority: projectAuthority);

    expect(merged.events.map((event) => event.operationId), [
      'op-event-first',
      'op-event-second',
    ]);
    expect(merged.events.last.predecessorIds, ['op-event-first']);
  });

  test('metadata uses audited LWW while immutable versions preserve forks', () {
    final rename = operation(
      id: 'op-rename',
      actor: 'device-a',
      tick: 4,
      entity: 'thread-metadata-1',
      kind: LocalFirstSyncEntityKind.metadata,
      payload: const {'title': 'Investigate release performance'},
    );
    final archive = operation(
      id: 'op-archive',
      actor: 'device-b',
      tick: 5,
      entity: 'thread-metadata-1',
      kind: LocalFirstSyncEntityKind.metadata,
      payload: const {'archived': true},
    );
    final patchA = operation(
      id: 'op-patch-a',
      actor: 'device-a',
      tick: 6,
      entity: 'patch-family-1',
      kind: LocalFirstSyncEntityKind.immutableVersion,
      payload: const {'parentId': 'plan-1', 'version': 'a'},
    );
    final patchB = operation(
      id: 'op-patch-b',
      actor: 'device-b',
      tick: 6,
      entity: 'patch-family-1',
      kind: LocalFirstSyncEntityKind.immutableVersion,
      payload: const {'parentId': 'plan-1', 'version': 'b'},
    );

    final merged = LocalFirstSyncContract.merge([
      patchB,
      archive,
      patchA,
      rename,
    ], authority: projectAuthority);

    expect(
      merged.metadataByEntity['thread-metadata-1']?.operationId,
      'op-archive',
    );
    expect(merged.metadataLoserIdsByEntity['thread-metadata-1'], ['op-rename']);
    expect(
      merged.immutableVersionsByEntity['patch-family-1']?.map(
        (entry) => entry.operationId,
      ),
      ['op-patch-a', 'op-patch-b'],
    );
  });

  test('stricter policy wins and post-revocation offline replay is ignored', () {
    final olderEvent = operation(
      id: 'op-before-revocation',
      actor: 'device-b',
      tick: 1,
      entity: 'thread-event-2',
      kind: LocalFirstSyncEntityKind.event,
      payload: const {
        'kind': 'message',
        'content': 'Offline before revocation',
      },
    );
    final revoke = operation(
      id: 'op-revoke-device-b',
      actor: 'device-owner',
      tick: 2,
      entity: 'membership-device-b',
      kind: LocalFirstSyncEntityKind.membership,
      payload: const {'memberId': 'device-b', 'state': 'revoked'},
    );
    final replayedAfterRevocation = operation(
      id: 'op-after-revocation',
      actor: 'device-b',
      tick: 3,
      entity: 'thread-event-2',
      kind: LocalFirstSyncEntityKind.event,
      payload: const {'kind': 'message', 'content': 'Must not merge'},
    );
    final dependentOnRejectedReplay = operation(
      id: 'op-dependent-on-rejected-replay',
      actor: 'device-a',
      tick: 4,
      entity: 'thread-event-2',
      kind: LocalFirstSyncEntityKind.event,
      predecessors: const ['op-after-revocation'],
      payload: const {'kind': 'message', 'content': 'Must wait'},
    );
    final allow = operation(
      id: 'op-policy-allow',
      actor: 'device-a',
      tick: 1,
      entity: 'network-policy',
      kind: LocalFirstSyncEntityKind.policy,
      payload: const {'scope': 'network', 'disposition': 'allow'},
    );
    final deny = operation(
      id: 'op-policy-deny',
      actor: 'device-b',
      tick: 2,
      entity: 'network-policy',
      kind: LocalFirstSyncEntityKind.policy,
      payload: const {'scope': 'network', 'disposition': 'deny'},
    );

    final merged = LocalFirstSyncContract.merge([
      replayedAfterRevocation,
      allow,
      revoke,
      olderEvent,
      deny,
      dependentOnRejectedReplay,
    ], authority: projectAuthority);

    expect(merged.events.map((event) => event.operationId), [
      'op-before-revocation',
    ]);
    expect(merged.revokedActorIds, contains('device-b'));
    expect(merged.ignoredOperationIds, contains('op-after-revocation'));
    expect(
      merged.deferredOperationIds,
      contains('op-dependent-on-rejected-replay'),
    );
    expect(
      merged
          .missingPredecessorIdsByOperation['op-dependent-on-rejected-replay'],
      ['op-after-revocation'],
    );
    expect(
      merged.policyByScope['network'],
      LocalFirstSyncPolicyDisposition.deny,
    );
    expect(merged.policyConflictIdsByScope['network'], ['op-policy-deny']);
  });

  test('newer schemas fail closed before local merge', () {
    expect(
      () => LocalFirstSyncContract.merge([
        operation(
          id: 'op-future-schema',
          actor: 'device-b',
          tick: 1,
          entity: 'thread-1',
          kind: LocalFirstSyncEntityKind.event,
          schema: localFirstSyncSchemaVersion + 1,
        ),
      ], authority: projectAuthority),
      throwsA(isA<LocalFirstSyncSchemaException>()),
    );
  });

  test('project and causal-envelope boundaries fail closed', () {
    final primary = operation(
      id: 'op-primary-project',
      actor: 'device-a',
      tick: 1,
      entity: 'thread-1',
      kind: LocalFirstSyncEntityKind.event,
    );
    final otherProject = LocalFirstSyncOperation(
      operationId: 'op-other-project',
      projectId: 'project-other',
      actorId: 'device-b',
      entityId: 'thread-1',
      kind: LocalFirstSyncEntityKind.event,
      timestamp: clock(2, 'device-b'),
    );
    expect(
      () => LocalFirstSyncContract.merge([
        primary,
        otherProject,
      ], authority: projectAuthority),
      throwsA(isA<LocalFirstSyncValidationException>()),
    );
    expect(
      () => LocalFirstSyncContract.validate(
        operation(
          id: 'op-invalid-cause',
          actor: 'device-a',
          tick: 3,
          entity: 'thread-1',
          kind: LocalFirstSyncEntityKind.event,
          predecessors: const ['op-invalid-cause'],
        ),
      ),
      throwsA(isA<LocalFirstSyncValidationException>()),
    );
    expect(
      () => LocalFirstSyncContract.validate(
        LocalFirstSyncOperation(
          operationId: 'op-path-project',
          projectId: '/Users/example/project',
          actorId: 'device-a',
          entityId: 'thread-1',
          kind: LocalFirstSyncEntityKind.event,
          timestamp: clock(4, 'device-a'),
        ),
      ),
      throwsA(isA<LocalFirstSyncValidationException>()),
    );
    expect(
      () => LocalFirstSyncContract.validate(
        operation(
          id: 'op-email-actor',
          actor: 'operator@example.test',
          tick: 5,
          entity: 'thread-1',
          kind: LocalFirstSyncEntityKind.event,
        ),
      ),
      throwsA(isA<LocalFirstSyncValidationException>()),
    );
    expect(
      () => LocalFirstSyncContract.validate(
        operation(
          id: 'op-display-entity',
          actor: 'device-a',
          tick: 6,
          entity: 'Customer Project',
          kind: LocalFirstSyncEntityKind.event,
        ),
      ),
      throwsA(isA<LocalFirstSyncValidationException>()),
    );
    expect(
      () => LocalFirstSyncContract.validate(
        operation(
          id: 'op-invalid-predecessor',
          actor: 'device-a',
          tick: 7,
          entity: 'thread-1',
          kind: LocalFirstSyncEntityKind.event,
          predecessors: const ['../external'],
        ),
      ),
      throwsA(isA<LocalFirstSyncValidationException>()),
    );
    expect(
      () => LocalFirstSyncContract.validate(
        operation(
          id: 'op-invalid-member',
          actor: 'device-a',
          tick: 8,
          entity: 'membership-device-b',
          kind: LocalFirstSyncEntityKind.membership,
          payload: const {'memberId': 'owner@example.test', 'state': 'active'},
        ),
      ),
      throwsA(isA<LocalFirstSyncValidationException>()),
    );
    expect(
      () => LocalFirstSyncContract.validate(
        LocalFirstSyncOperation(
          operationId: 'op-wrong-clock-actor',
          projectId: projectId,
          actorId: 'device-a',
          entityId: 'thread-1',
          kind: LocalFirstSyncEntityKind.event,
          timestamp: clock(9, 'device-b'),
        ),
      ),
      throwsA(isA<LocalFirstSyncValidationException>()),
    );
  });

  test(
    'envelopes stay bounded JSON and canonical duplicate delivery ignores map order',
    () {
      final first = operation(
        id: 'op-canonical-duplicate',
        actor: 'device-a',
        tick: 1,
        entity: 'thread-canonical-1',
        kind: LocalFirstSyncEntityKind.event,
        payload: const {
          'title': 'Customer handoff',
          'nested': {
            'owner': 'device-a',
            'labels': ['review', 'ready'],
          },
        },
      );
      final sameEnvelopeDifferentMapOrder = operation(
        id: 'op-canonical-duplicate',
        actor: 'device-a',
        tick: 1,
        entity: 'thread-canonical-1',
        kind: LocalFirstSyncEntityKind.event,
        payload: const {
          'nested': {
            'labels': ['review', 'ready'],
            'owner': 'device-a',
          },
          'title': 'Customer handoff',
        },
      );

      final merged = LocalFirstSyncContract.merge([
        first,
        sameEnvelopeDifferentMapOrder,
      ], authority: projectAuthority);
      expect(merged.events, hasLength(1));

      Object? tooDeep = 'end';
      for (
        var depth = 0;
        depth <= LocalFirstSyncContract.maxPayloadDepth;
        depth++
      ) {
        tooDeep = {'layer-$depth': tooDeep};
      }
      final invalidPayloads = <Map<String, Object?>>[
        {'value': double.nan},
        {
          'value': {1: 'non-string JSON key'},
        },
        {
          'value': List<String>.filled(
            LocalFirstSyncContract.maxPayloadEntries + 1,
            'bounded',
          ),
        },
        {
          'value': List<String>.filled(
            LocalFirstSyncContract.maxPayloadStringLength + 1,
            'x',
          ).join(),
        },
        {'value': tooDeep},
      ];
      for (var index = 0; index < invalidPayloads.length; index++) {
        expect(
          () => LocalFirstSyncContract.validate(
            operation(
              id: 'op-invalid-json-$index',
              actor: 'device-a',
              tick: index + 2,
              entity: 'thread-json-$index',
              kind: LocalFirstSyncEntityKind.event,
              payload: invalidPayloads[index],
            ),
          ),
          throwsA(isA<LocalFirstSyncValidationException>()),
        );
      }

      expect(
        () => LocalFirstSyncContract.validate(
          operation(
            id: 'op-too-many-predecessors',
            actor: 'device-a',
            tick: 10,
            entity: 'thread-json-bounded',
            kind: LocalFirstSyncEntityKind.event,
            predecessors: List<String>.generate(
              LocalFirstSyncContract.maxCausalPredecessors + 1,
              (index) => 'op-predecessor-$index',
            ),
          ),
        ),
        throwsA(isA<LocalFirstSyncValidationException>()),
      );
      expect(
        () => LocalFirstSyncContract.validate(
          const LocalFirstSyncOperation(
            operationId: 'op-negative-clock',
            projectId: projectId,
            actorId: 'device-a',
            entityId: 'thread-negative-clock',
            kind: LocalFirstSyncEntityKind.event,
            timestamp: LocalFirstSyncTimestamp(
              wallTimeMillis: -1,
              logicalCounter: 0,
              actorId: 'device-a',
            ),
          ),
        ),
        throwsA(isA<LocalFirstSyncValidationException>()),
      );
    },
  );

  test(
    'causal operations defer until every predecessor is available and retain causal order',
    () {
      final predecessor = operation(
        id: 'op-causal-predecessor',
        actor: 'device-a',
        tick: 5,
        entity: 'thread-causal-1',
        kind: LocalFirstSyncEntityKind.event,
        payload: const {'content': 'Root event'},
      );
      final successor = operation(
        id: 'op-causal-successor',
        actor: 'device-b',
        tick: 1,
        entity: 'thread-causal-1',
        kind: LocalFirstSyncEntityKind.event,
        predecessors: const ['op-causal-predecessor'],
        payload: const {'content': 'Reply event'},
      );

      final deferred = LocalFirstSyncContract.merge([
        successor,
      ], authority: projectAuthority);
      expect(deferred.events, isEmpty);
      expect(deferred.deferredOperationIds, {'op-causal-successor'});
      expect(deferred.missingPredecessorIdsByOperation['op-causal-successor'], [
        'op-causal-predecessor',
      ]);

      final deliveredOutOfOrder = LocalFirstSyncContract.merge([
        successor,
        predecessor,
      ], authority: projectAuthority);
      expect(deliveredOutOfOrder.deferredOperationIds, isEmpty);
      expect(deliveredOutOfOrder.events.map((event) => event.operationId), [
        'op-causal-predecessor',
        'op-causal-successor',
      ]);
    },
  );

  test(
    'causal dependency delivery preserves events that predate a later revocation',
    () {
      final dependency = operation(
        id: 'op-late-dependency',
        actor: 'device-a',
        tick: 4,
        entity: 'thread-revocation-1',
        kind: LocalFirstSyncEntityKind.event,
      );
      final beforeRevocation = operation(
        id: 'op-before-revocation-causal',
        actor: 'device-b',
        tick: 1,
        entity: 'thread-revocation-1',
        kind: LocalFirstSyncEntityKind.event,
        predecessors: const ['op-late-dependency'],
      );
      final revoke = operation(
        id: 'op-revoke-after-event-time',
        actor: 'device-owner',
        tick: 2,
        entity: 'membership-device-b',
        kind: LocalFirstSyncEntityKind.membership,
        payload: const {'memberId': 'device-b', 'state': 'revoked'},
      );

      final merged = LocalFirstSyncContract.merge([
        beforeRevocation,
        revoke,
        dependency,
      ], authority: projectAuthority);
      expect(merged.events.map((event) => event.operationId), [
        'op-late-dependency',
        'op-before-revocation-causal',
      ]);
      expect(merged.ignoredOperationIds, isEmpty);
      expect(merged.revokedActorIds, {'device-b'});
    },
  );

  test(
    'a revoked sync actor cannot be reactivated under the same identity',
    () {
      final revoke = operation(
        id: 'op-revoke-identity',
        actor: 'device-owner',
        tick: 1,
        entity: 'membership-device-b',
        kind: LocalFirstSyncEntityKind.membership,
        payload: const {'memberId': 'device-b', 'state': 'revoked'},
      );
      final reactivate = operation(
        id: 'op-reactivate-identity',
        actor: 'device-owner',
        tick: 2,
        entity: 'membership-device-b',
        kind: LocalFirstSyncEntityKind.membership,
        payload: const {'memberId': 'device-b', 'state': 'active'},
      );

      expect(
        () => LocalFirstSyncContract.merge([
          revoke,
          reactivate,
        ], authority: projectAuthority),
        throwsA(isA<LocalFirstSyncValidationException>()),
      );
    },
  );

  test('membership entity IDs and merge batches stay bounded', () {
    expect(
      () => LocalFirstSyncContract.validate(
        operation(
          id: 'op-membership-mismatch',
          actor: 'device-owner',
          tick: 1,
          entity: 'thread-not-membership',
          kind: LocalFirstSyncEntityKind.membership,
          payload: const {'memberId': 'device-b', 'state': 'active'},
        ),
      ),
      throwsA(isA<LocalFirstSyncValidationException>()),
    );

    expect(
      () => LocalFirstSyncContract.merge(
        List<LocalFirstSyncOperation>.generate(
          LocalFirstSyncContract.maxOperationsPerMerge + 1,
          (index) => operation(
            id: 'op-batch-$index',
            actor: 'device-a',
            tick: index + 1,
            entity: 'thread-batch-$index',
            kind: LocalFirstSyncEntityKind.event,
          ),
        ),
        authority: projectAuthority,
      ),
      throwsA(isA<LocalFirstSyncValidationException>()),
    );
  });

  test('only the local project owner may change membership', () {
    final ownerRevocation = operation(
      id: 'op-owner-revocation',
      actor: 'device-owner',
      tick: 1,
      entity: 'membership-device-b',
      kind: LocalFirstSyncEntityKind.membership,
      payload: const {'memberId': 'device-b', 'state': 'revoked'},
    );
    final nonOwnerRevocation = operation(
      id: 'op-forged-revocation',
      actor: 'device-b',
      tick: 2,
      entity: 'membership-device-a',
      kind: LocalFirstSyncEntityKind.membership,
      payload: const {'memberId': 'device-a', 'state': 'revoked'},
    );

    final accepted = LocalFirstSyncContract.merge([
      ownerRevocation,
    ], authority: projectAuthority);
    expect(accepted.revokedActorIds, contains('device-b'));
    expect(
      () => LocalFirstSyncContract.merge([
        nonOwnerRevocation,
      ], authority: projectAuthority),
      throwsA(isA<LocalFirstSyncValidationException>()),
    );
    expect(
      () => LocalFirstSyncContract.merge(
        const [],
        authority: const LocalFirstSyncProjectAuthority(
          projectId: 'project-6d995c3f',
          projectOwnerActorId: 'owner@example.test',
        ),
      ),
      throwsA(isA<LocalFirstSyncValidationException>()),
    );
  });
}
