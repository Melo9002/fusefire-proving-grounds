# How FuseFire works

The useful question when reading the code is: **which script owns this decision?** A scene connects objects; scripts define their behavior.

## Folder map

```text
levels/prototype_map/  Playable scene: map, units, camera, and references
systems/              Battle interaction, turns, and combat rules
systems/grid/         Terrain graph, map setup, occupancy, mouse rays
systems/generation/   Seeded producers of runtime MapData
systems/spawning/     Reusable spawn-zone data
systems/actions/      Move, Attack, and Defend operations
units/components/   UnitStats: HP, AP, defense, player movement budget
units/                Unit scene, movement animation, enemy decisions
ui/                   Buttons, turn/AP display, floating health bars
presentation/overlays/          Grid lines, cursor, paths, and range tiles
tests/                Repeatable check using the actual battle scene
```

Keep this layout while the prototype is small. Add folders when they group a real responsibility.

## Who owns what?

| Script | Responsibility | Change it when… |
| --- | --- | --- |
| `BattleController` | Player input, action modes, previews, request submission, and battle-level coordination | Changing how player intent becomes an authoritative action request |
| `TurnManager` | Phases, active unit, rosters, rounds | Changing whose turn it is or when AP resets |
| `MapBuilder` | Converts authored geometry into map cells and paths | Changing how a scene or future generator supplies terrain |
| `MapData` / `MapCellData` | Terrain, elevation, cover, LOS, and traversal facts | Asking what a battlefield cell contains |
| `MapValidator` | Reports whether runtime map and spawn data can support a battle | Adding legality rules shared by handmade and generated maps |
| `FlatMapGenerator` | Produces seeded flat terrain, cover, and faction spawn cells | Changing the first procedural map source |
| `GeneratedElevationPlacer` | Adds seeded freestanding platform surfaces as elevated map cells | Changing generated elevation placement |
| `GeneratedTerrainPresenter` | Builds disposable 3D cover meshes from generated MapData | Changing generated-map presentation |
| `MapBatchTester` | Generates and validates a range of seeds without scene instances | Adding structural batch checks and metrics |
| `MapGraphBuilder` | Derives Pathfinder state from completed MapData | Changing how generated terrain becomes traversable |
| `TerrainFeature` | Inspector metadata for authored obstacles | Declaring cover without relying on node names or dimensions |
| `ElevatedSurface` | Inspector metadata that produces elevated walkable cells | Authoring rooftops, platforms, or bridges |
| `ElevationPath` | Produces a sequence of rising walkable cells | Authoring stairs and ramps without special unit movement |
| `TraversalLink` | Converts an authored ladder connection into map data | Connecting terrain that normal height rules cannot join |
| `GridManager` | Cell/world conversion, map data, and separate unit occupancy | Looking up terrain or who occupies a cell |
| `Pathfinder` | A* routes and breadth-first movement range | Changing terrain traversal |
| `CombatRules` | Faction, range, and line of sight | Changing legal attack targets |
| `FactionRules` | Relationships between player, ally, enemy, and neutral | Changing who is hostile or friendly |
| `TacticalActionService` | Shared read-only action queries plus authoritative action transactions | Changing action lifecycle, AP/revision validation, or typed results |
| `UnitStats` | HP, AP, defense, defeat signals | Changing health or resource rules |
| `MissionActor` | Stable mission identity, actor role, and extraction capability | Defining who objectives refer to |
| `MissionDefinition` / `MissionObjectiveDefinition` | Saved mission and objective design data | Declaring objectives, targets, requirements, and progress totals |
| `MissionObjectiveState` | Runtime progress and active/completed/failed status | Reading what happened to one objective during a battle |
| `ObjectiveManager` | Owns objective legality/state, extraction roster consequences, mission outcomes, and authoritative mission-command events | Connecting future mission events and UI to objective progress |
| `TacticalUnit` | Path animation, defeat relay, health-display creation | Changing unit movement or presentation |
| `AIController` | Chooses among legal attacks, movement, and defense | Changing enemy priorities or difficulty |
| `SquadContext` | Shares current-round reservations and intentions within one AI team | Adding small coordination score adjustments |
| `AIDifficultyPolicy` | Holds Easy, Normal, and Hard decision weights | Tuning AI priorities without altering action validation |
| `AIPositionScorer` | Scores reachable tactical destinations with an inspectable breakdown | Tuning cover, exposure, firing, route progress, and danger |
| `AITargetScorer` | Ranks legal targets by vulnerability, role, threat, mission urgency, and squad focus | Tuning who automated units shoot |
| `MissionIntent` | Describes the active mission goal for one automated unit | Adding objective-aware AI planning |
| UI and visualizers | Display state and forward input | Changing feedback and presentation |
| `TacticalCamera` | Bounded pan, zoom, and rotation | Changing how the battlefield is viewed |
| `BattleLevel` | Builds selected teams before starting combat | Changing how a match is assembled |
| `SpawnZone` | Supplies ordered spawn transforms and faction data | Changing where a generated team may spawn |
| `UnitPortraitBar` | Mirrors the friendly roster and synchronizes selection | Changing roster-level battle UI |
| `UnitPortrait` | Displays one unit's HP, AP, and UI state | Changing the contents of a portrait card |
| `UnitSelectionVisualizer` | Applies the world outline to the selected friendly | Changing selection feedback in the battlefield |
| `DebugTools` | Pauses the battle, displays runtime data, and changes test control ownership | Adding developer-only battle inspection tools |
| `ShotTrajectoryVisualizer` | Draws the combat validator's exact shot segment | Diagnosing range, cover, and LOS decisions |

