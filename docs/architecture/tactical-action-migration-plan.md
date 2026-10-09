# FuseFire Prototype 1.5 — Tactical Action Architecture and Migration Plan

**Plan date:** 2026-10-08  
**Roadmap milestone:** Task 01.1  
**Starting branch:** `p2-foundation` at baseline commit `53e429f`  
**Status:** Task 01 implemented on `p2-foundation` through commit `a315a96`; this document retains the original audit and records the final architecture below

## Purpose

FuseFire needs one native tactical action pipeline:

> **Query → Validate → Resolve → Commit → Present**

The goal is not to preserve Prototype 1's action classes or controller APIs. It is to preserve intentional gameplay while making actions safe and comprehensible for player input, AI, replay, objectives, headless simulation, and future equipment. This plan uses the current implementation, the Prototype 1.5 baseline, both XCOM comparisons, and the supplied master roadmap as evidence.

The central conclusion is that the current `UnitAction` subclasses are only mutation helpers. The real action pipeline is distributed across `BattleController`, `ObjectiveManager`, `TurnManager`, `TacticalUnit`, UI controllers, AI, replay, cameras, and signals. The migration should replace that distributed protocol with a single action service and typed request/result records. It should not wrap the existing branches in another façade.

## 1. Current execution-path inventory

### Shared entry points and state

| Concern | Current owner | Verified behavior |
| --- | --- | --- |
| Player selection and targeting | `BattleController`, `ActionHUDController`, mouse raycaster | Buttons toggle controller modes; hover computes previews; clicks call `try_move` or `try_attack`. Skip calls `try_end_unit_turn`. Extraction can be invoked from a unit world bar. |
| AI choice | `AIController` | AI builds mission intent and scores targets/destinations, then calls `BattleController.try_attack`, `try_move`, `try_end_unit_turn`, or `ObjectiveManager.try_rescue`/`try_extract`. |
| Replay | `BattleReplayPlayer` | Dictionary records are decoded by string `kind`, actors are found by scene-node name, and the same controller/objective methods are invoked. |
| Legality | `BattleController`, `CombatRules`, `MoveAction`, `AttackAction`, `ObjectiveManager`, `TurnManager` | Checks are split. The gateway checks phase/busy state; rule helpers check range/LOS/path/mission state; action objects repeat some AP/unit checks. |
| Single-flight guard | `BattleController.is_action_in_progress` | Most actions reject while busy. Objective actions reach into the controller and set the flag themselves. `TurnManager.end_current_turn` is outside this guard. |
| RNG | `BattleController._combat_rng`; AI has a separate decision RNG | `try_attack` consumes one combat roll before constructing `AttackAction`; preview calls `CombatRules.evaluate_attack` and consumes no roll. `AttackAction` falls back to global `randf()` if no override is supplied. |
| Authority | Live `TacticalUnit`, `UnitStats`, `GridManager`, `ObjectiveManager`, `TurnManager` nodes | Mutations happen immediately on these objects. There is no transaction record or central revision. |
| Presentation | Controller, objective manager, unit, visual adapter, camera director | Camera may begin before mutation. Movement presentation occurs inside the live unit. Attack/hit/defeat presentation is triggered by unit/stat signals and controller calls. |
| Replay recording | `BattleController.record_replay_action`, `TurnManager.turn_ended`, `BattleReplayRecorder` | Records are dictionaries. Recorder adds a post-action state fingerprint when it receives a committed signal. No schema version exists. |
| Turn advancement | `TurnManager`, AP signals, AI | Player AP exhaustion schedules deferred selection; movement is specially awaited. AI also calls `end_current_turn` after its activation. Extraction alters rosters and selection directly. |

### AttackAction

**Initiators**

- Player: `BattleController._on_unit_clicked` while attack mode is active.
- AI: several branches in `AIController` call `battle_controller.try_attack`.
- Replay: `BattleReplayPlayer._execute` resolves actor and target names, then calls `try_attack`.
- Tests call the gateway directly.

**Query and legality**

- UI hover uses `BattleController.evaluate_attack`, which delegates to `CombatRules.evaluate_attack`.
- `try_attack` checks pause, `is_action_in_progress`, and `TurnManager.can_unit_act`, then evaluates attack legality.
- `AttackAction.is_valid` repeats actor/target validity, carrying restriction, defeat, hostility, and AP checks. It does not check range, LOS, cover, active turn, or the busy guard.

**Targets**

- Player target comes from the unit under the mouse.
- AI obtains hostiles and scores them in `AIController`/`AITargetScorer`, then relies on `try_attack` for final legality.
- Replay uses `record["target"]`, currently a scene-node name.

**Cost, RNG, and mutation**

- AP cost is `BattleController.UNIFORM_AP_COST`.
- `try_attack` consumes `_combat_rng.randf()` after the `CombatRules` legality check but before the action's repeated validation.
- `AttackAction.execute` consumes AP, compares the supplied roll with hit chance, and applies a fixed 25 damage on hit.
- `UnitStats.take_damage` emits HP/defeat signals. `TacticalUnit` starts hit/defeat presentation; defeat reaches `BattleController._on_unit_defeated`, which emits a battle lifecycle signal, unregisters occupancy, removes the unit from turn rosters, and later frees its visual body.
- `ObjectiveManager._on_unit_defeated` reacts to the battle signal and mutates objective progress/failure, roster totals, mission report, and possibly battle outcome.

**Replay and presentation**

- Action camera presentation begins before `AttackAction.execute`.
- After mutation, the attacker presentation is requested, `attack_resolved` is emitted, and a replay record stores target name, hit result, and hit chance. The random roll is not stored.
- Camera completion is awaited after commit/recording. AP exhaustion may schedule player selection while this presentation is still finishing.

**Completion/failure/cancellation**

- Any precheck returns `false` without a structured reason.
- Failure after the camera starts is possible if repeated validation changes; the camera has no explicit cancellation result in that branch.
- There is no cancellation after submission. UI mode cancellation only occurs before `try_attack`.

### MoveAction

**Initiators**

- Player: movement mode hover/click in `BattleController`.
- AI: destination selection in `AIController`, followed by `try_move`.
- Replay: destination array decoded and sent to `try_move`.

**Query and legality**

