# Commander Foundation 2.x validation and freeze

## Status

Commander Foundation 2.x is frozen on the implementation containing Default, Cautious, and Aggressive. A freeze means the policy boundary, team ownership, configuration, diagnostics, and replay identity are stable enough for Battlefield Generation 2.0. It does not claim that the doctrines are perfectly balanced on every map.

All three doctrines use the same ordered unit action policy and authoritative action services. Default preserves the prior behavior. Cautious changes protection and exposure preferences. Aggressive changes progress, firing-position, finishing, and calculated-risk preferences. Difficulty remains an independent competence policy.

## Final validation suite

`tests/commander_foundation_validation.gd` is a small deterministic matrix rather than a balance tournament. It covers:

| Layout | Mission | Team 0 | Team 1 |
| --- | --- | --- | --- |
| Authored | Eliminate | Default | Cautious |
| Generated cover | Reach | Cautious | Default |
| Generated cover | Terminal | Aggressive | Default |
| Generated refinery | Survive | Default | Aggressive |
| Generated refinery, seed `940059876` | Rescue | Cautious | Aggressive |
| Generated refinery, seed `940059876` | Rescue | Aggressive | Cautious |

The gate requires every match to initialize and terminate without a simulator stall, timeout, or round limit; to produce inspectable decision records; and to perform meaningful tactical or objective actions. Across the suite, every doctrine occupies both team assignments and at least five mission families run. A victory is not required for every doctrine because the matrix validates reliability and objective participation rather than ranking doctrine strength.

Seed `940059876` deliberately holds Rescue geometry constant while swapping Cautious and Aggressive. Both player-side doctrines rescue and extract the VIP. Their action traces and completion times differ, demonstrating that battlefield geometry can dominate the shared opportunity while doctrine changes how units evaluate and exploit it.

Existing focused fixtures remain the evidence for controlled scoring differences, Default compatibility, doctrine composition, match configuration, F3 diagnostics, deterministic replay, historical Default fallback, and bounded difficulty lapses. The Prototype 1 matrix remains the broader mission regression gate.

## Rescue completion contract

Rescue has two required objectives: acquire `RescueTarget`, then extract that VIP. Extracting the carrier records VIP extraction and completes `extract_rescue`. This does **not** immediately end the battle when friendly combatants remain deployed.

The implemented sequence is:

1. A legal Rescue action or movement consequence attaches the neutral VIP to a friendly carrier and completes `rescue`.
2. A legal Extract action removes the carrier and rescued VIP, records VIP progress, and completes `extract_rescue`.
3. `ObjectiveManager._evaluate_outcome_rules()` deliberately leaves the battle ongoing while `extracted_units < total_units`.
4. Remaining living Player and Ally combatants receive extraction intent and may evacuate. Friendly deaths reduce `total_units`, so defeated units do not make full evacuation impossible.
5. Victory occurs when every remaining required friendly has extracted, or when the player invokes the authoritative **Depart** command after the required VIP objective is secure.
6. Depart records the number of living units left behind, finishes with Victory, advances the authoritative revision, and is replayable.

This explains why AI-versus-AI Rescue battles can continue after the rescued VIP leaves. The current AI does not choose Depart; it continues the existing full-squad extraction policy. `tests/core_objectives_smoke.gd` verifies both continued evacuation and deliberate early departure.

Ordinary live battles have no fixed round limit. Therefore, a surviving unit that can neither reach extraction nor be defeated could theoretically prolong a completed Rescue indefinitely. Existing route urgency, carrier routing, defeat handling, simulator stall detection, focused congestion fixtures, and the validation matrices reduce this risk, but they do not constitute a proof for every future battlefield. Battlefield Generation 2.0 must preserve reachable extraction routes and should validate post-objective accessibility.

## Future post-objective strategic intent

Future commander logic may make an explicit decision after the required payload is safe:

- complete an orderly full-squad withdrawal;
- conduct a fighting withdrawal;
- depart immediately and leave remaining units behind;
- continue fighting for an authored retaliation, pursuit, or optional objective.

This is an extension point, not implemented Commander Foundation behavior. `ObjectiveManager` remains the authority for mission state and Depart eligibility. A future commander may recommend an intent, but units must still use legal tactical actions and Depart must remain an authoritative, recorded command. The decision must be deterministic and replay-configured if it affects battle continuation.

## Frozen boundaries

- One immutable commander policy is assigned to team 0 and one to team 1.
- Player and Ally currently share team 0 doctrine.
- Commander doctrine composes with difficulty exactly once.
- Doctrine influences scoring and narrow typed thresholds; it never changes legality or resolves actions.
- Match Setup defaults both teams to Default and allows explicit independent selection.
- The startup narrative logs `Player + Ally` and `Enemy` commander names beside difficulty and seed for reproducible playtest reports.
- Replay configuration stores both doctrine identities; older recordings default to Default.
- Dynamic strategic intent, distributed command, obedience, succession, Player Echo learning, and post-objective doctrine changes remain future work.
- Battlefield Generation 2.0 may provide richer tactical opportunities but should not rewrite this commander foundation without a demonstrated requirement.
