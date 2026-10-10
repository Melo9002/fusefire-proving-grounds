# Project FuseFire

A 3D tactical combat prototype made in Godot 4.7. Choose independent player, allied AI, and enemy force sizes, then fight across authored or generated multilayer battlefields.

## Play

Import `project.godot` in Godot and press **F5**.

The UI uses 1280×720 as its reference resolution and scales to standard 1080p and 1440p displays through Godot's canvas-item stretch mode.

During battle, press **Esc** to pause and open Resume or Return to Match Setup. Returning creates a fresh setup screen without retaining the current battle. Press **F3** separately to open the debug tools.

The match setup screen accepts 1–5 player combatants and 1–5 enemy combatants and lets you select a prototype mission objective and AI difficulty. AI allied combatants and an optional additional VIP are configured separately. A live deployment summary shows which actors are player-controlled or AI-controlled before battle. The battlefield spawns units from reusable marker-based spawn zones; team sizes do not need to match.

Generated maps prepare a fresh visible seed whenever a new match setup opens. Disable **Automatic New Seed** to unlock the seed field and reproduce a previous battlefield exactly; the map generator log also records the seed used.

During battle, the bottom portrait bar mirrors the friendly roster. Each Bean card shows HP, AP, and its selected, ready, exhausted, or dead state. Clicking a ready portrait selects the same unit in the battlefield.

The selected friendly also receives a thin cyan outline in the battlefield. The outline follows selection from either the world or portrait bar and clears during the enemy phase.

When the selected unit spends its final AP, selection advances through the friendly roster to the next living unit with AP. If nobody can act, the game remains in the player phase for inspection and highlights End Turn.

| Control | Effect |
| --- | --- |
| Click a player unit | Select it if it has AP remaining |
| Move, then click a yellow cell | Spend 1 AP to move |
| Attack, then click an enemy | Spend 1 AP if the target is in range and visible |
| Skip | End the selected unit's activation without granting a defensive bonus |
| End Turn | End the player phase; enemies act in sequence |
| Tab | Toggle the grid overlay |
| Mouse at screen edge / WASD / arrow keys | Pan the camera within the battlefield |
| Mouse wheel | Zoom in or out |
| Hold middle mouse and drag | Rotate the camera |
| Hold right mouse and drag | Grab and pan the map at the camera's focus height |
| F / Home | Center the manually selected unit, including its elevation |
| Alt + mouse wheel | Cycle legal surfaces under the cursor; the floor hint, movement preview and click use the same choice |
| Q / E or Page Up / Page Down | Rotate the camera with the keyboard |

Units start their phase with 2 AP and have 100 HP. Attacks deal 25 damage. Attack range uses grid distance with diagonal targeting and corner blocking. Every unit uses `UnitStats.speed` for its movement budget. Animation speed is separate.

Camera height gently follows the manually selected unit; selection does not automatically recenter horizontal position. Focus preserves zoom and rotation. Edge scrolling retains a 36-pixel inner band and 72-pixel outside tolerance, and pauses during mouse camera gestures, over UI, or on focus loss. Left click is reserved for selection and orders. The original selection outline is unchanged.

Stacked-floor selection resets to the nearest legal surface when the set of cells under the cursor changes. Alt + wheel can select intermediate floors as well as ground; a selected lower floor also filters unit picking by that elevation. Selection through geometry does not bypass combat line of sight or movement/AP rules.

Run `godot_console --headless --path . --script res://tests/elevation_selection_smoke.gd` for screen-ray checks of refinery tower tops, stair surfaces, ground beneath decks, unit selection and camera recovery.

## Understand the code

Start with the [documentation index](docs/index.md). It links the architecture guide, simulation commands, reproducibility notes, and the asset-import workflow.

The prototype has weighted 3D paths, low-cover vaulting, directional cover, elevation-aware line of sight, ladders, ramps, stairs, platforms, movement previews, selection, AP, shared actions, faction relationships, attacks, defense, autonomous allied and enemy turns, generated maps, mission actors, seven playable objective rules, battle results, a tactical camera, and health displays.

Match setup supports zero to five green AI allies. Turns proceed from player to allies to enemies. Allies use the same validated movement, attack, and defense actions as every other combatant, are friendly toward players, and are hostile toward enemies. Allies do not appear in the player portrait selector and cannot be selected manually.