- Player range preview uses `Pathfinder.get_reachable_cells` filtered through `GridManager.can_unit_occupy_cell`.
- `try_move` recalculates reachable cells, path, and destination occupancy.
- `MoveAction.is_valid` repeats actor/AP/path/occupancy checks but does not verify that the supplied path is still the authoritative route or within budget.

**Destination, cost, and mutation**

- Player destination is a clicked grid cell; AI selects a scored cell; replay stores a cell vector.
- Cost is one AP regardless of route length within the movement budget.
- `MoveAction.execute` consumes AP, immediately updates authoritative grid occupancy from origin to destination, then starts `TacticalUnit.move_along_path`.
- The unit's world transform remains between cells during presentation while authoritative occupancy already points to the destination. This is intentional reservation behavior but currently implicit.

**Objective, replay, and presentation**

- Camera starts before execution.
- Controller awaits `movement_finished`, emits `unit_moved`, then records the move and finishes the camera.
- `ObjectiveManager._on_unit_moved` may complete Reach or automatically rescue an adjacent VIP. Automatic rescue is therefore a consequence of movement, not a separate submitted action. Its changes are expected to appear in the move fingerprint.
- Movement animations/IK segments are derived in the controller using `tactical_pose_context.gd`, currently under the legacy `vroid_proof` path.

**Completion/failure/cancellation**

- Movement has no mid-path tactical cancellation. Once occupancy/AP commit, animation completes the accepted move.
- `TurnManager` specially waits for movement before selecting another player unit after AP exhaustion.
- No structured rejection explains unreachable, occupied, moving, inactive, paused, or stale destinations.

### DefendAction

**Initiators**

- Normal Prototype 1 gameplay no longer exposes Defend.
- Replay retains `defend` support for legacy captures.
- Tests exercise it as a shared-gateway legality check.

**Flow**

- `BattleController.try_defend` checks pause, busy, active unit, AP, starts the action camera, then `DefendAction.execute` consumes one AP and sets `UnitStats.is_defending = true`.
- Replay is recorded after mutation. Camera finishes afterward.
- `UnitStats.reset_turn` clears/updates turn state as part of the next phase setup.

**Finding**

Defend is obsolete as a current player/AI action but remains a replay compatibility branch. It should not shape the new production architecture. Either migrate it as a deliberately supported defensive action with real semantics or isolate it in a legacy replay importer and remove the runtime handler.

### Skip / Wait

**Initiators**

- Player: `ActionHUDController` calls `try_end_unit_turn` with a player-facing reason.
- AI: `_wait_for_next_turn` records its decision and calls the same gateway.
- Replay: `wait` dispatches to the same gateway.

**Flow**

- `try_end_unit_turn` checks pause, busy, active unit, and positive AP.
- It directly sets `current_ap = 0`, records `reason` and `spent_ap`, clears modes, prints a log, and returns.
- There is no `WaitAction`; the log label implies one, but authority lives directly in the controller.
- The AP signal schedules selection/phase consequences in `TurnManager`.

**Finding**

Skip/Wait is the simplest action and the clearest example of why action kind should be semantic while presentation labels may differ. It is an activation-ending action with no target and a cost of all remaining AP.

### RescueAction

**Initiators**

- AI explicitly calls `ObjectiveManager.try_rescue` when adjacent.
- Replay can dispatch an explicit recorded rescue.
- Movement can invoke `ObjectiveManager.complete_rescue` automatically from `_on_unit_moved`, without going through `try_rescue` or recording a nested rescue.
- No dedicated normal player button is present; player rescue is primarily proximity-driven by movement.

**Query and mutation**

- `ObjectiveManager.can_rescue` checks active rescue objective, valid actors, carrier state, pursuing faction, target mission ID/kind, and adjacency.
- `RescueAction.is_valid` delegates back to `can_rescue`.
- `complete_rescue` revalidates, unregisters the target's occupied cell, calls `rescuer.carry_unit`, and completes the rescue objective.
- There is no AP cost in the explicit rescue path.

**Replay and presentation**

- `try_rescue` may set `BattleController.is_action_in_progress`, starts the camera, executes the mutation, records names, waits, and clears the controller's busy flag.
- Pickup presentation occurs from `TacticalUnit.carry_unit` during authoritative mutation.
- Automatic movement rescue is intentionally folded into the move's resulting fingerprint. Replay contains logic to coalesce a record if gameplay signals already produced its expected state.

**Finding**

The architecture must decide whether rescue is an explicit action or a deterministic move consequence. Both may exist, but they need distinct semantics. A single state transition must not be recorded twice.

### ExtractAction

**Initiators**

- Player: unit world-bar action; debug mission controller; direct tests.
- AI: mission branches call `ObjectiveManager.try_extract`.
- Replay: extraction is dispatched before normal active-unit selection because zero-AP, non-active extraction is currently legal.

**Query and mutation**

- `can_extract` checks mission, roster membership, extraction objective/target, zone membership, movement state, and Survive completion. It does not require AP or active-unit status.
- `ExtractAction` delegates validation and execution back to `ObjectiveManager`.
- `complete_extraction` updates enemy escape or friendly/VIP counters and objectives, frees carried/VIP actors where applicable, asks `BattleController.extract_unit` to remove occupancy/turn-roster membership and queue-free the unit, then defers mission-outcome evaluation.

**Replay and presentation**

- Objective manager reaches into `BattleController` for the busy flag, camera, replay mode, and recording.
- Boarding presentation occurs before authoritative extraction; the unit may still fail validation after presentation if state changes.
- Replay stores actor name after success; extraction can destroy that actor immediately afterward.

**Finding**

Extraction is a tactical action with special activation policy, not an objective-manager UI routine. Its policy should be explicit in its handler (`requires_active_actor = false`, `ap_cost = 0`) and still use the shared submit path.

### Objective-related actions and consequences

Current objective-affecting operations fall into four categories:

1. **Explicit tactical actions:** rescue and extract.
2. **Action consequences:** move can complete Reach/rescue; attack/defeat can progress Eliminate or fail Protect/Rescue/Extract.
3. **Turn/time consequences:** `round_started` progresses Survive.
4. **Mission commands:** `end_mission_early` records `depart`, computes left-behind units, and ends the battle; `TurnManager.end_current_turn` advances phases and emits a separate replay record.

