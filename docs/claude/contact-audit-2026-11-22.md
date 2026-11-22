# Task 11 — environmental contact and traversal infrastructure (audit and report)

Tracking issue: Melo9002/fusefire-proving-grounds#54. Written by Claude, 2026-11-22. Status: implemented, verified, committed and pushed as `d7a4c6f`; owner review accepted the `HandContact` consolidation. A follow-up corrected the stair surface test oracle (section 10) and tracked the ladder reach limit as #55.

## 1. Baseline and repository state

* Branch `main`, HEAD `0f4ee0d` (Task 10 hardening), identical to `origin/main` at the start.
* Unrelated working-tree changes, verified rather than assumed: six `art/environments/kenney/*/colormap.png.import` modifications and two untracked `docs/claude/images/test-*.svg.import` files. They are untouched and unstaged.
* Baselines used: the 39-scenario pose trace (`tools/quality/pose_trace.gd`, approved baseline from before Task 10) and the 853-route trace (`tools/quality/route_trace.gd`, approved baseline from Task 07); the hand-contact diagnostics baseline `hand-contact-baseline-2026-11-18.json` is exercised by `unit_visual_hand_contact_diagnostics_test`.

## 2. Contact ownership and data flow (what the code does today)

Everything below is implemented unless marked.

| Question | Stairs | Ladder | Weapon grip | Rescue carry | Relaxed (unarmed) hang |
|---|---|---|---|---|---|
| Environmental geometry | `StairModel` (from the map's stair run; `StairProfile` for the body) | `TraversalProfile` rung layout (first rung, spacing, plane; **authored, not read from the map**) | the weapon's `handling` profile | `RescuePassenger.contact_frame` (the passenger's body) | the body's own anatomy |
| Who decides legality | Tactical layer (route, cells, AP). Never the rig. | Tactical layer | Presenter readiness (state, not geometry) | Tactical rescue interaction / presenter holds | n/a |
| Who plans contacts and phases | `StairFootPlanner` (pure functions: holds, stance/swing, riser clearance, pelvis) | `TraversalSolver.ladder_pose` (pure: rung index, contralateral parity, windows, deck handhold) | `CharacterRig.apply_weapon_targets` (stock pocket, grips) | `CharacterRig.apply_carry_targets` | `apply_relaxed_hand_targets` |
| Coordinate frame | planner output in **world**; typed in `StairPose` | solver output in the **character root's frame**; typed in `LadderPose` | rig-local markers | world, from the passenger | world |
| Who owns / applies the IK target | `TraversalPoseModifier` writes the leg IK foot targets; `TraversalFootModifier` the foot rotation | rig writes the hand targets (`apply_traversal_hand_targets`); `TraversalPoseModifier` the legs | rig (`apply_weapon_targets`) | rig | rig |
| Priority and blending | Modifier order (`PoseOwnership.STAGE_ORDER`): stairs/ladder legs after Locomotion and CoverCrouch, before WeaponPose; weight = stair weight | Ladder hands are placed after the weapon targets in the same WeaponPose pass, by the hand weight | the baseline | the carry pass returns before the weapon targets | placed first, then overridden by ladder/carry claims |
| Begin / persist / release / interrupt | `begin_stairs` / `set_stair_progress` / `end_stairs` (weight fades by `weight_at`) | `begin_traversal` / `set_traversal_progress` / `end_traversal` | readiness and aim (persistent) | `begin_pickup` / `end_carry`, handles from Task 08/10 | persistent |
| Invalid or unreachable | A foot that cannot reach is limited (`limit_ankle`); a pelvis that cannot is clamped (`pelvis_ok`); stairs are refused while carrying | The arm/leg IK reaches as far as the limb allows and stops short. **Not detected or reported** (see section 8) | The support clavicle adds reach up to a limit and reports a deficit | n/a | `_clear_of_thigh` keeps the hand off the leg |

Prototypes and not-implemented: the vault (`vault_pose`) exists in the solver but is not integrated; ordinary floor foot planting does not exist; the exploration playground uses the same rig calls (`begin_stairs`, `begin_climb`) and is experimental; the workbench drives the same calls for diagnostics.

Competing owners of the **hands** (the only body part with more than one producer) and how they were resolved before and after this task:

| Situation | Resolution | Task 11 |
|---|---|---|
| Weapon grip vs ladder rung | the ladder claims the hands while the hands hold the rungs; the rifle is slung | unchanged; **a stale ladder weight after the hands let go is now impossible** |
| Carried passenger vs weapon grip | carry returns early; the weapon targets are not placed | unchanged |
| Relaxed hand vs gesture | the gesture raises the unarmed right hand through the relaxed target (Task 10) | unchanged |
| Foot/gait/pelvis vs crouch | stair weight suspends the crouch; `PoseOwnership.OVERLAPS` | unchanged |

## 3. Duplication and architectural findings

1. **Three producers wrote the same data three ways.** The ladder, the carry and the relaxed hang each converted a world-space contact into the wrist target and the grip modifier's `contact_weight`, `contact_forward`, `contact_normal` and `curl`. They used **three different left/right conventions** (the ladder's `[left, right]`, the carry's grip index and shoulder index table, the relaxed hang's `1 - side`), and the skeleton-space conversion was written out three times.
2. **A demonstrated cleanup defect (reproduced).** The ladder released the grip's contact only in `end_traversal`. When the hands let go at the top of a ladder while the traversal stayed active (`hand_weight` reaches 0 before the body is off), the last ladder weight remained on the grip (0.156 in the probe) while the rifle was back in the hand. `HandGripModifier._orient_hands` lets any contact weight above 0.001 **replace** the weapon orientation, so the rifle hand was turned 16 % toward the ladder and was no longer gripping the rifle until `end_traversal`.
3. Release was scattered across three places (`end_traversal`, `end_carry`, the ladder's own writes).
4. Stairs and ladders pass solved data to modifiers through the **same** `TraversalPoseInput` (stairs world, ladder character space). That is intentional and documented; it is not duplication that a shared type would simplify.
5. No other genuine duplication was found worth sharing: the stair and ladder planners have different geometry, timing and constraints.

## 4. Alternatives considered

* **A. Retain everything.** Rejected for the hands: it leaves the demonstrated stale-weight defect and three conventions.
* **B. A small helper for hand writes.** Chosen shape, but as a typed value plus one writer method.
* **C. A shared contact representation across feet, hands and equipment.** Rejected: feet are planned and applied by different modifiers with different frames; a universal contact type would blur stance/swing and rung windows, which belong to their families. No scene-wide registry, scheduler, solver factory or universal IK was introduced.

## 5. Consolidation made

`HandContact` (`presentation/characters/rig/hand_contact.gd`): one hand's contact for this pass — hand (the grip modifier's convention, one only), world point, world finger direction, world palm normal, orientation weight and optional closure.

`CharacterRig.claim_hand_contact(contact)`: the **single writer**. It moves the wrist target, converts the directions into skeleton space and fills the grip modifier's slot.

`CharacterRig.release_hand_contacts()`: the **single release**. It runs at the start of every pass that places the hands (`apply_weapon_targets`) and in `end_traversal` / `end_carry`. A hand that nobody claims in a pass is therefore the weapon's (or the animation's) again; no contact weight can outlive its producer. Precedence is unchanged and is still the existing one: the last claim of a pass wins, and carry, ladder and relaxed hang are placed in the existing modifier-pass order.

