# Tactical Abilities and Reactions Plan

**Milestone:** Prototype 1.5 Task 01.11, Phase A

**Baseline:** `p2-foundation` at `b3e2e8f` (`clear the turn lane`)

**Status:** Phase A approved; Task 01.11.0 archetype laboratory implemented as the prerequisite slice

## 1. Current baseline

FuseFire has one authoritative **Query → Validate → Resolve → Commit → Present** pipeline. `TacticalActionService` owns revision/request checks, deterministic combat RNG, AP and action-state commitment, transaction IDs, typed results, replay records, and the busy barrier. `BattleController` supplies readable player/AI adapters and domain callbacks. `TacticalActionPresenter` consumes committed results. `TurnManager` and `ObjectiveManager` retain turn and mission authority. Player, AI, replay, and headless callers share the service.

Reusable foundations are stable actor IDs and registry, typed contracts, final pre-commit validation, synchronous guarded commit, result-driven presentation, schema-3 replay plus explicit schema-2 compatibility, fingerprints, and shared attack/move queries. End Turn already respects the action barrier.

Verified gaps:

- `UnitStats` has HP, AP, speed, and `is_defending`; it has no SP/ammo, explicit temporary-state lifetime, directional defense, or reaction reservation.
- `TacticalUnit` has one prototype attack profile and no weapon/inventory model.
- `CombatRules.evaluate_attack()` has no explicit modifier context.
- fingerprints omit proposed resources and tactical states.
- Move commits final occupancy before presentation; there is no authoritative checkpoint where a reaction can shorten its path.
- current action payloads use schema 2 and fixed result shapes.

`PROTOTYPE_1_CURRENT_STATE.md` and `docs/architecture.md` confirm the old SP/resupply experiment was removed. Management has now approved **Supply Points (SP)** as the new tactical resource, with initial capacity 4. Its gameplay begins in 01.11.1.

## 2. XCOM 2 SDK findings

Inspected root: `C:/Program Files (x86)/Steam/steamapps/common/XCOM 2 War of the Chosen SDK/Development/SrcOrig/XComGame/Classes`. These are local references; no proprietary source or assets enter FuseFire.

