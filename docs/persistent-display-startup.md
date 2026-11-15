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

The text result is JSON protocol 1 with `display_id`, `namespace`, `persistent`
and `bounds` (`x`, `y`, `width`, `height`). Hosts must rediscover current physical
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
