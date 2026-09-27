# FuseFire Prototype 1 — Current State

This report describes the repository as inspected on 2026-09-27. Runtime code, scenes, and tests are treated as authoritative. Existing planning language is included only where the implementation supports it.

## 1. Executive Summary

FuseFire Prototype 1 is a deterministic, turn-based 3D tactics sandbox made in Godot 4.7. A player can configure a match, choose force sizes, add AI allies or a VIP, select one of seven mission presets, choose an AI difficulty, select an authored or seeded generated battlefield, and play through the mission with movement, shooting, defending, elevation, cover, extraction, rescue, and objective rules.

The normal phase order is player squad, AI allies, enemies, then the next round. Every combatant has its own HP and AP. The player selects units and actions; allied and enemy units use the same legal gameplay actions through utility-based, objective-aware AI. Debug switches can instead let AI control the player faction or let the player control enemies.

Generated maps include cover formations, containers, buildings, platforms, hills, and vertical traversal. The special refinery uses an authored logical industrial layout inside the procedural map pipeline. All maps are converted into common `MapData`, validated for topology, spawns, traversal, and mission placement, and measured with tactical quality metrics.

Completed battles retain an in-memory action recording. The player can replay the battle from its seed and setup. Replay executes the recorded commands through normal gameplay APIs and checks an authoritative state fingerprint after every action. Playback has pause/play, four speeds, free and action-follow cameras, and a reduced replay UI. It does not yet provide a timeline, rewind, saved replay file, or cinematic camera system.

The prototype uses placeholder bean-shaped units and blockout terrain. It proves the combat, AI, objectives, map representation, procedural generation, simulation, deterministic replay, and debug foundations rather than final presentation or content production.

## 2. Core Gameplay Loop

1. Godot starts at `ui/match_setup.tscn`, controlled by `ui/match_setup.gd`.
2. The player chooses 1–5 player combatants, 1–5 enemies, and 0–5 allied AI combatants. An optional friendly VIP occupies one allied slot, limiting AI combatants to four.
3. The player selects a mission, Easy/Normal/Hard AI, authored or generated map, generated-map size, generic or refinery layout, and a seed. Automatic seed mode generates a new seed; manual mode supports reproduction.
4. `levels/prototype_map/battle_level.gd` instantiates units, assigns an `AIController` to each team unit, creates or scans the battlefield, validates it, creates mission zones, registers units, and starts the battle.
5. During the player phase, the player selects a ready portrait or battlefield unit, then spends AP on Move, Attack, or Defend. Extraction appears on an eligible unit in the correct zone and costs no AP. Rescue can happen when an eligible unit reaches a cell adjacent to the rescue target.
6. Movement uses a weighted 3D A* graph. A move costs 1 AP and may traverse ground, platforms, roofs, stairs, ramps, ladders, bridges, or vault links represented by graph connections.
7. An attack costs 1 AP. It must target a hostile living unit within range and with at least one visible target sample. A deterministic battle RNG resolves the displayed hit chance; a hit inflicts 25 damage before defense reduction.
8. Defend costs 1 AP and halves incoming damage until that unit's next phase refresh.
9. When a player unit reaches 0 AP, selection advances to another ready player unit. The player ends the faction phase manually unless AI controls the player faction. Allies and enemies act one unit at a time and advance automatically.
10. `ObjectiveManager` updates objective progress from movement, rescue, extraction, deaths, and rounds. It ends the battle when required objectives succeed or fail.
11. The result screen exposes **Replay Battle** and **Return to Match Setup**. Esc opens a pausing Resume/Return menu during battle.

There is no implemented SP, ammunition, weapon inventory, reload, or resupply system. Units currently share one prototype attack profile.

## 3. Unit System

### Factions and allegiances

`units/tactical_unit.gd` defines four factions: `PLAYER`, `ENEMY`, `ALLY`, and `NEUTRAL`. `systems/faction_rules.gd` supplies hostility relationships. Player and ally factions cooperate; enemies oppose them; neutral rescue actors are mission objects rather than ordinary combatants.

Every spawned team member uses `units/tactical_unit.tscn` and receives:

- a `TacticalUnit` controller;
- a `UnitStats` component;
- a `MissionActor` component;
- a world-space HP/AP bar;
- an `AIController`, even when normally player-controlled, so AI-vs-AI debug mode can take control.

`MissionActor.Kind` distinguishes combatants, VIPs, and rescuable actors. VIP behavior can be player-controlled, follow an escort, or hold position. Follow Escort is a simple behavior that moves toward the first player escort; Hold Position defends. A rescuable neutral becomes hidden and disabled while carried.

### Current statistics and actions

- HP: 100 maximum and initial.
- AP: 2 maximum and refreshed at the start of the unit's faction phase.
- Movement speed: 5 graph-cost units per Move action.
- Prototype battle attack range: 10 Manhattan grid units, assigned by `BattleLevel.test_battle_attack_range`.
- Move: 1 AP.
- Attack: 1 AP.
- Defend: 1 AP.
- Rescue: no AP cost.
- Extract: no AP cost.
- Attack damage: 25; 12 when the target is defending because `int(25 * 0.5)` truncates.

Carrying a rescued unit reduces speed by 2, with a minimum speed of 2. The carrier and carried actor extract together. No general-purpose pickup/drop, injury, incapacitation, body carrying, class, equipment, weapon, ammunition, or status-effect systems exist yet.

At 0 HP, a unit emits `defeated`, is removed from grid occupancy and the turn roster, and is queued for deletion. Portraits retain a dead presentation state; world bars delete themselves when their unit becomes invalid.

The authored and generated spawn systems both support up to five actors per combat faction. Generated maps store explicit faction spawn cells. Authored maps use `SpawnZone` markers in `levels/prototype_map/prototype_map.tscn`.

## 4. Combat System

Combat legality and accuracy live in `systems/combat_rules.gd`; execution lives in `systems/battle_controller.gd` and `scripts/actions/attack_action.gd`.

### Attack legality

An attack is legal only when:

- attacker and target are valid, alive, hostile units;
- the attacker is the active unit in the correct phase;
- the attacker has at least 1 AP;
- no unit is currently moving;
- Manhattan distance `|dx| + |dy| + |dz|` does not exceed attack range;
- at least one of five target samples has unobstructed geometry.

### Multi-point visibility

The shot origin is the attacker's cell world position plus its `standing_height`. Five target points are sampled relative to the target's standing height: high body/head, upper body, left/right body, and lower body. Segment-versus-cell-volume tests use `MapCellData.cover_height`. The target and attacker cells are ignored as blockers.

Visibility produces these obstruction penalties by visible sample count:

| Visible samples | Obstruction label | Penalty |
| ---: | --- | ---: |
| 0/5 | Blocked; attack illegal | — |
| 1/5 | Heavily obstructed | 50 |
| 2/5 | Heavily obstructed | 40 |
| 3/5 | Partially obstructed | 25 |
| 4/5 | Partially obstructed | 10 |
| 5/5 | Clear | 0 |

### Directional cover and accuracy

Cover is checked in the target-adjacent cardinal direction facing the attacker. Any directional low or full cover currently applies a 50-point cover penalty. Accuracy is:

```text
hit chance = clamp(100 - max(directional cover penalty, obstruction penalty), 5, 100)
```

The two penalties do not stack; the larger one wins. Elevation has no separate numeric high-ground bonus. It matters geometrically through 3D distance, shot origin/destination height, visibility samples, intervening obstacle volumes, and access to firing positions.

The chosen aim point is the first visible sample. The trajectory visualizer colors clear/obstructed/blocked previews and can identify the first blocking cell. On execution, the seeded combat RNG produces a roll in `[0,100)`; `roll < hit_chance` hits. A hit deals 25 damage. Defend halves the damage. There are no critical hits, armor, flanking multiplier, suppression, weapon falloff, damage variance, or reaction fire.

## 5. Turn System

`systems/turn_manager.gd` owns four phases: `PLAYER_TURN`, `ALLY_TURN`, `ENEMY_TURN`, and `TRANSITION`.

