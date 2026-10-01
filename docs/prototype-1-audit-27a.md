# Prototype 1 — 27A Repository-Wide Audit

Date: 2026-09-30  
Branch: `refactor/prototype-1-cleanup`  
Behavioral reference: home commit `5da9a73`  
Cleanup baseline: `c072b4d`

This is the canonical recovery audit for Prototype 1. It separates confirmed defects, verified cleanup improvements, measured optimization targets, and deferred ideas. No gameplay implementation changed during 27A except correcting a test coroutine parse error found by the audit.

## Preserved starting state

The checkout already contained a whitespace-only modification to `tests/debug_mission_controls_smoke.gd` and two untracked UIDs:

- `art/characters/vroid_proof/runtime/character_rig.gd.uid`
- `tests/battle_dependency_isolation_test.gd.uid`

The test now also contains the required `await` for `force_extract()`. It passes with zero failures, and the editor scan reports no project-script parse error.

## Result

The cleanup branch is a sound recovery base. Most changes are UID-preserving moves, documentation, small performance improvements, shared character presentation, and clearer dependency wiring. No cleanup-caused gameplay regression was confirmed.

Two shared Prototype 1 defects are confirmed:

1. Pause does not authoritatively stop tactical continuations.
2. Extract seed `25005` enters a deterministic no-progress Defend loop.

## Keep from the cleanup

- Responsibility-based actions, components, camera, and overlay folders.
- Preserved resource UIDs and runtime scene names.
- Shared `character_rig.gd` for demo and runtime.
- Explicit ObjectiveManager dependencies for AI and replay.
- Explicit presentation root for DebugTools.
- Path geometry reuse and indexed unweighted queues.
- Stress assertions based on durable outcomes.

The branch does not yet have one universal tile-marker system. PathVisualizer already serves configurable movement and attack ranges; a wider presentation theme remains future work.

## P0 — behavioral recovery

### Pause authority

A controlled probe paused during AI activation. In both repositories AP changed, the logical cell changed, and movement/action state began while paused.

Default `SceneTree.create_timer()` calls continue while paused. Relevant waits include `ai_controller.gd:84,123`, `battle_controller.gd:393,416`, `objective_manager.gd:181,215`, `tactical_unit.gd:117`, `unit_visual_adapter.gd:215`, and `character_animation_controller.gd:86`. Gameplay frame and deferred continuations also require verification.

### AI no-progress loop

The full matrix produced the same result in home and cleanup:

- 15 matches; 14 completed.
- Seed `25005`, Extract, exceeded 30 rounds.
- Identical final state and 272 decisions.
- PlayerUnit4 defended 55 times.
- Each remaining enemy defended 25–27 times.

Movement must beat holding position, safe second movement rejects excess exposure, and no urgency grows after repeated no-progress turns. Before changing weights, record all fallback decisions, hold score, acceptance threshold, movement history, revisit penalty, remaining AP, and no-progress age.

The desired correction is bounded urgency: progressively value objective progress and accept controlled exposure after repeated no-progress turns, while carriers, VIPs, and critically injured units remain more cautious.

## P1 — ownership and coupling

- `map_builder.gd` scans SceneTree-wide terrain groups, while BattleLevel can hide or disable every matching authored node. Remaining global service lookups should become battle-local incrementally.
- ObjectiveManager and AI select behavior through prototype mission IDs. Treat current IDs as contracts until each policy is migrated with tests.
- BattleController owns ordinary actions, locks, and replay, while ObjectiveManager coordinates rescue/extract and manipulates BattleController state. Document both transaction paths before extracting anything.
- Replay uses runtime node names and literal scene paths. Names, UIDs, animation paths, exports, and key paths remain compatibility contracts.
- AIController, DebugTools, BattleController, CharacterAnimationController, and ObjectiveManager mix several responsibilities. Split only cohesive responsibilities behind stable interfaces; avoid a big rewrite.
- `AIDifficultyPolicy.score_target()` and `score_path_progress()` are tested but unused by production. Replace their tests with live scorer coverage before removing them.

## P1 — human editing and art workflow

### Character profiles

`character_rig.gd` hardcodes the VRoid, AUG, controller, bones, and markers. Create a `CharacterPresentationProfile` resource containing model/weapon scenes, animation data, bone mapping, marker names, contacts, IK, recoil, effects, rescue offsets, locomotion, camera settings, and optional material/faction presentation. The current VRoid/AUG becomes the first profile.

A compatible character should be installable through the Inspector without editing shared scripts.

### Animation workflow

The skeletal workbench cannot preview the assembled weapon, IK, effects, passenger, or procedural fall. Keep it as the safe clip editor, then add an assembled preview using the same profile and runtime rig.