The 32×24 test battlefield is a systems lab: separated 5v5 spawn zones, long firing lanes, a central gate complex, a southern vault course, twin platforms, a three-route high platform, and stacked decks that allow units above and below the same X/Z position.

All combatant Beans currently use a shared 10-tile attack range to make cover and visibility testing easier. A future weapon definition will supply each unit's effective range and damage.

## Verify changes

With the Godot console executable on your PATH:

```powershell
godot_console --headless --path . --editor --quit
godot_console --headless --path . --script res://tests/battle_smoke.gd
godot_console --headless --path . --script res://tests/match_setup_smoke.gd
godot_console --headless --path . --script res://tests/portrait_bar_smoke.gd
godot_console --headless --path . --script res://tests/map_data_smoke.gd
godot_console --headless --path . --script res://tests/combat_cover_smoke.gd
godot_console --headless --path . --script res://tests/vault_smoke.gd
godot_console --headless --path . --script res://tests/battlefield_layout_smoke.gd
godot_console --headless --path . --script res://tests/elevation_smoke.gd
godot_console --headless --path . --script res://tests/vertical_traversal_smoke.gd
godot_console --headless --path . --script res://tests/elevation_combat_smoke.gd
godot_console --headless --path . --script res://tests/battlefield_stress_smoke.gd
godot_console --headless --path . --script res://tests/debug_tools_smoke.gd
godot_console --headless --path . --script res://tests/map_validation_smoke.gd
godot_console --headless --path . --script res://tests/flat_map_generator_smoke.gd
godot_console --headless --path . --script res://tests/objective_foundation_smoke.gd
godot_console --headless --path . --script res://tests/core_objectives_smoke.gd
godot_console --headless --path . --script res://tests/battle_pause_menu_smoke.gd
```

The smoke tests load the real battle scene and check terrain data, shared player/AI action validation, movement, AP, attacks, walls, defense, enemy turns, selection UI, and defeat cleanup. Play the scene to check appearance and combat feel.

`MapValidator` checks the completed runtime `MapData` before combat starts. A valid map prints its cell, traversal-link, and spawn-cell totals. Invalid maps report stable issue codes and readable messages for invalid cells, path-state mismatches, stale LOS indexes, broken traversal links, bad or insufficient spawn cells, and disconnected opposing spawn zones. A failed validation leaves the battle in its transition state instead of starting on broken data.

The match setup can launch a deterministic generated map. Enable `USE GENERATED MAP`, enter an integer seed, and start the battle. `FlatMapGenerator` creates the ground, faction spawn cells, seeded tactical cover formations, and accessible rooftops directly as `MapData`; `MapGraphBuilder` derives pathfinding from that data, validation approves it, and units spawn from its cells. Barricades, corners, low walls, and staggered positions rotate and move with the seed while cover density stays comparable. Reusing a seed reproduces spawns, cover, and buildings. Spawn bands and a central route remain clear.

Test the default batch of seeds 1 through 100 without opening a battle scene:

```powershell
godot_console --headless --path . --script res://tests/map_generation_batch_smoke.gd
```

Pass a first seed and number of seeds after `--` to test another reproducible range:

```powershell
godot_console --headless --path . --script res://tests/map_generation_batch_smoke.gd -- 5000 250
```

The batch exits unsuccessfully and lists exact seeds and validation messages if any generated map is structurally invalid. It also rejects scattered layouts when fewer than 75% of cover cells have an orthogonally adjacent cover neighbor.

## Debug tools

Generated maps offer Small (24×20), Medium (32×24), and Large (40×30) sizes in match setup. The size control is disabled for the handmade test map. Floor, grid lines, camera zoom and pan limits follow the selected dimensions.

Blue steel containers occupy 3×2 cells (or the rotated 2×3 footprint), are 2 m tall, and block movement and shots. Their footprints are stored in MapData; visuals read the same cells used by combat. Container roofs are not walkable in this step. Container placement reserves surrounding space and the central corridor, and counts toward the existing cover budget. Seed reproducibility requires the same map size and generator version.

Run `godot_console --headless --path . --script res://tests/container_maps_smoke.gd` to validate 100 seeds per size plus full-team runtime spawning and camera bounds.

