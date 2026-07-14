# ADR-0007: Studio UI state ownership

- Status: Accepted
- Date: 2026-07-10

## Context

Large Studio surfaces make duplicate derived state and oversized rebuild
regions easy to introduce.

## Decision

Screens render durable turn/thread projections plus local view state only.
Transcript, rail state, progress, approval cards, token usage, and outcomes
come from the selected persisted thread/turn. Views never render model-only
prompts or provider diagnostics as user transcript content.

## Consequences

Feature modules own their widgets and selectors; rendering convenience is not
an excuse to read legacy chat state or mutate runtime state directly. UI
composition must preserve keyboard access and deterministic status labels.

## Verification

Widget flows, state isolation, and no-legacy-dependency tests protect the
boundary while the current monoliths are split.