Clip lengths, sequence timings, and adapter return timers have different owners. Move presentation timing into profile/clip metadata or await animation completion with gameplay timeout safeguards.

Author stable attachment/effect nodes in a reusable scene where that improves inspection. Move team colors, overlays, offsets, widths, recoil, effects, and camera timing into focused profile/theme resources. Avoid a universal visualizer superclass.

### Documentation and storage

Documentation still contains Beans-era claims and `asset-import.md` says `assets/` while the project uses `art/`. Adopt:

`art/characters/<character_id>/{source,models,textures,materials,animations,runtime,demo,docs}`

The VRoid review folder contains hundreds of tracked disposable outputs. Keep selected references and archive reproducible frame sequences outside the main repository or adopt an intentional large-file policy.

## P1 — optimization candidates

### Shared hover sampling

MouseRaycaster and BattleController repeat floor raycasts every frame; attack hover repeats them and adds unit intersections. Give one owner responsibility for hover sampling. Cache by frame, mouse, camera, and selected floor; invalidate after camera, viewport, unit, floor, or map changes. Recalculate paths and previews only when inputs change.

### Deterministic priority queues

Pathfinder and MissionPlacementEvaluator repeatedly sort weighted frontiers. Replace this behind current interfaces with a stable queue. Preserve neighbor and equal-cost order; compare reachable sets, costs, decisions, and replay fingerprints.

### Safe hygiene

- Gate unconditional PathVisualizer logging and its diagnostic `get_faces()` allocation.
- Avoid recomputing reachability after AI has already evaluated a move while preserving authoritative validation.
- Disable processing for inactive debug nodes where safe.

### Measure first

Profile AI path/LOS multiplication, generated-terrain draw calls, VRoid animation/skinning/IK/shadows, range construction, MapQualityEvaluator startup cost, and world-bar polling.

Record CPU/GPU frame time, draw calls, objects/materials, memory/VRAM, setup time, range latency, AI latency, and path/LOS/raycast counts. Test authored and largest generated maps with 2, 10, and 20 humanoids in Forward+ and Intel Compatibility mode.

## Protected invariants

1. TacticalUnit, GridManager, action gateways, AP/HP, and ObjectiveManager own gameplay truth.
2. Animation, IK, camera, root motion, and overlays never decide legality, occupancy, damage, or mission progress.
3. Actions preserve validation, state mutation, presentation, completion, and event order.
4. Pause stops every tactical mutation and continuation.
5. Seeded randomness, neighbor order, tie-breaking, movement history, and reservations remain deterministic.
6. Mission-ID rules remain contracts until migrated individually.
7. Actor names, UIDs, animation paths, exports, and replay identifiers remain stable.
8. Eligible zero-AP extraction remains valid and replay mirrors it.
9. BattleLevel remains the composition root.

## 27A disposition

Keep the verified cleanup. Repair next:

1. authoritative pause tests and implementation;
2. AI no-progress trace and watchdog snapshot;
3. bounded objective urgency with seed `25005` coverage;
4. stale rescue/extraction assertions;
5. clean import/export verification.

Defer broad controller rewrites, universal services, wholesale mission-policy migration, global LOS caches, VRoid fidelity reductions, and mesh batching without measurements.

## Recovery status

The first two confirmed defects were repaired during the following 27B pass:

- Pause now stops tactical timers, AI continuations, movement/action entry points,
  objective interactions, outcome evaluation, and turn advancement. The pause
  smoke test snapshots authoritative and presentation state during an enemy turn.
- Every AI decision now records its cell, remaining AP, movement history, hold
  score, move threshold, Defend streak, urgency bonus, route corridor, and scored
  candidates in the F3 debug tools and simulation results.
- Bounded urgency begins only after repeated Defends. It gradually lowers the
  movement acceptance gate and widens the useful route corridor, with no urgency
  applied to carriers, VIPs, or units at critical health.
- The former seed `25005` extraction loop now completes in round 6. Its dedicated
  regression test and the full 15-match Prototype 1 matrix both pass.

## Human-maintainer acceptance tests

A developer should be able to replace a character, edit and preview a clip, adjust IK and weapon contacts, replace a weapon, change faction/overlay presentation, tune gameplay and camera values, add a mission without hidden name surprises, trace an action end-to-end, and reproduce a seed with an explanation for every AI Defend.

## Validation gates

1. Clean parser/import scan.
2. Focused subsystem tests.
3. Fixed-seed path, decision, mission, and replay comparisons.
4. All missions and generated map kinds.
5. Batch generation and AI simulation.
6. Replay round trips.
7. Forward+ and Compatibility visual checks.
8. Before/after profiler evidence.
9. Human editing exercises.

27A is complete when this document is accepted as the recovery baseline. Implementation continues with behavioral recovery before architecture and optimization changes.