`ObjectiveManager` consumes battle/turn signals and may defer `_evaluate_outcome` to avoid mutating the battle inside another signal stack. This avoids some reentrancy problems but makes transaction boundaries implicit. The replay player's comments and fingerprint-coalescing branch explicitly acknowledge nested automatic actions.

## 2. Verified architectural weaknesses

### The real pipeline has several authorities

`BattleController` is the gateway for attack/move/wait/legacy defend. `ObjectiveManager` becomes a second gateway for rescue/extract/depart. `TurnManager` directly handles end-turn. Signal listeners create further consequences. A caller cannot submit a generic action and receive one authoritative result.

### Validation is split and repeated without a shared result

Gateway, rule helper, and action object each check different subsets. Revalidation is desirable, but duplicated Boolean checks lose rejection reasons and can disagree. `MoveAction` trusts a supplied path more than the controller does; `AttackAction` does not know range/LOS; objective actions delegate back to their manager.

### RNG is consumed before final action acceptance

`try_attack` draws from the combat RNG before `AttackAction.is_valid`. Current ordering usually succeeds, but a failure after the draw advances the deterministic stream without a committed action. `AttackAction` also contains a global-random fallback that bypasses the battle seed.

### Presentation begins before authoritative commit

Attack, move, defend, rescue, and extract can start action-camera or unit presentation before mutation succeeds. Extraction even plays boarding before `ExtractAction.execute`. Failure recovery is not expressed as part of the protocol.

### Lifecycle consequences are nested and timing-dependent

Damage emits defeat while the attack stack is active; movement emits mission consequences after visual motion; AP changes schedule selection; objective evaluation is deferred; extraction can free the actor before downstream work. These are valid gameplay consequences, but their order exists in signal timing rather than a transaction definition.

### Replay records are weakly typed and identify actors by node name

Dictionary `kind` and ad hoc fields have no schema version. `find_child(name)` assumes scene names are stable and unique. Hit roll and resolved damage are not recorded. Replay regenerates combat randomness and trusts fingerprints to detect divergence. The coalescing workaround skips a record when a nested consequence already produced its expected state.

### Completion means different things

`try_attack` returns after camera completion but not necessarily defeat-body cleanup. `try_move` returns after visual traversal. Wait returns immediately and lets AP signals advance later. Extraction includes boarding delay and actor removal. Callers only receive `bool`, so they cannot distinguish committed, presented, rejected, cancelled, or committed-with-presentation-failure.

### Busy and turn advancement are loosely coupled

Objective manager mutates another object's busy flag. `TurnManager` can react to AP during an action. Movement receives a special wait; attack does not. Direct `end_current_turn` calls are outside the action guard. This permits selection/phase changes to race with presentation and makes reentrant submission prevention incomplete.

### Small action classes do not own coherent responsibilities

They hold live nodes and mutate them directly, yet depend on controllers/managers for complete legality and presentation. `RescueAction` and `ExtractAction` are delegating wrappers. `UnitAction.is_valid/execute -> bool` cannot represent the target architecture.

## 3. Proposed target architecture

### System overview

```text
Player UI ─┐
AI ────────┼─> TacticalActionService.query(request draft)
Replay ────┘                  │
                              v
                     ActionHandler for kind
                    query / validate / resolve
                              │
                              v
                    TacticalActionService.submit
                    single-flight + revalidation
                              │
                       consume RNG here only
                              │
                              v
                    commit authoritative changes
                    objective events + lifecycle
                    increment state revision
                              │
                              v
                       ResolvedActionResult
                    ┌─────────┼──────────┐
                    v         v          v
                 Replay   Presentation   AI/debug
                 record   coordinator    observers
                              │
                              v
                      presentation completed
                              │
                              v
                       activation progression
```

### `TacticalActionService`

One battle-scoped Node owns the submission protocol. It does not own combat rules, pathfinding, objectives, cameras, or turn rosters; it coordinates them through explicit collaborators.

Responsibilities:

- register/locate handlers by action kind;
- expose query APIs to UI, AI, replay, and tests;
- assign a monotonic transaction ID;
- serialize submission with one private active transaction;
- validate against the current state revision;
- permit the handler to resolve deterministic randomness only after final validation;
- call one authoritative commit path;
- synchronously collect lifecycle/objective consequences into the same result;
- increment the battle action revision exactly once per committed transaction;
- emit `action_committed(result)` once;
- hand the result to presentation and expose separate committed/presented completion;
- release turn progression according to the action completion policy.

It should replace `BattleController.is_action_in_progress` as action authority. UI may still observe `is_busy`; objective code must not write it.

### Action handlers

Use small typed GDScript handlers, not XCOM-style template inheritance. A handler may be a `RefCounted` strategy registered in code. Editable future equipment can reference handler kinds and data resources without turning all current actions into resources.

Each handler owns the full rules for one semantic kind:

```gdscript
class_name TacticalActionHandler
extends RefCounted

func query(context: TacticalActionContext, draft: TacticalActionRequest) -> ActionQueryResult
func validate(context: TacticalActionContext, request: TacticalActionRequest) -> ActionValidationResult
func resolve(context: TacticalActionContext, request: TacticalActionRequest) -> ResolvedActionResult
func commit(context: TacticalActionContext, result: ResolvedActionResult) -> void
```

`query` and `validate` are read-only. `resolve` may consume only the battle-owned RNG exposed by a resolution context and produces a complete result without mutating live state. `commit` applies a result that has already been proven internally consistent; it is not allowed to fail halfway through. If a complex future action cannot guarantee this, it must stage and verify all mutations before commit.

Initial handlers:

- `AttackActionHandler`
- `MoveActionHandler`
- `WaitActionHandler`
- `RescueActionHandler`
- `ExtractActionHandler`
- `EndPhaseActionHandler` or a separate turn command if phase ending is not a unit action
- `DepartMissionActionHandler`

Legacy Defend should not receive a production handler unless its gameplay is retained deliberately.

### Battle-scoped context

`TacticalActionContext` supplies narrow authoritative dependencies:

```gdscript
class_name TacticalActionContext
extends RefCounted

var actor_registry: TacticalActorRegistry
var turn_manager: TurnManager
var grid_manager: GridManager
var pathfinder: Pathfinder
var objective_manager: ObjectiveManager
var combat_rng: RandomNumberGenerator
var state_revision: int
```

