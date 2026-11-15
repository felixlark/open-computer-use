# Physical right-screen placement

The local macOS OCU virtual-display route is retired. `ensure_agent_display` is no longer advertised; both it and old `agent_display` calls reject creation even with a stale enable environment override. Historical display/preview documents are retained only as retired evidence.

For a caller-confirmed Agent window, call `get_app_state` with its exact running PID, `window_id`, and `window_placement: right_display`. The ID is required. OCU enumerates current physical displays, excludes OCU virtual screens and mirrors, and places the complete window on the rightmost screen without activation. An app may constrain its own outer frame; success requires exact live identity and full containment. An already contained window is unchanged. The response is a read-only observation of the same window.

Ordinary keep/observation/input remains available. restore/release are retained only to drain pre-retirement ownership. Successful right placement clears this owner's old parked record so exit cannot undo it. A different old owner must first drain its own records. Inspect unknown side effects before retrying; no blanket process/window claims or human-window migration.

Before stopping an old virtual-display owner, inventory all its real content windows, including unregistered and floating windows. Move confirmed Agent windows right, restore human windows using verified original-screen evidence, then stop the exact owner. Display backgrounds, menu chrome and invisible input overlays are not user documents. Check the actual physical topology and known human windows after display removal. Preview is no longer an installed working entry point.

Validation: targeted physical-selection/schema unit coverage and installed live checks for producer rejection, right-screen placement, ordinary exact observation and display removal. Full suite failures outside this change must be reported separately.
