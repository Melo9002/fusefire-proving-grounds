# presentation/characters

Shared humanoid character presentation. Nothing here may import gameplay, tactical, exploration or base types (`animation_module_boundaries_test` enforces it). The full guide is [`docs/animation.md`](../../docs/animation.md).

| Folder | Holds | Depends on |
| --- | --- | --- |
| `presenter/` | `CharacterPresenter` (time, facing, postures, action lifecycles), `ActionHandle`, `PostureArbiter`, `WeaponReadiness`, `RescueInteraction` | `motion/`, `equipment/` data only |
| `rig/` | `CharacterRig`, `RigBones`, animation controller, clip builder, passenger and attachment helpers, typed pose state | `rig_profile/`, `motion/`, `equipment/`, `presenter/` types |
| `rig/modifiers/` | the pose stages (Locomotion, CoverCrouch, Traversal, WeaponPose, HandGrip) and `PoseOwnership` | typed inputs only; never the rig or the presenter |
| `rig_profile/` | what the body is: roles, anatomy, joints, sockets, resolver (pure data) | Godot native types only |
| `motion/` | profiles, gait tables, pure solvers (ladder, stairs, paths), `CoverPostureProfile` | nothing above it |
| `equipment/` | `WeaponHandlingProfile`, `EquipmentPresentation` | `rig_profile/` sockets |

A context host (`presentation/tactical/TacticalCharacterAdapter`, `presentation/exploration/ExplorationCharacterHost`, `tools/animation_workbench/`) composes a `CharacterRig` and drives it and its presenter once per frame.
