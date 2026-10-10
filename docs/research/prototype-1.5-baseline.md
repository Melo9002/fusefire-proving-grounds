# FuseFire Prototype 1.5 — Baseline Architecture Audit

**Audit date:** 2026-10-08  
**Working tree:** `p2-foundation` at `53e429f017740e0f959bf5afd78ae93f5172553b`  
**Initial state:** clean; local branch matched `origin/p2-foundation`  
**Scope:** read-only inspection of the current implementation plus targeted verification. This report is the only intentional repository change.

## Purpose and evidence labels

This is the baseline for Prototype 1.5. It records what FuseFire does now so later XCOM research can inform small, reviewable experiments without quietly redefining the game.

Every assessment uses one of these labels:

- **Verified implementation** — present in the current source, scene, resource, or a test run performed for this audit.
- **Verified architectural weakness** — a concrete coupling, duplication, fragile contract, or tooling problem visible in the current tree.
- **Suspected risk requiring testing** — plausible from the implementation, but not established strongly enough to call a defect.
- **Existing planned feature, not yet implemented** — described in plans or research, without a complete production implementation.

The audit treats XCOM as research evidence only. A different XCOM design is not, by itself, a reason to rewrite a working FuseFire subsystem.

## Repository baseline

| Item | Current state | Classification |
| --- | --- | --- |
| Branch | `p2-foundation` | Verified implementation |
| Commit | `53e429f` (`Reopen the XCOM notebook`) | Verified implementation |
| Upstream | `origin/p2-foundation` was at the same commit | Verified implementation |
| Working tree before audit | Clean | Verified implementation |
| Engine | Godot 4.7, Forward Plus, D3D12 on Windows, Jolt Physics | Verified implementation |
| Main scene | `res://ui/match_setup.tscn` | Verified implementation |
| Project version | `1.0.0` remains in `project.godot` while 1.5 work is on its foundation branch | Verified implementation |

The most relevant existing documentation is `docs/architecture.md`, `docs/code-organization.md`, `docs/simulation.md`, `docs/replay.md`, `docs/human-editing-guide.md`, `docs/animation-editing-guide.md`, `docs/asset-import.md`, `docs/prototype-1-audit-27a.md`, `docs/prototype-1-release.md`, the Prototype 2 planning documents, the MIRA experiment notes, and the Operation XCOM research ledger. These documents are useful context; the findings below were checked against the current tree rather than copied from them.

## Current architecture map

### Composition and configuration

- **Verified implementation:** `ui/match_setup.tscn` is the user-facing entry point. It produces battle configuration rather than hard-coding one mission launch path.
- **Verified implementation:** `systems/battle_configuration.gd` carries the battle seed, generated or authored map choice, size, mission, difficulty, team configuration, and related setup data.
- **Verified implementation:** `levels/prototype_map/battle_level.gd` is the battle composition root. It connects configuration, map generation or loading, validation, terrain presentation, unit and mission-actor spawning, controllers, cameras, replay, and UI.
- **Verified architectural weakness:** `BattleLevel` also contains substantial content-specific setup and spawning policy. A new battle presentation or radically different scenario is likely to touch the same large script instead of being assembled from a smaller scenario definition.

### Tactical state and units

- **Verified implementation:** `units/tactical_unit.gd` owns authoritative per-unit state such as faction, stats, action points, grid position, mission-actor state, carrying state, and the movement path being executed.
- **Verified implementation:** `units/unit_stats.gd` owns health and combat statistics; `systems/grid_manager.gd` owns unit-to-cell registration and occupancy.
- **Verified implementation:** presentation is delegated through the unit visual adapter. Tests confirm movement, shooting, hit, and defeat presentation do not modify authoritative HP, AP, or grid position.
- **Verified architectural weakness:** some gameplay, motion, and presentation tunables exist at multiple levels: unit resources/scenes, battle configuration, controller exports, and visual scenes. The values are editable, but ownership is not always obvious when two settings describe related concepts.
- **Suspected risk requiring testing:** removal, extraction, death, and replay all update overlapping unit lifecycle state. Existing tests cover representative paths, but exhaustive ordering and signal-lifetime cases are not established.

### Turn flow

