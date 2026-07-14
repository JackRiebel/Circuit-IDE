# ADR-0002: Durable state, schema, and recovery

- Status: Accepted
- Date: 2026-07-10

## Context

Threads, patches, command evidence, artifacts, settings, and agent state must
survive restart without silently changing their meaning. Partial patch writes
are especially unsafe.

## Decision

Durable records use typed JSON envelopes with an explicit schema version and
forward-only migrations. A migration first writes a backup beside the source;
an unsupported newer version is retained untouched and reported with a
recovery action. Mutable workspace edits use a separate write-ahead journal,
snapshot before mutation, and atomic replacement.

## Consequences

Adding persistent fields requires a migration fixture and a round-trip test.
Readers never discard a record merely because it comes from a newer schema.
Compaction may omit historical detail only through a documented summary
projection, never by changing the authoritative history semantics.

## Verification

Schema fixtures cover every supported version; crash-injection tests cover
patch-journal recovery.
