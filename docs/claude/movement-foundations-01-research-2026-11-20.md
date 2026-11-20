# Movement foundations 01: research and architecture report

Method: read the code, trace a real Move through the game, and measure on the Tactical Test Range with `tools/quality/movement_audit.gd` (a diagnostic, not a test). Findings below are tagged **verified** (read in code or measured here) or **inference**. External material is cited as what it is; nothing is assumed about any commercial game's internals.

## 1. Current movement architecture (verified)

| Step | Owner | Where |
| --- | --- | --- |
| Destination selection, legality, AP | tactical | `BattleController._query_move_data`: `Pathfinder.get_reachable_cells(start, budget)`, occupancy (`can_unit_occupy_cell`), `calculate_3d_path`, `get_path_cost` against `stats.speed` |
| The route | tactical | an A* path of **cell-centre points** (one per cell); AP is the path cost in whole steps (1 per step, sqrt 2 diagonal; explicit links cost one step) |
| Move order | action layer | `TacticalActionService` stores `path`, `presentation_path`, `visual_segments`; replays record the request, not the trajectory |
| Presentation path | presentation | `BattleController._build_movement_path` adds `standing_height` (and low-cover height) to each point; `TacticalPoseContext.path_poses` labels each leg `move/climb/descend/vault` from cell data |
| Walking | presentation | `TacticalUnit.move_along_path` expands each leg through `SurfaceNavigation.traversal_route` and walks the waypoints with `move_toward` at one constant speed (`movement_speed`, 5 m/s; replay scales it); `UnitVisualAdapter` turns toward the heading and feeds speed to the gait |
| Committed position | tactical | `_snap_to_committed_destination`: the unit ends on the exact cell position whatever the walk did |

So tactical state is fully discrete and **decided before any pixel moves**; the walk is presentation. Timing is not part of the replay record.

**Does navigation assume passing through every tile centre? Yes** for the points of the path. **Is the segment between two centres checked for obstacles? Also yes, on surface-placement maps** (all current authored content): `SurfaceNavigation.edge_clear` sweeps the segment with the body (radius 0.28 + 0.04 clearance, height 1.8) against every physical part box (`_sweep_clear`, `segment_enters`), tries an "elbow" detour (`[from, elbow, to]`) when the straight line is blocked but an L-shaped path is clear, and routes low-cover obstacles as a raised vault. Unit-to-unit passing is a separate check (`units_clear`, gap = 2 radius + clearance). Legacy non-surface maps have no sweep. Consequence: **for legal surface-map edges the straight line between centres is already clear by construction**; the visible defects are elsewhere (below).

