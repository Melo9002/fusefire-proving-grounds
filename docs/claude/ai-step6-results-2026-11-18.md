# AI step 6 results: score the actual proposed action — 2026-11-18

Design: [AI step 6 design](ai-step6-design-2026-11-18.md). Evidence level: automated (E2) plus three 48-match baseline reruns. No human playtest. Starting commit `e1d3e9d`.

## What changed

| Slice | Change | Behaviour |
| --- | --- | --- |
| **A** | `AIActionPlan` (a typed plan: steps, target, destination, AP and supply cost, value, risk) and `AIPlanEvaluator`. The existing direct-versus-Aim comparison moved into the evaluator; `_try_aim_for_attack` keeps its API and its trace keys. | **Identical.** 48 of 48 matches identical to a reference run on `main`, including explanatory text. |
| **B** | The finishing bonus is the exact probability that the shots the unit can afford kill the target (`AITargetScorer.kill_probability`), not a flat +20 whenever one hit would. Affordable shots come from the unit's real AP and ammo (`AIPlanEvaluator.affordable_attack_shots`). | **No action, target or outcome changed in 48 matches.** Scores and the explanation ("kill N%") did. The scorer is more correct; in these battles the old flat bonus never flipped a choice. |
| **D** | Shield valued as the damage it prevents. Shield only lowers damage taken (inside its arc a shot's chance drops by the capability's accuracy modifier and its damage is multiplied by its damage multiplier), so its value is the exact expected damage prevented, from the real combat rules. The facing that covers the most expected damage wins. The old rule (Shield only on exactly the last AP, facing the single highest-chance threat) is gone; the stance lasts only until the unit's next activation, so any unit with nothing productive left may use it. A floor of 2.0 expected HP keeps a useless stance from costing AP. | The standard baseline has no Shield-capable units: a 16-match sample was identical to slice C. Behaviour is shown by scenarios. |
| **C** | Move then Attack. With a legal shot and AP to spare, the unit compares the best shot sequence from where it stands with the best after one move (bounded to 12 candidate cells, the destination must pass the existing exposure check, at most once per activation, a clear margin required). The explanation says why it moved. | **Intended change.** See below. |

Roadmap items: *use predicted hit chance, damage, defenses and costs* (done by the shared queries and `evaluate_attack_from_cell`); *replace the fixed 25-HP finisher* (the HP threshold was already replaced on 2026-11-17; slice B removes the remaining flat bonus); *compare Aim then Attack or Move then Attack* (A and C); *preferences reflect what the unit can achieve with its remaining resources* (B and the AP/supply limits of every plan).

## Slice C effect on the baseline

48 matches, 3 sites x 8 missions x seeds 16 and 17, Normal, 3 v 3. Slice C against slice B:

- **Use:** 15 repositions in 13 of 48 matches.
- **Outcomes:** 39 Victories became 37 (two matches changed from Victory to Defeat: `freight_yard-RESCUE-16`, `freight_yard-SURVIVE-16`). Rounds 262 to 258 and decisions 3,426 to 3,367. Some matches got much shorter (`freight_yard-ELIMINATE-17` 8 to 4 rounds), one got longer (`fleet_station-PROTECT-16`, 6 to 12 rounds, still a Victory). No stalls, timeouts or round limits.
- **Cost:** total wall time 443.1 s to 450.0 s (+1.6%).

**Why outcomes are not the right measure.** The same AI plays both sides. Both Victory-to-Defeat matches were caused by an *enemy* unit repositioning to two 100% shots. Win rate cannot say whether the AI is better; shot quality can:

| | Mean hit chance | Expected damage per shot | Total expected damage | Aims |
| --- | --- | --- | --- | --- |
| Players and allies, before to after | 77.5% to 78.9% | 19.39 to 19.73 | +2.3% | 48 to 36 |
| Enemies, before to after | 77.2% to 82.0% | 19.30 to 20.49 | +5.9% | 57 to 39 |

Shots are better for both sides. Enemies gain more because mission-bound units (carriers, escorts and VIPs) do not reposition while free units do. Moving to a better cell now sometimes replaces Aim, hence fewer Aims.

**What this means for balance.** At Normal difficulty the enemy AI is somewhat stronger in open fights. That is a pacing question for step 10, not hidden here. Easy keeps its old behaviour: `AIDifficultyPolicy.plans_repositioning` is off for Easy (and on for Normal and Hard).

## Tests

- `tests/ai_plan_evaluator_test.gd` (34 checks): the plan record, the Aim comparison, resource limits as hard limits, purity (no state change, no combat roll), and the repositioning switch surviving commander composition for every tier and profile. A policy field left out of `AICommanderPolicy.compose` is silently dropped; the switch's test found that and now guards it.
- `tests/ai_target_value_test.gd` (22 checks): exact kill probabilities, the finishing bonus scaling with chance and affordable shots, affordable shots from AP and ammo.
- Shield plan (in `tests/ai_plan_evaluator_test.gd`, 46 checks in total): the value equals the prevented damage computed from the rules, the arc covers only the attackers it faces, covering more expected damage ranks higher, no plan without a Shield, AP, a shooter or with Shield disabled, and valuing the plan changes no state and draws no roll. Scenarios S10 and S10b: a unit stuck under fire takes a Shield and explains it; with no shooter it does not.
- Scenarios S9 to S9e in `tests/ai_decision_scenarios_test.gd` (108 checks in total): a poor edge-of-range shot gives way to one reposition and then fire; a good shot is kept; with one AP the unit shoots instead of moving; the same setup gives the same plan; Easy does not reposition.
- Behaviour check: `compare_step5.py`-style comparison of baseline JSONs (decisions, outcomes, final states), as in step 5.

## Failures found along the way

1. **Defective test:** two messages contained "50% finisher", which GDScript's `%` operator reads as a format code. Escaped.
2. **Own defect:** an untyped ternary in the controller failed to compile; typed.
3. **Visible explanation lost:** my first version published a movement preview whose generic reason suppressed the reposition's own reason. It now records the reposition with its plan.
4. **Easy was silently smarter:** the new policy field was not copied by `AICommanderPolicy.compose`, so Easy repositioned. Found by a scenario; fixed and now covered by a composition test.

## Limits

- Guard (overwatch) is not valued. It is exclusive with Shield (a stance restriction), but its worth depends on what the enemy does, which has no authoritative model; it stays rule-based after Shield.
- The Shield floor (2.0 expected HP) is a fixed noise floor; the baseline cannot tune it because it contains no Shield-capable units.
- Only the chosen target's turn considers repositioning, and at most once per activation. Escorts, carriers and VIPs never reposition.
- The baseline is one difficulty (Normal), two seeds per mission and site; it shows a direction, not a distribution.
- Planning cost was measured only as total wall time (+1.6%); the step 11 budget (bounded candidates, latency per decision) is still to do.
- Not play-tested by a person.
