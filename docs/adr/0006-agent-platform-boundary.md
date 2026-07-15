# ADR-0006: Agent platform boundary

- Status: Accepted
- Date: 2026-07-10

## Context

Custom agents can amplify privileged actions and context leakage if they use
a parallel, auto-approved runtime.

## Decision

Every enabled agent runs through the Studio turn runtime with a narrow,
declared context and the shared permission policy. Agents emit typed lifecycle
and result envelopes; they may not inherit another thread's full history or
grant themselves undeclared tools/connectors.

## Consequences

Legacy direct-agent and auto-approve paths remain disabled until they conform
to this contract. Agent manifests, evaluation fixtures, and enablement checks
are prerequisites for a user-facing agent library.

## Verification

Isolation, permission, cancellation, and adversarial-agent tests are required
before an agent capability is enabled.