Handlers should receive this context rather than discovering nodes or holding long-lived live actor references. `CombatRules` remains reusable and stateless.

### Stable actor identity

Introduce a battle-scoped `TacticalActorId`, represented initially as a non-empty `StringName` value stored on every `TacticalUnit`. It must be unique within a battle and stable across replay reconstruction. Generated units should derive it deterministically from battle configuration, faction/role, and spawn ordinal; authored mission actors may retain authored IDs when unique.

A `TacticalActorRegistry` maps ID to the current live unit and rejects duplicates at battle setup. Requests and results store IDs, never NodePaths, instance IDs, or display names. `mission_id` remains a mission-role identity and must not be overloaded as the unique actor ID.

Prototype 1 recordings can be imported through a legacy name resolver if preserving them is useful; new records must use actor IDs.

### Requests

```gdscript
class_name TacticalActionRequest
extends RefCounted

var kind: StringName
var actor_id: StringName
var target_id: StringName
var destination: Vector3i
var expected_revision: int
var source: Source # PLAYER, AI, REPLAY, SYSTEM, DEBUG
var parameters: Dictionary # exceptional, validated data only
```

Requests describe intent, not outcomes. They contain no hit result, damage, path node objects, animation, camera, or mutable unit reference. A replay request may additionally carry expected resolved data for verification, but the normal submit path still validates it.

### Query and validation records

```gdscript
class_name ActionQueryResult
extends RefCounted

var kind: StringName
var actor_id: StringName
var state_revision: int
var availability: ActionValidationResult
var legal_target_ids: Array[StringName]
var legal_destinations: Array[Vector3i]
var previews: Dictionary
var ap_cost: ActionCost

class_name ActionValidationResult
extends RefCounted

var accepted: bool
var code: StringName
var message: String
var current_revision: int
```

Rejection codes are stable machine-facing values such as `actor_missing`, `wrong_activation`, `insufficient_ap`, `target_missing`, `target_not_hostile`, `out_of_range`, `blocked_los`, `destination_occupied`, `stale_revision`, and `action_busy`. UI chooses friendly text; AI/debug traces retain the code.

Query previews are deterministic calculations, never random samples. Attack preview returns chance, damage range, cover, obstruction, and predicted AP; it never predicts `did_hit`. Movement preview returns the authoritative candidate path/cost or enough information to request one, with a revision stamp.

### Costs and activation policy

Use a compact typed value, not subclasses initially:

```gdscript
class_name ActionCost
extends RefCounted

var ap: int = 0
var spend_all_remaining_ap := false
var ends_activation := false
var requires_active_actor := true
```

This expresses current exceptions explicitly:

- Attack/Move: one AP, normally do not force activation end.
- Wait: spend all remaining AP and end activation.
- Rescue: proposed zero AP pending design review.
- Extract: zero AP and currently does not require the active actor.
- End phase: no actor cost; changes phase only when permitted.

If future equipment adds charges/ammo, extend costs from concrete requirements rather than designing a universal currency framework now.

### Resolved results

```gdscript
class_name ResolvedActionResult
extends RefCounted

var schema_version: int
var transaction_id: int
var base_revision: int
var committed_revision: int
var request: TacticalActionRequest
var status: Status # RESOLVED, COMMITTED, PRESENTED, PRESENTATION_FAILED
var cost: ActionCost
var actor_before: Dictionary
var actor_after: Dictionary
var target_changes: Array[Dictionary]
var grid_changes: Array[Dictionary]
var objective_changes: Array[Dictionary]
var lifecycle_events: Array[DomainEvent]
var random_outcomes: Dictionary
var presentation: ActionPresentationPlan
```

The first implementation need not create a universal mutation language. `AttackResult`, `MoveResult`, and other typed detail objects may sit inside a shared envelope. The important rule is that replay, presentation, and diagnostics consume the committed result instead of rediscovering what happened from live nodes.

For Attack, the result should include hit chance, integer/normalized roll, hit/miss, damage, HP before/after, defeat, AP before/after, cover/LOS summary, and stable IDs. For Move, include origin, destination, authoritative path cells, AP delta, reservation/occupancy changes, traversal tags, and objective/lifecycle consequences.

### Domain events and objectives

During commit, handlers produce typed domain events such as:

- `UnitMoved`
- `UnitDamaged`
- `UnitDefeated`
- `UnitRescued`
- `UnitExtracted`
- `RoundStarted`
- `ActivationEnded`

`ObjectiveManager` consumes these synchronously through a method such as `apply_action_events(events, transaction)`, returns objective deltas and a possible battle-result request, and does not launch nested tactical actions. Signals remain useful as notifications after commit, but they no longer create authoritative consequences.

Automatic proximity rescue, if retained, becomes a `UnitRescued` consequence inside the Move transaction. It is not separately recorded as a second action. An explicit Rescue request produces the same event through its own transaction.

### Commit semantics

Commit is an ordered, non-awaiting section:

1. Verify service is not committing and request revision still matches.
2. Resolve stable IDs to live actors.
3. Run final validation.
4. Allocate transaction ID.
5. Resolve RNG and construct the complete result.
6. Apply AP/stat/grid/unit changes.
7. Derive and apply lifecycle and objective changes synchronously.
8. Apply roster/battle-result changes.
9. Increment `state_revision` once.
10. Finalize result and emit `action_committed`.
11. Only then begin presentation and post-commit notifications.

No `await` is allowed from step 1 through step 10. Godot does not provide transactional rollback for arbitrary Node mutation, so the architecture prevents partial failure by making all fallible checks occur before commit and keeping commit operations small and deterministic.

### Presentation

`TacticalActionPresenter` consumes an `ActionPresentationPlan` built from the resolved result. It owns camera, unit visual-adapter calls, feedback, pacing, and animation completion. It never changes AP, HP, occupancy, objectives, rosters, or battle result.

```gdscript
class_name ActionPresentationPlan
extends RefCounted

var kind: StringName
var actor_id: StringName
var focus_position: Vector3
var beats: Array[PresentationBeat]
var blocks_player_input := true
```