| Area | Exact source and symbol | Verified behavior | FuseFire decision |
| --- | --- | --- | --- |
| Ability composition | `X2AbilityTemplate.uc`; `X2Ability_DefaultAbilitySet.uc` | Templates compose costs, conditions, targeting, effects, triggers, state construction, and visualization. | **Adapt the separation; reject the hierarchy.** Keep explicit typed query/submit methods. |
| AP cost | `X2AbilityCost_ActionPoints.uc`: `CanAfford`, `GetPointCost`, `ApplyCost`, `ConsumeAllPoints` | Availability and payment are separate; costs may be fixed or consume all. | Extend `ActionCost` only for demonstrated needs and apply once at commit. |
| Ammo cost | `X2AbilityCost_Ammo.uc`: `CalcAmmoCost`, `CanAfford`, `ApplyCost` | Checks and commits source-weapon ammo use. | Use a unit-level prototype resource until weapons exist. |
| Reload | `X2Ability_DefaultAbilitySet.uc`: `AddReloadAbility`, `ReloadAbility_BuildGameState`, `ReloadAbility_BuildVisualization`, `Reload_OverrideAbilityAvailability` | One-AP self action; requires reloadable weapon state; fills the clip in committed state before visualization. | Adopt query/commit/present separation; omit upgrades/free reloads. |
| Overwatch registration | `X2Ability_DefaultAbilitySet.uc`: `AddOverwatchAbility`; `X2Effect_ReserveOverwatchPoints.uc`: `GetReserveType`, `GetNumPoints` | Validates ammo, converts ordinary AP to a typed reserve used by the shot. | Store one explicit armed-reaction state; do not reproduce named AP pools. |
| Reaction shot | `X2Ability_DefaultAbilitySet.uc`: `AddOverwatchShotAbility`, `PistolOverwatchShotHelper`; `XComGameState_Ability.uc`: `TypicalOverwatchListener`; `Helpers.uc`: `GetOverwatchersFromList` | `ObjectMoved` triggers a reaction ability that consumes reserve and ammo and participates in interruption history. | Resolve reactions at authoritative path checkpoints in stable order; no general event bus. |
| Move interruption | `X2Ability_DefaultAbilitySet.uc`: `MoveAbility_BuildGameState`, `MoveAbility_BuildInterruptGameState`; `XComGameStateContext_Ability.uc` interruption state | Explicit state frames and interruption status separate movement truth from animation. | Pre-resolve path/reactions into one Move result; do not copy XCOM object history. |
| Hunker Down | `X2Ability_DefaultAbilitySet.uc`: `AddHunkerDownAbility`; `HUNKERDOWN_DEFENSE`, `HUNKERDOWN_DODGE` config | Applies duration-bound defense/dodge effects and separate visualization. | Replace current production boolean semantics with an explicit stance/lifetime; isolate schema-2 Defend. |
| Effect lifetime | `X2Effect_Persistent.uc`: `BuildPersistentEffect`, `FullTurnComplete`, `OnEffectTicked`, `GetStartingNumTurns`, modifier hooks | Effects own durations, ticking/removal, and combat modifier hooks. | Use concrete typed tactical state for 01.11; defer a general conditions system to 01.12. |
| Shield | `X2Ability_AdventShieldbearer.uc`: `CreateEnergyShieldAbility`; `X2Effect_EnergyShield.uc` | Energy Shield is radial temporary HP with charges/cooldown/duration. It is not directional handheld cover. | Borrow data-driven state only. FuseFire's facing shield is original. |
| Interaction | `X2Ability_DefaultAbilitySet.uc`: `AddInteractAbility`, `InteractAbility_BuildGameState`, `InteractAbility_BuildVisualization`; `X2Condition_Interactive.uc`; `XComGameState_InteractiveObject.uc`: `Interacted` | Conditions discover targets; authoritative object state changes before visualization. | Add one small target contract and terminal example. |
| AI | `XGAIBehavior.uc`: ability option evaluation, `BT_GetOverwatcherCount`, `BT_SetOverwatcherStack`; `X2AIBTDefaultActions.uc`: `SetOverwatcherStack`, `SetNextOverwatcher`; `X2AIBTDefaultConditions.uc` | AI consumes availability/preview facts and applies policy; it estimates reaction threats. | Existing FuseFire AI consumes shared queries and focused scorers; no behavior-tree migration. |

No standard XCOM action matching the proposed spend-AP-for-next-shot Aim was verified. XCOM has aim stats and modifiers, but the Aim contract below is FuseFire-specific.

## 3. Proposed gameplay contracts

The gameplay/testing values in this section are approved initial values, not permanent balance commitments. They remain unimplemented during 01.11.0.

### Reload

Add Inspector-authored `max_supply_points` and runtime `current_supply_points` to `UnitStats`, default capacity 4. Normal Attack consumes 1 SP. Reload costs 1 AP and fills to maximum. Reload while partly depleted is supported; choosing an amount is not. Full resource rejects with `resource_full`; insufficient AP rejects normally.

SP means **Supply Points**: a broader tactical supply resource currently consumed by the single prototype attack profile. No weapon object is added. Typed Reload query/result records AP and SP before/after. Attack query/result gains SP cost and before/after. Fingerprints include both values. AI scores need versus exposure and available targets while legality stays authoritative.

### Aim

**Implemented in 01.11.2.** Each unit owns a compact `TacticalState` node. Aim costs 1 AP, grants +15 percentage points to the next eligible normal Attack, does not stack, and expires at the start of the actor's next activation if unused.

A rejected Attack does not consume Aim. Any committed normal Attack consumes it, hit or miss. Move, Reload, defense, Shield Stance, Overwatch, Wait, Rescue, or Extract cancels it. Defeat/removal clears it. Aim is actor-bound, not target-bound. Results record applied/cancelled state.

