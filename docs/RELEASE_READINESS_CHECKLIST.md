# CircuitCode release readiness checklist

Copy this file into the protected release-evidence location for every stable
release. Keep links to CI, signing, and smoke-test evidence; do not record
credentials, app-specific passwords, source contents, or customer data. A
release is blocked until every required row is checked or an approved,
time-bounded exception is recorded and signed below.

## Record

- Version / build:
- Commit / tag:
- Release channel:
- Release owner:
- Evidence location:
- Date:

## Product and data safety

- [ ] Migration and compatibility notes reviewed; a backup/rollback plan is
      linked.
- [ ] Any schema/data migration has an exercised downgrade or recovery path.
- [ ] The appcast item's `circuit:minimumDataSchema` matches the embedded
      `CircuitDataSchemaVersion`, and migration fixtures prove the candidate
      can read the supported historical data before updating.
- [ ] Required provider, agent-evaluation, patch, command, and artifact eval
      suites passed for affected functionality.
- [ ] Context/diagnostic retention defaults and redaction behavior were
      reviewed for the candidate.
- [ ] Accessibility and performance checks were run for changed UI/streaming
      surfaces, with known limitations recorded.

## Required engineering gates

- [ ] `flutter pub get`
- [ ] `dart format --output=none --set-exit-if-changed lib test`
- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] `bash circuit-ide/scripts/security_red_team_suite.sh`
- [ ] `bash scripts/verify_security_ci.sh`
- [ ] `flutter build macos --release`
- [ ] Relevant fixture-project smoke tests, including provider streaming and
      approval/patch/verification behavior.

## Security, signing, and distribution

- [ ] The current quarterly [security review](SECURITY_REVIEW_CHECKLIST.md)
      is signed and its evidence is linked.
- [ ] Entitlements were inspected before signing and after the final signed app;
      no unapproved inbound server entitlement is present.
- [ ] Developer ID signing, hardened runtime, notarization, stapling, and
      Gatekeeper assessment succeeded for the exact distributable.
- [ ] Update channel/rollback behavior is documented for this release, or the
      release does not ship an updater and this is recorded below.
- [ ] `verify_update_release_configuration.sh` passed for the exact pre-sign
      app, and its Sparkle appcast URL/public EdDSA key were reviewed without
      recording the private signing key in release evidence.
- [ ] Stable/Beta channel selection, release notes, phased rollout, update
      deferral during active Studio work, halt, and higher-version hotfix
      recovery have an owner and exercised evidence.
- [ ] Crash/support diagnostics privacy posture is documented; redacted support
      bundle export was smoke-tested when diagnostics changed.

## Release smoke test

- [ ] Installed the exact signed/notarized artifact on a clean Mac.
- [ ] Opened the app through Gatekeeper without an exception.
- [ ] Completed the [native macOS acceptance checklist](MACOS_ACCEPTANCE.md)
      against the candidate with a non-sensitive fixture folder; results and
      any approved exception are linked below.
- [ ] Completed the [accessibility acceptance checklist](ACCESSIBILITY.md)
      with VoiceOver, keyboard-only, Increase contrast, 200% text scale,
      Reduce motion, and target-format artifact-reader results recorded for
      changed Studio or artifact surfaces.
- [ ] Connected a test provider and observed incremental text/tool output.
- [ ] When provider protocol, streaming, or image handling changed, protected
      staging evidence from `verify_provider_staging.sh` and (for a
      vision-capable model) `verify_vision_staging.sh` is linked. The retained
      evidence contains no endpoint path, response text, prompt, or
      credential.
- [ ] Reviewed/rejected and approved a safe patch/command flow; approval scope
      and expiry behaved as expected.
- [ ] Tested connector consent, token revocation, and a redacted diagnostics
      export if connectors/diagnostics changed.
- [ ] Verified launch, workspace selection, recovery/retry, and uninstall
      instructions.

## Exceptions, rollback, and sign-off

| Blocker / exception | Impact | Owner | Expiry | Rollback or mitigation |
| --- | --- | --- | --- | --- |
| | | | | |

- Release owner signature / date:
- Security reviewer signature / date:
- QA / smoke-test reviewer signature / date:
