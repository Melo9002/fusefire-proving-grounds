# Authored plots — T09

Implemented 2026-10-28. This is source authoring and individual slot feasibility, **not** the T10 composition solver or a playable-map certificate.

## Try it

Open the existing Map Editor and choose **Author — Plot Authoring**. Select **Through Street Industrial** or **Yard Service Access** in the saved-plot list, then **Open selected plot**. The mission selector switches between Eliminate and Terminal.

- Cyan rectangles are slots, green cells are protected access, magenta cells are active mission capacity. Streets include their owned sidewalks. Buildings are deliberately not instantiated into slots yet.
- Set the plot ID and map dimensions with **Apply plot ID / boundary**.
- Select a record in the list or viewport. Edit its fields and press **Apply selected fields**, or use **Move on grid** and click its new origin. Escape cancels movement.
- Add streets, slots, access reservations and mission requirements with the four add buttons. Slot controls expose candidate IDs, allowed quarter turns, and obligations built from the candidates' actual port records.
- Use Undo/Redo, named draft Save/Open and the unsaved-change confirmation. Incomplete or infeasible drafts remain saveable; malformed sources do not replace the current session.
- The right panel scrolls. Reservation moves preserve authored cell shapes; changing width/depth deliberately replaces the shape with a rectangle.
- **Refresh library** rechecks current chunk sources and publication eligibility. **Pin registered revision** only pins an actually eligible street revision; it cannot grant approval.

## Ownership and persistence

`EnvironmentPlotSource` is versioned JSON (`fusefire_plot_source`, schema 1) with `plot_id`, `map_size`, `active_mission`, and four record collections. It shares `GenerationJsonStore` atomic persistence, filename rules and structural checks with the existing authoring infrastructure.

| Record | Owns |
| --- | --- |
| Fixed street | Stable local ID, chunk ID, exact registered revision pin when available, world origin, quarter turn, explicit boundary exit port IDs. The chunk owns its full rectangular footprint including bundled sidewalk. |
| Slot | Stable ID, world rectangle, candidate chunk IDs, supported rotations, required/optional state and explicit port/profile → frontage/access obligations. |
| Reservation | Stable ID, semantic role, cells, floor/whole-column scope and height. The pilot authors ground-level reservations. |
| Mission requirement | Stable ID, applicable mission, deployment/objective kind, faction, distinct-cell capacity, cells and required access reservation. Only `all` plus the active mission participate. |

Chunk instances, geometry, tactics, calibration and local ports stay in chunk sources. Slots anchor content at their origin. A smaller rotated rectangle leaves slack; no scaling, mirroring, implicit repositioning or polygon packing occurs. Source IDs and relationship targets survive edits/history. Deleting a referenced reservation leaves an explicit missing-access/obligation diagnostic; new records do not reuse IDs still referenced or present in session history.

The existing `EnvironmentLayoutPlan` remains the derived planning view: authored slots project into parcels, reservations into its reservation list, and fixed street footprints into owned road cells. The latter includes sidewalk ownership, not a claim that every such cell is carriageway. There is no second road/parcel planner. Mission intent remains in the plot source until runtime binding; the derived plan is not a second persisted authority.

## Feasibility and approval boundaries

`PlotFeasibility` uses the existing publication compiler and one dependency-resolution context per library refresh. It admits technically valid drafts for authoring analysis but independently marks exact revision eligibility through the existing publication index. Matching an ID alone cannot confer eligibility. Duplicate source IDs are ambiguous and cannot satisfy a slot.

Checks include map bounds; street/sidewalk ownership; street-port geometry and boundary exits; slot overlap; actual rotated dimensions; required ports, profiles and frontage/access geometry; connected access reservations reaching a street; distinct active-mission capacity; and blocking/clearance conflicts against fixed and candidate content. Shared canonical rotation and T03 spatial predicates handle floor versus whole-column clearance, including overhead decoration.

`ok` means individually feasible authoring constraints. `generation_ready` additionally requires eligible candidates and pinned fixed revisions. Neither means that a complete combination has been solved, mission connectivity is proven across the whole battlefield, or the result is playable. T10 must bind exact revisions, provide surfaces for open plot space/slack, enforce all chosen-content relationships and reservations, and compile/validate the accepted battlefield. Population regions and integration with T08 belong at that composition boundary; schema changes must be explicit.

Both shipped plots use the existing small industrial library:

- **Through-street industrial:** six supported straight street pieces, two warehouse-frontage slots, a service yard and a loading yard. Larger yard slots demonstrate slack without stretching.
- **Yard/service access:** five rotated street pieces, warehouse, loading and service yards, plus the alley/courtyard. Different orientations and access reservations exercise the same local ports in world space.

Both represent Eliminate deployments and a separate Terminal objective/access requirement. Other mission types reject rather than silently substitute. No content review or registration was created by this task. Current draft-library geometry passes; publication gates remain pending.

## Verification and handoff

- `tests/plot_source_test.gd` — **33 checks passed**: both plots × both missions, derived-plan ownership, no stretching, overlap/undersized/mismatched-port failures, active mission filtering, capacity/access failures, incomplete round-trip, malformed/version rejection, unapproved exclusion, floor/whole-column and rotated-volume checks.
- `tests/plot_editor_workflow_test.gd` — **20 checks passed**: actual editor controls, saved plot browsing, mission switching, invalid-but-editable source, undo/redo, transactional failed load, reservation/mission/slot/obligation authoring and discard confirmation. Reference-loss diagnostics remain visible even when an unrelated slot-fit check also fails. Ordinary graphics execution captures `artifacts/t09-through-street.png` and `artifacts/t09-service-access.png`.
- Existing chunk-editor workflow regression passes. Ironclad smoke: **10 passed, 0 failed, 0 skipped**; logs `artifacts/test-results/20261028-090805-smoke/`. Environment certificate-store warnings persist independently of these checks.
- Rendered evidence was inspected: fixed streets/sidewalks, all slot rectangles, access and mission overlays are visible. This proves the planning workspace rendering, not future battlefield visual quality or gameplay.

For T10, consume these sources rather than introducing plot-specific code recipes. Keep legacy generator/editor paths while their supported runtime consumers still depend on them; retire migrated dispatch only after composition/play/replay parity. No procedural road graph was added. Approval of the local chunk revisions remains an owner action.


T10 follow-up: plot schema 2 adds declared population rules; schema 1 remains readable without rewrite. Registered composition controls and resolution contract 2 are documented in [plot-composition.md](plot-composition.md).
