# Persistent display host bootstrap

User request: restore the OCU virtual screen after login and let Chrome use it automatically, without a manually parked fixture window.

Added the opt-in `ensure_agent_display` tool, sharing the existing namespace owner, lifecycle lock, persistent retention and exit cleanup. A configuration snapshot gates creation; the result reports current identity and geometry. Existing window/input tools remain unchanged. Targeted tests cover tool advertisement, persistent configuration, argument rejection and receipt schema. Two stale baseline assertions were aligned with the already-released `release` window operation. See `docs/persistent-display-startup.md`.

Installed provider and consuming-host acceptance is recorded in the delivery evidence after the coordinated switch. No public version/tag/npm release is requested.
