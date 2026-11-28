# Exploration Playground: PR #107 refinement and acceptance pass (2026-11-28)

Continues [playground-foundation-report-2026-11-27.md](playground-foundation-report-2026-11-27.md) on `review/claude-playground` (PR #107). Not merged. Nothing here has been played by a person: the sessions below were driven by automated input, and what I looked at is sequential frames and measurements, not motion.

State of each item uses separate words: **implemented**, **automated-tested**, **rendered** (frames I looked at), **owner-approved** (nothing is), **merged** (no).

## 1. What changed in this pass

| Area | Change | Status |
|---|---|---|
| Stair stop/start foot snap | A foot target may not move faster than `StairProfile.max_foot_speed` (3.5 m/s) while the body is below `limit_below_speed` (0.6 m/s) or a foot is still catching up, with a catch-up lift (`catch_up_lift`). Lives in `CharacterRig._carry_stair_feet`. No change to player speed. | implemented, automated-tested; partly improved, not eliminated |
| Stair approach pace | The flat "walk for 2 m before either end" is replaced by a graded pace: only when heading *at* a stair end, eased over the last 2 m (`PlaygroundTraversal.approach_pace`). Walking past, along or away is untouched. | implemented, automated-tested |
| Ladder approach pace | A run at the ladder crossed its 1 m zone in 0.2 s (the mount needs 0.25 s) and rammed the rungs; at the platform it could run off the edge before the mount. The same graded pace now applies at both ends. | implemented, automated-tested, negative control |
| Ground support (ramp) | Whole-foot ground sampling (toe, heel, sides), engage rate 12 to 40 per s, `MAX_DROP` 0.20 m (a foot over a ramp's side edge no longer reaches 0.43 m down). | implemented, mesh-measured |
| Placement | Other lying casualties (no collider) are now counted: footprint overlap test (`PlaygroundPlacement._footprints_overlap`). | implemented, automated-tested, negative control |
| Tests | `playground_adversarial_test` (26 checks), `playground_session_capture` (explicit-only, 29 steps), `ramp_contact_probe` (foot mesh), probe options for `stair_transition_probe`. | |

## 2. Stair transition (item 2) and stop/start snap (item 3)

Root cause of the snap (unchanged from the first report): `StairFootPlanner.contact_foot` blends the gait foot into the terrain stance over a 0.3 m/s speed band that a stop crosses in about 0.03 s, so a swinging foot jumps to the tread under it. The planner is pure and must stay so; the fix is in the rig, where the shown foot is state the rig already keeps.

Same probe (`stair_transition_probe`), same session, Regular MIRA; "off" is `limit=0`, the plan shown exactly. Second differences are frame-rate dependent, so compare only within a row pair. The fastest-ankle figure is from frames at least 4 ms apart.

| Case | Ankle second difference, off | on | Fastest ankle, off | on |
|---|---|---|---|---|
| stop and resume | 71.0 mm | 44.7 mm | 8.9 m/s | 5.2 m/s |
| run up (flat approach cap on) | 50.8 mm | 35.3 mm (graded approach) | 6.8 | 4.5 |
| walk up / walk down | 21 to 25 mm | 25 / 25 mm | 3.3 to 5.8 | 3.5 to 5.1 |

Ordinary walking is the same within noise: the limit is not active above 0.6 m/s, so a stride is shown exactly as planned (this is what `traversal_stair_gameplay_test`'s "feet are exactly the planner's" contract requires, and it passes).

**Is the approach slowdown justified?** The stair pose plans one foot per tread and the controller already holds the player to a walk *on* the stairs (an existing rule). Without any approach pace a run into the stairs is cut from run speed to walk speed at the first tread, a velocity step, and the hand-over popped (cap off, limiter off: pelvis 159 mm, ankle 389 mm; cap off, limiter on: 23 / 85 mm; graded cap, limiter on: 14 / 11 mm over the hand-over frames). So the slowdown is a deceleration into a speed limit that already exists, not a concealment; it is now graded (a run eases down over 2 m only when heading at the stairs) rather than a flat cap near them. The limiter alone does not replace it: it takes the entry from 389 to 85 mm, not to the walk level.

**Not eliminated.** Stop and resume is still 44.7 mm against 25 mm for ordinary stair walking. The foot now travels to the tread over a few frames instead of snapping, but the remaining jump is the start of that travel. A planner-level gather with swing clearance is still the fuller fix.

**Regression found and fixed on the way** (mine): the first version of the limiter lifted the stopped foot's toe 14 mm into the tread (`stair_contact_test`) and broke the exact-planner contract; the final version flattens the foot for the last 4 cm and only engages at stops and starts. `humanoid_portability_test` passes unmodified.

## 3. Ramp foot placement (item 4)

The first report measured the ankle bone against a flat-walk reference. This pass measures the **skinned foot mesh** (`SkinnedSurface`, every vertex that follows the foot and toe bones) against the ground under each vertex, every frame (`tools/quality/ramp_contact_probe.gd`). A first version of this probe measured bone offsets; it was biased on a tilted foot and I replaced it with the mesh measurement.

Lowest foot-mesh vertex above the ground, mm (negative is inside the ground), and frames more than 5 mm inside. Regular MIRA. "off" is no placement, "first" is the placement of the first report, "now" is this pass.

| Movement | off | first | now |
|---|---|---|---|
| flat walk (reference, unchanged) | -0.5 | -0.7 | -0.8 |
| ramp entry | -36 (25 fr) | -32 (1 fr) | **-0.7 (0 fr)** |
| ramp exit | -47 (185) | -18 (12) | -18 (12) |
| uphill | -47 (158) | -26 (9) | -27 (8) |
| downhill | -17 (45) | -7 (6) | -7 (7) |
| sideways | -55 (84) | -16 (8) | -16 (7) |
| diagonal | -58 (197) | -27 (19) | -16 (12) |
| standing | -18 (all) | -3.4 | -3.5 |
| crouching | -45 (248) | -18 (195) | -17 (153) |

Small MIRA (the flat walk itself dips 15 to 20 mm: this is the model's own gait, present with the placement off):

| Movement | off | first | now |
|---|---|---|---|
| flat walk | -19 | -20 | -15 |
| ramp exit | -46 (180) | -45 (106) | -46 (86) |
| uphill | -46 (146) | -27 (95) | -20 (64) |
| sideways | -55 (164) | -43 (59) | -43 (49) |
| diagonal | -58 (208) | -46 (86) | -41 (62) |
| stop | -46 (274) | -53 (67) | -54 (56) |
| turning | -50 (180) | -45 (74) | -45 (62) |
| crouching | -49 (252) | -54 (234) | -55 (185) |

What this says:

* The earlier claim that the ramp walk was within 1.5 cm of flat was true of the **ankle height**. The **mesh** still goes into the ramp by 1 to 3 cm for Regular in several movements, and by 4 to 5 cm for Small. The first report's evidence did not show that; this one does.
* **Found and fixed:** at the foot of the ramp the placement had weight 0 until the ankle itself was over the slope, so the toe went into the leading edge for about 10 frames (Regular uphill dump, frames 84 to 93, -27 mm, weight 0.00). Whole-foot sampling plus a faster engage fixed Regular's entry (-32 to -0.7 mm). It did not change the other rows, so it was not their cause.
* **Found and fixed:** a foot over the side edge of the ramp followed ground 0.43 m below (the old 0.45 m limit); capped at 0.20 m.
* **Not found:** the remaining Small dips. They are not a missing ground height under the foot (whole-foot sampling changed nothing there). Candidates I did not isolate: the small leg reaching its extension limit (0.992 of its length on the ramp) so the pelvis cannot follow the lower foot far enough, and the swing foot's own pitch. This is an open defect. Regular's remaining 1 to 3 cm are also unexplained beyond the same candidates.
* Pitch against the slope was not usable: my pitch metric has a constant offset between the foot bone and the sole; I do not report it. Foot **sliding** is not measured in motion; standing slide is 0.0 mm. Knee orientation and swing trajectory were not inspected.
* Airborne: the placement weight fades to 0.92 to 0.94 at the top of the jump, not 0 (it does not disengage fully while airborne, measured as the maximum over airborne frames); on landing it re-engages. I did not inspect whether this is visible.

## 4. Loaded ramp (item 5): **not done**

I did not exercise the four carrier/passenger pairings on the ramp, nor measure passenger clearance or attachment. The report's earlier statement stands: loaded carriers can walk on ramps; unmeasured. The ground-support engine runs for loaded carriers (it is not stair-gated) but I have not looked at it.

## 5. Ladder: adversarial review (item 6)

`playground_adversarial_test` (headless, real input actions; character placement for the fixtures only):

| Case | Result |
|---|---|
| walking along the foot | no mount |
| 45 degree approach | no mount |
| about 20 degrees, toward the rails' centre line | mounts |
| letting go before the 0.25 s timer, then a full walk | no mount, then mount |
| a step at it, then reversing | no mount, walks away |
| **running at it** | **defect found: she ran through the zone and stood against the rungs.** Fixed (graded approach pace). Control with the pace off: does not mount (reproduced). |
| three ascents and descents | each mounts, climbs, descends, steps off |
| platform edge, walking at it | on the ladder before she can step off (lowest y within 0.1 m of the deck) |
| E beside a casualty at the foot | picks the casualty up, does not mount |

Not covered: misalignment toward the other side, running at the head from far away at full speed with the loaded gate, the visible position or facing snap at the moment of mounting (frames below do not isolate it), the loaded transfer gate timing. The loaded-ladder matrix test (`loaded_ladder_playground_test`) passes unchanged.

## 6. Placement and ownership (item 7)

* **Defect found:** casualties have no collider, so the physics-based clearance check could not see them; a body could be put down onto another lying body. Fixed with a footprint overlap test (separating axes with a 10 cm margin). Test: with the others ignored (control) the spot is chosen onto the other body; counted, the carrier turns (more than 23 degrees) and the spot does not overlap; surrounded by eight bodies there is no direction (refused); a Small (0.6 scale) body finds room beside two bodies; the platform edge over a drop is refused; a release followed at once by a pickup keeps the same body; an interrupted put-down leaves the body carried or lying, never lost.
* Existing `playground_casualties_test` (90 checks) already covers a wall, a corner, the tower, defeat while carrying, the cancelled lift and reset. Its fixture needed one change, not an assertion: it put several bodies down at one spot, and the correct new behaviour now refuses that; it resets the casualties between carries.
* **Not inspected:** the swept presentation path during the put-down animation (the carrier's own motion and the passenger's arc). Only the final lying footprint is checked. The footprint uses fixed half-extents (0.90 x 0.34 m at scale 1); I did not re-measure them against each model's lying pose.

## 7. Entering through the normal interface, one continuous session (item 8)

`tests/playground_session_capture.gd` (explicit-only, windowed). **Automated; no person played it.** Match Setup, the Settings tab, the Exploration button, then the playground through key events only (W A S D, Shift, C, E, Space, Esc) with the camera turned by setting its yaw. State is read, never set, in the main sequence. 29 steps, 0 failed in the final run.

**Limits that matter:** (a) the synthetic mouse click did not reach the Match Setup tab or button in this harness (pushed to the viewport, no effect), so the tab is selected and the Exploration button pressed through their own signals; the playground and everything after is real key input. (b) The camera yaw is set to aim at each target (what a mouse look does). (c) One run was made while someone touched the keyboard and mouse; its results were identical to the clean runs before and after, and I discarded it from the evidence anyway.

Sequence: both casualties lie at the station; pick up Regular MIRA, carry and put her down (the other casualty did not move); pick up Small MIRA; walk at the ladder carrying her, climb to the deck (still carrying); walk at the ladder's head and mount from the platform; descend and step off; backing away does not remount; put her down; walk up the ramp; walk at the stairs and get on them; stop and resume; sideways across them; crouch and stand; jump off; switch to Small MIRA through the menu; carry the Regular casualty; Reset casualties and Reset character; leave to Match Setup and re-enter.

Things this session taught me that were not in the first report: switching character is refused while she is on the stairs (existing rule, `_can_replace_visual`); a jump off the stairs usually lands back on the treads and re-enters the stair pose, so "left the stairs" is true only while airborne.

## 8. Motion (item 9): what was and was not inspected

Burst captures at about 5 frames a second (not video; real time between frames, plus render time) for five transitions: carry pickup, loaded ladder approach, ladder from the platform, ramp entry, stair stop and start: `docs/claude/images/playground/motion_*.png`. I looked at the stairs and the loaded-ladder sheets. They show a continuous walk up the stairs and a carrier standing at the ladder; at 5 frames a second and this size they cannot show a foot snap, and the ladder burst started before the mount, so **it does not capture the mount itself**. The claim for these transitions rests on the per-frame ankle and pelvis series above, not on the sheets. Not inspected in motion: ramp entry and exit feet, ladder mounting and dismounting, passenger transfer, passenger release. No video tool was available.

## 9. Verification (item 10)

Runner: `tools/run_tests.ps1`. Counts are from the runs that produced them.

* `check` (catalog): 323 scripts, 323 entries (the session capture is classified explicit-only, render). Import passes. `smoke`: GREEN, 27 of 27.
* Selected tests, all pass at the final commit: `playground_adversarial_test` 26, `playground_casualties_test` 90, `playground_terrain_test`, `exploration_actions_test`, `exploration_playground_test`, `loaded_ladder_playground_test`, `humanoid_portability_test` (unmodified assertions), `traversal_stair_gameplay_test`, `stair_contact_test`, `traversal_stair_feet_test`, `traversal_stair_gait_test`, `traversal_surface_alignment_test`, `traversal_state_test`, `rig_profile_test`, `animation_module_boundaries_test`.
* Animation + movement + rescue subsystem tiers, run after the final code change: 134 passed, 1 failed. The failure is `ladder_landing_test` with 4 failing checks of 216, the same four descent samples that fail on the unmodified baseline (issue 64, unchanged, not touched by this PR). The full tier was not run.
* Negative controls: the stair hand-over (`playground_terrain_test`, limits off), the release into the tower, the run at the ladder (approach pace off), the put-down onto another body (others ignored).
* Intentionally superseded test contract: `playground_terrain_test` now tests `approach_pace` instead of the removed `approaching_stairs`.

## 10. Remaining defects, compromises, limits

* Stair stop and resume: improved (71 to 44.7 mm second difference), not equal to ordinary stair walking (25 mm).
* Small MIRA's foot mesh still goes 2 to 5 cm into the ramp in several movements; Regular 1 to 3 cm; crouching on the ramp sinks 1.7 to 5 cm continuously for both. Cause not isolated.
* The ground-support weight stays about 0.93 in the air.
* Item 5 (loaded ramp) not done.
* Ladder mounting: the mount snap, the loaded gate timing and the misaligned approach from the other side were not examined.
* The placement checks only the final lying footprint, with fixed extents.
* No person has played any of this; no owner approval.
* Retained compromises: a run toward the stairs or the ladder is eased to a walk over the last 2 m (justified above, graded, only when heading at them); the stair limiter below 0.6 m/s.

## 11. What the owner should check

Match Setup, Settings, Exploration. Run at the ladder from a distance (it should slow and mount, not hit the rungs). Run at the stairs. Stop and start on the stairs and look at the feet. Walk both models up, across and down the ramp, standing and crouching, looking at the feet from the side. Put a body down beside another one.