## Match setup and spawning

`MatchSetup` collects independent player, allied, and enemy counts, mission objective, and AI difficulty, then configures a new `BattleLevel`. The level asks each `SpawnZone` for the requested number of marker transforms, instantiates the shared tactical-unit scene, fills the turn rosters, and adds one AI controller per unit. Only then does it tell `BattleController` to scan and start the match.

## Mission actors

Faction answers who a unit considers hostile. `MissionActor` separately records what that unit means to a mission. Its `Kind` distinguishes combatants, VIPs, and rescuable actors, while `extraction_capable` describes a capability that any appropriate actor may have. Every spawned unit receives a stable mission ID derived from its unique battle name. Objective definitions refer to those IDs and roles without encoding mission logic in factions or unit names.

Unit coordinates do not live in spawning code. Handmade `SpawnZone` markers are converted into faction-keyed cells inside `MapData`; a future generator can supply the same data without scene markers. `BattleLevel` still uses authored transforms to instantiate the current Beans, while map validation uses the reusable cell representation.

## Objective foundation

Objectives use three layers. `MissionObjectiveDefinition` and `MissionDefinition` are Resources containing reusable design data. `MissionObjectiveState` holds the mutable progress and status for one battle. `ObjectiveManager` builds those states, rejects malformed IDs, exposes progress/complete/fail commands, and announces changes through signals so later UI does not need to own mission rules.

`ObjectiveManager` observes committed movement and defeat events plus the turn manager's round events. It translates them into eliminate, protect, rescue, reach, survive, and extract state changes, then resolves the mission from its required objectives. It never performs combat or movement itself. Extraction commits objective counters and removes grid occupancy and turn-roster membership through those systems' public boundaries. The visual actor remains registered until `TacticalActionPresenter` finishes boarding, then presentation performs visual cleanup.

`MissionCatalog` supplies the seven prototype presets shown by match setup. The menu creates the chosen Resource and passes it through `BattleLevel.configure()`; the level loads it into `ObjectiveManager` before map construction. The manager logs the active definitions and every later state change.

`MapZoneData` represents deployment, objective, and extraction areas with one ID, kind, cell list, and optional faction owner. `MapData` owns every zone and retains small spawn/objective query methods for its consumers. `MissionZonePlanner` chooses route-separated cells for authored and generated maps, while `ObjectiveZoneVisualizer` only presents those authoritative coordinates. Rescue adds a neutral, non-turn-taking mission actor on another valid cell. This keeps spatial objective rules independent from meshes, node names, and map source.