Generated maps place solid buildings with 3 m walkable roofs and a ground-to-roof ladder. `GeneratedBuildingExpansion` adds an alternate stair approach where space permits and gives each building a seeded 65% chance of a coherent 2×2 utility floor at 6 m, reached by a second ladder. Stairs use ordinary neighboring cells at heights 1 and 2; the existing one-level step rule connects them to ground and roof. Stairs and upper-floor walls block movement and LOS beneath their surfaces. Reserved approaches keep later cover placement clear. These are exterior routes; interiors, larger upper floors, and smooth generated ramps remain deferred while generation work is paused.

Generated maps contain seeded freestanding platforms at elevation levels 2 or 3. Their decks are ordinary walkable `MapData` cells with local pathfinding and click surfaces. Generated ladders, stairs, or ramps connect every deck to the ground and reserve their route from later cover placement.

Match Setup also offers **Special — Refinery**, a 40×30 fixed industrial shell with four elevated service platforms, two reachable tower caps, and two connecting catwalks. It guarantees visible ladder, stair, and ramp examples while seed-generated containers and smaller cover change between battles. Generic buildings and the large-map hill are excluded from this preset.

Generated mission placement runs after the completed 3D path graph is available. Reach zones favor balanced contested positions, friendly and enemy extraction zones sit across the battlefield from their pursuing faction, and rescue actors favor tactically useful cells away from both deployments. Placement may use reachable elevated cells, keeps all mission areas separate from deployments and one another, and rejects unreachable results during map validation. Run `godot_console --headless --path . --script res://tests/generated_mission_placement_smoke.gd` to exercise 80 standard and refinery maps.

`MapQualityEvaluator` measures generated battlefields without changing or rejecting them. Its report compares nearby cover access, viable route branches, and spawn exposure between opposing deployments; it also records open-space density, the largest connected open region, and clear firing-lane lengths. The report exposes separate cover, route, open-space, firing-lane, and spawn-safety scores plus the weakest category. Every initialized battle prints a compact `[MapQuality]` line containing the seed and raw measurements. The overall score is diagnostic rather than a generation pass/fail rule. Run `godot_console --headless --path . --script res://tests/map_quality_metrics_smoke.gd` to analyze 80 maps and print reproducible low-, middle-, and high-ranked examples for playtest calibration.

`AIMatchSimulator` runs the ordinary battle scene with player control delegated to the existing AI. It records mission outcome, rounds, decision count, elapsed time, and the map-quality report, while classifying non-completion as a stall, round limit, timeout, or setup failure. The batch smoke test cycles through all seven mission presets and accepts optional first-seed, match-count, and mission-offset arguments: `godot_console --headless --path . --script res://tests/ai_match_simulation_smoke.gd -- 23001 7 0`. This harness does not simplify combat or objective rules; it automates the same AI-vs-AI mode available through F3.

Non-completing simulations produce a JSON seed-failure report under `user://ai_sim_failure_reports`. Each report records the complete configuration, map identity and dimensions, validation errors, final state, and structured AI decision trail. The batch prints its absolute file path for immediate reproduction. Run `godot_console --headless --path . --script res://tests/seed_failure_report_smoke.gd` to verify report serialization.

Completed battles retain an in-memory authoritative replay. The end screen provides **Replay Battle** and **Return to Match Setup** buttons. Replay rebuilds the same seeded match, disables ordinary input and AI, and submits recorded movement, attacks, defense, rescue, extraction, and turn advances through the shared gameplay rules. Run `godot_console --headless --path . --script res://tests/battle_replay_smoke.gd` to verify recording, playback, and both end-screen controls.

Every match has a visible battle seed, including authored maps. Combat rolls use a battle-scoped RNG initialized from that seed, alongside the seeded AI decision stream; generated maps currently use the same value for their separate map-generation stream. Repeating the same authored map, battle configuration, action order, and seed therefore reproduces its combat outcomes. The simulation batch rotates through Small, Medium, and Large generated maps so size is part of its coverage. Run `godot_console --headless --path . --script res://tests/ai_match_determinism_smoke.gd` for the authored-map repeatability check.

Large 40×30 maps add one seeded 7×7 terraced hill. Its three walkable elevation tiers use the ordinary one-level step rule, while solid terrain beneath the surface blocks movement and line of sight.

Generated building presentation uses readable concrete walls, a recessed roof cap, doors, window panels, and rooftop utility details. The scene combines cool ambient fill with an angled warm directional light so opposing facades remain visible. These decorative pieces have no gameplay collision; movement, cover, and LOS still come exclusively from `MapData`.