Consumers (three real ones): the ladder's rung hands, the carried passenger's wrist/thigh contacts (rescue), and the unarmed relaxed hang. The weapon grip is **not** a claim; it is what remains when no contact claims the hand.

## 6. Deliberately left specialised

`StairFootPlanner`/`StairPose`/`TraversalFootModifier` (foot placement, stance/swing, pelvis, foot rotation), `TraversalSolver`/`LadderPose` (rung indexing, contralateral sequencing, windows, mount/dismount, deck handhold, weapon stowage), the weapon pose and grip (readiness, stock pocket, support reach), and the rescue interaction (contact frames, lift timeline, carrier posture). Each still plans in its own frame and only the hand's final application is shared.

## 7. Public contract changes

None removed. Added: `HandContact`, `CharacterRig.claim_hand_contact`, `CharacterRig.release_hand_contacts`. Removed: the private `CharacterRig._hang_hand` (replaced by a claim; no other user). `PoseTargetPlacer`, `TraversalPoseInput`, `ActionHandle` outcomes and the presenter/hold contracts of Task 10 are untouched. `PoseOwnership` needed no change (the same stages write the same roles).

## 8. Tactical authority, replay and traces

* No tactical code was touched (movement legality, routes, AP, occupancy, reaction checkpoints, scheduling, replay recording, presentation speeds). The route trace is **identical**: 853 routes against 853, 0 discrete differences, 0.0 float difference.
* Pose trace (39 scenarios) against the approved baseline: **37 scenarios identical** (bone positions 0.000, rotations 0.064° = the noise floor of the baseline). **Two differ, and only because of the defect fix**: `ladder` (frames 144–159) and `ladder_down` (frames 158–159). The differing bones are the six hand/finger bones (`LeftHand`, `RightHand`, thumb and index base) plus the weapon (2.7 cm at most, as the rifle returns from the sling to a hand that now grips it). No other bone or target changes. `ladder_interrupted` and `ladder_over_stairs` are identical. This is the intended correction, not noise; a new reference trace was recorded.

