# Ladder traversal stabilization (issue #55)

Status: **implemented and measured; full-suite result at the end of this file**. Not signed off by the owner. Branch convention: main, no branches.

Baseline for the independent Task 14 audit: commit `5034527`, tagged `task14-audit-baseline` (local tag, see "Audit baseline"). Nothing in this work touches that commit.

## 1. Root cause

Four separate defects, none of them in the hand-contact writer (`CharacterRig.claim_hand_contact`, which puts the wrist on its target whenever the arm can reach it):

1. **The ladder was described three times.** The authored scene, `TraversalProfile` (first rung, pitch, rise scaling, plane) and each tool (sandbox, workbench, captures) restated rung heights. Three parcel ladders were the 4 m mesh stretched to 0.75 in Y, so their pitch was 0.2475 m while the planner assumed the scaled value only because a profile flag said so.
2. **Windows were MIRA's metres.** The hand and foot windows, the pelvis height (0.90 m) and the standoff (0.30 m) were authored for MIRA. Small MIRA's pelvis hung at MIRA's height although its legs are 0.54 m, and its hands were asked for rungs 0.66 m apart. A two-rung stepping pattern needs an arm span of about two pitches (0.66 m at the old 0.33 m pitch); Small MIRA's arm (0.32 m) spans about 0.55 m even when hugging the ladder. Scaling the profile by `body_ratio` (the Task 11 attempt) cannot fix that: the sequencing of the windows was the problem.
3. **Knees went through the rungs.** The knee pole was a fixed offset from the foot (0.45 m up, 0.55 m forward), so every knee ended 7 to 14 cm beyond the rung plane and the thighs and shins crossed the bars. The foot targets were perfect and the legs were still inside the ladder. A raised knee is the hard part: with a 0.25 m pitch and a hip-to-ankle distance of 0.34 to 0.5 m the knee stands 0.25 to 0.3 m off the hip-ankle line, which cannot stay behind a rung plane unless the pelvis hangs far back, and the arms cap how far back it can hang.
4. **The wrist target was the rung's centre line**, so the forearm ran through the bar it grips.

## 2. Geometry ownership decision

One definition, **`LadderGeometry`** (`presentation/characters/motion/ladder_geometry.gd`), pure data plus a volume test. It owns pitch (0.25 m), first rung (0.25 m), top margin, rail span and thickness, rung size, the rung plane and the rise.

* The authored components **are** that definition: `maintenance_ladder_4m.tscn` (15 rungs) is regenerated from it and a new `maintenance_ladder_3m.tscn` (11 rungs) replaces the three 0.75-scaled 4 m instances (two in `tactical_test_range`, one in `combat_examples`). `ladder_geometry_test` compares every rung and rail and fails any parcel that stretches a ladder mesh (control: a synthetic stretched instance is detected).
* The profile no longer has rung fields, the plane, standoff, windows, ankle offsets, deck handhold start or hand release start. A host supplies only the rise.
* Sandbox, workbench and captures draw with `LadderGeometry.build_visual`.
* A taller or shorter ladder has more or fewer rungs at the same pitch. A stretched mesh is rejected by the test, not accommodated by the solver.

**Pitch decision.** 0.33 m is not usable by Small MIRA with alternating limbs (see cause 2); it is also outside the usual 0.25 to 0.30 m range. 0.25 m was chosen after measuring both bodies (`agent-comms/ladder_sweep.gd`, not committed). The owner approved changing the authored ladders. This is visual only: AP, routes, legality and the ladder metadata cells are unchanged.

## 3. Implementation summary

| Piece | Change |
|---|---|
| `LadderGeometry` (new) | The layout; exact capsule-against-rung/rail `penetration`; `build_visual`. |
| `LadderBody` (new) + `CharacterRig.ladder_body()` | Limb lengths and joint offsets measured once from the rest skeleton (thigh, shin, upper arm, forearm, hip and shoulder offsets, ankle height, ball length, ratio). |
| `TraversalSolver.plan_ladder` / `ladder_pose` | Pure function of (profile, geometry, body, height). Pelvis hangs at the torso's clearance and, where a raised knee needs it, farther back, up to what the arms still hold over their whole hand span. Hands step one rung (a short body) or two (a body whose arm span covers most of two pitches); feet step one rung; limb pairs are a quarter window apart with swings that do not overlap. Hand and foot windows are derived from the shoulders' height and the leg's reach. Planted limbs are on rungs exactly. The wrist holds a rung from below and behind (`GRIP_BELOW`, `GRIP_BEHIND`, scaled by the body). Returns `hand_reachable` and `foot_reachable`. A limb with no rung left in its own step takes the last rung there is, in both directions. |
| `LadderKneePlanner` (new) | Pure: from the actual hip and ankle, the leg's length and the rungs, finds the thigh turn (frog-leg) whose knee, thigh and shin volumes clear every rung and rail, starting from the turn the leg had. |
| `TraversalPoseModifier` | Uses the planner for the pole; keeps the previous turn and changes it at a limited rate so a knee glides. Reports `knee_overlap`. |
| `LadderPose`, `LadderClimb`, `TraversalPoseInput`, `CharacterRig` | Typed plumbing for geometry, body, reachability. |
| Docs | `docs/animation.md`: new "Ladders (issue #55)" section, limitations updated. |

