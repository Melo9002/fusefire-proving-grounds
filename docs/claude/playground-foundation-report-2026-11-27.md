# Exploration Playground foundation and traversal refinement: engineering report (2026-11-27)

Branch `review/claude-playground`. Baseline `e6826fd` (`main` after PR #106, the tactical carry/ladder adoption; PR #105 is in it). Final commit: the head of this branch (see the pull request). **Not merged, not owner-approved.**

Status by level: **implemented** yes, with the gaps listed in section 10; **automated-tested** yes (section 8); **rendered-tested** stills only, from the playground's own camera (section 7), no motion recording and no run by a person; **owner-approved** no; **merged** no.

## 1. Baseline and what was already there

Inspected before changing anything: `AGENTS.md`, `main`'s history (PR #105 and #106 merged; my own last documentation commit for PR #105 had not reached `main`, so it is carried here as `dc088eb`), the playground source (`exploration_playground.gd` and its seven component scripts), `ExplorationCharacterHost`, `CharacterRig`'s traversal path (`TraversalPoseInput`, `TraversalPoseModifier`, `TraversalFootModifier`, `StairFootPlanner`), and the existing tests. Reused as they were: `PassengerDefinition` / `PassengerFit` / `LoadedLadderCarry` (no second carry solver), `ActionHandle` for lift and release outcomes, the shared stair planner and ladder presentation, the playground's component layout (combat, cover, traversal, carry, health, props). Not reused: the single `BodyProp` and `passenger_id` of `PlaygroundCarry` (replaced, below).

Important finding about the premise: the Playground could already mount a **loaded** ladder (my own PR #105 did it, with E taking precedence over put-down at the foot), so "loaded ladder accessibility" was not missing, but the E-versus-put-down ambiguity was still structurally possible: nothing validated where a body was put down.

## 2. Owner-reported defects, reproduced

| Report | Reproduction | Root cause |
|---|---|---|
| Body put down inside solid geometry | Carry a body to the ladder foot facing the tower and put it down (probe). The released body's bones extend to z 15.68, the tower face is z 15.64; in the test 5 bones were inside solids until the check existed. | The shared release always lowers the body 0.95 m ahead of the carrier, the released `RescuePassenger` has no collider, and nothing asked whether there was room or a floor. Ladder mounting precedence was a different problem: it only decided whether E put the body down, not where. |
| One casualty only | Source. | `PlaygroundCarry` held one `prop` and one `passenger_id`. |
| Ladder mounting by E | Source and old tests. | Mount zone was a metre either side and E was overloaded. |
| Feet float or sink on the ramp | Ramp probe (section 6). Standing on the ramp the supporting ankle was 2.0 cm high; walking across or diagonally it sank 3.7 to 5.0 cm below its height on flat floor. | Ordinary locomotion has no ground contact: the clip assumes flat floor under the root; the capsule also rests about 2 cm above the slope, which is a constant float. |
| Discontinuity entering stairs | Stair probe. A run onto the stairs: pelvis second difference 118 mm, ankle 352 mm in one frame at the first tread. | The stair pose takes over by distance (about 0.6 m) while the body is still at 4.6 m/s from a run; the planner is a pure function of position and speed and has no time to blend. |
| Foot snap on stopping or starting on the stairs | Stair probe: after releasing the key the swinging ankle moves 0.28 m in three frames; starting again can hop a whole tread. | The gather onto one tread blends over a speed band 0.3 m/s wide (`settle_speed_low` to `_high`), which a body decelerating at 9 m/s squared crosses in about 0.03 s. **Not fixed**, see section 10. |

## 3. What was built

* **Casualties** (`playground_casualty.gd`, `playground_carry.gd`): each physical body has a world id and a model id (`PlaygroundCasualty`: `id`, `character_id`, `definition`, `state` GROUNDED / LIFTING / CARRIED / RELEASING, `home`). Two default casualties (Regular `mira_0`, Small `small_mira_0`) lie at the red casualty station from the start, 3 m apart, defined as data (`casualty_specs` in `playground_props.gd`). The controlled character is chosen independently and changes neither. Pickup hides the ground body and keeps it; it is freed only when the lift COMPLETED (or SKIPPED, the final state), and restored if the lift is cancelled or interrupted. Release adopts the rig's left-behind body into the world as the same casualty, or recreates it at the planned spot if the rig let go without leaving one. Defeat while carrying lays the body on the floor beside the carrier (`drop_carried_now`); reset and respawn never lose a body. An optional **extra casualty** (menu) adds a third body of either model.
* **One interaction decision** (`playground_interaction.gd`, `decide_interaction()` in the controller): the prompt shows the decision's text and E runs the decision's action. Target policy: the nearest lying body in reach (2 m), of two at nearly the same distance the one more ahead of the carrier, then first listed. Prompts: "Press E to pick up MIRA" / "... Small MIRA", "Press E to put down <name>", "No room to put <name> down here", "Walk toward the ladder to climb", "W / S: climb", "Press E to inspect the chair".
* **Put-down placement** (`playground_placement.gd`): before the put-down starts, the floor under the centre and four corners of the lying footprint must be the carrier's own floor (within 7 cm, not a slope) and a box query of the footprint must touch no solid. Directions are tried in a fixed order (ahead, then 45, 90, 135 degrees either side, then behind); the carrier turns to the first that fits and the shared release does the rest. With none, E is refused, the body stays on the carrier and nothing starts. Nothing is teleported and no collision is disabled.
* **Walk-at-the-ladder mounting** (`PlaygroundTraversal.update_approach`): a zone the width of the rails, a little behind the foot to just short of the rungs, and at the head from just inside the edge to 0.45 m beyond the spot the climb starts from; walking within about 37 degrees of straight at the ladder for 0.25 s mounts; standing, walking along or past it, or walking away does not. After a dismount the ladder stays disarmed until the key is released or she leaves the zone, plus 0.8 s. W and S climb, releasing stops her on the rungs, as before. The loaded transfer gate (`loaded_ladder_ready`) is untouched. E no longer mounts: the one decision keeps E for pickup, put-down and inspect, so the earlier ambiguity cannot recur. A facing test was tried and removed: it made turning at the platform's edge the dangerous part.
* **Ramp foot placement** (`presentation/characters/rig/ground_support.gd`, `TraversalPoseInput.Mode.GROUND`, modifier branches, `ExplorationCharacterHost` sampler): in the same pass as the animation, each animated ankle is shifted by (ground under it minus the root's height), the swing keeps its arc; the pelvis follows the lower foot; a planted foot is turned to the ground's normal. The host answers the rig's ground query from its own physics world (`follow_ground`, default on). On flat ground the shifts are under 4 mm and the weight stays zero, so the animation and the leg IK are untouched (tested). It is a general foundation for uneven ground, not a ramp special case. The tactical adapter sets no sampler, so tactical presentation is unchanged.
* **Stairs**: held to the stair pace for 2 m before either end (`approaching_stairs`, controller). The existing stair behavior (sideways, diagonal, reversal, crouch, jump-off) is untouched and covered by the unchanged `exploration_actions_test` and the stair tests.
* **Camera, layout, menu**: zoom out to 9 m; H toggles a clean view (no help text, state line or signs); station signs (fixed screen size) and a casualty pad; menu: extra casualty picker, Reset casualties, Reset character, Start area, ladder foot and top (unchanged), Resume, Back to Match Setup.

## 4. Casualty identity and ownership

World body identity (`PlaygroundCasualty.id`) and model identity (`character_id`, from `PassengerDefinition`) are separate, so two casualties of one model are two bodies (tested). The passenger keeps its definition from the floor (`node.definition`), onto the carrier (`rig.carry_passenger.definition`) and back (the released node's definition); scale is checked at each stage. Only `PassengerDefinition.for_character` resolves a model; no character name appears in shared code (`humanoid_portability_test` passes).

## 5. Ladder mounting policy, all four combinations

The unchanged loaded-ladder matrix runs through the playground's real input for Regular/Regular, Regular/Small, Small/Regular and Small/Small (`loaded_ladder_playground_test`: pickup from the station, walk at the ladder from the foot, climb with the passenger transfer gate honoured, top-out, ordinary carry restored, walk at the ladder from the platform, descent, bottom restore, put-down): 100 checks, 0 failures.

## 6. Measurements (final pose at `skeleton_updated`, bones not meshes)

**Ramp** (`tools/quality/ramp_foot_probe.gd`; clearance of the lower ankle over the ground under it, cm; the walk on flat floor is the reference because an ankle rises and falls through a stride; 232 to 321 frames per row; regenerate to see all rows):

| Case | Regular, off: p5 / p50 | Regular, on: p5 / p50 | Small, off | Small, on |
|---|---|---|---|---|
| flat walk (reference) | +2.5 / +2.9 | +2.3 / +2.9 | +1.8 / +2.6 | +1.8 / +2.6 |
| standing on the ramp | +2.0 (floats) | 0.0 | +2.0 | 0.0 |
| uphill | -1.1 / +1.4 | +1.0 / +3.0 | 0.0 / +2.2 | +1.1 / +2.5 |
| downhill | +0.1 / +3.2 | +2.4 / +3.1 | +0.6 / +2.8 | +1.8 / +2.6 |
| across the slope | -2.3 / +1.8 | +1.2 / +3.1 | -1.2 / +1.5 | +1.3 / +2.6 |
| diagonal | -2.5 / +0.6 | +0.8 / +2.8 | -1.4 / +1.2 | +0.9 / +2.5 |

Off, the deepest ankle is up to 5.0 cm below its flat-walk height (Regular, diagonal); on, the p5 is within 1.7 cm of the flat walk's worst case for Regular (uphill, diagonal) and within 0.9 cm for Small, and the usual height (p50) matches the flat walk to 0.3 cm or better in every row except Regular uphill, 0.1 cm high. The remaining 1.5 cm at the deepest frames is not explained: it appears at heel strike on the uphill foot and I did not chase it. **Not measured**: foot sliding, foot orientation error, pelvis displacement, mesh intersection.

**Stairs** (`tools/quality/stair_transition_probe.gd`; second difference of an ankle or the pelvis per frame, mm; frame-rate dependent, so only compare rows from one session): a run onto the stairs, before this work, pelvis 118 and ankle 352 at the first tread; after the approach pace limit, 18.3 and 15.5 over 42 hand-over frames. Walking up or down: hand-over frames show no spike beyond the rhythm inside the stairs (pelvis 18 to 20, ankle 18 to 24, unchanged). The control inside `playground_terrain_test` switches the limit off and the pop returns.

## 7. Rendered observations

`docs/claude/images/playground/casualties.png` and `ramp_and_stairs.png` (stills from the playground camera at 640 by 400, captured by `tests/playground_foundation_capture.gd`): both casualties lie at the red station on entering, each carrier at each casualty shows the right prompt, the Small carrier carries the Regular casualty, the put-down beside the station leaves the other body lying, and the body put down at the ladder foot lies beside the carrier clear of the tower; signs and the clean view read. **At this size the stills cannot show feet on the ramp**: ramp "off" and "on" look alike, so the ramp result rests on the numbers above and on no inspection by eye. No motion was viewed, by me or anyone. Not exercised through the Match Setup menu this session (the playground was instantiated directly by the tests and captures); the menu path itself is unchanged and `exploration_playground_test` still opens it from Match Setup.

## 8. Verification

New: `playground_casualties_test` 90 checks, `playground_terrain_test` 30 (both pass headless and windowed). Updated for intentionally superseded contracts (single casualty, E mount, prompt wording): `exploration_actions_test` 57, `exploration_playground_test` 49, `loaded_ladder_playground_test` 100, all pass; no assertion was weakened (the old stair and ladder checks are unchanged). Negative controls: the shared release alone puts the body into the tower (bones inside a solid); the ramp stance without the foot placement floats 2 cm; the stair run without the pace limit pops.

Ironclad (my branch): catalog check green (320 scripts); smoke GREEN 27/27; subsystem animation 94 passed, 1 failed; rescue GREEN 19/19; movement 54 passed, 1 failed. **The one failure in both is `ladder_landing_test`, issue #64**, four descents at 119 to 122 mm; on the unmodified baseline `e6826fd` it fails the same four (122 mm) in equivalent conditions, so #64 is **unchanged**. `humanoid_portability_test` failed once mid-work (a stair slew I tried made the toe cut a tread at rest); the slew was removed and it passes (69/69). Not run: the other subsystem tiers, the full tier, replay and tactical suites beyond what movement/rescue/animation include.

## 9. Performance

The foot placement costs two ray queries per frame and a few vector operations, only while the rig has a sampler; it was not timed (the headless frame pacing cannot resolve it, as in #79). The pickup/release code adds no per-frame scene searches (casualties are a small array). The fit cache of `PassengerFit` is reused. One cost to know: `target()` is evaluated every frame for the prompt, over the casualty list (a handful).

## 10. Remaining defects and limits, honestly

* **Stopping or starting on the stairs still snaps a foot** (0.28 m in three frames, or a one-tread hop), the root cause is in section 2. A host-side slew of the speed given to the planner lengthened the gather but exposed the planner's gait-pose toe intrusion (`humanoid_portability_test`), so it was removed. The right fix is in the planner (a gather path with swing clearance), which is a shared-code task on its own.
* Loaded movement on stairs and ramps: the rig refuses stairs while loaded (existing), so a loaded carrier cannot take the stairs; the ramp, being collider and ground support, works loaded but that combination was not measured or looked at.
* Ramp: 1.5 cm unexplained at the deepest uphill frames; foot orientation and mesh contact unmeasured.
* The extra-casualty picker never offers a model that is not in `CHARACTER_VISUALS`; a third model needs an exploration visual scene first.
* Put-down tries eight directions on the carrier's own floor level only; it will not step to a different level.
* The default station layout is an owner-facing guess; positions were not tuned by hand-play.
* Tests drive input through `Input.parse_input_event` and the controller's public calls; no one has played this at normal speed.
* Unrelated, unchanged: #64, #68 (pickup and release hand targets), the ladder-landing chest steps, the passenger pose polish from the PR #105 report.

## 11. How to use and extend

Open Match Setup, Settings, Exploration. WASD, Shift, mouse; E at a casualty (the prompt names it); walk at the ladder; **H** clean view; **Esc** menu. Add a default casualty: one entry in `casualty_specs` (`playground_props.gd`). Add a model: its exploration visual in `CHARACTER_VISUALS`, its label in `CHARACTER_LABELS`. Add a fixture the feet should follow: any collider; the host's sampler needs nothing else. Tools: `tools/quality/ramp_foot_probe.gd`, `stair_transition_probe.gd`, `tests/playground_foundation_capture.gd`.

## 12. Recommendations (not done)

1. Owner plays the station, the ladder from both ends loaded and unloaded, the ramp, and a run at the stairs, and judges the motion.
2. A dedicated task for the stair gather (planner-level swing clearance), with the `humanoid_portability_test` rest contract as its gate.
3. Decide whether loaded stairs should exist before anyone designs animation for them.
4. If the ramp's 1.5 cm matters, measure heel strike on the mesh first.
