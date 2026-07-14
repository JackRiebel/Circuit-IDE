# ADR-0010: Preserve per-command network denial during macOS sandbox migration

- Status: Proposed
- Date: 2026-07-14

## Context

`CircuitExecutionBroker` currently creates a Seatbelt profile with
`sandbox-exec`. That runner is deprecated, but its profile is also the current
enforcement point for a reviewed command's **per-request** network decision:
an unapproved command has no outbound network, while a specifically approved
command can retain the narrow network policy.

Apple's App Sandbox guidance supports an embedded helper that inherits the
containing app's sandbox and a user-selected workspace can be retained through
a security-scoped bookmark. That is not a drop-in replacement here: the host
requires outbound network access for approved providers, and an inherited
helper would receive that capability for every command. Replacing
`sandbox-exec` with inheritance alone would therefore weaken the existing
unapproved-command network denial.

## Decision

1. Introduce the Keychain-backed `circuitcode/workspace_access` native bridge
   before enabling App Sandbox. It creates/resumes only user-selected
   security-scoped workspace bookmarks; an absent or malformed persisted grant
   fails closed. The bridge is not an agent or tool surface.
2. Keep the current broker policy in force until a replacement preserves every
   current capability boundary, especially per-command network denial.
3. Evaluate a two-worker design for the replacement: a non-networked command
   helper and a separately code-signed network-capable helper, each accepting
   only an authenticated, user-approved request and a scoped workspace
   capability. The no-network worker must be the default.
4. Do not add a broad Documents/Home entitlement merely to make legacy recent
   paths work. Existing paths without an explicit scope must be reselected.

## Consequences

The workspace-scope bridge is safe groundwork for App Sandbox adoption without
claiming that the deprecated broker runner has already been replaced. Any
future helper split requires Developer ID signing, launch-constraint review,
security-scoped bookmark transfer validation, a clean-Mac escape suite, and
native privacy review before it can supersede the existing boundary.

## Verification

`macos_workspace_access_test.dart` proves bookmark persistence, resume, and
fail-closed malformed/missing grants. The macOS host source owns the matching
native channel. Existing `verify_execution_broker.sh` remains the active
security proof until an equivalent replacement harness exists.
