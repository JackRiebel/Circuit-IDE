# ADR-0003: Execution security boundary

- Status: Accepted
- Date: 2026-07-10

## Context

Provider output, tools, MCP servers, and shell processes are untrusted input.
Prompt guidance cannot enforce local permission or host isolation.

## Decision

Local typed policy evaluates every tool call before dispatch. The policy is
fail-closed for mutation, command, Git, network, MCP, and secret access, and
approvals are scoped to the exact operation. Child processes receive an
allowlisted environment; credentials remain in Keychain-backed storage. A
future brokered OS sandbox is required before untrusted code can be treated as
host-isolated.

## Consequences

No provider, connector, agent, or UI path may bypass the policy. The product
must state that OS-level sandboxing is not complete rather than implying it.

## Verification

Permission-boundary, malicious-input, environment, and secure-storage tests
are required for relevant changes.
