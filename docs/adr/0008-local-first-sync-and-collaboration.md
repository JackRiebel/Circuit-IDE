# ADR-0008: local-first sync and collaboration

- Status: Proposed — no remote sync client, endpoint, or background uploader
  may ship until this record has security and product approval.
- Date: 2026-07-12
- Owners: Studio platform, security, and enterprise administration

## Context

CircuitCode currently keeps projects, threads, tasks, patch metadata, artifacts,
and diagnostics on the local machine. That is the intended default. A future
collaboration feature must not turn workspace contents, prompts, credentials,
or command output into ambient cloud data simply because a user signs in.

## Decision

### Identity and local records

- Every syncable record receives a random, immutable, installation-independent
  identifier. Existing local IDs are retained as legacy aliases during
  migration; filesystem paths, display names, and user email addresses are
  never sync identifiers.
- A project has a random project ID and a separately stored local workspace
  binding. One project may have multiple local workspace bindings, but a local
  path is never sent as the project identity.
- The client records an append-only, schema-versioned operation envelope with
  operation ID, project ID, actor/device ID, causal predecessor IDs, entity
  ID, payload schema version, and hybrid logical timestamp. It does not sync
  unbounded local audit logs.

### Encryption and keys

- Sync is opt-in per project and remains disabled by default.
- Before any remote implementation, the project content key must be generated
  locally and kept in the platform secure store. Remote services store only
  encrypted operation envelopes and encrypted wrapped project keys.
- The production cryptographic implementation must use an independently
  reviewed authenticated-encryption design, explicit associated data
  (project/operation/schema identifiers), unique nonces, key rotation, and
  recovery/revocation semantics. The local envelope foundation uses AES-256-GCM
  with that associated-data shape, fresh nonces, and Keychain-backed,
  versioned project keys; it is deliberately not a remote transport,
  member-key wrapping system, or approved production sync feature. Independent
  review remains required before any remote or user-export flow is enabled.
- Credentials, Keychain references, raw provider bodies, raw command output,
  private diagnostics, and local-only workspace bindings are never syncable
  payload classes. Their schema validators must reject them before encryption.

### Conflict policy

| Entity | Concurrent update behavior | Automatic merge allowed? |
| --- | --- | --- |
| Task/thread events and messages | append both causally distinct events | Yes; event union only |
| Rename, pin, archive, labels | hybrid-logical-clock last writer wins, retaining loser metadata for audit | Yes |
| Plans, patches, artifacts, checkpoints | immutable child/version records; preserve both parents | Yes; never overwrite payload |
| Workspace file changes, patch application, commands, approvals | local execution evidence only; require explicit user review to carry forward | No |
| Permissions, network rules, organization policy | stricter policy wins; conflict is visible and blocks unsafe execution | No silent relaxation |

No conflict resolver may apply a remote patch, reuse an approval, start a
command, or modify a local workspace. The resolver produces a reviewable
choice or an immutable fork.

### Sharing and organization boundaries

- Sharing starts with a named project, named recipients, an explicit scope,
  and a visible data-class preview. The default scope is metadata and
  collaboration events, not workspace files.
- Membership and wrapped-key changes require the project owner’s explicit
  approval. Revocation stops new envelope/key access, records the event, and
  rotates the project key for future content; it cannot erase data a former
  member already decrypted.
- The deterministic merge contract receives the project ID and owner actor ID
  from locally trusted project state, never from a received envelope. It
  rejects membership mutations from any other actor. This is a pre-transport
  authorization boundary, not a substitute for the future signed,
  cryptographically verified actor identity requirement.
- Organization-managed sync requires an approved tenant endpoint, retention,
  export, DLP, legal-hold, and administrator-recovery policy. The personal
  encrypted mode and an organization mode are distinct configuration paths.
- Browser/computer sessions, connectors, and task execution remain local and
  are never controlled through a collaboration event.

### Rollout boundary

1. Validate this design with security/product review and deterministic local
   conflict simulations.
2. Ship an encrypted, user-initiated export/import prototype with no network
   transport only after its key/recovery review.
3. Add a staged remote transport behind a feature flag, per-project consent,
   envelope schema migration, and a kill switch.
4. Enable organization mode only after tenant policy and incident-response
   exercises are approved.

