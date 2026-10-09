# Human editing map

Use this page when you know what you want to change but not where FuseFire owns it.

| Goal | Edit here | Verify with |
| --- | --- | --- |
| Replace the character or weapon | Open `art/characters/mira_0/runtime/mira_0_unit_visual.tscn`; change **Model Assets** on its root | `tests/unit_visual_adapter_test.gd` and a local battle |
| Edit animation clips | Assign a library under **Model Assets → Clip Library** on the MIRA runtime scene | Animation workbench, then `tests/unit_visual_adapter_test.gd` |
| Tune hands, sight, stock, shoulder, or carry offsets | **Weapon Contact**, **Low Ready**, and **Rescue Carry** on the adapter root | `art/characters/mira_0/demo/mira_0_pose_workbench.tscn` |
| Change Attack, Move, Wait/Defend, Rescue, or Extract sequencing | The matching plainly named method in `presentation/actions/tactical_action_presenter.gd` | `tests/tactical_action_presenter_test.gd` plus the relevant replay test |
| Change friendly, ally, enemy, or neutral accents | `presentation/team_presentation_palette.tres` | `tests/unit_visual_adapter_test.gd` and a local battle |
| Change cursor, movement/path, cover, objective, shot, or selection markings | `levels/prototype_map/prototype_map.tscn` → **Visualizers**; each visualizer exposes its colors and dimensions | `tests/battle_smoke.gd` and a local battle |
| Match foot speed to a new walk cycle | **Locomotion → Stride Length** on the adapter; **Gameplay → Movement Speed** on the unit | Locomotion demo and a local battle |
| Tune shot, hit, landing, or pickup return timing | **Action Timing** on the adapter root | `tests/unit_visual_adapter_test.gd` |
| Change movement range, HP, or AP | `units/tactical_unit.tscn` → `UnitStats` | Core battle/objective smoke tests |
| Change weapon range or world movement speed | `units/tactical_unit.tscn` root → **Gameplay** | `tests/battle_smoke.gd` |
| Tune tactical camera movement and zoom | `levels/prototype_map/prototype_map.tscn` → `CameraRig` | `tests/action_camera_director_test.gd`, `tests/camera_obstruction_test.gd`, and manual close/far zoom |
| Inspect an AI choice | Enable F3 AI decision/scoring overlays during AI control | `tests/ai_match_determinism_smoke.gd` |
| Reproduce an AI match | Use a fixed seed in Match Setup | See `simulation.md` |
| Start a battle from code | Fill a `BattleConfiguration`, then call `BattleLevel.configure_battle()` | `tests/match_setup_smoke.gd` and `tests/battle_replay_smoke.gd` |

## Asset contracts

A replacement humanoid must contain a `Skeleton3D` with the current VRoid
`J_Bip_*` bone names. A replacement weapon must contain `SupportHandTarget` and
`MuzzleSocket` nodes. These contracts are checked when the runtime rig assembles.

The detailed model and animation procedures remain in `asset-import.md` and
`animation-editing-guide.md`. Authored clips in `prototype_clips.tres` are the
normal editing path; `character_fallback_animation_builder.gd` only supplies
safe placeholder clips when an authored clip is missing. Do not edit `.godot/`
or generated import files.

## Battle setup from code

Use `systems/battle_configuration.gd` when a menu, simulation, or tool starts a
battle. Its named fields make team counts, map settings, mission, difficulty,
and seed visible at the call site. `BattleLevel.configure()` remains only as a
compatibility wrapper for older Prototype 1 scripts.

## What remains runtime-built

The selected imported model supplies its `Skeleton3D`. Godot requires the weapon
bone attachment and two-bone IK solver to become children of that skeleton, so
the rig creates those model-dependent nodes after loading. Stable composition—IK
targets and the animation controller—remains visible in the runtime and demo
scenes. This boundary keeps model swapping possible without hiding ordinary
editable structure in code.
