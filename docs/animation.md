# Character animation: architecture and developer guide

The maintained guide to FuseFire's humanoid presentation. It describes the code as it is after Task 07. The dated reports in [`docs/claude/`](claude/README.md) (audits, the Task 02 to 06 designs, the Package 1 to 10 migration reports) are history; read this page for the current shape.

## The picture

Gameplay decides what happens and owns authority (AP, cells, occupancy, legality, movement completion, damage, objectives, replay). A **context host** turns the game's (or a tool's) state into presentation requests. One shared **presenter** per character owns presentation time and intent. A **rig** applies poses to the skeleton. Presentation may change transforms, poses, effects and timing; it never changes HP, AP, occupancy, line of sight, legality or replay outcomes.

```
 gameplay (TacticalUnit, systems/)            authoritative, knows nothing of poses
        |  reads / calls present_*()
 context host   TacticalCharacterAdapter  (tactical)      reads tactical state, chooses requests, cover policy
                ExplorationCharacterHost  (exploration)    a controller's wishes: move, face, crouch, inspect
                PoseWorkbench             (tools)         controls and benches
        |  requests (context-neutral)         drives once per frame: presenter.tick, advance_actions, rig.update_weapon_pose
 CharacterPresenter (RefCounted, in the rig)  time, facing, postures, aim/attack/hit/defeat lifecycles, rescue clock, ActionHandles
        |  typed inputs
 CharacterRig (Node3D)                        skeleton, resolved rig roles (RigBones), modifiers, IK targets, attachments, poses
```

A host is a plain `Node3D` with a `Rig` child. It does not inherit the rig, builds nothing on the skeleton, and the rig has no frame callback of its own: the host advances the character exactly once per frame. Ratchets in `tests/animation_module_boundaries_test.gd` enforce this.

## Who owns what

| Responsibility | Owner |
| --- | --- |
| AP, cells, occupancy, legality, movement completion, damage, objectives, replay | gameplay (`units/`, `systems/`); unchanged by presentation |
| Reading tactical state, choosing which presentation to request, tactical cover policy (`CoverEdgePolicy`, `CoverEdgeSelector`), route expansion (`TacticalRouteBuilder`), camera anchors, team ring and class marker | `TacticalCharacterAdapter` and `presentation/tactical/` |
| Presentation time, facing, posture arbitration (`PostureArbiter`), aim hold, attack sequence, hit and defeat lifecycle, the rescue clock, pending pickup, `ActionHandle`s | `CharacterPresenter` |
| Skeleton configuration, bone roles, the modifier stack and its order, IK targets, weapon and passenger attachments, equipment presentation, unarmed arms | `CharacterRig` |
| What the body is (bones, roles, joints, sockets, measurements, capabilities) | the rig profile, `presentation/characters/rig_profile/` and `art/characters/<name>/<name>_rig_profile.tres` |
| How it moves (gait tables, profiles, pure solvers for ladders, stairs, paths) | `presentation/characters/motion/` |
| What it carries (handling profile, equipment requirements) | `presentation/characters/equipment/`, optional per character |

The reusable cover **body-motion** numbers (yaw offsets, crouch depths, clearances, speeds) are `CoverPostureProfile` (`motion/`, exported on the rig). The tactical **edge-selection** numbers are `CoverEdgePolicy` (`presentation/tactical/`, owned by the host).

## Where things live