`ObjectiveHUD` mirrors every objective state in the top-right display and exposes early mission completion when its rules permit it. Extraction is a zero-AP mission action with no generic turn gate: `UnitWorldBar` enables its button from `query_mission()` for any eligible player-controlled unit standing inside an active extraction zone, even when exhausted. Missions such as Survive may explicitly keep extraction locked until an earlier objective completes. `ObjectiveManager` owns mission eligibility and evacuation bookkeeping. Automated allies consume the same query and action gateway before leaving through the zone.

Rounds proceed through `PLAYER_TURN → ALLY_TURN → ENEMY_TURN`; an empty allied roster skips its phase. Allied units are autonomous, use the same `AIController` and action gateways as enemies, remain outside player selection, and share player hostility rules. They do not prevent defeat when every player-controlled unit is lost.

`ObjectiveManager.get_mission_intent()` translates active objective state into a faction-relevant `MissionIntent`. The value identifies the objective, intent kind, zone, actor IDs, requirement status, and reason without executing an action. Each objective carries a faction mask declaring who pursues it; player and ally are the default, while future asymmetric missions may assign separate goals to enemies. AI therefore receives a mission goal alongside its combat choices. Rescue precedes extraction, and extraction unlocks only when mission rules allow it.

Reach and Extract intents are executable AI goals. `AIController` compares every eligible zone cell by reachable path length and advances toward the best route. If no legal shot follows the first move, it can advance again when its exposure does not worsen under the current difficulty policy. An eligible unit already in extraction, including one with zero AP, verifies the shared mission query and calls `ObjectiveManager.try_extract()` through the authoritative action service. Roster removal decides whether another automated player activates or the allied queue advances, avoiding a second phase transition from the AI controller.

Protect and Rescue intents are executable AI goals as well. A protecting combatant returns to a three-cell escort radius when separated, then uses ordinary combat logic while nearby. A rescuer pathfinds to an adjacent cell, checks the shared mission query, and calls `ObjectiveManager.try_rescue()` through the zero-AP action transaction. Automatic movement-triggered pickup remains a consequence of its parent Move transaction. The rescued actor is removed from grid occupancy and attached to the carrier's existing carried-unit state, which reduces movement speed. Completion exposes the Extract intent, so the carrier uses the normal objective route and mission action to evacuate both actors.

During an active Survive objective, `AIController` scores every reachable stopping cell using directional cover against each living hostile, separation from the nearest threat, movement distance, and distance to extraction. It moves to a higher-scoring staging position when one exists and then returns to shared attack or wait choices. `ObjectiveManager` continues to reject extraction before the round requirement is complete. Completion changes the unit's next intent to Extract, so no special evacuation path bypasses the mission action transaction or roster rules.

Enemy Evacuation combines a required player-owned Eliminate objective with an optional enemy-owned Extract objective. Objective definitions may name their own `MapData` zone, allowing enemy AI to select `enemy_extract` while friendly missions retain `extract`. The enemy exit is presented in orange. `ObjectiveManager` accepts extraction from the appropriate faction, records escaped enemies separately, and fails the required interception objective on the first escape. `TurnManager` removes an active enemy from its queue without skipping the following activation.

`BattleController` owns one `SquadContext` for the friendly alliance and one for enemies. Each context resets when a new round begins and removes an actor's stale intention before its next activation. AI controllers publish committed destinations, targets, and objective handlers after choosing through their existing local policy. Later teammates apply large exact-destination penalties, smaller adjacent-crowding penalties, and gradual target-focus penalties while preserving legal focus fire. Rescue extraction adds one coordination rule: non-carriers support the current carrier until that mobile objective is safe. The decision record carries a short `squad_adjustments` explanation for F3; the context never executes actions or bypasses shared validation.

