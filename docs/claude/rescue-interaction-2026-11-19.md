# Rescue interaction: pickup, loaded carry, release, interruption (animation 06C-06D)

Builds on the accepted static fireman's carry (06 to 06B.1, `humanoid-rescue-passenger-2026-11-19.md`). That pose, the contact
infrastructure, the weapon sling and the arm IK are unchanged. This adds the time dimension: how the carry begins and ends, how it moves,
and what happens when it is cut short.

## 1. Rescue lifecycle (traced before anything was built)

Tactical authority is `ObjectiveManager` and `TacticalUnit`. Presentation never decides an outcome.

| Moment | Tactical operation | Timing before 06C |
| --- | --- | --- |
| Rescue action | `ObjectiveManager.complete_rescue` calls `carrier.carry_unit(target)`: records `carried_unit`, lowers the carrier's speed by 2, hides the actor (`visible = false`, `PROCESS_MODE_DISABLED`), calls `visual_adapter.present_pickup()`. The objective completes in the same call. | Instant; the visual was a 0.6 s pose. |
| Moving while carrying | Ordinary move action; the adapter plays `carry_move` when `_carrying()`. | Presentation only. |
| Extraction | `TacticalActionPresenter._present_extract` calls `present_boarding()`, waits 0.6 s, frees the actor. The passenger visual shrinks over 0.55 s. | Already timed. |
| Carrier falls | `BattleController._on_unit_defeated` -> `ObjectiveManager.release_carried_unit(carrier, fall_cell)`: the actor is put on the nearest standable cell (within 3), made visible and active, and the Rescue objective reopens. Existing test: `rescue_carrier_loss_test`. | Tactical release was correct. **The carrier's visual passenger was not told**, so it stayed on the dead carrier next to the revealed actor (two passengers). |
| Ordinary release | **There is none.** Release exists only as the consequence of the carrier's death. | n/a |
| Carrier removed with its tree (mission cleanup, scene change) | The rig and its passenger node are children of the carrier and are freed with it. Nothing outlives them. | Fine. |

Gaps, stated plainly:

* No tactical "put down" command exists. The release timeline is implemented and tested but nothing in the game triggers it; it is
  used by the workbench. Giving it a trigger needs a gameplay decision (a new action) and was out of scope.
* The incapacitated state of the actor is whatever its own visual shows when revealed. There is no incapacitated status in the tactical
  layer, so the visual layer does not invent one.
* A carrier freed without dying (cleanup) leaves `carried_unit` set on a freed object; harmless at teardown and not touched.

## 2. Architecture

One clock, one owner, no new actors.

* **`RescueInteraction`** (`presentation/characters/runtime/rescue_interaction.gd`, a `Resource`): the shared timeline. Pure arithmetic: a
  function of time, no nodes, no randomness. Exposes `start/advance/scrub/stop`, `sample()` and `phase_bounds()`. All timing and key values are
  `@export` here. `CharacterRig` owns one instance (`rescue_interaction`).
* **`CharacterRig`** advances it once per frame (`_apply_carry_posture`) and applies the sample to both bodies: carrier crouch/kneel/lean/step/base
  clip, hand reach weight, weapon position, and the passenger's lift and pose. Entry points: `begin_pickup(passenger_world)`, `begin_release()`,
  `begin_carry()` (steady state, no lift), `finish_interaction_now()`, `end_carry(leave_passenger := false)`. Signal `rescue_interaction_finished`.
* **`RescuePassenger`** decides its own transform in one place, `placement(anchor)`: on the lift path before it is carried, on the chest anchor
  after. It also owns the secondary motion and re-poses itself from `PassivePassengerPose.blend(LYING, carried, t)`.
* **`UnitVisualAdapter`** is the lifecycle shim: `present_pickup(passenger_world)`, `present_carry_released()`, and settling the timeline when a
  conflicting presentation starts (move, boarding).
* **`TacticalUnit`** passes the actor's place to `present_pickup` and calls `present_carry_released()` from `release_carried_unit()`. These are
  the only changes outside presentation, and neither alters tactical state.

Unchanged: modifier order (CoverCrouch, WeaponPose, WeaponArmIK, HandGrip), the contact solver, `ChestAnchor`, `HandGripModifier`, elbow guidance.
The carry contacts gained a reach weight, so one solver serves reaching and holding.

## 3. Pickup (3.25 s with defaults)

| Phase | Seconds | Carrier | Passenger |
| --- | --- | --- | --- |
| align | 0.5 | Turns to the actor's place (a snap, as attacks do), walks in (`move`), starts to bend. Hands still where they were, rifle in hand. | Lying on its back at the actor's place, hands at its sides. |
| reach | 0.7 | Half-kneel; hands travel onto the passenger's wrist and thigh (contact 0 to 1, fingers close with it); rifle travels from the hand to the sling. | Still. |
| lift | 1.25 | Rises. Holds both contacts. | Comes up the carrier's front along a path through `lift_waypoint`, rolls over about the carrier's x axis (face toward the carrier first), limbs blend from lying to draped. |
| settle | 0.8 | Steps back to its tactical place into the carry lean and loaded gait. | Comes to rest across the shoulders (the 06B.1 pose). |

The hand starts at where the IK targets were (captured at `begin_pickup`), so nothing snaps. The weapon is interpolated between the socket and the
sling transform (`_weapon_hand_local`), not teleported.

## 4. Release (3.0 s)

The pickup timeline run backwards at its own duration (`release_seconds`): the carrier steps in with the load, kneels, lowers the passenger, and
only when it is on the floor (lift 0) do the hands let go (checked by test); then it rises and the rifle returns to the hand. The passenger is
freed at the end (`rescue_interaction_finished` is emitted first, so a listener can reveal the real actor where it was set down). The workbench keeps
it lying (`keep_released_passenger`).

## 5. Loaded gait and secondary motion

* `carry_move` now uses `CharacterFallbackAnimationBuilder.LOADED_GAIT` (one dictionary): thigh swing 14 deg (unloaded 22), knee 36 (48), foot 7,
  hip bob 10 mm (18), trunk sway 1.2 deg (2). Narrower and steadier, no sag. Tactical speed and costs untouched; `move` unchanged.
* Passenger secondary motion (`RescuePassenger._update_motion`): a first-order low pass of the chest anchor in the carrier's frame (response 0.12 s),
  clamped to 20 mm and 1.5 deg, plus up to 4 deg swing of head, spine and the free arm driven by the vertical lag. No spring, no overshoot, no state
  other than the filtered position; it is exactly zero at rest. Disabled while lifting. The held wrist and the thigh contact limbs are not swung, so
  the hands stay on their contacts (measured 0.00 mm).

## 6. Interruption and boarding

* Carrier falls in any phase: tactical release reveals the actor (unchanged) -> `present_carry_released()` -> `end_carry()`: passenger freed, weapon
  back in the hand, contacts, crouch, kneel, lean and step cleared, arm IK handed back, carrier leaves the carry states. Tested in six phases.
  This is a cut, not a synchronized fall: the revealed actor simply appears (no landing reaction was added).
* Boarding settles a running lift first (`finish_interaction_now`), then the existing shrink. Walking off during a pickup settles it likewise.

## 7. Parameters

| Where | What |
| --- | --- |
| `RescueInteraction` exports | phase seconds, release seconds, crouch depth, kneel, lift crouch, max step, stand-off, lift waypoint, ground height, stow window |
| `CharacterRig` "Rescue Carry" | `rescue_interaction`, `passenger_motion_*` (enabled, amplitude, tilt, response, swing), anchor, yaw, pose overrides, swivel |
| `CharacterFallbackAnimationBuilder.LOADED_GAIT` | loaded stride |
| `PassivePassengerPose.LYING` | the passenger's limb pose on the floor |
| `CharacterRig.RELAXED_HANDS/POLES`, `RELEASE_STEP` | where the hands let go to, how far a release steps in |

## 8. Workbench

`R` pickup (passenger 1 m ahead), `Q` release, `K` carrier-death drop, `O` pause, `,` `.` scrub 0.1 s, `Y` motion on/off, `P`/`M`/`E` steady carry,
carry move, boarding. The status label shows the phase and time. Captures use the production path through scripted scrubbing (`rescue_interaction.scrub`).

## 9. Known limits (provisional)

* The tactical actor is hidden at the instant of pickup, so its standing pose cuts to the lying passenger. There is no incapacitated visual.
* The carrier's walk-in uses the unloaded `move` clip at a slower pace and the step back uses `carry_move`; some foot sliding remains in the first
  and last quarter second.
* Hands are mitten-like (uniform curl); no finger wrap. Mesh interpenetration was looked at, not measured; the passenger's torso clips the carrier's
  chest in the first part of the lift and the carrier's hands are close to its own thighs in the half-kneel.
* The release has no tactical trigger. The revealed actor is placed by the tactical layer, which does not match where the release lays the visual.
* The carrier's turn to face the passenger is instant.