`CombatRules.evaluate_attack()` receives the explicit accuracy bonus assembled by the action service. Attack queries expose base chance, Aim bonus, and final chance. This remains readable and prepares for named shield/condition inputs without introducing a generic modifier framework.

FuseFire maps an activation to the first time a unit becomes active in a `(round, faction phase)` pair. Re-selecting a player in the same phase does not begin another activation. `TurnManager` calls `TacticalState.begin_activation()` before emitting `active_unit_changed`, so expiry occurs before UI or AI queries. Defeat and roster removal clear Aim explicitly.

New recordings opt into Aim through `BattleConfiguration.aim_enabled`, include Aim in unit fingerprints, record Aim payload schema 4, and use Attack payload schema 4. Recordings without the flag retain their old accuracy, payload comparison, and fingerprint layout. The replay envelope remains schema 3 and pre-SP compatibility remains unchanged.

### Ordinary defensive stance

Freeze schema-2 `defend` semantics at the compatibility boundary. Author current gameplay as `defensive_stance` while the UI may say **Defend**. Proposed cost is 1 AP; incoming damage is reduced 50%, matching Prototype 1; no extra cover bonus; expiry is next activation start; no stacking. Any other committed action cancels it.

Damage modification moves from an ambiguous boolean inside `take_damage()` to an explicit combat-resolution path. AI consumes expected prevented damage/exposure. Old recordings do not acquire new semantics.

### Shield capability and stance

Add a concrete `ShieldCapability` Godot `Resource`, Inspector-referenced by a unit. Fields: stance AP cost, protected arc degrees, damage multiplier, accuracy penalty against the unit, and whether attacks are allowed. Missing Resource means no shield; runtime stance state is never stored in the shared Resource.

Proposed defaults: 1 AP, 120° front arc, 0.35 incoming damage multiplier, -20 attacker accuracy in the arc, attacks prohibited, expiry at next activation start. Move, Aim, Overwatch, ordinary defense, Rescue, Extract, and Wait cancel it; Reload while shielding is proposed illegal. The request/result stores normalized facing.

`CombatRules.is_within_protected_arc()` compares the attacker-to-target grid vector with committed facing. Outside the arc is flanking/unprotected. Cover applies independently; named accuracy modifiers are additive and damage reduction follows a hit. HUD uses the shared query to draw coverage; AI uses the same arc query. Ally protection, formations, durability, classes, and equipment customization are deferred.

### Object interaction

Add a narrow concrete-node contract:

- stable `interaction_id`;
- `get_interactions(actor) -> Array[InteractionOption]`;
- `validate_interaction(option_id, actor, grid) -> ActionValidationResult`;
- `commit_interaction(option_id, actor) -> Dictionary` with authoritative before/after facts;
- a presentation cue ID in the committed result.

`InteractionOption` contains stable option ID, label, AP cost, range rule, and optional objective tag. A separate small registry maps stable interaction IDs to nodes. `TacticalActionService` owns revision/AP/transaction/busy behavior and calls the target once during commit.

First example: a mission terminal with `inactive → activated`, one-grid-step adjacency, 1 AP, idempotent rejection after activation, an ObjectiveManager event during commit, and a simple presenter cue. A door would also require path-graph mutation, so it is not the first proof.

### AI integration

Each action exposes a typed read-only query. Existing `AIController` gathers legal options and focused scorers compare tactical value: Reload need/exposure; Aim expected-damage gain; defense expected prevention; shield threats inside a proposed arc; Overwatch likely hostile path checkpoints and ally duplication; interaction mission priority/distance. Stable IDs, grid cells, and option IDs break ties before existing difficulty randomness. AI preference differs from UI presentation; tactical facts do not.

## 4. Overwatch transaction and interruption design

| Model | Benefit | Problem | Decision |
| --- | --- | --- | --- |
| Nested events in parent Move | Atomic command/revision; deterministic RNG; final occupancy follows full resolution | Richer Move result | **Use for 01.11** |
| Separate linked transactions | Individual action records | Exposes partially committed Move/reservation and complicates replay/rollback | Reject initially |
| Animation callback | Easy timing | Makes presentation authoritative and breaks headless/replay | Reject |

