# FuseFire Prototype 1.5 — XCOM 2 Tactical Systems Comparison

**Research date:** 2026-10-08  
**FuseFire baseline:** branch `p2-foundation`, baseline commit `53e429f`  
**Scope:** read-only comparison. No XCOM code, names, assets, or runtime dependencies are proposed for FuseFire.

## Evidence and limits

The primary XCOM evidence is the installed War of the Chosen SDK at:

`C:\Program Files (x86)\Steam\steamapps\common\XCOM 2 War of the Chosen SDK`

The investigation used `Development\SrcOrig\XComGame\Classes` and the shipped `XComGame\Config` files. The base-game SDK was checked where useful, but the War of the Chosen source is the more complete reference for the installed game. A statement marked **verified** is visible in UnrealScript, configuration, or a caller-visible native declaration. A statement marked **inference** follows from those interfaces but cannot be confirmed because its native C++ body is absent from the SDK.

The comparison uses the current FuseFire implementation and the verified baseline in `docs/research/prototype-1.5-baseline.md`, rather than planned features. This report describes architectural principles, not permission to implement every candidate.

## Executive finding

XCOM's tactical architecture is built around a durable separation:

1. a template describes an action and its rules;
2. an ability state checks whether a specific unit may use it and gathers legal targets;
3. an activation context records intent;
4. the ruleset builds and submits an authoritative game-state transaction;
5. effects change cloned state objects inside that transaction;
6. a separate visualization tree presents the accepted result;
7. the history retains the submitted states and their contexts.

FuseFire already follows parts of this model: tactical state belongs to units, the grid, objectives, and turn manager; presentation is delegated through visual adapters; action scripts route through `BattleController`; AI, player input, and replay use common execution entry points; and deterministic replay checks state fingerprints. The weakest seam is that legality, prediction, execution, replay payload creation, and presentation scheduling still meet inside a broad controller rather than at one explicit action transaction boundary.

The useful Prototype 1.5 direction is therefore a small FuseFire-native action contract and an explicit resolved-action result. Recreating XCOM's object history, hundreds of template/effect subclasses, native voxel grid, Kismet mission layer, or general visualization DAG would add machinery that FuseFire does not yet need.

## 1. Unit state and visual representation

### XCOM trace

- `XComGameState_Unit.uc` is the authoritative unit state. It stores stats, action points, inventory references, effects, team and tactical position data. `GiveStandardActionPoints` (line 6380 in the installed source) and `SetupActionsForBeginTurn` (6414) mutate tactical state, while native stat accessors begin near 6369.
- The same class exposes the presentation boundary through `FindOrCreateVisualizer` (1754), `SyncVisualizer` (1818), `AppendAdditionalSyncActions` (2023), and `CreatePawn` (6839).
- `XGUnit.uc` is the unit actor/visualizer. It owns pawn-facing behavior, animation and presentation work. It can be recreated or synchronized from `XComGameState_Unit` rather than serving as the authoritative record.
- `XComWorldData.SyncVisualizers` and `SyncReplay` (`XComWorldData.uc`, lines 754–755) synchronize the represented world to a history point or submitted state.
- `XComGameState_BaseObject`, `XComGameState`, and `XComGameStateHistory` provide the broader object-reference and historical-state mechanism used by the unit state.

**Verified flow:** authoritative data lives in game-state objects; actors and pawns visualize those objects. State objects know how to locate/create/synchronize a visualizer, but the visualizer is not the source of tactical truth.

**Unavailable detail:** parts of visualizer lookup, synchronization, state storage, and object cloning are native. The SDK proves the boundary and calls, but not every internal operation.

### FuseFire comparison

`units/tactical_unit.gd` owns HP through `UnitStats`, AP, faction, grid position, mission/carry state, and current traversal data. `systems/grid/grid_manager.gd` owns occupancy. `UnitVisualAdapter` and the character rig/animation controller present state and are tested not to mutate HP, AP, or grid position. This is already the same essential separation, implemented with Godot nodes rather than historical UObject snapshots.

The remaining coupling is practical rather than conceptual: `TacticalUnit` is both a scene node in the world and the holder of authoritative fields, while lifecycle events, movement interpolation, visual adapters, extraction, and replay all touch the live node. That is adequate for the present scale; a detached universal entity store would solve no demonstrated problem.

### Useful principle

