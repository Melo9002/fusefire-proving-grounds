# FuseFire Prototype 1.5 — XCOM 2 AI Architecture Research

**Research date:** 2026-10-08  
**FuseFire baseline:** `p2-foundation` at `53e429f017740e0f959bf5afd78ae93f5172553b`  
**Scope:** read-only comparison. No FuseFire gameplay code or XCOM asset was modified.

## Executive finding

XCOM 2 does not choose between behavior trees and utility scoring. It layers them.

The configured behavior tree determines which policy branch to try and in what priority order. Leaf actions then ask the tactical rules engine for legal abilities and targets, iterate candidates, accumulate target scores, filter and weight movement tiles, and finally submit one selected ability through the same authoritative ability system used by the rest of the game. Separate state objects preserve alert knowledge, group membership, jobs, priority targets, and turn-wide coordination.

FuseFire already has the most valuable lower layer: authoritative shared actions, deterministic candidate scoring, objective intent, squad reservations, and decision traces. Its main gap is not the absence of a behavior-tree runtime. It is that priority policy, candidate generation, scoring, coordination, and execution remain interleaved inside `AIController`. XCOM demonstrates useful boundaries and authoring concepts, but copying its full tree framework would add substantial complexity before FuseFire has enough unit abilities or doctrines to justify it.

## Installed evidence and limits

The investigation used both installed SDKs:

- War of the Chosen SDK: `C:\Program Files (x86)\Steam\steamapps\common\XCOM 2 War of the Chosen SDK`
- Base-game SDK: `C:\Program Files (x86)\Steam\steamapps\common\XCOM 2 SDK`

War of the Chosen is the primary reference because it contains the later tactical implementation and additions such as The Lost and Chosen behaviors. The base SDK was checked to confirm that the central `XGAI*`, `X2AIBT*`, AI job, configuration, and rules-engine architecture predates those additions.

The SDK contains original UnrealScript under `Development\SrcOrig`, including roughly 2,475 WotC `XComGame` classes, plus `XComGame\Config\DefaultAI.ini` and `DefaultAIJobs.ini`. This is strong source evidence for the script layer and configuration.

Some important methods are declared `native`, including behavior-tree construction and node creation in `X2AIBTBehaviorTree`, parts of path/candidate evaluation in `XGAIBehavior`, and portions of job initialization. Their signatures and callers are visible, but their C++ bodies are not present in the SDK. Findings that depend on those bodies are marked as inference.

## 1. Behavior-tree definitions, selectors, conditions, and priorities

### Verified SDK behavior

The tree manager is `Development\SrcOrig\XComGame\Classes\X2AIBTBehaviorTree.uc`:

- line 5 declares the configured `array<BehaviorTreeNode> Behaviors`;
- lines 96–117 expose native lookup, generation, node construction, score-node construction, type overrides, and validation;
- `QueueBehaviorTreeRun` at line 385 records the unit, root name, run count, history barrier, scamper flags, and whether an effect initiated the run;
- `TryStartBehaviorTreeRun` around line 318 waits for the manager and unit to be ready, initializes the unit behavior, applies scamper context, and calls `XGAIBehavior.StartRunBehaviorTree`;
- `BeginBehaviorTree` and `EndBehaviorTree` serialize active runs.

Node semantics are split across:

- `X2AIBTBehavior.uc` — shared node state, parent/child relationships, status, initialization, reset, and traversal data;
- `X2AIBTComposite.uc` — composite base;
- `X2AIBTSelector.uc` — succeeds on the first child that succeeds and preserves a running child;
- `X2AIBTSequence.uc` — runs children in order and fails when a required child fails;
- `X2AIBTDecorator.uc` — inverter, successor, repeat, random filter, and related decorators;
- `X2AIBTDefaultConditions.uc` — rule and state queries;
- `X2AIBTDefaultActions.uc` — target-stack, destination, blackboard, job, and ability-selection actions.