`BattleLevel` passes the match setup's selected difficulty and seed to `BattleController`, and each `AIController` creates an `AIDifficultyPolicy` and seeded decision RNG for that tier. The policy weights vulnerable-target and finisher scores, squad focus and movement penalties, position cover and exposure, firing opportunities, crossfire danger, survival separation, and acceptable exposure for a second advance. Normal uses the baseline weights. Easy has a 22% chance to choose a bounded near-best legal target or safe reachable tile; Normal has an 8% chance; Hard always chooses the top score. Alternatives cannot fall far behind mission priority or route progress or add substantially more exposure or danger. The policy affects only ranking and risk preferences; every chosen action still goes through `BattleController` and the same combat, AP, movement, and objective rules. F3 includes the active tier and any lapse with both scores in its decision record.

`AIPositionScorer` compares reachable stopping cells along or within two grid units of the chosen route. Its breakdown records route progress and remaining goal distance, directional cover, approximate incoming and outgoing firing lanes, crossfire and adjacent-enemy danger, and squad reservation penalties. Mission routes weight progress more strongly than combat approaches. Survive positioning reuses the tactical score while also valuing separation from hostiles and proximity to the later extraction zone. F3 displays the winning position's score components. The estimate ranks positions; actual shots and movement still use shared validation.

After `BattleController.evaluate_attack()` rejects illegal shots, `AITargetScorer` ranks the remaining hostiles. It combines missing HP and a near-defeat bonus, hostile VIP status, legal shots the target could take against the actor's team, objective-specific urgency, and `SquadContext` focus penalties. Protect and rescue carrier threats receive mission bonuses; enemies also prioritize an exposed rescue carrier, while player defenders prioritize evacuees near their exit. Difficulty weights these terms but does not change eligibility or hit resolution. F3 displays the selected target's component scores.

## Battlefield validation

After authored geometry has become `MapData`, `BattleController` asks `MapValidator` to inspect it before registering units or starting turns. Validation is read-only and returns a `MapValidationResult` containing structured `MapValidationIssue` records. Each issue has a stable code, readable message, and an optional grid coordinate.

The validator checks cell values and path-graph parity, LOS-index consistency, traversal endpoints and connections, unique walkable spawn cells, requested team capacity, and routes between every player/enemy spawn pair. The handmade test map passes through this same boundary that a procedural generator will use. Invalid data remains available for diagnosis, but combat does not start.

## Flat generated maps with cover

`MapData.containers` records rectangular ground footprints. The generator assigns full-cover height and movement/LOS properties to every footprint cell. The presenter skips those individual cubes and renders one ribbed steel container using the footprint and cell height. Containers are placed before smaller formations with a one-cell clearance; both share the cover budget. Generated size presets are passed from match setup to BattleLevel, which resizes the floor and refreshes grid lines and camera zoom before map generation. The handmade map retains its authored dimensions.

`MapData.buildings` stores generated structure footprints, roof levels, and access endpoints. Each solid footprint contributes full-height LOS blockers at ground level plus normal walkable cells at roof level. A `TraversalLinkData` joins the clear ground approach to its roof endpoint. The presenter draws the shell and ladder and adds a floor-click collision surface at roof height, but the data remains the authority for movement and combat.

`GeneratedBuildingExpansion` runs after building placement and before containers or cover. It adds ascending stair cells using the existing one-level neighbor rule and can replace a roof corner with a solid 2×2 utility floor. The upper ladder is another ordinary traversal link. Its landing and the stair exit remain outside the upper footprint. The building's `reserved_area` includes stair approaches so later placement cannot obstruct them. Stair access is tested with all ladder links disconnected. Presentation consolidates each floor into one mesh with matching layer-2 click surfaces, while actions and occupancy continue to use the common grid. Interiors, larger upper floors, and smooth ramps are deferred during the generation pause.

`FlatMapGenerator.generate()` creates the empty ground and faction spawn cells. `generate_with_cover()` applies a separate seeded layout grammar containing low/full barricades, corners, low walls, and staggered positions. It chooses anchors and rotations from the map seed, then accepts an entire formation only when every member avoids spawn bands, the central route, existing cover, and invalid cells. Low cover remains traversable at movement cost 2 but cannot be a destination. Full cover disables walking and blocks line of sight. The same inputs reproduce both spawn and cover placement.

`GeneratedElevationPlacer` adds freestanding 3×4 or 4×3 decks at elevation levels 2 or 3. Each deck owns a `GeneratedPlatformData` record and contributes normal walkable cells to `MapData`; the ground below remains usable. `GeneratedTraversalBuilder` gives every platform ladder, stair, or ramp access and records it as `GeneratedTraversalData`. Those exact cells are reserved from later cover placement, validated against the completed path graph, and consumed by presentation. The refinery preset instead uses a fixed industrial shell with four service platforms, two higher tower caps, and two connecting catwalks; seed-generated cover varies inside that structure while generic buildings and the hill are omitted.

On 40×30 maps the same placement stage adds one 7×7 `GeneratedHillData` feature. Concentric surface tiers occupy elevation levels 1, 2, and 3, so normal one-level neighbor connections make the hill climbable without an explicit traversal link. The base cells describe solid LOS-blocking terrain, and later placement respects the hill's reserved boundary.

`MapGraphBuilder` creates a fresh A* graph from the completed records. The validator checks data and graph together before units spawn from those generated coordinates. `GeneratedTerrainPresenter` creates simple meshes after the data is complete; those meshes do not decide movement or combat. The playable scene reuses its floor, camera, UI, and systems while hiding authored obstacles and vertical geometry.

`MissionPlacementEvaluator` builds weighted route-distance maps from both deployments over that completed graph. `MissionZonePlanner` uses those distances with local cover, available approaches, and elevation to place Reach, friendly extraction, enemy extraction, and rescue-actor cells. Four-cell zones must form a contiguous surface; all placements avoid deployment and previously reserved mission cells. `MapValidator` verifies that pursuing factions can reach every result and rejects overlaps. Objective rules remain in `ObjectiveManager`; placement only supplies valid battlefield locations.

`MapQualityEvaluator` is an observational layer over `MapData` and the completed path graph. It measures each deployment's nearby cover access, viable outbound route branches, open-space density and clustering, topology-based firing-lane lengths, and spawn exposure. `MapQualityReport` retains the raw measurements, five bounded category scores, the weakest category, and a bounded overall diagnostic score. The metrics smoke run prints category ranges and reproducible low-, middle-, and high-ranked seeds so human playtests can calibrate whether the ranking reflects tactical quality. Battle startup emits the concise raw summary that future batch simulation and seed-failure reporting can consume. These measurements do not reject maps or alter generation; thresholds remain deferred until simulation and playtesting provide a useful baseline.

`AIMatchSimulator` instantiates the real battle level, enables the existing automated-player path, and observes authoritative state rather than maintaining a simplified combat model. Each `AIMatchSimulationResult` captures the complete configuration, result, rounds, structured AI decision trail, elapsed time, map quality, validation errors, final state, and a completion classification. State signatures include turn, active actor, roster positions, HP/AP, and objective progress, allowing the runner to distinguish a slow battle from one making no progress. `AIMatchSimulationBatch` aggregates repeated seeds and missions. `SeedFailureReporter` writes non-completing matches as JSON under `user://ai_sim_failure_reports`, retaining the exact seed, mission, map parameters, terminal state, and decisions needed for reproduction.

Map generation, AI decision lapses, and combat resolution use separate deterministic random streams derived from the match seed. `BattleController` owns the combat stream and supplies every attack roll to `AttackAction`; the action never chooses an untracked global random value during ordinary play. Keeping the streams separate prevents an added map or AI random call from silently shifting every later combat result.

Every battle has a battle seed even when its map is authored. Generated battlefields additionally treat that value as their current map seed, while authored maps pair it with a stable map identity and version. A reproducible configuration therefore includes battle seed, map identity or generator parameters, map size/preset, mission, difficulty, rosters, and rules version. Batch simulation rotates map sizes explicitly rather than treating Medium as representative of every layout.