The first version may use a sequential beat list: camera start, movement/pose, shot, hit/miss, defeat, objective feedback, camera finish. Parallel groups should be added only when a real action needs them. Headless simulation uses a null presenter that completes immediately. Replay may choose full, accelerated, or suppressed presentation from the same result.

Presentation failure is logged and resynchronized from authoritative state; it does not roll back a committed action.

### Replay

New recordings use a versioned envelope:

```gdscript
{
    "schema_version": 2,
    "battle_configuration": {...},
    "actions": [
        {
            "transaction_id": 17,
            "base_revision": 16,
            "request": {...stable IDs...},
            "resolved": {...random outcomes and authoritative deltas...},
            "expected_state": "..."
        }
    ]
}
```

Replay submits the recorded request through the same service in verification mode. The handler recomputes legality and resolution with the seeded stream, then compares the produced result with recorded resolved fields before commit, or applies an explicitly approved authoritative-result mode for compatibility tests. Start with recomputation plus exact result/fingerprint comparison; it tests real rules rather than bypassing them.

Unsupported schema versions fail clearly. A one-time v1 importer may resolve names to actor IDs for important Prototype 1 fixtures; indefinite backward compatibility is not required. The current fingerprint remains as a strong post-commit assertion.

### UI and AI adapters

- **Player UI adapter:** builds request drafts, asks the service for queries/previews, renders legal targets/destinations/reasons, and submits confirmed requests. It owns modes and confirmation, not rules.
- **AI adapter:** asks for legal action/target/destination candidates, applies utility scoring and squad policy, then submits one request. It does not duplicate legality.
- **Replay adapter:** decodes schema, verifies revision and stable IDs, submits the request, and compares results/fingerprints.
- **Debug adapter:** may submit requests with source `DEBUG`, but bypasses must be explicit policy flags and recorded.

`BattleController` can remain temporarily as player-input adapter and composition point, then shrink or be replaced after migration. It should not remain the action authority.

## 4. Action lifecycle and ownership rules

### Lifecycle

| State | Meaning | Cancellation |
| --- | --- | --- |
| Draft | UI/AI is choosing kind/target/destination. | Free; no state/RNG changed. |
| Queried | A revision-stamped preview/candidate set exists. | Free; discard it. |
| Submitted | Service accepted the request for processing. | May cancel only before resolution begins. |
| Validating | Current state and revision are checked. | Cancellation returns `cancelled_before_commit`. |
| Resolving | RNG/outcome is being generated under the service lock. | No external cancellation; completes immediately without awaits. |
| Committing | Authoritative mutations and objective consequences are applied. | Never cancellable and never awaiting. |
| Committed | Result and new revision exist; replay can record. | Undo would require a new explicit action; no rollback through UI cancel. |
| Presenting | Camera/animation/UI consumes the result. | Presentation may be skipped/accelerated; authority remains committed. |
| Completed | Required presentation finished or was safely suppressed. | Terminal. |
| Rejected | Validation failed with a structured reason. | Terminal; no RNG/state change. |

### Ownership rules

- Action handlers own legality, costs, deterministic resolution, and typed result construction.
- The action service owns serialization, transaction/revision assignment, commit ordering, and lifecycle signals.
- State owners (`UnitStats`, `GridManager`, `TurnManager`, `ObjectiveManager`) apply only the changes relevant to them through explicit methods.
- Objective manager owns objective state and mission outcome rules, but not cameras, busy flags, replay recording, or tactical dispatch.
- Turn manager owns phases/active actors/rosters. It advances only from committed activation/phase results, never directly from AP-change presentation timing.
- Presenter owns all awaits and visual pacing.
- Recorder observes committed results; it does not infer a transaction from unrelated signals.
- UI and AI propose actions; neither commits state.

## 5. Safety mechanisms

### Double execution

A single battle-scoped service permits one active submit. Each accepted request receives one transaction ID, and `action_committed` is emitted once. Callers await/observe the same submission result rather than calling mutation helpers. Runtime storage of every historic idempotency key is unnecessary initially because requests are local and serialized; replay validates strictly increasing transaction IDs.

### Stale targets and occupancy

Every query includes `state_revision`; every request carries `expected_revision`. Submit rejects a mismatch, then re-resolves IDs and revalidates. A UI/AI adapter re-queries on `stale_revision`. Move resolution recomputes or verifies the path from current grid state; it never trusts a preview path blindly.

### Preview RNG

Query/preview APIs have no RNG dependency. Only `resolve` receives a restricted RNG interface after final validation. Remove global `randf()` fallbacks from action code.

### Presentation mutation

The presenter receives a resolved snapshot and actor IDs. Visual adapters may change transforms, animation state, visibility, camera, audio, and cosmetic nodes only. Authority tests continue to assert unchanged HP/AP/grid/objectives during isolated presentation calls.

### Replay divergence

Record schema version, stable IDs, base/committed revisions, transaction ID, random outcome, typed result, and post-state fingerprint. Replay compares at the earliest mismatch and reports field-level differences before the final fingerprint.

### Reentrant commits

Commit emits no public gameplay signals until its internal authoritative work and objective consumption finish. Post-commit observers cannot submit until the service exits the commit phase. If a future reaction requests another action, it enters a deliberate queue after the current transaction rather than recursing.

### Turn advancement

AP setters stop owning selection timing. Turn manager receives an `ActionCommitted`/`ActivationEnded` notification after authoritative resolution. Selection may advance immediately after commit or after blocking presentation according to one explicit pacing policy, but never before commit. Headless mode chooses immediate progression.

### Are revisions and transaction IDs justified?

Yes, in minimal form:

- One integer `state_revision` per battle prevents stale hover/AI/replay assumptions and increments once per committed action/turn command.
- One monotonic `transaction_id` provides log/replay/result identity.

No UUIDs, distributed idempotency service, snapshot history, or rollback log are justified. FuseFire is a local, single-threaded tactical simulation. The busy state plus monotonic IDs provides equivalent safety for its current environment.

## 6. Migration milestones

The roadmap proposes Attack first. The source supports that choice, but two small prerequisites should precede its full migration: stable actor IDs and the service/result skeleton. These are part of the Attack milestone, not separate feature projects.

### 01.2 — Contract skeleton and stable identities

**Goal:** establish types, registry, revision, service lifecycle, and a null/passthrough presenter without changing action behavior.

