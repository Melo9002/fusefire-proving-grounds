# Architecture and behavior

## Ownership and decision flow

Each tactical unit receives an `AIController` when the battle scene creates it (`BattleLevel._create_unit`). The controller is present on player, ally, and enemy units. Whether it acts depends on phase and debug mode:

- enemy units act automatically unless manual enemy control is enabled;
- allies act automatically during the ally phase;
- player units act automatically only in AI-versus-AI mode;
- replay mode disables tactical AI.

The complete flow is:

1. `TurnManager` refreshes a faction and selects an eligible active unit.
2. `active_unit_changed` reaches that unit's `AIController._on_active_unit_changed()`.
3. The controller obtains mission intent, opens its team's round-scoped `SquadContext`, clears diagnostic state, and calls `_execute_turn()`.
4. `_run_activation()` waits 0.6 presentation seconds and loops while the unit has AP, remains valid, the battle continues, and this controller still owns the activation.
5. The controller asks `BattleController` for queries or calls its `try_*` adapters.
6. `BattleController` delegates to `TacticalActionService`, which validates, resolves, commits, presents, and returns the result.
7. The controller re-evaluates after each committed action. A 0.25-second presentation delay follows attacks.
8. When the policy finishes, `TurnManager.advance_automated_player()` or `end_current_turn()` advances the activation queue.

The `_is_executing` guard prevents one unit from starting overlapping activation coroutines. The action service's busy state and TurnManager's presentation barrier prevent phase progression through an action still being presented.

This division is important: AI code chooses what to request, but it does not spend AP, roll attacks, apply Guard reactions, move occupancy, complete objectives, or decide whether an action is legal. Those remain authoritative shared-system responsibilities.

## Top-level policy

`AIController._run_activation()` is an ordered policy, approximately:

```text
if zero AP: try one legal free mission action
if already eligible to extract: extract

while AP remains:
    use Emergency Seal if Leaking and legal
    if escorting a carrier and clear of its route: take a legal threat shot
    perform immediate mission interaction or mission movement
    if carrying and unable to advance: wait
    find a legal scored attack target
    aim first when Aim + Attack fit and the shot is not already 100%
    attack
    reload when depleted, or on final AP with at most 1 SP
    if a Reach/Extract goal still cannot advance: wait
    perform carrier support and corridor-clearing behavior
    make a first approach move toward the nearest hostile
    make a second move only if exposure does not worsen beyond policy tolerance
    on the final AP, Shield against the highest-hit-chance legal threat
    Guard if a reaction is plausible and this is not a repeated low-value cycle
    otherwise Wait
```

This order is a hard priority. Emergency Seal preempts combat. An immediately available mission step normally preempts ordinary attack selection, except for the special escort-threat shot. Aim is considered only after a legal target has been selected. Shield is considered only on exactly 1 AP and late in the ladder. Guard is a fallback commitment rather than an action scored against Attack or Move.

## Candidate generation

### Attacks

`_find_attack_target()` asks `query_attack(unit)` for the authoritative inventory of candidate results. Every hostile from the living turn rosters is represented as either:

- a legal scored target; or
- a rejected target retaining the service validation code and reason.

If the actor is escorting a rescued-unit carrier, and any legally attackable hostile can itself legally attack that carrier, the candidate set is restricted to those threats. Otherwise all legal hostiles are scored.

Aim is generated only when Aim is legal, the chosen Attack is legal, the combined AP cost fits, and the current hit chance is below 100. Reload is generated only below maximum SP and either at zero SP or at at most 1 SP on the final AP.

### Movement

The AI starts with `query_move(unit).legal_destination_cells`, so AP, movement range, terrain cost, occupancy, traversal, and action-window restrictions come from the authoritative Move query. It then narrows those destinations for the current goal:

- a path toward the target or objective must exist;
- candidates normally remain within a route corridor;
- escort units cannot enter the carrier's reserved corridor;
- exact allied reservations are rejected and adjacent reservations are penalized;
- second advances must pass an exposure test;
- recent origins receive revisit penalties;
- most non-carriers must beat the score for holding position by at least 1 point, reduced by anti-stalemate urgency.