```
presentation/characters/        shared: no tactical, exploration or base types, no gameplay imports
  presenter/                    CharacterPresenter, PresentationTypes/Intent, ActionHandle, AttackHandle/AttackSequence/AttackHost,
                                AimHold, PostureArbiter, WeaponReadiness, RescueInteraction
  rig/                          CharacterRig, RigBones, RigAxes, animation controller, fallback clip builder, ChestAnchor,
                                RescuePassenger, PassivePassengerPose, typed pose state (LadderClimb/Pose, StairWalk/Pose, WeaponPoseBinding, ...)
    modifiers/                  Locomotion, CoverCrouch, Traversal, WeaponPose, HandGrip modifiers; PoseOwnership
  rig_profile/                  RigProfile, RigAnatomy, RigResolver, roles, joint specs, sockets, diagnostics (pure data)
  motion/                       LocomotionProfile/Gait, Traversal and Stair profiles and solvers, PathRefiner, CoverPostureProfile
  equipment/                    WeaponHandlingProfile, EquipmentPresentation
presentation/exploration/       the non-tactical host: ExplorationCharacterHost (reads no tactical type; ratcheted)
presentation/tactical/          the tactical host and its policy: TacticalCharacterAdapter, TacticalActionPresenter, CoverEdgeSelector,
                                CoverEdgePolicy, TacticalPoseContext, TacticalRouteBuilder
presentation/diagnostics/       hand-contact diagnostics (read the rig, never write it)
tools/animation_workbench/      the pose workbench (pose_workbench.tscn) and its locomotion test panel
tools/quality/                  pose_trace, route_trace, animation_perf_baseline and probes
art/characters/mira_0/          model, rig profile (mira_0_rig_profile.tres), runtime/mira_0_unit_visual.tscn (the production character)
tests/                          flat; tagged in tests/catalog.json
research/                       evidence only: update-order probe, exploration playground (the Task 03 host probe was retired into exploration_host_test)
```

Modifier order (declared in `PoseOwnership`, checked by `pose_ownership_test`): Locomotion, CoverCrouch, Traversal, TraversalLegIK, TraversalFoot, WeaponPose, WeaponArmIK, HandGrip. IK results are valid only at `skeleton_updated`, not between updates.

## How a context host uses CharacterPresenter

1. Add a scene with a host `Node3D` and a `Rig` child (a `CharacterRig` with `character_scene`, `rig_profile`, optional `weapon_scene`). See `art/characters/mira_0/runtime/mira_0_unit_visual.tscn` for the production shape.
2. In the host, resolve the rig (`rig`, `presenter = rig.presenter`) and, before it builds, set `rig.loaded_query` (when the context says the character is a loaded carrier) and `rig.aim_blend_follows_clips` (false if the host drives readiness itself). The tactical adapter does this in `_enter_tree`.
3. Each frame, in this order: feed motion (`presenter.set_movement_authority`, `report_velocity` or `set_scripted_motion`), `presenter.tick(delta)`, any host policy (posture requests via `presenter.postures`, `presenter.apply_posture`), `presenter.advance_actions(delta)`, then `rig.update_weapon_pose()`. The presenter advances exactly once per frame; `presentation_frame_driver_test` checks it.
4. Ask for actions through the presenter and rig (`begin_pickup`, `begin_release`, attack, hit, defeat) and await the returned `ActionHandle` (COMPLETED, SKIPPED, INTERRUPTED, CANCELLED). A handle describes the visual operation only; gameplay outcomes never depend on it.
5. Read `presenter.intent()` for the character's persistent state (posture, facing, equipment, readiness) when something else needs it.

`TacticalCharacterAdapter` is the tactical example; `ExplorationCharacterHost` is the minimal context-neutral one; `tools/animation_workbench/pose_workbench.gd` is the third. Nothing in the shared module may import gameplay.

### The non-tactical host (Task 08)

