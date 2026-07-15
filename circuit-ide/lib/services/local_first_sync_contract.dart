// Deterministic, transport-free contract for the proposed local-first sync
// design in ADR-0008.
//
// This is not a sync client, encrypted store, or background uploader. It
// models the envelope validation and conflict rules that any future approved
// implementation must preserve. Keeping those rules executable before a
// remote transport exists prevents a later adapter from silently treating a
// workspace path, secret, approval, or command result as collaboration data.

const localFirstSyncSchemaVersion = 1;

enum LocalFirstSyncEntityKind {
  event,
  metadata,
  immutableVersion,
  policy,
  membership,
  executionEvidence,
}

enum LocalFirstSyncPolicyDisposition { deny, review, allow }

class LocalFirstSyncTimestamp implements Comparable<LocalFirstSyncTimestamp> {
  final int wallTimeMillis;
  final int logicalCounter;
  final String actorId;

  const LocalFirstSyncTimestamp({
    required this.wallTimeMillis,
    required this.logicalCounter,
    required this.actorId,
  });

  @override
  int compareTo(LocalFirstSyncTimestamp other) {
    final wall = wallTimeMillis.compareTo(other.wallTimeMillis);
    if (wall != 0) return wall;
    final logical = logicalCounter.compareTo(other.logicalCounter);
    if (logical != 0) return logical;
    return actorId.compareTo(other.actorId);
  }
}

class LocalFirstSyncOperation {
  final String operationId;
  final String projectId;
  final String actorId;
  final List<String> predecessorIds;
  final String entityId;
  final LocalFirstSyncEntityKind kind;
  final int payloadSchemaVersion;
  final LocalFirstSyncTimestamp timestamp;
  final Map<String, Object?> payload;

  const LocalFirstSyncOperation({
    required this.operationId,
    required this.projectId,
    required this.actorId,
    this.predecessorIds = const [],
    required this.entityId,
    required this.kind,
    this.payloadSchemaVersion = localFirstSyncSchemaVersion,
    required this.timestamp,
    this.payload = const {},
  });
}

/// Locally trusted project ownership used to evaluate received envelopes.
///
/// This authority is not part of a sync envelope and must be resolved from the
/// project's local configuration. A future remote implementation must bind
/// the operation actor to a verified identity before it can rely on this
/// boundary; this pre-transport contract only ensures that an ordinary member
/// cannot use its own actor ID to mutate membership.
class LocalFirstSyncProjectAuthority {
  final String projectId;
  final String projectOwnerActorId;

  const LocalFirstSyncProjectAuthority({
    required this.projectId,
    required this.projectOwnerActorId,
  });
}

class LocalFirstSyncMigration {
  /// Creates the sync-safe representation of an existing local record.
  ///
  /// [localWorkspaceBinding] deliberately has no route into the envelope. It
  /// is accepted here solely so the migration simulation can prove that a
  /// local path remains a local binding while the legacy opaque ID stays
  /// available for recovery/audit.
  static LocalFirstSyncOperation migrateLegacyMetadata({
    required String operationId,
    required String projectId,
    required String actorId,
    required String entityId,
    required String legacyAlias,
    required String label,
    required LocalFirstSyncTimestamp timestamp,
    required String localWorkspaceBinding,
  }) {
    if (localWorkspaceBinding.trim().isEmpty) {
      throw const LocalFirstSyncValidationException(
        'A local binding is required for migration but is never syncable.',
      );
    }
    if (!LocalFirstSyncContract.isOpaqueIdentifier(legacyAlias)) {
      throw const LocalFirstSyncValidationException(
        'Legacy migration requires an opaque local alias.',
      );
    }
    final operation = LocalFirstSyncOperation(
      operationId: operationId,
      projectId: projectId,
      actorId: actorId,
      entityId: entityId,
      kind: LocalFirstSyncEntityKind.metadata,
      timestamp: timestamp,
      payload: {'legacyAlias': legacyAlias, 'label': label},
    );
    LocalFirstSyncContract.validate(operation);
    return operation;
  }
}

class LocalFirstSyncMergeResult {
  final List<LocalFirstSyncOperation> events;
  final Map<String, LocalFirstSyncOperation> metadataByEntity;
  final Map<String, List<LocalFirstSyncOperation>> immutableVersionsByEntity;
  final Map<String, List<String>> metadataLoserIdsByEntity;
  final Map<String, LocalFirstSyncPolicyDisposition> policyByScope;
  final Map<String, List<String>> policyConflictIdsByScope;
  final Set<String> revokedActorIds;
  final Set<String> ignoredOperationIds;
  final Set<String> deferredOperationIds;
  final Map<String, List<String>> missingPredecessorIdsByOperation;