At maximum urgency, an objective mover may accept a legal route detour or the least-bad route step. Carriers may accept a negative local step when congestion or geometry requires it, but prefer positive-progress options whenever one exists.

### Mission actions

`ObjectiveManager.get_mission_intent()` assigns the first applicable intent in this order:

1. Rescue.
2. Extraction when the unit should seek it.
3. Reach.
4. Interact Terminal.
5. Protect.
6. Survive.
7. Eliminate.

Faction ownership on each objective is authoritative. Enemy units therefore do not pursue player-only terminals or rescue goals. The controller submits Rescue, Extract, and terminal interaction through their shared authoritative actions. Terminal interaction remains available after the final movement AP because it is a legal free mission action.

### Defensive actions

Shield requires an actual shield capability, exactly 1 remaining AP at the policy call site, a legal authoritative Shield query, and at least one hostile with a currently legal incoming attack. The selected threat is the one with the highest current hit chance; equal scores use lexical tactical ID.

Guard requires a legal authoritative Guard query, no prior low-value defensive cycle, and a plausible trigger. A trigger is plausible when the actor can legally shoot a hostile now, or when the current actor-to-hostile distance is no greater than `attack_range + hostile movement speed`. This is a coarse reachability estimate; it does not predict an actual hostile path or future line of sight.

## Tactical behavior

### Targets

Legal targets are scored for wounds, finishing opportunity, hostile VIP status, threat to friendlies, mission relevance, and allied focus. The exact formula is in [the scoring reference](scoring-reference.md). Hit chance and expected damage are recorded for diagnostics but currently do not contribute directly to target score. Attack legality already incorporates range, line of sight, cover, obstruction, Shield, AP, SP, faction, and tactical state.

### Positions, cover, and elevation

Position scoring evaluates route progress, directional cover from each hostile, incoming hostile firing lanes, outgoing firing lanes, close-range danger, multiple-lane danger, and squad spacing. Objective travel disables the firing-lane reward and strengthens protection. Carriers strengthen protection further and receive no firing reward.

There is no separate “take high ground” bonus. Elevation matters indirectly through 3D world-space attack distance, path connectivity and cost, line-of-sight geometry, directional cover, and whether a shot is legal. A high cell is preferred only when those consequences improve its score or route progress.

### Aggression and caution

The AI attacks whenever a legal scored target reaches the attack portion of the policy. Movement is cautious because a candidate usually must beat holding position, second movement cannot exceed the allowed exposure increase, and danger penalties punish close and crossfire positions. Repeated Wait, Guard, or Shield decisions raise a bounded urgency state; after several low-value actions the acceptance threshold falls and the route corridor widens. Productive Move, Attack, Rescue, Extract, Interact, or Support resets that state. Carriers, VIPs, and critically wounded units do not receive the ordinary urgency relaxation.

### Coordination-like behavior

The following coordination is explicit but lightweight:

- one `SquadContext` is shared by player+ally factions and another by enemies;
- later units avoid exact reserved destinations and dislike cells adjacent to them;
- each additional ally intending to attack a target applies a focus penalty;
- units record objective handlers for diagnostics and future spread/support reasoning;
- a rescue carrier reserves its complete evacuation corridor;
- escorts clear that corridor, avoid occupying it, rejoin the carrier, and seek positions 2–5 cells away, ideally 3;
- when protecting a carrier, attack selection can be restricted to hostiles that can legally threaten it.

There is no faction-level turn planner. The apparent “massive trap” produced by several units using Guard can emerge because each independent unit has no useful attack or safe advance, sees a plausible Guard trigger, and commits its remaining AP. Shared positioning and target reservations make those independent choices less likely to collide, which strengthens the appearance of a coordinated plan.

## Determinism and difficulty

Each AI controller seeds its private decision RNG as:

```text
ai_decision_seed * 1,000,003 + hash(unit.name)
```

Combat uses the battle combat RNG instead. AI decision randomness is limited to bounded Easy and Normal “lapses” among near-best targets or positions. Hard always selects the best eligible scored option. Stable action ordering, sorted reachable cells, stable actor IDs, and authoritative action service results provide the rest of deterministic behavior. Some equal-score selections still inherit candidate iteration order; see the tuning notes.

