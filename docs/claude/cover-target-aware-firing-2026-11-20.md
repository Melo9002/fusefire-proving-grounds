# Target-aware cover firing (tactical cover presentation 04)

## 1. Findings: where attack intent comes from

* **One attack path.** Every shot (player, AI, overwatch reaction, guard return fire) is a resolved `AttackActionResult`; `TacticalActionPresenter` then calls `attacker.present_attack(result.target_position)` (a reaction shot calls
  `watcher.present_attack(unit.global_position)`). That call is the only place the visual layer learns that a shot was **authorized**, and it carries one thing about the enemy: the position the shot goes to. The action
  has already been decided and rolled by then; the presentation does not search for enemies, read visibility, or know hidden units.
* **No observation direction exists.** Overwatch is a reservation of AP/ammo (`present_overwatch` shows nothing directional); it fires through the same `present_attack`. Shield faces a threat but is not a cover posture.
  Priority B (an explicit watch direction) therefore has nothing to consume and was **not invented**: passive cover is the only no-attack posture.
* **Tactical geometry.** The shot origin is the cell's support position plus `standing_height` (`CombatRules.get_shot_origin`), cell centre, the attacker's own cell ignored, tile/box LOS between cells. The
  visual muzzle is wherever the rifle is on the lean/yaw. They disagree by up to the lean (about 14 cm) and by the body's yaw; see limitations.
* **Observed during this work:** a legal shot behind a 3-cell wall is only possible for targets that pass a wall end (oblique shots: for a unit centred behind it, (11,12) and (1,13) were legal; (9,13), (10,13), (8,14), (6,14) were Blocked). The tactical test
  is tile-based and tolerates a ray that clips a wall corner by about 0.1-0.25 m (e.g. (1,13): the straight line from the cell centre crosses the wall's end 0.24 m short). The plan records this as `ray_crosses_wall_end`.
* **A real defect fixed on the way.** While aiming round full cover the old pose yawed the body 20 degrees toward the edge **relative to a facing that already pointed at the target**, and the rifle follows the body, so the muzzle
  pointed 20 degrees off the target. Target-aware firing aims square to the target (`attack_aim_yaw_degrees`, default 0); the lean comes from the existing `shoot_left` / `shoot_right` clips.

## 2. Interface (smallest possible)

No new signals or tactical queries. The adapter reads the authorized target position it is already given:

`UnitVisualAdapter.present_attack(target)` → `_plan_attack_posture(cover, target)` → `CoverEdgeSelector.plan_attack(edges, full_cover, to_target, previous_attack_side, passive_side, face_distance, profile)`

`plan_attack` is a pure static function over geometry and a direction. It returns `{mode, side, mismatch, along, lateral, crossing}` where `mode` is `CoverEdgeSelector.FiringMode`:
`PROTECTED` (passive; also the "no honest pose" fallback), `OVER_COVER`, `AROUND_LEFT`, `AROUND_RIGHT`, `ORDINARY`.

## 3. Rules (priority)

A. **Active authorized attack** (`present_attack` from cover):
1. the wall is not between unit and target (cosine to the wall normal at or below `open_side_threshold`) → `ORDINARY`, `shoot`, no peek;
2. LOW cover → `OVER_COVER` (the existing rise-to-look-over crouch), `shoot`;
3. FULL cover, target clearly to one side → the edge **on the target's side**, if usable (`AROUND_RIGHT` for a target to the right: the shot passes that wall end), `shoot_left` / `shoot_right`. It is not "the nearest edge";
4. FULL cover, target straight ahead (`straight_ahead_threshold`) → the passive choice (nearest usable edge, right on a tie), so a long wall keeps today's fallback;
5. the target's side edge is unusable → the passive pose and a recorded mismatch (`target_side_edge_unusable`); no usable edge at all → `PROTECTED` with a mismatch. The skeleton is never pushed through a wall and the unit is never moved.
6. `attack_side_hysteresis`: a side chosen for the previous attack is kept while the next target is only slightly across the middle (no left/right flicker between consecutive attacks).

The plan is made once per attack and held (`attack_plan`) until the attack sequence ends, so it cannot flip mid-attack. `cover_side` stays the **passive** choice: when the attack ends the unit returns to exactly the pose and side it
would have had without the attack.

B. Explicit observation: none exists (see 1); not implemented.

C. **Passive cover:** unchanged (`CoverEdgeSelector.edges/choose`: nearest usable edge, right on a tie, obstructed edges rejected, none → protected, hysteresis).

## 4. Ownership and permitted displacement

| Thing | Owner |
| --- | --- |
| Whether a shot is legal, its outcome, protection, LOS | tactical layer (unchanged) |
| Which edge/pose presents it | `CoverEdgeSelector.plan_attack` (pure), called by `UnitVisualAdapter` |
| Body yaw offset | `UnitVisualAdapter._cover_yaw` via `CoverPostureProfile.attack_yaw_offset` (protected side = passive, aimed = square to the target) |
| Crouch, kneel, lean hips | `CoverCrouchModifier` / the `shoot_*` clips (the existing modifier order is untouched) |
| Rifle, arms, hands | WeaponPose, WeaponArmIK, HandGrip (unchanged) |

Visual displacement is only the existing crouch/kneel, the body yaw offset, and the 14 cm lean clips; the tactical cell, collision, path and LOS origin never move. Where a legal shot would need more than that the plan records a mismatch.

## 5. Tuning (`CoverPostureProfile`, group "Attack posture")

`open_side_threshold`, `straight_ahead_threshold`, `attack_side_hysteresis`, `attack_aim_yaw_degrees`.

## 6. Diagnostics

`UnitVisualAdapter.attack_plan` (current) and `attack_plan_log` (last 24 plans, with mismatches) are plain data for tests and tools; nothing is drawn in normal play. The workbench's optional overlay adds the authorized direction (yellow)
and a readout line (`intent`, mode, side, cosines, mismatch). The bench's target is a scripted *authorized* target; the game's comes from the attack result, so hidden enemies are never involved.

## 7. Workbench

Cover row: scenario walls (Low, Low aim, Left edge, Right edge, Tie, No edge, Peek aim, plus Left/Right usable only). "Authorized attack" row: Target left / right / ahead / Open side, Fire, End attack. The plan is
the production `plan_attack`; the facing change is absorbed exactly as in the game.

## 8. Tests

`tests/cover_target_aware_test.gd` (registered in the assets suite through the `^cover_` pattern): pure rules (intent beats passive, fallback, tie, hysteresis, unusable edge, determinism, profile parameters), and production attacks
(left target → `shoot_left`, then right target → `shoot_right`, rifle within 8 degrees of the target at fire, no muzzle jump, one plan per attack, plan dropped and passive side restored, cell/position/AP unchanged,
plan independent of other units, attack then move out of cover).

## 9. Limitations

Round obstacles have no peek side (unchanged). The tactical shot comes from the cell centre; the visual rifle is up to a lean away, so corner-clipping shots are reported, not corrected. A one-clip lean only: no start/stop
transitions between sides. Elevation-aware firing and per-target height are not modelled. No distinct hit reaction by direction.