The authored tree is primarily configuration in `XComGame\Config\DefaultAI.ini`, section `[XComGame.X2AIBTBehaviorTree]` starting near line 264. `BehaviorName`, `NodeType`, ordered `Child[]`, `Param[]`, and character-qualified names build the graph. The generic root at line 519 is:

`TryNonAggressiveBehavior -> TryMindControlledRoot -> ::CharacterRoot -> SkipMove`

That ordering is policy. A selector tries each branch until one works. `::CharacterRoot` is resolved for the current character group; for example WotC defines `TheLost::CharacterRoot`, `ChosenAssassin::CharacterRoot`, and `ChosenWarlock::CharacterRoot`. Character templates provide the default behavior-tree root through `strBehaviorTree`; `XGAIBehavior.GetBehaviorTreeRoot` around line 7317 reads it.

The tree is asynchronous. `XGAIBehavior.StartRunBehaviorTree` at line 2524 refreshes caches, initializes variables, and schedules `StepProcessBehaviorTree`. That function at line 2697 repeatedly processes the tree. A selected ability is deliberately returned as `BTS_RUNNING` for one tick by `X2AIBTDefaultActions.SelectAbility` at line 713, then recorded as `m_strBTAbilitySelection`. A successful tree calls `BTExecuteAbility`; failure can skip the turn; `BTS_RUNNING` schedules another short timer tick.

The configuration includes deterministic priority nodes and deliberate randomness. Examples include `RandSelector`, `RandFilter`, `SometimesRandomizeTarget`, random target-score additions, and difficulty conditions at `DefaultAI.ini` lines 616–621.

### Inference and unavailable internals

`GenerateBehaviorTree`, `CreateBehaviorNode`, and `ConstructBTNodeObject` are native. The configuration and generated debug UI prove their role, but allocation, caching, and exact parser behavior cannot be inspected from the supplied C++ source because it is absent.

### FuseFire comparison

FuseFire's `units/ai_controller.gd` uses imperative priority flow: mission-special handling, attacks, advances, safety checks, and Wait fallbacks. `ObjectiveManager.get_mission_intent` supplies high-level purpose; `AIDifficultyPolicy`, `AIPositionScorer`, and `AITargetScorer` supply utility values.

FuseFire therefore already has selectors and conditions conceptually, but they are GDScript branches rather than authored nodes. It does not have a reusable sequence/selector runtime, per-character tree roots, decorators, or configuration-driven policy graphs.

### Adoption value, risk, and testability

**Problem a concept could solve:** make policy order visible, allow unit archetypes or doctrines to reuse named decision fragments, and keep mission-specific priority from accumulating in one controller.

**Recommendation:** do not adopt a general behavior-tree runtime yet. First extract a small, typed decision-policy boundary that returns candidate actions or named intents. FuseFire's existing utility scorers can remain the decision core. If several later archetypes need independently authored priority graphs, that evidence could justify a tree or another declarative policy format.

**Implementation risk:** high for a full BT runtime; medium for a small policy/intent layer.  
**Testability:** good if each policy is a pure seeded evaluation returning a trace; poor if configuration strings and scene objects are introduced without schema validation.

## 2. Tactical target selection and scoring

### Verified SDK behavior

Target selection uses an explicit stack-and-accumulate protocol.

`DefaultAI.ini`, target selection section around line 1150, documents and defines the flow:

1. `SetTargetStack-<Ability>` gathers legal available targets for an ability.
2. `RepeatUntilFail` repeatedly calls an evaluation sequence.
3. `SetNextTarget` makes one stack entry current.
4. score conditions/actions add or subtract values.
5. `UpdateBestTarget` retains the highest positive result.
6. `HasValidTarget-<Ability>` gates the final `SelectAbility-<Ability>`.

The generic evaluator combines hit chance, health, flanking, marked status, difficulty modifiers, civilian treatment, and bound/panicked exclusions. Specialized chains exist for suppression, psi attacks, mind control, VIP exclusions, jobs, priority targets, retaliation, The Lost, and Chosen abilities.

`XGAIBehavior` implements the runtime state:

- `BT_SetTargetStack` at line 3196;
- `BT_SetPotentialTargetStack` at line 3233;
- `BT_SetNextTarget` at line 3863;
- `BT_AddToTargetScore` at line 3883;
- `BT_UpdateBestTarget` at line 4011;
- `BT_GetBestTarget` at line 4132.

`BT_UpdateBestTarget` keeps only targets with a positive score and stores the best entry for the current ability. This gives invalidation a simple convention: make a candidate non-positive or fail an evaluation branch.

The scores are intentionally legible rather than statistically optimal. The default hit-chance buckets award 10, 40, or 70; health, flanking, soldier rank, status, distance, and mission-specific rules add discrete values. Small random additions break ties and vary behavior. Difficulty modifiers are part of the same scoring chain.

WotC also contains a generic ability scorer in `XGAIBehavior.ScorePotentialAbility` at line 833. It gathers valid targets, rejects low hit chances for direct attacks, obtains damage previews from `XComGameState_Ability`, favors the best predicted damage, applies a standard-shot multiplier, rewards free actions, and penalizes turn-ending abilities that waste available AP. `CollectPotentialAbilities` and `IsValidPotentialAbility` obtain the candidates from the rules cache rather than inventing legality in the AI.

### FuseFire comparison

FuseFire's `systems/ai/ai_target_scorer.gd` already accumulates vulnerability, focus, VIP, threat, and mission components. `AIController._find_attack_target` asks `BattleController.evaluate_attack` for legality, records rejected candidates and score components, sorts legal candidates, and lets `AIDifficultyPolicy.choose_near_best_index` introduce a bounded mistake.

This is already a simpler equivalent for the current attack vocabulary. FuseFire additionally exposes candidate traces and heatmap/debug context directly in battle logs.

What FuseFire lacks is the ability-relative target context XCOM uses. With only a basic attack, one target scorer is sufficient. With suppression, healing, hacking, AoE, shields, melee, status abilities, or equipment actions, legality and scoring will differ by ability and hostility type.

### Adoption value, risk, and testability

**Problem a concept could solve:** future actions need their own target candidate source, constraints, and score components without adding another special branch to `AIController`.

**Recommendation:** retain utility scoring, but make it action-relative when the second or third meaningfully different targeted ability arrives. A candidate could carry `action`, `target`, `predicted outcome`, `cost`, `score components`, and rejection reason. This is the useful XCOM concept; the target-stack syntax is not required.

**Implementation risk:** medium because it touches action legality, AI policy, debug traces, and future ability definitions.  
**Testability:** high with table-driven candidate fixtures, seeded tie-breaking, and replay/state-fingerprint tests.

## 3. Movement, cover, flanking, and positional evaluation

### Verified SDK behavior

XCOM separates candidate restrictions from weighted preference profiles.

Behavior nodes first reset destination search and can impose hard restrictions such as:

- enemy or ally line of sight;
- flanking, non-flanking, or unflanked tiles;
- high cover;
- ability range or potential-target range;
- minimum ally count in an ability radius;
- axis, ground, hazard, dash, height, or melee constraints.

The tree then selects a named movement profile through actions such as `FindDestination-MWP_Defensive`, `...Standard`, `...Aggressive`, `...Flanking`, `...AdvanceCover`, or melee variants (`DefaultAI.ini` lines 721 onward).

The profiles are data in `DefaultAI.ini` lines 222–262. They combine cover, ideal-range distance, flanking, enemy visibility, ally visibility, priority-target distance, height, randomness, and special modifiers. Examples:

- `MWP_Defensive` weights cover and ally visibility strongly;
- `MWP_Aggressive` weights distance and flanking more strongly;
- `MWP_Fanatic` gives cover zero weight;
- `MWP_Flanking` gives flanking a weight of 10;
- height-aware and special-ability profiles reuse the same score structure.

`XGAIBehavior.ScoreDestinationTile` at line 2047 computes deltas from the current tile for cover, flanking, visibility, ally support, and height. `GetWeightedTileScore` at line 2077 applies restrictions first, rejects the current location, computes ideal-range distance change, multiplies each component by the selected profile, adds stable per-tile random variation based on decision history and coordinates, then applies teammate-spread penalties. `FillTileScoreData` supplies raw measurements. Candidate processing is spread over timer ticks by `BT_StartGetDestinations` and `BT_StepProcessDestinations` to avoid one long blocking calculation.