Local presentation offsets are already supported in several places (the rig node's step toward a passenger, cover yaw offset, ladder pelvis standoff), always as presentation-only values that never touch `global_position` of the tactical unit.

## 2. Geometric representations that exist (verified)

Grid cells with elevation and `walkable/can_stop` (`MapCellData`); surface placement (`SurfaceNavigation`, `MapData.movement_parts` = AABBs of physical parts, `columns` of floor cells per x/z); `ElevationPath` and `TraversalLinkData` for ramps, stairs and ladders; `CylinderPart` (pure exact vertical-cylinder geometry: ray entry, **`segment_clear` for a vertical body cylinder along a segment**, `resolve`, `contact`) and `MapData.presentation_cylinders` (compiler-recorded round parts). `CylinderPart`'s own header: *"Not integrated anywhere yet. Today a round asset is replaced by stepped whole-tile boxes."* No navmesh; no per-object tactical metadata beyond a few meta keys (`solid_size`, `movement_cost`, `round_volume`, ladder/deployment/objective keys).

## 3. Stairs as implemented, measured (verified)

The Tactical Test Range stairs (`TrainingGallery/Stairs`) are **six CSG treads, 0.5 m deep and 0.5 m high each**, plus an `ElevationPath`. The tactical representation is **three links of one cell (1 m) in run and 1 m in rise**: `(6,0,15)->(6,1,14)->(6,2,13)->(6,3,12)`, and `traversal_route` gives each link the shape *vertical 1 m at the lower cell centre, then 1 m horizontal at the upper height*. The movement parts for the stair cells are whole-cell blocks (1 m tops), not the physical treads, so **the treads are not in the map data** (only their cell-sized stand-ins).

Measured with a real Move from (6,0,15) to (6,3,12): 175 frames; **the unit's floor height is up to 1.50 m above the physical tread beneath it** (worst float) and never below one (worst sink 0.00 m): it rises 1 m straight up in the air 0.5 m before the first tread, glides across the treads, rises 1 m again, and so on, with the placeholder `climb` clip. This is the concrete evidence for the stair work: not a navigation fault, a **presentation path that ignores the physical stair**.

## 4. Obstacles and clearance, measured (verified)

* **Partially obstructed tiles.** On the range, 31 level-0 cells are blocked by an obstacle overlapping them; 7 of those are under 40% covered (e.g. cells `(4,0,5)`, `(4,0,8)`: 23% covered by a 0.48 m x 2.78 m support column). That is a *legitimate* limitation of the tile-centre model: the body (0.64 m diameter with clearance) cannot stand at a cell centre occupied by a 0.48 m column, even though 77% of the cell is free. 27 more overlapped cells stay walkable. A column touches 5 cells within body reach.
* **Corners and round objects.** All nine thin parts here are square columns. Round assets (tanks, silos) become stepped whole-tile boxes (documented in `CylinderPart`); for a round part of radius `r` the box stand-in is 4/pi = 1.27x its area, and a path that grazes its corner at 45 degrees is pushed out by about (sqrt 2 - 1)(r + body reach), e.g. 0.34 m for a 1 m barrel. `CylinderPart.segment_clear` already computes the exact answer, unused.
* **A tile that looks legal but collides.** None found on surface maps (the sweep is conservative by design). On non-surface maps the direct segment is unchecked (inference: the fixture-style maps), which is where collisions could occur; they are not the current content.
* The tactical edge test is axis-aligned and per segment, so a *smooth curve* between three consecutive centres can cut a corner that the two straight legs do not: any refinement must be checked against the same parts and radius, not assumed safe.

## 5. Visual refinement vs real sub-tile navigation

**Visual path refinement (feasible without new rules):** the presentation walks a different polyline between the *same* authorized cell positions, kept inside the clearance the tactical sweep already established, with the same start and end. It cannot make a blocked tile usable, change AP, occupancy, LOS or cover, and does not enter the replay record. **Sub-tile navigation (needs approval):** recognising more traversable space or positions; affects occupancy, pathfinding, LOS, cover and cost. Out of scope. A failed local-clearance calculation must report a mismatch and fall back to the tactical polyline, never authorize anything.

For different-sized humanoids the same representation works with a per-unit `body_radius` in the sweep (the map already stores one global radius; per-unit radius is a data extension).

## 6. Stair-aware locomotion: techniques and sources

* Foot placement IK is standard practice: Epic documents terrain/stair foot adjustment through the Animation Blueprint IK setups and IK Rig (feet and hips), and the Foot Placement node is marked experimental in Lyra's full-body setup per forum reports ([Epic IK setups](https://docs.unrealengine.com/4.26/AnimatingObjects/SkeletalMeshAnimation/IKSetups), [IK Rig](https://dev.epicgames.com/documentation/unreal-engine/ik-rig-in-unreal-engine), [Lyra foot placement thread](https://forums.unrealengine.com/t/skeletal-controls-foot-placement-node/881057)). Godot 4.6 re-added IK: `TwoBoneIK3D` and siblings are `SkeletonModifier3D`s ([Godot announcement](https://godotengine.org/article/inverse-kinematics-returns-to-godot-4-6/), [class reference](https://docs.godotengine.org/en/latest/classes/class_twoboneik3d.html)); this project already uses it for arms and now for legs.
* Semi-procedural walking with terrain-adapted feet: Rune Skovbo Johansen's GDC 2009 talk and thesis; footstep planning as search: Kapadia et al. dynamic footstep planning (Rutgers); Guerrilla's Horizon Zero Dawn traversal slides split "animation decides when a foot plants, code decides where" ([thesis](https://runevision.com/thesis/rune_skovbo_johansen_thesis.pdf), [Rutgers](https://people.cs.rutgers.edu/~mk1353/pdfs/2013-ceig-dynamic-footstep-planning.pdf), [HZD traversal](https://www2.slideshare.net/guerrillagames/player-traversal-mechanics-in-the-vast-world-of-horizon-zero-dawn)). A practitioner note says reacting to height before planting suits slopes but stairs benefit from authored content.
* **Genshin Impact:** no technical documentation was found; nothing about its stair handling is asserted here.

**Foot on every tread?** A configurable contact policy, as it differs by case:

| Case | Policy | Reason |
| --- | --- | --- |
| Slow / tactical walk, ascending | every tread | the stride is shorter than a tread pair; skipping looks like a stumble |
| Tactical walk, descending | every tread, shortened stride, forward lean slightly back | balance, readable weight |
| Jog | every tread or alternate (skip one) by tread depth vs jog stride | cadence is ~2 steps/s |
| Run | alternate (every second tread) when stride > 2 treads | skipping is natural at speed |
| Carrying a passenger | every tread, slower, no skipping | load and balance; may stay on current behaviour |

Recommend `StairContactPolicy` with `EVERY_TREAD / ALTERNATE / AUTO` (AUTO picks by speed-derived stride vs tread depth) plus per-gait overrides.

## 7. Recommended stair algorithm

1. **Stair model** (pure): `StairModel` = origin, direction, tread rise, tread depth, tread count and width; from authored metadata when present, else the documented default subdivision (two treads per tactical step) as an explicit assumption.
2. **Root path**: replace the rectilinear vertical-then-level route, for *stair links only* (rise per link <= `StairModel` limits), with a polyline that rides the tread profile (lerp up each riser over a short distance, level on each tread): same endpoints, shorter total length than the old route.
3. **Foothold plan**: ordered footholds on tread centres by policy; the swing foot lifts to `riser + clearance`, passes the nosing, lands on the next foothold; stance feet are locked (target fixed in world) until the next swing; bounded lookahead (two treads).
4. **Body**: pelvis height from the two stance footholds (smoothed); stride/cadence from the existing gait at the unit's speed.
5. **Application**: foot targets drive the leg two-bone IK that already exists (`TraversalLegIK`), blended in and out by weight; ankle orientation matches the tread slope; weapon and arm layers are untouched.

## 8. Recommended local-path refinement

Input: the tactical polyline (cell-centre points), the same `movement_parts` and body radius as `SurfaceNavigation`. Output: a smoothed polyline with identical endpoints and the same cells visited. Algorithm: corner rounding (circular arc or Chaikin-style cut limited by the turn angle), each candidate sub-segment tested with the existing sweep (`_sweep_clear`, or `CylinderPart.segment_clear` for rounds); if any rounded corner fails the test the corner is left sharp; if the original polyline itself fails the test, a mismatch is reported. Pure, bounded (O(points x local parts)), deterministic.

## 9. Skeleton and animation compatibility (verified in code)

Legs are driven by clip data (`LocomotionGait` phases) plus the modifiers; `TraversalLegIK` (two-bone IK with knee poles, influence-weighted) and a pelvis override exist from the ladder work and are the right integration point; no second leg system is needed. Missing: ankle orientation to a surface, per-step knee flexion limits in the IK path (limits are measured, not enforced), stance-foot locking. Bone ownership while stairs are active: Locomotion keeps turn/bank, the traversal layer owns pelvis and legs, WeaponPose/ArmIK/HandGrip keep arms and rifle (same split as the ladder).

## 10. Replay and determinism

Everything proposed is a function of the unit's tactical position along the (presentation) route, evaluated per frame: no accumulated state that depends on frame rate, so pause/seek/speed changes give the same feet for the same position. The refined path changes only the visual walk; combat during movement (reaction shots) already presents against `global_position`, which stays on the same endpoints. Timing: a refined path has a different length; movement duration is presentation-only. Carrier loss and interruption clear presentation state (as the ladder does).

## 11. Environment metadata required

Per stair: tread count, rise and depth (or a `StairModel` meta on the `ElevationPath`); per ladder: rung layout and plane (see the traversal report); per round obstacle: radius and axis (already in `presentation_cylinders`); per obstacle: whether it is a vault/step candidate. Authored scenes should declare these once on the component (like `ladder_local_bottom`), not per-prop scripts; assets built from modules can carry them as part of the module's meta.

## 12. Performance and risk

Corner rounding and per-frame foothold evaluation are O(1) per frame for a bounded window; the sweep reuses existing indexed local-part queries. Risks: a mismatch between the assumed tread layout and the real mesh (the main one: treads are not in the map data), IK popping when a foothold is dropped (mitigate with weight ramps and a bounded lookahead), changed movement duration being mistaken for a gameplay change, skeleton foot-roll not modelled.

## 13. Roadmap and acceptance tests

1. **Path refinement prototype (pure + opt-in hook):** tests: endpoints and cell sequence unchanged; min clearance to parts >= body radius; mismatch reported when the tactical polyline fails the sweep; deterministic; no AP/occupancy change.
2. **Stair model + root path:** tests: the root never floats above or sinks below the tread profile by more than a tolerance; ends exactly on the committed cell; descending symmetric.
3. **Foothold planner + policy:** tests: each foot target lies inside a tread and clears its riser; stance feet do not slide; knee bend inside limits; policy switches (walk every tread, run alternate); bounded lookahead.
4. **Rig integration:** tests: modifier order, interruption cleanup, flat-ground gait afterwards; loaded carry keeps current behaviour.
5. **Metadata and authored content:** declare stairs on authored components; map-data exposure; regression across maps.

## 14. Decisions for the project owner

* Presenting stair/vault routes along the physical geometry changes how long a move takes to show (presentation only): accept?
* Authoring: declare stairs (and rungs) in scenes, or keep inference defaults?
* Per-unit body radius in the sweep (affects nothing tactical until clearance becomes a rule).
* Whether the legacy non-surface maps should get the same sweep.
* Any sub-tile navigation (explicitly not started).
