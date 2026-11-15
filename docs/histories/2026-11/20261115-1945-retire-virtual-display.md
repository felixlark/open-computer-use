# Retire the macOS virtual-display route

User requested retiring OCU virtual displays and routing all Agent-derived windows to the rightmost physical screen. Ordinary computer-use tools remain.

Removed producer advertisement and made creation reject stale enable overrides. Added exact, nonactivating right_display placement and legacy recovery-record release. Updated affected schema tests and added physical geometry tests. Kept historical implementation solely for recovery/archive; preview/runtime consumers and host configuration are retired by their owners. See right-display.md for the current contract.

The ordinary product builds. The exact staged tree passes 18 targeted Swift tests and 34 JavaScript tests. Live checks reject both old producer calls with enabled=true and move exact native, browser and auxiliary windows to the physical right screen. Oversized frames resize before position so WindowServer clamping cannot prevent the fit operation; unknown effects stop for read-only reconciliation. The installed application preserves the checkout’s existing unrelated deltas; only retirement changes are committed.