Treat presentation as a consumer of accepted tactical results. Make it possible to resynchronize a unit's visual state from authoritative fields after interruption, skip, replay seek, or scene reload.

### Poor fit for FuseFire

Do not reproduce the UObject history/visualizer registry or split every unit into an XCOM-shaped state object plus actor. Godot resources and nodes have different lifetimes, and FuseFire already enforces the important authority rule with much less machinery.

**Classification: ALREADY PRESENT.** Add targeted resynchronization hooks only when an interruption or replay-seek use case proves they are needed.

## 2. Action and ability definitions

### XCOM trace

- `X2AbilityTemplate.uc` is the declarative definition. Its fields include `AbilityCosts` (line 50), shooter/target/multi-target conditions (54–56), shooter/target/multi-target effects (57–59), triggers (60), target styles, hostility, UI data, and presentation metadata.
- The template delegates separate rule and presentation responsibilities: `BuildNewGameStateFn` (216), `BuildInterruptGameStateFn` (217), `BuildVisualizationFn` (218), synchronization delegates (219–220), and merge/post-visualization hooks.
- `CheckShooterConditions`, `CheckTargetConditions`, and `CheckMultiTargetConditions` (450–452) are native template checks. `CanAfford` (346), `WillEndTurn` (378), `GetTotalPointsUsed` (427), and `ApplyCost` (455) expose the cost contract.
- `XComGameState_Ability.uc` is the per-owner runtime instance. `UpdateAbilityAvailability` (67) fills an `AvailableAction`; `CanActivateAbility` (111) evaluates activation; `GatherAbilityTargets` (287, native) supplies candidates; `WillEndTurn` (597) and damage-preview methods expose consequences to callers.
- `XComGameStateContext_Ability.uc` records input and result data, including ability, source, primary and additional targets, target locations, movement paths, hit results, and effect results. Its static `ActivateAbility` path builds a context and submits it through the ruleset around lines 1309–1419.
- `X2Ability.uc::TypicalAbility_BuildGameState` (line 281) is the common resolver used by many templates. It applies costs and effects into a new state rather than directly animating actors.
- `UITacticalHUD_AbilityContainer.uc` calls `XComGameStateContext_Ability.ActivateAbility` at line 676. Task 02 established that AI ultimately selects an `AvailableAction` and uses the same activation path.

**Verified flow:** a definition supplies costs, conditions, targets, effects, resolution, and visualization delegates; a per-unit ability state turns it into legal choices; a context captures one requested activation; the ruleset accepts or rejects it and creates the state change.

### FuseFire comparison

FuseFire has small `UnitAction`, `MoveAction`, `AttackAction`, `DefendAction`, `RescueAction`, and `ExtractAction` scripts. Player input, AI, and replay route through shared `BattleController` operations, and `CombatRules` centralizes attack evaluation. This prevents separate player and AI combat implementations.

However, the action scripts do not yet expose one uniform contract for availability, targets, AP cost, projected result, authoritative execution, replay payload, and presentation request. Mission actions also cross into `ObjectiveManager`. This is why adding equipment actions, statuses, or cancellation would currently enlarge controller branching.

### Useful principle

Define a small semantic action interface that can answer:

- is this action available, and why not;
- what legal targets or destinations exist;
- what it costs and whether it ends activation;
- what deterministic result is predicted for UI/AI;
- how the accepted request resolves into state changes;
- what stable data is recorded for replay and presentation.

Migrate existing actions one at a time and require identical deterministic outcomes before adding new mechanics.

### Poor fit for FuseFire

Do not begin with XCOM's universal template manager, name-based template registry, trigger taxonomy, or one subclass per tiny condition/effect. FuseFire has six actions and no demonstrated need for hundreds of data-authored combinations. Godot resources with typed composition can provide editability without recreating Unreal's class ecosystem.

**Classification: ADOPT IN 1.5.** This is the most useful foundation experiment, provided it starts with one existing action and retains the current public controller path during migration.

## 3. Effects, damage, modifiers, and status conditions

### XCOM trace