`BattleReplayRecorder` observes successful authoritative actions from `BattleController`, objective interactions from `ObjectiveManager`, and phase advances from `TurnManager`. It stores actor names, movement cells, attack targets and outcomes, rescue/extraction interactions, round, phase, and the complete battle configuration. Replay creates the same seeded battlefield, disables ordinary AI and manual control, then `BattleReplayPlayer` submits the recorded sequence through the shared gameplay APIs. This first replay foundation preserves turn-based timing and the normal tactical camera. Later presentation work can change replay pacing and camera direction without changing the action record.

Future battle replay should use an authoritative action journal rather than parsing presentation logs. Its header must identify the map, mission, rosters, rules version, and every random seed. Ordered records should use stable actor IDs and contain validated commands plus resolved random outcomes and compact state checks. A turn-by-turn replay can apply those records directly, while the post-battle pseudo-real-time presentation may reschedule and overlap their animations without recalculating combat results. Human-readable debug output and agent telemetry may derive from the same events, but neither is the replay authority.

`MapBatchTester` exercises this data pipeline without loading units, UI, physics, or meshes. Each seed receives a fresh map and path graph, then passes through `MapValidator` with 5v5 spawn requirements. The report retains failing seeds and their issue messages while aggregating low, full, and cohesive-cover counts. A refined layout also requires at least 75% of cover cells to have an orthogonally adjacent cover neighbor. This is a fast structural and layout-cohesion test; it does not claim that every valid map is tactically interesting.

## Portrait selection

After units are registered, `BattleController.units_registered` gives the portrait bar the current friendly roster. Each portrait observes its own unit's HP, AP, and defeat signals. Portrait clicks ask `TurnManager` to select the unit; battlefield clicks use that same method. Both paths are reflected back through `active_unit_changed`, so the UI never keeps a separate selection.

Exhausted and dead portraits remain visible but cannot be selected. A dead portrait remains as a record after its world unit leaves the active roster.

`UnitSelectionVisualizer` listens to the same `active_unit_changed` signal and applies a thin material overlay to every mesh below the selected friendly. It clears the previous overlay before applying the next one and does not outline AI units during the enemy phase. This keeps selection feedback separate from unit rules and supports future unit scenes with multiple meshes.

`TurnManager` observes AP for every friendly in the dynamic roster. When the selected unit reaches zero, it waits for any movement to finish and searches forward through the roster, wrapping once and skipping dead or exhausted units. If nobody can act, it emits `player_actions_exhausted`; the HUD emphasizes End Turn while the phase stays open for inspection.

`Pathfinder`, `CombatRules`, `MapBuilder`, and actions are code objects rather than scene nodes. `RefCounted` lets Godot release them when no references remain. The battle owns one pathfinder; the scene no longer contains an unused second one.

`MapData` is the runtime terrain description. Every `MapCellData` record stores its coordinate, world position, elevation, walkability, cover type, physical cover height, LOS blocking flag, and movement cost. Authored maps fill it through `MapBuilder`; a procedural generator can later produce the same records without changing gameplay systems. `GridManager.occupancy_map` remains separate because a unit standing on a tile does not change its terrain.

The Y component of a cell coordinate is its elevation level. `GridManager.elevation_step` converts each level into world height, and `MapData` may hold several cells in the same X/Z column. A `TacticalUnit` keeps its registered grid coordinate as logical state, so two units can occupy different floors in one column without model height confusing occupancy. Pathfinder connects horizontal neighbors whose elevation differs by at most one level; larger gaps remain disconnected until an explicit traversal link such as a ladder is supplied.

An authored `ElevatedSurface` contributes regular `MapCellData` records at its declared elevation. Its solid footprint disables the ground beneath it. A `TraversalLink` contributes `TraversalLinkData` to the map and joins two specified cells in the path graph. The current northwest platform is two levels high, so it remains unreachable when its ladder link is removed. Once a unit climbs onto it, movement uses the same cells and rules as the ground.

`ElevationPath` contributes a sequence of cells with increasing Y coordinates. Stairs and ramps therefore share pathfinding rules; only their scene geometry differs. A suspended surface can preserve lower cells in the same X/Z columns, allowing separate units and paths above and below it.

