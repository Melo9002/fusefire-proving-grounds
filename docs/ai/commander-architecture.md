# Commander architecture and strategic decision-making

## Status

This document separates implemented commander behavior from future design. **Default**, **Cautious**, and **Aggressive** are implemented. Changing strategic intent and commander-directed action priorities remain proposed.

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

`AICommanderPolicy` is an immutable, typed doctrine object. `BattleController.get_commander_policy()` owns one selected policy instance per AI team:

- Player and Ally factions currently share team `0`, matching their existing `SquadContext` and non-hostile coordination.
- Enemy uses team `1`.
- Repeated requests during a battle return the same instance.
- Policies persist across round resets; `SquadContext` remains the round-scoped reservation store.
- Every battle starts with a fresh configured policy for each team; omitted configuration defaults to Default.

`AIController` asks the battle for its team's policy and composes it with `AIDifficultyPolicy`. Default copies every difficulty field exactly. Cautious and Aggressive apply their values once to the existing difficulty weights. The composed `_policy` is consumed by `AIPositionScorer`, `AITargetScorer`, and controller risk gates.

Decision records now contain:

- `commander_policy`: readable name (`Default`).
- `commander_policy_id`: stable identity (`default`).
- `strategic_intent`: readable current intent (`Balanced engagement`).

The F3 AI decision explanation displays policy, intent, and the base difficulty value, commander multiplier or delta, and final value for the movement controls that influenced the decision. Replay fingerprints and authoritative actions are unchanged; these fields are diagnostic evidence only.

## Implemented Cautious doctrine

| Policy field | Multiplier or delta | Reason |
| --- | ---: | --- |
| `position_cover_weight` | ×1.30 | Makes effective directional cover materially more valuable. |
| `position_exposure_weight` | ×1.30 | Strengthens penalties from hostile firing lanes. |
| `position_danger_weight` | ×1.35 | Gives crossfire and close-range danger the strongest increase. |
| `position_firing_weight` | ×0.90 | Slightly reduces pressure to take exposure merely to acquire a shot. |
| `movement_progress_weight` | ×0.95 | Trades a small amount of speed for safety without abandoning progress. |
| `crowding_penalty_weight` | ×1.15 | Strengthens existing squad spacing. |
| `survival_separation_weight` | ×1.10 | Values hostile separation more during survival movement. |
| `safe_advance_exposure_tolerance` | −0.10, clamped to 0 | Makes Easy less permissive and leaves already-near-zero Normal and Hard at zero. |

Target weights, lapse probability, lapse margin, and action priority are unchanged. `survival_cover_weight` remains inactive and unmodified. No Guard-specific hook exists.

The deterministic `ai_cautious_commander_smoke.gd` fixture places two hostiles near an actor and scores the same authoritative legal movement destinations under Normal+Default and Normal+Cautious. It requires an actual preference reversal where Default favors one progress/offense trade-off and Cautious favors the alternative with the better combined cover, exposure, and danger result. A separate Hard+Cautious Reach simulation verifies required objective movement and completion. These fixtures demonstrate the doctrine boundary; they are not broad balance evidence for future Battlefield Generation 2.0 layouts.

One paired exploratory measurement used authored Eliminate seed `23231`, Hard difficulty, identical 2v2 rosters, and both teams on the same doctrine. Default completed in defeat after 6 rounds and 58 decisions; Cautious completed in victory after 8 rounds and 61 decisions. Their first trace difference was Default choosing Move while Cautious chose the existing Guard fallback. This single seed confirms an observable downstream difference, not that Cautious is generally stronger or that it intentionally prefers Guard. A broader comparison should wait for representative Generation 2.0 maps.

## Implemented Aggressive doctrine

Aggressive accepts calculated risk to improve pressure, finishing opportunities, and objective progress. It composes these values once with difficulty:

| Control | Aggressive adjustment |
|---|---:|
| Movement progress | ×1.20 |
| Firing-position value | ×1.20 |
| Wounded-target value | ×1.15 |
| Finishing bonus | ×1.25 |
| Target threat | ×1.10 |
| Cover value | ×0.90 |
| Exposure penalty | ×0.85 |
| Danger/crossfire penalty | ×0.90 |
| Safe-second-advance exposure tolerance | +0.15 |

Crowding, survival separation, mission targeting, VIP targeting, allied focus, lapse probability, and lapse margin remain difficulty-owned and unchanged. Exposure and danger keep nonzero penalties, so offensive value does not erase survival constraints. `survival_cover_weight` remains inactive.

The deterministic `ai_aggressive_commander_smoke.gd` fixture compares identical authoritative legal movement cells under Default, Cautious, and Aggressive. It requires an actual preference reversal: Cautious selects the better-protected alternative while Aggressive selects the cell with greater progress or firing value. The same fixture verifies that Aggressive rejects the worst-protection destination, strengthens the score margin for a legal finishing attack, and completes a required Reach mission against Cautious.

One same-seed authored Eliminate comparison used seed `23231`, Hard difficulty, and identical 2v2 rosters. Default/Default completed in defeat after 6 rounds and 58 decisions; Cautious/Cautious completed in victory after 8 rounds and 61 decisions; Aggressive/Cautious completed in defeat after 5 rounds and 50 decisions. Aggressive/Cautious recorded 17 Moves, 3 Guards, 11 Aims, 16 Attacks, and 3 Reloads, while Cautious/Cautious also produced 5 Waits and 7 Guards. This is evidence of different deterministic traces and tempo on one controlled seed, not a power ranking or broad balance conclusion.