The configured global constants also show design intent: no-cover, half/full-cover factors; extra full-cover preference for pod leaders; minimum teammate spacing; height thresholds; and a linger penalty that slightly reduces the current tile's appeal.

### Inference and unavailable internals

Several spatial helpers are native, including parts of movement range and enemy-cover caching. Their callers establish inputs and outputs, but exact path-search and visibility implementations are not fully visible.

### FuseFire comparison

FuseFire's `AIPositionScorer.evaluate` already returns component scores for progress, cover, exposure, firing opportunity, danger, and squad adjustment. `AIController._move_along_goal_path` generates reachable candidates, applies hard safety/corridor rules, scores them, filters against a hold threshold, introduces bounded near-best choices, and records every accepted or rejected tile. `SquadContext` adds reservations and crowding. Carrier and escort paths add mission-specific constraints.

FuseFire therefore already matches the important utility pattern. The notable difference is profile selection. XCOM chooses a named positional doctrine and reuses one scorer; FuseFire changes weights through difficulty policy and embeds several contextual adjustments in controller branches.

### Adoption value, risk, and testability

**Problem a concept could solve:** make “defensive,” “advance,” “flank,” “escort,” “carrier,” and later equipment-driven movement understandable data rather than controller-specific arithmetic.

**Recommendation:** consider typed FuseFire movement profiles after the XCOM study, but preserve FuseFire's continuous elevation/stair traversal and current pathfinder. Profiles should select weights and hard constraints; they should not replace the map or movement model.

**Implementation risk:** medium. Poor profile composition could hide mission requirements or recreate the carrier deadlock.  
**Testability:** high using `733578405`, existing position-scoring fixtures, map batches, wait counts, route progress, deterministic traces, and explicit hold-vs-move cases.

## 4. Alertness, perception, and knowledge

### Verified SDK behavior

XCOM represents knowledge as persistent, typed alert records rather than a single “enemy visible” flag.

`XComGameState_AIUnitData.uc` owns `m_arrAlertData` and implements:

- `AddAlertData` at line 303;
- expiration/removal at line 691;
- absolute-knowledge lists at line 744;
- `HasAbsoluteKnowledge` at line 821;
- priority distance updates at line 845;
- `GetPriorityAlertData` at line 863;
- knowledge lookup by unit and tile at lines 907–952;
- cause classification (`absolute`, nonvisible-allowed, aggressive, suspicious, reflex-move-triggering) at lines 973–1060.

An alert records cause, source, tile, radius, knowledge type, age, and optional Kismet tag. Causes include seeing a unit, taking damage/fire, corpses, sound, ally damage, yells, comm links, civilian alarms, smoke, fire, explosion, map-wide alerts, objectives, and throttling beacons.

The behavior configuration distinguishes Green, Yellow, Orange, and Red alert (`DefaultAI.ini` lines 566–569). It scores alert records by knowledge certainty, danger, corpse/noise meaning, age, and distance around lines 1090–1160. Absolute knowledge receives a high score, former knowledge less, sounds and corpses smaller values; old data decays and can be deleted. Yellow and Orange branches investigate alert destinations, while Red enables engaged combat behavior. Group reveal/scamper uses the same state transition machinery.

The visibility system is separate. `X2GameRulesetVisibilityManager.uc`, `X2GameRulesetVisibilityInterface.uc`, and `X2TacticalVisibilityHelpers.uc` provide rules-level visibility data. Alert records consume observations from that system; they do not replace LOS checks.

### FuseFire comparison

FuseFire currently evaluates actual units and current LOS/exposure. AI obtains current hostile lists, combat legality, threat, mission actors, and objective intent. It has recent move origins and squad reservations, but it does not model uncertain enemy knowledge, suspicious locations, heard events, knowledge decay, or an investigation state.