Registration consumes all remaining AP (minimum 1) and requires at least 1 SP. It does not spend SP; the first eligible reaction consumes both armed state and 1 SP. A voluntary committed action, Wait/next activation, defeat, or extraction clears it.

Before Move commits occupancy, resolve the validated path cell by cell:

1. Evaluate the mover at the next checkpoint in a read-only movement-resolution context.
2. Collect hostile, alive, armed reactors with legal range/trajectory.
3. Sort by faction phase order, then tactical actor ID.
4. For each still eligible reactor, draw from service RNG, consume Overwatch/resource, and append a typed `ReactionEvent` with IDs, trigger cell, chance, roll, damage, resources, and defeat.
5. Stop when the mover is defeated/disabled/removed; otherwise continue.

The parent result stores requested/resolved paths, final cell, interruption reason, AP before/after, ordered events, objective consequences, and final state. Move AP is paid once even if interrupted. Occupancy changes once from origin to the last resolved survivable cell. Reach/Rescue consequences inspect only that final cell.

Presentation animates to each trigger checkpoint, shows the already committed shot/outcome, then continues only when the result says so. Suppression/interruption snaps visuals to final authority and releases one parent barrier. No reaction callback submits Attack or advances turns.

The parent Move remains one replay record, transaction, and revision. Replay resolves and compares nested events field by field. Use normal combat legality at each checkpoint with a proposed -15 reaction modifier; cover/elevation/obstruction are calculated from that checkpoint. Multiple reactors fire in stable order until the mover falls or the list ends.

## 5. Temporary-state lifetime model

Task 01.11 needs concrete lifetime state, not 01.12's general conditions system. `TacticalUnitState` holds typed Aim, defense, shield, and Overwatch records plus activation serial/round-phase provenance.

- action commit applies/cancels state according to the matrix;
- activation start invokes one plainly named authoritative expiry method;
- turn records include resulting expirations rather than inventing synthetic unit actions;
- defeat/extraction clears state as a parent consequence;
- presentation only observes state.

Use activation serials, never frame time/timers. Fingerprints include active states and facing. Runtime state is distinct from immutable Inspector-authored capability data.

## 6. Interaction matrix

| Combination | Proposed rule |
| --- | --- |
| Aim + Attack | Aim applies and is consumed on any committed normal Attack, hit or miss. |
| Aim + Move/Reload/stance | The committed other action cancels Aim. |
| Overwatch + Move | Enemy checkpoint entry may add nested reaction events before Move commit. |
| Overwatch + multiple shooters | Stable phase/actor-ID order; stop after mover defeat/removal. |
| Overwatch + defeat | Defeated reactor cannot fire; defeated mover stops and triggers no destination objective. |
| Overwatch + extraction | Explicit Extract does not trigger; movement into an extraction zone can trigger first. |
| Overwatch + cover/elevation | Shared attack rules evaluate the trigger cell. |
| Defensive stance + direction | Ordinary stance is omnidirectional damage reduction. |
| Shield + flanking | Outside the committed arc is unprotected. |
| Shield + cover | Named accuracy modifiers combine; shield damage reduction applies after hit. |
| Reload + exhaustion | Attack rejects at zero resource; legal Reload restores capacity. |
| Interaction + mission completion | ObjectiveManager applies consequences once inside interaction commit. |
| Ability + End Turn | Service barrier blocks End Turn through presentation. |
| Ability + pause | Pause affects presentation; committed state and eventual barrier release remain valid. |
| Ability + replay | Same authority path; typed result/fingerprint comparison; no cosmetic state. |
| Aim + Overwatch | Registration cancels Aim; Aim never buffs reaction fire in 01.11. |
| Defend + Shield | Mutually exclusive; shieldless units retain ordinary defense. |
| Shield + Attack/Reload | Attack prohibited; Reload proposed illegal until stance ends/cancels. |
| Interaction + Overwatch | Acting cancels own Overwatch; interaction itself does not provoke it. |

## 7. Risk register and tests