  const LocalFirstSyncMergeResult({
    required this.events,
    required this.metadataByEntity,
    required this.immutableVersionsByEntity,
    required this.metadataLoserIdsByEntity,
    required this.policyByScope,
    required this.policyConflictIdsByScope,
    required this.revokedActorIds,
    required this.ignoredOperationIds,
    required this.deferredOperationIds,
    required this.missingPredecessorIdsByOperation,
  });
}

/// Applies the ADR's deterministic, no-side-effect conflict policy.
class LocalFirstSyncContract {
  /// Bounds that keep a future encrypted envelope deterministic and prevent a
  /// collaboration record from becoming an unbounded storage or merge input.
  static const maxCausalPredecessors = 64;
  static const maxPayloadDepth = 8;
  static const maxPayloadEntries = 256;
  static const maxPayloadStringLength = 16 * 1024;
  static const maxOperationsPerMerge = 512;

  static const _forbiddenPayloadKeys = {
    'workspacepath',
    'localworkspacebinding',
    'path',
    'clientsecret',
    'credential',
    'keychain',
    'authorization',
    'providerbody',
    'rawproviderbody',
    'commandoutput',
    'auditlog',
    'diagnostic',
  };

  /// Returns whether [value] is safe to persist as replicated metadata.
  ///
  /// Sync identifiers must stay opaque and bounded so local paths, display
  /// names, and contact details cannot become identity fields before a future
  /// transport is explicitly approved.
  static bool isOpaqueIdentifier(String value) {
    return RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$').hasMatch(value);
  }

  static void validate(LocalFirstSyncOperation operation) {
    if (operation.payloadSchemaVersion != localFirstSyncSchemaVersion) {
      throw LocalFirstSyncSchemaException(
        'Sync schema ${operation.payloadSchemaVersion} is unsupported; update CircuitCode before accepting this envelope.',
      );
    }
    for (final value in [
      operation.operationId,
      operation.projectId,
      operation.actorId,
      operation.entityId,
      operation.timestamp.actorId,
    ]) {
      if (!isOpaqueIdentifier(value)) {
        throw const LocalFirstSyncValidationException(
          'Sync envelope identifiers must be opaque, bounded, and non-empty.',
        );
      }
    }
    if (operation.timestamp.actorId != operation.actorId) {
      throw const LocalFirstSyncValidationException(
        'The hybrid logical timestamp must belong to the envelope actor.',
      );
    }
    if (operation.timestamp.wallTimeMillis < 0 ||
        operation.timestamp.logicalCounter < 0) {
      throw const LocalFirstSyncValidationException(
        'Hybrid logical timestamps must have non-negative wall and logical values.',
      );
    }
    if (operation.predecessorIds.length > maxCausalPredecessors ||
        operation.predecessorIds.any(
          (predecessor) =>
              !isOpaqueIdentifier(predecessor) ||
              predecessor == operation.operationId,
        ) ||
        operation.predecessorIds.toSet().length !=
            operation.predecessorIds.length) {
      throw const LocalFirstSyncValidationException(
        'Causal predecessor IDs must be unique, opaque, and distinct from the operation ID.',
      );
    }
    if (operation.kind == LocalFirstSyncEntityKind.executionEvidence) {
      throw const LocalFirstSyncValidationException(
        'Commands, approvals, patch application, and workspace execution evidence are local-only.',
      );
    }
    _validatePayload(operation.payload, depth: 0);
    if (operation.kind == LocalFirstSyncEntityKind.policy) {
      final scope = operation.payload['scope'];
      final disposition = operation.payload['disposition'];
      if (scope is! String ||
          scope.trim().isEmpty ||
          _policyDisposition(disposition) == null) {
        throw const LocalFirstSyncValidationException(
          'Policy envelopes require a scope and deny, review, or allow disposition.',
        );
      }
    }
    if (operation.kind == LocalFirstSyncEntityKind.membership) {
      final memberId = operation.payload['memberId'];
      final state = operation.payload['state'];
      if (memberId is! String ||
          !isOpaqueIdentifier(memberId) ||
          operation.entityId != 'membership-$memberId' ||
          (state != 'active' && state != 'revoked')) {
        throw const LocalFirstSyncValidationException(
          'Membership envelopes require a matching opaque member ID and active or revoked state.',
        );
      }
    }
  }