At battle start, round 1 begins with the player phase. Player AP and defending state reset, and the first player unit becomes active. Player units may be selected in any order while they have AP. Reaching 0 AP triggers deferred selection of another ready player. A manual End Turn begins the ally phase, or the enemy phase if there are no allies.

Allies and enemies are processed as ordered queues. Each unit receives an active-unit signal, its AI acts until it exhausts AP or chooses to stop, and the queue advances. After the enemy queue, the round increments and a new player phase begins.

Safeguards reject actions when the battle is over, the wrong unit is active, a unit is defeated or moving, another unit is moving, AP is insufficient, a destination is invalid/occupied, a path is absent, or an attack is illegal. End Turn is rejected while any unit moves. Extraction removes a unit safely from its roster and adjusts queue indexes when necessary.

Objective missions disable the turn manager's simple annihilation outcome and let `ObjectiveManager` decide results. Without objective tracking, empty enemy/player rosters produce victory/defeat directly.

## 6. Enemy and Allied AI

### Architecture

Each unit has a local `units/ai_controller.gd`. The controller listens for that unit becoming active. Enemy AI runs during enemy turns; allied AI always runs during ally turns; player-unit AI runs only in AI-vs-AI debug mode. Replay disables ordinary AI entirely.

The AI calls the same `BattleController.try_move`, `try_attack`, `try_defend`, and `ObjectiveManager.try_extract/try_rescue` APIs used by manual play. It does not bypass AP, range, pathfinding, occupancy, line-of-sight, faction, or objective legality.

### Information available

AI has direct access to the current map, all living hostile units, objective state and mission intent, reachable graph cells, attack evaluations, allied reservations, and deterministic decision RNG. This is full-state tactical awareness; fog of war and uncertain perception are not implemented.

### Decision flow

```text
unit becomes active
  -> load difficulty policy, mission intent, and team squad context
  -> reserve intent as an objective handler
  -> if VIP: follow escort when configured, then defend
  -> while AP remains:
       1. perform urgent mission interaction or mission movement
       2. otherwise score every legal attack target and attack the selected target
       3. otherwise score reachable progress toward the nearest hostile
       4. after one move, consider a safe second advance
       5. otherwise defend
  -> advance the faction queue
```

Mission behavior precedes generic combat when it can take a useful step. Rescue AI approaches and picks up the target. Reach and extraction AI seek the relevant zone. A rescue carrier heads to extraction while teammates can stay near it as mobile support. Protect AI returns within an escort radius of three cells. Survive AI prefers cover and separation until the timer completes, then seeks extraction. Enemy evacuation AI uses the enemy extraction zone.

### Target scoring

`systems/ai/ai_target_scorer.gd` scores every legal target using:

- missing HP multiplied by the policy's wounded-target weight;
- a 20-point finishing bonus at 25 HP or less;
- a 25-point VIP value;
- threat, based on legal shots the target has against friendlies, capped at 28;
- mission relevance, including carriers, enemies near evacuation, threats to protected actors/carriers, and occupants near objective zones;
- a soft `-15` per ally already intending to attack that target.

Difficulty policies multiply those components. Easy discounts tactical targeting; Hard emphasizes wounded units, threats, VIPs, and mission relevance. Focus-fire penalties are soft, so several units can still finish an important target.

### Position scoring

`systems/ai/ai_position_scorer.gd` scores reachable cells using:

- path/goal progress, weighted more strongly on objective routes;
- directional cover against each hostile in range (`+4` low, `+7` full before policy weighting);
- exposure to hostile firing lanes (`-14` without cover, `-9` low, `-5` full);
- firing opportunities from the candidate (`+10` against an uncovered target, `+6` against cover);
- close-range danger (`-8` per hostile within two cells);
- crossfire danger (`-9` per incoming lane after the first);
- squad destination adjustments.

The exact same position logic applies to enemy, ally, and debug-controlled player AI. A second Move is allowed when the destination's estimated exposure is within the policy tolerance compared with the current cell.

### Squad awareness

`systems/ai/squad_context.gd` is a per-team, per-round tactical blackboard rather than a commander:

- an exact destination reserved by another unit is rejected with `-1000`;
- a cell adjacent to another reservation receives `-12`;
- intended targets accumulate the soft focus penalty;
- objective handlers are counted so later units can spread or support;
- rescue carriers are treated as mobile protected actors.

Reservations are updated as each unit commits, allowing later activations to react. They reset each round. There are no leaders, formations, multi-turn joint plans, role assignments, or global optimization.

### Difficulty and intentional mistakes

`systems/ai/ai_difficulty_policy.gd` defines Easy, Normal, and Hard as score weights and deterministic lapse policies. Normal has an 8% chance to choose an eligible near-best option within 12 score points. Easy uses 22% within 15 and weaker tactical weights. Hard always chooses the best eligible option and uses stronger tactical weights. The action rules remain identical.

AI decision records expose mission goal, reason, alternatives, squad adjustments, position scores, target scores, and difficulty to the F3 panel and simulation logs.

## 7. Map System

`systems/grid/map_data.gd` is the common logical battlefield format for authored and generated play. It contains cells, zones, faction spawns, traversal links, generated structures, containers, and a line-of-sight blocker index.

`MapCellData` stores grid/world position, walkability, whether a unit may stop, movement cost, elevation, cover type/height, terrain type, hazard type, and line-of-sight blocking. Cover types are none, low, and full. Terrain and hazard fields are typed extension points; the current game does not apply broad terrain or hazard gameplay effects.

`MapGraphBuilder` converts cells and traversal links into the `Pathfinder` A* graph. Ordinary same-level adjacency and explicit vertical/traversal connections coexist. Movement cost limits reachable cells and affects path choice.

### Authored map

`levels/prototype_map/prototype_map.tscn` contains the reusable battle systems plus a hand-built test arena with CSG obstacles, low/full cover, multiple platforms, ladders, a ramp, stairs, an upper deck, and faction spawn markers. `MapBuilder` scans authored features and physics geometry into `MapData`.

### Generated maps

Generated maps begin as fully populated ground grids, then receive faction spawns, cover, structures, elevation, traversal, and objective zones. Their visual geometry is built at runtime by `GeneratedTerrainPresenter`. Available dimensions are 24×20, 32×24, and 40×30.

### Hybrid status

The ordinary generated map is procedural. The authored test map is scene-authored but converted into the same runtime data model. The refinery is hybrid: its large-scale industrial logical layout is fixed in code while cover dressing, containers, spawns, seed, and mission placement use the generated pipeline.

### Validation

`systems/grid/map_validator.gd` checks cell identity and finite coordinates, legal movement/cover state, path nodes, LOS indexing, traversal endpoints/connections, platforms, hills, spawn capacity/uniqueness/connectivity, zones, deployment overlap, mission-zone overlap, and mission reachability. Battle initialization stops on validation failure.

## 8. Refinery Map

The refinery is selected as a special 40×30 generated map. `systems/generation/refinery_layout_builder.gd` supplies its authored logical backbone:

- six industrial equipment footprints;
- six elevated platform/tower surfaces at levels 2, 3, 5, and 6;
- two fixed elevated bridges;
- named equipment areas such as LEACH 01/02, SEPARATION, PRECIPITATION, and reagent vessels.

Equipment footprints block walking and line of sight to authored heights. Platforms add elevated walkable cells; bridges add intermediate elevated cells and traversal metadata. `GeneratedTraversalBuilder` adds access routes such as stairs and ladders. `refinery_presenter.gd` renders box-based industrial vessels, ducts, labels, and pipe runs, while the general presenter renders decks, rails, supports, access structures, containers, and cover.

Seeded faction deployment, extra containers/cover formations, mission zones, objective placement, validation, pathfinding, and quality measurement still occur through the common generation pipeline. Tactically, the refinery offers taller high ground, fixed industrial occluders, bridges, multiple access routes, and denser authored landmarks than generic generated layouts.

## 9. Mission and Objective System

`MissionDefinition` contains ordered `MissionObjectiveDefinition` resources. Runtime `MissionObjectiveState` tracks active/completed/failed status and progress. Definitions specify kind, required/optional status, target amount/IDs, zone, and pursuing faction mask.