Not changed: tactical movement, AP, occupancy, routes, replay, presentation speeds, the contact claim contract and cleanup, the hand-contact writer, the other stages.

## 4. Measurements

All from the **final skeleton pose** (sampled at `skeleton_updated`), 4 m ladder, 4 cm steps in `ladder_climb_test` (1 cm steps and full weight in the probe). Volumes are approximate capsules with proportional radii (generous by design; see Limitations).

Before (old code, old 0.33 m ladder, probe at 2 cm steps, all samples with the pose over half applied; hand reach judged at 97% of the arm):

| | hands beyond reach | wrist miss > 3 cm (worst) | foot miss > 3 cm (worst) | worst overlap knee / shin / thigh |
|---|---|---|---|---|
| MIRA up | 18 / 278 (excess 5 cm) | 3 (3.6 cm) | 1 (3.1 cm) | 2.0 / 7.9 / 10.2 cm |
| MIRA down | 39 / 278 | 3 (3.8 cm) | 59 (14.9 cm) | 2.0 / 8.1 / 10.1 cm |
| Small MIRA up | 158 / 278 (excess 15.6 cm) | 123 (14.7 cm) | 54 (29.1 cm) | 6.7 / 6.1 / 7.9 cm |
| Small MIRA down | 111 / 278 | 74 (13.3 cm) | 171 (41.1 cm) | 3.9 / 3.2 / 5.9 cm |

After (`ladder_climb_test`, pose fully applied, armed and unarmed, up and down; hand reach judged at 100% of the arm):

| | hands within reach | wrist worst | planted ankle worst | worst overlap knee / shin / thigh | torso / arms |
|---|---|---|---|---|---|
| MIRA up | 124 / 124 | 0.0 cm | 0.2 cm | 1.8 / 1.7 / 3.3 cm | 0 |
| MIRA down | 124 / 124 | 0.0 cm | 1.5 cm | 0.9 / 1.6 / 2.4 cm | 0 |
| Small MIRA up | 135 / 138 armed, 133 / 138 unarmed (96 to 98%) | 2.5 cm | 0.2 cm | 0.0 / 0.6 / 1.1 cm | 0 |
| Small MIRA down | 135 / 138 armed, 133 / 138 unarmed | 2.3 cm | 0.3 cm | 0.0 / 0.5 / 1.0 cm | 0 |

The criteria of the issue: at least 95% of planted hands within reach on both bodies, armed and unarmed (met: 96 to 100%); wrist within 3 cm (met: worst 2.5 cm); unreachable contacts reported (`hand_reachable`, `foot_reachable`, with negative controls); legs clear (met to 3.5 cm of modelled overlap, from up to 10 cm; see Limitations). Cadence: MIRA's hands step two rungs, Small MIRA's one; both bodies' feet step one rung.

## 5. Regression tests and negative controls

* `ladder_geometry_test` (new, FAST and smoke): the definition, the volume test with controls (a leg across a rung overlaps, a thin limb through a gap does not, a knee behind the plane is clear, a limb on a rail overlaps, the floor level shifts the volume), the authored 4 m and 3 m scenes against the definition, and a scan that no authored scene stretches a ladder (with a synthetic stretched control).
* `traversal_solver_test` (rewritten for the new contract, same invariants): purity under reverse evaluation, continuity at 1 cm, planted contacts exactly on rungs, limb steps, mount/dismount weights, descent, both bodies, the plan follows the body, unreachable contacts reported (a body with 3 cm arms is reported unreachable for over 90% of samples; short legs likewise).
* `ladder_climb_test` (new, FAST): the table above as assertions on both rigs, armed and unarmed, up and down, plus knees not popping.
* `hand_contact_test` (unchanged, 58 checks): the Task 11 contact ownership, interruption, repeated entry, cleanup and equipment restoration still pass.
* **Mutation checks.** Restoring the old knee pole fails `ladder_climb_test` on all 8 bodies/directions with overlaps of 3.7 to 10.6 cm (verified, then restored). Reverting to the old geometry reproduces the "before" table above.
* Catalog: both new tests are listed; the `check` tier (283 scripts) passes; `changed -Since 5034527` selected the ladder tests and, through the support-file reference scan, the tests that use the new support files.

## 6. Replay and trace comparisons