- **Verified implementation:** `systems/turn_manager.gd` is the authoritative phase and activation coordinator. It supports player, ally, enemy, and transition phases; maintains rosters; advances rounds; selects player units; queues automated activations; removes or extracts units; and prioritizes a rescued-VIP carrier.
- **Verified implementation:** a unit may end its activation without spending all AP. The player-facing action is **Skip**; AI records a `WaitAction` with an explanatory reason.
- **Verified implementation:** turn completion and battle completion are distinct, and objective results can end the battle independently of eliminating every hostile.
- **Verified architectural weakness:** turn flow depends on mutable Node references and signals shared with the battle and objective controllers. This works, but the legal ordering is encoded across several classes rather than in one explicit transition model.

### Actions and combat

- **Verified implementation:** action types are represented by small scripts: `UnitAction`, `MoveAction`, `AttackAction`, `DefendAction`, `RescueAction`, and `ExtractAction`.
- **Verified implementation:** `systems/battle_controller.gd` remains the action authority exposed to player input, AI, replay, and mission systems. It validates and attempts moves, attacks, waiting/defending, rescue, extraction, and turn completion.
- **Verified implementation:** `systems/combat_rules.gd` evaluates range, line of sight, cover, hit chance, and attack legality. Combat randomness is seeded from the battle configuration.
- **Verified implementation:** `DefendAction` still exists as a supported internal action, but the player UI uses Skip and current AI deadlock recovery does not depend on repeatedly defending.
- **Verified architectural weakness:** `BattleController` combines input mode, cursor/path/cover/shot previews, authoritative action execution, pathfinding access, combat RNG, AI logs, squad contexts, replay commits, extraction, and action-camera triggering. The action classes are useful boundaries, but they have not removed the controller's broad ownership.
- **Existing planned feature, not yet implemented:** there is no general FuseFire ability/effect/state framework for equipment actions, statuses, suppression, hacking, shields, or future MIRA abilities. This is a research topic, not an immediate rewrite requirement.
- **Existing planned feature, not yet implemented:** fully data-driven weapon archetypes and equipment-dependent action sets are not yet the production combat model.

### AI and squad coordination

- **Verified implementation:** each automated unit uses `units/ai_controller.gd`, a seeded decision RNG, `AIDifficultyPolicy`, `AIPositionScorer`, and `AITargetScorer`.
- **Verified implementation:** `systems/ai/squad_context.gd` shares destination reservations, recent origins, carrier-corridor information, and other squad coordination state.
- **Verified implementation:** objective intent comes from the objective system. AI can advance, attack, rescue, carry, extract, support a carrier, reserve or avoid destinations, relax movement thresholds after stagnation, and finish an activation with a diagnostic reason.
- **Verified implementation:** difficulty changes scoring and permits intentional, believable mistakes rather than only changing health or damage.
- **Verified implementation:** decision traces expose candidate rejection reasons, scoring components, goals, and waits; debug overlays can inspect scores and heatmaps.
- **Verified architectural weakness:** `AIController` is the largest concentration of gameplay policy. It mixes activation orchestration, mission-specific behavior, route and carrier-corridor logic, combat decisions, survival rules, movement scoring, target scoring, stagnation recovery, animation waits, and trace formatting.
- **Verified architectural weakness:** several tests call private AI methods and inspect private fields. They provide strong regression coverage but make internal refactoring expensive even when behavior is unchanged.
- **Suspected risk requiring testing:** current reservations are local tactical safeguards rather than a general plan with explicit ownership and expiry semantics for every possible interruption.
- **Existing planned feature, not yet implemented:** formal tactical roles, commander doctrines, explicit controller/faction separation, broad ally/hostile/neutral relationships, and reusable multi-faction squad policies remain Prototype 2 ideas.

### Objectives

- **Verified implementation:** objective definitions and runtime states are resources/data, and `systems/objectives/mission_catalog.gd` assembles seven current mission families: Eliminate, Protect, Rescue, Reach, Survive, Extract, and Enemy Evacuation.
- **Verified implementation:** `systems/objectives/objective_manager.gd` activates objectives, tracks progress, exposes mission intent to AI, performs rescue/extraction-related transitions, and evaluates victory or defeat.
- **Verified implementation:** mission actors use explicit state and tags instead of being inferred only from faction.
- **Verified architectural weakness:** `ObjectiveManager` combines rule evaluation, state mutation, actor queries, action-side effects, AI intent generation, logging, and battle-result evaluation. New objective semantics are likely to increase this central switchboard unless a narrower boundary is introduced when a concrete feature demands it.
- **Suspected risk requiring testing:** objective identity and several payloads use `StringName` keys and dictionaries. Validation catches many mistakes, but schema evolution and malformed authored data are not fully type-enforced.

