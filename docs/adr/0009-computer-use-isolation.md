# ADR-0009: Computer-use isolation before enablement

- Status: Proposed
- Date: 2026-07-13

## Context

Desktop automation combines model output with access to applications, browser
sessions, clipboard-like data, and sensitive fields. It must not inherit the
Studio coding runtime, the browser-preview state, or broad macOS permissions.

## Decision

Computer use remains disabled and is not registered as a Studio tool. Any
computer/desktop/screen/mouse/keyboard/accessibility-shaped model tool call is
explicitly denied by the shared permission policy.

Before a future executor can be enabled, it must run as a separate visible
session with all of the following contracts:

1. Every proposed action is a display-safe preview bound to that session. It
   names the target application, optional exact domain, target role/label, and
   action summary; raw typed values and pixels are excluded from the proposal.
   In particular, a `typeText` proposal renders only its character count, even
   if a model tries to place the value in its summary. The preview derives all
   non-typing summaries from the action kind and bounded display-safe target
   fields as well, so model-supplied summaries cannot reflect paths, secrets,
   or arbitrary text into the review surface.
2. The user configures exact application/domain allowlists for that one
   session. Empty allowlists deny all actions, and the session takes an
   immutable normalized copy so later mutable input cannot broaden it.
3. Every action requires a fresh explicit user confirmation. A review preview
   expires after two minutes and is denied when its timestamp is in the future,
   so a future worker must re-inspect the visible target and obtain a new
   review rather than replaying a stale proposal. The local policy may return
   only **deny** or **requires user review**; it cannot dispatch an action
   itself.
4. Passwords, OTPs, tokens, payment data, and other sensitive fields are
   denied. Session visibility, target identity, session identity, and
   allowlists are rechecked immediately before any future dispatch. A target
   must also carry evidence that the visible native session—not the model—
   inspected it; oversized, secret-shaped, path-shaped, or control-character
   target details are denied rather than rendered into the preview.
5. An emergency stop clears pending action proposals and halts the session.
   Restarting requires a new visible session and new policy configuration. A
   session retains only one non-empty, session-bound pending proposal at a
   time, so user review cannot accumulate a reusable action queue.

The pre-enable contract is action-specific: every proposal other than an
application launch must name both a visible target role and label; navigation
also requires a syntactically valid exact hostname; and typing requires a
positive character count. URL/path/port/wildcard-shaped values are never
allowlist domains. The sensitive-field deny list also includes verification
codes, recovery phrases, private keys, and bank-routing/account data.

## Consequences

There is no desktop-control implementation, macOS accessibility entitlement,
model tool registration, or implicit browser-to-computer bridge in this
release. The model cannot create or operate a computer-use session.

## Verification

`computer_use_safety_policy_test.dart` proves disabled-by-default behavior,
review-first action previews, exact app/domain allowlists, sensitive-field
denial, session mismatch denial, and emergency stop. `agent_permission_boundary_test.dart`
proves computer-use-shaped tool calls are hard denied before generic unknown
tool handling.

The same contract suite additionally proves typed previews never reveal a
model-supplied value, caller-owned allowlist sets cannot be mutated after the
session starts, and missing session/action identities fail closed.
It also proves untargeted pointer actions, domain-less navigation, zero-length
typing, malformed domain entries, stale/future-dated action previews, and the
expanded sensitive-field cases fail closed before any future worker could be
invoked.

The contract additionally proves that a model-proposed target cannot reach
review without native-inspection evidence, non-typing summaries discard seeded
secret/path text, unsafe target text is denied, and sessions reject multiple,
wrong-session, or halted pending actions.

Enablement additionally requires a dedicated isolated-worker implementation,
native accessibility/privacy review, user-visible action-preview acceptance,
and an adversarial computer-use red-team suite.