  static LocalFirstSyncMergeResult merge(
    Iterable<LocalFirstSyncOperation> received, {
    required LocalFirstSyncProjectAuthority authority,
  }) {
    _validateProjectAuthority(authority);
    final incoming = received.toList(growable: false);
    if (incoming.length > maxOperationsPerMerge) {
      throw const LocalFirstSyncValidationException(
        'A sync merge exceeds the approved operation batch bound.',
      );
    }
    final unique = <String, LocalFirstSyncOperation>{};
    for (final operation in incoming) {
      validate(operation);
      if (operation.projectId != authority.projectId) {
        throw const LocalFirstSyncValidationException(
          'A sync merge may contain envelopes for its locally authorized project only.',
        );
      }
      if (operation.kind == LocalFirstSyncEntityKind.membership &&
          operation.actorId != authority.projectOwnerActorId) {
        throw const LocalFirstSyncValidationException(
          'Only the locally authorized project owner may change sync membership.',
        );
      }
      final existing = unique[operation.operationId];
      if (existing != null && !_sameEnvelope(existing, operation)) {
        throw const LocalFirstSyncValidationException(
          'An operation ID cannot be reused for a different envelope.',
        );
      }
      unique.putIfAbsent(operation.operationId, () => operation);
    }
    final pending = unique.values.toList()
      ..sort((left, right) {
        final timestamp = left.timestamp.compareTo(right.timestamp);
        return timestamp != 0
            ? timestamp
            : left.operationId.compareTo(right.operationId);
      });
    final acceptedIds = <String>{};
    final causallyReady = <LocalFirstSyncOperation>[];
    while (pending.isNotEmpty) {
      final ready = pending
          .where(
            (operation) => operation.predecessorIds.every(acceptedIds.contains),
          )
          .toList(growable: false);
      if (ready.isEmpty) break;
      for (final operation in ready) {
        pending.remove(operation);
        acceptedIds.add(operation.operationId);
        causallyReady.add(operation);
      }
    }

    final events = <LocalFirstSyncOperation>[];
    final metadata = <String, LocalFirstSyncOperation>{};
    final immutable = <String, List<LocalFirstSyncOperation>>{};
    final metadataLosers = <String, List<String>>{};
    final policies = <String, LocalFirstSyncPolicyDisposition>{};
    final policyConflicts = <String, List<String>>{};
    final revokedAt = <String, LocalFirstSyncTimestamp>{};
    final ignored = <String>{};
    final appliedIds = <String>{};

    // Resolve membership revocations before applying payloads so a late
    // dependency cannot accidentally make an event that predates revocation
    // look post-revocation merely because it became causal-ready later.
    for (final operation in causallyReady) {
      if (operation.kind != LocalFirstSyncEntityKind.membership ||
          operation.payload['state'] != 'revoked') {
        continue;
      }
      final memberId = operation.payload['memberId']! as String;
      final previous = revokedAt[memberId];
      if (previous == null || previous.compareTo(operation.timestamp) < 0) {
        revokedAt[memberId] = operation.timestamp;
      }
    }

    for (final operation in causallyReady) {
      if (!operation.predecessorIds.every(appliedIds.contains)) {
        // A causally resolved parent may still have been rejected because its
        // actor was revoked. Descendants must wait for a valid replacement,
        // not treat that rejected parent as usable history.
        continue;
      }
      final actorRevokedAt = revokedAt[operation.actorId];
      final isOwnRevocation =
          operation.kind == LocalFirstSyncEntityKind.membership &&
          operation.payload['memberId'] == operation.actorId &&
          operation.payload['state'] == 'revoked';
      if (!isOwnRevocation &&
          actorRevokedAt != null &&
          operation.timestamp.compareTo(actorRevokedAt) >= 0) {
        ignored.add(operation.operationId);
        continue;
      }

      if (operation.kind == LocalFirstSyncEntityKind.membership &&
          operation.payload['state'] == 'active') {
        final memberId = operation.payload['memberId']! as String;
        final memberRevokedAt = revokedAt[memberId];
        if (memberRevokedAt != null &&
            operation.timestamp.compareTo(memberRevokedAt) >= 0) {
          throw const LocalFirstSyncValidationException(
            'A revoked sync actor must be re-invited with a new actor ID.',
          );
        }
      }

      switch (operation.kind) {
        case LocalFirstSyncEntityKind.event:
          events.add(operation);
        case LocalFirstSyncEntityKind.metadata:
          final previous = metadata[operation.entityId];
          if (previous == null ||
              previous.timestamp.compareTo(operation.timestamp) < 0) {
            if (previous != null) {
              (metadataLosers[operation.entityId] ??= []).add(
                previous.operationId,
              );
            }
            metadata[operation.entityId] = operation;
          } else {
            (metadataLosers[operation.entityId] ??= []).add(
              operation.operationId,
            );
          }
        case LocalFirstSyncEntityKind.immutableVersion:
          (immutable[operation.entityId] ??= []).add(operation);
        case LocalFirstSyncEntityKind.policy:
          final scope = operation.payload['scope']! as String;
          final next = _policyDisposition(operation.payload['disposition'])!;
          final current = policies[scope];
          if (current != null && current != next) {
            (policyConflicts[scope] ??= []).add(operation.operationId);
          }
          policies[scope] = current == null ? next : _stricter(current, next);
        case LocalFirstSyncEntityKind.membership:
          // Membership authorization and revocation state were evaluated
          // before payload application so causal delivery order cannot alter
          // whether a pre-revocation event is admissible.
          break;
        case LocalFirstSyncEntityKind.executionEvidence:
          // Rejected by validate before merge. Keep this branch exhaustive.
          throw StateError('Local-only execution evidence cannot be merged.');
      }
      appliedIds.add(operation.operationId);
    }

    final deferred = <String>{};
    final missingPredecessors = <String, List<String>>{};
    final unresolved = [
      ...pending,
      for (final operation in causallyReady)
        if (!appliedIds.contains(operation.operationId) &&
            !ignored.contains(operation.operationId))
          operation,
    ];
    for (final operation in unresolved) {
      final missing =
          operation.predecessorIds
              .where((predecessor) => !appliedIds.contains(predecessor))
              .toSet()
              .toList()
            ..sort();
      deferred.add(operation.operationId);
      missingPredecessors[operation.operationId] = List.unmodifiable(missing);
    }

    return LocalFirstSyncMergeResult(
      events: List.unmodifiable(events),
      metadataByEntity: Map.unmodifiable(metadata),
      immutableVersionsByEntity:
          Map<String, List<LocalFirstSyncOperation>>.unmodifiable({
            for (final entry in immutable.entries)
              entry.key: List<LocalFirstSyncOperation>.unmodifiable(
                entry.value,
              ),
          }),
      metadataLoserIdsByEntity: Map<String, List<String>>.unmodifiable({
        for (final entry in metadataLosers.entries)
          entry.key: List<String>.unmodifiable(entry.value),
      }),
      policyByScope: Map.unmodifiable(policies),
      policyConflictIdsByScope: Map<String, List<String>>.unmodifiable({
        for (final entry in policyConflicts.entries)
          entry.key: List<String>.unmodifiable(entry.value),
      }),
      revokedActorIds: Set.unmodifiable(revokedAt.keys.toSet()),
      ignoredOperationIds: Set.unmodifiable(ignored),
      deferredOperationIds: Set.unmodifiable(deferred),
      missingPredecessorIdsByOperation: Map<String, List<String>>.unmodifiable(
        missingPredecessors,
      ),
    );
  }