**Likely changes**

- Add `systems/actions/runtime/` with request, validation/query, cost, result, context, handler, service, and actor registry types.
- Add stable tactical ID to `TacticalUnit` and deterministic assignment/validation in `BattleLevel` spawning/setup.
- Bind the service in the battle composition root.
- Add schema/version constants without migrating recordings yet.

**Reuse:** current battle dependency injection, `CombatRules`, `GridManager`, `TurnManager`, deterministic configuration, fingerprints.

**Remove:** nothing yet; avoid premature cleanup.

**Temporary adapters:** `BattleController` continues current execution while service types are tested in isolation.

**Tests:** duplicate/missing actor IDs; deterministic generated IDs; request serialization; stale revision; single-flight/reentrant rejection; no RNG on query.

**Completion:** service can query/submit a test-only no-op transaction, increments revision once, and produces a typed result without touching gameplay.

### 01.3 — Attack vertical migration

**Goal:** migrate the complete Attack path and make it the reference implementation.

**Likely changes**

- Add `AttackActionHandler` and typed attack query/result details.
- Move all attack legality/cost/RNG/damage resolution out of `BattleController` and `AttackAction`.
- Add result-driven attack presenter using existing camera director and visual adapter.
- Make player, AI, and replay attack adapters use the service.
- Recorder writes versioned attack transactions.
- Objective/death consequences are synchronously collected into the attack result.

**Reuse:** `CombatRules.AttackEvaluation`, combat RNG stream, visual adapter, action camera, target scorer, state fingerprint.

**Remove after parity:** old `AttackAction`; `BattleController.try_attack` internals (method may remain briefly as adapter); `attack_resolved` if all consumers move to typed committed results; global-random fallback.

**Tests:** current combat/battle smoke; legal/illegal target reasons; no RNG on rejected/stale request; exact AP/hit/damage/death; presenter authority isolation; headless versus presented fingerprint; double submit/reentrancy; replay result and schema mismatch diagnostics; seed `23001`; AI same-seed decisions.

**Risk:** defeat currently triggers roster/objective changes through synchronous signals and delayed visual cleanup. Migration must separate authoritative defeat from body presentation without changing mission outcomes.

**Completion:** player, AI, replay, and headless simulation attack only through the service; one committed result contains all authoritative attack consequences; camera/animation can be skipped with identical state.

### 01.4 — Move migration

**Goal:** establish authoritative paths, destination reservations, visual motion, traversal tags, and move consequences.

**Likely changes**

- Add `MoveActionHandler` query/result and move presenter.
- Centralize reachable destination/path validation.
- Preserve immediate destination reservation at commit, but document it in the result.
- Move traversal-pose derivation behind presentation data and out of `BattleController`/legacy VRoid path.
- Convert Reach and automatic rescue consequences into typed events inside the move transaction.

**Reuse:** `Pathfinder`, `GridManager`, `MapData`, traversal links, current locomotion/IK, movement tests.

**Remove after parity:** old `MoveAction`; duplicated reachable/path checks; controller movement execution branch; movement-specific AP advancement workaround once turn progression consumes committed results.

**Tests:** occupied/stale destination; changed path between query and submit; corners/elevation/stairs/ladders/vaults; destination reservation while presenting; headless instant movement; reach/rescue consequence recorded once; cancellation allowed before but not after commit.

**Risk:** the live unit transform currently performs visual interpolation while also being the tactical actor. Presenter suppression must snap it to the committed destination, and interruptions must resynchronize safely.

**Completion:** one move result determines occupancy, AP, path, traversal presentation, and objective consequences; no nested replay coalescing is required.

### 01.5 — Wait/Skip and activation progression

**Goal:** migrate the simplest action and remove AP-signal ownership of action completion.

**Likely changes**

- Add `WaitActionHandler` with `spend_all_remaining_ap` and `ends_activation`.
- Route player Skip, AI Wait, and replay through it.
- Change `TurnManager` to advance from committed action/activation results rather than raw AP signals.
- Define whether player selection advances at commit or after blocking presentation consistently.

**Reuse:** turn rosters/phases, current player selection order, carrier priority.

**Remove after parity:** direct AP mutation in `try_end_unit_turn`; fake `WaitAction` logging; `_on_player_ap_changed` deferred action-completion logic if no longer needed.

**Tests:** skip with remaining AP; zero-AP rejection/idempotence; correct next player; last player to ally/enemy phase; AI wait/end; pause; no phase advancement before commit.

**Completion:** all unit activation endings are explicit committed results.

### 01.6 — Rescue and extraction migration

**Goal:** remove objective manager as a second action gateway.

**Likely changes**

- Add Rescue and Extract handlers with explicit costs/activation policies.
- Player/AI/UI/replay submit through the action service.
- Objective manager exposes pure queries and commit-time event application, not `try_*` orchestration.
- Decide explicit rescue versus automatic move consequence and encode both without duplicate records.
- Present pickup/boarding only after commit.

**Reuse:** mission definitions/states, `can_rescue`/`can_extract` rules, carry model, extraction reports, current animations/camera.

**Remove after parity:** `RescueAction` and `ExtractAction` delegating wrappers; `ObjectiveManager.try_rescue`/`try_extract`; objective manager access to controller busy/camera/replay; replay's special extract dispatch path.

**Tests:** adjacency/faction/mission actor rules; carrier state; zero-AP extraction; non-active extraction policy; enemy evacuation; actor removal; carried VIP; mission outcome; repeated extraction; rescue/refinery congestion; replay without coalescing.

**Risk:** extraction destroys actors and mutates rosters/objectives in one operation. Stable IDs and resolved snapshots must preserve replay/presentation data after nodes are freed.

**Completion:** objective manager cannot launch or present tactical actions; rescue/extract each commit once and remain reproducible after actor removal.

### 01.7 — Turn and mission commands

**Goal:** bring End Phase, Depart Mission, and round-driven objective changes under explicit command/result boundaries without pretending every command is a unit ability.

**Likely changes**

- Add battle-command request/result support in the same service or a sibling `TacticalCommandService` sharing revision/serialization.
- Migrate `end_current_turn` and `end_mission_early` callers.
- Produce typed `RoundStarted`/phase/battle-result events for objectives and replay.

