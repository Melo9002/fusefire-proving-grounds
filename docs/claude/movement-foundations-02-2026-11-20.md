# Movement foundations 02: clearance-aware path presentation and stair footsteps (prototype)

Builds on `movement-foundations-01-research-2026-11-20.md`. Everything here is presentation: the tactical route, AP, occupancy, LOS, cover and the replay record are untouched, and the committed position is still snapped to the exact cell.

## 1. Implemented

### A. Path presentation (`PathRefiner`, opt-in, experimental)
Pure function of (route floor points, physical part AABBs, body radius, height). Steps: (1) every horizontal segment of the authorized route must already clear every part by the body radius (the tactical sweep's own rule); if one does not, a **mismatch is reported and the route is returned unchanged** (no new route, no teleport); (2) each flat corner is replaced by a quadratic curve cut back at most `corner_cut` (0.45 m); the cut is halved up to three times until every curve segment keeps the clearance, else the corner stays sharp. Vertical and stepped segments (ladders, stairs, vaults) are never touched. `PathPresentationProfile.enabled` is **off by default**.
Integration: `TacticalUnit.move_along_path` runs it per flat run of the expanded route; points inherit the pose and stair id of the point they replace; `last_path_report` carries mismatches and the rounded count.

### B. Stairs (`StairModel`, `StairFootPlanner`, `StairProfile`)
* **Declaration (new metadata, defaults unchanged):** `ElevationPath.surface_kind` (Unspecified / Ramp / Stairs) and `treads_per_step`, carried into `TraversalLinkData` by the compiler. The test range's stairs are declared (stairs, 2 treads per step) and its ramp as a ramp; undeclared paths keep the old presentation.
* **Alignment convention** (verified against the range): the upper cell of a link sits on the last riser line, so risers are at `D - (n-k) * depth` from the lower cell centre.
* **Root path**: for a run of consecutive stair links the walk follows a polyline that is level on each tread and ramps over up to a tread's depth (`riser_ramp`, now 0.5 m) ending exactly on each riser line (cell centres keep their exact floors); 5.33 m for the 3 m stair instead of 6.00 m. (Updated in Foundations 03: pelvis smoothing and the wider ramp; ladders and stairs are classified by explicit link kind, ramps follow their slope.)
* **Foothold planner**: ordered holds (ground, chosen treads, landing); feet alternate; 50% stance; a foot lifts first and travels after going up, travels first and drops after going down; stance feet are locked; deterministic in the unit's progress along the stair only.
* **Contact policy** `StairProfile.ContactPolicy {EVERY_TREAD, ALTERNATE, AUTO}`; AUTO = every tread, except every second tread when the unit is at least 3 m/s, unloaded, **and the double rise is something the legs span** (`max_step_rise` 0.55 m). On the 0.5 m range stairs AUTO never skips (see findings).
* **Pelvis** placed from the feet: highest height at which a planted leg neither overreaches nor folds past 45 degrees; a swinging ankle is pulled in only as far as the knee limit allows.
* **Rig**: the existing `TraversalLegIK` two-bone IK and the `Traversal` modifier now also apply stair feet and pelvis height (weight 0 at both ends of the stair walk, so the animation's legs hand over with a blend). No new modifier or solver; arms, rifle and `LocomotionPoseModifier` untouched. A carrier keeps the existing loaded gait (stairs are not applied while carrying).
* **Speed**: with `slow_stairs_enabled` the stair is presented at 1.4 m/s along its slope (route speed 5 m/s would give seven steps a second on 0.5 m treads); same decision as the ladder, presentation only.

### C. Workbench
Stairs section (0.5/0.5 and 0.17/0.33 presets, custom rise/depth sliders, up/down, hold at mid stair, pause, **frame step**, slow motion from the existing slider, readout of progress/weight/step/pelvis, planned-vs-actual foot markers) and a Path corridor section (open, wall, corner, column, narrow ok, too narrow; tactical route white, smoothed route cyan, obstacle footprints orange, character footprint circles green, mismatch in the readout). All use the production classes.

## 2. Measurements (Tactical Test Range stairs, real Move)

| Metric | Before | After |
| --- | --- | --- |
| Root floor above the tread beneath it | up to 1.50 m (vertical 1 m pop, then glide) | max 0.48 m (never more than one riser), sink 0.000 m |
| Path length, 3 m stair | 6.00 m | 5.33 m |
| Planted-foot sliding | n/a | 0.00000 m |
| Ankle bone vs planted foothold | n/a | 0.003 m worst |
| Pelvis | n/a | reachable in every frame (0 unreachable) |
| Stair weight change per frame | n/a | 0.03 at most |
| Ascent duration shown | about 0.9 s | 3.6 s (presentation speed 1.4 m/s) |
| AP / final cell / floor height | unchanged | unchanged (tests compare) |

Corridor (tests and range): a 0.48 m column passed at 0.76 m is smoothed with clearance 0.760 m; the L route past it is 2.83 m vs 3.00 m; a corridor 0.05 m wider than the body each side is walked with the clearance intact; one 0.1 m too narrow is reported and returned unchanged; a route through the column is reported.

## 3. Findings worth the owner's attention

* **0.5 m risers are extreme for this body** (leg 0.84 m, arm 0.46 m): every-tread stepping works only at the 45 degree knee limit (the range stairs measure 45 degrees at the tightest point with the pelvis at its highest allowed), and skipping a tread would need 1.0 m of rise between feet, impossible. On realistic stairs (0.167 m rise, 0.333 m depth) both policies work (knee 63 to 94 degrees).
* The treads are not in the map data (only cell-sized stand-ins): they are authored as visible CSG and described by the new `treads_per_step` metadata plus the alignment convention.
* Stairs and ramps share the link type; only the new metadata tells them apart.
* On every surface map the straight segment between two authorized centres is already clearance-validated, so corridor refinement never avoids a collision there; its value is smooth corners and the mismatch report. Round obstacles are still stepped tile boxes (`CylinderPart.segment_clear` exists and is unused).

## 4. Determinism

Stair feet, pelvis and weight are pure functions of the unit's progress along the stair (checked frame by frame in `traversal_stair_gameplay_test`: the rig's feet equal the planner's for the unit's progress, 0 differences) so frame rate, pause, replay speed and seeking cannot change contacts. The refined path is a pure function of the route and the map. Neither enters the replay record.

## 5. Tests (movement suite, run by the runner's "traversal|path_" patterns)

`traversal_stair_feet_test` (66: model alignment, ride path, policy, feet on treads, locked stance, no riser penetration up and down, reach, knee limit, determinism, weights; both the range stairs and a low-rise stair), `traversal_stair_gameplay_test` (21: the real Move up and down the range stairs: cost, exact end, float and sink, slide, ankle error, pelvis, weight smoothness, cleanup, defeat mid-stair), `path_refiner_test` (17), `traversal_path_gameplay_test` (12: real map parts, mismatch report, same cell and AP with the refinement on and off).

## 6. Still experimental / known failure cases

Path refinement is off by default and not exercised by the AI or replay playback in a real match; foot orientation to the tread slope, heel/toe roll, stance-foot lock against the root's own drift, and ankle-to-ground blending at flat-to-stair entry are not done; loaded carriers on stairs keep the old gait; the knee limit is enforced in the planner (pelvis and swing foot), not inside the IK solver; tread layout is assumed uniform and straight; no spiral or turning stairs; stair speed is a presentation decision; round obstacles and different body sizes are not handled.

## 7. Next steps

Decide the presentation-speed question for ladders and stairs together; declare stairs on the remaining authored scenes (and rung layouts for ladders); ankle orientation and a foot-roll pass; exercise the refinement in the AI and replay paths with a recorded-trajectory comparison; per-unit body radius; use `CylinderPart` for round obstacles.

## Update (2026-11-20, foundation closure)

The stair alignment described above was corrected after this report: checked against physics rays on the authored stairs, the model was one tread too low. The verified convention is that a cell centre is at the foot of a riser and the first riser is at the foot cell's own centre. The pelvis reference is now the smoothed tread-top surface. Planted soles now equal the physical treads to 0.0000 m. See [foundation-closure-2026-11-20.md](foundation-closure-2026-11-20.md). Heights and thresholds quoted above that depend on the old alignment are superseded.