This is expected for Prototype 1's fully informed tactical battles. It becomes relevant only when Prototype 2 introduces concealment, reconnaissance, real-time exploration, smoke, noise, or partial information.

### Adoption value, risk, and testability

**Problem a concept could solve:** stop AI from acting on omniscient state while still letting it investigate evidence and share appropriate knowledge.

**Recommendation:** do not add XCOM's four alert levels now. Preserve the concept as a future typed `TacticalKnowledge`/observation ledger owned outside the decision controller. Introduce it only alongside a concrete perception mechanic, beginning with visible/current and last-known observations.

**Implementation risk:** high because it changes what every AI is allowed to know and affects replay, objectives, targeting, and debugging.  
**Testability:** medium-to-high if observations are deterministic data with timestamps; difficult if perception is read opportunistically from scene nodes.

## 5. Squad/pod behavior and tactical jobs

### Verified SDK behavior

XCOM has two related coordination layers.

`XComGameState_AIGroup.uc` is persistent pod/group state. It stores members, calculates group midpoint and mobility, tracks engagement and sighting, initiates reflex reveal/scamper, coordinates fallbacks, moves members as a group, and exposes group-wide ability lookup. `XGAIGroup.uc` and `XGAIPatrolGroup.uc` provide visualizer/navigation behavior, patrol destinations, and current/previous alert state.

`XGAIPlayer.uc` coordinates the whole AI side. It gathers units to move, orders them, waits for visualization and scamper barriers, starts the next unit, tracks aggressive-unit usage, caches enemies and dangerous areas, and records turn-wide state. `GatherUnitsToMove` and `AddToOrderedCharacterList` combine unit availability, group state, jobs, and priorities.

`X2AIJobManager.uc`, configured by `DefaultAIJobs.ini`, assigns tactical roles. Job definitions specify valid character types in priority order, movement-order priority, disqualifying effects, and whether engagement is required. The default list includes Scout, Leader, Soldier, Aggressor, Support, Artillery, Observer, Flanker, Terrorist, Executioner, Hunter, Charger, and scenario-specific jobs.

At turn initialization, the manager rebuilds the active job list for the mission, assesses existing assignments, and fills vacancies. `AssignGroupToJob` can assign an entire pod. Behavior conditions `HasJob` and `IsMyJob` select `JobRoot_<name>` branches. Kismet can post, revoke, or prioritize jobs and targets through `SeqAct_AIJobUpdate`, `SeqAct_SetPriorityTarget`, and related actions.

XCOM's fight manager also throttles simultaneous engagement. `XComGameState_AIPlayerData` tracks engaged groups and can place group-specific throttling beacons, preventing every inactive pod from converging at once. This is encounter pacing as much as tactical intelligence.

### FuseFire comparison

FuseFire's `SquadContext` already coordinates destination reservations, focus counts, recent origins, and the carrier corridor. Turn order prioritizes a rescued-VIP carrier. Objective intent gives all relevant units a shared mission purpose. Carrier, escort, VIP, and ordinary combat behavior act like implicit roles.

FuseFire does not have persistent explicit role assignments, pod membership, an AI-side commander, encounter activation, or engagement throttling. In current small battles, adding XCOM's job manager would duplicate simple rules with a large framework.

### Adoption value, risk, and testability

**Problem a concept could solve:** prevent every unit from solving the same local problem, establish action order, reserve scarce responsibilities, and coordinate support/attack/movement across a squad.

**Recommendation:** extend `SquadContext` with a small per-round commitment ledger before considering permanent jobs. Commitments could include “carrier,” “route clearer,” “threat engager,” “support destination,” or later “ability reserved,” each with owner, target, expiry, and reason. This suits FuseFire's mission AI and is easier to invalidate than XCOM's character-priority job table.

**Implementation risk:** medium; stale commitments can cause worse deadlocks than no coordination.  
**Testability:** high with deterministic multi-unit scenarios, explicit expiry assertions, duplicate-claim tests, carrier-route fixtures, and trace reconciliation.

## 6. Difficulty-related decision changes

