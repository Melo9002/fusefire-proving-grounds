# Movement foundations 03: traversal integration, timing contract and geometry validation

Hardening of the uncommitted traversal work (ladders, stairs, path smoothing, shared leg IK). Repository state at the start: `main` at `396c8cb` (ladder work committed); the stair, ramp, path-refinement and metadata work of Movement Foundations 01-02 uncommitted, plus the six Kenney `.import` files; the earlier ladder timing review had been answered only by a presentation-speed default, so its findings still applied and are re-verified here.

## 1. Integration findings (and what was fixed)

| # | Finding | Severity | Action |
| --- | --- | --- | --- |
| 1 | The presenter waited for a visual walk with a **fixed 30 s deadline**; with the approved speeds and replay playback 0.5x a long ladder plus stairs can approach it, which ends in "timed out; snapped to committed destination". | medium | `TacticalUnit.estimated_move_seconds()`; the deadline is now `max(30 s, 3 x estimate)`. |
| 2 | `_present_reactive_move` walked **one leg per call**, so a stair or ladder run was cut into one-link models and the feet/contacts restarted at every cell whenever a reaction was possible. | high for stairs/ladders | Legs between reaction checkpoints are now walked in one order; reactions still fire at their checkpoint. |
| 3 | Ladder identity was **inferred from height** (any vertical link of at least 1.8 m). | high | Ladders now carry an explicit kind (see 3). Undeclared vertical links keep the placeholder clips. |
| 4 | Ramps shared the stair/ladder route shape (vertical pop, then level) and the `climb` clip. | medium | A declared ramp is walked along its slope (see 5). |
| 5 | The pelvis jerked up to a whole riser per footfall (feet-only solve). | medium | Pelvis = smoothed floor reference pushed only as far as the planted legs demand (`pelvis_smoothed`); root ride ramp widened to a full tread. Worst frame step of pelvis/chest/head fell from 0.042 m to 0.030 m on the 0.5 m stairs. |
| 6 | Carrier on a ladder: contacts and ladder pose correctly off, but see 8 (unsupported combination, documented and tested). | info | tests |

## 2. Confirmed timing contract

Verified by `traversal_timing_contract_test` on the real range:

1. **Tactical first.** `try_move` commits the destination (grid occupancy, AP, replay record) before any pixel moves: mid-climb, with the body more than 0.5 m from the target, `grid.get_unit_grid(actor)` and `grid.get_unit_at(top)` already name the destination.
2. **The action barrier holds.** A second command issued while the unit is still walking is rejected (action service busy). `try_move` returns only after `unit.is_moving` is false and the unit stands exactly on the committed cell, so the next command, the AI's next decision, turn progression and reaction attacks all see a finished walk. The presenter polls `is_moving` (it also observes teardown), and the deadline follows the walk.
3. **Reactions** happen at their checkpoints between whole stair/ladder runs; the mover stops at the checkpoint, the watcher shoots, the walk resumes.
4. **Replay.** `BattleReplayPlayer` scales `movement_speed` by playback speed (0.5 to 4.0); the traversal speeds scale with it (`movement_speed / 5`). Measured: the 3 m stairs take 7.1 s at 0.5x and 1.8 s at 2.0x (ratio 3.92 for an expected 4); the ladder 3.7 s at 1x and equal to its own estimate within 25%.
5. **No new blocking and no scheduling change**: only the existing barrier and a deadline that scales. Tactical turn scheduling is untouched.
6. **Replay determinism** (`traversal_replay_determinism_test`): eight scripted moves (flat route, ramp, stairs, ladder, back) run with every presentation feature off and then on give byte-identical recorded action records, identical state fingerprints after each move, identical AP and cells; only the time to present differs (5.3 s vs 14.0 s).

Defaults (provisionally approved): stairs 1.4 m/s, ladder up 0.85 m/s, down 0.75 m/s; tunable on `StairProfile` / `TraversalProfile`.

## 3. Classification (corrected)

