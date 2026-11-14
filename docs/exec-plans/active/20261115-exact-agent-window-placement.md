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
