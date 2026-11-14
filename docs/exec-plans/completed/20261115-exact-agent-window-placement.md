# Exact agent window placement

## Goal and constraints

Allow consumers of OCU's persistent display to delegate one confirmed window by
PID and WindowServer ID, without changing a human sibling or creating another
virtual display. Preserve legacy calls, session persistence, and existing input
behavior. This increment adds no resize/close-on-exit or global input fallback.

## Implementation

- Native exact `keep`, park, restore and record-only `release`, with strict ID and
  live process/window checks; no launch/current-window/parent fallback.
- Running numeric PID resolution preserves blocked-app policy.
- Pins retain process launch and AX identity; release is one-shot without delayed
  retries. Display idle checks include floating/unmanaged occupants.
- JavaScript option forwarding, capability contract, targeted unit tests and
  public usage documentation.

## Validation and rollout

Targeted native tests and JS contracts passed. Required repository CI passed on
the final documented tree, including the occupancy regression fix. Independent
code review found and closed the nonzero-layer occupancy bug.
A signed installed isolated app agent proved exact AX selection, wrong-PID/stale
ID rejection and unregistered release without frame/topology/focus changes.
That proof does not cover parking, registered recovery or owner exit.

The original GUI holder saved its buffers and handed over its authorized temporary
windows; those windows were closed and disappearance verified. Another authorized
GUI transaction is finishing, and an unattributed browser occupant remains on the
shared display. Its ownership must be resolved before an owner-process exit. Do not
replace its bundle or connect a new identity until its current atomic work and
restoration finish. Census actual windows first, account for any stale recovery
entry belonging to a human window, then perform the coordinated upgrade. Complete
same-process sibling, reconnect, registered release, restoration and normal owner
exit acceptance using only task-owned windows. Do not create a second virtual
display while another owner is holding the live screen. Keep this plan active
until that installed-runtime acceptance is complete.

## Observed idle lifecycle correction

During coordinated cleanup, the old shared owner stayed alive but its display
disappeared after the last registered temporary windows and stale human entry
were pruned. An unregistered shared browser was relocated by WindowServer. The
old implementation destroyed on an empty registry, ignoring real occupants. In
addition to the occupant check, retain the explicit persistent-workspace choice
until owner exit, including zero registered/occupied windows and later transient
clients. This avoids repeated display topology changes between business units.
The classification question became moot after the browser had already returned;
no browser window is moved by this task. All original GUI holders subsequently
reported a complete input/recording safety point for the formal switch.

## Ambiguous native move delivery

Real installed validation observed AXError -25204 after the window had actually
reached the hidden screen. Record original recovery ownership and the persistent
latch before sending the move. On error only read back the exact window's target
position; never resend automatically. An unresolved outcome retains recovery for
explicit restore/release. Preserve the earlier normal owner-exit proof and rerun
the installed final move/session/empty-display path after this correction.

WindowServer renormalized global display origins while creating/removing a
display, including initially offscreen fixture windows. Do not claim constant
global coordinates across topology changes: verify physical IDs/modes/main and
the human windows' placement relative to their physical screens. Inside an
existing persistent display, exact sibling frames and topology stayed identical.

## Completed validation

The final signed installed candidate passed exact same-process selection, wrong
PID/stale-ID rejection, parking the second window without changing its sibling,
native OCU set_value plus exact AX read-back, turn-end/disconnect/reconnect
retention, registered release without movement, explicit restore, and retention
after closing the last registered fixture window and a CLI Stop/new client.
All task fixture windows/processes were closed. Actual backend tools/list and
permissions were read back. The namespace display remains non-primary and
unmirrored; consumers received the current identity and rediscover its serial.

13 targeted native tests passed on the final source. JS33 and required repository
CI remain valid for their unchanged paths; final doc checks cover this closure.
Independent review closed the floating-occupant and failed-guard policy issues.
Normal owner-exit restoration was proven on the preceding signed candidate; the
restore/exit implementation is unchanged by the later ambiguous-move correction,
so that evidence is reused rather than cycling a shared browser again.

All original GUI owners handed over at business safety points; the installed
service and GUI lane were returned without waiting for source publication. No
public npm/tag/version bump is part of this local increment.