`TraversalLinkData.surface_kind`: `UNSPECIFIED` (generic vertical link), `RAMP`, `STAIRS`, `LADDER`; low-cover transit stays a vault transit cell (route shape), not a link. Sources: `ElevationPath.surface_kind` (Ramp, Stairs) and the ladder contract metadata (`ladder_local_bottom/top`) which now stamps `LADDER`. The tactical test range's nine links: **3 ladders, 3 stair steps (2 treads each), 3 ramp steps, none undeclared** (`traversal_classification_test`). Only a LADDER link gets rung contacts; only a STAIRS link with a tread count gets stair feet; a RAMP is walked on its slope; an UNSPECIFIED vertical link still works exactly as before with the placeholder clip. The old `ladder_min_rise` height guess was removed. Legality, cost and reachability are untouched (same AP, same cell, declared or not: tested).

## 4. Stair geometry

The range's `TrainingGallery/Stairs` has six CSG treads of 0.5 m rise and 0.5 m depth; one tactical level is 1 m and one cell 1 m, so each one-cell link is two treads: a **coarse test fixture, scaled to the grid (45 degrees)**, not conventional stairs (the signage reads "RAMP / STAIRS" in a test range; the generated-map traversal data lists STAIRS as a kind without geometry). Authored content was not remodelled. Realistic dimensions are tested in `traversal_stair_gait_test` (0.17 m risers, 0.28 m treads, 14 treads), up and down, with flat-to-stair and stair-to-flat hand-over.

| Case | Tightest knee | Pelvis step per 2 mm | Swing foot pulled in | Unreachable |
| --- | --- | --- | --- | --- |
| 0.5/0.5, every tread, up and down | 45 degrees (the limit) | 0.0088 m | 0.05-0.06 m | 0 |
| 0.17/0.28, every tread | 88 degrees | 0.0059 m | 0.000 m | 0 |
| 0.17/0.28, every second tread | 53-54 degrees | 0.0050 m | 0.000 m | 0 |
| 0.5/0.5 forced every second tread | - | - | - | **350 of 1125 samples** (outside reach; AUTO never does it) |