To playtest this 6D slice: run the project with **F5**, enable `USE GENERATED MAP`, choose Medium (32×24), enter seed `12345`, and start a battle. Move a unit to the steps, then click the roof to climb; compare this with the yellow ground ladder. From the roof, use the second ladder to reach the 2×2 utility floor. Check descent, AP use, and attacks at different heights. This seed should report 786 cells and 2 traversal links. Restart with the same size and seed to reproduce the layout. Run `godot_console --headless --path . --script res://tests/generated_buildings_smoke.gd` for 300 seeds plus runtime movement, AP, occupancy, and click-surface checks.

The battle scene's `DebugTools` node exposes `Debug Tools Enabled` in the Inspector. When enabled, a small hint appears at the top right. Press **F3** or **Esc** to toggle the debug panel and pause or resume the battle; **Resume Battle** also closes it. `Show battle-data overlay` displays live round, phase, active-unit, coordinate, HP/AP, movement, range, map-cell, and occupancy data.

## Mission actors

Every tactical unit has a `MissionActor` component. Faction controls relationships and targeting; the mission actor independently identifies a `COMBATANT`, `VIP`, or `RESCUABLE` and whether that actor can extract others. Spawned units receive unique mission IDs, while existing Beans remain ordinary combatants. Enable the debug overlay to inspect the active unit's mission ID and role.

The VIP is additional to the selected player combatants and reserves one allied spawn slot. Enabling it therefore permits up to four ordinary AI allies.

1. **Player Controlled:** appears in the portrait bar and uses normal player actions.
2. **Follow Escort:** activates during the allied phase, approaches a player combatant, then defends.
3. **Hold Position:** remains on its spawn tile and defends.
4. AI-controlled modes require at least two friendly slots so the VIP has an escort.

## Objective foundation

1. **Eliminate:** victory when all enemies are defeated.
2. **Reach:** immediate victory when a player or AI ally reaches the zone.
3. **Protect:** eliminate all enemies while every protected ally/VIP survives; losing one causes defeat.
4. **Rescue:** approaching the neutral VIP picks them up; the carrier moves more slowly and must extract while carrying them. Once the VIP is being carried, other friendly units may also evacuate.
5. **Extract:** every living player or allied unit can evacuate individually through a zero-AP action. Extraction has no generic turn minimum: an eligible unit may leave as soon as its objective is active and it occupies the zone. Dead units leave the required pool. A VIP is required only when enabled in match setup. All included VIPs must extract; after at least one ordinary unit extracts, the player may end early and leave others behind. Extracting everyone ends automatically.
6. **Survive:** survive three rounds, then evacuate every remaining unit; early departure is disabled.
7. **Enemy Evacuation:** defeat every enemy before any reaches the orange evacuation zone. One successful enemy escape causes defeat.

Mission and objective definitions are Godot Resources, so future missions can save required and optional objectives as data. Each battle receives separate runtime state with progress plus active, completed, or failed status. `ObjectiveManager` validates the definitions, observes battle events, and applies the selected mission's victory and defeat rules.

The setup menu offers Eliminate, Protect, Rescue, Reach, Survive, Extract, and Enemy Evacuation presets. Starting the battle loads the selected definition and prints an `[Objectives] ACTIVE` message with its kind, requirement, and target. Progress, completion, and failure also print as objective events.

The temporary top-right objective readout shows every required and optional objective, its status, and its progress. Any player-controlled unit standing in the green zone receives an **EXTRACT** button beside it, including exhausted units. Extract missions also expose **End Mission** after at least one ordinary unit and every included VIP are safe.

Deployment, objective, and extraction areas share one `MapZoneData` format inside `MapData`. Each zone has an ID, kind, cells, and an optional owning faction. Map validation rejects empty zones, repeated coordinates, missing cells, and terrain where a unit cannot legally stop. Authored scenes and generated maps therefore supply the same mission-space data.

`Manual enemy control` stops automatic enemy decisions. During each enemy activation, use the ordinary Move, Attack, and Defend buttons, then press End Turn to advance the enemy queue. `AI controls both teams` is a hands-off simulation mode and cannot be active together with manual enemy control.

`Show shot trajectories` draws the selected visible aim line used by combat validation while Attack mode is active and a unit is hovered. Combat samples five points scaled to the target's standing height. Green is a fully clear shot, amber is a legal covered or partially obstructed shot, and red is illegal. Illegal trajectories remain visible through geometry to reveal where the path crosses an obstacle.

