# CircuitCode architecture

## Supported product

The Flutter application in `circuit-ide/` is the supported CircuitCode desktop
product. Retired Python GUI, TUI, and CLI packages are isolated under
`legacy/python/` for migration research only; they are not launchable root
entry points or release targets. `circuit-ide.command` opens the same Flutter
macOS app that CI builds.

## Runtime flow

1. A Studio task creates a persisted turn and selects an intent contract.
2. Context construction collects the selected workspace, direct file mentions,
   active files, instructions, LSDF, and bounded history.
3. The provider adapter streams typed content, usage, tool, and completion
   events into the Studio turn runtime.
4. Tool dispatch checks `AgentToolPermissionPolicy` before any workspace,
   network, command, Git, or MCP action.
5. Patches are proposed for review. Commands run only in the verification path
   and carry a constrained environment.
6. The turn persists its outcome, tool evidence, and user-visible progress for
   restart and review.

## Important modules

- `lib/state/studio_*` — persisted Studio threads, turns, lifecycle, and UI
  state
- `lib/ui/studio/studio_rail_row.dart` — shared semantic, focusable project
  and conversation-rail interactions
- `lib/ui/studio/studio_composer_selectors.dart` — persisted task-mode,
  specialist, permissions, and execution-mode controls; the composer facade
  retains text editing and submission ownership
- `lib/agent/providers/` — provider adapters and streaming protocol handling
- `lib/agent/security/` — tool policy, command sanitization, secret-path
  controls, and child-process environment isolation
- `lib/state/patch_proposal_provider.dart` — patch review and application
- `lib/services/generated_artifact_writer.dart` — artifact output routing
- `lib/agent/mcp/` and `lib/services/mcp_process_manager.dart` — MCP transport,
  configuration, secure tokens, and server lifecycle

## Decision records

Accepted architectural constraints live in [`adr/`](adr/README.md): Studio turn
ownership, durable state, execution security, provider protocol, artifact
lifecycle, agent isolation, and Studio UI state. New cross-cutting work must
follow the applicable ADR and extend it when the decision changes.

Collaboration remains local-first and disabled by default. The proposed
[sync and collaboration ADR](adr/0008-local-first-sync-and-collaboration.md)
defines the required identity, encryption, conflict, sharing, and organization
boundaries before any remote transport can be enabled.

## Current limitations

The macOS app is not yet process-sandboxed or notarized. A future brokered
execution boundary must prevent a compromised tool process from escaping the
approved workspace or accessing host resources. The Product Parity Master
Checklist is the authoritative list of these open requirements.
