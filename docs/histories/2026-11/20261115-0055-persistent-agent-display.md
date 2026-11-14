# Persistent agent display between sessions

Added opt-in `virtualDisplay.restoreOnSessionEnd=false` so the long-lived macOS app agent keeps parked windows and their occlusion pins across turn-end notifications and client disconnects. The default remains transient for compatibility. Explicit restoration and normal process exit retain recovery.

Window identity now includes process launch identity, stale pin records are discarded safely, and background state mutations are serialized across tool calls and cleanup. Distributed turn-end names and virtual-display serials follow the app-agent socket namespace. Display creation preserves a physical main display when available; restoration resolves original positions relative to the current physical layout.

Validation: ten focused Swift tests, eleven JavaScript configuration tests, repository CI, signed installed-runtime permission checks, and two real GUI acceptance passes using native/WebKit fixtures. Acceptance covers turn-end, disconnect/reconnect, semantic editing without activation, overlapping web-content retention, explicit restore, removal of the last virtual display, and re-parking. Persistence does not extend across an owner crash, logout or reboot.

See [completed plan](../../exec-plans/completed/20261114-persistent-agent-display.md) and the opt-in [installed smoke test](../../../scripts/tests/macos-persistent-display-smoke.mjs). The GUI smoke test requires installed fixture apps and is deliberately separate from XCTest and normal CI.