- `X2Effect.uc` is the base effect definition. It supplies application checks, hit-result gating, game-state application hooks, damage and hit modifiers, preview information, and visualization hooks.
- `X2Effect_Persistent.uc` adds duration, duplicate-effect behavior, removal rules, event registration, periodic ticking, stat changes, and effect conditions.
- `XComGameState_Effect.uc` is the runtime record. It stores its template reference, source and target references, application parameters, duration/turn counters, and registered-event behavior. This separates a reusable effect definition from one applied instance.
- `X2Effect_ApplyWeaponDamage.uc` calculates and applies weapon damage through game state. Unit-side damage handling continues in `XComGameState_Unit.TakeEffectDamage` (line 5689) and death processing in `OnUnitDied` (5979).
- `X2Condition.uc` and its many subclasses provide reusable checks for units, effects, visibility, ranges, values, and tactical state. Costs follow the same compositional pattern under `X2AbilityCost*`; `X2AbilityCost_ActionPoints.uc` checks and consumes action points.
- `X2EventManager` connects persistent effects and triggered abilities to state events. `RegisterForEvent` (238), `TriggerEvent` (268), and state/visualization deferral hooks (275–298) are native interfaces.

**Verified flow:** ability effects are definitions; persistent applications create runtime effect-state objects; conditions gate application or activation; costs and modifiers participate in resolution; damage reaches authoritative unit state. Event listeners support reactions and duration behavior.

**Unavailable detail:** many condition checks, event queues, and low-level damage/history operations are native. The composition model is verified; all ordering semantics are not fully visible.

### FuseFire comparison

FuseFire has direct damage, hit chance, cover modifiers, AP, defend/skip behavior, and mission/carry states. These are explicit and well tested, but there is no general status/effect runtime because Prototype 1 did not need one. Planned suppression, EMP, hacking, shields, armor, equipment actions, and component damage would create such a need.

### Useful principle

When the first concrete status feature is selected, separate:

- an editable definition;
- an applied runtime instance with source, target, duration, and stack policy;
- pure modifier queries;
- explicit lifecycle events;
- authoritative application/removal results suitable for replay.

### Poor fit for FuseFire

Building a general effect framework before selecting two or three real FuseFire mechanics would encode imaginary requirements. XCOM's subclass count, duplicate policies, implicit global event names, and expansion-driven exceptions are evidence of scale, not a desirable starting size.

**Classification: DEFER TO PROTOTYPE 2.** In 1.5, record requirements and perhaps prototype the contract only if an approved action migration needs a minimal modifier representation.

## 4. Tactical turns and action sequencing

### XCOM trace

- `X2GameRuleset.uc` is the submission boundary. Its comment above `SubmitGameStateContext` states that AI and UI use it to indicate an intended action (lines 200–209). `SubmitGameStateContext_Internal` begins at 410; it builds, validates, submits, and queues the resulting state work. `SubmitGameStateContexts` (303) supports ordered groups.
- `X2TacticalGameRuleset.uc` owns tactical phase progression, player turns, unit actions, interruption handling, end-of-battle checks, and the rules cache used by UI and AI.
- `XComGameState_Player` stores team/player action-phase state, while `XComGameState_Unit.SetupActionsForBeginTurn` and action-point methods initialize unit opportunities.
- `XComGameStateContext_Ability` can submit normal or latent contexts. Interrupt state and resume behavior flow into visualization actions through `X2Action.BeginInterruption`, `ResumeFromInterrupt`, and `CompleteAction` (`X2Action.uc`, lines 521, 594, 644).
- `X2EventManager` has immediate, state-submitted, and visualization-related deferral points, so reaction effects can be ordered against authoritative submission and presentation completion.

**Verified flow:** UI or AI proposes a context; the ruleset converts it into one or more submitted states; turn/AP state changes occur authoritatively; interrupts and reactions can insert more states; visualization is scheduled around the accepted history entries.

### FuseFire comparison

`TurnManager` is already the phase and activation authority. Units receive and spend AP, player Skip and AI Wait end an activation, automated teams advance in a deterministic order, and objectives can end the battle independently. `BattleController` executes and awaits actions, while replay records accepted operations.

The legal ordering is distributed among live nodes and signals. A controller operation can combine validation, mutation, presentation waits, replay commit, AI logging, and turn advancement. This makes cancellation and interruption harder to define: cancelling a preview is trivial; cancelling after authoritative mutation is not.

### Useful principle

Give every action an explicit lifecycle: proposed, validated, resolved, committed, presenting, completed. Define a point after which cancellation becomes a new action or rollback operation rather than silently undoing live state. Keep turn advancement dependent on committed results, not animation completion side effects.

### Poor fit for FuseFire

Do not import XCOM's multiplayer-aware state submission queue, interrupt graph, or reaction system until FuseFire has an actual reaction mechanic. A lightweight transaction/result boundary is enough for current turns.

