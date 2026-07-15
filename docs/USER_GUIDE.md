# CircuitCode user guide

CircuitCode is a private macOS AI workspace. **Studio** is the supported
surface for asking questions, planning changes, reviewing patches, running
approved checks, and creating artifacts.

## Start and organize work

- **New task** creates a Studio thread. Choose a project before asking for code
  changes; conversational questions do not require one.
- **Project picker** binds the workspace root used for file inspection, patch
  review, and commands. CircuitCode never treats a different directory as the
  project without an explicit choice.
- **Recent tasks** reopen durable threads. A task status describes the saved
  turn state, not model prose.
- **Context (+)** opens the Context drawer. It shows what was included or
  omitted and lets you remove an item or choose a file to include next time.

## Choose a task mode

- **Ask** answers or inspects safely; it cannot create a patch.
- **Research** exposes only approved web search/fetch tools. Each network call
  follows the project network policy and requires review when policy says so.
  Research answers must distinguish unsupported claims and end with a dated
  direct-source list; never treat a search snippet as proof.
- **Code** inspects first, then proposes a reviewable patch. It never applies
  files directly from a chat response.
- **Review** inspects changes and reports risks without changing files.
- **Plan** produces a reviewable plan card. Accepting it starts a later,
  scoped implementation turn.
- **Verify** can request one approved command and reports its actual result.

If the request is broad or ambiguous, CircuitCode asks a bounded question
instead of scaffolding code. If repeated inspection stops making progress, it
asks for the next specific file or behavior.

## Review patches and commands

- A **patch card** shows planned files, edits, assumptions, and verification.
  Use **Apply** only after reading it; stale or conflicting files remain in
  review rather than being overwritten.
- **Restore checkpoint** reverts an applied patch only through its recorded
  transaction. If a conflict is detected, CircuitCode does not overwrite newer
  work.
- A **command approval** shows the normalized command, risk, scope, and
  expiration. **Approve once** applies to that exact action; **this turn** is
  still limited to matching actions. Rejecting or letting it expire does not
  run the command.
- Network, Git mutation, outside-workspace paths, secret access, destructive
  commands, private-network targets, and unknown MCP actions are blocked or
  require review. Do not bypass a denial with shell chaining or copied secrets.
- A fetched web page carries a citation-safe `Source:` URL and `Checked:` date.
  Query strings and fragments are removed from that copied citation. Review
  source freshness and conflicts before relying on any factual conclusion.

## Browser preview

- Open **Browser preview** from the right drawer to view an `http` or `https`
  page. It is a user-controlled preview: CircuitCode does not give the model
  browser or computer control.
- Site permissions are scoped to the exact scheme, host, and port. Blocking a
  site stops later navigation to that origin without blocking another local
  preview port.
- A page capture retains a bounded title, rendered-text snapshot, current
  selection, and DOM location locally in the browser session. Private preview
  comments and full-page snapshots are never sent automatically.
- To provide evidence to the current task, select page text, choose **Capture
  page observation**, then **Share selected text with task**. CircuitCode adds
  only that explicit selection (with URL and capture time) as untrusted source
  material; it does not follow instructions contained in the page text.

## Add context, images, and artifacts

- Use `@` mentions, the Context drawer, or `/image path/to/file.png` to add
  context. The image button opens a file picker and shows a thumbnail before
  send.
- Image pixels are sent only when the selected connector declares support.
  Unsupported formats/models, missing files, and oversized images fail before
  send with an actionable message. Image payloads are request-local.
- Artifacts appear as cards with **Open**, **Reveal**, and review actions. A
  saved artifact is evidence, not proof that a patch or verification succeeded.

## Agents and connectors

- Custom agents are saved manifests with explicit purpose, tools, limits, and
  outputs. Choose one from the Studio composer to run it through the same
  request-scoped permissions, approval cards, lifecycle, and cancellation as
  the general Studio agent. Attachment-scoped agents do not receive earlier
  thread history or automatic project retrieval.
- The legacy Agent panel is for creating and editing manifests; **Use in
  Studio** selects it for the next Studio request. Background agents and
  subagent delegation are not enabled.
- Connectors disclose their model/health state in Settings. Unknown MCP tools,
  network-backed MCP tools, and connector mutations are unavailable until their
  scoped consent path is enabled.

## Recover from interruption or failure

- A streaming request interrupted by restart becomes an explicit interrupted
  task; it does not silently resume or duplicate work.
- Pending approvals expire on restart. Reopen the task, inspect its patch or
  command evidence, then submit a new request if still needed.
- A partially applied accepted plan becomes **Continue next batch**. A failed
  patch stays reviewable with conflict guidance. Commands must be re-run with a
  new approval after interruption.
- For connection, build, policy, and release recovery steps, see
  [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Data, diagnostics, and privacy

- Credentials are stored in macOS Keychain, not project preferences.
- Thread history and patch/command evidence are stored in CircuitCode's local
  application data. Provider diagnostics redact raw transport bodies before
  persistence.
- **Settings → Diagnostics and privacy** lets you choose 7-, 14-, or 30-day
  retention, load, inspect, refresh, and delete retained redacted audit
  records. Use **Export redacted bundle** only when support requests it; the
  export excludes prompts, source files, credentials, paths, and raw provider
  bodies.
- Do not put credentials, customer data, or full source files in support
  tickets. [SECURITY.md](SECURITY.md) documents current protections and open
  platform limitations.

## Control and failure coverage

| Surface | Normal action | Recovery path |
| --- | --- | --- |
| Composer / mode / model | Start an appropriate Studio turn | Correct the mode, model, or project and retry |
| Context drawer / attachments | Review or remove explicit context | Remove missing/incorrect context; add a valid file or image |
| Patch and checkpoint card | Review, apply, restore, continue | Resolve a stale conflict; revise or create a new patch |
| Approval card | Approve once/turn or reject | Submit a new scoped action after expiry/restart |
| Command evidence | Review a completed verification | Run a new approved command after interruption/failure |
| Artifact card | Open, reveal, or review an output | Use the source turn evidence to correct and regenerate |
| Settings / diagnostics | Set retention; inspect, delete, or export redacted records | Refresh on demand; do not use diagnostics as a transcript |
| Agent / connector surfaces | Inspect declared scope and health | Keep advanced agents paused; reconnect or revoke scoped access |