Policy by speed (`AUTO`): 1.2 m/s every tread on both stairs; 3.0 and 4.6 m/s every tread on the 0.5 m stairs, every second tread on the realistic stair; a loaded carrier never skips. Foot support, riser clearance (no sole below a tread, up or down), locked stance (0.00000 m slide), pelvis reach, knee angles and the weight hand-over (exactly 0 at both ends, jump under 0.01 per sample) are asserted. The pelvis climbs with the stair (about 2.1 m over the 2.38 m realistic stair's walked part). Remaining roughness: at the 0.5 m fixture the pelvis still rises up to about 6 m/s at the 1.4 m/s walk during a step (about 4.4 m/s on the realistic stair); the whole-riser lift is inherent to the fixture.

## 5. Ramps

A ramp is a continuous incline. Ramp metadata never triggers stair logic (`stair_link` is null for it; no stair state, ladder pose or climb clip in play). The walk now follows the slope: the unit's deviation from the ramp plane is **under 0.02 m** (the undeclared old route measures over 0.4 m), same AP and cell. Not done (no demonstrated defect beyond this): foot orientation to the slope and slope-matching leg IK; the walk uses the ordinary gait on the incline.

## 6. Path refinement (still off by default)

`traversal_path_gameplay_test` now scans **120 legal routes** from three starting places on the range (beside the support columns, open ground, the stair foot): 62 were smoothed, **0 mismatches** between the tactical sweep and the refiner, endpoints exact on all, **clearance 0.500 m minimum sampled every 2 cm along the whole smoothed path** (body 0.320), no point more than 0.072 m from the authorized route. Stair, ramp, ladder and vault legs are excluded from the clearance check (they legitimately touch their own blocks) and are never smoothed. A route the geometry does not support is reported and left untouched (unit test and a real column route). Same cell and AP with it on or off (tested); occupancy and replay records untouched (replay test enables it in the "on" run). Not enabled globally.

## 7. Round objects (investigation only; tactical traversability unchanged)

* **Current semantics.** A round asset's tactical volume is a conservative box: every cell its footprint touches becomes a whole-cell `movement_parts` stand-in (`presentation_stand_ins` marks them); the real circle is recorded only in `MapData.presentation_cylinders` for cover markers and pose contacts (`authored_scene_map_compiler._register_presentation`). `CylinderPart` (pure) answers `segment_clear(from, to, body_radius, height, clearance)` exactly and `resolve(cell, cylinders, ...)` finds a legal standing point in a cell; its header says it is not integrated.
* **Measurement** (synthetic, grid-aligned, body 0.28 + 0.04; `tools/quality/movement_audit.gd`, section E; the range itself has no round assets): r = 0.5 centred on a cell: 1 cell blocked either way. r = 1.0 centred: **stamping blocks 9 cells and 12 east-west edges; exact queries block 5 cell centres and 8 edges** (the four diagonal cells and four edges are over-blocked). r = 1.5 centred: 9 and 12 either way. r = 1.0 on a corner: 4 and 6 either way. The over-blocking is concentrated in diagonal cells next to mid-size tanks; large and small ones are already tight.
* **Integration points** (in order of risk): (1) the sweep inside `SurfaceNavigation._sweep_clear` / `traversal_route` (use `segment_clear` for parts flagged round, body radius = `data.body_radius`), (2) the cell stamping in the compiler (stop emitting the coarse stand-in, rely on `resolve`), (3) `SurfaceNavigation.supported`/`body_clear`, (4) the cover and LOS code, which read the stand-ins today.
* **Consequences to decide first:** a cell the stamping blocks but `resolve` accepts becomes newly traversable/stoppable (new reachable destinations, changed AP paths, different occupancy and cover geometry, changed replay of existing recordings); the AI's planning caches key on the old geometry. This is a tactical change and needs its own approved milestone.
* **Regression scenarios for that milestone:** replay recordings from content with round assets must stay byte-identical until the change is switched on per map; reachable-cell counts before/after on every authored parcel with round assets; occupancy of a round-adjacent cell by two units; LOS and cover across a tank; the refiner against `segment_clear`; a body radius per unit.

## 8. Loaded carriers

The tactical rules allow a carrier everything: carrying only lowers the movement budget (`stats.speed - 2`, min 2). Presentation, tested in `traversal_loaded_carrier_test` (steady carry set up through the rig):

| Traversal | Legal | Presentation while carrying |
| --- | --- | --- |
| Stairs | yes | **path follows the treads** (no pop; float 0.48 m, sink 0), carry gait, no stair feet or leg IK (unsupported), slow stair speed applies (3.6 s) |
| Ramp | yes | follows the slope (deviation 0.000 m) |
| Ladder | yes | **unsupported presentation**: no rung contacts, no pose, route speed (0.8 s for 3 m: the old placeholder pop with the carry gait) |
| Low-cover vault | yes | unchanged placeholder (not on the range; not exercised) |

In all three the passenger stayed on the carrier's chest (drift range under 0.05 m, about 0.24-0.27 m absolute) and the rifle stayed slung; nothing of stairs/ladder was left behind. Risks: a ladder pop with a body on the shoulders is visually crude; a stair walk without feet IK can clip feet through risers on 0.5 m stairs (not measured, the passenger test measures drift only); hand contacts cannot be shared with rungs. No restriction was added; a design decision is needed (allow with a proper carry-climb, or forbid ladders for carriers).

## 9. Tests

Run by the movement suite (names match "traversal"): `traversal_solver_test`, `traversal_rig_test`, `traversal_ladder_gameplay_test`, `traversal_stair_feet_test` (66), `traversal_stair_gait_test` (48, new), `traversal_stair_gameplay_test` (22), `traversal_path_gameplay_test` (17), `traversal_classification_test` (11, new), `traversal_timing_contract_test` (11, new), `traversal_replay_determinism_test` (6, new), `traversal_loaded_carrier_test` (12, new); plus `path_refiner_test` (path_). Captures (explicit-only): `traversal_ladder_capture`, `traversal_stair_capture`.

## 10. Open decisions

Presentation speeds (provisionally approved); carriers on ladders; round-object navigation milestone; whether to author stairs at conventional dimensions for realistic play (the fixture is intentionally coarse); declaring `treads_per_step` and rung layouts on all authored scenes; ankle/slope orientation.

## Update (2026-11-20, foundation closure)

Ramp contract finalised: a declared ramp is walked continuously along its real slope (within 7 mm of the authored surface), with one stepped rise at the authored 0.5 m lip below the exit deck (`TraversalLinkData.step_at_to`). Cost, legality, destination and replay records are unchanged. The old `current_path.size() == 7` expectation was replaced by behaviour assertions. The stair alignment correction (one tread) is in the same note. See [foundation-closure-2026-11-20.md](foundation-closure-2026-11-20.md).