### Implemented presets

| Mission | Rules and outcome | Placement and AI |
| --- | --- | --- |
| Eliminate | Required progress for each defeated enemy; victory when all configured enemies are defeated. | AI uses combat behavior and target scoring. |
| Protect | Required Eliminate plus required survival of `FriendlyVIP`; VIP death fails Protect. | Protecting AI stays within roughly three cells; threats to the VIP gain target score. |
| Rescue | Rescue adjacent neutral `RescueTarget`, then extract that carried target. | Target uses the scored rescue spawn; AI approaches, carries, extracts, and supports the carrier. |
| Reach | Enter any cell of the four-cell Reach zone. | Zone is distant from both deployments; AI follows a scored objective route. |
| Survive | Survive three round advances, then extract survivors. | AI prioritizes safer positions before seeking extraction. Extraction is locked until survival completes. |
| Extract | Extract VIPs when configured; ordinary squad extraction is optional. A player may end early after at least one ordinary extraction once VIP requirements are complete. | Friendly extraction zone is deliberately distant; AI navigates and invokes extraction. |
| Enemy Evacuation | Required elimination of all enemies before any escape. The first enemy extraction fails the stop objective; escape count is optional telemetry. | Enemy faction pursues `enemy_extract`; player/allied targeting values enemies near that zone. |

`MissionZonePlanner` creates four-cell Reach, friendly extraction, and enemy extraction zones plus a one-cell rescue spawn. It excludes deployments and previously reserved mission zones. `MissionPlacementEvaluator` requires connectivity and scores route distance, fairness, cover, exit count, and elevation. Reach requires at least 32% of deployment separation from each side. Extraction requires 62% from its pursuing side and 12% from the opponent. Rescue rewards distance from both sides, tactical surroundings, and high elevation.

## 10. Procedural Generation

The generated-map pipeline is:

1. `FlatMapGenerator.generate` creates all level-zero cells and seed-determined player, enemy, and ally spawn rows on opposing edges.
2. `generate_with_cover` uses a derived deterministic RNG stream for layout.
3. Generic maps place buildings, expand building roofs/details, add platforms and hills, then generate vertical access.
4. Refinery maps apply the fixed industrial layout and then generate access.
5. Containers and rotated low/full-cover formations fill legal areas while preserving deployment margins, a central route, structures, traversal columns, and spacing rules.
6. LOS blockers are re-indexed.
7. `MapGraphBuilder` builds the 3D navigation graph.
8. `MissionZonePlanner` evaluates and reserves reachable objective areas.
9. `MapValidator` rejects invalid data before play.
10. `MapQualityEvaluator` reports cover access/fairness, route options/fairness, open-space ratio and clustering, firing-lane lengths, and spawn exposure/fairness.
11. `GeneratedTerrainPresenter` constructs runtime meshes and collision for logical terrain.

Generation is deterministic for a seed and map selection. There is no runtime retry loop visible in `BattleLevel`; invalid generation prevents battle initialization. Batch tests cover many seeds and record failures for reproduction.

The quality score is diagnostic rather than a generation acceptance threshold. Its weighted total is 25% cover, 20% routes, 10% open space, 10% firing lanes, and 35% spawn safety.

## 11. UI and Player Feedback

- Match setup: force counts, optional VIP behavior, seven missions, three AI difficulties, generated-map toggle, three sizes plus refinery, automatic/manual seed, and deployment summary.
- Turn HUD: phase, round context, End Turn state, replay status, result, Replay Battle, and Return to Match Setup.
- Action bar: Move, Attack with current hit preview/reason, and Defend.
- AP HUD: active unit AP.
- Portrait bar: player units with name, HP, AP, READY/SELECTED/EXHAUSTED/DEAD state and click selection.
- World bars: faction-colored HP, AP, carrying state, and contextual Extract button.
- Battlefield feedback: selected-unit outline, grid cursor, movement range/path, cover display, attack range, colored shot trajectory, and objective-zone colors.
- Objective HUD: required/optional objectives, state and progress, plus early-mission completion where legal.
- Pause menu: Esc pauses and offers Resume or Return to Match Setup.
- Debug UI: F3 exposes map/unit/mission data, AI decisions and scores, AI-vs-AI/manual-enemy controls, and mission manipulation tools. This is intentionally development-facing.

Replay hides the tactical action, AP, portrait, objective, world-bar, and debug UI. Its dedicated bar provides action progress, pause/play, 0.5×–4× speed, Free/Follow Action camera selection, and Return to Setup. This is a clean playback foundation rather than a full photo mode.

## 12. Architecture

```text
MatchSetup
  -> BattleLevel (composition/spawning/map choice/replay entry)
       -> BattleController (legal actions, combat RNG, selection, path previews)
       -> TurnManager (phase, active unit, rosters, AP refresh, result)
       -> ObjectiveManager (mission intent, progress, extraction, outcome)
       -> GridManager + MapData + Pathfinder
            -> authored MapBuilder OR generated FlatMapGenerator
            -> MapValidator / MapQualityEvaluator
       -> one AIController per team unit
            -> AIDifficultyPolicy
            -> AIPositionScorer / AITargetScorer
            -> shared SquadContext
       -> UI and visualizers through signals
       -> ReplayRecorder OR ReplayPlayer
```

The main deliberate separations are:

- action legality/execution versus UI input;
- logical `MapData` versus authored/generated visual presentation;
- mission definitions versus runtime objective state;
- AI scoring policy versus shared combat rules;
- per-unit AI versus lightweight squad context;
- replay command recording versus deterministic battle reconstruction;
- simulation harness versus ordinary playable battle composition.

Signals connect turn, combat, objectives, portraits, world bars, debug tools, and replay recording. Mission and map data use Resources/ref-counted data rather than being hard-coded solely into UI scenes.

## 13. Data and Extensibility

Implemented extension points include:

- `MapCellData` terrain, hazard, cover, elevation, movement cost, walkability, and LOS fields;
- typed traversal data for stairs, ramps, ladders, vaults, and bridges;
- `MissionDefinition`/`MissionObjectiveDefinition` data for objective composition and faction pursuit;
- `MissionActor` kinds and VIP behavior;
- `UnitAction` subclasses and controller entry points;
- difficulty policies as weights without changing legal rules;
- independent AI position, target, mission-intent, and squad-context layers;
- deterministic seed/configuration capture;
- replay action dictionaries plus fingerprints;
- generated building/platform/hill/traversal records separated from their presenter;
- map validators, quality reports, simulations, and seed-failure JSON.

These are structural extension points, not proof that arbitrary weapons, hazards, classes, status effects, or new objective behaviors already work.

## 14. Tests and Validation

The repository contains 45 headless GDScript smoke tests under `tests/`.

### Battle, UI, and lifetime

- `battle_smoke.gd`, `battlefield_layout_smoke.gd`, `battlefield_stress_smoke.gd`: battle setup and larger layouts.
- `match_setup_smoke.gd`, `battle_pause_menu_smoke.gd`: configuration and pause flow.
- `portrait_bar_smoke.gd`, `unit_world_bar_lifetime_smoke.gd`: portrait state and UI cleanup.
- `debug_tools_smoke.gd`: development controls.

### Combat and traversal

- `combat_cover_smoke.gd`: cover, visibility, accuracy, and damage behavior.
- `elevation_smoke.gd`, `elevation_selection_smoke.gd`, `elevation_combat_smoke.gd`: elevated movement/selection/fire.
- `vertical_traversal_smoke.gd`, `vault_smoke.gd`: explicit traversal paths.

### Maps and generation

- `map_data_smoke.gd`, `flat_map_generator_smoke.gd`, `container_maps_smoke.gd`.
- `generated_buildings_smoke.gd`, `generated_elevation_smoke.gd`, `generated_traversal_smoke.gd`, `generated_mission_placement_smoke.gd`.
- `map_validation_smoke.gd`, `map_generation_batch_smoke.gd`, `map_quality_metrics_smoke.gd`.

### Objectives and factions

- `objective_foundation_smoke.gd`, `core_objectives_smoke.gd`, `mission_actor_smoke.gd`.
- `allied_faction_smoke.gd`, `enemy_evacuation_smoke.gd`.
- `objective_ai_navigation_smoke.gd`, `protect_rescue_ai_smoke.gd`, `rescue_carrier_support_smoke.gd`, `survive_ai_smoke.gd`.

### AI

- `ai_mission_intent_smoke.gd`, `ai_position_scoring_smoke.gd`, `ai_target_scoring_smoke.gd`.
- `ai_difficulty_policy_smoke.gd`, `ai_intentional_mistakes_smoke.gd`, `ai_second_advance_smoke.gd`.
- `squad_context_smoke.gd`.
- `ai_match_simulation_smoke.gd`, `ai_match_determinism_smoke.gd`.

### Replay and reproducibility

- `battle_replay_smoke.gd`: complete deterministic action replay with per-action fingerprints.
- `rescue_battle_replay_smoke.gd`: exact 5v5 + two-allies rescue/carry/extract regression at seed 372339682.
- `seed_failure_report_smoke.gd`: reproducible JSON failure reports.

In addition to tests, runtime map validation blocks invalid battles, map quality logs characterize layouts, the F3 panel inspects live state, AI simulation runs full AI-controlled matches, and replay halts at the first fingerprint divergence with expected/actual state.

## 15. Known Issues, Incomplete Features, and Prototype Shortcuts

No explicit `TODO`, `FIXME`, or `HACK` markers were found in the inspected `.gd`, `.tscn`, or `.md` files.

### Confirmed incomplete or placeholder areas

- Units are placeholder bean models without production humanoid assets or combat animations.
- Terrain and refinery visuals are blockout geometry generated from boxes/simple meshes.
- Replay is in memory and sequential. It lacks persistent files, rewind/scrubbing, a timeline, smooth cinematic tracking, a final-mover-only camera, and a full photo interface.
- The tactical HUD remains visible during replay, although normal gameplay input and AI are disabled.
- SP, ammunition, reload/resupply, weapons, classes, inventory, injury/incapacitation, and general carrying are absent.
- There is no fog of war or perception model; AI reads authoritative battle state.
- Difficulty changes utility and believable lapses, not planning depth or multi-turn search.
- Squad coordination is current-round reservations and score adjustments, not centralized tactics.
- The map-quality score reports quality but does not automatically reject or regenerate low-scoring valid maps.
- `BattleLevel` does not visibly retry a failed generated map; validation failure stops initialization.
- The refinery layout is authored in code and rendered as industrial blockout, not an art-complete environment.

### Intentional prototype simplifications

- One shared attack with fixed range 10, fixed 25 damage, and fixed 1 AP cost.
- Directional low and full cover currently produce the same 50-point attack penalty.
- No independent elevation accuracy modifier; elevation acts through geometry and positioning.
- Rescue pickup and extraction cost no AP.
- VIP Follow Escort follows the first escort rather than selecting or coordinating an escort dynamically.
- Generated structures and objective selection favor deterministic validity and testability over final content variety.

No additional known runtime bug is asserted here without a reproducible failure in code, tests, or logs.

## 16. Prototype 1 Feature Inventory