Movement distinguishes crossing a cell from ending on it. Floor cells cost one movement point and accept units. Low cover stays connected, costs two points, and cannot be a destination; the movement path raises the unit by the declared cover height while crossing it. Full cover is disconnected. Every completed Move action still costs one AP.

Movement facts have one read-only contract. `TacticalActionService.query_move(actor_id)` returns the current legal-destination inventory; supplying a destination returns its authoritative path, path cost, budget, predicted AP, elevation change, and traversal presentation segments. Player range/hover code and AI active-turn candidate scoring consume this contract. AI may still use unrestricted pathfinding for long-range hypothetical planning and owns the strategic value of a destination.

Submission always reruns the targeted query against the current revision and occupancy. A successful commit spends AP and moves grid occupancy synchronously, so the committed destination itself is the reservation while animation is running. `TacticalActionPresenter` only animates the committed result and snaps the visual to that destination when presentation is suppressed or interrupted.

`CoverVisualizer` draws a short edge inside each reachable destination beside cover while Move mode is active. The edge faces the obstacle, matching directional combat cover. Low and full cover use separate materials, and leaving Move mode clears both.

## Follow one move

1. The Move button calls `BattleController.toggle_move_mode()`.
2. The controller asks `Pathfinder` for cells within the selected unit's budget and filters occupied destinations through `GridManager`.
3. `PathVisualizer` draws yellow cells. Hovering requests an A* path and draws it in blue.
4. `MouseRaycaster` turns a click into a floor hit. The controller verifies the active turn, recomputes the reachable set and path from map data, then creates `MoveAction`.
5. The action spends AP, reserves the destination, and gives the path to `TacticalUnit`.
6. The unit advances each frame and emits `movement_finished` on arrival. The action mode has already returned to neutral.

A **signal** is an announcement: `ap_changed` lets UI update without stats knowing where the AP label lives. An **exported property** is a value or reference wired in Godot's Inspector.

## Follow an attack and a round

Attack mode makes an enemy click call `BattleController.try_attack()`. `CombatRules.evaluate_attack()` returns legality, hit chance, directional cover, target visibility, a visible aim point, and a reason. It samples five points scaled from the target's standing height. No visible samples blocks the attack; partial visibility applies a discrete obstruction penalty. Directional cover and obstruction use the stronger single penalty so one obstacle is not counted twice. `AttackAction` spends AP and resolves the roll; hits deal full damage and misses deal none. AI attacks use the same evaluation and controller entry point.

Line of sight reads the terrain description rather than using pathfinding or raw obstacle collisions. Each cell with physical cover height forms a vertical volume from its terrain elevation through that height. Combat tests segments from the attacker's standing-height origin to the target samples against those volumes. A shot can therefore pass above a wall, and an elevated attacker may receive a penalized partial shot when only part of a lower target is visible.

`MapData.los_blocking_cells` indexes only terrain that can stop a shot. Map construction rebuilds this index after applying authored features; dynamic terrain should rebuild it after changing LOS flags or heights.

Attack previews use the evaluation's first visible target sample, so the debug trajectory shows a line the shot can actually take. Blocked previews retain the target center and identify the first blocking cell. Low cover is directional and queried on the target's elevation layer, so ground cover does not protect a unit standing on a platform. Touching only the outer boundary or corner of an obstacle does not block a shot.

Authored obstacles declare their cover type and physical height. The current map uses bright 1 m low cover and darker 2 m full cover. Enable `Debug Shots` on `BattleController` to log attempted targets, legality, chance, and the blocking terrain cell when present.

The 32×24 test battlefield is a systems laboratory. Opposing 5-unit spawn zones sit beyond long firing lanes. The center contains full-cover gates and flank pillars, the south contains staggered vault barriers, and the north contains twin platforms. A higher central platform can be reached independently by ramp, stairs, or ladder. A suspended northwest deck also verifies movement and occupancy above and below the same X/Z columns.

At zero HP, stats announce defeat. The unit relays the signal, and the battle removes it from occupancy and the roster before freeing it.

