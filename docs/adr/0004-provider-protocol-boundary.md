# ADR-0004: Provider protocol boundary

- Status: Accepted
- Date: 2026-07-10

## Context

External providers differ in stream framing, tool representations, token
accounting, capability, and failure behavior. Display text cannot safely serve
as runtime control flow.

## Decision

Adapters translate provider responses into typed lifecycle events and typed
tool envelopes. The protocol will be versioned and capability-negotiated; new
features need a fixture-backed contract before Studio exposes them. Token
input and output accounting remain separate.

## Consequences

Provider-specific payloads do not leak into Studio UI state. Unknown or
unsupported fields fail with an actionable compatibility result, never a
best-effort mutation.

## Verification

Recorded-stream contract tests cover incremental text, tools, usage, errors,
and terminal conditions.
