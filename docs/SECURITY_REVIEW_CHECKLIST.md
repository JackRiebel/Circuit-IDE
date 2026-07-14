# CircuitCode quarterly security review

Use this checklist once each calendar quarter and before any stable release
that changes permissions, providers, connectors, updates, or macOS packaging.
It is a signed operating record, not a substitute for a production incident
response plan. Store the completed copy with the release evidence; do not put
tokens, customer prompts, source files, or credential values in it.

## Record

- Review period:
- Build / commit:
- Review owner:
- Independent reviewer:
- Date completed:
- Evidence location:

## Assets and trust boundaries

Confirm that the threat model in [SECURITY.md](SECURITY.md) still describes:

- [ ] Keychain-held provider, GitHub, and connector credentials.
- [ ] Workspace files, generated artifacts, checkpoints, and Git state.
- [ ] Provider requests and streamed responses.
- [ ] MCP/command child processes, their environment, and their stdout/stderr.
- [ ] Persisted Studio state, diagnostics, support bundles, update packages,
      signing identity, and notarization tickets.
- [ ] The boundaries between user input/repository text, model output, local
      policy, the operating system, connectors, and release distribution.

## P0 control mapping

Record a link, command output, test run, or exception for every row.

| Control | Review question | Evidence / exception |
| --- | --- | --- |
| CC-SEC-001 | Are credentials Keychain-only and legacy migration still fail-closed? | |
| CC-SEC-002 | Does the brokered/OS execution boundary limit roots, processes, Keychain, and network as documented? | |
| CC-SEC-003 | Do release entitlements contain no inbound server capability, and is that true after signing/notarization? | |
| CC-SEC-004 | Do commands/MCP children receive only the allowlisted environment and redacted logs? | |
| CC-SEC-005 | Does every exposed tool and app-owned mutation route through the shared policy inventory? | |
| CC-SEC-007 | Are approval scope, normalized action, expiry, recovery, and audit records still enforced? | |
| CC-SEC-008 | Do retained diagnostics/support bundles pass seeded-secret redaction checks and obey retention/purge? | |

## Required security evidence

- [ ] `bash circuit-ide/scripts/security_red_team_suite.sh` passed; attach the
      console output or CI URL.
- [ ] `bash scripts/verify_security_ci.sh` passed and required branch checks
      are configured by repository administrators.
- [ ] The manual `Security scanner fixture exercise` workflow was dispatched
      from the reviewed revision and completed green only after both Gitleaks
      and OSV rejected their runner-local controlled fixtures. Link the run;
      do not retain scanner logs or fixture contents in this record.
- [ ] If browser preview changed, review the loopback WebKit host-test result
      and confirm that the preview still has no Circuit JavaScript channel or
      model tool route; only explicit selected text may enter task context.
- [ ] `bash circuit-ide/scripts/verify_release_entitlements.sh <app>` passed
      for the candidate app, or the release is explicitly blocked before
      signing.
- [ ] Provider protocol compatibility, connector consent/revocation, and
      signed plugin-package tests were reviewed for the candidate changes.
- [ ] Dependency/security scan results were triaged; accepted risks include an
      owner, expiry, and mitigation.
- [ ] Open P0 exceptions are listed below and release impact is explicit.

## Incident response exercise

- [ ] A suspected credential/connector leak exercise used only redacted test
      values.
- [ ] The team practiced containment: disable connector, revoke Keychain token,
      stop active runs, preserve redacted diagnostics, and rotate affected
      credentials with the provider.
- [ ] The team practiced assessment: identify affected version, workspace,
      connector scope, and support-bundle evidence without collecting source or
      secret data unnecessarily.
- [ ] The team practiced recovery: ship/review a fix, verify scans and
      entitlements, publish customer communication through approved channels,
      then record a corrective-action owner and due date.

## Exceptions and decisions

| Risk / control | Decision | Owner | Expiry | Follow-up evidence |
| --- | --- | --- | --- | --- |
| | | | | |

## Sign-off

By signing, reviewers confirm that the evidence above was inspected and that
any remaining risks are visible to the release owner.

- Review owner signature / date:
- Independent reviewer signature / date:
- Release owner acknowledgement / date:
