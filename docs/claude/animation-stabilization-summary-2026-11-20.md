# Animation stabilization checkpoint: architecture and summary (01, 01B, 02, 03)

Detail lives in `locomotion-foundation`, `locomotion-speed`, `rescue-lifecycle` and `cover-posture` (this folder); this page is the integrated view.

## Modifier ownership (runtime order, verified by tests)

`Locomotion` -> `CoverCrouch` -> `WeaponPose` -> `WeaponArmIK` -> `HandGrip`, each exactly once under the skeleton (asserted in `locomotion_gait_test`, `cover_edge_selection_test`, the elbow, torso-frame,
weapon-pose and rescue tests).

| Owner | Controls |
| --- | --- |
| AnimationTree (before the modifiers) | gait clips (walk/jog/run/loaded), idle, shots, hits, carry arms |
| `LocomotionPoseModifier` | turn twist (hips/spine, chest net zero), banking, accel pitch, turn steps; never arms or weapon |
| `CoverCrouchModifier` | hip drop, legs, kneel, spine lean (aim lean, carry lean) |
| `UnitVisualAdapter` | the visual root's **yaw** (cover offset), the rig's step toward a passenger, state selection |
| `WeaponPoseModifier` / `WeaponArmIK` / `HandGrip` | rifle targets, arm IK, hand orientation; carry contacts while carrying |
| `CharacterAnimationController` | state changes and cross-fades; its visual-root tween resets **only lean axes and position**, never yaw |

## Coordinate conventions

Character frame: x = its left, y = up, z = forward. The humanoid's anatomical forward is the way the toes point, measured from the rest pose; up is hips to head; the hip hinge is forward x up
(`CharacterFallbackAnimationBuilder.measure_axes`). Imported bone-local axes are never assumed (on MIRA a local-x leg rotation swings the leg sideways). Locomotion direction vectors: x toward the character's left,
y forward. Bone position offsets are in the skeleton's own units (the model is scaled in the rig), so metres are divided by that scale where exactness matters (`make_lean_shot`).
Cover/peek side: +1 right, -1 left as the unit faces the wall; turning right is a negative yaw.

## Editable values

`LocomotionProfile` / `LocomotionGait` (thresholds, cadence limits, responsiveness, turning, bank, accel lean, the walk/jog/run/loaded phase tables, strides); `CoverPostureProfile` (edge reach, tie tolerance, tie side, hysteresis, protected and
peek yaw, turn rate, crouch numbers); `RescueInteraction` (phase timings, carrier bend, passenger path); `WeaponHandlingProfile.ready_clearance`. Exported on `CharacterRig`; the workbench panel shows the live values.

## Behaviours

* **Cover side:** nearest usable wall edge (reachable, unobstructed, within reach); right when within the tie tolerance; none when no edge is usable; hysteresis keeps a chosen side. No facing or enemy inputs. `shoot_left`/`shoot_right` were
  found **reversed** (and 22 cm of lean) at this checkpoint and now lean 14 cm toward the character's left/right respectively (`make_lean_shot`, tested both ways).
* **Rescue lifecycle:** Rescue is an explicit action (world-bar button -> `ObjectiveManager.try_rescue`); proximity only makes a unit eligible. The target awaiting rescue is shown as a lying body (derived flag `awaiting_rescue`); the
  pickup starts from it; a carrier lost at any phase leaves one lying body and the objective open; a second unit repeats the lift.
* **Test runner:** subsystem selection is by filename pattern (`tools/run_tests.ps1`). The `cover_*` tests matched no subsystem (they only ran in the `full` tier); `^cover_` is now part of the `assets` pattern. Other unmatched tests (battle_*,
  destructible_cover_investigation, squad_loss_outcome, turn_removal_continuation, unit_identity) are outside this work and still run in `full`.

## Workbench

Run `res://art/characters/mira_0/demo/mira_0_pose_workbench.tscn` (Godot, F6 / `godot --path . art/characters/mira_0/demo/mira_0_pose_workbench.tscn`). The panel (top right) drives the production rig: speed slider and Idle/Walk/Jog/Run, direction, loaded carry,
turns in place, moving 90/180, scripted transitions, the Cover row with an optional overlay (default off), camera views, slow motion, live readout. Keys: `R` pickup, `Q` release, `K` carrier-death drop, `P`/`M`/`E` steady carry / carry move / boarding. The cover
scenarios use the production `CoverEdgeSelector` and `CoverPostureProfile` on a synthetic wall; rescue and locomotion use the production rig.

## Known limitations

Loaded-carry pelvis yaw (kept at 0): drift of 5.8 mm at 2 degrees; no modifier-order fault found (the carry contact targets are computed in the WeaponPose pass from the chest anchor and the carrier's shoulders); the likely sensitivity is the
shoulder-to-limb side direction the contact uses, but the cause is not isolated. Round obstacles have no peek side. Distant rescue orders are unsupported. A player-controlled VIP shown incapacitated is still tactically selectable (rules unchanged,
decision for the project owner). End Turn during a lift is not specially handled.

## Deferred (not implemented)

Animation polish: upper-body motion, finer pelvis/hip compensation, foot contact and stopping, pickup/release choreography, more hit reactions, elevation-aware firing posture, finger articulation, secondary-motion physics.
Cover: target-aware side selection, muzzle/cover geometry consistency, round-obstacle peeking, corner transitions.
Combat: anatomical hit resolution (visibility-aware regions, projectile paths consistent with hit outcomes, regional armour and damage, component damage on androids, region-specific hit reactions). The existing combat simulation stays authoritative.

## Recommended priorities

1. Decide whether a player-controlled incapacitated VIP should be selectable/active. 2. Hit-reaction set and recovery blends. 3. Target-aware cover side once the tactical layer can expose the firing side. 4. Start/stop foot steps. 5. Anatomical hit-resolution design.
