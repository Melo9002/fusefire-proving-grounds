# Human editing map

Use this page when you know what you want to change but not where FuseFire owns it.

| Goal | Edit here | Verify with |
| --- | --- | --- |
| Replace the character or weapon | Open `art/characters/mira_0/runtime/mira_0_unit_visual.tscn`; change **Model Assets** on its root | `tests/unit_visual_adapter_test.gd` and a local battle |
| Edit animation clips | Assign a library under **Model Assets → Clip Library** on the MIRA runtime scene | Animation workbench, then `tests/unit_visual_adapter_test.gd` |
| Tune hands, sight, stock, shoulder, or carry offsets | **Weapon Contact**, **Low Ready**, and **Rescue Carry** on the adapter root | `art/characters/mira_0/demo/mira_0_pose_workbench.tscn` |
| Change Attack, Move, Wait/Defend, Rescue, or Extract sequencing | The matching plainly named method in `presentation/actions/tactical_action_presenter.gd` | `tests/tactical_action_presenter_test.gd` plus the relevant replay test |
| Change friendly, ally, enemy, or neutral accents | `presentation/team_presentation_palette.tres` | `tests/unit_visual_adapter_test.gd` and a local battle |
| Disable a unit's floating battle HUD in an isolated tool or fixture | Turn off **Presentation → Show World Hud** on `TacticalUnit`; keep the HUD scene assigned so enabled units still validate their dependency | Presenter or locomotion fixture using the unit |
| Change cursor, movement/path, cover, objective, shot, or selection markings | `levels/prototype_map/prototype_map.tscn` → **Visualizers**; each visualizer exposes its colors and dimensions | `tests/battle_smoke.gd` and a local battle |
| Match foot speed to a new walk cycle | **Locomotion → Stride Length** on the adapter; **Gameplay → Movement Speed** on the unit | Locomotion demo and a local battle |
| Tune shot, hit, landing, or pickup return timing | **Action Timing** on the adapter root | `tests/unit_visual_adapter_test.gd` |
| Change movement range, HP, or AP | `units/tactical_unit.tscn` → `UnitStats` | Core battle/objective smoke tests |
| Change weapon range or world movement speed | `units/tactical_unit.tscn` root → **Gameplay** | `tests/battle_smoke.gd` |
| Change Attack legality, cover, obstruction, range, or hit chance | `systems/combat_rules.gd`; activation/AP/revision checks remain in `systems/actions/runtime/tactical_action_service.gd` | `tests/tactical_action_service_test.gd` and combat cover/elevation/trajectory tests |
| Change the prediction facts available to UI and AI | `systems/actions/runtime/attack_query_result.gd`, populated by `TacticalActionService.query_attack()` | `tests/tactical_action_service_test.gd` |
| Change attack-preview wording or AI preference | UI text: `BattleController._update_attack_preview`; button state: `ui/action_hud_controller.gd`; AI preference: `systems/ai/ai_target_scorer.gd` | Battle smoke plus AI target/determinism tests |
| Change movement legality or AP/revision checks | `TacticalActionService.query_move()` and `BattleController._query_move_data()` | `tests/tactical_action_service_test.gd` plus movement smoke tests |
| Change Wait or legacy Defend availability and AP behavior | `TacticalActionService.query_simple()` / `submit_simple()` | `tests/tactical_action_service_test.gd` |
| Change Rescue or Extract eligibility and objective effects | Domain rules: `systems/objectives/objective_manager.gd`; shared availability/transaction boundary: `TacticalActionService.query_mission()` / `submit_mission()` | `tests/core_objectives_smoke.gd` plus rescue, departure, and battle replay tests |
| Change which mission interactions AI prefers | `units/ai_controller.gd`; it consumes `BattleController.query_mission()` for legality | Mission AI and evacuation tests |
| Change how player input becomes an action request | The plainly named `try_attack`, `try_move`, `try_simple_action`, and `try_mission_action` adapters in `systems/battle_controller.gd` | `tests/tactical_action_service_test.gd` plus the relevant battle smoke test |
| Change action lifecycle or the input/presentation barrier | `systems/actions/runtime/tactical_action_service.gd`; `BattleController.is_action_in_progress` is a read-only view of this service | Tactical action service and presenter tests |
| Change extraction's authoritative roster or occupancy effects | `systems/objectives/objective_manager.gd`; visual disposal after boarding lives in `presentation/actions/tactical_action_presenter.gd` | Core objectives plus departure and rescue replay tests |
| Change turn or phase progression | `systems/turn_manager.gd`; action completion is observed through the service barrier in `systems/battle_controller.gd` | Tactical action turn-progression fixture plus AI and replay tests |
| Change mission-departure replay recording | `ObjectiveManager.authoritative_command_committed` and `systems/replay/battle_replay_recorder.gd` | Departure replay and replay schema tests |
| Change reachability, route cost, diagonal, or corner rules | `systems/grid/pathfinder.gd`; terrain stoppability and traversal links come from map data | Diagonal, elevation, vault, and vertical traversal tests |
| Change occupancy commitment | `systems/grid/grid_manager.gd`; Move commits through `TacticalActionService.submit_move()` | Tactical action service and replay tests |
| Change player path/range display | `BattleController.update_unit_movement_zone()` and `_update_movement_preview()` consume the shared Move query | `tests/battle_smoke.gd` |
| Change AI movement preference | `units/ai_controller.gd` and `systems/ai/ai_position_scorer.gd`; legal active-turn destinations come from the shared Move query | AI determinism, mission AI, and evacuation tests |
| Tune tactical camera movement and zoom | `levels/prototype_map/prototype_map.tscn` → `CameraRig` | `tests/action_camera_director_test.gd`, `tests/camera_obstruction_test.gd`, and manual close/far zoom |
| Inspect an AI choice | Enable F3 AI decision/scoring overlays during AI control | `tests/ai_match_determinism_smoke.gd` |
| Reproduce an AI match | Use a fixed seed in Match Setup | See `simulation.md` |
| Start a battle from code | Fill a `BattleConfiguration`, then call `BattleLevel.configure_battle()` | `tests/match_setup_smoke.gd` and `tests/battle_replay_smoke.gd` |
| Inspect or extend replay records | `systems/replay/battle_replay_recording.gd` for the envelope and the action result's `to_replay_record()` | `tests/replay_schema_test.gd` plus the relevant end-to-end replay |

## Asset contracts

A replacement humanoid must contain a `Skeleton3D` compatible with the current
MIRA Zero humanoid mapping. A replacement weapon must contain `SupportHandTarget` and
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
