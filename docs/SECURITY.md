# CircuitCode security status

## Threat model

CircuitCode protects five primary asset classes: Keychain-held credentials;
workspace/Git/checkpoint/artifact data; provider and connector requests;
persisted Studio/diagnostic/support-bundle records; and signed/notarized
release artifacts. The critical trust boundaries are user/repository text to
model output, model output to the local permission policy, policy to the tool
executor/child process, connector data to the transcript, and build output to
the macOS distribution channel.

We assume a malicious repository, prompt-injected model response, compromised
or over-privileged connector, poisoned child-process output, stolen local
device, dependency compromise, and update/distribution tampering are plausible
attackers. The local policy, scoped approvals, redaction, Keychain, and child
environment controls must therefore be treated as enforcement points rather
than provider-prompt suggestions.

## Controls currently in place

- Provider and GitHub credentials use `flutter_secure_storage` / macOS
  Keychain. Legacy plaintext credential settings are migrated only after a
  successful secure write.
- Studio tool policy distinguishes read-only access, patch proposal/application,
  command verification, Git mutation, public-network access, and MCP risk.
- Generated-artifact materialization and export call the same policy engine.
  They require an explicit artifact request and can write only inside the
  active workspace's `outputs/` directory.
- Secret paths, destructive commands, nested shells, unapproved network use,
  private network targets, and outside-workspace command paths are blocked in
  the Studio execution path.
- A macOS brokered command with reviewed public-network access receives only a
  broker-owned loopback HTTP(S) proxy. Direct child sockets remain blocked;
  the proxy resolves each requested host once, rejects every private,
  reserved, or ambiguous answer, and connects only to the selected numeric
  public address. Proxy-incompatible raw egress fails closed.
- Agent commands and MCP child processes receive an allowlisted base
  environment. Connector-declared tokens are injected explicitly, and child
  stdout/stderr is redacted before diagnostic logging.
- Release and debug entitlements no longer request the macOS network-server
  capability.
- A required CI security red-team job runs policy-injection, path/symlink,
  destructive-command, Git, MCP, network/exfiltration, child-environment, and
  secret-storage tests. Public network actions remain review-gated; private
  network targets and untrusted MCP browser/network calls fail closed.
- The required aggregate CI run performs a full-history Gitleaks scan with
  the scanner's default rules, pinned OSV dependency scanning, SBOM creation,
  and a runner-local vulnerable-fixture exercise. The Gitleaks exception
  policy may name only reviewed historic commit IDs; a checked-in guard
  rejects path, pattern, stopword, or rule-wide bypasses and default-rule
  disablement.
- Computer use is feature-disabled: no desktop-control executor or model tool
  is registered. Computer-shaped tool calls fail closed in the shared policy;
  ADR-0009 requires a separate visible, review-only session before enablement.
- Persisted legacy-agent audit records now redact prompt and tool content,
  paths, URLs, secrets, environment values, and error context before writing.
  **Studio Settings → Diagnostics and privacy** lets users choose a 7-, 14-,
  or 30-day retention period, purge expired records on demand, inspect/delete
  retained diagnostics, and export a user-selected redacted support bundle.
  Export structurally re-redacts retained records and metadata before writing.
  Persisted Studio provider diagnostics use the same redactor and replace raw
  transport bodies with a length-only placeholder.

## P0 control mapping

| Control | Threat addressed | Current enforcement/evidence |
| --- | --- | --- |
| CC-SEC-001 | Credential theft from local files | Keychain-only storage and fail-closed migration tests. |
| CC-SEC-002 | Model/child escape to host resources | Shared policy plus the packaged `CircuitExecutionBroker`: a default-deny workspace/tool profile, loopback-only DNS-validating network proxy, sanitized child environment, CPU/file-descriptor limits, and an escape harness. The `sandbox-exec` implementation, clean-Mac run, and notarized Keychain proof remain open. |
| CC-SEC-003 | Unexpected inbound network surface | Release/debug entitlement inspection and final signed-app verification. |
| CC-SEC-004 | Environment/secret inheritance | Allowlisted child environments plus output redaction tests. |
| CC-SEC-005 | Ungoverned tool or mutation route | One policy inventory and boundary-route tests. |
| CC-SEC-007 | Confused-deputy approvals | Normalized action keys, expiry, durable scope, and recovery tests. |
| CC-SEC-008 | Secret retention or support-data leakage | Central redaction, retention/purge controls, and seeded-secret bundle tests. |

The required release evidence for these controls is the red-team suite,
entitlement inspection, CI security topology, and a signed quarterly review in
[SECURITY_REVIEW_CHECKLIST.md](SECURITY_REVIEW_CHECKLIST.md). The release owner
records those links in [RELEASE_READINESS_CHECKLIST.md](RELEASE_READINESS_CHECKLIST.md).

## Incident response

1. **Contain.** Stop active Studio tasks, disable the affected connector,
   revoke its Keychain token, and block the affected release/update channel.
2. **Assess.** Preserve only redacted diagnostics; identify version, connector
   scope, policy/approval events, and affected project metadata without
   collecting source or secrets unnecessarily.
3. **Recover.** Rotate credentials with the relevant provider, implement and
   review a fix, re-run the security/release gates, and ship only a signed,
   notarized artifact with smoke-test evidence.
4. **Communicate and learn.** Use approved support/security channels for any
   required notification. Record owner, remediation due date, and verification
   evidence in the quarterly review; update this threat model when the trust
   boundary or attacker assumption changed.

## Residual risks

Release builds bundle a separately signed `CircuitExecutionBroker` that
applies a default-deny Seatbelt profile before launching a reviewed command.
On macOS 26, `sandbox-exec` refuses an executable launched directly from an
`.app` bundle, so CircuitCode first verifies that bundled helper and atomically
stages a fresh owner-only copy in a private per-user runtime directory. A
missing, invalid, or unstaged helper fails closed rather than falling back to
a direct shell.
It permits the approved workspace, bounded system tool roots, a private
workspace temporary directory, and only a broker-owned loopback proxy for a
reviewed network command. The command cannot connect directly to a network
peer: the proxy validates all DNS answers and opens its own pinned public-IP
socket. The escape harness covers outside-root/symlink reads, writes, process
inspection, environment leakage, direct-network bypass, private-target proxy
rejection, proxied public egress, and broad tool-root rejection. This is
meaningful OS-level isolation, but it is not a claim of
complete host isolation: the profile still relies on deprecated
`sandbox-exec`, and clean-Mac/Developer-ID/notarized Keychain-escape evidence
is required before `CC-SEC-002` can close. On the current macOS 26 host,
`sandbox-exec` refuses the helper when it runs directly from an app bundle; the
verified fresh owner-only staging step avoids that refusal, and the exact
embedded Release helper passes the staged packaged escape harness. That local
evidence does not replace the planned XPC migration or signed clean-Mac proof.
Network, connector, storage, audit-log, and approval hardening remain tracked by `CC-SEC-002` and
`CC-SEC-005` through `CC-SEC-009` in the Product Parity Master Checklist.

## Reporting and operation

Do not include secrets, customer data, or production tokens in issue reports.
Export the redacted support bundle from **Studio Settings → Diagnostics and
privacy** when support requests it. It is designed for failure categories and
metadata, not for sharing prompts, source files, credentials, or raw provider
bodies. Inspect the bundle before sending it if your organization has stricter
data-handling requirements.

Run `bash scripts/verify_security_docs.sh` after editing the threat model or
release/security checklists. Complete and sign the quarterly checklist before
every stable release that changes the described security boundaries.