`ExplorationCharacterHost` (`presentation/exploration/`, scene `art/characters/mira_0/runtime/mira_0_exploration_visual.tscn`) hosts the same rig scene as the tactical unit (`mira_0_rig.tscn`) with no unit, turns, AP, cover or combat state. A controller asks for: `report_velocity(world_velocity, delta)` (the presenter turns the body toward it and derives the gait), `face_point` / `face_yaw`, `set_crouched(on)` (a CONTEXT-priority posture request) and `inspect(world_point, seconds)`, which turns to the object, bends toward it and returns an `ActionHandle` (COMPLETED when the hold ends, INTERRUPTED when the controller walks away or the host is removed, CANCELLED if one is already running). The host selects the clip state (`move` or `rifle_idle`) and drives the frame: presenter tick, posture, action stage, `rig.update_weapon_pose()`. Equipment is the scene's choice: set `rig.weapon_scene = null` before the host enters the tree for an unarmed MIRA. `ExplorationSpawnGuard` (same folder) is the mode's fall safety net: a body that falls out of the world is let fall for a moment, then returned to the nearest spawn point (any `Node3D` in group `exploration_spawn`) with its velocity cleared; the controller then calls `host.reset_motion(yaw)`. A controller should move its body per rendered frame (speed times that frame's delta), not on 60 Hz physics ticks: stepping only on ticks while the camera and animation run per frame shows as a tremor at higher frame rates. The host also offers `set_aiming` and `fire` (the shared attack sequence through a small `AttackHost`), `react_hit` and `defeat`, `enter_cover`/`leave_cover` (the shared cover posture), `begin_climb`/`set_climb_height`, `begin_stairs`/`set_stairs_progress`, and `pick_up`/`put_down` (the shared rescue lift and release). The example controller is `research/exploration_playground/` (WASD, Shift run, RMB aim, LMB fire, Space cover or a placeholder jump, E climb, lift or inspect, C crouch, Q holster, middle mouse recenters). It is a proof of concept, not an exploration architecture: each action is its own small component (`playground_combat`, `playground_cover`, `playground_traversal`, `playground_carry`, `playground_player_health`, plus mannequins and props). Test: `exploration_actions_test`; render: `tests/exploration_actions_capture.gd`.

## How to add or configure a humanoid rig

A rig is configured entirely by its profile; no skeleton bone name appears in production code (ratcheted).

1. Import the model (a glb with a `Skeleton3D`). Keep its path stable once referenced.
2. Create the rig profile (`RigProfile`): a Godot `BoneMap` of the humanoid roles to this skeleton's bone names, the anatomy (head-top bone, standing height measurements) and sockets. `art/characters/mira_0/mira_0_rig_profile.tres` is the reference; `tests/fixtures/rigs/` holds a synthetic skeleton with entirely different names.
3. `RigBones.from_profile` turns it into the typed roles every stage reads (`hips`, `torso`, arms, legs, fingers, toes, `head_top`). Roles the skeleton lacks are listed in `bones.absent`; a stage that cannot build records why in `bones.degraded` and declines instead of crashing. Check `rig_bones_test` and `rig_profile_test`.
4. Build the character scene as above. The feet are at the visual's origin (the foot-point convention): do not offset the scene; the host composes it (`TacticalUnit` places it `standing_height` below its origin; `presenter.foot_point_problems()` checks the basis).
5. Tune with the workbench (below) and the pose trace.

### A second humanoid (Task 09): what a new character takes

The small medabot-style robot (`art/characters/small_mira_0/`) runs on the same `CharacterRig`, `CharacterPresenter`, modifiers and hosts as MIRA. Its whole difference is data: a model with fixed skinning (`models/small_mira_0.glb`), a rig profile (`small_mira_0_rig_profile.tres`: the same Mixamo role map, `character_scale = 1.2`, so the mesh stands 1.20 m), a weapon handling profile (`small_mira_0_weapon_handling.tres`), and three scenes in `runtime/` (`small_mira_0_rig.tscn`, `_exploration_visual.tscn`, `_unit_visual.tscn`), copied from MIRA's with the character-local numbers in the rig scene scaled by the leg ratio (0.70: arm IK elbow guides, hand-target markers, shoulder contact offset; the handling profile's lowered grip, ready clearance, sling offset and weapon scale). Its anatomy against MIRA (skeleton heights; the mesh with its ears is 1.20 m): stature 1.06 m vs 1.62 m, leg 0.54 m vs 0.77 m (thigh 0.26/shin 0.28 vs 0.39/0.38), torso 18% shorter against its leg, feet 36% longer against its leg, shoulder width 12% wider against hip width, upper arm 10% shorter against its forearm.