### Verified SDK behavior

XCOM exposes difficulty to the tree as a stat condition. `DefaultAI.ini` lines 616–621 define Easy, Normal, Hard, Classic, above-Normal, and low-difficulty checks. Trees use them to enable or suppress branches, alter target modifiers, and gate more capable choices.

Difficulty is not the only source of imperfection. Random selectors and filters choose among authored alternatives; target scoring can receive random additions; movement profiles can include deterministic random tile weights; non-aggressive behavior uses probability; and character-specific trees intentionally select suboptimal or thematic actions.

The generic target chain includes `ApplyDifficultyModifiers`, while character trees sometimes contain explicit difficulty branches. The result is qualitative policy variation plus noise, not merely inflated unit statistics.

The exact native stat lookup behind every `StatCondition` is not present, but the configuration and condition classes verify the decision gates.

### FuseFire comparison

FuseFire's `AIDifficultyPolicy` adjusts target and movement weights, exposure tolerance, mission/threat emphasis, and a `lapse_score_margin`. Easy and Normal may pick a near-best candidate; Hard takes the best. Dedicated smoke tests verify policy differences and intentional mistakes.

FuseFire already captures the most desirable principle: believable errors within legal, explainable choices. It currently has fewer action types, so branch-level difficulty differences are limited.

### Adoption value, risk, and testability

**Problem a concept could solve:** later difficulties may need different information use, coordination discipline, or action preferences rather than only different score weights.

**Recommendation:** keep the present policy object. When new abilities or doctrines exist, let policy influence candidate availability or commitment discipline explicitly, and log the rejected/allowed branch. Avoid scattering `if difficulty` checks through action code.

**Implementation risk:** low-to-medium if centralized; high if authored policy fragments become untraceable.  
**Testability:** high with fixed candidate sets, seeded RNG, distribution bounds, and existing intentional-mistake tests.

## 7. Ability selection and coordination with tactical rules

### Verified SDK behavior

The behavior tree does not execute bespoke combat logic. It selects an existing tactical ability.

`X2AIBTDefaultActions.SelectAbility` validates the named ability through `XGAIBehavior.IsValidAbility`, checks whether a destination is required and available, then records the selected ability name. `XGAIBehavior.BTExecuteAbility` resolves the selected cached `AvailableAction`, target, target locations, and destination. It submits through the ability/game-state machinery and waits for `LatentExecuteAbilityCallback`. The callback dirties the cache, records completion, and resumes or ends behavior processing.

Legality and prediction come from authoritative objects:

- `XComGameState_Ability` supplies available targets, shot breakdown, damage preview, costs, and templates;
- `X2AbilityTemplate` defines action costs, turn-ending behavior, target styles, multi-target styles, hostility, and effects;
- the game-rules cache supplies actions currently available to the unit;
- visualization follows submitted game-state contexts rather than being the source of truth.

`EquivalentAbilities` in `DefaultAI.ini` lines 269–282 maps concrete abilities such as pistol/sniper shots to semantic keys such as `StandardShot`. This lets one decision fragment work across multiple equipment implementations. AoE profiles describe who may be targeted, friendly-fire/objective restrictions, required target counts, LOS, and path validation.

Effects can also request a named behavior-tree reaction: `X2Effect_RunBehaviorTree` is used by abilities such as Archon Frenzy, Berserker Rage, Cyberus Superposition, Chosen Agile movement, and Lost burning responses. The rules/effect system owns the trigger; AI policy selects the response.

### FuseFire comparison

FuseFire already shares execution APIs. AI calls `BattleController.evaluate_attack` and `try_attack`, `try_move`, and objective-manager rescue/extract operations. Replay reuses authoritative operations. Small action classes exist, but move/attack/objective APIs and presentation orchestration are still distributed across `BattleController` and `ObjectiveManager`.

FuseFire lacks an ability definition that uniformly describes cost, legality, target generation, predicted outcome, execution, and presentation. That absence is harmless with Move, Attack, Skip, Rescue, and Extract; it will become expensive with a broad equipment/action vocabulary.