**Reuse:** current `TurnManager` phase code and objective outcome rules.

**Remove after parity:** direct UI/AI/replay calls to phase mutation; separate `turn_ended` dictionary recording; direct departure replay record.

**Tests:** every phase transition, empty teams, extracted/defeated active actor, Survive progress, departure confirmation, left-behind report, pause, replay ordering.

**Completion:** every replay-relevant tactical state change has a revisioned transaction/command identity.

### 01.8 — Legacy Defend decision and compatibility cleanup

**Goal:** stop legacy support from defining the production API.

**Decision options**

1. Remove Defend runtime support and declare v1 recordings containing it unsupported or import it as Wait with an explicit compatibility rule.
2. Retain it only if Task 04/07 approves a meaningful defensive mechanic; then implement it through a real handler and status/result semantics.

**Tests:** explicit old-schema handling; no silent reinterpretation.

**Completion:** no unused `DefendAction` or unexplained branch remains.

### 01.9 — Controller and replay cleanup

**Goal:** delete obsolete structure after every action and command uses the new path.

**Likely changes**

- Reduce `BattleController` to battle composition/player interaction or split those concerns into input/query adapters.
- Remove old `try_*`, `record_replay_action`, Boolean-only action classes, duplicate legality, nested-record coalescing, node-name lookup, and writable cross-manager busy state.
- Update documentation and human-editing guides.

**Tests:** complete focused suite plus Prototype 1 milestone matrix, replay fixtures, dependency isolation, headless simulations, and MIRA authority/presentation tests.

**Completion:** only one authoritative submission path remains; repository search finds no obsolete gateways or v1 dictionary production.

## 7. Test and validation strategy

### Contract tests

- Query is read-only and RNG-free.
- Every rejection has a stable code and changes neither revision nor RNG stream.
- A successful commit increments revision once and emits one transaction.
- A stale revision fails before RNG.
- Reentrant submission during commit is rejected/queued deliberately.
- Presentation-disabled and presentation-enabled runs produce identical authoritative fingerprints.
- Presentation failure resynchronizes visuals and preserves committed state.

### Per-action parity

For each migrated action, run the current focused tests before and after migration. Compare:

- accepted/rejected actions;
- AP/HP/grid/objective/roster mutations;
- combat RNG outcomes;
- selected next actor and phase;
- replay result and final fingerprint;
- AI decision/action traces on fixed seeds.

When a behavior change is approved, record the intended delta and establish a new fixture rather than weakening the old assertion silently.

### Existing high-value fixtures

- `battle_smoke.gd`, `combat_cover_smoke.gd`, and cover/elevation tests for Attack.
- `battle_replay_smoke.gd` at seed `23001` for transaction/replay parity.
- `ai_match_determinism_smoke.gd` and `battle_dependency_isolation_test.gd` for determinism and ownership.
- traversal/vault/generated-building tests for Move.
- `core_objectives_smoke.gd`, `mission_actor_smoke.gd`, `enemy_evacuation_smoke.gd`, `departure_replay_smoke.gd`, and `rescue_battle_replay_smoke.gd` for objective actions.
- rescue refinery seed `733578405` for carrier/congestion and wait/progress behavior.
- `prototype_1_milestone.gd` for all seven mission families after each major migration group.
- `unit_visual_adapter_test.gd` and animation handoff tests for presentation authority.

### New diagnostics

- Human-readable transaction log: transaction ID, revision, source, action, actor/target, validation, RNG, mutations, objective consequences, presentation status.
- Field-level replay result comparison before fingerprint comparison.
- Debug overlay may show current revision and last committed transaction.
- Test-only presenter modes: normal, instant, fail-one-beat.

## 8. Expected obsolete code and cleanup opportunities

Expected removals after migration, subject to review:

- `UnitAction.is_valid/execute -> bool` base contract.
- `AttackAction`, `MoveAction`, `RescueAction`, and `ExtractAction` in their current live-node/mutating form.
- `DefendAction` unless a real defensive mechanic is approved.
- Direct `BattleController.try_*` authority; temporary adapters should be deleted after callers migrate.
- `BattleController.record_replay_action` and hand-built action dictionaries.
- `ObjectiveManager.try_rescue`, `try_extract`, camera/replay access, and writes to controller busy state.
- AP-signal-driven action completion and movement-specific deferred selection workaround.
- `BattleReplayPlayer` string-kind dispatch to several managers.
- `find_child(unit_name)` actor resolution.
- replay “already applied” coalescing for nested automatic consequences.
- combat action global `randf()` fallback.
- attack/move duplicate Boolean legality checks without structured results.
- traversal presentation dependency on the `vroid_proof` path.
- signals whose only purpose was to bridge authoritative consequences during an action; notification signals may remain after commit.

This cleanup should happen as each caller migrates, not in a speculative mass deletion at the beginning.

## 9. Open decisions requiring review

### Rescue semantics

Should entering adjacency automatically rescue, should Rescue be a zero-cost explicit action, or should both exist? Recommendation: use explicit Rescue for player readability unless movement auto-rescue is a deliberate design feature; if both remain, encode auto-rescue as a Move consequence and never a nested action.

### Extraction activation policy

Current extraction permits zero-AP and non-active units. Preserve this for parity during migration, but confirm whether future mouse-first play should require selecting the unit or spending an action.

### Turn progression versus presentation

Authority may advance immediately after commit, but input/camera pacing may wait for blocking presentation. Recommendation: commit first, keep the service busy for blocking presentation, then expose the next activation; headless mode completes instantly. This avoids background AI beginning while the previous action camera is still showing.

### Replay policy

Recommendation: new schema re-simulates requests using deterministic RNG and compares resolved results plus fingerprints. Store outcomes for diagnostics, not as the normal source of authority. Decide whether any v1 recordings deserve a name-to-ID importer.

### Stable ID format

Recommendation: deterministic battle-local `StringName`, validated unique at setup, with room for future persistent MIRA identity as a separate field. Do not use Node name, instance ID, or mission role ID as universal identity.

### Result model shape

Recommendation: shared result envelope plus typed per-action details, not a universal array of loosely typed mutations. Revisit a generic mutation model only after three migrated actions reveal genuine common structure.

### End phase as action or command

