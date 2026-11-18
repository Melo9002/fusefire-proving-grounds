# AI step 6 design: score the actual proposed action — 2026-11-18

Milestone 05 step 6 ([plan](../ai-2-plan.md)): *use predicted hit chance, damage, defenses and costs; replace the fixed 25-HP finishing threshold; compare short plans such as Aim then Attack or Move then Attack; preferences should reflect what the unit can actually achieve with its remaining resources.* Starting commit `e1d3e9d`. This document is a design and an audit; nothing in it is implemented yet.

## What the audit found is already done

| Roadmap item | State today | Where |
| --- | --- | --- |
| Use authoritative chance, damage, defenses | Done. Target scoring takes the shared Attack query's hit chance and on-hit damage (Shield and edited tuning included) and caps expected damage at the target's HP. | `AITargetScorer.evaluate` |
| Replace the fixed 25-HP finisher | Done in the 2026-11-17 repair batch. The finisher test is `current_hp <= damage` with the real on-hit damage. | `AITargetScorer`, [repairs](../quality/ai-repairs-2026-11-17.md) |
| Aim then Attack | Done, bounded to three AP: direct shots versus Aim plus shots, with real ammo, costs and per-shot chances, and kill probability. | `_try_aim_for_attack`, `shot_sequence_value` |

## What is still missing

1. **Move then Attack is never considered.** The activation is a fixed priority chain: if any legal shot exists the unit shoots (after the Aim comparison). A 15% shot from an exposed cell is taken even when one move reaches a cell with an 80% shot and AP to fire.
2. **Targets are ranked by a single shot.** A unit with three AP and ammo can deliver three shots, but a target that needs two hits scores no finisher bonus. Preferences do not reflect what the remaining AP and SP can achieve.
3. **The defensive choice is rule-based.** Shield is used only on exactly the last AP against a "credible" threat; Guard only if nothing low-value happened earlier. The expected prevented damage is never compared with the alternatives.
4. **Reload** is a threshold rule (empty, or nearly empty on the last AP). Because the activation loop re-plans after every action it already behaves close to optimally; it is not a priority.

## Design

A small typed record, `AIActionPlan`, and an evaluator, `AIPlanEvaluator`, owned by the existing AI code (no new service):

- `AIActionPlan`: ordered steps (`move`, `aim`, `reload`, `attack`), target, destination for a move, AP and supply cost, expected value (HP-capped expected damage plus kill probability, as `shot_sequence_value` computes it), a position risk term for a move, and a one-line explanation. `to_dictionary()` keeps the existing trace keys (`_last_attack_plan`), so F3 and the records do not change shape.
- Every chance and damage comes from the shared queries or the combat rules' `evaluate_attack_from_cell` / `evaluate_attack_after_move`, which already evaluate a hypothetical shooter cell. No combat code changes and no random draws.
- Resource limits are hard: a plan whose AP or supply cost exceeds what the unit has is not generated.

Delivered in slices, each measured on its own:

| Slice | Change | Expected effect on the 48-match baseline |
| --- | --- | --- |
| **A** | Introduce `AIActionPlan` and `AIPlanEvaluator`; move the existing direct-versus-Aim comparison into it. | **None.** Must be 48 of 48 identical (ignoring explanatory text). |
| **B** | Rank targets by the value of the best shot sequence the unit can afford (kill probability over its real shots), not a single shot. | Target choice changes only when a target is killable with several shots; recorded and explained. |
| **C** | Move then Attack: before shooting, compare the attack-now value with the best reposition-then-shoot plan over a bounded set of cells (at most 12, nearest to a firing lane). Reposition only if the plan beats attack-now by a stated margin, still leaves AP to fire, passes the existing exposure and reservation checks, and happens at most once per activation. | Some units move before firing; fewer low-odds shots. Judged with scenarios, not by sameness. |
| **D (if time)** | Compare Shield, Guard and Wait by expected prevented damage from the same shared evaluations. | Fewer pointless Guard/Wait turns; judged with scenarios. |

## How it will be checked

- Controlled scenarios for each plan (poor shot versus better tile, a two-hit kill, Aim versus Move, AP and ammo limits, a plan that must be refused for lack of AP), asserted as properties ("the chosen plan is no worse than the best legal alternative"), never one exact tile.
- Hard rules asserted in every scenario: nothing is rejected by the authoritative service, AP and ammo never go negative, plans never exceed resources, no random draws.
- The 48-match baseline rerun after each slice and compared by [the same method as step 5](ai-constraints-2026-11-18.md): A must be identical; B and C record their intended differences.
- Planning cost measured with `profile-ai` (the plan evaluation must stay bounded; the milestone's performance budget is step 11).
- Subsystem suites one at a time before each push.

## Not in scope

Named movement profiles (step 7), commitment expiry (step 8), mission roles (step 9), difficulty tuning (step 10). Lower difficulty tiers keep their bounded near-best lapses; plans do not change what a tier is allowed to see.

## Open questions I will settle with evidence while building

- The margin for repositioning (a fixed fraction of the attack-now value plus a small constant, or a policy field). It must avoid dithering between two cells.
- How a move's exposure is priced against its gain, using the position scorer's existing components rather than a new constant.