**Classification: ADOPT IN 1.5.** Define the lifecycle and cancellation semantics alongside the action-contract experiment; full reactions remain Prototype 2 work.

## 5. Movement, occupancy, cover, and line of sight

### XCOM trace

- `XComWorldData.uc` exposes a native, quantized 3D tile/voxel world. `BuildWorldData` (739) constructs it from the playable level volume. Coordinate and floor conversions occupy lines 771–790.
- Visibility is native: `CanSeeTileToTile` (861), location/tile voxel ray traces (862–863), fog data, viewers, and cached visibility updates.
- Cover is precomputed/queryable through `GetCachedCoverAndPeekData` (870), directional cover helpers (886–891), and cover-point queries (892–895).
- Occupancy and destination legality are exposed by `GetUnitsOnTile`, `AreOtherUnitsOnTile`, `SetTileBlockedByUnitFlag`, `IsTileBlockedByUnitFlag`, `IsTileOccupied`, and `CanUnitsEnterTile` in the 923–940 region.
- Environmental hazards and destruction update tile data; poison, smoke, fire, acid, destructibles, floor validity, ladders, and traversal objects all participate in the world representation.
- Movement is activated as an ability and carries path tiles in `XComGameStateContext_Ability`; presentation is performed by `X2Action_Move` and related traversal actions after the move state is accepted.

**Verified boundary:** one native world service answers tile, occupancy, cover, visibility, hazard, and traversal queries used by rules and AI. The exact spatial algorithms are unavailable because the important bodies are native.

### FuseFire comparison

FuseFire already has a shared tactical representation: `MapData`/`MapCellData`, `GridManager`, weighted `Pathfinder`, `CombatRules`, traversal links, continuous elevation and stairs, occupancy, directional cover, and LOS. Generated and authored maps share this data. Preview and execution use the same combat evaluation, and focused tests cover corner LOS, full/low cover, occupancy, elevation, traversal, and map validation.

FuseFire's seamless height model is an intentional strength. It should not be replaced with XCOM's discrete floor presentation or native voxel assumptions. The current system is also inspectable GDScript/data rather than an opaque engine subsystem.

### Useful principle

Keep legality queries centralized and reusable by UI, AI, validation, and execution. Cache only after profiling identifies repeated expensive queries, and attach cache invalidation to explicit occupancy/map revisions.

### Poor fit for FuseFire

Reject a direct port of XCOM's native world grid, cover-point cache, voxel visibility, destructible environment propagation, or floor model. They depend on Unreal's coordinate, actor, level, native-memory, and destruction systems and would undermine FuseFire's continuous vertical traversal.

**Classification: ALREADY PRESENT** for the shared movement/cover/LOS authority. **Classification: REJECT** for replacing it with the XCOM spatial model. Performance caches are **INVESTIGATE FURTHER** only after measurement.

## 6. Mission objectives and event-driven state changes

### XCOM trace

- `XComGameState_ObjectivesList.uc` stores display-facing objective records and exposes get/set/hide/clear operations. It is not the whole mission-rules system.
- Tactical mission logic is distributed across mission/game-state classes, Kismet sequence actions (`SeqAct_*`), and events. Examples include `SeqAct_SpawnAdditionalObjective`, `SeqAct_DisplayMissionObjective`, `SeqAct_CompleteMissionObjective`, `SeqAct_SpawnEvacZone`, and state-changing actions for units, loot, visibility, narrative, and transfer.
- `SeqAct_SpawnAdditionalObjective` assigns a `BuildVisualizationFn` and builds objective presentation from a submitted change, demonstrating that mission scripting can create authoritative state plus later UI presentation.
- `X2EventManager.TriggerEvent` accepts optional event data, source, and a game state. Its `OnGameStateSubmitted`, `PreGameStateSubmitted`, `OnVisualizationBlockStarted`, and `OnVisualizationBlockCompleted` hooks permit event work at known phases.
- `X2TacticalGameRuleset` performs end-of-battle evaluation and coordinates tactical state transitions; mission scripts and objective/event state feed that decision.

**Verified conclusion:** XCOM combines persistent objective display state, mission-specific scripted state changes, a global event bus, and ruleset win/loss evaluation. It is deliberately flexible, but responsibility is spread across templates, Kismet, events, and tactical rules.

### FuseFire comparison