No action-ladder hook was necessary. Aggressive changes candidate rankings inside action categories the existing ladder already reaches. It does not make Move globally compete with Attack, change Guard priority, or submit actions outside the authoritative service.

## Difficulty and personality composition

Difficulty and commander personality answer different questions:

| Layer | Responsibility |
| --- | --- |
| Difficulty | Decision consistency, bounded lapse probability, and current competence weights |
| Commander doctrine | Risk preference, objective pressure, target/position values, and narrow action-policy preferences |
| Strategic intent | Battle-specific emphasis derived from mission and battlefield state |
| Action service | Legality, cost, resolution, transaction, and presentation ownership |

The implemented composition rules are:

1. Create the selected `AIDifficultyPolicy` exactly as today.
2. Apply commander multipliers once to named scoring components. Default multipliers are `1.0`.
3. Apply commander deltas once to named thresholds such as safe-advance tolerance and clamp according to that threshold's domain. Default deltas are `0.0`.
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

## Implemented and proposed profiles

The profile boundary now supports:

- **Default (implemented):** exact compatibility baseline.
- **Cautious (implemented):** changes movement scoring and the safe-second-advance threshold using the table above. Existing urgency and mission-route recovery remain responsible for necessary risk.
- **Aggressive (implemented):** strengthens progress, finishing, threat, and firing-position values while retaining exposure and danger penalties. It does not reorder the action ladder.

Default remains the compatibility baseline. Every future profile test should compare Default traces and outcomes before accepting behavior changes.

## Decision-ladder diagnostics

Current diagnostics accurately record selected actions, legal and rejected movement/target candidates, scoring components, thresholds, squad adjustments, commander identity, and intent. They do not yet record every branch in `_run_activation()`.

A later diagnostic should record one bounded entry per policy branch with these states:

- `selected`: this branch committed the action;
- `illegal`: an authoritative query rejected it;
- `rejected_by_policy`: legal input existed but a documented tactical gate declined it;
- `not_reached`: an earlier committed action ended this evaluation pass.

It must distinguish “no candidate existed” from “an action was queried and rejected.” Implement this alongside the first real commander profile, when the required ladder hooks are known. Instrumenting every asynchronous exit during the identity-only groundwork would create unnecessary behavioral risk.

## Future distributed command and individual autonomy

The current one-policy-per-team ownership is an initial assignment rule, not a required limit of the tactical architecture. A future unit could resolve commander influence from a squad leader, a faction commander, or no commander while continuing to use the same unit-level controller and authoritative action service.

Preserve these extension rules:

- Commander doctrine expresses what a leader values; it does not execute actions or replace a unit's tactical judgment.
- Command ownership may later be resolved per squad or per unit rather than only by faction team.
- Personal disposition and command compliance, if approved, should compose with commander influence at the policy boundary. They should not introduce separate action legality or battlefield mutation paths.
- Layered faction and squad command should contribute a small, deterministic set of named influences with an explicit precedence rule. Avoid running an independent planner at every layer.
- Leader defeat, succession, refusal, and last-order persistence require explicit battle-state and replay contracts before they affect gameplay.
- Units without an assigned commander must continue to function through the Default doctrine.

None of distributed command, personal doctrine, obedience, refusal, succession, or cascaded command is implemented. The current runtime still assigns one immutable policy to team `0` and one to team `1`. This section records an extension boundary so that future command authority can influence autonomous units without changing authoritative action execution.

## Determinism and replay

Commander policy IDs must be stable data, never Node instance IDs. Future mutable commander state needs canonical ordering and replay/fingerprint treatment before it affects ordinary missions. Policy evaluation must consume no combat RNG. Difficulty lapse RNG remains seeded and isolated as it is today.

Commander choice is stored independently for player/ally team `0` and enemy team `1` in `BattleConfiguration` and replay configuration. Recordings without these optional fields load both teams as Default. The replay envelope and action schema remain unchanged because commander selection does not change an action's serialized contract. Playback reconstructs the configured battle, then consumes its recorded authoritative actions with ordinary AI disabled.

Code and tests can configure a matchup without source changes:

```gdscript
var config := BattleConfiguration.new()
config.player_commander = AICommanderPolicy.Profile.CAUTIOUS
config.enemy_commander = AICommanderPolicy.Profile.DEFAULT
level.configure_battle(config)
```

`AIMatchSimulator` accepts the same `player_commander` and `enemy_commander` keys. Match Setup exposes independent **Player + Ally** and **Enemy** doctrine selectors in Settings. Both default to Default, and the battle briefing shows the selected matchup before deployment.

## Open decisions

- Whether future allies can own a distinct commander while remaining non-hostile to the player. Current ownership deliberately follows the shared player/ally team context.
- Which boundary may change strategic intent: phase start, round start, or specific mission events.
- Whether a later campaign layer should constrain commander selection instead of exposing every doctrine in custom Match Setup.
- Which commander state belongs in replay fingerprints once it can influence actions.

## Recommended next task

Run a broader three-doctrine comparison after Battlefield Generation 2.0 provides representative streets, interiors, alleys, and vertical routes. Use those measurements to tune values before considering dynamic strategic intent or any narrow action-ladder hook.
