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
5. Do not replace the broker with a nominal XPC wrapper until it preserves the
   reviewed tool-root and per-command-network contracts. A static XPC
   `network.client` entitlement would give every inherited command generic
   egress, while omitting it prevents a command from reaching a loopback
   network mediator. Likewise, a sandboxed XPC service cannot execute a
   Homebrew/runtime tool outside its bundle merely because the service receives
   a bookmark to that tool root. Falling back silently to an unrestricted
   child would be a security regression; falling back to the existing broker is
   acceptable only while the existing reviewed profile remains the active
   enforcement point.

## XPC Feasibility Evidence

On 2026-07-15, a disposable signed app bundle embedded an XPC service with
`com.apple.security.app-sandbox=true`. The service received a plain bookmark
for one temporary workspace, explicitly started access, read that workspace,
and launched `/bin/sh` successfully. The inherited command could not read a
separate unbookmarked temporary file. This proves that an XPC service can carry
the required workspace capability without granting general host-file access.

The same probe then passed a separately created bookmark for `/opt/homebrew`
and attempted to execute `/opt/homebrew/bin/python3`. macOS denied that
command. This is consistent with Apple's documented App Sandbox restriction on
executing programs outside the app bundle/container and shows that workspace
bookmarks are not a substitute for the existing reviewed system/Homebrew tool
roots. The probe also confirmed that signing order matters: sign the XPC bundle
with its entitlement first, then sign the containing app without recursively
re-signing the nested bundle, or the XPC entitlement is lost.

Apple references: [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox),
[accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox),
and [creating XPC services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html).

## Consequences

The workspace-scope bridge is safe groundwork for App Sandbox adoption without
claiming that the deprecated broker runner has already been replaced. A full
replacement additionally needs a reviewed way to provide the command runtime
inside the sandbox or an OS-supported capability mediator that preserves
per-command network denial. Any future helper split requires Developer ID
signing, launch-constraint review, security-scoped bookmark transfer
validation, a clean-Mac escape suite, and native privacy review before it can
supersede the existing boundary.

## Verification

`macos_workspace_access_test.dart` proves bookmark persistence, resume, and
fail-closed malformed/missing grants. The macOS host source owns the matching
native channel. Existing `verify_execution_broker.sh` remains the active
security proof until an equivalent replacement harness exists.