FuseFire's `MissionCatalog` defines seven mission families and `ObjectiveManager` owns activation, progress, mission actors, AI intent, and victory/defeat. Objective definitions/runtime states are data, and explicit signals connect mission progress to the battle. This is simpler and already reusable across current mission types.

The pressure point is `ObjectiveManager` itself: rules, mutation, actor queries, action side effects, AI intent, logging, and result evaluation converge there. Adding many interactive objectives could turn its central branching into the same distributed complexity seen in XCOM, just inside one file.

### Useful principle

Express objective changes as explicit typed events/results emitted by committed actions—unit entered zone, actor rescued, carrier extracted, round ended, unit defeated. Let each objective definition consume only the events it needs and return progress/result changes. Keep one mission coordinator responsible for ordering and final win/loss resolution.

### Poor fit for FuseFire

Do not adopt Unreal Kismet sequence actions, string-only global events, or separate display objectives as the primary mission truth. FuseFire's missions benefit from typed resources and direct test fixtures.

**Classification: INVESTIGATE FURTHER.** Prototype one existing objective as an event consumer only after the action result schema exists; retain current behavior and compare exact mission/replay outcomes.

## 7. Tactical AI interaction with legal actions

### XCOM trace

- `XComGameState_Ability.UpdateAbilityAvailability` populates an `AvailableAction`, including `AvailableCode`; `CanActivateAbility` and `GatherAbilityTargets` provide the legal choice set.
- The tactical rules cache exposes per-unit available actions and targets. Ability triggers elsewhere in `XComGameState_Ability.uc` repeatedly locate the matching cached action, require `AA_Success`, then call `XComGameStateContext_Ability.ActivateAbility` (for example lines 1540–1623).
- Task 02 traced `X2AIBTDefaultActions.SelectAbility` to `XGAIBehavior.IsValidAbility`; `XGAIBehavior.BTExecuteAbility` resolves the selected cached `AvailableAction` and submits it through the same context/ruleset route as player activation.
- AI target and movement scoring choose among candidates supplied or checked by tactical rules. They do not define a second damage or AP system.

**Verified flow:** AI chooses semantic intent, target, and destination from rules-engine candidates; the shared ability/rules layer remains the authority and can reject stale choices.

### FuseFire comparison

FuseFire already routes AI through `BattleController` and `ObjectiveManager` methods shared with player/replay execution. Its target and position scorers do not apply damage themselves. Candidate generation and rejection are nevertheless partly embedded in `AIController`, and the controller must know several action-specific APIs.

### Useful principle

Let AI consume the same structured action queries as UI and replay: legal actions, legal targets/destinations, cost, expected outcome, and rejection reason. AI may score and coordinate choices, but it should never need to reproduce action legality.

### Poor fit for FuseFire

Do not add XCOM's rules cache shape or behavior tree just to obtain this boundary. A short-lived query snapshot keyed to an authoritative state revision is enough; stale snapshots should be revalidated on commit.

**Classification: ADOPT IN 1.5.** This is the AI-facing benefit of the action-contract work, not a separate AI rewrite.

## 8. Visualization and animation after authoritative decisions

### XCOM trace

- `X2AbilityTemplate.BuildVisualizationFn` converts an accepted game state into visualization tracks; `BuildAppliedVisualizationSyncFn` and `BuildAffectedVisualizationSyncFn` handle state synchronization.
- `X2Ability.TypicalAbility_BuildVisualization` constructs common fire, hit, damage, death, sound, camera, and effect actions from the submitted ability context and state changes.
- `VisualizationActionMetadata` and `X2Action.AddToVisualizationTree` attach presentation actions to a dependency tree. Parent/child relationships permit parallel and ordered work.
- `X2Action.uc` is the asynchronous presentation base. It supports interruption, timeouts, immediate mode, completion, and emits `X2Action_Completed` (lines 644–762). `X2Action_Move`, `X2Action_Fire`, and `X2Action_ApplyWeaponDamageToUnit` are representative consumers of already-resolved results.
- `X2EventManager` has visualization block start/completion deferrals, allowing presentation-timed reactions without making animation the combat authority.

**Verified flow:** gameplay resolution creates history; the accepted context/result is translated into an action tree; visual actions move pawns, play animations/effects, and notify presentation events; completion releases later visualization or turn work.

### FuseFire comparison

