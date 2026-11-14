## 2026-11-15 | Task: Manage one persistent agent window precisely

### Execution context

- Agent: Codex Desktop, original result owner.
- Runtime: macOS, signed local development bundle; host model not independently queried.

### Request

Let OCU operate its own hidden workspace without selecting a human sibling,
returning ongoing windows at turn end or requiring another tool for every step.

### Changes

- Exact live PID/WindowServer ID selection and scoped keep/park/restore/release.
- Process-launch/AX identity-bound occlusion pins; release has no deferred writes.
- Keep displays for unregistered/floating occupants and latch explicitly persistent
  workspaces until owner exit, including an empty registry.
- Record recovery before an ambiguous AX move; read back rather than resend.
  Failed re-park validation preserves the prior recovery policy.
- Update JS forwarding, public contract and lifecycle documentation.

### Verification

13 targeted native tests, 33 JS adapter tests and required repository CI passed;
independent review findings were resolved. A real signed installed two-window
receiver passed semantic edit/read-back, exact selection, identity rejection,
sibling preservation within the existing display, reconnect retention, scoped
release/restore and final-record closure retention. Normal owner-exit recovery
was proven before the last move-only correction; the unchanged restore path's
evidence is reused. No GUI XCTest, public package or release tag was added.

WindowServer can renormalize global origins during real display creation/removal;
this change does not promise fixed global coordinates or crash/logout persistence.
The shared service was switched at business safety points and left running.

### Main paths

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AgentDisplay.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/WindowOcclusionIdentity.swift`
- `docs/exact-window-placement.md`