## 9. Both humanoids (MIRA and Small MIRA), armed and unarmed

`tests/hand_contact_test.gd` (new, 58 checks, all four combinations). Findings worth owner attention:

* **Small MIRA's ladder is out of reach for a large share of the climb.** Measured with the wrist sampled at `skeleton_updated`: wherever the arm can reach the contact, the wrist is on it (worst miss 0.000 m on both bodies). But 51 of 88 sampled hand contacts on Small MIRA (and 7 of 88 on MIRA) are farther from the shoulder than the arm is long; the arm stretches toward the rung and stops short, by up to ~0.12–0.15 m. Cause: `TraversalProfile` holds MIRA-scale lengths (hips height, reach windows) and the rung spacing (0.33 m, environment) leaves a 0.66 m window per hand, which a 0.32 m arm cannot span. I tried scaling the body-relative profile lengths by `body_ratio()` (as the stair profile already does): it reduced the worst miss from 0.149 to 0.119 m only, because the remaining problem is the rung-window sequencing, which belongs to the ladder family. The attempt was **reverted**. This is a pre-existing limitation (this task did not make it worse: the Small MIRA ladder trace is not part of the approved pose baseline, and the contact writer is bit-identical for it). Tracked as Melo9002/fusefire-proving-grounds#55 (acceptance criteria there) for the framework stabilization milestone: it needs ladder windows derived from the arm's length, with a rendered review.
* Stairs use measured anatomy and scale to Small MIRA already; nothing changed there.

## 10. Tests, negative controls