  static void _validateProjectAuthority(
    LocalFirstSyncProjectAuthority authority,
  ) {
    if (!isOpaqueIdentifier(authority.projectId) ||
        !isOpaqueIdentifier(authority.projectOwnerActorId)) {
      throw const LocalFirstSyncValidationException(
        'Local sync authority must use opaque project and owner identifiers.',
      );
    }
  }

  static LocalFirstSyncPolicyDisposition _stricter(
    LocalFirstSyncPolicyDisposition left,
    LocalFirstSyncPolicyDisposition right,
  ) => left.index < right.index ? left : right;

  static LocalFirstSyncPolicyDisposition? _policyDisposition(Object? value) {
    if (value is! String) return null;
    return LocalFirstSyncPolicyDisposition.values
        .where((candidate) => candidate.name == value)
        .firstOrNull;
  }

  static bool _sameEnvelope(
    LocalFirstSyncOperation left,
    LocalFirstSyncOperation right,
  ) =>
      left.operationId == right.operationId &&
      left.projectId == right.projectId &&
      left.actorId == right.actorId &&
      left.entityId == right.entityId &&
      left.kind == right.kind &&
      left.payloadSchemaVersion == right.payloadSchemaVersion &&
      left.timestamp.compareTo(right.timestamp) == 0 &&
      _sameStrings(left.predecessorIds, right.predecessorIds) &&
      _sameJsonValue(left.payload, right.payload);