FuseFire has `UnitVisualAdapter`, animation controllers, tactical/action cameras, shot feedback, overlays, and action-specific `await` paths. Tests prove visual calls do not directly change tactical HP/AP/grid position. Replay drives the same authoritative operations and receives presentation.

The difference is orchestration: `BattleController` often performs mutation and awaits movement/animation/camera work within one method. It is understandable at current scale, but it makes skipped animation, fast replay, cancellation, headless simulation, and recovery depend on branches inside the action executor.

### Useful principle

Have an accepted action return a compact presentation plan or resolved result containing movement path, shot result, damage, defeat, objective changes, and relevant identities. A presentation coordinator can play it normally, instantly, or not at all. Visual completion may gate input pacing, but should not decide whether damage or movement occurred.

### Poor fit for FuseFire

Do not implement a fully general visualization DAG now. XCOM needs it for simultaneous projectiles, reactions, cinematic cameras, destruction, multi-target abilities, and interrupts. FuseFire can begin with a sequential list plus explicitly parallel groups if a real action needs them.

**Classification: ADOPT IN 1.5.** Introduce the resolved result/presentation seam during one action migration; grow sequencing only from demonstrated cases.

## 9. Replay, debugging, and deterministic behavior

### XCOM trace

- `XComGameStateHistory.uc` stores submitted game states and contexts, retrieves historical object versions, and supports state inspection/resynchronization. The ruleset submits changes into this history rather than treating actor state as the record.
- `XComGameStateContext.uc` is the provenance attached to a state change; ability contexts preserve input and outcome details used by validation and visualization.
- `UIDebugHistory.uc` exposes history inspection. `UIReplay.uc` disables/enables visualization building and moves through history/replay setup; `XComWorldData.SyncReplay` applies a processed state to the world.
- `X2EventManager` exposes validation and debug-string functions (`ValidateEventManager`, `AllEventListenersToString`, `PendingEventToString`, lines 345–362).
- Deterministic gameplay relies on synchronized random facilities and authoritative history. `XGUnit.uc` also contains a synchronized random-sample buffer (`AddRandomSampleToBuffer`, `GetSyncRand`, `GetRandomSample`, lines 183–208) for presentation behavior that must remain synchronized.

**Verified conclusion:** XCOM has strong historical state provenance and debugging around submitted changes. The available SDK supports replay/history visualization and synchronization. It does not, by itself, prove that every campaign/tactical session is a portable, version-stable player replay format.

### FuseFire comparison

FuseFire records semantic actions in `battle_replay_recorder.gd`, plays them through authoritative operations in `battle_replay_player.gd`, and compares `battle_state_fingerprint.gd` results. Seeded map, combat, and AI streams support headless same-seed reproduction. This is simpler and more directly testable than cloning XCOM's entire object graph.

FuseFire's known weakness is schema durability: replay actions are dictionary/string-kind payloads without an explicit version and migration boundary. Its logs also lack a single typed action-result record joining request, legality, random draw, mutations, objective changes, and presentation.

### Useful principle

Version replay records and derive debug traces from the same committed action result. Record enough inputs and resolved random outcomes to diagnose divergence. Keep deterministic simulation independent of presentation timing.

### Poor fit for FuseFire

Do not replace semantic replay with full snapshots of every Godot node/resource after every action. That would increase file size, couple saves to scene internals, and weaken the current ability to replay through real rules.

**Classification: ALREADY PRESENT** for deterministic semantic replay and fingerprint checking. **Classification: ADOPT IN 1.5** for an explicit replay schema version and action-result identity if the action contract changes.

## Cross-system decision matrix

