# Character animation: architecture and developer guide

The maintained guide to FuseFire's humanoid presentation. It describes the code as it is after Task 07. The dated reports in [`docs/claude/`](claude/README.md) (audits, the Task 02 to 06 designs, the Package 1 to 10 migration reports) are history; read this page for the current shape.

## The picture

Gameplay decides what happens and owns authority (AP, cells, occupancy, legality, movement completion, damage, objectives, replay). A **context host** turns the game's (or a tool's) state into presentation requests. One shared **presenter** per character owns presentation time and intent. A **rig** applies poses to the skeleton. Presentation may change transforms, poses, effects and timing; it never changes HP, AP, occupancy, line of sight, legality or replay outcomes.

```
 gameplay (TacticalUnit, systems/)            authoritative, knows nothing of poses
        |  reads / calls present_*()
 context host   TacticalCharacterAdapter  (tactical)      reads tactical state, chooses requests, cover policy
                PoseWorkbench             (tools)         controls and benches
                a probe / test            (anything)
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
presentation/tactical/          the tactical host and its policy: TacticalCharacterAdapter, TacticalActionPresenter, CoverEdgeSelector,
                                CoverEdgePolicy, TacticalPoseContext, TacticalRouteBuilder
presentation/diagnostics/       hand-contact diagnostics (read the rig, never write it)
tools/animation_workbench/      the pose workbench (pose_workbench.tscn) and its locomotion test panel
tools/quality/                  pose_trace, route_trace, animation_perf_baseline and probes
art/characters/mira_0/          model, rig profile (mira_0_rig_profile.tres), runtime/mira_0_unit_visual.tscn (the production character)
tests/                          flat; tagged in tests/catalog.json
research/                       evidence only: host probe, update-order probe, exploration playground
```

Modifier order (declared in `PoseOwnership`, checked by `pose_ownership_test`): Locomotion, CoverCrouch, Traversal, TraversalLegIK, WeaponPose, WeaponArmIK, HandGrip. IK results are valid only at `skeleton_updated`, not between updates.

## How a context host uses CharacterPresenter

1. Add a scene with a host `Node3D` and a `Rig` child (a `CharacterRig` with `character_scene`, `rig_profile`, optional `weapon_scene`). See `art/characters/mira_0/runtime/mira_0_unit_visual.tscn` for the production shape.
2. In the host, resolve the rig (`rig`, `presenter = rig.presenter`) and, before it builds, set `rig.loaded_query` (when the context says the character is a loaded carrier) and `rig.aim_blend_follows_clips` (false if the host drives readiness itself). The tactical adapter does this in `_enter_tree`.
3. Each frame, in this order: feed motion (`presenter.set_movement_authority`, `report_velocity` or `set_scripted_motion`), `presenter.tick(delta)`, any host policy (posture requests via `presenter.postures`, `presenter.apply_posture`), `presenter.advance_actions(delta)`, then `rig.update_weapon_pose()`. The presenter advances exactly once per frame; `presentation_frame_driver_test` checks it.
4. Ask for actions through the presenter and rig (`begin_pickup`, `begin_release`, attack, hit, defeat) and await the returned `ActionHandle` (COMPLETED, SKIPPED, INTERRUPTED, CANCELLED). A handle describes the visual operation only; gameplay outcomes never depend on it.
5. Read `presenter.intent()` for the character's persistent state (posture, facing, equipment, readiness) when something else needs it.

`TacticalCharacterAdapter` is the worked example; `tools/animation_workbench/pose_workbench.gd` is the smallest. Nothing in the shared module may import gameplay.

## How to add or configure a humanoid rig

A rig is configured entirely by its profile; no skeleton bone name appears in production code (ratcheted).

1. Import the model (a glb with a `Skeleton3D`). Keep its path stable once referenced.
2. Create the rig profile (`RigProfile`): a Godot `BoneMap` of the humanoid roles to this skeleton's bone names, the anatomy (head-top bone, standing height measurements) and sockets. `art/characters/mira_0/mira_0_rig_profile.tres` is the reference; `tests/fixtures/rigs/` holds a synthetic skeleton with entirely different names.
3. `RigBones.from_profile` turns it into the typed roles every stage reads (`hips`, `torso`, arms, legs, fingers, toes, `head_top`). Roles the skeleton lacks are listed in `bones.absent`; a stage that cannot build records why in `bones.degraded` and declines instead of crashing. Check `rig_bones_test` and `rig_profile_test`.
4. Build the character scene as above. The feet are at the visual's origin (the foot-point convention): do not offset the scene; the host composes it (`TacticalUnit` places it `standing_height` below its origin; `presenter.foot_point_problems()` checks the basis).
5. Tune with the workbench (below) and the pose trace.

Not done (Task 09): a second humanoid is not part of production yet; the alternate profile is a test fixture.

## Equipment and unarmed characters

Equipment is chosen by the scene, never by the rig. `weapon_scene` is null by default: a rig with none initialises, moves, crouches, climbs, carries and is defeated on the same stack, with relaxed arms (`apply_relaxed_hand_targets`: hands hang by the thighs with a neutral wrist, cleared of the thigh by `HAND_THIGH_CLEARANCE`). `rig.has_weapon()` and `rig.equipment_state()` (NONE, HELD, SLUNG) are the truth; readiness is STOWED and an attack request settles SKIPPED without a shot clip. To equip, assign `weapon_scene` (a model with `SupportHandTarget` and `MuzzleSocket` nodes) and a `WeaponHandlingProfile`. No placeholder weapon exists. Tests: `unarmed_humanoid_test`, `unarmed_hand_clearance_test` (mesh penetration, not joint distance).

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

Not done and not required by the current architecture: an arm swing for unarmed walking; general body self-collision (the unarmed hands only clear the thigh); the carry clip's upper-arm track (removed because it never applied; restoring it is an animation decision); a second humanoid (Task 09); a non-tactical demonstration (Task 08); broader capability, traversal and workbench-diagnostics work (Tasks 10 to 12).