  static bool _sameStrings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static bool _sameJsonValue(Object? left, Object? right) {
    if (identical(left, right)) return true;
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final entry in left.entries) {
        if (entry.key is! String || !right.containsKey(entry.key)) {
          return false;
        }
        if (!_sameJsonValue(entry.value, right[entry.key])) return false;
      }
      return true;
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index++) {
        if (!_sameJsonValue(left[index], right[index])) return false;
      }
      return true;
    }
    return left == right;
  }

  static void _validatePayload(
    Map<String, Object?> payload, {
    required int depth,
  }) {
    if (depth > maxPayloadDepth || payload.length > maxPayloadEntries) {
      throw const LocalFirstSyncValidationException(
        'Sync payloads exceed the approved collaboration-envelope bounds.',
      );
    }
    for (final entry in payload.entries) {
      if (entry.key.trim().isEmpty || entry.key.length > 128) {
        throw const LocalFirstSyncValidationException(
          'Sync payload keys must be non-empty and bounded JSON field names.',
        );
      }
      final key = entry.key.trim().toLowerCase().replaceAll(
        RegExp(r'[^a-z]'),
        '',
      );
      if (_forbiddenPayloadKeys.contains(key)) {
        throw LocalFirstSyncValidationException(
          'The ${entry.key} payload class is local-only and cannot enter a sync envelope.',
        );
      }
      _validateValue(entry.value, depth: depth + 1);
    }
  }

  static void _validateValue(Object? value, {required int depth}) {
    if (depth > maxPayloadDepth) {
      throw const LocalFirstSyncValidationException(
        'Sync payload nesting exceeds the approved collaboration-envelope depth.',
      );
    }
    switch (value) {
      case null || bool() || int():
        return;
      case double number:
        if (!number.isFinite) {
          throw const LocalFirstSyncValidationException(
            'Sync payload numbers must be finite JSON values.',
          );
        }
        return;
      case String text:
        if (text.length > maxPayloadStringLength) {
          throw const LocalFirstSyncValidationException(
            'Sync payload strings exceed the approved collaboration-envelope bound.',
          );
        }
        final normalized = text.toLowerCase();
        if (RegExp(
              r'(^|\s)(token|api[_-]?key|client[_-]?secret)\s*[=:]',
            ).hasMatch(normalized) ||
            RegExp(r'\bbearer\s+\S+').hasMatch(normalized) ||
            RegExp(
              r'(^|[^a-z])/(users|private|tmp|var|home)/',
            ).hasMatch(normalized) ||
            RegExp(r'^[a-z]:\\', caseSensitive: false).hasMatch(text)) {
          throw const LocalFirstSyncValidationException(
            'Secret-shaped values and local filesystem paths are not syncable.',
          );
        }
      case Map<Object?, Object?> map:
        final jsonMap = <String, Object?>{};
        for (final entry in map.entries) {
          final key = entry.key;
          if (key is! String) {
            throw const LocalFirstSyncValidationException(
              'Sync payload maps must use string JSON field names.',
            );
          }
          jsonMap[key] = entry.value;
        }
        _validatePayload(jsonMap, depth: depth);
      case List values:
        if (values.length > maxPayloadEntries) {
          throw const LocalFirstSyncValidationException(
            'Sync payload lists exceed the approved collaboration-envelope bound.',
          );
        }
        for (final item in values) {
          _validateValue(item, depth: depth + 1);
        }
      default:
        throw const LocalFirstSyncValidationException(
          'Sync payloads must contain only JSON-shaped values.',
        );
    }
  }
}

class LocalFirstSyncValidationException implements Exception {
  final String message;

  const LocalFirstSyncValidationException(this.message);

  @override
  String toString() => message;
}

class LocalFirstSyncSchemaException implements Exception {
  final String message;

  const LocalFirstSyncSchemaException(this.message);

  @override
  String toString() => message;
}
