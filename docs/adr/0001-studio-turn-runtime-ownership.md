# ADR-0001: Studio turn runtime ownership

- Status: Accepted
- Date: 2026-07-10

## Context

Studio previously had overlapping chat, task, provider, and UI state. That
makes an interrupted or retried task ambiguous and permits stale global state
to change what the user sees.

## Decision

`StudioTurn` is the durable unit of work. Its state machine owns the lifecycle,
approvals, patch-review and verification phases. `StudioThread` is a durable
ordered container and projection of its turns; UI controllers may hold only
ephemeral selection, composition, and rendering state. A turn separates its
display prompt, model prompt, and task title.

## Consequences

All provider, tool, patch, and completion events must identify a request and
turn before they alter Studio. Illegal terminal transitions are rejected.
Legacy chat state is not a Studio dependency. New state must be derived from
persisted turns or added to the typed turn envelope.

## Verification

State-machine, restart, and legacy-dependency tests cover the contract.
