# Phone host display

The sole virtual display exception serves SmartShadow phone hosting. `phone_host_display` accepts ensure/status/park/release and an exact admission tuple: instance UUID, vendor PID, process launch timestamp and WindowServer ID. The helper verifies the creation nonce and owns runtime admission updates. The provider requires the dedicated smart-shadow-phone-host namespace and the SmartShadow phone-host-ocu configuration; ordinary virtualDisplay flags still cannot enable the retired generic route.

Status reports real bounds, display serial, claim_present and released. Unknown moves are reconciled by status, never repeated blindly. Release requires the old exact window to be absent and remains readable after its host exits. Client disconnect retains the screen. Normal AppKit, RPC and signal termination enters an atomic terminating state only after the claimed window is gone. Planned recovery closes the phone bridge/window first, then releases, replaces the provider if needed and creates a new admission.

An unexpected provider crash may let macOS reposition the window before the consumer detects failure; this is not a promise of zero transient visibility. The helper must revoke the bridge and reconcile; corrupted journals require explicit offline reconciliation.

Validation: production build and six isolated same-source policy tests passed; focused independent review completed. Existing full tests currently fail compilation in the unrelated LockedUseIncidentReplayTests delta. Deployment and phone receive/send/stream/reconnect acceptance are tracked in SmartShadow #578/#613 and remain pending.
