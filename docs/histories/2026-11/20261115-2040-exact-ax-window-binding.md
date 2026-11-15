# Preserve exact-window AX diagnostics and tolerate transient reads

An existing CG-owned window could be reported as 'not a current window' when a 0.1-second AX enumeration or private AX-to-CG ID read failed. Unscoped snapshots use a different selection path and did not establish exact identity.

Exact binding now uses per-object messaging limits, a two-second binding-read budget and at most two read-only samples. It preserves raw AX statuses, distinguishes CG absence/owner changes from AX unavailability/non-enumeration, and checks process launch identity and CG owner before accepting the requested AX ID. Focused sheets are candidates only when their exact ID matches; no title selection, activation or write retry is added. The already verified ID is reused instead of being re-read under the short tree-traversal timeout. The binding budget does not cover the full snapshot's setup, tree traversal or capture.

The ordinary product builds and the exact staged source passes 18 targeted tests (nine pure injected binding cases plus placement regressions). Independent review has no outstanding findings. Installed GUI acceptance is coordinated with the existing consumer owner; no active business windows are closed for the switch.