### Adoption value, risk, and testability

**Problem a concept could solve:** one semantic action contract for player UI, AI, replay, equipment, status effects, and previews, eliminating duplicated legality and special dispatch.

**Recommendation:** study this boundary further in Task 03 before implementation. If adopted, begin with existing actions and prove that Move/Attack/Skip/Rescue/Extract can share a small contract without forcing every future effect into an XCOM-sized framework. Semantic tags or capabilities are more robust than concrete class-name checks.

**Implementation risk:** high because this can become the central tactical API and touches save/replay schemas, UI, AI, and presentation.  
**Testability:** very high in principle: each action can expose legal/illegal fixtures, deterministic outcome previews, cost application, serialized intent, and authoritative execution tests.

## 8. Debugging, configuration, and authoring

### Verified SDK behavior

XCOM's AI is unusually inspectable:

- `DefaultAI.ini` authors tree nodes, movement weights, AoE profiles, equivalent abilities, score constants, and difficulty gates.
- `DefaultAIJobs.ini` authors job qualifications and order priorities.
- character templates choose a root and scamper tree.
- Kismet sequence actions can execute a tree, set directed behavior, force a destination, post/revoke jobs, set a priority target, set a target unit, change alert state, or skip AI.
- `XGAIBehavior.SaveBTTraversals`, `AddTraversalData`, `GetBTTraversalDebugString`, and `CompileBTString` preserve node-by-node results and details.
- `UIDebugBehaviorTree.uc` provides “BehaviorTree Traversal History,” reconstructs the selected character's tree, and displays saved traversals with invalid-node filtering.
- `XGAIPlayer.LogAI`, `LogAIBT`, and `DumpAILog` separate general AI and tree logs.
- cheat-manager hooks record the last action/intent, force an ability, override a root node, display visibility and AI strings, and report timeouts or missing choices.
- movement evaluation retains `DebugTileScores`; target evaluation prints component additions and the current best candidate.

The system also validates many names at startup and raises red-screen diagnostics for invalid roots, missing targets, illegal ability selection, a running tree being replaced, and missing destinations.

### FuseFire comparison

FuseFire already records a clearer high-level explanation than many games: goal, action, subject, reason, alternatives, position components, target components, rejection causes, reservations, thresholds, recent origins, and corridor state. Debug overlays expose score candidates and heatmaps. Seeded simulations and replay make traces reproducible.

FuseFire's authoring is less data-driven. Inspector tunables and policy classes are human-friendly, but decision priority is code. It also lacks a stable machine-readable decision-event schema: logs use dictionaries assembled through the controller.

### Adoption value, risk, and testability

**Problem a concept could solve:** preserve explainability while policy is decomposed, compare before/after decisions automatically, and let authored profiles fail fast instead of silently referencing missing actions or score terms.

**Recommendation:** establish a typed decision trace/candidate record before large AI changes. It should include seed/context, considered action, legality result, component scores, selected policy/profile, coordination commitments, chosen result, and fallback reason. Add validation for any authored profile names. FuseFire does not need XCOM's traversal UI unless it later gains a graph runtime.

**Implementation risk:** low-to-medium if introduced alongside current dictionaries and migrated gradually.  
**Testability:** high through snapshot/schema tests and deterministic trace comparisons; avoid brittle full-string assertions.

## Observable XCOM decision flow

The verified normal combat path can be summarized as follows:

1. `XGAIPlayer` gathers living AI-controlled units with available actions, orders them using group/job/special priorities, and begins one unit.
2. `X2AIBTBehaviorTree` queues or starts a named root after visualization/history barriers are satisfied.
3. `XGAIBehavior` refreshes the rules cache, known allies/enemies, alert data, behavior variables, and current tactical context.
4. The configured root tries ordered selector branches. Conditions query unit state, alerts, jobs, difficulty, effects, objectives, targets, and ability readiness.
5. Target branches obtain legal candidates from an ability, iterate a stack, accumulate scores, and retain the best positive target.
6. Movement branches apply hard destination restrictions, score reachable tiles using a named movement profile, and retain the best tile.
7. An action leaf validates and marks a semantic ability selection, optionally with target and destination.
8. `BTExecuteAbility` resolves the selected `AvailableAction` and submits it through the tactical ability/game-state rules engine.
9. Visualization/game-state completion calls back into AI, invalidates caches, records traversal/debug data, and either runs again for remaining AP or advances the AI player.
10. Failure and timeout paths log diagnostics and safely skip/end rather than executing an unverified action.