| Feature | Status | Primary evidence |
| --- | --- | --- |
| Match setup and force sizing | IMPLEMENTED | `ui/match_setup.gd` |
| 720p reference viewport and scalable UI | IMPLEMENTED | `project.godot`, setup scene |
| Automatic/manual battle seeds | IMPLEMENTED | `ui/match_setup.gd`, `battle_level.gd` |
| Player/enemy/ally/neutral factions | IMPLEMENTED | `tactical_unit.gd`, `faction_rules.gd` |
| 1–5 units per combat force | IMPLEMENTED | `match_setup.gd`, spawn systems |
| Optional controllable/AI VIP | IMPLEMENTED | `mission_actor.gd`, `battle_level.gd` |
| HP/AP and unit exhaustion | IMPLEMENTED | `unit_stats.gd`, `turn_manager.gd` |
| SP/ammunition/resupply | PLACEHOLDER | No runtime system found |
| Grid movement and weighted A* | IMPLEMENTED | `pathfinder.gd`, `move_action.gd` |
| Move/Attack/Defend actions | IMPLEMENTED | `scripts/actions/` |
| Rescue/carry/extract | IMPLEMENTED | `objective_manager.gd`, `tactical_unit.gd` |
| Multi-point LOS and accuracy | IMPLEMENTED | `combat_rules.gd` |
| Directional cover | IMPLEMENTED | `combat_rules.gd` |
| Elevation and vertical combat | IMPLEMENTED | map/grid/traversal systems |
| Stairs, ramps, ladders, vaults, bridges | IMPLEMENTED | traversal data/builders and tests |
| Seven mission presets | IMPLEMENTED | `mission_catalog.gd` |
| Objective-aware allied/enemy AI | IMPLEMENTED | `ai_controller.gd` |
| Position and target utility scoring | IMPLEMENTED | AI scorers |
| Easy/Normal/Hard policies | IMPLEMENTED | `ai_difficulty_policy.gd` |
| Intentional believable AI lapses | IMPLEMENTED | difficulty policy |
| Squad reservations/focus/support | IMPLEMENTED | `squad_context.gd` |
| AI-vs-AI and manual enemy debug | DEBUG/TEST | `debug_tools.gd`, controller flags |
| Authored test battlefield | IMPLEMENTED | `prototype_map.tscn`, `MapBuilder` |
| Seeded generic procedural maps | IMPLEMENTED | `flat_map_generator.gd` |
| Generated buildings/platforms/hills | IMPLEMENTED | generation modules |
| Special refinery battlefield | IMPLEMENTED blockout | refinery builder/presenter |
| Objective-aware zone placement | IMPLEMENTED | mission placement evaluator/planner |
| Map topology validation | IMPLEMENTED | `map_validator.gd` |
| Tactical map-quality metrics | DEBUG/TEST | `map_quality_evaluator.gd` |
| Automated AI match simulation | DEBUG/TEST | `systems/simulation/` |
| Seed failure JSON reports | DEBUG/TEST | `seed_failure_reporter.gd` |
| F3 inspection/mission controls | DEBUG/TEST | `ui/debug_tools.gd` |
| Battle pause and return to setup | IMPLEMENTED | `battle_pause_menu.gd` |
| End-screen replay/setup buttons | IMPLEMENTED | `turn_hud_controller.gd` |
| Deterministic verified replay | IMPLEMENTED | `systems/replay/`, replay tests |
| Replay controls and action-follow camera | IMPLEMENTED | `replay_controls.gd`, `battle_replay_player.gd` |
| Replay timeline/rewind/cinematic cameras | PLACEHOLDER | No runtime system found |
| Photo mode | PLACEHOLDER | No runtime system found |
| Production humanoids/animation/art | PLACEHOLDER | Bean and blockout scenes |
| Headless regression suite | IMPLEMENTED | `tests/` |

## 17. What Prototype 1 Currently Proves

Prototype 1 demonstrates that FuseFire's central tactical ideas can coexist in one data-driven, testable system:

- multi-unit turn-based combat with common legal rules for human and AI control;
- 3D grid movement and shooting across generated elevation and traversal;
- partial visibility and cover-derived accuracy that responds to physical geometry;
- several mission structures beyond annihilation, including protection, rescue/carry, survival extraction, and enemy evacuation;
- objective-aware AI that balances mission progress, tactical position, target value, survival, and lightweight team coordination;
- seeded procedural and hybrid map construction represented through the same map model as authored content;
- automated validation and tactical quality measurement across many maps;
- deterministic combat, AI simulation, exact seed reproduction, failure reporting, and action-by-action verified replay;
- debug tooling capable of observing and manipulating complex matches;
- architecture that separates data, rules, AI policy, presentation, generation, objectives, testing, and replay sufficiently to support continued development.

The prototype therefore proves the technical gameplay foundation of a mission-based 3D tactics game. Its remaining visible gaps are primarily production presentation, content breadth, advanced replay presentation, and systems deliberately deferred beyond the current prototype.