### Map data, generation, movement, and traversal

- **Verified implementation:** `systems/map_data.gd` is the shared tactical representation for authored and generated maps. It contains cells plus generation/presentation descriptors for cover, containers, structures, elevation, traversal, zones, LOS support, and transport footprints.
- **Verified implementation:** generated maps use the flat-map generator plus focused builders for cover, buildings, elevation, traversals, refinery layouts, mission placement, and terrain presentation.
- **Verified implementation:** `systems/map_validator.gd` and `systems/map_quality_evaluator.gd` check reachability, spawns, traversal, cover distribution, route fairness, exposure, lanes, and other quality signals.
- **Verified implementation:** `systems/pathfinder.gd` builds a weighted A* graph with diagonal-clearance rules, elevation, traversal links, occupancy, reachability, and movement costs. Stairs and traversals preserve FuseFire's continuous multi-height grid rather than switching whole map floors.
- **Verified architectural weakness:** `MapData` combines authoritative tactical cells with generated-world and presentation descriptors. This has enabled one shared representation, but it can make future authored-map and editor workflows depend on generator-specific fields.
- **Suspected risk requiring testing:** large maps and many AI candidates repeatedly query paths, LOS, exposure, and cover. Functional batch tests exist, but this audit found no current CPU, allocation, or frame-time profile that establishes scaling limits.

### Replay and deterministic simulation

- **Verified implementation:** replay is split among `battle_replay_recorder.gd`, `battle_replay_session.gd`, and `battle_replay_player.gd`. Actions are recorded, played through authoritative battle operations, and compared with expected state fingerprints.
- **Verified implementation:** replay includes controls for play, pause, step, and speed. The focused replay smoke test reproduced 39 actions and the expected defeat with zero failures.
- **Verified implementation:** `systems/simulation/ai_match_simulator.gd` runs battles headlessly; batch, result, and failure-report helpers support seed-based regression work.
- **Verified implementation:** battle seed, mission, map source, map size, difficulty, and related configuration make failures reproducible. Map generation, combat, and AI decisions use deterministic seeded streams.
- **Verified architectural weakness:** replay records are dictionary/string-kind data without an explicit versioned schema or migration boundary. Renaming keys or changing action payload meaning can invalidate old captures silently unless tests are updated with the code.
- **Suspected risk requiring testing:** determinism is verified inside the current engine/platform setup. Cross-version, cross-renderer, or cross-platform replay stability is not established.

### Presentation and camera

- **Verified implementation:** presentation code is grouped under `presentation/`: tactical and action cameras, obstruction handling, paths, cursors, cover/range/target overlays, shot trajectories, world bars, and team palette resources.
- **Verified implementation:** the action camera and tactical camera share battle state without becoming combat authority. Obstruction tests cover environmental hiding/cutaway behavior.
- **Verified architectural weakness:** `BattleController` directly owns or drives several presentation nodes and creates the action-camera director. Presentation is organized on disk, but its runtime dependency boundary is still partly embedded in the gameplay controller.
- **Existing planned feature, not yet implemented:** shared cinematic/replay camera grammar, polished live-action framing, roof and upper-floor presentation rules, and final tactical UI remain later work.

### Character rigging and MIRA Zero

