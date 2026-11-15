> Retired on 2026-11-15: virtual displays, persistent workspace and preview are no longer a supported runtime route. Use [physical right-screen placement](right-display.md). The content below is historical recovery evidence.

# Exact window placement (macOS)

Use `get_app_state` with `window_id` to observe or manage one current window of a
running app. This is suitable for applications containing both human and agent
windows. The ID is a positive UInt32 WindowServer ID, not a title or AX index.
Use the current PID as the `app` string when selecting a particular process.

## Capability and identity

Before using this increment, inspect `tools/list` from the actual native app
agent: `get_app_state` must advertise `window_id` and the `release` placement.
An old runtime may ignore unknown arguments; a client-side schema or the version
string alone does not prove support. A replacement CLI can restart an old app
agent when their build identities differ. Coordinate an actual safe handover
before changing the shared bundle, connecting a replacement, or exiting its
owner; do not treat a preflight connection as harmless.

An explicit ID never launches an app, selects a current/title-matched fallback,
activates it, raises it or silently switches to a parent. Its AX window must
belong to the running process. An explicit sheet cannot be parked: obtain and
confirm its parent ID instead. A PID or window mismatch fails before movement.
The normal blocked-app policy still applies to numeric PIDs. Recovery ownership
and the full original frame are recorded before display creation or AX writes:
an AX error can arrive after delivery. OCU reads back the requested attribute
without repeating an unconfirmed write. An unresolved error retains
the recovery record; inspect that exact window before restoring or releasing it.

## Native calls

The following is the JSON body of a native `tools/call` request. Replace the PID
and ID with freshly observed values for an owned window:

```json
{"name":"get_app_state","arguments":{"app":"12345","window_id":67890,"window_placement":"agent_display","include_screenshot":false}}
```

| Placement | Effect with an explicit ID |
| --- | --- |
| `keep` | Observe that exact window, without moving it. |
| `agent_display` | Record its actual original frame and identity, fit oversized dimensions, then park only it fully inside OCU's owned invisible display. |
| `restore` | Restore only its registered full frame, then observe the same window. |
| `release` | Drop only its recovery record and visibility pin; do not move or snapshot it. |

`release` requires `window_id` and returns a text JSON receipt:

```json
{"window_id":67890,"released":true,"was_registered":true,"occlusion_restored":true}
```

`was_registered=false` is a successful no-op for an unregistered live window.
`occlusion_restored=false` means the one-shot visibility reset could not be
confirmed. The pin and recovery entry have still been discarded; no late retry
will replay the old state after user takeover. Closed windows are pruned by
identity during session/owner cleanup. Do not retry their ID after it is reused.

Without `window_id`, the legacy app-scoped selection and restore remain. Do not
use app-scoped restore to release one window in a mixed-ownership app.

## JavaScript adapter

Bind without a default snapshot, then select explicitly:

```js
var app = await cua.getApp("12345", { initialState: false });
await app.getAXState({ windowId: 67890, windowPlacement: "agent_display", includeScreenshot: false });
await app.getAXState({ windowId: 67890, windowPlacement: "keep", includeScreenshot: false });
await app.getAXState({ windowId: 67890, windowPlacement: "release" });
```

Element/query indexes are native-session scoped. Observe and act in the same MCP
connection or CLI batch, and query again after reconnecting. `release` does not
provide a fresh AX tree. Disable automatic action read-back and the animated
cursor where the host requires background interaction, then explicitly inspect
that exact window after semantic actions:

```sh
export OPEN_COMPUTER_USE_ACTION_READ_BACK=0
export OPEN_COMPUTER_USE_VISUAL_CURSOR=0
```

These options and the hidden display do not independently guarantee that every
input method preserves focus. Choose a verified method for the target control;
do not silently fall back to global keyboard/mouse or activation.

## Persistence and recovery

Virtual display creation remains opt-in. With
`virtualDisplay.restoreOnSessionEnd=false`, registered windows and their pins
survive turn boundaries and client disconnects on the same app-agent namespace.
Once requested, that persistent display also survives an empty window registry
until its owner exits; a later transient client cannot silently dismantle it.
Pins bind the PID, launch date and original AX window; replacement/gone/unknown
identities are never written during cleanup.

Releasing the last registered window does not destroy a display that still
contains another live window, including floating/nonzero-layer windows. Unknown
WindowServer metadata conservatively keeps it alive. OCU remains the single
owner of that display; consumers must not create another display for parking.

Full-frame placement requires the actual namespace owner's
`ensure_agent_display` receipt with `protocol:2` and
`geometry:"fit_restore_v1"`; protocol 1 only promises the legacy position
contract. The tool's exact-ID schema alone cannot distinguish these contracts.
Consumers must not pre-resize a delegated window: OCU captures its original
frame before any placement effect. Dimensions exceeding the virtual screen's
existing inset area are reduced; dimensions fitting that area are unchanged.
Unsupported size writes, OS minimum dimensions or incomplete placement return
an error while preserving recovery ownership, rather than accepting an
off-screen window. Full frame and Space membership are confirmed before success.

Restore moves onto the original physical display, restores original dimensions,
then corrects any observed position change. An unchanged original display
restores the exact original frame, including previously partly off-screen
geometry. A changed/missing original display uses the existing relative-position
fallback with the original size; this is not proof of an unchanged-layout
restore. If the OS cannot restore those dimensions, or identity/geometry becomes
unknown, the operation fails and retains its recovery record and visibility
pin. Only verified full-frame restoration releases them. Reconcile the exact
window before deciding on a later explicit restore or release; do not blindly
replay an uncertain operation.

A window
born on the hidden display has no earlier physical position. Close that owned
window before normal owner exit, or accept the existing physical-display fallback
when explicitly restoring it. True owner exit attempts restoration and the display
cannot survive its process. Crash/logout/reboot persistence is not provided.

### 实体屏 fallback 的完整尺寸

原屏及bounds未变时恢复真实原frame（允许原本部分出屏）。原屏消失或变化后已不能容纳原尺寸时，fallback优先能容原尺寸加既有40pt余量的实体屏：main可容则main，否则面积最大的可容屏。无可容屏则尽力选最大实体屏，并仍以完整frame读回为成功条件；不缩小原尺寸冒称恢复。fallback位置夹至40pt可用区以避开菜单栏/边缘约束。没有实体屏或写入/读回未确认时保留恢复记录和pin。