This flow is verified at the UnrealScript/configuration boundary. The native behavior-tree factory and some spatial algorithms are the principal unavailable internals.

## Ranked shortlist for FuseFire

These are research candidates, not approved implementations.

### 1. Unify tactical action queries around a small semantic action contract

**Why first:** every future weapon, equipment action, status, AI choice, replay event, and UI preview needs legality, candidates, cost, predicted outcome, and execution. XCOM's strongest boundary is that AI selects rules-engine abilities rather than implementing them.  
**FuseFire equivalent today:** shared `BattleController`/`ObjectiveManager` attempt APIs and small action classes, but no complete uniform contract.  
**Risk:** high.  
**Test strategy:** migrate one existing action at a time; prove identical milestone/replay fingerprints before adding features.

### 2. Add typed decision candidates and a stable decision-trace schema

**Why second:** this makes every later experiment measurable and prevents decomposition from reducing explainability. It also replaces private-method tests and ad hoc dictionaries with behavioral records.  
**FuseFire equivalent today:** rich but controller-assembled trace dictionaries and log strings.  
**Risk:** low-to-medium.  
**Test strategy:** schema validation, deterministic candidate snapshots, and compatibility with existing debug overlays.

### 3. Introduce named movement-policy profiles with explicit hard constraints

**Why third:** FuseFire already has a good scorer, but escort/carrier/survival/advance rules are spread between scorer, difficulty, and controller. Profiles can reuse the scorer without replacing continuous traversal.  
**FuseFire equivalent today:** `AIPositionScorer`, safety checks, corridor rules, and difficulty weights.  
**Risk:** medium.  
**Test strategy:** exact-seed trace comparison, especially `733578405`, plus map batches and wait/progress metrics.

### 4. Extend `SquadContext` into a short-lived commitment ledger

**Why fourth:** it addresses duplicate effort and action ordering with less machinery than XCOM's global job manager. Commitments should expire and remain mission-aware.  
**FuseFire equivalent today:** destination/corridor reservations, focus counts, recent origins, and carrier priority.  
**Risk:** medium.  
**Test strategy:** duplicate-claim, expiry, unit-death, blocked-route, and deterministic multi-unit scenarios.

### 5. Preserve a typed tactical-knowledge model for the first real perception feature

**Why fifth:** XCOM's alert records are the relevant pattern for future recon, concealment, noise, smoke, and last-known positions, but implementing them before those mechanics would be speculative.  
**FuseFire equivalent today:** current omniscient hostile lists and LOS/exposure queries.  
**Risk:** high.  
**Test strategy:** deterministic observation events, knowledge decay, information-sharing limits, replay, and explicit “AI may not know this unit” assertions.

## Decision on behavior trees

Behavior trees solve a real XCOM problem: thousands of reusable, data-authored priority fragments across many enemy archetypes, abilities, alert modes, scripted encounters, and DLC additions. They also impose string-based authoring, a custom runtime, native factory code, extensive validation, traversal debugging, and a large vocabulary of condition/action adapters.

FuseFire does not currently need that machinery. Its utility architecture can incorporate the most useful XCOM concepts more simply:

- semantic legal action candidates from the tactical rules layer;
- action-relative target scoring;
- named positional profiles and hard constraints;
- short-lived squad commitments;
- typed knowledge when perception exists;
- stable, inspectable decision traces.

If Prototype 1.5 later produces several unit archetypes whose priority policies must be authored independently of code, a behavior tree can be reconsidered with concrete requirements and migration tests. Until then, the evidence favors decomposing the existing utility pipeline rather than replacing it.
