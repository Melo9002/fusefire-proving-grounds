# Commander architecture and strategic decision-making

## Status

This document separates the small foundation implemented by AI Foundation 2.0 from future commander behavior. **Default** is the only implemented commander profile. Aggressive, Cautious, changing strategic intent, and commander-directed action priorities remain proposed.

The governing relationship is:

```text
Commander doctrine and strategic intent
                ↓
Unit tactical policy and candidate scoring
                ↓
BattleController queries and TacticalActionService execution
```

A commander can influence values and coordination. It cannot make an illegal action legal, mutate AP or SP, move actors, resolve attacks, own mission progress, or replace `ObjectiveManager`.

## Implemented foundation

`AICommanderPolicy` is an immutable, typed doctrine object. `BattleController.get_commander_policy()` owns one policy instance per AI team:

- Player and Ally factions currently share team `0`, matching their existing `SquadContext` and non-hostile coordination.
- Enemy uses team `1`.
- Repeated requests during a battle return the same instance.
- Policies persist across round resets; `SquadContext` remains the round-scoped reservation store.
- Every battle starts with a fresh Default policy for each team.

`AIController` asks the battle for its team's policy and composes it with `AIDifficultyPolicy`. The implemented Default composition copies every difficulty field exactly. It introduces no new weights, gates, randomness, or action ordering. The existing `_policy` consumed by `AIPositionScorer`, `AITargetScorer`, and controller risk gates therefore has the same values as before.

Decision records now contain:

- `commander_policy`: readable name (`Default`).
- `commander_policy_id`: stable identity (`default`).
- `strategic_intent`: readable current intent (`Balanced engagement`).

The F3 AI decision explanation displays policy and intent. Replay fingerprints and authoritative actions are unchanged; these fields are diagnostic evidence only.

## Difficulty and personality composition

Difficulty and commander personality answer different questions:

| Layer | Responsibility |
| --- | --- |
| Difficulty | Decision consistency, bounded lapse probability, and current competence weights |
| Commander doctrine | Risk preference, objective pressure, target/position values, and narrow action-policy preferences |
| Strategic intent | Battle-specific emphasis derived from mission and battlefield state |
| Action service | Legality, cost, resolution, transaction, and presentation ownership |

The proposed composition rules are:

1. Create the selected `AIDifficultyPolicy` exactly as today.
2. Apply commander multipliers once to named scoring components. Default multipliers are `1.0`.
3. Apply commander deltas once to named thresholds such as safe-advance tolerance. Default deltas are `0.0`.
4. Evaluate legal candidates using the composed values.
5. Apply difficulty-owned bounded lapse selection to the final ranked candidates. Commander doctrine must not alter lapse probability or margin.
6. Submit the selected action through the existing authoritative gateway.

This prevents accidental double multiplication and keeps Hard+Cautious distinct from Easy+Cautious. Hard chooses the best option under cautious values consistently; Easy may select a bounded near-best option under the same doctrine.

Do not expose every numeric constant. The initial commander surface should be limited to values with clear behavioral meaning:

- position cover, exposure, firing, and danger multipliers;
- target vulnerability, finishing, focus, threat, and mission multipliers;
- movement progress and crowding multipliers;
- safe-second-advance tolerance and move-acceptance adjustment;
- a small set of explicit action-policy hooks for Guard, defense, or breakthrough behavior.

`survival_cover_weight` remains configured but inactive. Commander work must not silently make it active.

## Scoring and action priority remain separate

Commander candidate weights cannot affect an action category that `_run_activation()` never reaches. A firing-position multiplier changes the choice among movement cells; it does not make Move compete globally with Attack. FuseFire should preserve this inspectable distinction.

Future profiles may use narrow policy gates at explicit ladder decisions. For example, an Objective Breakthrough intent might permit a productive objective Move before an ordinary low-value Attack. Such a hook must state its trigger and retain the action service query. Avoid commander-name checks and avoid replacing the ladder with a global utility planner.

## Strategic intent proposal

The implemented intent is the immutable `BALANCED_ENGAGEMENT` label. Future battle-specific intent should live in a separate team-owned state object, not inside the immutable policy and not solely inside round-scoped `SquadContext`.

Possible future intents are Balanced Engagement, Aggressive Advance, Defensive Hold, Objective Breakthrough, Carrier Protection, and Tactical Withdrawal. A deterministic evaluator could derive intent from:

- authoritative mission intent and completion state;
- carrier/VIP status;
- friendly casualties and vulnerable actors;
- whether legal objective progress exists;
- nearby hostile pressure;
- repeated low-value rounds.

It should select among a small number of named states at documented boundaries, likely phase or round start. `ObjectiveManager.get_mission_intent()` remains the authority for what each unit's mission requires. Commander intent only changes how the squad pursues that requirement.

Long-lived intent should persist in a team-owned commander state. Destination, target, objective-handler, and corridor reservations remain in `SquadContext` and reset each round as they do now.

## Proposed profiles

These profiles are designs, not implemented behavior:

- **Aggressive:** stronger progress, finishing, and firing-position values; higher safe-advance tolerance; narrow preference for productive breakthroughs over passive defense. It must retain minimum survival gates.
- **Cautious:** stronger cover, exposure, crossfire, and vulnerable-unit preservation values; lower safe-advance tolerance; stronger preference for useful Guard and defensive positioning. Objective urgency must eventually overcome passivity.

Default remains the compatibility baseline. Every future profile test should compare Default traces and outcomes before accepting behavior changes.

## Decision-ladder diagnostics

Current diagnostics accurately record selected actions, legal and rejected movement/target candidates, scoring components, thresholds, squad adjustments, commander identity, and intent. They do not yet record every branch in `_run_activation()`.

A later diagnostic should record one bounded entry per policy branch with these states:

- `selected`: this branch committed the action;
- `illegal`: an authoritative query rejected it;
- `rejected_by_policy`: legal input existed but a documented tactical gate declined it;
- `not_reached`: an earlier committed action ended this evaluation pass.

It must distinguish “no candidate existed” from “an action was queried and rejected.” Implement this alongside the first real commander profile, when the required ladder hooks are known. Instrumenting every asynchronous exit during the identity-only groundwork would create unnecessary behavioral risk.

## Determinism and replay

Commander policy IDs must be stable data, never Node instance IDs. Future mutable commander state needs canonical ordering and replay/fingerprint treatment before it affects ordinary missions. Policy evaluation must consume no combat RNG. Difficulty lapse RNG remains seeded and isolated as it is today.

The current Default foundation changes neither action payloads nor authoritative fingerprints because it changes no battlefield state. The added decision-record fields are deterministic and appear equally in simulation diagnostics.

## Open decisions

- Whether future allies can own a distinct commander while remaining non-hostile to the player. Current ownership deliberately follows the shared player/ally team context.
- Which boundary may change strategic intent: phase start, round start, or specific mission events.
- Which first profile provides the best proof. Cautious exercises safety weights; Aggressive exercises both weights and a likely ladder hook.
- Whether commander selection belongs in match setup before profiles affect gameplay.
- Which commander state belongs in replay fingerprints once it can influence actions.

## Recommended next task

Implement one profile behind explicit match configuration, preferably Cautious because most of its identity can be expressed through existing position and risk controls. Add canonical policy snapshots, focused score-composition tests, same-seed Default compatibility, F3 source breakdowns (`difficulty`, `commander`, `final`), and only the smallest Guard policy hook if scoring alone cannot express the intended behavior.