- **Verified implementation:** `art/characters/mira_0/models/mira_0_prototype.glb` is tracked and instantiated by `mira_0_unit_visual.tscn`; the old bean is a fallback rather than the primary current character.
- **Verified implementation:** the MIRA scene uses the shared `UnitVisualAdapter`, `CharacterRig`, and `CharacterAnimationController`; it identifies its arm bones, creates editable IK targets and elbow poles, exposes weapon grip offsets, and supplies camera anchors.
- **Verified implementation:** the MIRA pose workbench can exercise idle, move, aim, shoot, hit, defeat, cover, traversal, pickup, carry, and boarding states. The runtime unit adapter test passed movement, shooting, hit, defeat, teardown, and tactical-authority isolation during this audit.
- **Verified implementation:** the current model is approximately 1.6 m through its scene scale and is already sufficient to validate framing, sockets, skeleton access, and state handoff.
- **Verified architectural weakness:** the reusable character scripts and some active tests still live under `art/characters/vroid_proof/`. MIRA therefore depends on a directory whose name describes a retired proof asset, obscuring current ownership.
- **Verified architectural weakness:** MIRA's `clip_library` is currently null. The controller generates fallback placeholder motion, so passing animation tests do not prove the final imported/retargeted animation pipeline.
- **Suspected risk requiring testing:** weapon alignment, two-hand contact, buttstock clearance, cover poses, root motion, and all traversal transitions need visual validation with the intended skeleton and future clips.
- **Existing planned feature, not yet implemented:** finished MIRA textures/materials, a canonical FuseFire skeleton contract, an original clip library, finalized retargeting, face rigging, modular/detachable parts, and production character customization.

## Cleanup and foundation work already completed

These items should not be reopened merely because the XCOM SDK contains a different solution.

- **Verified implementation:** the repository has current architecture, simulation, replay, human-editing, asset-import, animation-editing, release, and prior audit documentation.
- **Verified implementation:** pause behavior has an authoritative test; input and automated battle flow respect it.
- **Verified implementation:** player Skip and AI Wait replaced the proven repeated-Defend stalemate in normal decision flow, with readable reasons in logs.
- **Verified implementation:** AI target and position scoring are separated helpers, difficulty is data/policy-driven, and squad reservations/corridor behavior are explicit.
- **Verified implementation:** direct battle dependencies are injected/bound. The isolation test created two simultaneous battles plus an unrelated global objective manager and passed, demonstrating that AI and replay bind to their owning battle rather than arbitrary global discovery.
- **Verified implementation:** map validation, map-quality scoring, batch generation, deterministic AI simulation, seed failure reports, and replay verification exist.
- **Verified implementation:** presentation assets and team accents have a clear folder/resource structure; camera obstruction and action-camera behavior have focused tests.
- **Verified implementation:** important tunables are exposed through Inspector groups and human-editing guides rather than requiring every experiment to be a code edit.
- **Verified implementation:** Prototype 1 was packaged and released with a documented release checklist. That evidence applies to the release baseline; it is not automatic proof that every later 1.5 branch state is distributable.

## Remaining cross-cutting weaknesses and risks

| Finding | Classification | Practical consequence |
| --- | --- | --- |
| `AIController` carries too many forms of policy and orchestration | Verified architectural weakness | AI experiments collide in one file and tests depend on private implementation details. |
| `BattleController` spans authority, player interaction, replay hooks, AI context, and presentation | Verified architectural weakness | Adding actions or alternate controllers can require changes across unrelated concerns. |
| `ObjectiveManager` owns rules, mutation, queries, intent, and results | Verified architectural weakness | New mission types increase branching and coupling. |
| Scene/NodePath and signal wiring remain important runtime contracts | Verified architectural weakness | Scene reorganizations can fail at runtime even when scripts parse. Exported references reduce, but do not remove, this risk. |
| Replay payloads lack an explicit versioned schema | Verified architectural weakness | Old captures are fragile across action-contract changes. |
| Active MIRA code depends on the legacy `vroid_proof` location | Verified architectural weakness | Ownership is confusing and deleting the old proof asset would remove current runtime code. |
| Local XCOM files are Git-ignored but live below `res://` | Verified architectural weakness | Godot imported 251 local FBX entries during this audit, expanding cache/startup work and placing proprietary research inside the project import surface. A later task should move it outside the project or add a deliberate `.gdignore`; this audit did not change it. |
| Performance limits are inferred from batch completion, not measured profiles | Suspected risk requiring testing | CPU, GPU, memory, loading, and worst-case planning budgets remain unknown. |
| Full lifecycle ordering for death, extraction, objectives, replay, and presentation | Suspected risk requiring testing | Rare signal-order or teardown defects may exist outside covered scenarios. |
| Compatibility renderer and low-end Intel behavior after current branch changes | Suspected risk requiring testing | Prototype 1 release evidence should be rerun at the 1.5 gate. |

## Regression inventory and what it verifies