| Candidate | Classification | Reason |
| --- | --- | --- |
| Authoritative tactical state separated from character visuals | **ALREADY PRESENT** | Current unit/visual-adapter tests already enforce the important rule. |
| Small query/validate/resolve action contract | **ADOPT IN 1.5** | Reduces controller coupling and serves UI, AI, replay, equipment, and future statuses. |
| Explicit committed action result and presentation plan | **ADOPT IN 1.5** | Clarifies authority, cancellation, headless execution, replay, and animation sequencing. |
| Defined action lifecycle and cancellation boundary | **ADOPT IN 1.5** | Needed before adding XCOM-like cancellation or reactions; can remain small. |
| Versioned replay/action-result schema | **ADOPT IN 1.5** | Protects current deterministic evidence during foundation changes. |
| Data-driven persistent status/effect system | **DEFER TO PROTOTYPE 2** | Needs concrete suppression/EMP/shield/equipment use cases before design. |
| Objective rules consuming typed committed events | **INVESTIGATE FURTHER** | Promising decomposition, but should follow action-result work and be trialed on one existing objective. |
| Query caching keyed to state/map revisions | **INVESTIGATE FURTHER** | Valuable only if profiling proves current legality/spatial queries are a bottleneck. |
| Full reaction/interrupt system | **DEFER TO PROTOTYPE 2** | No approved mechanic currently requires XCOM's sequencing complexity. |
| XCOM-style behavior tree | **REJECT** for 1.5 | Task 02 found the useful rules boundary can serve FuseFire's utility AI without a new runtime. |
| Native voxel world, discrete floor model, and destructible propagation | **REJECT** | Unreal-specific and conflicts with FuseFire's inspectable seamless-height representation. |
| Kismet-like mission scripting and global string event bus | **REJECT** | Typed Godot resources/signals and focused objective rules are simpler and more testable here. |
| Full historical clone of every tactical object | **REJECT** | Semantic replay plus compact resolved results fits FuseFire's scale and engine better. |
| General visualization dependency graph | **INVESTIGATE FURTHER** | Start sequentially; add explicit parallel dependencies only for demonstrated multi-part actions. |

## Proposed priorities

These priorities are proposals for review, not implementation performed by this task.

### 1. Specify one FuseFire action transaction

Choose `AttackAction` because it exercises legality, a target, AP, seeded randomness, cover/LOS, damage, defeat, replay, camera, and animation. Write the contract before moving code: query, request, validation result, resolved result, commit, presentation, completion. Preserve the existing `BattleController` entry point as an adapter during the experiment.

**Gate:** the replay battle at seed `23001`, combat-cover tests, battle smoke tests, AI determinism, and milestone outcomes must remain identical.

### 2. Separate committed result from presentation timing

Make the migrated action produce an immutable-enough result record that can be presented normally, instantly, or headlessly. It should include stable unit identities, AP change, hit roll/outcome, damage/defeat, and presentation cues without holding presentation nodes as authority.

**Gate:** the same action result must yield the same final fingerprint with presentation enabled and suppressed.

### 3. Version the replay boundary

Add an explicit schema version and validate action/result fields. Do not promise indefinite compatibility yet; fail clearly when a recording uses an unsupported version. Tie this to the migrated action so the schema reflects real data rather than a speculative universal format.

**Gate:** current replay fixtures either migrate deliberately or produce a clear unsupported-version result; no silent key mismatch.

### 4. Expose the query to AI and UI

Once one action owns its legality and target/result preview, make both player preview and AI candidate evaluation consume it. Keep AI scoring separate from legality and revalidate at commit to handle stale occupancy or defeated targets.

**Gate:** deterministic decision traces and selected actions remain unchanged for the baseline scenarios unless a behavior change is separately approved.

### 5. Run one objective-event experiment only after priorities 1–4

Use a narrow existing transition such as unit-entered-extraction-zone or rescue completion. Feed the committed action result to one objective rule without rewriting all objectives. Compare mission progress, final result, replay, and AI intent against the current implementation.

**Gate:** all seven mission families retain their current results in the Prototype 1 milestone matrix.

## What Prototype 1.5 should not do from this research

- It should not become an XCOM framework reconstruction.
- It should not replace continuous elevation, stairs, or FuseFire's grid with XCOM's floor/voxel implementation.
- It should not add a universal status framework before real FuseFire statuses are selected.
- It should not add behavior trees, Kismet, a global string event bus, or a general action DAG merely because XCOM uses them at a much larger content scale.
- It should not make imported XCOM animation or asset data a runtime dependency. Presentation architecture can be learned from the SDK while MIRA and original assets remain the production path.

## Final assessment

FuseFire already possesses the two foundations that matter most: authoritative tactical rules shared by humans, AI, and replay; and presentation that is prevented from owning HP, AP, and grid state. XCOM demonstrates how far those ideas can scale when every action is expressed as a legal ability request, a submitted state transaction, and a later visualization sequence.

The next useful experiment is smaller than XCOM's solution: migrate one action to a uniform query/request/result contract, separate its presentation from its committed outcome, and protect it with the deterministic fixtures already established. Persistent effects, reactions, generalized mission events, and richer visualization sequencing can then be designed from actual Prototype 2 mechanics rather than copied in advance.