End Turn starts the enemy phase. Every action request passes through `BattleController`, which asks `TurnManager` whether that unit is alive, active, and part of the current faction roster. Rejected actions preserve AP. Move requests also rebuild their path from authoritative map data, so neither UI nor AI can supply a shortcut through blocked terrain.

The current enemy AI repeats a small priority list while it has AP: attack the legal target with the lowest HP; otherwise move once toward the nearest living player; otherwise Defend and finish its activation. Attack legality, hit chance, movement budget, occupancy, AP cost, damage, and defense all come from the same rules and action classes used by player input. The test level also assigns its extended attack range to both teams, so enemies take legal ranged shots instead of approaching to the unit scene's shorter default range. The AI chooses an intention; it does not implement a second version of combat.

Difficulty should later adjust decision policy, such as target scores, position scores, planning depth, or intentional mistakes. It should not bypass action validation or secretly use different movement and combat rules. After the final enemy activation, a new player round begins. AP resets and defense expires at the start of that team's phase. Running out of player AP does **not** automatically end the phase. Removing the final enemy or player ends the battle and displays Victory or Defeat.

The test scene's `DebugTools` node owns developer-only control overrides. Its Inspector switch can remove the tools from play. F3 opens a pause-safe panel, the optional overlay reads battle state without owning it, manual enemy control redirects the active enemy to the normal action UI, and AI-versus-AI mode attaches the same faction-neutral decision policy to player activations. The shot-trajectory option draws the same body-center segment used by `CombatRules`, including illegal attempts, so its visualization cannot drift from LOS geometry. Blocked shots mark the responsible `MapCellData`, while AI controllers publish structured decision records that the debug UI may display without participating in those decisions. These modes change who chooses actions; all requests still pass through ordinary turn and action validation.

## Terrain and units are different data

Terrain says where the map allows walking. Occupancy says where units are. Moving a unit never disables terrain points.

| Physics layer | Use |
| --- | --- |
| 1 | Environment: blocks movement scans and shots |
| 2 | Floor: receives ground clicks |
| 3 (mask value 4) | Units: receives unit clicks |

Physics collision layers are separate from visual render layers. Map setup waits briefly for CSG collision bodies before scanning and starting the player phase.

## What this cleanup changed

- Extracted map setup and combat validation from `BattleController`.
- Reused `GridManager` for coordinate conversion instead of maintaining a second battle-controller formula.
- Moved the action HUD into `ui/`, preserving its Godot UID and updating its scene reference.
- Removed SP/resupply, the unused AP component and pip HUD, a debug level script, the unused enemy scene, and interrupted scene-save copies. Playable enemies already use `tactical_unit.tscn` with enemy faction set in the level.
- Removed the unused scene pathfinder, an unconfigured health-bar instance, dead turn-automation helpers, and obsolete occupancy/pathfinder coupling.
- Removed the pathfinding override that let paths escape blocked terrain. Units no longer disable terrain, so routes and ranges now both respect blocked starting cells.
- Shortened comments and removed duplicate defense notifications and delayed movement-overlay clearing.

## Camera

`TacticalCamera` is a pivot above the map. Moving changes the pivot's X/Z position, rotation turns the pivot around its center, and zoom changes the child camera's distance. The pivot is clamped to the floor bounds plus a small margin, so the camera can reveal tiles behind UI without wandering far away.

## Known limits to playtest next

- Paths consider terrain, not intervening units. Friendly/enemy blocking needs a gameplay decision.
- Attack-range coloring shows legal cells, while the attack button shows the exact hovered unit chance or blocked reason.
- The global action lock prevents selection, new actions, and phase changes during movement. Attacks and defense are currently immediate, so they do not hold the lock across an animation.
- The base grid assumes an unrotated floor centered on world X/Z. Elevated surfaces add layers above it, but moving or rotating the base is not supported by all conversions and visuals.
- Terrain is scanned only at startup; moving walls later will not rebuild paths.
- Victory and Defeat are text states in the existing turn HUD; a dedicated result screen can come later.

Play a few rounds, choose the rules you want, and then change the relevant owner above.