The test suite is primarily executable Godot scripts under `tests/`. It is broad and behavior-oriented, but there is no single machine-readable test manifest; release documents and milestone runners are the current suite index.

| Area | Tests | What they verify |
| --- | --- | --- |
| Core battle and turns | `battle_smoke`, `battle_pause_menu_smoke`, `allied_faction_smoke`, `match_setup_smoke` | Battle startup, phase progression, pause ownership, ally phase, and setup propagation. |
| Actions and combat | `combat_cover_smoke`, `diagonal_combat_test`, `shot_result_feedback_test`, `tactical_pose_test` | Cover/LOS/hit evaluation, diagonal rules, visible results, and tactical pose transitions. |
| Movement and traversal | `diagonal_movement_test`, `elevation_smoke`, `elevation_selection_smoke`, `vertical_traversal_smoke`, `vault_smoke`, `locomotion_foundation_test` | Legal paths, corner rules, elevation selection, traversal/vault links, facing/cadence, and return to idle. |
| Objectives | `objective_foundation_smoke`, `core_objectives_smoke`, `mission_actor_smoke`, `enemy_evacuation_smoke`, `survive_ai_smoke` | Objective lifecycle, mission-actor state, win/loss semantics, evacuation, and survive behavior. |
| AI fundamentals | `ai_difficulty_policy_smoke`, `ai_intentional_mistakes_smoke`, `ai_position_scoring_smoke`, `ai_target_scoring_smoke`, `ai_second_advance_smoke`, `ai_stalemate_recovery_smoke`, `squad_context_smoke` | Difficulty policy, controlled mistakes, score components, second movement, stagnation relaxation, and reservations. |
| Objective AI | `ai_mission_intent_smoke`, `objective_ai_navigation_smoke`, `protect_rescue_ai_smoke`, `rescue_carrier_support_smoke`, `rescue_refinery_congestion_smoke` | Intent translation, carrier priority/support, extraction route behavior, and the known refinery choke case. |
| Generation and quality | `flat_map_generator_smoke`, `container_maps_smoke`, `generated_buildings_smoke`, `generated_elevation_smoke`, `generated_mission_placement_smoke`, `generated_traversal_smoke`, `map_data_smoke`, `map_generation_batch_smoke`, `map_quality_metrics_smoke`, `map_validation_smoke`, `transport_placement_test`, `battlefield_layout_smoke`, `battlefield_stress_smoke` | Seeded generation, data integrity, placement, reachability, traversal, transport footprints, quality metrics, and stress layouts. |
| Simulation and determinism | `ai_match_simulation_smoke`, `ai_match_determinism_smoke`, `seed_failure_report_smoke`, `prototype_1_milestone` | Headless completion, same-seed repeatability, reproducible failure artifacts, and the release mission matrix. |
| Replay | `battle_replay_smoke`, `departure_replay_smoke`, `rescue_battle_replay_smoke` | Recorded action playback, state fingerprints, mission departures, rescue/carry/extract replay, and final result. |
| Presentation/debug | `action_camera_director_test`, `camera_obstruction_test`, `path_visualizer_cache_test`, `portrait_bar_smoke`, `unit_world_bar_lifetime_smoke`, `ai_scoring_overlay_smoke`, `debug_tools_smoke`, `debug_map_inspector_smoke`, `debug_mission_controls_smoke` | Camera choices, obstruction, cached paths, HUD lifetime, score visualization, debug defaults/controls, and map inspection. |
| Character pipeline | `unit_visual_adapter_test`, `animation_handoff_test`, `vroid_asset_import_test`, `vroid_pose_refinement_test`, `vroid_vertical_slice_animation_test`, `vroid_weapon_ik_test`, `locomotion_foundation_test` | Authority/presentation separation, skeleton/clip handoff, import assumptions, pose and IK controls, state transitions, and locomotion continuity. Several still exercise the legacy VRoid fixture. |
| Dependency boundaries | `battle_dependency_isolation_test` | AI and replay use their explicitly owned battle dependencies in a multi-battle tree. |

### Verification performed during this audit