When a shot is blocked, its LOS cell is covered by a translucent red marker. The battle-data overlay reports that cell's coordinate, cover type, and height. `Show AI decision explanations` displays the latest automated actor, chosen action and subject, reason, and actions it considered as alternatives.

Automated units also receive a mission intent derived from the active objective. The console prints `[AI Goal]` at activation, and the AI decision overlay shows the same mission goal beside the combat action. This foundation identifies Reach, Extract, Protect, Rescue, Survive, and Eliminate goals; later AI tasks decide how each goal competes with combat choices.

For Reach and Extract missions, AI-controlled players and allies choose the nearest path-reachable cell in the corresponding `MapData` zone before considering ordinary combat movement. Reaching a destination completes Reach immediately. Units entering extraction submit the same zero-AP Extract request as manually controlled units, leave occupancy and the turn roster, and update the mission report. If mission movement cannot be performed, the unit falls back to its legal attack or defense choices.

For Protect missions, an AI ally outside a three-cell escort radius moves back toward the protected actor before resuming normal combat decisions. For Rescue missions, AI-controlled players and allies approach a neutral rescue target, submit the shared zero-AP Rescue request from an adjacent cell, accept the existing carrying movement penalty, and then pursue the unlocked extraction objective. Friendly VIP behavior modes remain independent from these combatant mission goals.

For Survive missions, automated players and allies cannot evacuate while the round requirement remains active. They score reachable positions by directional cover, distance from living hostiles, travel cost, and proximity to extraction, reposition when a safer staging cell is available, and retain their remaining AP for combat or defense. Once the survival timer completes, their mission intent changes to Extract and they evacuate through the normal shared action.

Enemy Evacuation assigns the enemy faction an optional Extract objective and a dedicated orange exit across the battlefield. Enemy AI pathfinds to that zone and submits the same zero-AP Extract request. Defeating every evacuee completes the player's required objective; the first escape fails it. The battle result reports escaped enemies separately from friendly units and VIPs.

Automated teammates share a lightweight per-team `SquadContext` for the current round. It records destination reservations, attack intentions, focus counts, and objective handlers. Exact reserved destinations are rejected, nearby reservations apply a soft crowding penalty, and each ally already targeting an enemy reduces that target's score without forbidding useful focus fire. Rescue carriers become mobile protected actors, so later allies support the carrier until the VIP is safe. F3 lists the objective-handler, destination, focus-fire, and carrier-support adjustments that affected the latest decision.

Match setup offers **Easy**, **Normal** (default), and **Hard** AI for both automated teams. `AIDifficultyPolicy` changes target, movement, exposure, and survival-position scoring; Normal uses the baseline weights. Easy favors less precise targeting and cover use and accepts a modest exposure increase, while Hard prioritizes vulnerable targets, cover, and squad spacing more strongly. Easy occasionally selects a plausible near-best target or movement tile (22% chance when one exists); Normal does so less often (8%); Hard always takes its top-scored option. These choices are seeded by the match seed, and F3 labels a chosen alternative as a lapse with both scores. All tiers still use the same AP, movement, attack, and objective action validation. The selected tier appears in the startup log and F3 AI decision explanation.

For movement, `AIPositionScorer` compares reachable stopping tiles on or near a route. It balances progress toward the goal, directional cover, incoming firing lanes, future shots, crossfire or close-enemy danger, and squad reservations. Goal progress has extra weight on mission routes so a useful flank does not turn into endless sightseeing. F3 shows the selected tile's score components. Dangerous tiles currently mean combat exposure; environmental hazards are not represented yet.

For attacks, `AITargetScorer` ranks legal targets by injury/finishing opportunity, VIP status, shots they can take against friendlies, mission urgency, and existing squad focus. Mission urgency includes enemies threatening a protected VIP or rescue carrier, enemies targeting the carrier, obstacles to a rescue or destination, and enemy evacuees nearing their exit. F3 shows the chosen target's score components. The scorer does not change shot legality, accuracy, or damage.

When no legal shot is available after a first move, an automated combatant can spend its remaining AP advancing again toward a Reach, Extract, Rescue, or combat goal. It compares enemy firing lanes and directional cover at the proposed tile with its current exposure; it advances when the move does not worsen that exposure, otherwise it Defends. This also applies to enemies without a player-owned mission objective. Protect and Survive retain their cautious positioning behavior.