* **Pose trace** (39 scenarios, `--fixed-fps 60`) against the approved trace: **35 identical**; the 4 ladder scenarios (`ladder`, `ladder_down`, `ladder_interrupted`, `ladder_over_stairs`) differ, as intended (bone positions up to 0.41 m, hand and foot targets moved); crouch, kneel, yaw, passenger, world position, phase and IK flags are unchanged in them. The 0.064 degree rotation floor appears between the approved Task 12 and Task 14 traces too. **The approved baseline is not replaced**; the new trace is `scratchpad/l55_pose.json` (not committed) and the visual evidence below supports the change.
* **Route trace**: 853 routes, **zero discrete differences, zero float difference**. Gameplay is untouched.
* `traversal_ladder_gameplay_test`, `traversal_loaded_carrier_test`, `current_mission_replay_matrix_test`, `traversal_state_test`, `traversal_rig_test` pass.

## 7. Real-rendered evidence

All unstretched (see "Capture correction"). Rows: MIRA side, front, three-quarter, then Small MIRA side, front, three-quarter. In `docs/claude/images/ladder55/`:

* `baseline-up-unarmed.png`: the **old** code at 1.1 m and 2.0 m. Knees and thighs pass through the rungs in the front and three-quarter views, on both bodies.
* `after-up-unarmed.png`, `after-up-armed.png`: climbing, four limb phases. Legs behind the rungs in a frog-leg stance, feet on rungs, hands on rungs, rifle slung as before.
* `after-down-unarmed.png`, `after-mount-unarmed.png`, `after-topout-unarmed.png`.

What the renders show and do not show: the legs no longer cross the bars; the stance is wide (a knee raised on a 0.25 m pitch has nowhere else to go); close-ups at the worst modelled grazes were not taken, so a 3 cm graze of the real armor is not excluded by eye. Mount and descent were looked at at the sheet scale only.

## 8. Performance

`ladder_pose` costs 30 microseconds. The knee planner makes the per-frame cost about **0.5 ms for MIRA and 0.25 ms for Small MIRA** (two legs, with the previous turn as the starting point), only while a character is on a ladder; MIRA is higher because its raised knee often has no clear turn and the search ends at the last candidate. Idle characters pay nothing. No budget is invented or gated.

## 9. Known limitations

* **A raised MIRA knee can still graze a rung by up to about 3.4 cm** in the approximate volumes (it was 10 cm). It is geometry: a 0.25 m pitch, a hip-to-ankle distance of about 0.34 m at the high foot and a pelvis that cannot hang farther back without losing the hands.
* **Top-out is abrupt.** The hands let go about 0.9 m below the deck because the body hangs far enough back that the deck is out of reach, and the climber stands out of a deep squat with the arms down. A pelvis that moves in toward the deck during the dismount would fix it; not done (a new body-motion rule, outside a stabilization).
* The planted-hand criterion is judged at 100% of the arm's length and met at 96 to 100%; some hand targets are near full stretch.
* A **frog-leg stance** is the visible price of keeping knees off the rungs.
* Presentation speeds are unchanged, so the one-rung steps of feet (and of Small MIRA's hands) are quicker than MIRA's two-rung hand steps.
* A loaded carrier still climbs with placeholder clips (unchanged, documented).
* `LEAN_SHOULDER_GAIN` (0.68) and `HAND_REACH_FRACTION` are calibrated on the two shipped bodies; a third humanoid is measured by `ladder_climb_test` through the same rig, which is the point of the test.
* The older `*_capture` scripts that resize a viewport into a tile of another aspect (17 do) stretch the image; only the two ladder captures were corrected.

## 10. Capture correction

While reviewing, the owner noticed the evidence images were stretched. Cause: the capture scripts resize the 16:9 viewport directly into a portrait tile. `ladder_review_capture.gd` and `contact_ladder_capture.gd` now crop to the tile's aspect before scaling. The numbers above are not affected (they come from joints). Earlier sheets (Task 11 ladder, Task 14 images made with such tiles) should be judged for proportions with caution.

## 11. Audit baseline

The independent Task 14 audit stays reproducible against `5034527`. A local tag `task14-audit-baseline` marks it. To audit without contamination, check it out in a separate worktree: `git worktree add ../fusefire-audit-task14 task14-audit-baseline`. This work is committed on main after that commit; no history is rewritten.

## 12. Full-suite result

`check` OK (283 scripts, 35 explicit-only, FAST and SMOKE lists complete). `smoke` 26 PASS. `fast -Subsystem animation` 29 PASS. `changed -Since 5034527` 82 PASS. **`full`: PASS=249, FAIL=0, SKIP=35 (explicit-only captures and batches, not run), 2754 s**, logs in `artifacts/test-results/20261122-225236-full`. Not run: the explicit-only render captures other than the ladder sheets above, and any hand-driven playtest of the workbench or sandbox. Headless success does not establish visual correctness; the visual judgement above is from the sheets only.
