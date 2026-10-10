# Prototype 1.5 Remaining Actions Audit

Task 01.8 began at `d167e02` on `p2-foundation`. The implementation and the locally installed War of the Chosen SDK were inspected before code changes.

## FuseFire lifecycle audit

| Action or command | Availability and cost | Commit and presentation | Replay/headless | Finding |
| --- | --- | --- | --- | --- |
| Wait/Skip | `TacticalActionService._validate_actor`; remaining AP is exhausted | `submit_simple` commits AP/revision/transaction, then `TacticalActionPresenter.present_simple` reports the reason | Typed schema-2 `SimpleActionResult`; normal service replay; suppression supported | Already migrated. HUD used a parallel AP check and no read-only query existed. |
| Defend | Same actor/AP validation; costs one AP and sets `is_defending` | Same simple-action commit and presenter | Retained only for explicit legacy replay records | Already migrated for compatibility. No current player or AI authoring path selects it. Its effect lifetime remains the existing turn reset behavior. |
| Rescue | `ObjectiveManager.can_rescue` checks active objective, faction, target identity/kind, carrying state, and adjacency; zero AP | `submit_mission` calls the objective-owned commit once, captures objective/counter state, then presents pickup feedback | Typed schema-2 `MissionActionResult`; normal service replay; suppression supported | Already migrated. AI queried `ObjectiveManager` directly before using the service. Automatic movement pickup correctly remains inside the Move transaction. |
| Extract | `ObjectiveManager.can_extract` checks roster, faction objective, zone, movement state, and Survive gate; intentionally zero AP and may apply to an exhausted unit | Mission commit updates counters/objectives/roster synchronously; presenter boards and releases the visual actor | Typed mission result and normal replay path | Already migrated. World-bar and AI availability checks bypassed a shared read-only action query. |
| Reach / automatic Rescue | `ObjectiveManager._on_unit_moved` reacts to the committed destination | Consequences are synchronous children of the parent Move commit and appear in its objective snapshot/fingerprint | Exactly one Move record; no nested Rescue record | Correct and intentionally preserved. |
| End turn | `TurnManager` owns phase/queue legality | Dedicated authoritative command; advances the action-service revision through the controller signal | Explicit `end_turn` command record | Correctly kept outside the unit-action service. |
| Depart | `ObjectiveManager.can_end_mission_early` owns mission-wide eligibility | Dedicated mission command commits left-behind count and final result, advances revision, records `depart` | Replay invokes the same command | Correctly kept outside the unit-action service. |

The action service is already the commit boundary. The genuine consistency gap is query ownership: player and AI consumers cannot ask it whether Wait, Defend, Rescue, or Extract is currently available or why it is rejected.

## XCOM 2 SDK research

Source root: `C:/Program Files (x86)/Steam/steamapps/common/XCOM 2 War of the Chosen SDK/Development/SrcOrig/XComGame/Classes`.

- `X2Ability_DefaultAbilitySet.uc::AddHunkerDownAbility` composes an action-point cost, shooter conditions, persistent stat-change effects, a turn-begin removal effect, an availability override, and `HunkerDownAbility_BuildVisualization`. The useful principle is explicit availability/cost/effect/presentation composition. FuseFire's current Defend is much smaller and does not justify templates or an effect hierarchy.
- `X2Ability_DefaultAbilitySet.uc::AddOverwatchAbility` spends ordinary points through an effect that creates reserve points; `AddOverwatchShotAbility` consumes those reserve points and registers `XComGameState_Ability::TypicalOverwatchListener`. Reaction registration and reaction execution are separate abilities/state changes. FuseFire has no reaction action yet, so reserve-point and interrupt machinery is deferred rather than hidden inside Defend.
- `X2Ability_DefaultAbilitySet.uc` reload templates use `X2AbilityCost_ActionPoints`, ammo conditions, an ammo effect, and normal visualization. This reinforces keeping costs and eligibility queryable before authoritative effects; it does not justify adding Reload before FuseFire has ammunition.
- `X2AbilityTemplate.uc` evaluates costs and conditions for availability, applies costs/effects while building a new game state, and associates visualization builders with the committed state. `X2AbilityCost_ActionPoints.uc`, `X2AbilityCost_ReserveActionPoints.uc`, and the `X2Condition_*` classes keep those concerns explicit.
- `X2AIBTDefaultActions.uc` contains tactical object/civilian interaction actions and attaches rescue visualization to the newly committed game state. Interactions still use authoritative state first and visualization second.

## Decisions

### Adopt now

- Explicit read-only availability queries for simple and mission actions.
- Structured rejection code/message, cost, predicted AP, revision, legal rescue targets, and extraction facts.
- HUD and AI consume the same queries; commit always revalidates.

### Preserve

- Objective-specific eligibility and mutation remain discoverable in `ObjectiveManager`.
- Automatic Reach/Rescue remains part of Move.
- Turn and Depart remain dedicated commands.
- Defend remains replay-only until a later design milestone decides its gameplay future.

### Defer

- A generic world-interaction registry. Two current interactions do not justify it. Revisit when doors or terminals create repeated discovery/range/cost/commit code.
- Persistent-effect, reaction, reserve-AP, Reload, Overwatch, and Aim systems. XCOM demonstrates how to separate them, but FuseFire has no approved mechanics requiring them in Task 01.8.
