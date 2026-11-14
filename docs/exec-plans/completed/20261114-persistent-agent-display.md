# Persistent agent display between turns

## Goal and authority

The user approved OCU virtual-display window hosting with Agent Desktop semantic actions, and explicitly requested that agent windows remain hidden after operations and between Codex turns. Keep the user's physical screens, system pointer and focus available. Implementation, installation and actual cross-session verification are authorized; do not change other machines or restore paused business tasks.

## Current facts

`resetOpenComputerUseBackgroundWindowState` restores all AgentDisplay windows on MCP turn-ended, connection teardown and distributed turn-end hooks. The macOS app agent already outlives individual MCP clients, so it can retain the virtual display. Explicit `restore` and process exit already have recovery paths. The existing installed runtime is shared; other windows are currently parked, and its source checkout contains unrelated pending input changes.

## Change

- Add `virtualDisplay.restoreOnSessionEnd` (default true for compatibility), resolving strict JSON booleans and an optional environment override. Record the policy when a window is parked, while request configuration is available.
- Session cleanup restores transient windows, prunes closed targets, and leaves retained windows/display alive. Explicit restore still returns them; a real owner-process exit retains its best-effort recovery. No state is serialized as credentials or window content.
- Preserve query-index and overlay cleanup. Keep the existing occlusion pin for retained windows so overlapping Chromium/Electron windows do not lose their content between clients; release transient pins and discard stale identity records. Explicit restore and true process exit retain full recovery. New clients must take fresh snapshots before actions.
- Record and revalidate PID, process launch date and AX window identity before reusing/restoring a record; prune closed or replaced targets without moving their replacements. Unknown observation keeps the recovery record rather than treating the window as closed.
- Namespace the distributed turn-end notification name using the same namespace identity as the app-agent socket. A namespaced Stop hook must not broadcast the legacy notification that old installed agents listen to. Keep the unnamespaced name for unnamespaced legacy clients.
- Build from an immutable export of the committed baseline plus only this task's changes; keep unrelated dirty source files and the existing shared installed agent unchanged. Install the signed development variant in the global Applications directory with a separate app-agent namespace. Update the normal Codex OCU configuration and operation guidance to that installed path. Existing sessions can consume the same installed runtime through its supported CLI while their original MCP transport remains loaded.
- Keep the prior installation available; do not stop its in-flight clients or return their parked windows during migration.
- Installed acceptance found that WindowServer can change the global display origin while adding a virtual display; compare windows relative to their display, not by absolute coordinates. A virtual screen must not become the user's main screen when a physical screen is available. Preserve the prior physical main when still active, otherwise select an existing physical screen (largest usable area), applying a session-only uniform coordinate translation. Do not enable, disable or change modes of physical screens. Capture the original window's display identity/relative position before creation, and resolve restoration against current display coordinates; if that display is unavailable, restore to an active physical screen rather than the hidden virtual screen.
- Set the installed runtime's explicit config to `virtualDisplay.enabled=true` and `virtualDisplay.restoreOnSessionEnd=false`. Set its Codex MCP environment to the dedicated config path and namespace. Include any environment override key in `OCUConfiguration.environmentKeys`; verify the actual CLI and MCP consume the same configuration.

## Validation and delivery

1. Unit tests cover strict configuration, independent override precedence and defaults. Existing MCP lifecycle tests continue to cover turn-end and EOF cleanup dispatch without GUI tests.
2. From the real installed path, park task-owned overlapping windows, including a Chromium/web-content window, send the actual MCP turn-ended notification and the namespaced CLI Stop hook, close that client, then open a new MCP client. Assert the same windows/display remain hidden and the web content tree is still available; read and edit the native document with fresh Agent Desktop refs. Observe foreground/clipboard/system pointer and physical-screen geometry. Verify pre-existing old-instance parked windows retain their geometry across the namespaced hook.
3. Exercise explicit restoration and verify its result; park again and leave the test document hidden across another completed session. Do not equate a simulated notification with an unobserved future Codex turn; record the exact hook and connection boundaries tested.
4. Publish only this task's source/docs/tests, complete required checks, install the accepted candidate, and update guidance. Report owner-process exit/crash/reboot boundaries honestly; this change is not a separate login session or VM.

## Status

Completed in the signed installed macOS candidate. Ten targeted Swift tests and eleven configuration JavaScript tests pass; repository CI passes. Real installed-runtime acceptance passed twice with overlapping WebKit and native fixture windows: MCP turn-end, EOF, the namespaced CLI hook, six connections, fresh semantic editing, CLI snapshots, explicit restore, last-display removal and re-parking. The correlated second pass observed no fixture activation or clipboard change during its lifecycle interval. The user may still move the physical pointer independently.

Design/code reviews resolved adoption settings, occlusion retention, namespace isolation, identity validation, atomic cleanup and CLI override locking. A final concurrency review and display-geometry review found no blocking issues. Acceptance also exposed and resolved duplicate virtual-display serial numbers and virtual-screen primary selection.

The retention lifetime is the app-agent owner process. Explicit restoration and normal owner exit still recover windows; crashes, logout and reboot are outside the persistence guarantee. Existing installations and unrelated dirty input changes were preserved.
