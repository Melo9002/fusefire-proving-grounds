# Animation developer guide: "If I want to change X, where do I go?"

> **Superseded (Task 07, 2026-11-21).** The current architecture and paths are in [docs/animation.md](../animation.md). This dated report is kept as history; its paths and class names (`UnitVisualAdapter`, `presentation/characters/runtime/`) no longer exist.

Explanatory only (companion to [animation-architecture-audit-2026-11-20.md](animation-architecture-audit-2026-11-20.md)). Paths are real as of 2026-11-20; `RT` = `presentation/characters/runtime/`. Items marked *(uncommitted)* exist in the working tree but not yet in `main`.

## The 60-second picture

Gameplay commits an action -> `TacticalActionPresenter` / `TacticalUnit` show it -> `UnitVisualAdapter` (the only class that reads tactical state) turns it into calls on `CharacterRig` -> the rig feeds an `AnimationTree` of **generated** clips and a stack of seven skeleton modifiers, using pure solvers and profile resources for the numbers. The scene is `art/characters/mira_0/runtime/mira_0_unit_visual.tscn`; the inspector is `art/characters/mira_0/demo/mira_0_pose_workbench.tscn`.

Modifier order (current): Locomotion, CoverCrouch, Traversal, TraversalLegIK, WeaponPose, WeaponArmIK, HandGrip.

## Where do I go?

| I want to change... | Go to | Notes |
| --- | --- | --- |
| **Walking / jogging / running speed thresholds** | `RT/locomotion_profile.gd` (resource, exposed as `CharacterRig.locomotion_profile`): `walk_until`, `jog_at`, `run_at`, `max_cadence` | The unit's actual movement speed is `TacticalUnit.movement_speed` (5 m/s) and `stats.speed` (AP budget): gameplay, not here. |
| **Gait style** (stride, cadence, arm swing, knee lift) | `RT/locomotion_gait.gd` tables per gait; clips are built in `RT/character_fallback_animation_builder.gd` (`make_gait`) | Clips are generated; there are no authored files to edit. |
| **Turning** (twist, bank, lean, turn steps) | `RT/locomotion_profile.gd` turn/bank/accel settings; behaviour in `RT/locomotion_pose_modifier.gd`; the turn is started by `UnitVisualAdapter.face_world_position` / `update_locomotion` | Known interaction: the spine twist share is erased when a lean is active (audit F-04). |
| **Weapon pose** (stock, grips, ready, stow) | `RT/weapon_handling_profile.gd` (numbers) + `RT/character_rig.gd` (`apply_weapon_targets`, `update_torso_frame`, `ready_grip`) + `RT/weapon_pose_modifier.gd` | One weapon today (AUG, `character_rig.gd` `weapon_scene`). |
| **Hand contacts / fingers** | `RT/hand_grip_modifier.gd` (curl, orientation); contact targets in `character_rig.gd` (`apply_carry_targets`, `apply_traversal_hand_targets`) | Diagnostics: `presentation/diagnostics/hand_contact_*`. |
| **Elbows** | `character_rig.gd` `apply_elbow_guidance`, exports `carry_elbow_swivel_degrees`, `left_elbow_ready/aim`; doc `docs/claude/swivel-preserving-elbow-guidance-2026-11-19.md` | |
| **Cover behaviour** (crouch depth, which side, yaw) | `RT/cover_posture_profile.gd`; side/firing plan `RT/cover_edge_selector.gd`; crouch solve `RT/cover_crouch_modifier.gd`; state machine in `UnitVisualAdapter` (`_sync_cover_crouch`, `_plan_attack_posture`); grid lookup `RT/tactical_pose_context.gd` | Protection/LOS/legality are tactical (`systems/combat_rules.gd`), never here. |
| **Aim / attack timing** | `UnitVisualAdapter` (`present_attack`, `_advance_attack`, phases RAISE..RELEASE); `WeaponHandlingProfile` (`max_raise_wait_seconds`, `shot_recover_seconds`) | The presenter polls `is_attack_pending()`. |
| **Hit reactions** | `UnitVisualAdapter.present_hit`; clip `hit` in the builder | One clip only. |
| **Rescue pickup / carry / release** | `RT/rescue_interaction.gd` (timeline resource: phases, durations), `RT/rescue_passenger.gd`, `RT/passive_passenger_pose.gd`, rig `begin_pickup/begin_carry/apply_carry_targets` | Trigger is `ObjectiveManager.try_rescue` (explicit button). |
| **Ladder climbing** | `RT/traversal_profile.gd` (rung layout, windows, mount lengths, speeds), `RT/traversal_solver.gd` (pure contacts), `RT/traversal_pose_modifier.gd` (pelvis/legs); rig `begin_traversal/set_traversal_progress`; adapter `note_segment` | Only links of kind LADDER (`TraversalLinkData.LADDER`, stamped by the map compiler from `ladder_local_bottom/top`). |
| **Stair contacts** *(uncommitted)* | `RT/stair_profile.gd` (policy, speed, pelvis), `RT/stair_model.gd`, `RT/stair_foot_planner.gd`; declare stairs on the scene's `ElevationPath` (`surface_kind = Stairs`, `treads_per_step`) | Route expansion currently lives in `units/tactical_unit.gd` `move_along_path`. |
| **Ramps** *(uncommitted)* | Declare `surface_kind = Ramp` on the `ElevationPath`; walked along the slope by `move_along_path` | |
| **Path smoothing** *(uncommitted)* | `RT/path_presentation_profile.gd` (off by default), `RT/path_refiner.gd`; hooked in `TacticalUnit` | |
| **Presentation speeds on ladders/stairs** | `TraversalProfile.climb_speed/descend_speed`, `StairProfile.speed` | Presentation only; replay scale applies automatically. |
| **Rig proportions / bone names** | There is no single place (audit F-01): bone names in `RT/character_rig.gd` (`_build_*` and exports), `RT/character_fallback_animation_builder.gd`, `RT/locomotion_pose_modifier.gd`, `RT/character_animation_controller.gd`; numbers in the profiles above; model scale on `mira_0_unit_visual.tscn` (`character_scale = 1.6`) | Plan for several edits per rig today. |
| **Animation state transitions** | `RT/character_animation_controller.gd` (`STATES`, `play`, AnimationTree) for clip states; policy (when to play what) in `UnitVisualAdapter` (`present_*`) | New state = add to `STATES` and the builder. |
| **A new profile value that should be tunable** | add an `@export` to the relevant profile resource; read it from the owning modifier/solver | Keep presentation numbers out of tactical files. |
| **Something to look at** | Workbench scene `art/characters/mira_0/demo/mira_0_pose_workbench.tscn` (panel: locomotion, cover, ladder, stairs, path corridor, cameras, markers) | The workbench re-implements part of the adapter's frame loop. |

## Rules of thumb

* Presentation may not change HP, AP, cells, occupancy, LOS, cover rules or replay records (enforced by `tests/traversal_replay_determinism_test.gd`).
* New pose math goes in a **pure** class first (no scene, no time) and gets a unit test, then a rig/gameplay test.
* A modifier must say which bones it writes and whether it **multiplies** the current pose or **replaces** it (the F-04 defect came from mixing the two).
* Read bone poses inside `skeleton_updated`, never after the frame.
* Run: `tools/run_tests.ps1 subsystem -Subsystem assets` (rig/cover/locomotion), `-Subsystem movement` (traversal), `full` before a checkpoint; `tools/quality/script_warning_audit.gd` for GDScript warnings.

## Verified during the audit

The suite runs listed in the audit report (section M, and the final message) were executed on 2026-11-20 on the working tree; earlier historical results are not repeated.
