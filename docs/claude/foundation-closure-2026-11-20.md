# Foundation closure: ramp contract, stair alignment and F-04 (resolution note)

Follow-up to [animation-architecture-audit-2026-11-20.md](animation-architecture-audit-2026-11-20.md) (which stays as the historical record of what it observed) and to the Movement Foundations 01-03 reports. Scope: close the unfinished Movement Foundations checkpoint (the ramp contract, F-13) and the confirmed spine composition defect (F-04). No architecture migration was started.

## 1. Baseline

`main` at `396c8cb` (ladder traversal, committed). Working tree: Movement Foundations 01-03 uncommitted (15 modified tracked files, about 36 new files) plus six unrelated Kenney `.import` changes; the architecture audit and developer guide, also uncommitted. The audit's description of the tree was accurate at the start of this work.

## 2. Ramp contract

**Owner decision (provisional, now verified):** a declared ramp is presented as continuous travel along its real slope, not as a repeated vertical-rise/horizontal-step sequence.

**Verification against the real geometry (physics rays against the authored CSG on the Tactical Test Range, not the tactical block stand-ins):**

* The ramp body is a straight 45 degree slope through the cell centres: the physical surface equals `y = -0.5 - z` within **0.007 m** from the foot to the last cell. So the continuous walk matches the authored ramp (`traversal_surface_alignment_test`).
* **Finding: a step at the top.** The authored ramp ends at the cell boundary (2.45 m high at z = -2.95) and the exit deck begins at 3.0 m: **a 0.5 m lip** (verified: 2.45 below, 3.00 above). Walking the pure slope into the exit cell would take the unit through the deck's edge for the last half cell. The old vertical-then-level route avoided that only because it floated. Correction: `TraversalLinkData.step_at_to` (set by the compiler on the last link of a Ramp path) makes the walk climb the slope to the cell boundary and step up there; descending reverses it. Presentation only.
* Legality, cost and destination are untouched: the same three one-step links (path cost 3.0), one action (1 AP), exact final cell and floor point. Ramp classification stays separate from stairs and ladders (`stair_link` is null for a ramp). Ascent and descent are both covered. Speed: the ramp keeps the ordinary route speed; completion is the same tactical-first barrier (`traversal_timing_contract_test`). Replay: the scripted ramp/stairs/ladder sequence still produces byte-identical records and fingerprints with presentation on and off (`traversal_replay_determinism_test`).

**Old versus new ramp behaviour (measured against the physical surface):**

| | Old (vertical rise, then level step per link) | New (continuous slope, step at the lip) |
| --- | --- | --- |
| Deviation from the physical surface | up to about 1 m (floating in the air between links; the test measured over 0.4 m) | 0.007 m |
| Waypoints for the 3-link ramp | 7 | 6 |
| Vertical steps | 3 (one per link, in mid air) | 1 (the authored lip, 0.5 m) |

**The test.** `surface_vertical_traversal_test` asserted `current_path.size() == 7`, a statement of the old route, not of behaviour. It now asserts behaviour: the move completes on the committed cell and exact floor point; the unit stays on the physical surface (float under 0.02 m, sink under 0.02 m, excluding the lip plane); the tactical cost is unchanged (path cost 3.0, one AP); the route climbs steadily toward the exit, never backwards, with exactly one vertical step no taller than the lip; the route ends at the committed destination. The ladder assertions in that file are untouched. The ramp's new contract is also covered by `traversal_classification_test`, `traversal_loaded_carrier_test` (a loaded carrier walks the ramp on its slope) and `traversal_surface_alignment_test`.

### 2a. A correction found while verifying: the stair alignment

Checking the stairs against physics rays showed that **the stair model of Movement Foundations 02 was one tread too low**: it assumed the first riser half a link up the stair and a cell centre ON a riser line looking up, so every foothold was 0.5 m below the real treads (it had only been compared with the tactical block stand-ins and with itself). The verified convention: **a cell centre is at the foot of a riser, standing on the lower tread; the first riser is at the foot cell's own centre; tread k (top at k x rise) spans [(k-1) x depth, k x depth].** `StairModel.from_links`, `height_at`, `path_points` and `ride_path_height_at` were corrected, and the pelvis reference now follows the smoothed tread tops (the average of a staircase is the line through its tread tops, half a rise above the line through its cell centres). Result against physics: model tread tops equal the physical ones to **0.0000 m**; planted soles equal the physical treads to **0.0000 m** (235 samples up, 235 down); ankle bones reach them within 4 mm. Side effects, all improvements: `pelvis_smoothed` is a closed-form average (**15 us per call, was 505 us** measured in the audit), the pelvis step per 2 mm on the 0.5 m stairs stays at 0.009 m, and the root reference line no longer sits above the treads (it sits up to one riser below, the body being placed by the feet and the pelvis). The tests that encoded the old alignment (`traversal_stair_feet_test`, `traversal_stair_gameplay_test`, `traversal_loaded_carrier_test`) were updated to the verified geometry and the physical test is new.

## 3. F-04: spine composition