| Risk | Constraint and targeted test |
| --- | --- |
| Move commits too early | Pre-resolve reactions; test mid-path defeat gives one occupancy mutation, final checkpoint, one revision. |
| Duplicate AP/resource cost | Record before/after; test accepted/rejected/stale/reentrant Reload and Overwatch. |
| Query RNG mutation | Repeated queries preserve RNG/revision. |
| Reactor instability | Reverse registration order and require identical event order/fingerprint. |
| Duplicate replay records | One Move record with N nested events. |
| Presentation authority | Normal/suppressed/headless reaction movement must match. |
| Premature turn progress | End Turn/UI/AI attempts during reaction presentation remain blocked. |
| Stale state on removal | Defeat/extraction fingerprints contain no armed stance/reaction. |
| Ambiguous expiry | Test consecutive turns, Wait, round rollover, and replay. |
| Direction errors | Front/edge/back, diagonal, elevation projection, and same-cell cases. |
| Old replay breakage | Run schema-2 Defend and schema-3 current fixtures. |
| Interaction double commit | Duplicate/stale terminal requests and mission-completion event exactly once. |
| Shared Resource mutation | Two units sharing capability Resource have independent runtime state. |
| AI bypass | Player and AI query results agree for every mechanic. |

## 8. Implementation slices

### 0. Tactical archetype laboratory and Match Setup roster editor

Implemented as the prerequisite authoring slice. `TacticalArchetype` Resources define stable IDs, descriptions, baseline stat overrides, and the currently demonstrated shield capability declaration. The existing Forces tab edits independent Player, Enemy, and AI Ally slots. `BattleConfiguration` and replay data carry per-slot IDs; spawning applies each preset before the unit enters the scene tree. Generic preserves count-only setups, and mission actors remain outside the roster.

### 1. Shot resource and Reload

**Implemented in 01.11.1.** `UnitStats` owns independent runtime Supply Points initialized from the archetype's Inspector-authored `max_supply_points`. Attack consumes one SP at commit, and typed Reload query/result contracts restore the reserve for one AP without consuming RNG. The existing HUD, presenter, AI loop, fingerprints, and replay player all consume the same authoritative facts. Full/empty/AP/stale/reentrant/presentation/replay cases have focused coverage. Weapons, inventory, upgrades, supply transfer, and selectable reload amounts remain excluded.

Historical recordings without an explicit `supply_points_enabled` configuration flag retain pre-SP semantics: their payload-v2 Attacks consume no SP and their fingerprints use the pre-SP unit layout. New recordings opt into SP explicitly, use Attack/Reload payload schema 3, and compare SP fields normally. The replay envelope remains schema 3.

### 2. Aim and explicit tactical state

**Implemented in 01.11.2.** `TacticalState`, typed Aim query/result contracts, the action HUD, presenter, replay path, fingerprinting, and a conservative AI Aim-then-Attack policy use the existing authoritative pipeline. Accepted Attack consumes Aim; accepted Move, Reload, Wait/Defend, Rescue, and Extract cancel it. Rejected actions preserve it. Focused coverage verifies cost, RNG independence, accuracy, cancellation, activation expiry, defeat, HUD, AI, and compatibility. Generic effects, target lock, stacking, defense, shield, and reactions remain excluded.

### 3. Current defensive stance

Add `defensive_stance`, isolate schema-2 Defend, and make damage modification explicit. Test old replay compatibility, lifetime, fingerprint, shared query, and AI use. Exclude shield and generalized conditions.

### 4. Shield capability and stance

Add `ShieldCapability`, facing contracts, arc math, HUD coverage, presentation, and AI facing score. Test shieldless defense, arc edges, cover composition, replay, and shared queries. Exclude ally cover, durability, classes, and equipment framework.

### 5. Overwatch simulation and reactions

Add registration, pre-commit checkpoint resolver, nested events, movement presentation sequencing, and AI threat facts. Test deterministic multi-reactor order, final occupancy, objective timing, one record/revision, barriers, and all presentation modes. Exclude suppression, Kill Zone, return fire, and generic reactions.

