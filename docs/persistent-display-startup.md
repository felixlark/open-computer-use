> Retired on 2026-11-15: virtual displays, persistent workspace and preview are no longer a supported runtime route. Use [physical right-screen placement](right-display.md). The content below is historical recovery evidence.

# Persistent display host bootstrap

`ensure_agent_display` is a macOS tool for login hosts. It creates or reuses the
same owner/namespace screen without opening, looking up, moving or pinning any
window. It is advertised only when `virtualDisplay.enabled` is enabled. Calls
require the configuration snapshot to also set `restoreOnSessionEnd=false`.
Disabled, missing, malformed or transient configuration fails before creation.
The caller should pass its normal configuration path and namespace, without
forcing enabled/retention environment overrides over that file.

The operation shares the normal background transaction and AgentDisplay lock.
It establishes the persistent-workspace retention and normal owner exit hook,
including an empty screen. Repeated calls reuse the same screen. Session EOF,
turn end and later transient clients do not remove the retained screen. The
normal owner exit, logout or OS restart ends that process-owned screen; a login
host requests bootstrap again when the user session starts.

The text result is JSON protocol 2 with `geometry:"fit_restore_v1"`, `display_id`,
`namespace`, `persistent` and `bounds` (`x`, `y`, `width`, `height`). This capability
means the same owner's exact placement chain stores the full original frame,
fits oversized windows and confirms full-frame restoration. Hosts relying on
that behavior must confirm both protocol and geometry marker from the actual
owner before starting window claims; a protocol 1 receipt proves only the older
position-restoration contract. Hosts must rediscover current physical
identity and geometry after creation, before capturing original window frames.
A display ID from a previous boot is never a stable identity. WindowServer can
translate global coordinates when creating a screen; this operation preserves
the user's main screen using the existing provider contract and does not move
human application windows itself.

Upgrade the provider at its actual shared-window safety point and keep a rollback
bundle. Only the provider owns creation/lifetime; consumers neither create a
second display nor use a temporary window to bootstrap it. Client request timeout
is not proof a display was not created: reconcile the namespace screen before
retrying this idempotent operation. Never terminate the shared owner merely to
recover a timed-out temporary proxy.

Validation includes the opt-in/schema/receipt unit tests and the installed login
host cold-start acceptance recorded by the consuming feature. Existing test
expectations now include the already-shipped exact-window `release` option.
The new geometry contract's non-GUI tests do not prove installed oversized-window
acceptance; that requires the provider and consuming host to be switched and
observed together. See [exact placement](exact-window-placement.md).