**Reproduction** (production stack on the workbench rig, driver stopped, modifiers set by hand, poses read in `skeleton_updated`; `tests/locomotion_cover_composition_test.gd`, run against the pre-fix code): with a 20 degree turn and an aim lean the **chest yaw was -13.4 degrees instead of 0**; with a 15 degree turn and the 20 degree carry lean it was **-10.0 degrees**; in a cover crouch with lean and turn it was -13.4 degrees; the spine's twist share was erased (-20.0 against the -13.3 it should keep). 6 of 13 checks failed.

**Root cause.** `LocomotionPoseModifier` (first in the order) twists the hips and gives the twist back up the spine so the chest's net yaw is zero; its writes MULTIPLY the current pose. `CoverCrouchModifier._apply_lean` then wrote the spine bones as the ABSOLUTE pose `rest * lean`, discarding every other component of the bone's pose, including that compensating twist, whenever any lean (aim, carry, ladder) or crouch was active.

**Correction** (`presentation/characters/runtime/cover_crouch_modifier.gd`): the lean still OWNS the spine's flexion (rotation about the measured forward axis): it replaces the baked flexion (a gait's running lean, a clip's own pitch) exactly as before, because those are intended replacements. Every other component of the bone's current pose is kept: `_set_flexion_keeping_rest` removes the flexion part by swing-twist decomposition about the measured axis and re-applies the lean to the rest, so `result = rest * others * lean`. With no other influence this equals the old `rest * lean` (no change in the existing cover, aim and carry poses), and with a Locomotion twist the twist is preserved exactly. The leg flexion writes (`_set_flexion`, the crouch solve) and the support clavicle remain absolute on purpose (the crouch solves the legs completely). The modifier order is unchanged.

**Result** (same cases, post-fix): turn only: hips -20.0, chest yaw 0.0; lean only: chest pitch -5.7; **turn + lean: hips -20.0, chest yaw 0.0, spine twist share -13.3 (equal to the turn-only value), chest pitch -5.5**; loaded carry turn: chest yaw 0.0 (was -10.0), carry lean -18.8 against -19.3 alone; cover crouch + lean + turn: chest yaw 0.0, the crouch height identical; back to neutral: no residue (hips, spine and lower spine). 13 of 13 checks pass.

**Known bounded interaction:** the start/stop pitch (a rotation about the hip hinge on the first spine bone) is also a flexion, so while a lean is active the lean owns it; because the hinge and the bone's own axis agree only within the rest tilt, a part of the pitch survives (up to about 1.2 degrees on a 4 degree pitch with a 6 degree lean) and never stacks. This only occurs when a unit accelerates with the weapon up or a lean active, which the game does not do in practice (loaded locomotion sets the pitch to zero); documented, not changed.

## 4. Tests added or changed

New: `locomotion_cover_composition_test` (13), `traversal_surface_alignment_test` (18). Changed to reflect intended contracts: `surface_vertical_traversal_test` (ramp assertion rewritten, 23 checks), `traversal_stair_feet_test` (alignment), `traversal_stair_gameplay_test` (root reference semantics), `traversal_loaded_carrier_test` and `traversal_classification_test` (ramp expectations now piecewise: slope to the lip, deck beyond). No assertion was weakened to obtain a pass: each changed expectation encodes the verified physical geometry or the new documented contract. Both new tests are picked up by the existing runner patterns (`locomotion` and `traversal`).

## 5. Validation

Run on 2026-11-20 with Godot 4.7.2 headless, after the final code edit.

* **Full tier** (`tools/run_tests.ps1 full`): **PASS=209, FAIL=2, SKIP=24** (2,232 s). The 24 skips are the explicit-only visual captures and similar (not run, not claimed).
* **The two failures are not caused by this work.** `cover_edge_selection_test` ("the rifle's direction never jumps ... worst N deg/s", limit 900) and `cover_target_aware_test` ("without a muzzle jump", same kind of limit) fail identically on a clean checkout of `HEAD` (396c8cb, no working-tree changes, separate worktree): 4453 and 2922 deg/s there; 3801 to 8940 deg/s here, varying from run to run, and 3801 with the F-04 change reverted. The measure is a wall-clock angular rate per rendered frame, so it varies with headless frame timing; it is probably an environment/test-timing issue (or a pre-existing regression from the earlier cover commit) and needs its own diagnosis. Not changed, not skipped, not weakened here. Both are reported as open failures.
* **Focused suites** (all passing when last run): `traversal_surface_alignment_test` 18, `surface_vertical_traversal_test` 23, `locomotion_cover_composition_test` 13 (6 failing before the fix), `traversal_stair_feet_test` 66, `traversal_stair_gait_test` 48, `traversal_stair_gameplay_test` 22, `traversal_loaded_carrier_test` 12, `traversal_classification_test` 11; the rest of the traversal, path and locomotion tests passed inside the full tier.
* **GDScript warning audit:** 0 warnings.
* **Not run:** the explicit-only visual captures (e.g. `traversal_stair_capture`). Headless success does not establish visual correctness; the stair and ramp look has been verified by physics-ray measurement, not by eye in this closure.

## 6. Remaining limitations

