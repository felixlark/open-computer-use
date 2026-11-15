## 2026-11-15 | Add read-only live virtual display preview

The requested preview is delivered as a standalone signed macOS companion,
Open Computer Use Preview, so opening, closing or updating it does not retire
the automation provider or restore its hidden windows.

It displays a complete OCU virtual display with aspect-fit scaling, a selector
for multiple owners and a persistent OCU menu-bar entry. ScreenCaptureKit streams
video only; the observer has no input forwarding, placement or display lifecycle
capability. Frames remain in a single memory slot. Closing, connection loss or
capture failure clears the image; superseded async starts stop their own streams.
The companion has its own Screen Recording permission UI and no Accessibility
permission requirement.

Independent implementation-readiness review identified gaps in owner isolation,
permission onboarding and capture lifecycle. The revised plan and implementation
closed all three in a focused recheck. The build script uses the system bash to
avoid a locally observed Homebrew bash heredoc write stall.

Validation: three non-GUI unit tests; repository CI; Developer ID signature and
installed launch; actual hidden-screen marker A to B updates; a click on the
previewed fixture button left the original button count unchanged; zoom and
960×650 resizing retained the entire display; close/reopen displayed the changed
marker; menu Close/Show was operated and observed using headless native AX.
OCU performed normal window observation/interaction; Agent Desktop covered only
the menu-bar surface and precise resizing capabilities absent from OCU.
The disposable fixture was closed and the existing automation owner retained its
PID throughout. First-run system authentication was completed by the user.

See [usage and build instructions](../../agent-display-preview.md) and the
[completed plan](../../exec-plans/completed/20261115-agent-display-preview.md).
No unrelated checkout deltas are part of this change.