What is shared, what is per character:
- **Shared behaviour** (code): the presenter and its arbitration, the locomotion clips (angle tables), the leg and arm IK, the crouch and kneel solvers, the foot stage, the stair planner, the weapon pose, the action handles.
- **Per-character configuration** (data): bone names and roles (profile), anatomy and sockets (profile), weapon handling (grips, lowered grip, ready clearance, sling, scale), arm IK guide positions and hand-target markers (rig scene), camera anchors (unit scene). The measured anatomy (leg, ankle, hip joints, foot size) is never configured: the rig measures it from the skeleton at build.
- **Presentation style**: the locomotion profile (speed thresholds are context policy and stay in m/s; the stride is authored on the reference body).
- **Reference-body lengths**: a few shared lengths in metres were authored for MIRA (stride, pelvis bob and sway, the exploration crouch depth, the wary cover bend, the stair stance roll, heel lift, swing lift, margins and step rise, the crouch balance and kneel constants). They stay in metres for the reference body (`RigBones.REFERENCE_HIP_TO_ANKLE`) and a body scales them by `RigBones.body_ratio` / `CharacterRig.body_ratio()` (its hip-joint-to-ankle height over the reference's; 1 for MIRA, 0.70 for the robot). Depths derived from the world (low cover) are not scaled. The crouch also corrects only a body's DIFFERENCE from the reference rest lean of the legs, so MIRA's tuned poses are unchanged.

Required roles: the hips, the spine to the head, both arms (upper, lower, hand) and both legs (upper, lower, foot). Optional: toes (the foot stage then uses a default foot length), fingers (the hand grip declines and reports it), upper chest, head top. A missing required bone is a resolver error naming the role; a missing optional one is listed in `bones.absent` and the stage that needs it in `bones.degraded`. Equipment compatibility is configuration: the robot draws the same rifle model at 0.57 scale through its own handling profile; an item that cannot be made to fit gets no handling profile instead of a forced pose. The workbench takes `--character=small_mira_0` (or the `character` export): the same host, panel and diagnostics, cameras scaled by the body ratio. Tests: `humanoid_portability_test` (body-relative, with negative controls for the stride scaling and the crouch rest-lean correction, a renamed-bone fixture through the full rig, missing optional anatomy, a required-bone diagnostic) and `posture_body_scale_test`; renders: `tests/humanoid_portability_capture.gd`.

## Equipment and unarmed characters

Equipment is chosen by the scene, never by the rig. `weapon_scene` is null by default: a rig with none initialises, moves, crouches, climbs, carries and is defeated on the same stack, with relaxed arms (`apply_relaxed_hand_targets`: hands hang by the thighs with a neutral wrist, cleared of the thigh by `HAND_THIGH_CLEARANCE`). `rig.has_weapon()` and `rig.equipment_state()` (NONE, HELD, SLUNG) are the truth; readiness is STOWED and an attack request settles SKIPPED without a shot clip. To equip, assign `weapon_scene` (a model with `SupportHandTarget` and `MuzzleSocket` nodes) and a `WeaponHandlingProfile`. No placeholder weapon exists. Tests: `unarmed_humanoid_test`, `unarmed_hand_clearance_test` (mesh penetration, not joint distance).

## Stairs: foot placement and the stance motion

Both contexts use the same stair planner (`motion/stair_foot_planner.gd`, tuned by `StairProfile`): the feet are planned on the treads (one hold per tread at walking pace, every second at speed), alternate left and right, and the pelvis is placed from the feet. With `stance_motion_enabled` (the default) a planted foot is not nailed to one point: through its stance it rolls (the ankle drifts forward by `stance_roll` and the heel comes up by `heel_lift` toward toe-off), where it lands varies a little per tread (`placement_variation`, deterministic: the same every time for the same tread), and the pelvis shifts sideways toward the supporting foot (`pelvis_sway`). It is a pure function of where the body is along the stair, so replay and frame rate are unaffected. Switching it off reproduces the earlier locked-foot behaviour exactly (the tactical pose trace is identical with it off). ### Stairs: terrain contact, foot orientation and balance

The planner knows the rig's real anatomy: `CharacterRig._measure_stair_anatomy` fills the `StairProfile` copy it owns (leg length hip joint to ankle, ankle height above the sole, hip joint offset, foot front/back/half-width) from the skeleton's rest pose through the profile's roles, so no bone names or proportions live in the planner. Reach and knee-fold are measured from the hip JOINTS, not the pelvis origin (`StairFootPlanner.hip_joint`); a window narrower than `REACH_TOLERANCE` (1.5 cm, inside the legs' real 2.3 cm slack) is met in the middle. Feet follow the body across the stair (`lateral_follow_enabled`) and stay wholly on their tread and inside its width (`tread_clamp_enabled`: heel and toe margins, orientation-aware). As the body slows, the gait's feet blend into a terrain stance (`StairFootPlanner.stance_foot`, `contact_foot`, `settle_enabled`): each foot stands on the tread under it, so a stop, a turn across the stair or a body on a riser line settles onto valid treads instead of freezing the stride. The leg IK only places the ankle; `TraversalFootModifier` (stage `TraversalFoot`, right after `TraversalLegIK`, owns foot rotation only) turns each planted foot flat to the tread, heel up by the planner's lift, and a swing foot part way (before it, the shin leaned the foot toes-down and the ball sat 4-5 cm in the tread). Nothing is written when no stair pose is active. Tests: `stair_contact_test` (pure planner plus a rig stopped half way up at the centre and the edge, with negative controls for the lateral follow, the tread clamp, the settle and the foot stage); render: `tests/stair_contact_capture.gd`. Known limits: steep (0.5 m) risers pull the swing foot in up to 12 cm; running is walked on stairs; the foot stage levels the foot but does not plan toe clearance beyond the planner's lift.

