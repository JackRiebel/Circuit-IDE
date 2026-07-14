# CircuitCode native macOS acceptance

Run this checklist on the exact Release candidate after its automated macOS
host, packaged-launch, broker, and entitlement gates pass. Use a disposable
local fixture folder and a non-sensitive file. Do not use customer projects,
provider credentials, or generated customer deliverables as test inputs.

Record the candidate version, macOS version, Mac model, test account, and the
result of every step in the protected release evidence. A failed step blocks
the candidate until it is fixed or has a signed, time-bounded exception.

## Window and standard application behavior

1. Launch the app from Finder. Confirm the title bar has native traffic-light
   controls with no overlap into CircuitCode content, and resize/minimize/zoom
   the window through both the traffic lights and the standard Window menu.
2. Inspect the App, File, Edit, View, Window, and Help menus. Confirm the App
   menu includes Services; File includes **Open…**; and normal macOS shortcuts
   such as Command-O, Command-W, Command-Q, Command-C, Command-V, and
   Control-Command-F work when their selected control permits them.
3. Move and resize the window to a distinctive position, quit the app, then
   relaunch it. Confirm the saved frame restores. On a clean test account,
   confirm first launch centers the window instead of restoring another app's
   window frame.

## Open, Finder, and drag/drop behavior

1. Choose **File → Open…** (and repeat with Command-O). Select the disposable
   fixture folder. Confirm the native Open panel closes, the project binds in
   Studio, and the project appears in recent projects.
2. Repeat **File → Open…** with a regular file inside that folder. Confirm its
   containing folder binds first and the exact file opens in the Studio Files
   surface. Cancel the Open panel once and confirm it does not alter the
   current workspace.
3. With the app already running, open the same fixture file from Finder. Then
   quit the app and open the file again from Finder or the Dock's recent
   documents. In both cases, confirm the app activates and follows the same
   containing-folder-plus-exact-file behavior without duplicate workspace
   records.
4. Drag the fixture folder and then the fixture file from Finder onto the
   CircuitCode window. Confirm each is accepted once and follows the same
   behavior as File → Open. Drag a non-file item and confirm it is ignored.

## Artifact reveal and work preservation

1. Generate or use a non-sensitive local artifact, then choose its visible
   **Reveal in Finder** action. Confirm Finder opens and selects that exact
   artifact, not merely its parent directory. Confirm a missing artifact
   produces an actionable in-app error rather than opening an arbitrary path.
2. Open a task with an active or pending Studio action, then verify that normal
   app close/reopen behavior preserves the documented recovery choice and
   never silently reruns a command, patch, or provider request.
3. Verify the app reopens after its last window was closed from the Dock and
   returns to a usable window without creating a second product session.

## Browser preview privacy and origin controls

1. In the disposable fixture folder, create a non-sensitive HTML file that
   contains a short unique sentence, then serve it only on loopback (for
   example, with `python3 -m http.server --bind 127.0.0.1 --directory <fixture>
   8765`). Open it through **Browser preview** using a URL with a harmless
   query and fragment, such as `http://127.0.0.1:8765/browser-fixture.html?review=local#fact`.
   Confirm the tab shows only that visible local page; do not use a customer or
   public page for this acceptance check.
2. Select the unique sentence and add a private browser note. Confirm neither
   the note nor the page preview appears in task context or Sources
   automatically. Select **Share selected text with task** and confirm Sources
   now contains only the explicit selection with its capture time and a
   canonical URL that omits the query and fragment.
3. Capture the visible page, select **Save visible pixels locally with this
   task**, and accept the sensitive-data confirmation. Confirm the Sources
   entry contains provenance (capture time, byte count, and hash) rather than
   image bytes or page text; use **Reveal in Finder** to inspect the confined
   local PNG. Delete that saved snapshot and confirm both the Sources record
   and its local file are removed. Do not attach the PNG to release evidence.
4. Block the exact loopback origin. Confirm the active tab immediately clears
   its snapshot/selection and shows the explicit **Site blocked** recovery
   state; retry the same URL and confirm no page is loaded. Confirm a different
   loopback port remains a distinct permission scope. Stop the local server and
   remove the disposable fixture when finished.

## Pass criteria and handoff

The candidate passes only when every expected native action works once,
without duplicate delivery, data loss, unexpected workspace changes, clipped
title-bar controls, focus loss, browser data shared without an explicit action,
or an origin block that still loads visible content. Link the automated gate
output and a short step-by-step result summary in the release readiness
checklist. Do not attach screenshots that expose workspace content, browser
pixels, or the fixture file itself.

This manual review is the acceptance evidence for `CC-UI-012`; it complements
but does not replace the automated native host, menu-resource, file-open, and
packaged-app tests.