- Godot headless editor import/parse completed with exit code 0. It also exposed the ignored-XCOM-import issue described above.
- `prototype_1_milestone.gd`: **0 failures**; 15/15 matches completed across all seven mission families, authored/generated cover/generated refinery sources, three map sizes, elevation, and traversal. Average was 7.3 rounds.
- `battle_dependency_isolation_test.gd`: **0 failures**.
- `battle_replay_smoke.gd`: **0 failures**; 39/39 actions verified and expected defeat reproduced.
- `rescue_refinery_congestion_smoke.gd`: **0 failures** on seed `733578405`; 208 decisions and 28 waits, completed as a defeat. This verifies termination and traceability, not good balance or guaranteed rescue success.
- `unit_visual_adapter_test.gd`: **pass** for move, shoot, hit, defeat, teardown, and tactical-authority separation with the current runtime unit visual.
- `locomotion_foundation_test.gd`: **0 failures**. Its isolated unit now disables world-HUD presentation explicitly instead of clearing the HUD resource and producing a misleading missing-dependency warning.

## Deterministic before/after scenarios

These are suitable gates for controlled 1.5 experiments:

| Scenario | Seed/source | Best use |
| --- | --- | --- |
| Prototype 1 mission matrix | Seeds `25000+`, `25100+`, plus authored seed `25200` | Broad behavior gate across every mission family, map sizes, refinery layouts, elevation, and traversal. |
| Refinery rescue congestion | `733578405`, generated refinery, 40×30 | Carrier priority, escort route clearing, reservations, stagnation, waits, and survival under pressure. |
| Replay battle | `23001`, generated cover, 24×20 | Authoritative action compatibility and replay fingerprint preservation. |
| Dependency isolation | `8100` and `8101` | Multi-battle ownership and rejection of accidental global dependencies. |
| Transport placement | `1`, `23001`, `372339682` | Stable transport/extraction footprint placement. |
| Seed failure reporting | `8675309` | Reproduction artifact and failure-report workflow. |
| Same-seed AI determinism fixture | Authored deterministic battle | Decision and result repeatability without generator noise. |

For an architecture-only change, the expected comparison is identical decisions, actions, fingerprints, and final results. For an explicitly approved behavior experiment, preserve the seed and configuration and record the intended delta rather than treating every changed trace as a regression.

## Third-party and local-only material

- **Verified implementation:** `research/xcom-local/` is ignored by Git. At audit time it contained roughly 265 local files and 741 MB of SDK research/export material. No XCOM asset is tracked in the repository.
- **Verified implementation:** Operation XCOM documentation marks extracted animations as local reference/temporary placeholder material that must not be committed or redistributed.
- **Verified architectural weakness:** `.gitignore` prevents commits but does not stop Godot imports. Because the folder is inside the project root, Godot currently treats its FBXs as project resources unless a `.gdignore` boundary or external location is used.
- **Verified implementation:** the tracked AUG proof asset includes `AUG_ATTRIBUTION.md` and records its CC BY 4.0 attribution.
- **Verified implementation:** the tracked VRoid proof includes intake/runtime reports and workflow/license notes. It remains a proof fixture and should not be assumed to grant rights for final character distribution beyond those documented terms.
- **Verified implementation:** MIRA Zero is tracked as the current user-provided prototype model. This audit found no embedded XCOM animation library in its runtime scene.
- **Suspected risk requiring testing:** the final export preset should be audited for accidental inclusion of research, review renders, proof assets, and source-only material even when Git ignores some of it.

## What Prototype 1.5 can safely build on

Prototype 1.5 does not begin from a fragile tech demo. It already has deterministic tactical authority, seven objective families, continuous elevation and traversal, AI-vs-AI simulation, explainable utility scoring, squad reservations, replay verification, generated-map validation, organized presentation systems, and a real MIRA model exercising the visual boundary.

The strongest candidates for later controlled upgrades are the boundaries already under pressure: action contracts around `BattleController`, policy decomposition around `AIController`, objective semantics around `ObjectiveManager`, a versioned replay/data contract, and a character pipeline whose reusable code no longer belongs to the VRoid proof. Each should begin with a concrete FuseFire use case and the deterministic scenarios above. XCOM findings can support or reject an experiment; they do not pre-authorize a framework.

The immediate baseline also exposes two practical housekeeping items for separate approval: keep proprietary research outside Godot's import surface, and distinguish tests of generated fallback animation from tests of the future production clip/retargeting path.