### 6. Mission terminal interaction

Add the minimal option/target contract, stable registry, terminal example, service transaction, objective hook, presentation, and AI mission score. Test discovery, adjacency, AP, idempotency, missing targets, mission completion, and replay. Exclude doors and hacking minigames.

### 7. Cross-mechanic AI and integration

Compare typed legal options in existing AI flow with stable tie-breaking and focused policy weights. Construct cases where AI rationally chooses every new action. Run full regressions without changing unrelated AI architecture.

This order deliberately establishes resources, lifetime state, and modifier contracts before Overwatch. Interaction follows the high-risk movement work to keep slices focused.

## 9. Human-editability map

| Intent | Intended owner |
| --- | --- |
| Tune capacity/Aim/defense/shield | Inspector fields on `UnitStats` or `ShieldCapability.tres` |
| Change legality/cost/transition | named query/submit method in `TacticalActionService` |
| Change attack math/modifiers | `systems/combat_rules.gd` |
| Change Aim state lifetime | `units/components/tactical_state.gd` and `TurnManager._set_active_unit()` |
| Change reaction order/checkpoints | one focused movement-reaction resolver |
| Change camera/animation/feedback | action-specific presenter and visual-adapter methods |
| Change AI preference | focused scorer consuming query results |
| Change terminal behavior | terminal script implementing the small interaction contract |
| Diagnose replay | typed serializer plus existing replay diagnostics |

Do not create ability registries, factories, generic effect stacks, event buses, or equipment hierarchies. If the service becomes hard to navigate, extract cohesive action-specific rule helpers while its public query/submit map stays explicit.

## 10. Explicit deferrals

- ally shield protection, formations, durability, classes, equipment customization;
- general conditions/hazards/EMP/hacking consequences (01.12);
- base/effective/current AP and tempo modifiers (01.13);
- path-mutating doors, hacking minigame, inventories, weapon swaps, reload upgrades;
- suppression, Kill Zone, return fire, reaction chains, rollback/rewind;
- universal ability templates, ECS, event bus, generic effect framework, networking.

### Movement-planning debt exposed during 01.11.2

AI hypothetical continuation paths currently evaluate the real occupancy map, so
an actor's present tile can obstruct a route calculated from a proposed future
tile in a one-cell passage. Maximum-urgency movement has a deterministic fallback
that scores an already-legal first step by geometric progress; permanent fixtures
cover extraction seed `25005` and refinery elimination seed `25100`. Before or
during Overwatch integration, evaluate a focused Pathfinder API that can ignore
the planning actor's origin without mutating authoritative occupancy. Reaction
checkpoints and committed movement must continue to use real authoritative state.

## 11. Definition of Done

01.11 is done only after the prerequisite laboratory and all seven gameplay slices leave a working project; every mechanic has shared read-only queries and one authoritative commit; Move reactions resolve deterministically before presentation; resources/state are fingerprinted and replayed; schema-2 Defend stays explicit; normal/suppressed/headless results match; AI uses every mechanic without competing legality; MIRA presentation consumes committed results; Inspector tuning and docs are current; focused and full regressions pass without hidden warnings. The comprehensive Goal 01 audit after 01.13 remains separate.

## 12. Approved initial decisions

- SP means **Supply Points**; initial capacity is 4.
- Reload costs 1 AP and refills to capacity.
- Aim costs 1 AP and adds 15 percentage points.
- Ordinary defense costs 1 AP and reduces incoming damage by 50%.
- Shield Stance costs 1 AP, protects a 120° frontal arc, applies 0.35 incoming damage and -20 percentage points to incoming accuracy.
- Overwatch consumes all remaining AP when registered, applies -15 reaction accuracy, and consumes 1 SP only when firing.
- Interrupted Move retains its normal 1 AP cost.
- Reactions order by faction phase, then tactical actor ID.
- The mission terminal is the first interaction example.
- Replay uses the smallest compatible version change justified by Slice 1 fixtures.

Exact cancellation details not enumerated above remain governed by the contracts in this plan and should be verified by their implementation fixtures.
