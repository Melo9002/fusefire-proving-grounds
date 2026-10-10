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
| Tune a roster archetype's Supply Point capacity | Open its `.tres` file under `units/archetypes/` and edit **Max Supply Points**; each spawned unit receives independent current/max values | `tests/tactical_archetype_lab_test.gd` and `tests/supply_reload_test.gd` |
| Change Attack legality, cover, obstruction, range, or hit chance | `systems/combat_rules.gd`; activation/AP/revision checks remain in `systems/actions/runtime/tactical_action_service.gd` | `tests/tactical_action_service_test.gd` and combat cover/elevation/trajectory tests |
| Change Attack SP cost or Reload legality/AP cost | Named `query_attack()`, `submit_attack()`, `query_reload()`, and `submit_reload()` paths in `systems/actions/runtime/tactical_action_service.gd` | `tests/supply_reload_test.gd` plus battle replay and AI determinism |
| Change Reload camera/animation/feedback | `TacticalActionPresenter.present_reload()`; it receives committed AP/SP facts and must not mutate them | `tests/supply_reload_test.gd` and `tests/tactical_action_presenter_test.gd` |
| Change Reload HUD wording or basic AI preference | `ui/action_hud_controller.gd` for display; `AIController._try_reload_if_useful()` for preference | `tests/supply_reload_test.gd` and AI determinism |
| Change Aim cost, legality, or cancellation | `TacticalActionService.query_aim()` / `submit_aim()` and the small `_cancel_aim()` commit helper | `tests/aim_tactical_state_test.gd` |
| Change Aim bonus or its attack calculation | `TacticalState.AIM_ACCURACY_BONUS`; `TacticalActionService.query_attack()` passes it once to `CombatRules.evaluate_attack()` | Aim test plus combat cover/elevation tests |
| Change Aim lifetime | `units/components/tactical_state.gd`; `TurnManager._set_active_unit()` supplies the round/phase activation token | Aim test plus replay and AI determinism |
| Change Aim HUD, presentation, or AI preference | `ui/action_hud_controller.gd`, `TacticalActionPresenter.present_aim()`, and `AIController._try_aim_for_attack()` | Aim test, presenter test, and AI determinism |
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
seed, and per-slot archetypes visible at the call site. `BattleLevel.configure()` remains only as a
compatibility wrapper for older Prototype 1 scripts.

## Tactical archetypes and the roster laboratory

Testing archetypes live in `units/archetypes/` as ordinary `.tres` Resources. Open one in Godot to edit its display name, description, starting stat overrides, or demonstrated capability fields. `generic.tres` preserves the existing baseline; Shieldbearer, Marksman, Sentinel, and Support are laboratory presets rather than permanent classes. Only Shieldbearer currently declares a capability, and that declaration grants no defensive bonus before Task 01.11.4.

To add another test archetype:

1. Duplicate one of the `.tres` definitions and give it a unique `archetype_id`, name, and truthful description.
2. Add the Resource to `TacticalArchetypeCatalog.DEFINITIONS` in `units/archetypes/tactical_archetype_catalog.gd`.
3. Add focused catalog, configuration, and spawn coverage. Do not store current HP, AP, SP, or tactical state in the shared Resource.

Supply Points are the prototype's limited normal-attack supply, not a general energy or stamina pool. The current defaults are 4 maximum/current SP, 1 SP per normal Attack, and a 1 AP Reload that restores the reserve to maximum. Runtime values live on the unit's `UnitStats`; changing one unit cannot mutate its shared archetype Resource. The action HUD reads the same Attack and Reload queries used by AI, while committed changes come only from `TacticalActionService`.

Aim is independent per-unit runtime state in the `TacticalState` child of `TacticalUnit`. It costs 1 AP and adds 15 percentage points before the existing accuracy clamp. The next accepted normal Attack consumes it on hit or miss; accepted Move, Reload, Wait/Defend, Rescue, or Extract cancels it. Rejected actions leave it untouched. Aim survives AP exhaustion and expires immediately before that actor's first action query in its next round/faction-phase activation. The component is the discoverable home for future explicit stance fields, but it is intentionally not a generic effect system.

The existing Match Setup **Forces** tab owns roster selection. Its three counts synchronize the Player, Enemy, and AI Ally arrays in `ui/match_setup.gd`; new slots start Generic and removed slots come from the end. `BattleConfiguration` carries those IDs through replay reconstruction, and `BattleLevel._create_unit()` resolves and applies the preset before adding the unit to the scene tree. Faction, AI ownership, stable tactical ID, and mission roles remain separate concerns.

Future mechanics should query a concrete capability on the unit, never compare the archetype ID. Add capability data only when its mechanic is implemented. The proposed drone-swarm archetype is a future idea and is not part of the current catalog.

## What remains runtime-built

The selected imported model supplies its `Skeleton3D`. Godot requires the weapon
bone attachment and two-bone IK solver to become children of that skeleton, so
the rig creates those model-dependent nodes after loading. Stable composition—IK
targets and the animation controller—remains visible in the runtime and demo
scenes. This boundary keeps model swapping possible without hiding ordinary
editable structure in code.