* New: `hand_contact_test` (writer indexing and skeleton conversion with a turned skeleton, release of unclaimed hands, the ladder's final-pose hand accuracy, no stale weight after the hands let go, interruption and three repeated entries/exits, unarmed return to the hang).
* Negative controls, each by temporarily reverting one invariant and watching `hand_contact_test` fail: (1) no release at the start of the pass → the stale-weight and release checks fail on both rigs (stale 0.1563); (2) left/right slot indices swapped → the left/right writer checks fail; (3) no skeleton-space conversion → the conversion check fails (it only fails because the check turns the skeleton; an un-turned skeleton cannot detect it, which is why that check exists); (4) the relaxed hang claimed with weight 0 → the unarmed hang and interruption checks fail; (5) the wrist target not written → the writer and ladder checks fail.
* Existing contracts re-run and unchanged: `traversal_rig_test`, `unarmed_humanoid_test`, `traversal_loaded_carrier_test`, `unit_visual_hand_contact_diagnostics_test`, `rescue_presentation_handle_test`, `modifier_boundary_test`, `pose_ownership_test`, `unarmed_hand_clearance_test`.
* **A pre-existing failure was found and fixed in the contract**: `traversal_surface_alignment_test` failed on the unmodified HEAD (planted sole-to-tread 0.0300 m against a 0.02 m limit). Diagnosis: an obsolete contract, not a regression: the stair work in 76d4150 deliberately raises a planted heel by up to `StairProfile.heel_lift` (0.03 m) so the toes stop sinking into the treads, and the test still measured the raw ankle. The first correction derived the lift from the ankle it was validating, so an unplanned vertical offset could hide inside the lift (owner review). It now takes the expected foot from an independent `StairFootPlanner.contact_foot` call for the same place, root, facing and speed; the 0.02 m sole tolerance is unchanged, the planner's lift is bounded by `heel_lift`, and every planted ankle must equal the planner's own height within 3 mm. Negative controls: adding +1.0, +1.5 and -1.5 cm to planted ankles in `set_stair_progress` makes the new check fail on both stair legs (worst difference 0.0100, 0.0150, 0.0150 m); the earlier assertion alone would have passed them. Stair behaviour was not changed.
* Gates run (all PASS): strict changed-file tier 44/44 (before the surface-test edit; the edited test and `hand_contact_test` re-run separately), animation FAST 26/26, 18 named traversal/stair/rescue tests (17 pass, the one failure being the pre-existing surface-alignment contract above, now passing), `check` (catalog complete, 274 entries), route trace identical, pose trace as in section 8.
* Rendered evidence: `docs/claude/images/task11/ladder-contact-sheet.png` (`tests/contact_ladder_capture.gd`, explicit-only): MIRA (top row) and Small MIRA (bottom row), armed, six frames � mid-climb, reaching, hands letting go, just after (the rifle's grip owns the hands), the top, and a climb interrupted mid-way. Reviewed by eye: MIRA's hands are on the rungs and the rifle is gripped after release; Small MIRA's arms are stretched high toward the rungs (the reach limit of section 9, visible); the interrupted frame returns to the ordinary standing pose. The render is an evidence sheet from a free-standing test ladder, not the Tactical Test Range.

## 11. Remaining limitations and deferred work

* Small MIRA ladder reach (section 9) — deferred, measured.
* Ladder rung layout is authored in `TraversalProfile`, not read from the map (pre-existing; the profile says so).
* Unreachable contacts are not reported by the ladder (stairs report `pelvis_ok`); a shared "reachable" diagnostic would be worth adding with the Small MIRA fix.
* Loaded ladder traversal remains unsupported, exactly as before.
* Feet remain specialised: ordinary floor foot planting, the vault and mantling stay out of scope.
* The pose trace does not include Small MIRA or armed-ladder top-out with a render; rendered review of the Small MIRA ladder belongs with the deferred fix.

## 12. Changed files

Modified: `presentation/characters/rig/character_rig.gd`, `docs/animation.md`, `tests/catalog.json`, `tests/traversal_surface_alignment_test.gd`. New: `presentation/characters/rig/hand_contact.gd` (+ `.uid`), `tests/hand_contact_test.gd` (+ `.uid`), `tests/contact_ladder_capture.gd` (+ `.uid`), `docs/claude/contact-audit-2026-11-22.md`, `docs/claude/images/task11/ladder-contact-sheet.png`. Not staged and untouched: the six Kenney `.import` files and the two `docs/claude/images/test-*.svg.import` files. Committed in `d7a4c6f`.