## Required verification before implementation

- Migration fixtures preserve legacy IDs and never emit local paths or secrets.
- Two-device simulations cover append ordering, simultaneous rename/archive,
  immutable patch/artifact forks, stricter-policy wins, revoked membership,
  offline replay, duplicate delivery, and schema downgrade refusal.
- Seeded-secret scans prove excluded data classes cannot enter an encrypted
  envelope or export.
- Security review covers key generation, wrapping, rotation, recovery,
  revocation, endpoint trust, metadata leakage, and incident response.
- Product acceptance proves users can inspect sharing scope and resolve every
  non-automatic conflict without hidden workspace mutation.

## Current local simulation evidence

`circuit-ide/lib/services/local_first_sync_contract.dart` is a deterministic,
transport-free contract simulator. Alongside it,
`circuit-ide/lib/services/local_first_sync_encryption.dart` seals only
validated contract operations with AES-256-GCM. The outer envelope retains
only opaque project/operation/schema/key-version routing metadata; those
fields are authenticated as associated data, while the actor, timestamp,
predecessors, entity, and payload are encrypted. Per-project keys are created
and versioned in platform secure storage, and old key versions remain readable
only for explicit recovery after rotation. A local encrypted journal stages
only those sealed envelopes through a bounded regular file plus sibling staging
and atomic rename; it never writes a plaintext operation. A superseded local
key can be retired only after rotation, which cuts off local recovery for its
historical envelopes without deleting the current key. These local controls do
not distribute revocations or wrapped keys. Neither service has a transport,
account, uploader, remote storage, feature flag, or sharing UI.

`circuit-ide/test/local_first_sync_contract_test.dart` exercises legacy-alias
migration with excluded local bindings, seeded secret/path/raw diagnostic
rejection, two-device event ordering and duplicate delivery, rename/archive
last-writer-wins audit records, immutable patch/artifact forks, stricter-policy
conflict handling, revocation with offline replay rejection, and future-schema
refusal. `local_first_sync_encryption_test.dart` proves encrypted round trips,
fresh nonces, associated-data/ciphertext tamper refusal, missing-key refusal,
rotation recovery, local historical-key retirement, and pre-encryption
excluded-data refusal. `local_first_sync_encrypted_journal_test.dart` proves
concurrent append serialization, ciphertext-only atomic persistence, bounded
and duplicate-record refusal, tamper refusal, and symlink refusal. `bash
circuit-ide/scripts/verify_sync_architecture.sh` runs all suites and guards
this ADR's disabled-by-default boundary in CI.

Membership acceptance is also bound to a locally supplied opaque project-owner
actor ID. A non-owner envelope cannot revoke or activate a member merely by
arriving in a merge batch. Until a remote design verifies and signs actor
identity, this remains a deterministic local check rather than proof of remote
authorization.

These simulations and the local encrypted-envelope foundation do not implement
remote storage, account membership, member key wrapping, sharing UI, transport,
or a feature flag, and they cannot replace the listed security/product
approvals.

The local validator also requires bounded JSON-only payloads, finite numbers,
string map keys, bounded nesting/collection/string sizes, non-negative hybrid
logical timestamps, and bounded causal predecessor lists. It compares duplicate
envelopes structurally rather than by map insertion order. These are
pre-encryption envelope constraints, not a cryptographic implementation or a
claim that any data can leave the device.

The deterministic merge resolves causal predecessors before applying an
operation. Missing or cyclic predecessor graphs remain deferred with their
missing opaque IDs; they do not become sync history merely because their own
envelope is well-formed. A descendant cannot use a parent rejected for a
post-revocation actor as causal history. Conversely, revocation is evaluated
against the hybrid logical timestamp, so an event that genuinely predates a
later revocation is not lost when an unrelated dependency arrives later. Merge
batches are bounded, membership entity IDs must match their member IDs, and a
revoked actor cannot be activated again under the same identity: a future
approved transport must provision a new actor/key identity instead.

## Consequences

This keeps CircuitCode useful with no account or network connection and makes
collaboration an explicit data-sharing decision. It also means sync cannot be
advertised or feature-enabled until the cryptographic/storage design, review,
and simulations above are implemented and accepted.