Recommendation: share the same serialization/revision/result protocol but model End Phase and Depart Mission as battle commands, because they do not have ordinary unit target/cost semantics.

### Defend compatibility

Recommendation: remove it from production architecture now and handle old recordings explicitly. Task 04/07 can introduce a new defensive action later if shields, crouch, suppression, or another concrete mechanic justifies it.

### Revision scope

Recommendation: increment one battle revision for every committed tactical action or battle command. Visual-only changes and AI queries do not increment it. Non-action debug mutations must either use a debug transaction or invalidate/increment revision explicitly.

## Approval boundary

## 10. Implementation record — Task 01 complete

The migration was implemented incrementally rather than reproducing every proposed class boundary. The resulting pipeline is:

> **Query → Validate → Resolve → Commit → Present**

`TacticalActionService` is the battle-scoped transaction coordinator. Stable `tactical_id` values are resolved through `TacticalActorRegistry`; typed requests carry expected revisions and source identities; typed results become schema-versioned replay records. Queries and rejected requests do not consume combat RNG or mutate tactical state. A successful commit increments one shared action revision before presentation, emits one committed result, and remains busy until presentation completes or is explicitly suppressed.

### Implemented actions

| Action | Authoritative rules and commit | Presentation | Replay result |
| --- | --- | --- | --- |
| Attack | Service validates activation and `CombatRules`, consumes seeded combat RNG only after final validation, then commits AP, damage, defeat, roster, and objective consequences synchronously. | `BattleController` consumes `AttackActionResult` for camera, attack, impact, defeat, and feedback. | Hit chance, roll, damage, AP/HP, defeat, objectives, and battle result. |
| Move | Service re-queries pathfinding and destination occupancy immediately before commit, then commits AP and destination reservation before traversal. | `BattleController` derives and plays the existing traversal path/pose segments. Suppressed presentation snaps to the committed destination. | Origin/destination, AP, objective changes, and carried actor resulting from Reach or automatic Rescue consequences. |
| Wait / Skip | Service validates the acting unit and commits remaining AP to zero. | A lightweight result presenter logs the reason; selection and phase progression remain in `TurnManager` behind the service busy barrier. | AP before/after and defending state. |
| Defend | Service retains the old one-AP defensive state transition solely for legacy replay compatibility. The obsolete `DefendAction` class was removed. | Existing short defensive camera presentation remains available to old recordings. | AP and defending state. |
| Rescue | Service validates revision and single-flight state, while `ObjectiveManager.can_rescue` remains the mission-domain rule. Commit removes target occupancy, attaches the carried actor, and completes the objective. | `BattleController` presents the result after commit. | Objective state and mission counters with stable actor/target IDs. |
| Extract | Service applies the explicit zero-AP, non-active-unit policy through `ObjectiveManager.can_extract`. Commit updates objectives/counters and removes occupancy/roster membership before boarding presentation. | Actor registry identity and the visual node survive until boarding finishes; final unregister/free is presentation cleanup. Suppression cleans up immediately. | Objective state, mission counters, and roster removal. |

The former `AttackAction`, `MoveAction`, `DefendAction`, `RescueAction`, and `ExtractAction` mutation wrappers were removed. Player, AI, replay, debug extraction, and headless callers now converge on the same submission paths. `ObjectiveManager.try_rescue` and `try_extract` remain thin public adapters because mission UI and AI already depend on that domain-facing API; they contain no action mutation or presentation logic.

### Authority boundaries

- `TacticalActionService` owns single-flight submission, stale-request rejection, deterministic resolution, transaction/revision identity, commit lifecycle, and committed/presented signals. It coordinates real action paths directly instead of introducing a speculative handler registry.
- `CombatRules`, pathfinding, and `GridManager` remain rule/space collaborators. The service does not duplicate their algorithms.
- `ObjectiveManager` owns mission legality, progress, counters, and outcome rules. Rescue and Extract are action transactions whose domain commit calls this owner.
- `BattleController` adapts input and owns cameras, animation, feedback, and final visual disposal. Presentation cannot decide whether a commit succeeds.
- `TurnManager` remains the authority for activation queues, phase transitions, round progression, and battle completion. Turn records are dedicated commands, not synthetic unit actions.
- `end_mission_early` remains a dedicated mission command. Turn and departure commands advance the shared revision so old previews become stale without forcing these operations into an unsuitable action abstraction.
- Automatic Reach and Rescue remain deterministic consequences of a committed Move. They are captured in the Move result and fingerprint, never recorded as duplicate nested actions.
- Round-based Survive progress and defeat-driven objective changes remain consequences of their authoritative turn/attack events. Debug objective mutation remains an explicit developer command outside normal gameplay.

### Deliberate differences from the proposal

The implementation did not create a generic `TacticalActionHandler` hierarchy. Attack, Move, simple activation actions, and mission interactions have materially different collaborators and activation policies; typed service entry points and injected mission callbacks provide clearer ownership with less indirection at the current scale. A handler registry can be reconsidered when weapon/equipment abilities produce enough concrete action kinds to justify it.

Cancellation remains pre-commit only. Accepted Prototype 1 actions are short, deterministic transactions whose authoritative mutation completes synchronously. Camera or animation completion may be awaited, but it cannot roll back or alter the result.

### Validation added during migration

`tactical_action_service_test.gd` covers stable IDs, read-only/RNG-safe queries, stale and duplicate rejection, one-time commit/revision behavior, deterministic attack reconstruction, normal versus suppressed presentation, movement occupancy and AP, and Wait lifecycle behavior. Existing battle, objective, AI, traversal, camera, dependency, and replay suites verify the integrated paths. The final release validation matrix remains the release gate rather than a substitute for these focused contract tests.

### Remaining concerns

- Movement pose data is still derived from `art/characters/vroid_proof/runtime/tactical_pose_context.gd`; moving this neutral traversal contract is character-pipeline work rather than action authority work.
- Defend is intentionally a compatibility behavior, not an approved current mechanic. Replay schema migration policy should decide when old Defend support can be removed.
- Action result classes share small serialization patterns. Their explicit forms are currently easier to inspect than a generic envelope; consolidate only if future ability work demonstrates repeated maintenance cost.
- `TacticalActionService` currently contains the four proven orchestration paths. New abilities should first test whether a small handler abstraction reduces real duplication before adding a general framework.
