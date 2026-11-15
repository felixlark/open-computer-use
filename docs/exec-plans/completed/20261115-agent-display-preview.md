# Read-only live agent display preview

## Goal and current facts

Let a human open a resizable, read-only window showing an entire existing OCU
virtual display in real time, without moving its windows or sending input.
The macOS app agent already owns persistent virtual displays; their shim uses
vendor/product 0x0CAC and a namespace-derived serial. It has no preview UI.
Existing unrelated local deltas and the running owner must be preserved.

## Implementation

- Add a self-contained OCUPreview executable target with AppKit and a menu-bar
  `OCU` item, packaged as Open Computer Use Preview.app. Launching this companion
  shows preview; closing keeps its menu available. Existing CLI/runtime unchanged.
- Discover only active, non-main, non-mirrored OCU vendor/product displays.
  Present a display selector for multiple namespace owners. Never create or
  destroy a display. Rediscover after topology changes; an absent selected
  display clears the image and shows waiting, rather than capturing a physical
  display. Selection remains bound to serial identity across ID reuse.
- ScreenCaptureKit SCStream captures the whole selected display, excluding
  the preview window itself. Render with aspect fit. No keyboard, mouse or AX
  forwarding exists. Capture audio is disabled. Frames stay in memory only.
- Closing the window cancels capture; reopening starts a fresh generation.
  Async start/stop and late frames check generation and selected identity.
  The controller retains active stream and sink; each pending start task also
  retains its own stream and stops it after start completes if superseded.
  SCStream callbacks discard incomplete frames and replace a single latest-frame
  slot. A main-actor timer drains that slot; close/failure clears both slot and
  displayed image. There is no unbounded per-frame UI task queue.
  Failure clears stale imagery and offers Retry. No automatic app activation
  or window relocation is used for capture. A human may move/resize preview.
- Build only the new product, using explicit Library cache/scratch paths and
  Developer ID signing. Install the companion without replacing automation
  bundle or owner. Its own stable bundle identity requires Screen Recording
  only: CGPreflightScreenCaptureAccess checks access, explicit Allow button
  calls CGRequestScreenCaptureAccess, and an Open Settings button opens the
  native privacy pane if needed. Retry updates access without touching OCU.
  No Accessibility permission is requested.

## Verification and recovery

Unit checks cover selection identity, no physical-screen fallback and stale
generation rejection; build the actual app. Installed GUI acceptance opens,
resizes, closes and reopens preview; a disposable fixture changes on the hidden
screen and the preview must update. Check input remains local to preview,
capture stops on close, and existing hidden windows remain parked. Companion
permission failures show its dedicated screen-recording-only UI; no credential handling,
recording, network listener or new input capability is added.

Rollback closes/removes only the new companion, leaving automation untouched. Existing
unrelated changes and windows remain owned by their original tasks.

## Status

Implementation complete. Independent readiness review found three implementation
gaps (companion isolation, dedicated permission UI, async capture ownership); all
were corrected and the focused independent recheck closed them.

The installed signed companion passed real display streaming, marker A→B update,
local-only preview click (fixture count stayed zero), zoom/960×650 aspect-fit,
close/reopen with a fresh marker, and menu close/show. The disposable fixture was
closed; existing automation owner remained running with the same PID. Three
non-GUI unit tests and repository CI passed. Final source publication is handled
by the original task without including unrelated checkout deltas.

## Write scope

Only Package.swift, apps/OCUPreview/, scripts/build-ocu-preview-app.sh,
README.md, README.zh-CN.md, docs/agent-display-preview.md and this task's plan/history. No existing automation
runtime, input, placement or unrelated dirty path is staged or installed.