* The authored ramp's 0.5 m lip is stepped (a vertical hop at the cell boundary), not climbed with a mantle motion; no foot placement on ramps (the ordinary gait runs on the slope).
* The stair model assumes straight, uniform stairs declared with `treads_per_step`; the verified alignment holds for the range's stairs; other authored stairs must follow the same cell-at-the-foot-of-a-riser convention (a metadata requirement).
* Loaded carriers keep the old ladder placeholder and no stair feet; hit/interruption of a climb is only partly covered (see the audit F-06).
* The F-04 pitch interaction above; pelvis steps on the 0.5 m fixture stairs remain abrupt (inherent to the fixture's riser height).
* Explicit-only visual captures were not re-run for this closure (see section 5).

## 7. Checkpoint file inventory

Nothing is committed. Proposed grouping (three commits, in this order):

**A. Movement Foundations 01-03 (traversal presentation)**
* Modified: `art/characters/mira_0/demo/locomotion_test_panel.gd`, `art/characters/mira_0/demo/mira_0_pose_workbench.gd`, `art/environments/authored/parcels/tactical_test_range.tscn`, `presentation/actions/tactical_action_presenter.gd`, `presentation/characters/runtime/{character_rig,traversal_pose_modifier,traversal_profile,unit_visual_adapter}.gd`, `systems/generation2/authored_scene_map_compiler.gd`, `systems/grid/{elevation_path,surface_navigation,traversal_link_data}.gd`, `units/tactical_unit.gd`, `tools/run_tests.ps1`, `tests/surface_vertical_traversal_test.gd`
* New: `presentation/characters/runtime/{path_presentation_profile,path_refiner,stair_foot_planner,stair_model,stair_profile}.gd` (+ `.uid`), `tests/{path_refiner,traversal_classification,traversal_loaded_carrier,traversal_path_gameplay,traversal_replay_determinism,traversal_stair_capture,traversal_stair_feet,traversal_stair_gait,traversal_stair_gameplay,traversal_surface_alignment,traversal_timing_contract}_test/capture.gd` (+ `.uid`), `tools/quality/movement_audit.gd` (+ `.uid`)

**B. F-04 correction**
* Modified: `presentation/characters/runtime/cover_crouch_modifier.gd`
* New: `tests/locomotion_cover_composition_test.gd` (+ `.uid`)

**C. Documentation**
* `docs/claude/README.md` (modified), `docs/claude/{movement-foundations-01-research,movement-foundations-02,movement-foundations-03,animation-architecture-audit,animation-developer-guide,foundation-closure}-2026-11-20.md`, `docs/claude/images/traversal-stairs-and-paths.png`

**D. Test measurement fix (separate small commit, or fold into B):** `tests/cover_edge_selection_test.gd`, `tests/cover_target_aware_test.gd` (section 8).

**Not part of this checkpoint (leave out):** the six `art/environments/kenney/*/models/Textures/colormap.png.import` changes (unrelated); `AGENTS.md`, `.agents`, `.codex` (local only).

Caveat for A: some of A's files were also touched by the closure work (stair model, planner, profile, compiler, unit, ramp tests), so A already contains the corrected alignment; B is cleanly separable.

## 8. Addendum: the two cover muzzle-rate failures (diagnosed and fixed)

`cover_edge_selection_test` and `cover_target_aware_test` failed their "no muzzle jump" check on a clean `HEAD` as well. Cause: a **defective measurement**, not a motion regression. The tests divided the per-frame muzzle angle by the wall-clock time between two `await process_frame` resumptions, quantised to 1 ms. On fast headless frames the resumption gap can read 1 ms for a frame that actually advanced by the engine's normal delta, so a smooth 3.3 degree frame printed as 3256 deg/s (probe: "3.26 deg in 0.0010 s"; the neighbouring frame was 2.03 degrees in 8 ms). Fix: both tests now divide by the engine's own delta for the frame (`Node.get_process_delta_time()` on a clock node in the tree), the quantity the animation actually advanced by. The 900 deg/s limit and the checks are unchanged. Result: worst rate 667 to 689 deg/s (limit 900), 28/28 and 41/41 checks pass, repeated. A real pop larger than about 15 degrees in one frame still fails. The last executed full-tier result remains PASS=209, FAIL=2, SKIP=24 (section 5). After the fix the two tests were re-run on their own, twice each, and passed; no full tier was run after the fix, and no 211/0/24 result exists. The next complete regression run is deferred to a later architectural milestone.

## 9. Correction (Task 02.5)

Section 8's fix was incomplete. Dividing by the engine delta removed the wall-clock quantisation but an uncapped headless run still produces 1 to 5 ms frames with unstable deltas, and three of four later runs of `cover_edge_selection_test` failed (1,539 to 2,166 deg/s) with the same smooth motion. Both cover tests now also pin `Engine.max_fps = 60` while they measure; at that rate the worst single frame is about 8 degrees and the worst rate 325 to 336 deg/s (limit 900), over 8 consecutive passing runs. Details: [test-suite-efficiency-2026-11-20.md](test-suite-efficiency-2026-11-20.md).