A crouch is suspended on stairs and ladders and a run is walked on stairs in the exploration host, because the stair pose owns the legs and the pelvis there. Tactical stairs are ridden kinematically along the route and have no collision; the sandbox staircase has solid treads that are ignored while she is on them.

## Cosmetic effects outside the action lifecycle

These are deliberate and stay outside `CharacterPresenter`'s lifecycles because nothing waits on them and they cannot affect gameplay: the team ring and class marker (`TacticalCharacterAdapter`), the muzzle flash and shot-feedback timer (`CharacterRig`), the passenger's presence fade while boarding (`present_boarding`), the stow blend and carry sway, and, for a standalone rig only, the sights tween (`aim_blend_follows_clips`). Move one into the presenter only if its ownership causes a real timing or lifecycle problem.

## Held Aim pose

A committed Aim keeps the sights up for as long as it lasts: until its attack, an action that cancels it (a Move), a Reload, or the next activation. `TacticalCharacterAdapter` follows the committed `tactical_state.is_aiming` flag (translated into `presenter.aim_committed`) and the presenter's `AimHold` keeps a short release grace so the rifle does not dip while the attack camera moves in. A carrying unit never raises a rifle; a shot, hit, defeat, move or traversal is never interrupted. Test: `aim_hold_presentation_test`.

## Running and testing

Run from the repository root (`godot_console` is the console build of Godot 4.7):

```powershell
.\tools\run_tests.ps1 fast -Subsystem animation      # the animation FAST tier (about 90 s)
.\tools\run_tests.ps1 changed -Since HEAD            # tests selected by what changed
.\tools\run_tests.ps1 select -Test pose_ownership_test
.\tools\run_tests.ps1 check                          # catalog consistency
```

Equivalence evidence for any structural change (compare before and after with the scratch comparison scripts or by diffing the JSON): the deterministic pose trace (39 scenarios) and route trace (853 routes), and the performance baseline.

```powershell
godot_console --headless --fixed-fps 60 --path . --script res://tools/quality/pose_trace.gd -- pose.json
godot_console --headless --path . --script res://tools/quality/route_trace.gd -- route.json
godot_console --headless --path . --script res://tools/quality/animation_perf_baseline.gd
godot_console --headless --path . --script res://tools/quality/script_warning_audit.gd
```

The workbench: open `tools/animation_workbench/pose_workbench.tscn` and press F6 (it shows MIRA with the locomotion test panel, the cover, ladder and stair benches, hand diagnostics on `H`, pose presets on `Z`). Rendered evidence scripts need a display: `tests/unarmed_capture.gd`, `tests/pose_review_capture.gd`, `tests/weapon_readiness_capture.gd` (see each script's header). Headless success does not establish visual correctness: inspect a render after pose changes.

Contracts to know before editing: `animation_module_boundaries_test` (module and composition ratchets), `pose_ownership_test`, `animation_cleanup_test` and `action_handle_test` (teardown and handle settling), `presentation_frame_driver_test` (once per frame), `modifier_boundary_test`, `traversal_*` tests, `rescue_*` tests.

## Known limits and future work

Not done and not required by the current architecture: an arm swing for unarmed walking; general body self-collision (the unarmed hands only clear the thigh); the carry clip's upper-arm track (removed because it never applied; restoring it is an animation decision); a second humanoid's own art polish and gait style (the robot reuses MIRA's angle tables, only stride and pelvis motion scale; its baked Tripo clips are unused); an inspection that reaches with a hand (the exploration inspect is a turn-and-bend, no hand IK); broader capability, traversal and workbench-diagnostics work (Tasks 10 to 12).
