# CircuitCode accessibility acceptance

Run this on the exact release candidate with macOS VoiceOver enabled before a
release that changes Studio. Use only a disposable non-sensitive project and
sample artifacts. Record the result in the release readiness evidence; never
retain customer prompts, files, browser captures, or artifact contents.

1. Open a project and use Tab/Shift-Tab to reach New chat, Search, New project, Settings, the Command palette, and the work-panel toggle. Confirm every control announces a name, role, and selected state where applicable.
2. Create a task, send a prompt, and confirm the transcript announces the task status, “Your message,” and “Circuit response.” While streaming, confirm the status changes are announced without moving focus from the composer.
3. Trigger a reviewed command or patch. Confirm the approval card announces the protected tool and its preview, and that Reject, Approve for this turn, and Approve once are named buttons.
4. Open Plan and Patch review. Confirm the plan/patch title, file rows, expand/review actions, and Apply changes action are reachable and clearly named. Keep focus on the relevant control after an action completes or is blocked.
5. Open every right work-panel view (Progress, Artifacts, Code, Diff, Files, Terminal, Context). Confirm the panel and each mode selector announces its name and selected state. Collapse and restore the panel, then verify focus lands on the control that changed it.
6. Run a verification command, let it complete, and confirm the terminal task event is announced with its result. Verify the composer remains usable after completion, failure, cancellation, and a rejected approval.
7. Open **Settings → App updates**. Confirm that the release channel announces both its current selection and its purpose, and that automatic checking and automatic downloading each announce a distinct setting name plus their on/off and enabled/disabled state. Confirm the disabled download setting cannot be activated until its prerequisite is enabled. Tab to each enabled toggle, confirm its focus ring is visible, and use Space to change it.
8. Enable macOS **Increase contrast** and inspect the rail, transcript, composer, drawers, focused inputs, selected task states, and approval actions in both a light and dark saved palette. Confirm text, focus rings, selected states, and action boundaries remain distinguishable without relying on hue alone. Repeat the 200% text-scale check for any changed surface.
9. Enable macOS **Reduce motion**. Start and complete a non-sensitive streaming task, open/close the right work panel, and move through a task-state transition. Confirm that status remains understandable without relying on animation, focus stays at the active control, and no essential progress cue is visible only while moving.
10. Generate one disposable DOCX, PDF, PPTX, and XLSX artifact. Use the target format's screen reader or accessibility reader to review each output. Confirm the title, section/slide order, table headers, chart/diagram descriptions where present, links/citations, and any declared accessibility gap are discoverable. Record only format, template, pass/fail, and gap category; do not retain the artifact or its content in release evidence.

Record the build number, macOS version, VoiceOver result, keyboard-only result,
contrast/text-scale/reduced-motion result, target-format artifact-reader result,
and any follow-up in the release checklist. Do not mark `CC-A11Y-001`,
`CC-A11Y-002`, `CC-A11Y-004`, or `CC-ART-007` complete until the relevant
steps pass without unlabeled or unreachable controls, focus loss, visual-only
state, or undisclosed artifact-reader gaps.
